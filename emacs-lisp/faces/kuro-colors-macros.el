;;; kuro-colors-macros.el --- Macros for ANSI color palette defcustoms  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Macro helpers for generating the ANSI color palette defcustoms.

;;; Code:

(defmacro kuro--defcolor (suffix default label index)
  "Define a `defcustom' for ANSI palette entry SUFFIX with DEFAULT hex value.
LABEL is the color name string; INDEX is the palette index integer."
  `(defcustom ,(intern (concat "kuro-color-" suffix)) ,default
     ,(concat "Color for ANSI " label " (palette index " (number-to-string index)
              ").\nValue must be a 6-digit hex string, e.g. #rrggbb.")
     :type '(string :tag "Hex color (#rrggbb)")
     :group 'kuro-colors
     :set #'kuro--set-color))

(provide 'kuro-colors-macros)

;;; kuro-colors-macros.el ends here
