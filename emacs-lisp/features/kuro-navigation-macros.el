;;; kuro-navigation-macros.el --- Macro helpers for kuro-navigation  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Compile-time helpers shared by kuro-navigation commands.
;; Keeping them separate makes the load order explicit and keeps the
;; runtime navigation file focused on prompt/history logic.

;;; Code:

(defmacro kuro--def-navigator (name type-pred on-found on-miss docstring)
  "Define NAME as a directional navigator over `kuro--prompt-positions'.
DOCSTRING becomes the generated function docstring.
TYPE-PRED filters entries.  ON-FOUND runs with `target' bound to the entry,
ON-MISS runs with `direction' still in scope when no match is found."
  `(defun ,name (direction)
     ,docstring
     (let ((target (kuro--find-mark-in-direction direction ,type-pred)))
       (if target
           ,on-found
         ,on-miss))))

(defmacro kuro--def-nav-cmd (name nav-fn direction docstring)
  "Define NAME as an interactive navigation command.
DOCSTRING becomes the generated command docstring.
Calls NAV-FN with DIRECTION (a quoted symbol) on invocation."
  `(defun ,name () ,docstring (interactive) (,nav-fn ',direction)))

(defmacro kuro--with-focus-guard (&rest body)
  "Execute BODY only when in an active kuro buffer with focus-events enabled."
  `(when (and (derived-mode-p 'kuro-mode)
              kuro--initialized
              (kuro--get-focus-events))
     ,@body))

(defmacro kuro--def-focus-handler (name sequence doc)
  "Define a focus event handler NAME that sends SEQUENCE.
DOC is the docstring for the generated handler function."
  `(defun ,name ()
     ,doc
     (kuro--with-focus-guard
      (kuro--send-key ,sequence))))

(provide 'kuro-navigation-macros)

;;; kuro-navigation-macros.el ends here
