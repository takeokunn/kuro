;;; kuro-input-mode-ext2-mode-macros.el --- Macros for line-mode commands  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Macro helpers for defining line-mode switch commands.

;;; Code:

(defmacro kuro--def-input-mode (name mode message &rest pre-apply)
  "Define NAME as a Kuro input-mode switch command.
MODE is the mode symbol to set.  MESSAGE is shown after switching.
PRE-APPLY forms run between the buffer reset and `kuro--apply-input-mode'."
  `(defun ,name ()
     ,(format "Switch the current Kuro buffer to %s mode." mode)
     (interactive)
     (kuro--with-kuro-mode
      (setq kuro--input-mode ',mode)
      (kuro--line-reset-state)
      ,@pre-apply
      (kuro--apply-input-mode)
      (message ,message))))

(provide 'kuro-input-mode-ext2-mode-macros)

;;; kuro-input-mode-ext2-mode-macros.el ends here
