;;; kuro-input-mode-history-test-2.el --- History navigation tests  -*- lexical-binding: t; -*-

;;; Commentary:

;; Unit tests for history navigation and completion in `kuro-input-mode-history.el'.
;;
;; Groups covered:
;;   Group 2:  kuro--line-all-history-completions
;;   Group 3:  kuro--line-word-span-before-point
;;   Group 4:  kuro--line-complete (dispatch)
;;   Group 5:  kuro--line-complete-history-multi
;;   Group 6:  kuro--line-complete-word
;;   Group 7:  kuro--line-expand-abbrev
;;   Group 8:  kuro--line-history-search
;;   Group 9:  kuro--line-history-prev
;;   Group 10: kuro--line-history-next
;;   Group 11: kuro--line-goto-history-oldest
;;   Group 12: kuro--line-goto-history-newest

;;; Code:

(require 'kuro-input-mode-history-test-support)
(require 'kuro-input-mode-history)

;;; ── Group 2: kuro--line-all-history-completions ──────────────────────────────

(kuro-history2--deftest-all-completions)

;;; ── Group 3: kuro--line-word-span-before-point ───────────────────────────────

(kuro-history2--deftest-word-spans)

(ert-deftest kuro-history2-with-word-span-binds-token-data ()
  "`kuro--line-with-word-span' binds span offsets and token string."
  (kuro-input-mode-test--with-edit
   (setq kuro--line-buffer "git status"
         kuro--line-point  7)
   (kuro--line-with-word-span (start end word)
     (should (equal (list start end word) '(4 7 "sta"))))))

;;; ── Group 4: kuro--line-complete dispatch ────────────────────────────────────

(kuro-history2--deftest-complete-dispatches)

;;; ── Group 5: kuro--line-complete-history-multi ───────────────────────────────

(kuro-history2--deftest-complete-history-multi)

;;; ── Group 6: kuro--line-complete-word ───────────────────────────────────────

(kuro-history2--deftest-complete-words)

;;; ── Group 7: kuro--line-expand-abbrev ────────────────────────────────────────

(kuro-history2--deftest-expand-abbrevs)

;;; ── Group 8: kuro--line-history-search ──────────────────────────────────────

(ert-deftest kuro-history2-history-search-errors-when-empty ()
  "`kuro--line-history-search' signals user-error when history is empty."
  (kuro-input-mode-test--with-edit
   (setq kuro--line-history nil)
   (should-error (kuro--line-history-search) :type 'user-error)))

(kuro-history2--deftest-history-searches)

;;; ── Group 9: kuro--line-history-prev ───────────────────────────────────────

(kuro-history2--deftest-nav-actions
 kuro-history2-history-prev-noop-when-history-empty
 kuro-history2-history-prev-first-call-stashes-buffer
 kuro-history2-history-prev-first-call-loads-most-recent
 kuro-history2-history-prev-second-call-advances-index
 kuro-history2-history-prev-clamps-at-oldest)

;;; ── Group 10: kuro--line-history-next ───────────────────────────────────────

(kuro-history2--deftest-nav-actions
 kuro-history2-history-next-noop-at-bottom
 kuro-history2-history-next-from-zero-restores-stash
 kuro-history2-history-next-decrements-index)

;;; ── Group 11: kuro--line-goto-history-oldest ─────────────────────────────────

(kuro-history2--deftest-nav-actions
 kuro-history2-goto-oldest-noop-when-empty
 kuro-history2-goto-oldest-stashes-buffer
 kuro-history2-goto-oldest-jumps-to-last-entry)

;;; ── Group 12: kuro--line-goto-history-newest ─────────────────────────────────

(kuro-history2--deftest-nav-actions
 kuro-history2-goto-newest-noop-at-bottom
 kuro-history2-goto-newest-restores-stash-and-resets-index)

(ert-deftest kuro-history2-goto-newest-from-idx-zero-restores-stash ()
  "`kuro--line-goto-history-newest' works symmetrically with `kuro--line-goto-history-oldest'."
  (kuro-input-mode-test--with-edit
   (setq kuro--line-history '("git status")
         kuro--line-buffer "partial"
         kuro--line-history-idx -1
         kuro--line-history-stash "")
   ;; jump to oldest first
   (kuro--line-goto-history-oldest)
   (should (equal kuro--line-buffer "git status"))
   ;; then return to newest
   (kuro--line-goto-history-newest)
   (should (equal kuro--line-buffer "partial"))
   (should (= kuro--line-history-idx -1))))

(provide 'kuro-input-mode-history-test-2)
;;; kuro-input-mode-history-test-2.el ends here
