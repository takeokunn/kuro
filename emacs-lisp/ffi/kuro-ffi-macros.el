;;; kuro-ffi-macros.el --- FFI macro helpers for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Macro helpers for the FFI wrapper layer.  The runtime functions remain in
;; `kuro-ffi.el', which requires this file before expanding any macro use.

;;; Code:

(defmacro kuro--when-divisible (counter divisor &rest body)
  "Execute BODY when COUNTER is divisible by DIVISOR (counter mod divisor = 0).
This is the fundamental cadence-gating primitive used for periodic polling and
animation timing: BODY is a continuation invoked at exact multiples of DIVISOR.
`%' is used instead of `mod': both are identical for non-negative COUNTER
\(frame counter is always ≥ 0), but `%' avoids the sign-normalization branch
inside `mod'."
  (declare (indent 2))
  `(when (zerop (% ,counter ,divisor))
     ,@body))

(defmacro kuro--defvar-permanent-local (name value &optional doc)
  "Define NAME as a buffer-local variable with VALUE, marked permanent-local.
Convenience macro for the common pattern:
  (defvar-local NAME VALUE DOC)
  (put \\='NAME \\='permanent-local t)

Variables marked permanent-local survive `kill-all-local-variables', which is
called when a major mode is activated.  This is required for all Kuro state
variables so that mode re-activation (e.g., after a theme change) does not
destroy in-progress terminal session state."
  (declare (doc-string 3) (indent defun))
  `(progn
     (defvar-local ,name ,value ,doc)
     (put ',name 'permanent-local t)))

(defmacro kuro--def-ffi-getter (name core-fn default doc)
  "Define a zero-argument FFI getter function NAME.
CORE-FN is called with `kuro--session-id'; DEFAULT is returned on error.
DOC is the docstring for the generated function."
  `(defun ,name () ,doc (kuro--call ,default (,core-fn kuro--session-id))))

(defmacro kuro--def-ffi-unary (name core-fn default arg doc)
  "Define NAME as a one-argument FFI wrapper with fallback DEFAULT.
CORE-FN is the underlying Rust function called with session-id and ARG.
DOC is the docstring for the generated function."
  `(defun ,name (,arg) ,doc (kuro--call ,default (,core-fn kuro--session-id ,arg))))

(defmacro kuro--def-ffi-binary (name core-fn default arg1 arg2 doc)
  "Define NAME as a two-argument FFI wrapper with fallback DEFAULT.
CORE-FN is the underlying Rust function called with session-id, ARG1, and ARG2.
DOC is the docstring for the generated function."
  `(defun ,name (,arg1 ,arg2) ,doc
          (kuro--call ,default (,core-fn kuro--session-id ,arg1 ,arg2))))

(defmacro kuro--define-ffi-binary-getters (&rest entries)
  "Expand ENTRIES into top-level `kuro--def-ffi-binary' forms.
Each entry has the form (NAME CORE-FN DEFAULT ARG1 ARG2 DOC)."
  (declare (indent 0))
  `(progn
     ,@(mapcar (lambda (entry)
                 `(kuro--def-ffi-binary
                   ,(nth 0 entry)
                   ,(nth 1 entry)
                   ,(nth 2 entry)
                   ,(nth 3 entry)
                   ,(nth 4 entry)
                   ,(nth 5 entry)))
               entries)))

(defmacro kuro--define-ffi-getters (&rest entries)
  "Expand ENTRIES into top-level `kuro--def-ffi-getter' forms.
Each entry has the form (NAME CORE-FN DEFAULT DOC)."
  (declare (indent 0))
  `(progn
     ,@(mapcar (lambda (entry)
                 `(kuro--def-ffi-getter
                   ,(nth 0 entry)
                   ,(nth 1 entry)
                   ,(nth 2 entry)
                   ,(nth 3 entry)))
               entries)))

(defmacro kuro--define-ffi-unary-getters (&rest entries)
  "Expand ENTRIES into top-level `kuro--def-ffi-unary' forms.
Each entry has the form (NAME CORE-FN DEFAULT ARG DOC)."
  (declare (indent 0))
  `(progn
     ,@(mapcar (lambda (entry)
                 `(kuro--def-ffi-unary
                   ,(nth 0 entry)
                   ,(nth 1 entry)
                   ,(nth 2 entry)
                   ,(nth 3 entry)
                   ,(nth 4 entry)))
               entries)))

(defmacro kuro--call (fallback &rest body)
  "Guard a Rust FFI call with initialization check and error recovery.

Evaluates BODY only when `kuro--initialized' is non-nil.
On error, logs a message and returns FALLBACK.

Usage:
  (kuro--call nil (kuro-core-get-cursor kuro--session-id))
  (kuro--call 0   (kuro-core-get-scroll-offset kuro--session-id))"
  (declare (indent 1))
  `(when kuro--initialized
     (condition-case err
         (progn ,@body)
       (error
        (when kuro-log-errors (kuro--log err))
        ,fallback))))

(provide 'kuro-ffi-macros)

;;; kuro-ffi-macros.el ends here
