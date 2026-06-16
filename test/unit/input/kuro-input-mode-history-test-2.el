;;; kuro-input-mode-history-test-2.el --- History navigation tests  -*- lexical-binding: t; -*-

;;; Commentary:

;; Unit tests for history navigation and completion in `kuro-input-mode-history.el'.
;;
;; Groups covered:
;;   Group 2:  kuro--line-history-stash-if-fresh
;;   Group 3:  kuro--line-all-history-completions
;;   Group 4:  kuro--line-word-span-before-point
;;   Group 5:  kuro--line-complete (dispatch)
;;   Group 6:  kuro--line-complete-history-multi
;;   Group 7:  kuro--line-complete-word
;;   Group 8:  kuro--line-expand-abbrev
;;   Group 9:  kuro--line-history-search
;;   Group 10: kuro--line-load-history-entry
;;   Group 11: kuro--line-history-prev
;;   Group 12: kuro--line-history-next
;;   Group 13: kuro--line-goto-history-oldest
;;   Group 14: kuro--line-goto-history-newest

;;; Code:

(require 'kuro-input-mode-history-test-support)
(require 'kuro-input-mode-history)

;;; ── Group 2: kuro--line-history-stash-if-fresh ───────────────────────────────

(ert-deftest kuro-history2-stash-if-fresh-stores-buffer-when-idx-minus-one ()
  "`kuro--line-history-stash-if-fresh' stashes `kuro--line-buffer' when idx is -1."
  (kuro-input-mode-test--with-edit
   (setq kuro--line-buffer "git status"
         kuro--line-history-idx -1)
   (kuro--line-history-stash-if-fresh)
   (should (equal kuro--line-history-stash "git status"))))

(ert-deftest kuro-history2-stash-if-fresh-noop-when-idx-nonzero ()
  "`kuro--line-history-stash-if-fresh' does nothing when already navigating (idx ≠ -1)."
  (kuro-input-mode-test--with-edit
   (setq kuro--line-buffer "new text"
         kuro--line-history-idx 2
         kuro--line-history-stash "original")
   (kuro--line-history-stash-if-fresh)
   (should (equal kuro--line-history-stash "original"))))

;;; ── Group 3: kuro--line-all-history-completions ──────────────────────────────

(kuro-history2--deftest-all-completions)

;;; ── Group 4: kuro--line-word-span-before-point ───────────────────────────────

(kuro-history2--deftest-word-spans)

(ert-deftest kuro-history2-with-word-span-binds-token-data ()
  "`kuro--line-with-word-span' binds span offsets and token string."
  (kuro-input-mode-test--with-edit
   (setq kuro--line-buffer "git status"
         kuro--line-point  7)
   (kuro--line-with-word-span (start end word)
     (should (equal (list start end word) '(4 7 "sta"))))))

;;; ── Group 5: kuro--line-complete dispatch ────────────────────────────────────

(kuro-history2--deftest-complete-dispatches)

;;; ── Group 6: kuro--line-complete-history-multi ───────────────────────────────

(kuro-history2--deftest-complete-history-multi)

;;; ── Group 7: kuro--line-complete-word ───────────────────────────────────────

(kuro-history2--deftest-complete-words)

;;; ── Group 8: kuro--line-expand-abbrev ────────────────────────────────────────

(kuro-history2--deftest-expand-abbrevs)

;;; ── Group 9: kuro--line-history-search ──────────────────────────────────────

(ert-deftest kuro-history2-history-search-errors-when-empty ()
  "`kuro--line-history-search' signals user-error when history is empty."
  (kuro-input-mode-test--with-edit
   (setq kuro--line-history nil)
   (should-error (kuro--line-history-search) :type 'user-error)))

(kuro-history2--deftest-history-searches)

;;; ── Group 10: kuro--line-load-history-entry ─────────────────────────────────

(ert-deftest kuro-history2-load-history-entry-sets-buffer ()
  "`kuro--line-load-history-entry' loads the entry at IDX into the line buffer."
  (kuro-input-mode-test--with-edit
   (setq kuro--line-history '("git status" "ls" "pwd"))
   (kuro--line-load-history-entry 1)
   (should (equal kuro--line-buffer "ls"))))

(ert-deftest kuro-history2-load-history-entry-sets-point-to-end ()
  "`kuro--line-load-history-entry' places `kuro--line-point' at the end of the loaded entry."
  (kuro-input-mode-test--with-edit
   (setq kuro--line-history '("git status"))
   (kuro--line-load-history-entry 0)
   (should (= kuro--line-point (length "git status")))))

(ert-deftest kuro-history2-history-last-index-returns-oldest-index ()
  "`kuro--line-history-last-index' returns the last list position."
  (kuro-input-mode-test--with-edit
   (setq kuro--line-history '("git status" "ls" "pwd"))
   (should (= (kuro--line-history-last-index) 2))))

(ert-deftest kuro-history2-history-prev-index-table ()
  "`kuro--line-history-prev-index' advances toward older history and clamps."
  (dolist (case kuro-history2--prev-index-cases)
    (pcase-let ((`((,idx ,history) . ,expected) case))
      (kuro-input-mode-test--with-edit
       (setq kuro--line-history history
             kuro--line-history-idx idx)
       (should (= (kuro--line-history-prev-index) expected))))))

(ert-deftest kuro-history2-history-next-index-table ()
  "`kuro--line-history-next-index' advances toward newer history."
  (dolist (case kuro-history2--next-index-cases)
    (pcase-let ((`((,idx ,history) . ,expected) case))
      (kuro-input-mode-test--with-edit
       (setq kuro--line-history history
             kuro--line-history-idx idx)
       (should (= (kuro--line-history-next-index) expected))))))

(ert-deftest kuro-history2-restore-history-stash-resets-index ()
  "`kuro--line-restore-history-stash' restores live input and exits history navigation."
  (kuro-history2--with-nav '("git status") "" 0 "partial"
    (kuro--line-restore-history-stash)
    (should (equal kuro--line-buffer "partial"))
    (should (= kuro--line-history-idx -1))))

;;; ── Group 11: kuro--line-history-prev ───────────────────────────────────────

(kuro-history2--deftest-nav-actions
 kuro-history2-history-prev-noop-when-history-empty
 kuro-history2-history-prev-first-call-stashes-buffer
 kuro-history2-history-prev-first-call-loads-most-recent
 kuro-history2-history-prev-second-call-advances-index
 kuro-history2-history-prev-clamps-at-oldest)

;;; ── Group 12: kuro--line-history-next ───────────────────────────────────────

(kuro-history2--deftest-nav-actions
 kuro-history2-history-next-noop-at-bottom
 kuro-history2-history-next-from-zero-restores-stash
 kuro-history2-history-next-decrements-index)

;;; ── Group 13: kuro--line-goto-history-oldest ─────────────────────────────────

(kuro-history2--deftest-nav-actions
 kuro-history2-goto-oldest-noop-when-empty
 kuro-history2-goto-oldest-stashes-buffer
 kuro-history2-goto-oldest-jumps-to-last-entry)

;;; ── Group 14: kuro--line-goto-history-newest ─────────────────────────────────

(kuro-history2--deftest-nav-actions
 kuro-history2-goto-newest-noop-at-bottom
 kuro-history2-goto-newest-restores-stash-and-resets-index)

(ert-deftest kuro-history2-goto-newest-from-idx-zero-restores-stash ()
  "`kuro--line-goto-history-newest' works symmetrically with `kuro--line-goto-history-oldest'."
  (kuro-history2--with-nav '("git status") "partial" -1 ""
    ;; jump to oldest first
    (kuro--line-goto-history-oldest)
    (should (equal kuro--line-buffer "git status"))
    ;; then return to newest
    (kuro--line-goto-history-newest)
    (should (equal kuro--line-buffer "partial"))
    (should (= kuro--line-history-idx -1))))

(provide 'kuro-input-mode-history-test-2)
;;; kuro-input-mode-history-test-2.el ends here
