;;; kuro-input-mode-history-test-cases.el --- History input test cases  -*- lexical-binding: t; -*-

;;; Commentary:

;; Data tables for history-related input-mode tests.

;;; Code:

(defconst kuro-history-test--complete-history-cases
  '((kuro-history-test-complete-history-match-calls-set-buffer
     "When a history entry starts with the prefix, `kuro--line-set-buffer' is called."
     "git s"
     ("git status" "git commit")
     (:set-buffer "git status"))
    (kuro-history-test-complete-history-first-match-wins
     "seq-find returns the first (most recent) matching entry."
     "git"
     ("git status" "git commit" "git log")
     (:set-buffer "git status"))
    (kuro-history-test-complete-history-exact-match-skipped
     "An entry identical to the prefix is excluded; next candidate is used."
     "git status"
     ("git status" "git status --short")
     (:set-buffer "git status --short"))
    (kuro-history-test-complete-history-no-match-messages
     "When no entry matches, a message is emitted and `kuro--line-set-buffer' is not called."
     "xyz"
     ("git status" "ls -la")
     (:set-buffer nil :message "xyz"))
    (kuro-history-test-complete-history-empty-history-no-match
     "Empty history always produces the no-match path."
     "ls"
     nil
     (:set-buffer nil))
    (kuro-history-test-complete-history-empty-prefix-matches-any
     "An empty prefix matches any non-empty history entry (string-prefix-p \"\" s is always t)."
     ""
     ("git status" "ls")
     (:set-buffer "git status"))
    (kuro-history-test-complete-history-all-exact-no-match
     "When every history entry equals the prefix, there is no completion."
     "ls"
     ("ls" "ls")
     (:set-buffer nil)))
  "Data cases for `kuro--line-complete-history'.")

(defconst kuro-history2--all-completions-cases
  '((kuro-history2-all-completions-returns-prefix-matches
     "git"
     ("git status" "git diff" "ls -la" "git log")
     ("git status" "git diff" "git log")
     "`kuro--line-all-history-completions' returns entries that start with PREFIX.")
    (kuro-history2-all-completions-excludes-exact-match
     "git"
     ("git" "git status")
     ("git status")
     "`kuro--line-all-history-completions' excludes entries equal to PREFIX.")
    (kuro-history2-all-completions-deduplicates
     "git"
     ("git status" "git status" "git diff")
     ("git status" "git diff")
     "`kuro--line-all-history-completions' returns each unique entry only once.")
    (kuro-history2-all-completions-empty-prefix-returns-all
     ""
     ("ls" "pwd" "ls")
     ("ls" "pwd")
     "`kuro--line-all-history-completions' with empty prefix returns all unique entries.")
    (kuro-history2-all-completions-no-match-returns-nil
     "git"
     ("ls" "pwd")
     nil
     "`kuro--line-all-history-completions' returns nil when nothing matches PREFIX.")
    (kuro-history2-all-completions-preserves-order
     "git"
     ("git status" "git diff" "git log")
     ("git status" "git diff" "git log")
     "`kuro--line-all-history-completions' preserves history order (most-recent first)."))
  "Cases for `kuro--line-all-history-completions'.")

(defconst kuro-history2--word-span-cases
  '((kuro-history2-word-span-at-eol-returns-last-word
     "git status"
     10
     (4 . 10)
     "`kuro--line-word-span-before-point' returns span of the last word when at EOL.")
    (kuro-history2-word-span-at-bol-returns-empty
     "git status"
     0
     (0 . 0)
     "`kuro--line-word-span-before-point' returns (0 . 0) when point is at the start.")
    (kuro-history2-word-span-mid-word-returns-current
     "git status"
     7
     (4 . 7)
     "`kuro--line-word-span-before-point' returns span of word even if point is mid-word.")
    (kuro-history2-word-span-after-space-is-empty
     "git "
     4
     (4 . 4)
     "`kuro--line-word-span-before-point' returns empty span when point follows a space."))
  "Cases for `kuro--line-word-span-before-point'.")

(defconst kuro-history2--complete-dispatch-cases
  '((kuro-history2-complete-dispatches-to-history-multi-when-no-fn
     "`kuro--line-complete' calls `kuro--line-complete-history-multi' when completion fn is nil."
     nil
     kuro--line-complete-history-multi)
    (kuro-history2-complete-dispatches-to-word-when-fn-set
     "`kuro--line-complete' calls `kuro--line-complete-word' when `kuro-line-completion-function' is set."
     ignore
     kuro--line-complete-word))
  "Cases for `kuro--line-complete' dispatch behavior.")

(defconst kuro-history2--complete-history-multi-cases
  '((kuro-history2-complete-multi-no-match-messages
     "`kuro--line-complete-history-multi' messages the user when no candidates match."
     ("ls" "pwd") "git" 3
     (:message-match "git"))
    (kuro-history2-complete-multi-single-replaces-buffer
     "`kuro--line-complete-history-multi' replaces the buffer when only one candidate."
     ("git status" "ls") "git s" 5
     (:buffer "git status"))
    (kuro-history2-complete-multi-multi-shows-completions
     "`kuro--line-complete-history-multi' emits a message with the candidate count."
     ("git status" "git diff" "ls") "git" 3
     (:message-match "2"))
    (kuro-history2-complete-multi-multi-does-not-replace-buffer
     "`kuro--line-complete-history-multi' does not modify the line buffer when multiple candidates."
     ("git status" "git diff" "ls") "git" 3
     (:buffer "git")))
  "Cases for `kuro--line-complete-history-multi'.")

(defconst kuro-history2--complete-word-cases
  '((kuro-history2-complete-word-no-match-messages
     "`kuro--line-complete-word' messages when the completion function returns nil."
     nil "gi" 2
     (:message t))
    (kuro-history2-complete-word-single-replaces-word
     "`kuro--line-complete-word' replaces the word at point with the sole candidate."
     ("git") "gi" 2
     (:buffer "git"))
    (kuro-history2-complete-word-multiple-messages-count
     "`kuro--line-complete-word' emits a message with the candidate count when multiple candidates."
     ("git" "gitk") "gi" 2
     (:message-match "2"))
    (kuro-history2-complete-word-multiple-does-not-replace-buffer
     "`kuro--line-complete-word' does not modify the line buffer when multiple candidates."
     ("git" "gitk") "gi" 2
     (:buffer "gi")))
  "Cases for `kuro--line-complete-word'.")

(defconst kuro-history2--expand-abbrev-cases
  '((kuro-history2-expand-abbrev-replaces-word-when-found
     "`kuro--line-expand-abbrev' replaces the word before point with its expansion."
     (("gs" . "git status")) "gs" 2
     (:buffer "git status"))
    (kuro-history2-expand-abbrev-no-match-messages
     "`kuro--line-expand-abbrev' messages the user when the word is not in the alist."
     (("gs" . "git status")) "ls" 2
     (:message-match "ls"))
    (kuro-history2-expand-abbrev-leaves-context-intact
     "`kuro--line-expand-abbrev' expands only the last word, preserving the prefix."
     (("gs" . "git status")) "cmd gs" 6
     (:prefix "cmd ")))
  "Cases for `kuro--line-expand-abbrev'.")

(defconst kuro-history2--history-search-cases
  '((kuro-history2-history-search-calls-completing-read
     "`kuro--line-history-search' calls `completing-read' with the history list."
     ("git status" "ls") "" "git status"
     (:collection t))
    (kuro-history2-history-search-sets-buffer-to-selection
     "`kuro--line-history-search' replaces line buffer with the completing-read result."
     ("git status" "ls") "" "git status"
     (:buffer "git status"))
    (kuro-history2-history-search-noop-on-empty-selection
     "`kuro--line-history-search' is a no-op when `completing-read' returns empty string."
     ("git status") "old" ""
     (:buffer "old"))
    (kuro-history2-history-search-quit-is-noop
     "`kuro--line-history-search' silently aborts when `completing-read' signals quit."
     ("git status") "old" :quit
     (:buffer "old")))
  "Cases for `kuro--line-history-search'.")

(defconst kuro-history2--nav-action-cases
  '((kuro-history2-history-prev-noop-when-history-empty
     "`kuro--line-history-prev' does nothing when history is empty."
     nil "current" -1 "" kuro--line-history-prev
     (:buffer "current" :idx -1))
    (kuro-history2-history-prev-first-call-stashes-buffer
     "`kuro--line-history-prev' stashes current buffer on the first call (idx = -1)."
     ("git status" "ls") "partial" -1 "" kuro--line-history-prev
     (:stash "partial"))
    (kuro-history2-history-prev-first-call-loads-most-recent
     "`kuro--line-history-prev' loads history[0] on the first call."
     ("git status" "ls") "partial" -1 "" kuro--line-history-prev
     (:buffer "git status" :idx 0))
    (kuro-history2-history-prev-second-call-advances-index
     "`kuro--line-history-prev' advances index on subsequent calls."
     ("git status" "ls" "pwd") "" 0 "partial" kuro--line-history-prev
     (:buffer "ls" :idx 1))
    (kuro-history2-history-prev-clamps-at-oldest
     "`kuro--line-history-prev' stays at the oldest entry when already there."
     ("git status" "ls") "" 1 "x" kuro--line-history-prev
     (:buffer "ls" :idx 1))
    (kuro-history2-history-next-noop-at-bottom
     "`kuro--line-history-next' does nothing when idx is already -1."
     ("git status") "current" -1 "" kuro--line-history-next
     (:buffer "current" :idx -1))
    (kuro-history2-history-next-from-zero-restores-stash
     "`kuro--line-history-next' at idx=0 restores the stash and resets to -1."
     ("git status") "" 0 "partial" kuro--line-history-next
     (:buffer "partial" :idx -1))
    (kuro-history2-history-next-decrements-index
     "`kuro--line-history-next' moves toward more-recent entries."
     ("git status" "ls" "pwd") "" 2 "partial" kuro--line-history-next
     (:buffer "ls" :idx 1))
    (kuro-history2-goto-oldest-noop-when-empty
     "`kuro--line-goto-history-oldest' does nothing when history is empty."
     nil "current" -1 "" kuro--line-goto-history-oldest
     (:buffer "current"))
    (kuro-history2-goto-oldest-stashes-buffer
     "`kuro--line-goto-history-oldest' stashes the current buffer (when at idx -1)."
     ("git status" "ls" "pwd") "work in progress" -1 "" kuro--line-goto-history-oldest
     (:stash "work in progress"))
    (kuro-history2-goto-oldest-jumps-to-last-entry
     "`kuro--line-goto-history-oldest' loads the last (oldest) history entry."
     ("git status" "ls" "pwd") "" -1 "" kuro--line-goto-history-oldest
     (:buffer "pwd" :idx 2))
    (kuro-history2-goto-newest-noop-at-bottom
     "`kuro--line-goto-history-newest' does nothing when idx is already -1."
     ("git status") "current" -1 "" kuro--line-goto-history-newest
     (:buffer "current" :idx -1))
    (kuro-history2-goto-newest-restores-stash-and-resets-index
     "`kuro--line-goto-history-newest' restores the stash and resets idx to -1."
     ("git status" "ls") "" 1 "work in progress" kuro--line-goto-history-newest
     (:buffer "work in progress" :idx -1)))
  "Cases for history navigation actions.")

(defconst kuro-history2--prev-index-cases
  '(((-1 ("git status" "ls")) . 0)
    ((0 ("git status" "ls")) . 1)
    ((1 ("git status" "ls")) . 1))
  "Cases for `kuro--line-history-prev-index'.")

(defconst kuro-history2--next-index-cases
  '(((2 ("git status" "ls" "pwd")) . 1)
    ((1 ("git status" "ls" "pwd")) . 0)
    ((0 ("git status" "ls" "pwd")) . -1))
  "Cases for `kuro--line-history-next-index'.")

(provide 'kuro-input-mode-history-test-cases)

;;; kuro-input-mode-history-test-cases.el ends here
