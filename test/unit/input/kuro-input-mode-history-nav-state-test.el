;;; kuro-input-mode-history-nav-state-test.el --- History navigation state tests  -*- lexical-binding: t; -*-

;;; Commentary:

;; Unit tests for pure helpers in `kuro-input-mode-history-nav-state.el'.

;;; Code:

(require 'kuro-input-mode-history-test-support)
(require 'kuro-input-mode-history-test-macros)
(require 'kuro-input-mode-history-nav-state)

(ert-deftest kuro-history-nav-state-stash-if-fresh-stores-buffer-when-idx-minus-one ()
  "`kuro--line-history-stash-if-fresh' stashes `kuro--line-buffer' when idx is -1."
  (kuro-input-mode-test--with-edit
   (setq kuro--line-buffer "git status"
         kuro--line-history-idx -1)
   (kuro--line-history-stash-if-fresh)
   (should (equal kuro--line-history-stash "git status"))))

(ert-deftest kuro-history-nav-state-stash-if-fresh-noop-when-idx-nonzero ()
  "`kuro--line-history-stash-if-fresh' does nothing when already navigating (idx ≠ -1)."
  (kuro-input-mode-test--with-edit
   (setq kuro--line-buffer "new text"
         kuro--line-history-idx 2
         kuro--line-history-stash "original")
   (kuro--line-history-stash-if-fresh)
   (should (equal kuro--line-history-stash "original"))))

(ert-deftest kuro-history-nav-state-history-last-index-returns-oldest-index ()
  "`kuro--line-history-last-index' returns the last list position."
  (kuro-input-mode-test--with-edit
   (setq kuro--line-history '("git status" "ls" "pwd"))
   (should (= (kuro--line-history-last-index) 2))))


(kuro-history2--deftest-history-index-table
 kuro-history-nav-state-history-prev-index-table
 "`kuro--line-history-prev-index' advances toward older history and clamps."
 kuro-history2--prev-index-cases
 kuro--line-history-prev-index)


(kuro-history2--deftest-history-index-table
 kuro-history-nav-state-history-next-index-table
 "`kuro--line-history-next-index' advances toward newer history."
 kuro-history2--next-index-cases
 kuro--line-history-next-index)

(provide 'kuro-input-mode-history-nav-state-test)
;;; kuro-input-mode-history-nav-state-test.el ends here
