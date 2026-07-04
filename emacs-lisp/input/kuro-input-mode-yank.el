;;; kuro-input-mode-yank.el --- Yank-related line editing commands  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Yank-related line editing commands for `kuro-input-mode'.
;; Keep kill/delete and yank state separate so the extension files stay small.

;;; Code:

(require 'kuro-input-mode-macros)

;; Functions defined in kuro-input-mode-line.el and kuro-input-mode-macros.el.
(declare-function kuro--line-splice        "kuro-input-mode-buffer-macros" (from to replacement new-point))
(declare-function kuro--line-splice-with-undo "kuro-input-mode-buffer-macros" (from to replacement new-point))

;; Buffer-local variables defined in kuro-input-mode.el.
(defvar kuro--line-buffer)
(defvar kuro--line-point)
(defvar kuro--line-history)
(defvar kuro--line-yank-length)
(defvar kuro--line-yank-last-arg-idx)
(defvar kuro--line-yank-last-arg-len)

(defun kuro--line-yank ()
  "Yank the most recent kill into the line buffer at `kuro--line-point'.
Sets `kuro--line-yank-length' so `kuro--line-yank-pop' can replace the region."
  (interactive)
  (if (null kill-ring)
      (message "Kuro: kill ring is empty")
    (let* ((text (current-kill 0))
           (p    kuro--line-point))
      (kuro--line-insert-with-undo p text)
      (setq kuro--line-yank-length (length text)))))

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
    (kuro--line-replace-range-with-undo start p text)
    (setq kuro--line-yank-length (length text))))

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
        (setq kuro--line-yank-last-arg-idx
              (min (1+ kuro--line-yank-last-arg-idx) (1- hist-len)))
      (setq kuro--line-yank-last-arg-idx 0)
      (setq kuro--line-yank-last-arg-len 0))
    (let ((word (kuro--line-last-word
                 (nth kuro--line-yank-last-arg-idx hist))))
      (if (not word)
          (message "Kuro: no last argument in history entry %d"
                   (1+ kuro--line-yank-last-arg-idx))
        (kuro--with-line-edit-undo
         (when (> kuro--line-yank-last-arg-len 0)
           (let ((prev-start (- kuro--line-point kuro--line-yank-last-arg-len)))
             (kuro--line-splice prev-start kuro--line-point "" prev-start)))
         (kuro--line-splice kuro--line-point kuro--line-point word
                            (+ kuro--line-point (length word)))
         (setq kuro--line-yank-last-arg-len (length word)))))))

(provide 'kuro-input-mode-yank)
;;; kuro-input-mode-yank.el ends here
