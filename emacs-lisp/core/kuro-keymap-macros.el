;;; kuro-keymap-macros.el --- Keymap macro helpers for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Macro helpers for building sparse keymaps and repeating key bindings.

;;; Code:

(defmacro kuro--define-key-bindings (map bindings key-fn command-fn)
  "Expand BINDINGS into direct `define-key' forms on MAP.
BINDINGS can be a literal alist or the name of a `defconst' table.
KEY-FN and COMMAND-FN are function designators evaluated at macro-expansion
time and applied to each binding."
  (let* ((binding-list (cond
                        ((symbolp bindings) (symbol-value bindings))
                        ((and (consp bindings) (eq (car bindings) 'quote))
                         (cadr bindings))
                        (t bindings)))
         (key-fn (eval key-fn))
         (command-fn (eval command-fn)))
    `(progn
       ,@(mapcar (lambda (binding)
                   (let ((command (funcall command-fn binding)))
                     `(define-key ,map ,(funcall key-fn binding)
                        ,(if (symbolp command) `#',command command))))
                 binding-list))))

(defmacro kuro--bind-keys (map command &rest keys)
  "Bind KEYS in MAP to COMMAND.
The macro expands to direct `define-key' calls so repeated bindings stay
declarative at the call site."
  (let ((map-sym (make-symbol "map"))
        (command-sym (make-symbol "command")))
    `(let ((,map-sym ,map)
           (,command-sym ,command))
       ,@(mapcar (lambda (key)
                   `(define-key ,map-sym ,key ,command-sym))
                 keys))))

(defmacro kuro--define-keymap (&rest bindings)
  "Build a sparse keymap from BINDINGS.
Each binding is (KEY . COMMAND)."
  `(let ((map (make-sparse-keymap)))
     ,@(mapcar (lambda (binding)
                 `(define-key map ,(car binding) #',(cdr binding)))
               bindings)
     map))

(defmacro kuro--define-keymap-with-parent (parent &rest bindings)
  "Build a sparse keymap from BINDINGS and set PARENT as its parent.
Each binding is (KEY . COMMAND)."
  `(let ((map (make-sparse-keymap)))
     (set-keymap-parent map ,parent)
     ,@(mapcar (lambda (binding)
                 `(define-key map ,(car binding) #',(cdr binding)))
               bindings)
     map))

(provide 'kuro-keymap-macros)

;;; kuro-keymap-macros.el ends here
