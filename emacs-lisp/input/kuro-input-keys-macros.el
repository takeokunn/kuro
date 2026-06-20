;;; kuro-input-keys-macros.el --- Macro helpers for kuro-input-keys  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Code:

(defmacro kuro--def-key-sequence (name doc normal application &optional kkp-cp)
  "Define an interactive command NAME that sends a key sequence to the PTY.
NORMAL is sent in normal cursor mode; APPLICATION in application cursor mode.
When KKP-CP (a KKP codepoint integer) is provided and the REPORT_ALL_KEYS
flag is active, the canonical CSI KKP-CP ; 1 u form is sent instead.
DOC is the function docstring."
  (if kkp-cp
      `(defun ,name () ,doc
         (interactive)
         (kuro--send-kkp-functional ,kkp-cp ,normal ,application))
    `(defun ,name () ,doc
       (interactive)
       (kuro--send-key-sequence ,normal ,application))))

(defmacro kuro--def-shifted-fkey (name legacy-seq kkp-cp doc)
  "Define interactive shifted-function-key sender NAME.
With KKP all-escape (0x08) active, send the canonical CSI KKP-CP ; 2 u form
\(shift wire = shift-bit 1 + offset 1 = 2).  Otherwise send the xterm
LEGACY-SEQ string.  DOC is the function docstring."
  `(defun ,name () ,doc
     (interactive)
     (kuro--with-kkp-all-escape ,(format "\e[%d;2u" kkp-cp)
       (kuro--send-key ,legacy-seq)
       (kuro--schedule-immediate-render))))

(defmacro kuro--def-keypad-key (name normal-char application-seq doc)
  "Define interactive numeric-keypad sender NAME.
Sends NORMAL-CHAR in normal keypad mode (DECKPNM) or the SS3-prefixed
APPLICATION-SEQ in application keypad mode (DECKPAM), dispatched on
`kuro--app-keypad-mode'.  DOC is the function docstring."
  `(defun ,name () ,doc
     (interactive)
     (kuro--send-key (if kuro--app-keypad-mode ,application-seq ,normal-char))
     (kuro--schedule-immediate-render)))

(provide 'kuro-input-keys-macros)

;;; kuro-input-keys-macros.el ends here
