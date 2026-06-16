;;; kuro-input-mode-ext.el --- Kill, yank, word ops, and word-case transforms  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Continuation of `kuro-input-mode'.  Loaded automatically at the end of
;; that file.  Contains: kill/yank commands and word-case transforms.
;; Minibuffer send, line-buffer editor, line-mode keymap builder, and public
;; mode-switch commands live in `kuro-input-mode-ext2'.
;;
;; Do not `(require \\='kuro-input-mode-ext)' directly; load
;; `kuro-input-mode' instead.

;;; Code:

(require 'kuro-config)
(require 'kuro-input-mode-macros)

;; Functions defined in kuro-input-mode.el (loaded before this file at runtime).
(declare-function kuro--line-mode-update-display "kuro-input-mode" ())
(declare-function kuro--line-clear-overlay        "kuro-input-mode" ())
(declare-function kuro--line-word-bounds-forward  "kuro-input-mode" ())
(declare-function kuro--schedule-immediate-render "kuro-input"      ())
(declare-function kuro--send-key                  "kuro-ffi"        (key))
(declare-function kuro--build-keymap              "kuro-input-keymap" ())

;; Buffer-local variables defined in kuro-input-mode.el.
(defvar kuro--line-yank-length)
(defvar kuro--line-history)
(defvar kuro--line-history-idx)
(defvar kuro--line-history-stash)
(defvar kuro--line-yank-last-arg-idx)
(defvar kuro--line-yank-last-arg-len)
(defvar kuro--input-mode)
;; Keymap variables forward-declared in kuro-input-mode.el.
(defvar kuro--keymap)
(defvar kuro--char-keymap)
(defvar kuro-mode-map)
;; Defcustom variables defined in kuro-input-mode.el.
(defvar kuro-line-completion-function)
(defvar kuro-line-abbrev-alist)


;;;; Line mode: kill and yank handlers

(defmacro kuro--def-line-kill-word (name skip-past skip-word beg end new-point docstring)
  "Define NAME as a directional word-kill command.
DOCSTRING becomes the generated command docstring.
SKIP-PAST skips non-word chars to the word boundary; SKIP-WORD skips the word.
BEG and END are the splice range; NEW-POINT is the cursor position after kill.
All position expressions are evaluated with `p' bound to `kuro--line-point'."
  `(defun ,name ()
     ,docstring
     (interactive)
     (let* ((p     kuro--line-point)
            (bound (,skip-word kuro--line-buffer
                               (,skip-past kuro--line-buffer p))))
       (kuro--with-line-edit-undo
        (kuro--line-splice ,beg ,end "" ,new-point)))))

(kuro--def-line-kill-word kuro--line-kill-word
  kuro--line-skip-non-word-fwd kuro--line-skip-word-fwd
  p bound p
  "Kill from `kuro--line-point' to the end of the next word.")

(kuro--def-line-kill-word kuro--line-backward-kill-word
  kuro--line-skip-non-word-bwd kuro--line-skip-word-bwd
  bound p bound
  "Kill from the start of the previous word to `kuro--line-point'.")

(defun kuro--line-delete-char ()
  "Delete the character at `kuro--line-point'."
  (interactive)
  (when (< kuro--line-point (length kuro--line-buffer))
    (kuro--with-line-edit-undo
     (kuro--line-splice kuro--line-point (1+ kuro--line-point) "" kuro--line-point))))

(defun kuro--line-kill-to-bol ()
  "Kill from the beginning of the line to `kuro--line-point'."
  (interactive)
  (kuro--with-line-edit-undo
   (kuro--line-splice 0 kuro--line-point "" 0)))

(defun kuro--line-transpose-chars ()
  "Transpose the character before point with the one at point.
At end of line, transposes the two characters before point."
  (interactive)
  (let* ((s kuro--line-buffer)
         (len (length s))
         (p (if (= kuro--line-point len)
                (max 0 (1- kuro--line-point))
              kuro--line-point)))
    (when (>= p 1)
      (kuro--with-line-edit-undo
       (kuro--line-splice (1- p) (1+ p)
                          (string (aref s p) (aref s (1- p)))
                          (min (1+ p) len))))))

(defun kuro--line-yank ()
  "Yank the most recent kill into the line buffer at `kuro--line-point'.
Sets `kuro--line-yank-length' so `kuro--line-yank-pop' can replace the region."
  (interactive)
  (if (null kill-ring)
      (message "Kuro: kill ring is empty")
    (let* ((text (current-kill 0))
           (p    kuro--line-point))
      (kuro--with-line-edit-undo
       (kuro--line-splice p p text (+ p (length text)))
       (setq kuro--line-yank-length (length text))))))

(defun kuro--line-yank-pop ()
  "Rotate the kill ring and replace the last yank in the line buffer.
Only meaningful immediately after `kuro--line-yank' or another
`kuro--line-yank-pop'.  Signals `user-error' if the previous command was
neither."
  (interactive)
  (unless (memq last-command '(kuro--line-yank kuro--line-yank-pop))
    (user-error "Kuro: yank-pop requires a previous yank"))
  (let* ((prev-len kuro--line-yank-length)
         (p        kuro--line-point)
         (start    (- p prev-len))
         (text     (current-kill 1 t)))
    (kuro--with-line-edit-undo
     (kuro--line-splice start p text (+ start (length text)))
     (setq kuro--line-yank-length (length text)))))

(defsubst kuro--line-last-word (s)
  "Return the last whitespace-delimited token in S, or nil if S has none.
Trailing whitespace is stripped before splitting so \"git commit \" → \"commit\"."
  (when (and s (string-match-p "[^[:space:]]" s))
    (car (last (split-string (string-trim-right s))))))

(defun kuro--line-yank-last-arg ()
  "Insert the last argument of a previous history entry at point.
First invocation: inserts the last whitespace-delimited word of the most
recent history entry.
Repeated invocations (when `last-command' is `kuro--line-yank-last-arg'):
  replace the previously inserted argument with the last word of the next
  older history entry.  Stops silently at the oldest entry.
State is reset whenever any other command runs."
  (interactive)
  (let* ((hist kuro--line-history)
         (hist-len (length hist)))
    (when (zerop hist-len)
      (user-error "Kuro: no history for yank-last-arg"))
    (if (eq last-command 'kuro--line-yank-last-arg)
        ;; Cycle: advance to next older entry (capped at oldest)
        (setq kuro--line-yank-last-arg-idx
              (min (1+ kuro--line-yank-last-arg-idx) (1- hist-len)))
      ;; First invocation: start at most recent entry
      (setq kuro--line-yank-last-arg-idx 0)
      (setq kuro--line-yank-last-arg-len 0))
    (let ((word (kuro--line-last-word
                 (nth kuro--line-yank-last-arg-idx hist))))
      (if (not word)
          (message "Kuro: no last argument in history entry %d"
                   (1+ kuro--line-yank-last-arg-idx))
        (kuro--line-undo-push)
        ;; Remove previously inserted arg when cycling
        (when (> kuro--line-yank-last-arg-len 0)
          (let ((prev-start (- kuro--line-point kuro--line-yank-last-arg-len)))
            (kuro--line-splice prev-start kuro--line-point "" prev-start)))
        ;; Insert new last-arg at point (display CPS tail)
        (kuro--with-line-edit
         (kuro--line-splice kuro--line-point kuro--line-point word
                            (+ kuro--line-point (length word)))
         (setq kuro--line-yank-last-arg-len (length word)))))))

(defun kuro--line-unix-word-rubout ()
  "Kill from `kuro--line-point' backward to the nearest whitespace.
Uses bash unix-word-rubout semantics: only space/tab delimit tokens, so
hyphenated words and dotted paths are killed as a single token.  Contrast
with `kuro--line-backward-kill-word', which stops at any non-word char."
  (interactive)
  (let* ((s     kuro--line-buffer)
         (p     kuro--line-point)
         (start p))
    (while (and (> start 0) (memq (aref s (1- start)) '(?\s ?\t)))
      (setq start (1- start)))
    (while (and (> start 0) (not (memq (aref s (1- start)) '(?\s ?\t))))
      (setq start (1- start)))
    (kuro--with-line-edit-undo
     (kuro--line-splice start p "" start))))


;;;; Line mode: word-case transforms

(defmacro kuro--def-line-word-case (name docstring &rest transform-body)
  "Define NAME as a word-case transform command.
DOCSTRING becomes the generated command docstring.
Uses `kuro--line-word-bounds-forward' to locate the target word.
TRANSFORM-BODY is spliced into the concat that builds the replacement word text;
it receives bindings for S (the line buffer), START, and END."
  `(defun ,name ()
     ,docstring
     (interactive)
     (let* ((bounds (kuro--line-word-bounds-forward))
            (start  (car bounds))
            (end    (cdr bounds))
            (s      kuro--line-buffer))
       (when (> end start)
         (kuro--with-line-edit-undo
          (kuro--line-splice start end (concat ,@transform-body) end))))))

(kuro--def-line-word-case kuro--line-upcase-word
  "Upcase the word from `kuro--line-point' forward."
  (upcase (substring s start end)))

(kuro--def-line-word-case kuro--line-downcase-word
  "Downcase the word from `kuro--line-point' forward."
  (downcase (substring s start end)))

(kuro--def-line-word-case kuro--line-capitalize-word
  "Capitalize the word from `kuro--line-point' forward."
  (upcase   (substring s start (1+ start)))
  (downcase (substring s (1+ start) end)))

(defun kuro--line-transpose-words ()
  "Transpose the word before `kuro--line-point' with the word after it.
Point advances to the end of the second word after transposition."
  (interactive)
  (let* ((s        kuro--line-buffer)
         (p        kuro--line-point)
         (w1-end   (kuro--line-skip-non-word-bwd s p))
         (w1-start (kuro--line-skip-word-bwd     s w1-end))
         (w2-start (kuro--line-skip-non-word-fwd s p))
         (w2-end   (kuro--line-skip-word-fwd     s w2-start)))
    (when (and (> w1-end w1-start) (> w2-end w2-start))
      (let ((between (substring s w1-end w2-start))
            (w1      (substring s w1-start w1-end))
            (w2      (substring s w2-start w2-end)))
        (kuro--with-line-edit-undo
         (kuro--line-splice w1-start w2-end
                            (concat w2 between w1)
                            (+ w1-start (length w2) (length between) (length w1))))))))


(require 'kuro-input-mode-ext2)

(provide 'kuro-input-mode-ext)
;;; kuro-input-mode-ext.el ends here
