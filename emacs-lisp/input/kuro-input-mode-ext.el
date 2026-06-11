;;; kuro-input-mode-ext.el --- Kill, yank, word ops, keymap, and public commands  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Continuation of `kuro-input-mode'.  Loaded automatically at the end of
;; that file.  Contains: kill/yank commands, word-case transforms, minibuffer
;; send, line-buffer editor, line-mode keymap builder, and public mode-switch
;; commands.
;;
;; Do not `(require \\='kuro-input-mode-ext)' directly; load
;; `kuro-input-mode' instead.

;;; Code:

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

(defun kuro--line-kill-word ()
  "Kill from `kuro--line-point' to the end of the next word (M-d)."
  (interactive)
  (let* ((p   kuro--line-point)
         (end (kuro--line-skip-word-fwd kuro--line-buffer
                 (kuro--line-skip-non-word-fwd kuro--line-buffer p))))
    (kuro--with-line-edit-undo
     (kuro--line-splice p end "" p))))

(defun kuro--line-backward-kill-word ()
  "Kill from the start of the previous word to `kuro--line-point' (M-DEL)."
  (interactive)
  (let* ((p     kuro--line-point)
         (start (kuro--line-skip-word-bwd kuro--line-buffer
                   (kuro--line-skip-non-word-bwd kuro--line-buffer p))))
    (kuro--with-line-edit-undo
     (kuro--line-splice start p "" start))))

(defun kuro--line-delete-char ()
  "Delete the character at `kuro--line-point' (C-d, forward delete)."
  (interactive)
  (when (< kuro--line-point (length kuro--line-buffer))
    (kuro--with-line-edit-undo
     (kuro--line-splice kuro--line-point (1+ kuro--line-point) "" kuro--line-point))))

(defun kuro--line-kill-to-bol ()
  "Kill from the beginning of the line to `kuro--line-point' (C-u)."
  (interactive)
  (kuro--with-line-edit-undo
   (kuro--line-splice 0 kuro--line-point "" 0)))

(defun kuro--line-transpose-chars ()
  "Transpose the character before point with the one at point (C-t).
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
  "Yank the most recent kill into the line buffer at `kuro--line-point' (C-y).
Sets `kuro--line-yank-length' so `kuro--line-yank-pop' can replace the region."
  (interactive)
  (if (null kill-ring)
      (message "kuro: kill ring is empty")
    (let* ((text (current-kill 0))
           (p    kuro--line-point))
      (kuro--with-line-edit-undo
       (kuro--line-splice p p text (+ p (length text)))
       (setq kuro--line-yank-length (length text))))))

(defun kuro--line-yank-pop ()
  "Rotate the kill ring and replace the last yank in the line buffer (M-y).
Only meaningful immediately after `kuro--line-yank' or another
`kuro--line-yank-pop'.  Signals `user-error' if the previous command was
neither."
  (interactive)
  (unless (memq last-command '(kuro--line-yank kuro--line-yank-pop))
    (user-error "kuro: yank-pop requires a previous yank"))
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
  "Insert the last argument of a previous history entry at point (M-., M-_).
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
      (user-error "kuro: no history for yank-last-arg"))
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
          (message "kuro: no last argument in history entry %d"
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
  "Kill from `kuro--line-point' backward to the nearest whitespace (C-w).
Uses bash unix-word-rubout semantics: only space/tab delimit tokens, so
hyphenated words and dotted paths are killed as a single token.  Contrast
with `kuro--line-backward-kill-word' (M-DEL) which stops at any non-word char."
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
  "Define a word-case transform command using `kuro--line-word-bounds-forward'.
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
  "Upcase the word from `kuro--line-point' forward (M-u)."
  (upcase (substring s start end)))

(kuro--def-line-word-case kuro--line-downcase-word
  "Downcase the word from `kuro--line-point' forward (M-l)."
  (downcase (substring s start end)))

(kuro--def-line-word-case kuro--line-capitalize-word
  "Capitalize the word from `kuro--line-point' forward (M-c)."
  (upcase   (substring s start (1+ start)))
  (downcase (substring s (1+ start) end)))

(defun kuro--line-transpose-words ()
  "Transpose the word before `kuro--line-point' with the word after it (M-t).
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


;;;; Line mode: minibuffer send

;;;###autoload
(defun kuro-line-minibuffer-send ()
  "Read a line via minibuffer and send it to the PTY.
Unlike the overlay accumulator, `read-from-minibuffer' fully supports
input methods (DDSKK, mozc, skk) because `input-method-function' fires
inside the minibuffer input loop before any keymap dispatch.  Command
history is accessible via \\[previous-history-element] /
\\[next-history-element].

The current `kuro--line-buffer' is used as the initial contents.
C-g cancels without sending; the line buffer is cleared in all cases
so no stale state accumulates.

Bound to \\[kuro-line-minibuffer-send] in line mode.  When
`kuro-line-use-minibuffer' is non-nil, every keypress auto-invokes this
function with the typed character pre-filled."
  (interactive)
  (unless (derived-mode-p 'kuro-mode)
    (user-error "Not in a Kuro terminal buffer"))
  (let ((initial kuro--line-buffer))
    (setq kuro--line-buffer "")
    (kuro--line-clear-overlay)
    (condition-case nil
        (let ((text (read-from-minibuffer "» " initial nil nil
                                          'kuro--line-history)))
          (kuro--send-key (concat text "\r"))
          (kuro--schedule-immediate-render))
      (quit nil))))


;;;; Line buffer editor — C-x C-e opens line buffer in a full Emacs text buffer

(defvar-local kuro--line-edit-source-buffer nil
  "The `kuro-mode' buffer this line-edit buffer was spawned from.
Set by `kuro--line-edit-in-buffer' in the edit buffer.")

(defvar-local kuro--line-edit-original nil
  "The value of `kuro--line-buffer' at the time the edit buffer was opened.
Used by `kuro-line-edit-discard' to restore the terminal buffer's line state.")

(defvar kuro--line-edit-keymap
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'kuro-line-edit-send)
    (define-key map (kbd "C-c C-k") #'kuro-line-edit-discard)
    map)
  "Keymap installed in buffers created by `kuro--line-edit-in-buffer'.")

;;;###autoload
(define-derived-mode kuro-line-edit-mode text-mode "Kuro-Line-Edit"
  "Major mode for editing the current line-mode command in a full Emacs buffer.
Created by `kuro--line-edit-in-buffer' (\\[kuro--line-edit-in-buffer] in line mode).

The buffer holds the current line-mode accumulator.  Use any Emacs editing
commands (`query-replace', M-x, abbrev expansion, company-mode, etc.) then:

\\[kuro-line-edit-send]    — send the buffer contents as a command to the PTY
\\[kuro-line-edit-discard] — discard and restore the original line buffer"
  (setq buffer-read-only nil)
  (use-local-map (make-composed-keymap kuro--line-edit-keymap
                                       (current-local-map))))

;;;###autoload
(defun kuro--line-edit-in-buffer ()
  "Open the current line-mode accumulator in a full Emacs text buffer (C-x C-e).
Creates a dedicated buffer named `*kuro-line-edit: <name>*' pre-filled with
the current `kuro--line-buffer'.  Full Emacs editing is available.

When done:
  \\[kuro-line-edit-send]    — send result as a command to the PTY (C-c C-c)
  \\[kuro-line-edit-discard] — restore original line buffer and close (C-c C-k)

Analogous to bash \\='s `edit-and-execute-command' (C-x C-e)."
  (interactive)
  (unless (derived-mode-p 'kuro-mode)
    (user-error "Not in a Kuro terminal buffer"))
  (let* ((source (current-buffer))
         (initial kuro--line-buffer)
         (edit-name (format "*kuro-line-edit: %s*" (buffer-name source)))
         (edit-buf (get-buffer-create edit-name)))
    (with-current-buffer edit-buf
      (kuro-line-edit-mode)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert initial)
        (goto-char (point-max)))
      (setq kuro--line-edit-source-buffer source)
      (setq kuro--line-edit-original initial))
    (setq kuro--line-buffer "")
    (setq kuro--line-point 0)
    (kuro--line-clear-overlay)
    (switch-to-buffer edit-buf)
    (message "Kuro line edit — C-c C-c: send to PTY, C-c C-k: discard")))

;;;###autoload
(defun kuro-line-edit-send ()
  "Send the line-edit buffer contents as a command to the source Kuro PTY.
The buffer text is sent with a trailing RET (as `kuro--line-commit' does)
and the edit buffer is killed.  Signals `user-error' when the source
Kuro buffer is no longer live."
  (interactive)
  (unless (derived-mode-p 'kuro-line-edit-mode)
    (user-error "Not in a Kuro line-edit buffer"))
  (let ((text   (buffer-string))
        (source kuro--line-edit-source-buffer))
    (unless (buffer-live-p source)
      (user-error "Source Kuro buffer no longer exists"))
    (kill-buffer (current-buffer))
    (with-current-buffer source
      (kuro--send-key (concat text "\r"))
      (kuro--schedule-immediate-render)
      (message "kuro: line-edit command sent to PTY"))))

;;;###autoload
(defun kuro-line-edit-discard ()
  "Discard the line-edit buffer and restore the original line accumulator."
  (interactive)
  (let ((original kuro--line-edit-original)
        (source   kuro--line-edit-source-buffer))
    (kill-buffer (current-buffer))
    (when (buffer-live-p source)
      (with-current-buffer source
        (kuro--line-set-buffer (or original ""))))
    (message "kuro: line-edit discarded")))


;;;; Line mode keymap

(defvar kuro--line-mode-keymap nil
  "Keymap active in Kuro line mode.
Inherits from `kuro--keymap' (semi-char) but overrides self-insert, RET,
DEL/backspace, C-k, and C-g to operate on the local line buffer instead
of forwarding to the PTY.")

(defconst kuro--line-mode-bindings
  '(;; commit / abort / newline
    ("C-m"     . kuro--line-commit)         ("C-j"     . kuro--line-commit)
    ("C-o"     . kuro--line-newline)        ("C-g"     . kuro--line-abort)
    ;; delete
    ("DEL"     . kuro--line-delete)         ("C-h"     . kuro--line-delete)
    ("C-k"     . kuro--line-kill-line)      ("C-d"     . kuro--line-delete-char)
    ("C-u"     . kuro--line-kill-to-bol)    ("C-w"     . kuro--line-unix-word-rubout)
    ;; movement
    ("C-a"     . kuro--line-beginning-of-line) ("C-e"  . kuro--line-end-of-line)
    ("C-f"     . kuro--line-forward-char)   ("C-b"     . kuro--line-backward-char)
    ("M-f"     . kuro--line-forward-word)   ("M-b"     . kuro--line-backward-word)
    ;; word operations
    ("M-d"     . kuro--line-kill-word)      ("M-DEL"   . kuro--line-backward-kill-word)
    ("M-u"     . kuro--line-upcase-word)    ("M-l"     . kuro--line-downcase-word)
    ("M-c"     . kuro--line-capitalize-word) ("M-t"    . kuro--line-transpose-words)
    ;; misc editing
    ("C-t"     . kuro--line-transpose-chars) ("C-q"   . kuro--line-quoted-insert)
    ("C-/"     . kuro--line-undo)           ("C-_"     . kuro--line-undo)
    ("C-y"     . kuro--line-yank)           ("M-y"     . kuro--line-yank-pop)
    ("M-."     . kuro--line-yank-last-arg)  ("M-_"     . kuro--line-yank-last-arg)
    ;; history navigation
    ("M-p"     . kuro--line-history-prev)   ("M-n"     . kuro--line-history-next)
    ("C-p"     . kuro--line-history-prev)   ("C-n"     . kuro--line-history-next)
    ("M-<"     . kuro--line-goto-history-oldest) ("M->" . kuro--line-goto-history-newest)
    ;; completion / search / abbrev
    ("TAB"     . kuro--line-complete)       ("M-/"     . kuro--line-complete-history)
    ("C-r"     . kuro--line-history-search) ("C-c C-r" . kuro-line-minibuffer-send)
    ("M-SPC"   . kuro--line-expand-abbrev)  ("C-x C-e" . kuro--line-edit-in-buffer))
  "Key→command binding table for `kuro--line-mode-keymap'.
Vector-keyed special bindings ([remap self-insert-command], [return],
[backspace]) are installed directly in `kuro--build-line-mode-keymap'.")

(defun kuro--build-line-mode-keymap ()
  "Build `kuro--line-mode-keymap' from `kuro--keymap'.
Must be called after `kuro--build-keymap' so the parent is up to date."
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map kuro--keymap)
    (define-key map [remap self-insert-command] #'kuro--line-self-insert)
    (define-key map [return]    #'kuro--line-commit)
    (define-key map [backspace] #'kuro--line-delete)
    (dolist (b kuro--line-mode-bindings)
      (define-key map (kbd (car b)) (cdr b)))
    (setq kuro--line-mode-keymap map)
    map))


;;;; Keymap application

(defun kuro--apply-input-mode ()
  "Update the current buffer's effective keymap for `kuro--input-mode'.
Sets `kuro-mode-map' parent to:
  `char'      → `kuro--char-keymap'  (all keys bound)
  `semi-char' → `kuro--keymap'       (exceptions removed)
  `line'      → `kuro--line-mode-keymap' as a composed local map
The mode-line is updated after every switch."
  (pcase kuro--input-mode
    ('char
     (set-keymap-parent kuro-mode-map kuro--char-keymap)
     (use-local-map kuro-mode-map))
    ('semi-char
     (set-keymap-parent kuro-mode-map kuro--keymap)
     (use-local-map kuro-mode-map))
    ('line
     (kuro--build-line-mode-keymap)
     ;; Compose: line-mode overrides on top, kuro-mode-map's C-c bindings below
     (use-local-map (make-composed-keymap kuro--line-mode-keymap kuro-mode-map))))
  (force-mode-line-update))


;;;; Public commands

(defmacro kuro--def-input-mode (name mode message &rest pre-apply)
  "Define a Kuro input-mode switch command.
MODE is the mode symbol to set.  MESSAGE is shown after switching.
PRE-APPLY forms run between the buffer reset and `kuro--apply-input-mode'."
  `(defun ,name ()
     ,(format "Switch the current Kuro buffer to %s mode." mode)
     (interactive)
     (unless (derived-mode-p 'kuro-mode)
       (user-error "Not in a Kuro buffer"))
     (setq kuro--input-mode ',mode
           kuro--line-buffer "")
     ,@pre-apply
     (kuro--apply-input-mode)
     (message ,message)))

;;;###autoload
(kuro--def-input-mode kuro-char-mode char
  "Kuro: char mode — all keys forwarded to PTY"
  (kuro--line-clear-overlay))

;;;###autoload
(kuro--def-input-mode kuro-semi-char-mode semi-char
  "Kuro: semi-char mode — exception keys pass through to Emacs"
  (kuro--line-clear-overlay))

;;;###autoload
(kuro--def-input-mode kuro-line-mode line
  "Kuro: line mode — type locally, RET sends, C-g cancels"
  (kuro--line-mode-update-display))

;;;###autoload
(defun kuro-cycle-input-mode ()
  "Cycle through Kuro input modes: semi-char → char → line → semi-char.
Provides a quick one-key way to switch without remembering three commands."
  (interactive)
  (unless (derived-mode-p 'kuro-mode)
    (user-error "Not in a Kuro buffer"))
  (pcase kuro--input-mode
    ('semi-char (kuro-char-mode))
    ('char      (kuro-line-mode))
    ('line      (kuro-semi-char-mode))
    (_          (kuro-semi-char-mode))))

(provide 'kuro-input-mode-ext)

;;; kuro-input-mode-ext.el ends here
