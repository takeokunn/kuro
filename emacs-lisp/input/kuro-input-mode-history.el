;;; kuro-input-mode-history.el --- Completion and history for line mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Completion, history navigation, and navigation commands for Kuro line mode.
;; Loaded automatically at the end of `kuro-input-mode'.

;;; Code:

(require 'kuro-input-mode-macros)

;; Buffer-local variables defined in kuro-input-mode.el (loaded before this file).
(defvar kuro--line-buffer)
(defvar kuro--line-point)
(defvar kuro--line-history)
(defvar kuro--line-history-idx)
(defvar kuro--line-history-stash)
(defvar kuro-line-completion-function)
(defvar kuro-line-abbrev-alist)

(defsubst kuro--line-history-stash-if-fresh ()
  "Stash the current buffer when first entering history navigation (idx = -1)."
  (when (= kuro--line-history-idx -1)
    (setq kuro--line-history-stash kuro--line-buffer)))

(defun kuro--line-complete-history ()
  "Complete `kuro--line-buffer' using the most recent matching history entry.
Uses the current buffer content as a prefix and replaces it with the most
recent `kuro--line-history' entry that starts with (but is not equal to)
that prefix.  No-ops with a message when no entry matches."
  (interactive)
  (let ((prefix kuro--line-buffer))
    (if-let* ((match (seq-find
                      (lambda (h) (and (string-prefix-p prefix h)
                                       (not (equal h prefix))))
                      kuro--line-history)))
        (progn
          (kuro--line-undo-push)
          (kuro--line-set-buffer match))
      (message "kuro: no history completion for %S" prefix))))

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

(defsubst kuro--line-word-span-before-point ()
  "Return (START . END) for the space-delimited token immediately before point.
Both `kuro--line-complete-word' and `kuro--line-expand-abbrev' use this."
  (let* ((end   kuro--line-point)
         (start end))
    (while (and (> start 0)
                (not (= (aref kuro--line-buffer (1- start)) ?\s)))
      (setq start (1- start)))
    (cons start end)))

(defmacro kuro--line-with-word-span (vars &rest body)
  "Bind VARS to the word span before point, then run BODY.
VARS must be (START-VAR END-VAR WORD-VAR)."
  (declare (indent defun))
  (let ((start-var (nth 0 vars))
        (end-var (nth 1 vars))
        (word-var (nth 2 vars))
        (span (make-symbol "span")))
    `(let* ((,span (kuro--line-word-span-before-point))
            (,start-var (car ,span))
            (,end-var (cdr ,span))
            (,word-var (substring kuro--line-buffer ,start-var ,end-var)))
       ,@body)))

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
  (cond
   ((null candidates)
    (message no-match-format no-match-value))
   ((= (length candidates) 1)
    (funcall single-cont (car candidates)))
   (t
    (kuro--line-display-completions candidates multiple-label))))

(defun kuro--line-complete ()
  "Complete the current line-mode input (TAB).
When `kuro-line-completion-function' is set, calls it with the word
immediately before point; replaces that word on a unique match or displays
all candidates.  Otherwise matches the full input prefix (up to point)
against `kuro--line-history' via `kuro--line-all-history-completions':
unique match replaces the buffer; multiple matches show a *Completions*
buffer; no match messages the user."
  (interactive)
  (if kuro-line-completion-function
      (kuro--line-complete-word)
    (kuro--line-complete-history-multi)))

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
       (kuro--line-undo-push)
       (kuro--line-set-buffer candidate)))))

(defun kuro--line-complete-word ()
  "TAB word completion via `kuro-line-completion-function' for the word at point."
  (kuro--line-with-word-span (word-start word-end prefix)
    (kuro--line-dispatch-completion-candidates
     (funcall kuro-line-completion-function prefix)
     "kuro: no completions for %S"
     prefix
     "completions"
     (lambda (candidate)
       (kuro--with-line-edit-undo
	(kuro--line-splice word-start word-end candidate
			   (+ word-start (length candidate))))))))

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
	(kuro--with-line-edit-undo
	 (kuro--line-splice start end expansion
			    (+ start (length expansion))))))))

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
          (kuro--line-undo-push)
          (kuro--line-set-buffer match)))
    (quit nil)))

(defsubst kuro--line-load-history-entry (idx)
  "Load history entry IDX into the line buffer and refresh the display."
  (kuro--line-set-buffer (nth idx kuro--line-history)))

(defsubst kuro--line-history-last-index ()
  "Return the index of the oldest history entry."
  (1- (length kuro--line-history)))

(defsubst kuro--line-history-prev-index ()
  "Return the history index reached by moving to older history."
  (if (= kuro--line-history-idx -1)
      0
    (min (1+ kuro--line-history-idx)
         (kuro--line-history-last-index))))

(defsubst kuro--line-history-next-index ()
  "Return the history index reached by moving to newer history."
  (1- kuro--line-history-idx))

(defsubst kuro--line-restore-history-stash ()
  "Restore stashed live input and reset history navigation state."
  (setq kuro--line-history-idx -1)
  (kuro--line-set-buffer kuro--line-history-stash))

(defun kuro--line-history-prev ()
  "Navigate to the previous (older) entry in line-mode history.
On the first call stashes the current in-progress input, then moves
backward through `kuro--line-history' (index 0 = most recent)."
  (interactive)
  (when kuro--line-history
    (kuro--line-history-stash-if-fresh)
    (setq kuro--line-history-idx (kuro--line-history-prev-index))
    (kuro--line-load-history-entry kuro--line-history-idx)))

(defun kuro--line-history-next ()
  "Navigate to the next (newer) entry in line-mode history.
At the bottom (idx -1) does nothing.  At index 0 restores the stashed
in-progress input and resets the navigation index to -1."
  (interactive)
  (unless (= kuro--line-history-idx -1)
    (setq kuro--line-history-idx (kuro--line-history-next-index))
    (if (= kuro--line-history-idx -1)
        (kuro--line-restore-history-stash)
      (kuro--line-load-history-entry kuro--line-history-idx))))

(defun kuro--line-goto-history-oldest ()
  "Jump to the oldest entry in line-mode history (readline M-<).
Stashes the current in-progress input the same way as
`kuro--line-history-prev', then moves directly to the last element of
`kuro--line-history'.  No-op when the history list is empty."
  (interactive)
  (when kuro--line-history
    (kuro--line-history-stash-if-fresh)
    (setq kuro--line-history-idx (kuro--line-history-last-index))
    (kuro--line-load-history-entry kuro--line-history-idx)))

(defun kuro--line-goto-history-newest ()
  "Return to the most recent (in-progress) input in line-mode (readline M->).
Restores `kuro--line-history-stash' and resets the navigation index to -1,
  mirroring the behavior of `kuro--line-history-next' at the bottom of history."
  (interactive)
  (unless (= kuro--line-history-idx -1)
    (kuro--line-restore-history-stash)))

(kuro--def-line-nav kuro--line-beginning-of-line
  "Move `kuro--line-point' to the beginning of the line (C-a)."
  (setq kuro--line-point 0))

(kuro--def-line-nav kuro--line-end-of-line
  "Move `kuro--line-point' to the end of the line (C-e)."
  (setq kuro--line-point (length kuro--line-buffer)))

(kuro--def-line-nav kuro--line-forward-char
  "Move `kuro--line-point' one character forward (C-f)."
  (when (< kuro--line-point (length kuro--line-buffer))
    (setq kuro--line-point (1+ kuro--line-point))))

(kuro--def-line-nav kuro--line-backward-char
  "Move `kuro--line-point' one character backward (C-b)."
  (when (> kuro--line-point 0)
    (setq kuro--line-point (1- kuro--line-point))))

(kuro--def-line-nav kuro--line-forward-word
  "Move `kuro--line-point' forward past the end of the next word (M-f)."
  (let ((s kuro--line-buffer))
    (setq kuro--line-point
	  (kuro--line-skip-word-fwd s
				    (kuro--line-skip-non-word-fwd s kuro--line-point)))))

(kuro--def-line-nav kuro--line-backward-word
  "Move `kuro--line-point' backward past the start of the previous word (M-b)."
  (let ((s kuro--line-buffer))
    (setq kuro--line-point
	  (kuro--line-skip-word-bwd s
				    (kuro--line-skip-non-word-bwd s kuro--line-point)))))

(require 'kuro-input-mode-ext)

(provide 'kuro-input-mode-history)
;;; kuro-input-mode-history.el ends here
