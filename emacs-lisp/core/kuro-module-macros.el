;;; kuro-module-macros.el --- Macros for kuro-module.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Tiny helper macro extracted from kuro-module.el.

;;; Code:

(defvar kuro-module--search-tiers)

(defmacro kuro--module-try (path-expr)
  "Return PATH-EXPR if it names an existing file, nil otherwise."
  `(let ((p ,path-expr))
     (when (and p (file-exists-p p)) p)))

(defmacro kuro--run-module-search-tiers ()
  "Run the fixed module search tiers in priority order.
The ordered tier list remains data in `kuro-module--search-tiers'."
  `(or ,@(mapcar (lambda (fn) `(,fn)) kuro-module--search-tiers)))

(provide 'kuro-module-macros)

;;; kuro-module-macros.el ends here
