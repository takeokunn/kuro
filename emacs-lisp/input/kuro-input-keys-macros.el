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

(provide 'kuro-input-keys-macros)

;;; kuro-input-keys-macros.el ends here
