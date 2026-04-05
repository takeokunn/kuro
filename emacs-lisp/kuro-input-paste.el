;;; kuro-input-paste.el --- Bracketed paste for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; Bracketed paste mode (DEC mode 2004) support for the Kuro terminal.
;;
;; When bracketed paste is active, yanked text is wrapped with
;; ESC[200~ / ESC[201~ escape sequences and sanitized to remove
;; ESC (0x1b) and C1 CSI (0x9b) bytes that could escape the paste
;; bracket and allow command injection.

;;; Code:

(require 'subr-x)
(require 'kuro-ffi)

;; Forward reference: kuro--schedule-immediate-render is defined in kuro-input.el.
(declare-function kuro--schedule-immediate-render "kuro-input" ())

;;; Bracketed Paste State

(kuro--defvar-permanent-local kuro--bracketed-paste-mode nil
  "Bracketed paste mode state from Rust (?2004); polled by render cycle.")

(kuro--defvar-permanent-local kuro--keyboard-flags 0
  "Cached Kitty keyboard protocol flags, polled by render cycle.
This is a bitmask integer:
  Bit 0 (1): Disambiguate escape codes
  Bit 1 (2): Report event types (press/repeat/release)
  Bit 2 (4): Report alternate keys
  Bit 3 (8): Report all keys as escape codes
  Bit 4 (16): Report associated text")


;;; Bracketed Paste Sequences

(defconst kuro--paste-open "\e[200~"
  "Opening sequence for bracketed paste mode (DEC mode 2004).")

(defconst kuro--paste-close "\e[201~"
  "Closing sequence for bracketed paste mode (DEC mode 2004).")


;;; Paste Functions

(defun kuro--sanitize-paste (text)
  "Sanitize TEXT before sending as bracketed paste.
Removes ESC (\\x1b) and C1 CSI (\\x9b) bytes to prevent bracketed paste
escape injection.  Both \\e[201~ (7-bit) and \\x9b201~ (8-bit C1 CSI) would
prematurely close the paste bracket and allow command injection."
  (thread-last text
    (replace-regexp-in-string "\x1b" "")
    (replace-regexp-in-string (regexp-quote (string #x9b)) "")))

(defun kuro--send-paste-or-raw (text)
  "Send TEXT to the PTY, bracketing it when `kuro--bracketed-paste-mode' is set.
In bracketed mode the text is sanitized and wrapped with `kuro--paste-open' /
`kuro--paste-close'.  In plain mode it is sent verbatim."
  (if kuro--bracketed-paste-mode
      (kuro--send-key (concat kuro--paste-open (kuro--sanitize-paste text) kuro--paste-close))
    (kuro--send-key text)))

(defun kuro--yank (&optional arg)
  "Yank from kill ring, wrapping with bracketed paste sequences when active."
  (interactive "P")
  (let* ((n (if (numberp arg) (1- arg) 0))
         (text (current-kill n)))
    (kuro--send-paste-or-raw text))
  (kuro--schedule-immediate-render))

(defun kuro--yank-pop (&optional arg)
  "Cycle kill ring and yank; wraps with bracketed paste sequences when active.
Like `yank-pop': signals an error if the previous command was not a yank."
  (interactive "p")
  (unless (memq last-command '(yank kuro--yank kuro--yank-pop))
    (user-error "Previous command was not a yank"))
  (let ((text (current-kill (or arg 1))))
    (kuro--send-paste-or-raw text)))

(provide 'kuro-input-paste)

;;; kuro-input-paste.el ends here
