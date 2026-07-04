;;; kuro-faces-macros.el --- Macros for face remapping  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Macro helpers for face remapping and lifecycle management.

;;; Code:

(defmacro kuro--with-face-remap (cookie-var &rest remap-body)
  "Remove the face-remap cookie in COOKIE-VAR, then evaluate REMAP-BODY.
COOKIE-VAR is a symbol whose value holds the cookie returned by
`face-remap-add-relative', or nil when no remap is active.
The old cookie is removed and COOKIE-VAR set to nil before REMAP-BODY runs.
REMAP-BODY is typically a `setq' form that stores the new cookie back into
COOKIE-VAR.  When REMAP-BODY is empty the macro acts as a pure remove."
  (declare (indent 1))
  `(progn
     (when ,cookie-var
       (face-remap-remove-relative ,cookie-var)
       (setq ,cookie-var nil))
     ,@remap-body))

(provide 'kuro-faces-macros)

;;; kuro-faces-macros.el ends here
