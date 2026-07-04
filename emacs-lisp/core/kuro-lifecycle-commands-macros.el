;;; kuro-lifecycle-commands-macros.el --- Macros for lifecycle commands  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:
;; Macro helpers for lifecycle command definitions.

;;; Code:

(defmacro kuro--def-control-key (name sequence doc)
  "Define an interactive command NAME that sends SEQUENCE to the terminal.
DOC is the docstring for the generated command."
  `(defun ,name () ,doc (interactive) (kuro--send-key ,sequence)))

(provide 'kuro-lifecycle-commands-macros)
;;; kuro-lifecycle-commands-macros.el ends here
