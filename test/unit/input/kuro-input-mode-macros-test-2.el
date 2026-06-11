;;; kuro-input-mode-macros-test-2.el --- Tests for kuro-input-mode-macros.el (part 2)  -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for kuro--line-skip-* word-scan defsubsts and kuro--line-word-bounds-forward.

;;; Code:

(require 'kuro-input-mode-test-support)
(require 'kuro-input-mode-macros)

;;; Group 3 — kuro--line-skip-non-word-fwd / kuro--line-skip-word-fwd

(ert-deftest kuro-input-mode-macros-skip-non-word-fwd-skips-spaces ()
  "`kuro--line-skip-non-word-fwd' advances past leading spaces."
  (should (= (kuro--line-skip-non-word-fwd "  hello" 0) 2)))

(ert-deftest kuro-input-mode-macros-skip-non-word-fwd-at-word-is-noop ()
  "`kuro--line-skip-non-word-fwd' is a no-op when already at a word character."
  (should (= (kuro--line-skip-non-word-fwd "hello" 0) 0)))

(ert-deftest kuro-input-mode-macros-skip-non-word-fwd-at-end-returns-len ()
  "`kuro--line-skip-non-word-fwd' returns string length when tail is all non-word."
  (should (= (kuro--line-skip-non-word-fwd "   " 0) 3)))

(ert-deftest kuro-input-mode-macros-skip-word-fwd-advances-past-word ()
  "`kuro--line-skip-word-fwd' advances past an entire word."
  (should (= (kuro--line-skip-word-fwd "hello world" 0) 5)))

(ert-deftest kuro-input-mode-macros-skip-word-fwd-at-non-word-is-noop ()
  "`kuro--line-skip-word-fwd' is a no-op when starting at a non-word character."
  (should (= (kuro--line-skip-word-fwd " hello" 0) 0)))

(ert-deftest kuro-input-mode-macros-skip-word-fwd-at-end-returns-len ()
  "`kuro--line-skip-word-fwd' returns length when starting past end."
  (let ((s "hi"))
    (should (= (kuro--line-skip-word-fwd s (length s)) (length s)))))

;;; Group 4 — kuro--line-skip-non-word-bwd / kuro--line-skip-word-bwd

(ert-deftest kuro-input-mode-macros-skip-non-word-bwd-skips-trailing-spaces ()
  "`kuro--line-skip-non-word-bwd' retreats past trailing spaces."
  (let* ((s "hello  ") (p (length s)))
    (should (= (kuro--line-skip-non-word-bwd s p) 5))))

(ert-deftest kuro-input-mode-macros-skip-non-word-bwd-at-word-is-noop ()
  "`kuro--line-skip-non-word-bwd' is a no-op when p-1 is a word character."
  (should (= (kuro--line-skip-non-word-bwd "hello" 5) 5)))

(ert-deftest kuro-input-mode-macros-skip-word-bwd-retreats-past-word ()
  "`kuro--line-skip-word-bwd' retreats past an entire word."
  (should (= (kuro--line-skip-word-bwd "hello" 5) 0)))

(ert-deftest kuro-input-mode-macros-skip-word-bwd-stops-at-space ()
  "`kuro--line-skip-word-bwd' stops at a space boundary."
  (should (= (kuro--line-skip-word-bwd "foo bar" 7) 4)))

;;; Group 5 — kuro--line-word-bounds-forward

(ert-deftest kuro-input-mode-macros-word-bounds-forward-at-start-of-word ()
  "`kuro--line-word-bounds-forward' returns the span of the word at point."
  (let ((kuro--line-buffer "hello world")
        (kuro--line-point 0))
    (should (equal (kuro--line-word-bounds-forward) '(0 . 5)))))

(ert-deftest kuro-input-mode-macros-word-bounds-forward-skips-leading-space ()
  "`kuro--line-word-bounds-forward' skips leading non-word chars before the word."
  (let ((kuro--line-buffer "  foo")
        (kuro--line-point 0))
    (should (equal (kuro--line-word-bounds-forward) '(2 . 5)))))

(ert-deftest kuro-input-mode-macros-word-bounds-forward-empty-buffer ()
  "`kuro--line-word-bounds-forward' returns (0 . 0) for empty buffer."
  (let ((kuro--line-buffer "")
        (kuro--line-point 0))
    (should (equal (kuro--line-word-bounds-forward) '(0 . 0)))))

(ert-deftest kuro-input-mode-macros-word-bounds-forward-all-spaces ()
  "`kuro--line-word-bounds-forward' returns (len . len) when buffer has no words."
  (let* ((s "   ") (kuro--line-buffer s) (kuro--line-point 0))
    (should (equal (kuro--line-word-bounds-forward) (cons (length s) (length s))))))

(provide 'kuro-input-mode-macros-test-2)
;;; kuro-input-mode-macros-test-2.el ends here
