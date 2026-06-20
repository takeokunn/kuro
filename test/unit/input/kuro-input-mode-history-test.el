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

(provide 'kuro-input-mode-history-test)

;;; kuro-input-mode-history-test.el ends here
