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

(require 'kuro-input-mode-test-support)
(require 'kuro-input-mode-history)

;;; ── Test helpers ─────────────────────────────────────────────────────────────

(defmacro kuro-history2--with-nav (history buf idx stash &rest body)
  "Run BODY inside `kuro-input-mode-test--with-edit' with history state pre-set.
HISTORY: `kuro--line-history' (list or nil).
BUF: `kuro--line-buffer' string (use \"\" when the test doesn't care about initial buf).
IDX: `kuro--line-history-idx' integer.
STASH: `kuro--line-history-stash' string (use \"\" when not relevant)."
  `(kuro-input-mode-test--with-edit
    (setq kuro--line-history ,history
          kuro--line-buffer   ,buf
          kuro--line-history-idx ,idx
          kuro--line-history-stash ,stash)
    ,@body))

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

(ert-deftest kuro-history2-all-completions-returns-prefix-matches ()
  "`kuro--line-all-history-completions' returns entries that start with PREFIX."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history '("git status" "git diff" "ls -la" "git log"))
    (should (equal (kuro--line-all-history-completions "git")
                   '("git status" "git diff" "git log")))))

(ert-deftest kuro-history2-all-completions-excludes-exact-match ()
  "`kuro--line-all-history-completions' excludes entries equal to PREFIX."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history '("git" "git status"))
    (should (equal (kuro--line-all-history-completions "git")
                   '("git status")))))

(ert-deftest kuro-history2-all-completions-deduplicates ()
  "`kuro--line-all-history-completions' returns each unique entry only once."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history '("git status" "git status" "git diff"))
    (should (equal (kuro--line-all-history-completions "git")
                   '("git status" "git diff")))))

(ert-deftest kuro-history2-all-completions-empty-prefix-returns-all ()
  "`kuro--line-all-history-completions' with empty prefix returns all unique entries."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history '("ls" "pwd" "ls"))
    (should (equal (kuro--line-all-history-completions "")
                   '("ls" "pwd")))))

(ert-deftest kuro-history2-all-completions-no-match-returns-nil ()
  "`kuro--line-all-history-completions' returns nil when nothing matches PREFIX."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history '("ls" "pwd"))
    (should (null (kuro--line-all-history-completions "git")))))

(ert-deftest kuro-history2-all-completions-preserves-order ()
  "`kuro--line-all-history-completions' preserves history order (most-recent first)."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history '("git status" "git diff" "git log"))
    (let ((result (kuro--line-all-history-completions "git")))
      (should (equal (nth 0 result) "git status"))
      (should (equal (nth 1 result) "git diff"))
      (should (equal (nth 2 result) "git log")))))

;;; ── Group 4: kuro--line-word-span-before-point ───────────────────────────────

(ert-deftest kuro-history2-word-span-at-eol-returns-last-word ()
  "`kuro--line-word-span-before-point' returns span of the last word when at EOL."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-buffer "git status"
          kuro--line-point  10)
    (should (equal (kuro--line-word-span-before-point) '(4 . 10)))))

(ert-deftest kuro-history2-word-span-at-bol-returns-empty ()
  "`kuro--line-word-span-before-point' returns (0 . 0) when point is at the start."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-buffer "git status"
          kuro--line-point  0)
    (should (equal (kuro--line-word-span-before-point) '(0 . 0)))))

(ert-deftest kuro-history2-word-span-mid-word-returns-current ()
  "`kuro--line-word-span-before-point' returns span of word even if point is mid-word."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-buffer "git status"
          kuro--line-point  7)
    ;; point is at 's' in "sta|tus"; span should cover "sta" (4..7)
    (should (equal (kuro--line-word-span-before-point) '(4 . 7)))))

(ert-deftest kuro-history2-word-span-after-space-is-empty ()
  "`kuro--line-word-span-before-point' returns empty span when point follows a space."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-buffer "git "
          kuro--line-point  4)
    ;; point is right after the space; no word before it
    (should (equal (kuro--line-word-span-before-point) '(4 . 4)))))

;;; ── Group 5: kuro--line-complete dispatch ────────────────────────────────────

(ert-deftest kuro-history2-complete-dispatches-to-history-multi-when-no-fn ()
  "`kuro--line-complete' calls `kuro--line-complete-history-multi' when completion fn is nil."
  (kuro-input-mode-test--with-edit
    (let ((kuro-line-completion-function nil)
          called)
      (cl-letf (((symbol-function 'kuro--line-complete-history-multi)
                 (lambda () (setq called t))))
        (kuro--line-complete)
        (should called)))))

(ert-deftest kuro-history2-complete-dispatches-to-word-when-fn-set ()
  "`kuro--line-complete' calls `kuro--line-complete-word' when `kuro-line-completion-function' is set."
  (kuro-input-mode-test--with-edit
    (let ((kuro-line-completion-function #'ignore)
          called)
      (cl-letf (((symbol-function 'kuro--line-complete-word)
                 (lambda () (setq called t))))
        (kuro--line-complete)
        (should called)))))

;;; ── Group 6: kuro--line-complete-history-multi ───────────────────────────────

(ert-deftest kuro-history2-complete-multi-no-match-messages ()
  "`kuro--line-complete-history-multi' messages the user when no candidates match."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history '("ls" "pwd")
          kuro--line-buffer   "git"
          kuro--line-point    3)
    (let (msg)
      (cl-letf (((symbol-function 'message) (lambda (fmt &rest args)
                                               (setq msg (apply #'format fmt args)))))
        (kuro--line-complete-history-multi)
        (should (string-match-p "git" (or msg "")))))))

(ert-deftest kuro-history2-complete-multi-single-replaces-buffer ()
  "`kuro--line-complete-history-multi' replaces the buffer when only one candidate."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history '("git status" "ls")
          kuro--line-buffer   "git s"
          kuro--line-point    5)
    (kuro--line-complete-history-multi)
    (should (equal kuro--line-buffer "git status"))))

(ert-deftest kuro-history2-complete-multi-multi-shows-completions ()
  "`kuro--line-complete-history-multi' emits a message with the candidate count."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history '("git status" "git diff" "ls")
          kuro--line-buffer   "git"
          kuro--line-point    3)
    (let (msg)
      (cl-letf (((symbol-function 'message) (lambda (fmt &rest args)
                                               (setq msg (apply #'format fmt args))))
                ((symbol-function 'display-completion-list) #'ignore))
        (kuro--line-complete-history-multi)
        ;; Multi case: message says "2 history completions"
        (should (string-match-p "2" (or msg "")))))))

(ert-deftest kuro-history2-complete-multi-multi-does-not-replace-buffer ()
  "`kuro--line-complete-history-multi' does not modify the line buffer when multiple candidates."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history '("git status" "git diff" "ls")
          kuro--line-buffer   "git"
          kuro--line-point    3)
    (cl-letf (((symbol-function 'display-completion-list) #'ignore)
              ((symbol-function 'message) #'ignore))
      (kuro--line-complete-history-multi)
      (should (equal kuro--line-buffer "git")))))

;;; ── Group 7: kuro--line-complete-word ───────────────────────────────────────

(ert-deftest kuro-history2-complete-word-no-match-messages ()
  "`kuro--line-complete-word' messages when the completion function returns nil."
  (kuro-input-mode-test--with-edit
    (let ((kuro-line-completion-function (lambda (_prefix) nil)))
      (setq kuro--line-buffer "gi"
            kuro--line-point  2)
      (let (msg)
        (cl-letf (((symbol-function 'message) (lambda (fmt &rest args)
                                                 (setq msg (apply #'format fmt args)))))
          (kuro--line-complete-word)
          (should (stringp msg)))))))

(ert-deftest kuro-history2-complete-word-single-replaces-word ()
  "`kuro--line-complete-word' replaces the word at point with the sole candidate."
  (kuro-input-mode-test--with-edit
    (let ((kuro-line-completion-function (lambda (_prefix) '("git"))))
      (setq kuro--line-buffer "gi"
            kuro--line-point  2)
      (kuro--line-complete-word)
      (should (equal kuro--line-buffer "git")))))

(ert-deftest kuro-history2-complete-word-multiple-messages-count ()
  "`kuro--line-complete-word' emits a message with the candidate count when multiple candidates."
  (kuro-input-mode-test--with-edit
    (let ((kuro-line-completion-function (lambda (_prefix) '("git" "gitk"))))
      (setq kuro--line-buffer "gi"
            kuro--line-point  2)
      (let (msg)
        (cl-letf (((symbol-function 'message) (lambda (fmt &rest args)
                                                 (setq msg (apply #'format fmt args))))
                  ((symbol-function 'display-completion-list) #'ignore))
          (kuro--line-complete-word)
          (should (string-match-p "2" (or msg ""))))))))

(ert-deftest kuro-history2-complete-word-multiple-does-not-replace-buffer ()
  "`kuro--line-complete-word' does not modify the line buffer when multiple candidates."
  (kuro-input-mode-test--with-edit
    (let ((kuro-line-completion-function (lambda (_prefix) '("git" "gitk"))))
      (setq kuro--line-buffer "gi"
            kuro--line-point  2)
      (cl-letf (((symbol-function 'display-completion-list) #'ignore)
                ((symbol-function 'message) #'ignore))
        (kuro--line-complete-word)
        (should (equal kuro--line-buffer "gi"))))))

;;; ── Group 8: kuro--line-expand-abbrev ────────────────────────────────────────

(ert-deftest kuro-history2-expand-abbrev-replaces-word-when-found ()
  "`kuro--line-expand-abbrev' replaces the word before point with its expansion."
  (kuro-input-mode-test--with-edit
    (let ((kuro-line-abbrev-alist '(("gs" . "git status"))))
      (setq kuro--line-buffer "gs"
            kuro--line-point  2)
      (kuro--line-expand-abbrev)
      (should (equal kuro--line-buffer "git status")))))

(ert-deftest kuro-history2-expand-abbrev-no-match-messages ()
  "`kuro--line-expand-abbrev' messages the user when the word is not in the alist."
  (kuro-input-mode-test--with-edit
    (let ((kuro-line-abbrev-alist '(("gs" . "git status"))))
      (setq kuro--line-buffer "ls"
            kuro--line-point  2)
      (let (msg)
        (cl-letf (((symbol-function 'message) (lambda (fmt &rest args)
                                                 (setq msg (apply #'format fmt args)))))
          (kuro--line-expand-abbrev)
          (should (string-match-p "ls" (or msg ""))))))))

(ert-deftest kuro-history2-expand-abbrev-leaves-context-intact ()
  "`kuro--line-expand-abbrev' expands only the last word, preserving the prefix."
  (kuro-input-mode-test--with-edit
    (let ((kuro-line-abbrev-alist '(("gs" . "git status"))))
      (setq kuro--line-buffer "cmd gs"
            kuro--line-point  6)
      (kuro--line-expand-abbrev)
      (should (string-prefix-p "cmd " kuro--line-buffer)))))

;;; ── Group 9: kuro--line-history-search ──────────────────────────────────────

(ert-deftest kuro-history2-history-search-errors-when-empty ()
  "`kuro--line-history-search' signals user-error when history is empty."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history nil)
    (should-error (kuro--line-history-search) :type 'user-error)))

(ert-deftest kuro-history2-history-search-calls-completing-read ()
  "`kuro--line-history-search' calls `completing-read' with the history list."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history '("git status" "ls"))
    (let (cr-collection)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt collection &rest _)
                   (setq cr-collection collection)
                   "git status")))
        (kuro--line-history-search)
        (should (equal cr-collection kuro--line-history))))))

(ert-deftest kuro-history2-history-search-sets-buffer-to-selection ()
  "`kuro--line-history-search' replaces line buffer with the completing-read result."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history '("git status" "ls")
          kuro--line-buffer  "")
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "git status")))
      (kuro--line-history-search)
      (should (equal kuro--line-buffer "git status")))))

(ert-deftest kuro-history2-history-search-noop-on-empty-selection ()
  "`kuro--line-history-search' is a no-op when `completing-read' returns empty string."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history '("git status")
          kuro--line-buffer  "old")
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "")))
      (kuro--line-history-search)
      (should (equal kuro--line-buffer "old")))))

(ert-deftest kuro-history2-history-search-quit-is-noop ()
  "`kuro--line-history-search' silently aborts when `completing-read' signals quit."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history '("git status")
          kuro--line-buffer  "old")
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) (signal 'quit nil))))
      (kuro--line-history-search)
      (should (equal kuro--line-buffer "old")))))

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

;;; ── Group 11: kuro--line-history-prev ───────────────────────────────────────

(ert-deftest kuro-history2-history-prev-noop-when-history-empty ()
  "`kuro--line-history-prev' does nothing when history is empty."
  (kuro-history2--with-nav nil "current" -1 ""
    (kuro--line-history-prev)
    (should (equal kuro--line-buffer "current"))
    (should (= kuro--line-history-idx -1))))

(ert-deftest kuro-history2-history-prev-first-call-stashes-buffer ()
  "`kuro--line-history-prev' stashes current buffer on the first call (idx = -1)."
  (kuro-history2--with-nav '("git status" "ls") "partial" -1 ""
    (kuro--line-history-prev)
    (should (equal kuro--line-history-stash "partial"))))

(ert-deftest kuro-history2-history-prev-first-call-loads-most-recent ()
  "`kuro--line-history-prev' loads history[0] on the first call."
  (kuro-history2--with-nav '("git status" "ls") "partial" -1 ""
    (kuro--line-history-prev)
    (should (equal kuro--line-buffer "git status"))
    (should (= kuro--line-history-idx 0))))

(ert-deftest kuro-history2-history-prev-second-call-advances-index ()
  "`kuro--line-history-prev' advances index on subsequent calls."
  (kuro-history2--with-nav '("git status" "ls" "pwd") "" 0 "partial"
    (kuro--line-history-prev)
    (should (equal kuro--line-buffer "ls"))
    (should (= kuro--line-history-idx 1))))

(ert-deftest kuro-history2-history-prev-clamps-at-oldest ()
  "`kuro--line-history-prev' stays at the oldest entry when already there."
  (kuro-history2--with-nav '("git status" "ls") "" 1 "x"
    (kuro--line-history-prev)
    (should (= kuro--line-history-idx 1))
    (should (equal kuro--line-buffer "ls"))))

;;; ── Group 12: kuro--line-history-next ───────────────────────────────────────

(ert-deftest kuro-history2-history-next-noop-at-bottom ()
  "`kuro--line-history-next' does nothing when idx is already -1."
  (kuro-history2--with-nav '("git status") "current" -1 ""
    (kuro--line-history-next)
    (should (equal kuro--line-buffer "current"))
    (should (= kuro--line-history-idx -1))))

(ert-deftest kuro-history2-history-next-from-zero-restores-stash ()
  "`kuro--line-history-next' at idx=0 restores the stash and resets to -1."
  (kuro-history2--with-nav '("git status") "" 0 "partial"
    (kuro--line-history-next)
    (should (equal kuro--line-buffer "partial"))
    (should (= kuro--line-history-idx -1))))

(ert-deftest kuro-history2-history-next-decrements-index ()
  "`kuro--line-history-next' moves toward more-recent entries."
  (kuro-history2--with-nav '("git status" "ls" "pwd") "" 2 "partial"
    (kuro--line-history-next)
    (should (equal kuro--line-buffer "ls"))
    (should (= kuro--line-history-idx 1))))

;;; ── Group 13: kuro--line-goto-history-oldest ─────────────────────────────────

(ert-deftest kuro-history2-goto-oldest-noop-when-empty ()
  "`kuro--line-goto-history-oldest' does nothing when history is empty."
  (kuro-history2--with-nav nil "current" -1 ""
    (kuro--line-goto-history-oldest)
    (should (equal kuro--line-buffer "current"))))

(ert-deftest kuro-history2-goto-oldest-stashes-buffer ()
  "`kuro--line-goto-history-oldest' stashes the current buffer (when at idx -1)."
  (kuro-history2--with-nav '("git status" "ls" "pwd") "work in progress" -1 ""
    (kuro--line-goto-history-oldest)
    (should (equal kuro--line-history-stash "work in progress"))))

(ert-deftest kuro-history2-goto-oldest-jumps-to-last-entry ()
  "`kuro--line-goto-history-oldest' loads the last (oldest) history entry."
  (kuro-history2--with-nav '("git status" "ls" "pwd") "" -1 ""
    (kuro--line-goto-history-oldest)
    (should (equal kuro--line-buffer "pwd"))
    (should (= kuro--line-history-idx 2))))

;;; ── Group 14: kuro--line-goto-history-newest ─────────────────────────────────

(ert-deftest kuro-history2-goto-newest-noop-at-bottom ()
  "`kuro--line-goto-history-newest' does nothing when idx is already -1."
  (kuro-history2--with-nav '("git status") "current" -1 ""
    (kuro--line-goto-history-newest)
    (should (equal kuro--line-buffer "current"))
    (should (= kuro--line-history-idx -1))))

(ert-deftest kuro-history2-goto-newest-restores-stash-and-resets-index ()
  "`kuro--line-goto-history-newest' restores the stash and resets idx to -1."
  (kuro-history2--with-nav '("git status" "ls") "" 1 "work in progress"
    (kuro--line-goto-history-newest)
    (should (equal kuro--line-buffer "work in progress"))
    (should (= kuro--line-history-idx -1))))

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
