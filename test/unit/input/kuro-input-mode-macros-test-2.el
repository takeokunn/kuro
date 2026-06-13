;;; kuro-input-mode-macros-test-2.el --- Tests for kuro-input-mode-macros.el (part 2)  -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for kuro--line-skip-* word-scan defsubsts, kuro--line-word-bounds-forward,
;; kuro--line-complete-history-multi, kuro--line-complete-word, and kuro--line-history-search.

;;; Code:

(require 'kuro-input-mode-test-support)
(require 'kuro-input-mode-macros)

;;; Group 3 — kuro--line-skip-non-word-fwd / kuro--line-skip-word-fwd

(ert-deftest kuro-input-mode-macros-skip-non-word-fwd-skips-spaces ()
  "`kuro--line-skip-non-word-fwd' advances past leading spaces."
  (should (= (kuro--line-skip-non-word-fwd "  hello" 0) 2)))

(ert-deftest kuro-input-mode-macros-skip-non-word-fwd-at-word-is-noop ()
  "`kuro--line-skip-non-word-fwd' is a no-op when already at a word character."
  (should (= (kuro--line-skip-non-word-fwd "hello" 0) 0)))

(ert-deftest kuro-input-mode-macros-skip-non-word-fwd-at-end-returns-len ()
  "`kuro--line-skip-non-word-fwd' returns string length when tail is all non-word."
  (should (= (kuro--line-skip-non-word-fwd "   " 0) 3)))

(ert-deftest kuro-input-mode-macros-skip-word-fwd-advances-past-word ()
  "`kuro--line-skip-word-fwd' advances past an entire word."
  (should (= (kuro--line-skip-word-fwd "hello world" 0) 5)))

(ert-deftest kuro-input-mode-macros-skip-word-fwd-at-non-word-is-noop ()
  "`kuro--line-skip-word-fwd' is a no-op when starting at a non-word character."
  (should (= (kuro--line-skip-word-fwd " hello" 0) 0)))

(ert-deftest kuro-input-mode-macros-skip-word-fwd-at-end-returns-len ()
  "`kuro--line-skip-word-fwd' returns length when starting past end."
  (let ((s "hi"))
    (should (= (kuro--line-skip-word-fwd s (length s)) (length s)))))

;;; Group 4 — kuro--line-skip-non-word-bwd / kuro--line-skip-word-bwd

(ert-deftest kuro-input-mode-macros-skip-non-word-bwd-skips-trailing-spaces ()
  "`kuro--line-skip-non-word-bwd' retreats past trailing spaces."
  (let* ((s "hello  ") (p (length s)))
    (should (= (kuro--line-skip-non-word-bwd s p) 5))))

(ert-deftest kuro-input-mode-macros-skip-non-word-bwd-at-word-is-noop ()
  "`kuro--line-skip-non-word-bwd' is a no-op when p-1 is a word character."
  (should (= (kuro--line-skip-non-word-bwd "hello" 5) 5)))

(ert-deftest kuro-input-mode-macros-skip-word-bwd-retreats-past-word ()
  "`kuro--line-skip-word-bwd' retreats past an entire word."
  (should (= (kuro--line-skip-word-bwd "hello" 5) 0)))

(ert-deftest kuro-input-mode-macros-skip-word-bwd-stops-at-space ()
  "`kuro--line-skip-word-bwd' stops at a space boundary."
  (should (= (kuro--line-skip-word-bwd "foo bar" 7) 4)))

;;; Group 5 — kuro--line-word-bounds-forward

(ert-deftest kuro-input-mode-macros-word-bounds-forward-at-start-of-word ()
  "`kuro--line-word-bounds-forward' returns the span of the word at point."
  (let ((kuro--line-buffer "hello world")
        (kuro--line-point 0))
    (should (equal (kuro--line-word-bounds-forward) '(0 . 5)))))

(ert-deftest kuro-input-mode-macros-word-bounds-forward-skips-leading-space ()
  "`kuro--line-word-bounds-forward' skips leading non-word chars before the word."
  (let ((kuro--line-buffer "  foo")
        (kuro--line-point 0))
    (should (equal (kuro--line-word-bounds-forward) '(2 . 5)))))

(ert-deftest kuro-input-mode-macros-word-bounds-forward-empty-buffer ()
  "`kuro--line-word-bounds-forward' returns (0 . 0) for empty buffer."
  (let ((kuro--line-buffer "")
        (kuro--line-point 0))
    (should (equal (kuro--line-word-bounds-forward) '(0 . 0)))))

(ert-deftest kuro-input-mode-macros-word-bounds-forward-all-spaces ()
  "`kuro--line-word-bounds-forward' returns (len . len) when buffer has no words."
  (let* ((s "   ") (kuro--line-buffer s) (kuro--line-point 0))
    (should (equal (kuro--line-word-bounds-forward) (cons (length s) (length s))))))

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
   (cl-letf (((symbol-function 'kuro--line-undo-push) #'ignore)
             ((symbol-function 'kuro--line-set-buffer) (lambda (s) (setq kuro--line-buffer s))))
     (kuro--line-complete-history-multi))
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
  (let ((kuro--line-history '("git status" "ls"))
        (kuro--line-buffer "")
        set-to)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) "git status"))
              ((symbol-function 'kuro--line-undo-push) #'ignore)
              ((symbol-function 'kuro--line-set-buffer)
               (lambda (s) (setq set-to s))))
      (kuro--line-history-search))
    (should (equal set-to "git status"))))

(ert-deftest kuro-input-mode-macros-history-search-quit-leaves-buffer-unchanged ()
  "`kuro--line-history-search' swallows C-g quit and leaves buffer unchanged."
  (let ((kuro--line-history '("git status"))
        (kuro--line-buffer "orig")
        changed)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) (signal 'quit nil)))
              ((symbol-function 'kuro--line-set-buffer)
               (lambda (_) (setq changed t))))
      (kuro--line-history-search))
    (should-not changed)))

(ert-deftest kuro-input-mode-macros-history-search-empty-selection-no-set ()
  "`kuro--line-history-search' does not call `kuro--line-set-buffer' for empty selection."
  (let ((kuro--line-history '("git status"))
        set-called)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) ""))
              ((symbol-function 'kuro--line-undo-push) #'ignore)
              ((symbol-function 'kuro--line-set-buffer)
               (lambda (_) (setq set-called t))))
      (kuro--line-history-search))
    (should-not set-called)))

(provide 'kuro-input-mode-macros-test-2)
;;; kuro-input-mode-macros-test-2.el ends here
