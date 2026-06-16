;;; kuro-input-paste-test-2.el --- kuro-input-paste-test (part 2)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-input-paste-test-support)

;;; Group 7: kuro--send-paste-or-raw dispatch

(kuro-paste-test--deftest-send-paste-or-raws)

;;; Group 8: kuro--yank dispatch

(kuro-paste-test--deftest-yank-renders)
(kuro-paste-test--deftest-yank-args)

;;; Group 9: kuro--yank-pop edge cases

(kuro-paste-test--deftest-yank-pop-last-commands)

;;; Group 10: kuro--sanitize-paste — combined ESC and C1 CSI edge cases

(kuro-paste-test--deftest-sanitizes
 kuro-input-paste--sanitize-mixed-esc-and-c1
 kuro-input-paste--sanitize-only-c1-bytes
 kuro-input-paste--sanitize-preserves-unicode
 kuro-input-paste--sanitize-esc-between-unicode
 kuro-input-paste--sanitize-long-string-with-c1
 kuro-input-paste--sanitize-preserves-cr-lf
 kuro-input-paste--sanitize-consecutive-esc-and-c1
 kuro-input-paste--sanitize-does-not-strip-del
 kuro-input-paste--sanitize-null-byte-preserved
 kuro-input-paste--sanitize-c1-then-injection-sequence)


;;; Group 11: kuro--yank and kuro--yank-pop additional dispatch cases

(kuro-paste-test--deftest-yank-extras)
(kuro-paste-test--deftest-extra-errors)
(kuro-paste-test--deftest-initial-values)

;;; Group 12: kuro--paste-text, bracketed sequences, and dispatch invariants

(kuro-paste-test--deftest-sequence-structures)

(provide 'kuro-input-paste-test-2)
;;; kuro-input-paste-test-2.el ends here
