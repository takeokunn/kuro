;;; kuro-prompt-status-test-cases.el --- Data tables for prompt-status tests  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;;; Commentary:

;; Shared table data for kuro-prompt-status-test.el.

;;; Code:

(defconst kuro-prompt-status-test--indicator-result-table
  '((kuro-prompt-status--indicator-success-for-zero     0 "✓" kuro-prompt-success)
    (kuro-prompt-status--indicator-failure-for-nonzero  1 "✗" kuro-prompt-failure))
  "Table of (test-name exit-code expected-text expected-face) for exit-code indicator.")

(defconst kuro-prompt-status-test--format-duration-table
  '((kuro-prompt-status--format-duration-0ms       0       "0ms")
    (kuro-prompt-status--format-duration-999ms     999     "999ms")
    (kuro-prompt-status--format-duration-1000ms    1000    "1.0s")
    (kuro-prompt-status--format-duration-59999ms   59999   "60.0s")
    (kuro-prompt-status--format-duration-60000ms   60000   "1m00s")
    (kuro-prompt-status--format-duration-3600000ms 3600000 "60m00s"))
  "Table of (test-name ms expected) for `kuro--format-prompt-duration' boundaries.")

(defconst kuro-prompt-status-test--face-exists-table
  '((kuro-prompt-status--success-face-exists kuro-prompt-success)
    (kuro-prompt-status--failure-face-exists kuro-prompt-failure))
  "Table of (test-name face-sym) for prompt-status face existence checks.")

(provide 'kuro-prompt-status-test-cases)

;;; kuro-prompt-status-test-cases.el ends here
