;;; kuro-input-paste-test.el --- Tests for kuro-input-paste  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;;; Commentary:

;; ERT tests for kuro-input-paste.el.
;; Covers kuro--sanitize-paste (ESC and C1 CSI injection prevention) and
;; kuro--yank / kuro--yank-pop (bracketed paste wrapping).
;; Pure Elisp tests — no Rust dynamic module required.
;; kuro--send-key and kuro--schedule-immediate-render are stubbed via cl-letf.

;;; Code:

(require 'kuro-input-paste-test-support)

;;; Group 1: kuro--sanitize-paste — basic behaviour

(kuro-paste-test--deftest-sanitizes
 kuro-input-paste--sanitize-clean-string-unchanged
 kuro-input-paste--sanitize-strips-single-esc
 kuro-input-paste--sanitize-strips-multiple-esc
 kuro-input-paste--sanitize-leading-esc
 kuro-input-paste--sanitize-trailing-esc
 kuro-input-paste--sanitize-only-esc-bytes
 kuro-input-paste--sanitize-empty-input
 kuro-input-paste--sanitize-long-input-no-truncation
 kuro-input-paste--sanitize-newlines-preserved
 kuro-input-paste--sanitize-tabs-preserved
 kuro-input-paste--sanitize-injection-sequence-neutralized
 kuro-input-paste--sanitize-c1-csi-injection-neutralized)

;;; Group 2: kuro--yank — plain mode (bracketed paste off)

(kuro-paste-test--deftest-yank-sends)

;;; Group 3: kuro--yank — bracketed paste mode

;;; Group 4: kuro--yank-pop — bracketed paste mode

(kuro-paste-test--deftest-yank-pop-sends)
(kuro-paste-test--deftest-yank-pop-errors)

;;; Group 5: Buffer-local state isolation

(kuro-paste-test--deftest-buffer-locals)

;;; Group 6: kuro--paste-open and kuro--paste-close defconst values

(kuro-paste-test--deftest-sequences)

(provide 'kuro-input-paste-test)
;;; kuro-input-paste-test.el ends here
