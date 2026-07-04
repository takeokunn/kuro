;;; kuro-input-mode-line.el --- Line-mode editing helpers  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Line-mode accumulator and editing commands for Kuro.
;; Loaded automatically by `kuro-input-mode' before history/ext modules.

;;; Code:

(require 'kuro-config)
(require 'kuro-ffi)
(require 'cl-lib)
(require 'kuro-input-mode-line-display)
(require 'kuro-input-mode-macros)

(declare-function kuro--schedule-immediate-render "kuro-input-render" ())
(declare-function kuro--send-key "kuro-ffi" (key))
(declare-function kuro-line-minibuffer-send "kuro-input-mode-ext2-send" ())

;; Buffer-local variables defined in kuro-input-mode.el.
(defvar kuro--line-buffer)
(defvar kuro--line-overlay)
(defvar kuro--line-point)
(defvar kuro--line-history)
(defvar kuro--line-undo-stack)
(defvar kuro--input-mode)
;; Defcustom variables defined in kuro-input-mode.el.
(defvar kuro-line-history-max-length)
(defvar kuro-line-use-minibuffer)


;;;; Line mode: undo stack

(defun kuro--line-undo ()
  "Undo the last edit to the line buffer (C-/ or C-_).
Restores the most recent state from `kuro--line-undo-stack'.
No-ops with a message when the stack is empty."
  (interactive)
  (if (null kuro--line-undo-stack)
      (message "kuro: no further undo information")
    (let ((state (pop kuro--line-undo-stack)))
      (setq kuro--line-buffer (car state))
      (setq kuro--line-point  (cdr state))
      (kuro--line-mode-update-display))))


(defun kuro--line-word-bounds-forward ()
  "Return (START . END) for the word at or after `kuro--line-point'."
  (let* ((s   kuro--line-buffer)
         (beg (kuro--line-skip-non-word-fwd s kuro--line-point))
         (end (kuro--line-skip-word-fwd     s beg)))
    (cons beg end)))

;;;; Line mode: key handlers

(defun kuro--line-self-insert ()
  "Append `last-command-event' to the line buffer at `kuro--line-point'.
When `kuro-line-use-minibuffer' is non-nil, pre-fills the typed character
and immediately delegates to `kuro-line-minibuffer-send' for full IME
support (DDSKK, mozc); `input-method-function' then fires in the
minibuffer context where it operates correctly."
  (interactive)
  (when (characterp last-command-event)
    (if (bound-and-true-p kuro-line-use-minibuffer)
        (progn
          (kuro--line-undo-push)
          (kuro--line-splice kuro--line-point kuro--line-point
                             (string last-command-event) (1+ kuro--line-point))
          (kuro-line-minibuffer-send))
      (kuro--line-insert-with-undo kuro--line-point
                                   (string last-command-event)))))

(defun kuro--line-quoted-insert ()
  "Read the next key literally and insert it into the line buffer.
Mirrors readline / Emacs `quoted-insert': the following keystroke — or an
octal/hex/decimal code accepted by `read-quoted-char' — is inserted
verbatim at `kuro--line-point'.  This lets you embed control characters
such as a literal TAB, ESC, or carriage return into the line before it is
dispatched to the PTY on RET, without those keys triggering their normal
line-mode editing commands."
  (interactive)
  (let* ((ch (read-quoted-char "C-q-"))
         (s  (char-to-string ch)))
    (kuro--line-insert-with-undo kuro--line-point s)))

(defun kuro--line-delete ()
  "Remove the character before `kuro--line-point' (backspace in line mode)."
  (interactive)
  (when (> kuro--line-point 0)
    (kuro--line-delete-with-undo (1- kuro--line-point) kuro--line-point)))

(defun kuro--line-newline ()
  "Insert a literal newline into the line buffer without sending.
Lets you compose a multi-line command -- a for-loop, a heredoc body, a
pasted block -- entirely within line mode, then dispatch the whole thing to
the PTY at once with RET.  The embedded newlines are sent verbatim ahead of
the final carriage return, so the shell runs each line in sequence."
  (interactive)
  (kuro--line-insert-with-undo kuro--line-point "\n"))

(defun kuro--line-kill-line ()
  "Kill from `kuro--line-point' to end of line (C-k in line mode)."
  (interactive)
  (kuro--line-delete-with-undo kuro--line-point (length kuro--line-buffer)))

(defun kuro--line-commit ()
  "Send accumulated line buffer to the PTY followed by a carriage return.
Clears the overlay and the accumulator before dispatching so a failed
send does not leave stale visual state."
  (interactive)
  (let ((text kuro--line-buffer))
    (when (> (length text) 0)
      (push text kuro--line-history)
      (when (and kuro-line-history-max-length
                 (> (length kuro--line-history) kuro-line-history-max-length))
        (setq kuro--line-history
              (cl-subseq kuro--line-history 0 kuro-line-history-max-length))))
    (kuro--line-suspend-state)
    (kuro--send-key (concat text "\r"))
    (kuro--schedule-immediate-render)))

(defun kuro--line-abort ()
  "Cancel line-mode input without sending anything to the PTY."
  (interactive)
  (kuro--line-suspend-state)
  (message "kuro: line input cancelled"))

(provide 'kuro-input-mode-line)
;;; kuro-input-mode-line.el ends here
