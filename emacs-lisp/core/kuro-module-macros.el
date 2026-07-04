;;; kuro-module-macros.el --- Macros for kuro-module.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Tiny helper macro extracted from kuro-module.el.

;;; Code:

(defvar kuro-module--search-tiers)
(declare-function kuro-module--library-candidate-from-path
                  "kuro-module" (path &optional required source))

(defmacro kuro--module-try (path-expr)
  "Return a validated module library candidate for PATH-EXPR, or nil."
  `(let ((p ,path-expr))
     (and p (kuro-module--library-candidate-from-path
             p nil "module search tier"))))

(defmacro kuro--run-module-search-tiers ()
  "Run the fixed module search tiers in priority order.
The ordered tier list remains data in `kuro-module--search-tiers'."
  `(or ,@(mapcar (lambda (fn) `(,fn)) kuro-module--search-tiers)))

(provide 'kuro-module-macros)

;;; kuro-module-macros.el ends here
