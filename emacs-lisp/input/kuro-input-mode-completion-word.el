;;; kuro-input-mode-completion-word.el --- Word completion for line mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Word completion and abbreviation expansion commands for Kuro line mode.

;;; Code:

(require 'kuro-input-mode-macros)
(require 'kuro-input-mode-completion-dispatch)
(require 'kuro-input-mode-completion-word-macros)

;; Buffer-local variables defined in kuro-input-mode.el (loaded before this file).
(defvar kuro--line-buffer)
(defvar kuro--line-point)
(defvar kuro-line-completion-function)
(defvar kuro-line-abbrev-alist)
(declare-function kuro--line-mode-update-display "kuro-input-mode-line-display" ())

(defsubst kuro--line-word-span-before-point ()
  "Return (START . END) for the space-delimited token immediately before point.
Both `kuro--line-complete-word' and `kuro--line-expand-abbrev' use this."
  (let* ((end kuro--line-point)
         (start end))
    (while (and (> start 0)
                (not (= (aref kuro--line-buffer (1- start)) ?\s)))
      (setq start (1- start)))
    (cons start end)))

(defun kuro--line-complete-word ()
  "TAB word completion via `kuro-line-completion-function' for the word at point."
  (kuro--line-with-word-span (word-start word-end prefix)
    (kuro--line-dispatch-completion-candidates
     (funcall kuro-line-completion-function prefix)
     "kuro: no completions for %S"
     prefix
     "completions"
     (lambda (candidate)
       (kuro--line-replace-range-with-undo word-start word-end candidate)))))

(defun kuro--line-expand-abbrev ()
  "Expand the word immediately before point using `kuro-line-abbrev-alist' (M-SPC).
Walks backward from point to find the start of the current word (stopping
at whitespace or buffer start), looks it up in the alist, and replaces it
with the expansion.  Point is set to the end of the expansion.  No-ops with
a message when no entry matches."
  (interactive)
  (kuro--line-with-word-span (start end word)
    (let ((expansion (cdr (assoc word kuro-line-abbrev-alist))))
      (if (null expansion)
          (message "kuro: no abbreviation for %S" word)
        (kuro--line-replace-range-with-undo start end expansion)))))

(provide 'kuro-input-mode-completion-word)
;;; kuro-input-mode-completion-word.el ends here
