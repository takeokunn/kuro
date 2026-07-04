;;; kuro-input-keymap-meta-macros.el --- Macros for kuro-input-keymap-meta.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Compile-time expansion helpers for Meta key bindings.

;;; Code:

(require 'kuro-input-macros)
(require 'kuro-input-keymap-data)

(defmacro kuro--define-meta-letter-bindings (map letters)
  "Expand LETTERS into direct Meta bindings on MAP.
LETTERS can be a literal list or a quoted `defconst' table of characters.
Each generated binding installs both the M-CHAR form and the ESC-prefixed
fallback that resolves to the same sender command."
  (let* ((letter-list (cond
                       ((symbolp letters) (symbol-value letters))
                       ((and (consp letters) (eq (car letters) 'quote))
                        (cadr letters))
                       (t letters)))
         (map-sym (make-symbol "map")))
    `(let ((,map-sym ,map))
       ,@(mapcar
          (lambda (char)
            `(let ((char ,char))
               (let ((command (lambda ()
                                (interactive)
                                (kuro--send-meta char))))
                 (define-key ,map-sym (kbd (format "M-%c" char)) command)
                 (define-key ,map-sym (vector ?\e char) command))))
          letter-list))))

(provide 'kuro-input-keymap-meta-macros)

;;; kuro-input-keymap-meta-macros.el ends here
