;;; kuro-input-encode-test.el --- Tests for named-key-sequences and encode-key-event  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-input.el — Groups 14-15.
;; Groups 1-13 are in kuro-input-test.el and kuro-input-test-2.el.

;;; Code:
(require 'kuro-input-test-support)

;;; Group 14: kuro--named-key-sequences data table

(ert-deftest kuro-input-named-key-sequences-is-alist ()
  "kuro--named-key-sequences is a non-empty alist of (symbol . string) pairs."
  (should (consp kuro--named-key-sequences))
  (dolist (entry kuro--named-key-sequences)
    (should (symbolp (car entry)))
    (should (stringp (cdr entry)))))

(kuro-input-test--deftest-named-key-sequence-cases)

;;; Group 15: kuro--encode-key-event

(kuro-input-test--deftest-encode-key-event-cases)


(provide 'kuro-input-encode-test)
;;; kuro-input-encode-test.el ends here
