;;; kuro-input-mode-completion.el --- Completion commands for line mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Completion and history-search commands for Kuro line mode.

;;; Code:

(require 'kuro-input-mode-completion-history)
(require 'kuro-input-mode-completion-word)

(defvar kuro-line-completion-function)

(declare-function kuro--line-complete-history-multi "kuro-input-mode-completion-history" ())
(declare-function kuro--line-complete-word "kuro-input-mode-completion-word" ())

(defun kuro--line-complete ()
  "Complete the token at point.
When `kuro-line-completion-function' is non-nil, complete the word at point
using that callback.  Otherwise complete the current line from history."
  (interactive)
  (if kuro-line-completion-function
      (kuro--line-complete-word)
    (kuro--line-complete-history-multi)))

(provide 'kuro-input-mode-completion)
;;; kuro-input-mode-completion.el ends here
