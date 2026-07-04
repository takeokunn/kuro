;;; kuro-input-paste.el --- Bracketed paste for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Bracketed paste mode (DEC mode 2004) support for the Kuro terminal.
;;
;; Paste delivery is delegated to Rust.  The core checks the current DEC 2004
;; mode in the same session operation that writes to the PTY, avoiding decisions
;; based on the render cycle's cached mode snapshot.

;;; Code:

(require 'kuro-ffi)

;; Forward reference: kuro--schedule-immediate-render is defined in kuro-input.el.
(declare-function kuro--schedule-immediate-render "kuro-input-render" ())

;;; Bracketed Paste State

(kuro--defvar-permanent-local kuro--bracketed-paste-mode nil
  "Bracketed paste mode state from Rust (?2004); observational cache only.")

(kuro--defvar-permanent-local kuro--keyboard-flags 0
  "Cached Kitty keyboard protocol flags, polled by render cycle.
This is a bitmask integer:
  Bit 0 (1): Disambiguate escape codes
  Bit 1 (2): Report event types (press/repeat/release)
  Bit 2 (4): Report alternate keys
  Bit 3 (8): Report all keys as escape codes
  Bit 4 (16): Report associated text")


;;; Paste Functions

(defun kuro--paste-prefix-numeric-value (arg default)
  "Return numeric prefix value for ARG, using DEFAULT when ARG is nil."
  (cond
   ((null arg) default)
   ((or (integerp arg)
        (eq arg '-)
        (and (consp arg)
             (integerp (car arg))
             (null (cdr arg))))
    (prefix-numeric-value arg))
   (t
    (signal 'wrong-type-argument
            (list 'kuro--paste-prefix-argument-p arg)))))

(defun kuro--paste-yank-index (arg)
  "Return the zero-based `kill-ring' index for `kuro--yank' ARG."
  (let ((value (kuro--paste-prefix-numeric-value arg 1)))
    (unless (> value 0)
      (user-error "Yank argument must be a positive integer"))
    (1- value)))

(defun kuro--paste-yank-pop-index (arg)
  "Return the `kill-ring' rotation count for `kuro--yank-pop' ARG."
  (kuro--paste-prefix-numeric-value arg 1))

(defun kuro--send-paste-or-raw (text)
  "Send TEXT to the PTY through the Rust paste API.
Rust decides between raw and bracketed paste from the session's current DEC 2004
state; this function must not use `kuro--bracketed-paste-mode' for safety."
  (unless (stringp text)
    (signal 'wrong-type-argument (list 'stringp text)))
  (kuro--send-paste text))

(defun kuro--yank (&optional arg)
  "Yank from kill ring through the Rust paste API.
Optional ARG selects which kill ring entry to use."
  (interactive "P")
  (let* ((n (kuro--paste-yank-index arg))
         (text (current-kill n)))
    (kuro--send-paste-or-raw text))
  (kuro--schedule-immediate-render))

(defun kuro--yank-pop (&optional arg)
  "Cycle kill ring and yank ARG entries forward.
Paste encoding is delegated to Rust at send time.
Like `yank-pop': signals an error if the previous command was not a yank."
  (interactive "p")
  (unless (memq last-command '(yank kuro--yank kuro--yank-pop))
    (user-error "Previous command was not a yank"))
  (let ((text (current-kill (kuro--paste-yank-pop-index arg))))
    (kuro--send-paste-or-raw text))
  (kuro--schedule-immediate-render))

(provide 'kuro-input-paste)

;;; kuro-input-paste.el ends here
