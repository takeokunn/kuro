;;; kuro-lifecycle-macros.el --- Macro helpers for Kuro lifecycle  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Macro helpers extracted from `kuro-lifecycle.el'.

;;; Code:

(defvar kuro--session-setup-fns)

(defmacro kuro--clear-session-state ()
  "Reset buffer-local session identity after detach or error.
Sets `kuro--initialized' to nil and `kuro--session-id' to 0."
  `(setq kuro--initialized nil
         kuro--session-id  0))

(defmacro kuro--detach-and-clear-session-state (session-id)
  "Detach SESSION-ID and clear the current session state.
Swallow detach errors so cleanup can continue."
  `(condition-case nil
       (progn
         (kuro-core-detach ,session-id)
         (kuro--clear-session-state))
     (error
      (kuro--clear-session-state))))

(defmacro kuro--run-session-setup-fns ()
  "Run the fixed session setup sequence in order.
The ordered function list remains data in `kuro--session-setup-fns'."
  `(progn
     ,@(mapcar (lambda (fn) `(,fn)) kuro--session-setup-fns)))

(provide 'kuro-lifecycle-macros)

;;; kuro-lifecycle-macros.el ends here
