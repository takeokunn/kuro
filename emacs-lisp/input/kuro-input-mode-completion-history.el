;;; kuro-input-mode-completion-history.el --- History completion for line mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; History-prefix completion and history search commands for Kuro line mode.

;;; Code:

(require 'kuro-input-mode-macros)
(require 'kuro-input-mode-completion-dispatch)

;; Buffer-local variables defined in kuro-input-mode.el (loaded before this file).
(defvar kuro--line-buffer)
(defvar kuro--line-point)
(defvar kuro--line-history)

(defun kuro--line-all-history-completions (prefix)
  "Return all deduplicated history entries that start with PREFIX.
Entries exactly equal to PREFIX are excluded (they are already the input).
Preserves history order (most-recent first)."
  (let ((seen (make-hash-table :test 'equal))
        results)
    (dolist (entry kuro--line-history)
      (when (and (string-prefix-p prefix entry)
                 (not (gethash entry seen))
                 (not (string= prefix entry)))
        (puthash entry t seen)
        (push entry results)))
    (nreverse results)))

(defun kuro--line-complete-history ()
  "Complete `kuro--line-buffer' using the most recent matching history entry.
Uses the current buffer content as a prefix and replaces it with the most
recent `kuro--line-history' entry that starts with (but is not equal to)
that prefix.  No-ops with a message when no entry matches."
  (interactive)
  (let* ((prefix kuro--line-buffer)
         (match (car (kuro--line-all-history-completions prefix))))
    (if match
        (kuro--line-replace-buffer-with-undo match)
      (message "kuro: no history completion for %S" prefix))))

(defun kuro--line-complete-history-multi ()
  "TAB history completion: match full buffer prefix against all history entries."
  (let* ((prefix     (substring kuro--line-buffer 0 kuro--line-point))
         (candidates (kuro--line-all-history-completions prefix)))
    (kuro--line-dispatch-completion-candidates
     candidates
     "kuro: no history completions for %S"
     prefix
     "history completions"
     (lambda (candidate)
       (kuro--line-replace-buffer-with-undo candidate)))))

(defun kuro--line-history-search ()
  "Search `kuro--line-history' interactively using completion.
Uses `completing-read' over all history entries so the user can filter by
substring.  The selected entry replaces `kuro--line-buffer' with point at
the end.  Signals `user-error' when history is empty.  Canceling leaves the
line buffer unchanged."
  (interactive)
  (unless kuro--line-history
    (user-error "Kuro: history is empty"))
  (condition-case nil
      (let ((match (completing-read "History: " kuro--line-history nil t
                                    nil nil kuro--line-buffer)))
        (unless (string= match "")
          (kuro--line-replace-buffer-with-undo match)))
    (quit nil)))

(provide 'kuro-input-mode-completion-history)
;;; kuro-input-mode-completion-history.el ends here
