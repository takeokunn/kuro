;;; kuro-lifecycle-test-cases.el --- Shared lifecycle test data  -*- lexical-binding: t; -*-

;;; Commentary:

;; Data tables shared by lifecycle tests.

;;; Code:

(defconst kuro-lifecycle-test--session-status-table
  '((kuro-lifecycle--sessions-entry-running  (5 "fish" nil t)   "running")
    (kuro-lifecycle--sessions-entry-detached (3 "bash" t   t)   "detached")
    (kuro-lifecycle--sessions-entry-dead     (7 "zsh"  nil nil) "dead"))
  "Table: (test-name raw-entry expected-status) for session status conversion.")

(provide 'kuro-lifecycle-test-cases)

;;; kuro-lifecycle-test-cases.el ends here
