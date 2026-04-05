;;; kuro-compilation.el --- Compilation error navigation for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn
;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:
;; Integrates Emacs compilation-mode error parsing with Kuro terminal output.
;; When enabled, compiler errors and warnings in terminal output become
;; clickable overlays that jump to the source location.

;;; Code:

(require 'compile)

(defcustom kuro-compilation-navigation t
  "When non-nil, enable `compilation-shell-minor-mode' in Kuro buffers.
This makes compiler error messages clickable and navigable with
\\[next-error] and \\[previous-error]."
  :type 'boolean
  :group 'kuro)

(defun kuro--setup-compilation ()
  "Enable compilation error navigation in the current Kuro buffer.
Activates `compilation-shell-minor-mode' which parses terminal output
for error patterns and creates navigable overlays."
  (when kuro-compilation-navigation
    (compilation-shell-minor-mode 1)))

(defun kuro--teardown-compilation ()
  "Disable compilation error navigation in the current Kuro buffer."
  (when (bound-and-true-p compilation-shell-minor-mode)
    (compilation-shell-minor-mode -1)))

(provide 'kuro-compilation)
;;; kuro-compilation.el ends here
