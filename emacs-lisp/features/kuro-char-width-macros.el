;;; kuro-char-width-macros.el --- Macro helpers for Kuro char width  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Macro helpers extracted from `kuro-char-width.el'.

;;; Code:

(defmacro kuro--set-fontset-font-both (range spec)
  "Register SPEC for RANGE in both the current frame and the default fontset.
Both nil (current frame) and t (default template) are updated because
frame creation copies the default fontset - modifying only t would not
update existing frames, and modifying only nil would not affect new frames."
  `(progn
     (set-fontset-font nil ,range ,spec nil 'prepend)
     (set-fontset-font t   ,range ,spec nil 'prepend)))

(provide 'kuro-char-width-macros)

;;; kuro-char-width-macros.el ends here
