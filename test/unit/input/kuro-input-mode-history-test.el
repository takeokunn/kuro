;;; kuro-input-mode-history-test.el --- Tests for kuro-input-mode-history  -*- lexical-binding: t; -*-

;;; Commentary:

;; Unit tests for `kuro-input-mode-history.el'.
;; Covers: kuro--line-complete-history (single-match prefix completion).

;;; Code:

(require 'kuro-input-mode-test-support)
(require 'kuro-input-mode-history)

;; ── Helpers ───────────────────────────────────────────────────────────────────

(defmacro kuro-history-test--with-complete (&rest body)
  "Run BODY with `kuro--line-undo-push' and `kuro--line-set-buffer' stubbed.
Binds `set-buf-called' to the argument passed to `kuro--line-set-buffer'."
  `(kuro-input-mode-test--with-buffer
    (let (set-buf-called)
      (cl-letf (((symbol-function 'kuro--line-undo-push) #'ignore)
                ((symbol-function 'kuro--line-set-buffer)
                 (lambda (s) (setq set-buf-called s))))
        ,@body))))

;; ── Group 1 — kuro--line-complete-history ─────────────────────────────────────

(ert-deftest kuro-history-test-complete-history-is-interactive ()
  "`kuro--line-complete-history' is an interactive command."
  (should (commandp #'kuro--line-complete-history)))

(ert-deftest kuro-history-test-complete-history-match-calls-set-buffer ()
  "When a history entry starts with the prefix, `kuro--line-set-buffer' is called."
  (kuro-history-test--with-complete
    (setq kuro--line-buffer "git s"
          kuro--line-history '("git status" "git commit"))
    (kuro--line-complete-history)
    (should (equal set-buf-called "git status"))))

(ert-deftest kuro-history-test-complete-history-first-match-wins ()
  "seq-find returns the first (most recent) matching entry."
  (kuro-history-test--with-complete
    (setq kuro--line-buffer "git"
          kuro--line-history '("git status" "git commit" "git log"))
    (kuro--line-complete-history)
    (should (equal set-buf-called "git status"))))

(ert-deftest kuro-history-test-complete-history-exact-match-skipped ()
  "An entry identical to the prefix is excluded; next candidate is used."
  (kuro-history-test--with-complete
    (setq kuro--line-buffer "git status"
          kuro--line-history '("git status" "git status --short"))
    (kuro--line-complete-history)
    (should (equal set-buf-called "git status --short"))))

(ert-deftest kuro-history-test-complete-history-no-match-messages ()
  "When no entry matches, a message is emitted and `kuro--line-set-buffer' is not called."
  (kuro-history-test--with-complete
    (setq kuro--line-buffer "xyz"
          kuro--line-history '("git status" "ls -la"))
    (let (msg-text)
      (cl-letf (((symbol-function 'message) (lambda (fmt &rest args)
                                               (setq msg-text (apply #'format fmt args)))))
        (kuro--line-complete-history))
      (should (null set-buf-called))
      (should (string-match-p "xyz" (or msg-text ""))))))

(ert-deftest kuro-history-test-complete-history-empty-history-no-match ()
  "Empty history always produces the no-match path."
  (kuro-history-test--with-complete
    (setq kuro--line-buffer "ls"
          kuro--line-history nil)
    (kuro--line-complete-history)
    (should (null set-buf-called))))

(ert-deftest kuro-history-test-complete-history-empty-prefix-matches-any ()
  "An empty prefix matches any non-empty history entry (string-prefix-p \"\" s is always t)."
  (kuro-history-test--with-complete
    (setq kuro--line-buffer ""
          kuro--line-history '("git status" "ls"))
    (kuro--line-complete-history)
    (should (equal set-buf-called "git status"))))

(ert-deftest kuro-history-test-complete-history-all-exact-no-match ()
  "When every history entry equals the prefix, there is no completion."
  (kuro-history-test--with-complete
    (setq kuro--line-buffer "ls"
          kuro--line-history '("ls" "ls"))
    (kuro--line-complete-history)
    (should (null set-buf-called))))

(ert-deftest kuro-history-test-complete-history-calls-undo-push-on-match ()
  "`kuro--line-undo-push' is called before `kuro--line-set-buffer' on a match."
  (kuro-input-mode-test--with-buffer
    (let (undo-called set-called call-order)
      (cl-letf (((symbol-function 'kuro--line-undo-push)
                 (lambda () (push 'undo call-order)))
                ((symbol-function 'kuro--line-set-buffer)
                 (lambda (_s) (push 'set call-order))))
        (setq kuro--line-buffer "git"
              kuro--line-history '("git status"))
        (kuro--line-complete-history))
      (should (equal (reverse call-order) '(undo set))))))

(provide 'kuro-input-mode-history-test)

;;; kuro-input-mode-history-test.el ends here
