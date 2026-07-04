;;; kuro-input-mode-macros-test-2.el --- Tests for kuro-input-mode-macros.el (part 2)  -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for kuro--line-skip-* word-scan defsubsts, kuro--line-word-bounds-forward,
;; kuro--line-complete-history-multi, kuro--line-complete-word, and kuro--line-history-search.

;;; Code:

(require 'kuro-input-mode-test-support)
(require 'kuro-input-mode-macros)

;;; Group 3/4 — word-skip scanners

(kuro-input-mode-macros-test--deftest-skip-cases)

;;; Group 5 — kuro--line-word-bounds-forward

(kuro-input-mode-macros-test--deftest-word-bounds-forward)

;;; ── kuro--line-complete-history-multi ────────────────────────────────────────

(ert-deftest kuro-input-mode-macros-complete-history-multi-no-candidates-messages ()
  "`kuro--line-complete-history-multi' messages when no candidates match."
  (let ((kuro--line-buffer "xyz") (kuro--line-point 3) (kuro--line-history nil)
        msgs)
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
      (kuro--line-complete-history-multi))
    (should (cl-some (lambda (m) (string-match-p "no history" m)) msgs))))

(ert-deftest kuro-input-mode-macros-complete-history-multi-single-candidate-sets-buffer ()
  "`kuro--line-complete-history-multi' completes directly when exactly one match."
  (kuro-input-mode-test--with-buffer
   ;; Use prefix "git s" — matches only "git status", not "git commit"
   (setq kuro--line-buffer "git s" kuro--line-point 5
         kuro--line-history '("git status" "git commit"))
   (kuro--line-complete-history-multi)
   (should (equal kuro--line-buffer "git status"))))

;;; ── kuro--line-complete-word ──────────────────────────────────────────────────

(ert-deftest kuro-input-mode-macros-complete-word-no-candidates-messages ()
  "`kuro--line-complete-word' messages when completion function returns nil."
  (let ((kuro--line-buffer "foo") (kuro--line-point 3)
        (kuro-line-completion-function (lambda (_) nil))
        msgs)
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
      (kuro--line-complete-word))
    (should (cl-some (lambda (m) (string-match-p "no completions" m)) msgs))))

(ert-deftest kuro-input-mode-macros-complete-history-multi-multiple-candidates-messages ()
  "`kuro--line-complete-history-multi' messages the count when >1 candidate matches."
  (kuro-input-mode-test--with-line "git" 3
   (setq kuro--line-history '("git status" "git commit" "ls"))
   (let (msgs)
     (cl-letf (((symbol-function 'display-completion-list) #'ignore)
               ((symbol-function 'message)
                (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
       (kuro--line-complete-history-multi))
     (should (cl-some (lambda (m) (string-match-p "2 history completions" m)) msgs)))))

;;; ── kuro--line-complete-word (single/multiple candidate paths) ───────────────

(ert-deftest kuro-input-mode-macros-complete-word-single-candidate-splices ()
  "`kuro--line-complete-word' replaces the word before point when exactly one match."
  (kuro-input-mode-test--with-line "git sta" 7
   (let ((kuro-line-completion-function (lambda (_) '("status"))))
     (kuro--line-complete-word))
   ;; "sta" (positions 4-7) replaced by "status"
   (should (equal kuro--line-buffer "git status"))))

(ert-deftest kuro-input-mode-macros-complete-word-multiple-candidates-messages ()
  "`kuro--line-complete-word' messages the count when >1 candidate matches."
  (kuro-input-mode-test--with-line "git" 3
   (let ((kuro-line-completion-function (lambda (_) '("git" "gitk")))
         msgs)
     (cl-letf (((symbol-function 'display-completion-list) #'ignore)
               ((symbol-function 'message)
                (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
       (kuro--line-complete-word))
     (should (cl-some (lambda (m) (string-match-p "2 completions" m)) msgs)))))

;;; ── kuro--line-history-search ────────────────────────────────────────────────

(ert-deftest kuro-input-mode-macros-history-search-empty-history-user-error ()
  "`kuro--line-history-search' signals user-error when history is empty."
  (let ((kuro--line-history nil))
    (should-error (kuro--line-history-search) :type 'user-error)))

(ert-deftest kuro-input-mode-macros-history-search-selection-sets-buffer ()
  "`kuro--line-history-search' sets the line buffer to the selected entry."
  (kuro-input-mode-test--with-buffer
   (let ((kuro--line-history '("git status" "ls")))
     (cl-letf (((symbol-function 'completing-read)
                (lambda (&rest _) "git status")))
       (kuro--line-history-search))
     (should (equal kuro--line-buffer "git status"))
     (should (= kuro--line-point (length "git status"))))))

(ert-deftest kuro-input-mode-macros-history-search-quit-leaves-buffer-unchanged ()
  "`kuro--line-history-search' swallows C-g quit and leaves buffer unchanged."
  (kuro-input-mode-test--with-buffer
   (let ((kuro--line-history '("git status")))
     (setq kuro--line-buffer "orig"
           kuro--line-point 4)
     (cl-letf (((symbol-function 'completing-read)
                (lambda (&rest _) (signal 'quit nil))))
       (kuro--line-history-search))
     (should (equal kuro--line-buffer "orig"))
     (should (= kuro--line-point 4)))))

(ert-deftest kuro-input-mode-macros-history-search-empty-selection-no-set ()
  "`kuro--line-history-search' does not call `kuro--line-set-buffer' for empty selection."
  (kuro-input-mode-test--with-buffer
   (let ((kuro--line-history '("git status")))
     (setq kuro--line-buffer "orig"
           kuro--line-point 4)
     (cl-letf (((symbol-function 'completing-read)
                (lambda (&rest _) "")))
       (kuro--line-history-search))
     (should (equal kuro--line-buffer "orig"))
     (should (= kuro--line-point 4)))))

;;; Group 6-10 — macro structural tests

(kuro-input-mode-macros-test--deftest-macro-heads)
(kuro-input-mode-macros-test--deftest-macro-members)
(kuro-input-mode-macros-test--deftest-macro-tails)
(kuro-input-mode-macros-test--deftest-macro-form-positions)
(kuro-input-mode-macros-test--deftest-interactive-commands)

(provide 'kuro-input-mode-macros-test-2)
;;; kuro-input-mode-macros-test-2.el ends here
