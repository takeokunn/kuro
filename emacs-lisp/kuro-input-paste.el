;;; kuro-input-paste.el --- Bracketed paste for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:
;; Bracketed paste mode support (mode 2004) with security sanitization.

;;; Code:

(require 'kuro-ffi)

;; Forward reference: kuro--schedule-immediate-render is defined in kuro-input.el.
(declare-function kuro--schedule-immediate-render "kuro-input" ())

;;; Bracketed Paste State

(defvar-local kuro--bracketed-paste-mode nil
  "Cached bracketed paste mode state from Rust (?2004), polled by render cycle.")
(put 'kuro--bracketed-paste-mode 'permanent-local t)

(defvar-local kuro--keyboard-flags 0
  "Cached Kitty keyboard protocol flags, polled by render cycle.
This is a bitmask integer:
  Bit 0 (1): Disambiguate escape codes
  Bit 1 (2): Report event types (press/repeat/release)
  Bit 2 (4): Report alternate keys
  Bit 3 (8): Report all keys as escape codes
  Bit 4 (16): Report associated text")
(put 'kuro--keyboard-flags 'permanent-local t)


;;; Paste Functions

(defun kuro--sanitize-paste (text)
  "Sanitize TEXT before sending as bracketed paste.
Removes all ESC (\\x1b) bytes to prevent bracketed paste escape injection,
where clipboard content containing \\e[201~ could prematurely close the
paste bracket and cause command injection."
  (replace-regexp-in-string "\x1b" "" text))

(defun kuro--yank (&optional arg)
  "Yank from kill ring, wrapping with bracketed paste sequences when active."
  (interactive "*P")
  (let* ((n (if (numberp arg) (1- arg) 0))
         (text (current-kill n)))
    (if kuro--bracketed-paste-mode
        (kuro--send-key (concat "\e[200~" (kuro--sanitize-paste text) "\e[201~"))
      (kuro--send-key text)))
  (kuro--schedule-immediate-render))

(defun kuro--yank-pop (&optional arg)
  "Cycle kill ring and yank, wrapping with bracketed paste sequences when active.
Like `yank-pop', signals an error if the previous command was not a yank."
  (interactive "p")
  (unless (memq last-command '(yank kuro--yank kuro--yank-pop))
    (user-error "Previous command was not a yank"))
  (let ((text (current-kill (or arg 1))))
    (if kuro--bracketed-paste-mode
        (kuro--send-key (concat "\e[200~" (kuro--sanitize-paste text) "\e[201~"))
      (kuro--send-key text))))

(provide 'kuro-input-paste)

;;; kuro-input-paste.el ends here
