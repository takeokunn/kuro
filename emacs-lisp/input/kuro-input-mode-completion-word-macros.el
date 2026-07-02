;;; kuro-input-mode-completion-word-macros.el --- Macros for line word completion  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:
;; Macro helpers for completion-word mode.

;;; Code:

(require 'kuro-input-mode-macros)

(defmacro kuro--line-with-word-span (vars &rest body)
  "Bind VARS to the word span before point, then run BODY.
VARS must be (START-VAR END-VAR WORD-VAR)."
  (declare (indent defun))
  (let ((start-var (nth 0 vars))
        (end-var (nth 1 vars))
        (word-var (nth 2 vars))
        (span (make-symbol "span")))
    `(let* ((,span (kuro--line-word-span-before-point))
            (,start-var (car ,span))
            (,end-var (cdr ,span))
            (,word-var (substring kuro--line-buffer ,start-var ,end-var)))
       ,@body)))

(provide 'kuro-input-mode-completion-word-macros)
;;; kuro-input-mode-completion-word-macros.el ends here
