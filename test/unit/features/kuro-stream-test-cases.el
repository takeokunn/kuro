;;; kuro-stream-test-cases.el --- Data tables for kuro-stream tests  -*- lexical-binding: t; -*-

;;; Commentary:

;; Shared table data for kuro-stream-test.el.

;;; Code:

(defconst kuro-stream-test--min-interval-lazy-init-table
  '((kuro-stream--min-interval-lazy-init-at-60fps 60)
    (kuro-stream--min-interval-lazy-init-at-30fps 30))
  "Table of (test-name frame-rate) for lazy kuro--stream-min-interval init tests.")

(defconst kuro-stream-test--stop-reset-sim-table
  '((kuro-stream--stop-resets-last-render-time kuro--stream-last-render-time 0.0)
    (kuro-stream--stop-resets-min-interval     kuro--stream-min-interval     nil))
  "Table: (test-name var-sym expected-after-reset) for simulated stop reset tests.")

(provide 'kuro-stream-test-cases)

;;; kuro-stream-test-cases.el ends here
