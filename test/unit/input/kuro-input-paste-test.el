;;; kuro-input-paste-test.el --- Tests for kuro-input-paste  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;;; Commentary:

;; ERT tests for kuro-input-paste.el.
;; Covers kuro--yank / kuro--yank-pop dispatch to the Rust paste boundary.
;; Pure Elisp tests — no Rust dynamic module required.
;; kuro--send-paste and kuro--schedule-immediate-render are stubbed via cl-letf.

;;; Code:

(require 'kuro-input-paste-test-support)

;;; Group 1: kuro--yank paste dispatch

(kuro-paste-test--deftest-yank-sends)

;;; Group 2: kuro--yank-pop paste dispatch

(kuro-paste-test--deftest-yank-pop-sends)
(kuro-paste-test--deftest-yank-pop-errors)

;;; Group 3: Buffer-local state isolation

(kuro-paste-test--deftest-buffer-locals)

(provide 'kuro-input-paste-test)
;;; kuro-input-paste-test.el ends here
