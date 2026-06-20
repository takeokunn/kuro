;;; kuro-config-macros.el --- Macros for Kuro configuration  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Macro helpers for configuration validation and propagation.  The runtime
;; configuration module stays focused on data, setters, and defaults.

;;; Code:

(defmacro kuro--broadcast-to-buffers (fn &rest args)
  "When FN is bound, call (FN ARGS...) in every live kuro-mode buffer."
  `(when (fboundp ',fn)
     (dolist (buf (kuro--kuro-buffers))
       (with-current-buffer buf
         (,fn ,@args)))))

(defmacro kuro--in-all-buffers (&rest body)
  "Evaluate BODY with each live kuro buffer current."
  `(dolist (buf (kuro--kuro-buffers))
     (with-current-buffer buf
       ,@body)))

(defmacro kuro--with-mode (mode msg &rest body)
  "Execute BODY only when `derived-mode-p' MODE.
Signal user-error MSG otherwise."
  `(if (derived-mode-p ',mode)
       (progn ,@body)
     (user-error ,msg)))

(defmacro kuro--with-kuro-mode (&rest body)
  "Execute BODY only in an active kuro-mode buffer, signaling user-error otherwise."
  `(kuro--with-mode kuro-mode "Not in a kuro buffer" ,@body))

(defmacro kuro--check-positive-integer (var errors)
  "Push an error string onto ERRORS if VAR is not a positive integer."
  `(unless (kuro--positive-integer-p ,var)
     (push (kuro--positive-integer-error ',var ,var) ,errors)))

(defmacro kuro--check-positive-integer-symbol (var errors)
  "Push an error onto ERRORS if symbol VAR is not bound to a positive integer."
  `(let* ((sym ,var)
          (val (symbol-value sym)))
     (unless (kuro--positive-integer-p val)
       (push (kuro--positive-integer-error sym val) ,errors))))

(defmacro kuro--check-positive-integer-vars (vars errors)
  "Push validation errors onto ERRORS for every symbol in VARS."
  `(dolist (var ,vars)
     (kuro--check-positive-integer-symbol var ,errors)))

(defmacro kuro--check-optional-positive-integer-vars (vars errors)
  "Push validation errors onto ERRORS for non-nil symbols in VARS."
  `(dolist (var ,vars)
     (when (symbol-value var)
       (kuro--check-positive-integer-symbol var ,errors))))

(defmacro kuro--check-hex-color (var errors)
  "Push an error string onto ERRORS if VAR is not a 6-digit hex color string."
  `(let ((val (symbol-value ,var)))
     (unless (and (stringp val)
                  (string-match-p "^#[0-9a-fA-F]\\{6\\}$" val))
       (push (format "%s: must be a 6-digit hex string like #rrggbb, got: %s"
                     ,var val)
             ,errors))))

(defmacro kuro--def-positive-int-setter (name err-msg doc &rest body)
  "Define a defcustom :set handler NAME for a positive-integer setting.
ERR-MSG is the user-error format string (receives VALUE as %s argument).
DOC is the function docstring.
Validates VALUE, sets SYMBOL via `set-default', then evaluates BODY.
SYMBOL and VALUE are bound within BODY."
  (declare (indent 3) (doc-string 3))
  `(defun ,name (symbol value)
     ,doc
     (unless (kuro--positive-integer-p value)
       (user-error ,err-msg value))
     (set-default symbol value)
     ,@body))

(provide 'kuro-config-macros)

;;; kuro-config-macros.el ends here
