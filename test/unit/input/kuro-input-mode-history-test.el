;;; kuro-input-mode-history-test.el --- Tests for kuro-input-mode-history  -*- lexical-binding: t; -*-

;;; Commentary:

;; Unit tests for `kuro-input-mode-history.el'.
;; Covers: kuro--line-complete-history (single-match prefix completion).

;;; Code:

(require 'kuro-input-mode-history-test-support)
(require 'kuro-input-mode-history)

;; ── Group 1 — kuro--line-complete-history ─────────────────────────────────────

(ert-deftest kuro-history-test-complete-history-is-interactive ()
  "`kuro--line-complete-history' is an interactive command."
  (should (commandp #'kuro--line-complete-history)))

(kuro-history-test--deftest-complete-history)

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
