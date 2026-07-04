;;; kuro-input-macros.el --- Input macros -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Macro helpers for `kuro-input.el'.

;;; Code:

(defmacro kuro--def-special-key (name byte doc)
  "Define an interactive command NAME that sends special-key BYTE to the PTY.
DOC is the function docstring."
  `(defun ,name () ,doc
     (interactive)
     (kuro--send-special ,byte)))

(defmacro kuro--def-kkp-key (name kkp-seq legacy-char doc)
  "Define interactive KKP-aware key command NAME.
With KKP REPORT_ALL_KEYS flag (0x08), sends KKP-SEQ string via `kuro--send-key'.
Otherwise sends LEGACY-CHAR byte via `kuro--send-special'.
DOC is the docstring for the generated command."
  `(defun ,name ()
     ,doc
     (interactive)
     (if (not (zerop (logand kuro--keyboard-flags #x08)))
         (kuro--send-key ,kkp-seq)
       (kuro--send-special ,legacy-char))))

(defmacro kuro--def-key-sender (name encoder-form arg doc)
  "Define function NAME that encodes ARG via ENCODER-FORM and sends it.
The generated function calls `kuro--send-key' with the result of
ENCODER-FORM (which may reference ARG), then schedules an immediate render.
DOC is the docstring for the generated function."
  `(defun ,name (,arg) ,doc
     (kuro--send-key ,encoder-form)
     (kuro--schedule-immediate-render)))

(defmacro kuro--with-kkp-all-escape (sequence-form &rest legacy-body)
  "Send SEQUENCE-FORM when KKP all-escape is active, otherwise LEGACY-BODY.
The KKP branch always schedules an immediate render after sending."
  `(if (kuro--kkp-flag-p kuro--kkp-all-escape)
       (progn
         (kuro--send-key ,sequence-form)
         (kuro--schedule-immediate-render))
     (progn ,@legacy-body)))

(defmacro kuro--with-kkp-disambiguate (kkp-form legacy-form)
  "Evaluate KKP-FORM when KKP disambiguate is active, otherwise LEGACY-FORM."
  `(if (kuro--kkp-flag-p kuro--kkp-disambiguate)
       ,kkp-form
     ,legacy-form))

(provide 'kuro-input-macros)

;;; kuro-input-macros.el ends here
