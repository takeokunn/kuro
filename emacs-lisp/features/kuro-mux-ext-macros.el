;;; kuro-mux-ext-macros.el --- Macros for kuro-mux-ext.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Macro helpers extracted from `kuro-mux-ext.el'.

;;; Code:

(defvar kuro-mux--lifecycle-hooks)

(defmacro kuro--install-mux-lifecycle-hooks ()
  "Install the fixed kuro-mux lifecycle hooks in order."
  `(progn
     ,@(mapcar (lambda (h) `(add-hook ',(car h) ',(cdr h)))
               kuro-mux--lifecycle-hooks)))

(defmacro kuro--uninstall-mux-lifecycle-hooks ()
  "Remove the fixed kuro-mux lifecycle hooks in order."
  `(progn
     ,@(mapcar (lambda (h) `(remove-hook ',(car h) ',(cdr h)))
               kuro-mux--lifecycle-hooks)))

(provide 'kuro-mux-ext-macros)

;;; kuro-mux-ext-macros.el ends here
