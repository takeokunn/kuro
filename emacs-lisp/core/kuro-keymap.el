;;; kuro-keymap.el --- Shared keymap helpers for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Shared helpers for building sparse keymaps and binding alist-driven
;; key tables across Kuro's Emacs Lisp modules.

;;; Code:

(defun kuro--bind-key-alist (map alist key-fn command-fn)
  "Bind ALIST into MAP using KEY-FN and COMMAND-FN.
For each ALIST entry, KEY-FN computes the key event and COMMAND-FN
computes the command object.  Returns MAP."
  (dolist (binding alist map)
    (define-key map
      (funcall key-fn binding)
      (funcall command-fn binding))))

(defun kuro--bind-keys (map command &rest keys)
  "Bind KEYS in MAP to COMMAND."
  (dolist (key keys)
    (define-key map key command)))

(defun kuro--build-keymap-from-alist (bindings key-fn command-fn
                                               &optional parent)
  "Return a sparse keymap built from BINDINGS.
KEY-FN computes the key event for each binding.
COMMAND-FN computes the command object for each binding.
When PARENT is non-nil, use it as the parent keymap."
  (let ((map (make-sparse-keymap)))
    (when parent
      (set-keymap-parent map parent))
    (kuro--bind-key-alist map bindings key-fn command-fn)
    map))

(defmacro kuro--define-keymap (&rest bindings)
  "Build a sparse keymap from BINDINGS.
Each binding is (KEY . COMMAND)."
  `(let ((map (make-sparse-keymap)))
     ,@(mapcar (lambda (binding)
                 `(define-key map ,(car binding) #',(cdr binding)))
               bindings)
     map))

(provide 'kuro-keymap)

;;; kuro-keymap.el ends here
