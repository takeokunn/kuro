;;; kuro-input-mode-completion-dispatch.el --- Shared completion candidate dispatch for line mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Shared helper functions for line-mode completion commands.  These keep the
;; 0/1/many candidate branching in one place so word completion and history
;; completion stay thin.

;;; Code:

(defun kuro--line-display-completions (candidates label)
  "Display CANDIDATES and message their count with LABEL."
  (with-output-to-temp-buffer "*Completions*"
    (display-completion-list candidates))
  (message "kuro: %d %s" (length candidates) label))

(defun kuro--line-dispatch-completion-candidates
    (candidates no-match-format no-match-value multiple-label single-cont)
  "Run common completion control flow for CANDIDATES.
NO-MATCH-FORMAT and NO-MATCH-VALUE build the no-candidate message.
MULTIPLE-LABEL names the candidate kind in the multiple-candidate message.
SINGLE-CONT is called with the only candidate when there is exactly one."
  (let ((count (length candidates)))
    (cond
     ((zerop count)
      (message no-match-format no-match-value))
     ((= count 1)
      (funcall single-cont (car candidates)))
     (t
      (kuro--line-display-completions candidates multiple-label)))))

(provide 'kuro-input-mode-completion-dispatch)
;;; kuro-input-mode-completion-dispatch.el ends here
