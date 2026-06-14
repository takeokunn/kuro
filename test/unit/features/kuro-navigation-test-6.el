;;; kuro-navigation-test-6.el --- Direct unit tests for kuro--update-prompt-positions  -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for kuro-navigation.el — Group 20: kuro--update-prompt-positions.
;;
;; kuro--update-prompt-positions is a pure O(M+N) merge helper.
;; Entry format: (TYPE ROW COL) or (TYPE ROW COL EXIT-CODE).  ROW is at index 1.
;; The function:
;;   - Fast-paths on nil marks (returns positions unchanged)
;;   - Sorts marks ascending by row then merges with positions (already sorted)
;;   - Caps the result at max-count entries

;;; Code:

(require 'kuro-navigation-test-support)

;;; Group 20: kuro--update-prompt-positions

(ert-deftest kuro-navigation--update-prompt-positions-nil-marks-returns-positions ()
  "`kuro--update-prompt-positions' fast-paths when marks is nil — returns positions unchanged."
  (let ((positions '(("p" 3 0) ("p" 7 0))))
    (should (equal (kuro--update-prompt-positions nil positions 10)
                   positions))))

(ert-deftest kuro-navigation--update-prompt-positions-nil-both-returns-nil ()
  "`kuro--update-prompt-positions' with nil marks and nil positions returns nil."
  (should (null (kuro--update-prompt-positions nil nil 10))))

(ert-deftest kuro-navigation--update-prompt-positions-empty-positions-returns-marks ()
  "`kuro--update-prompt-positions' with empty positions returns marks (up to max-count)."
  (let ((marks '(("p" 2 0) ("p" 5 0) ("p" 8 0))))
    (should (equal (kuro--update-prompt-positions marks nil 10)
                   marks))))

(ert-deftest kuro-navigation--update-prompt-positions-merges-in-ascending-row-order ()
  "`kuro--update-prompt-positions' interleaves marks and positions by ascending row."
  (let ((marks     '(("m" 1 0) ("m" 5 0)))
        (positions '(("p" 3 0) ("p" 7 0))))
    (should (equal (kuro--update-prompt-positions marks positions 10)
                   '(("m" 1 0) ("p" 3 0) ("m" 5 0) ("p" 7 0))))))

(ert-deftest kuro-navigation--update-prompt-positions-respects-max-count ()
  "`kuro--update-prompt-positions' returns at most max-count entries."
  (let ((marks     '(("m" 1 0) ("m" 3 0)))
        (positions '(("p" 5 0) ("p" 7 0) ("p" 9 0))))
    (should (= (length (kuro--update-prompt-positions marks positions 3)) 3))))

(ert-deftest kuro-navigation--update-prompt-positions-max-count-zero-returns-nil ()
  "`kuro--update-prompt-positions' with max-count 0 returns nil."
  (let ((marks '(("m" 1 0))))
    (should (null (kuro--update-prompt-positions marks nil 0)))))

(ert-deftest kuro-navigation--update-prompt-positions-position-wins-at-equal-row ()
  "`kuro--update-prompt-positions' places position before mark when rows are equal."
  ;; When mark-row == position-row, the `< mark-row position-row` test is false,
  ;; so position is pushed first (>= branch).
  (let ((marks     '(("m" 5 0)))
        (positions '(("p" 5 0))))
    (let ((result (kuro--update-prompt-positions marks positions 10)))
      (should (equal result '(("p" 5 0) ("m" 5 0)))))))

(ert-deftest kuro-navigation--update-prompt-positions-sorts-unsorted-marks ()
  "`kuro--update-prompt-positions' sorts marks by row before merging."
  ;; marks provided in reverse order; result must be ascending.
  (let ((marks '(("m" 8 0) ("m" 2 0) ("m" 5 0))))
    (let ((result (kuro--update-prompt-positions marks nil 10)))
      (should (equal result '(("m" 2 0) ("m" 5 0) ("m" 8 0)))))))

(ert-deftest kuro-navigation--update-prompt-positions-max-count-one-takes-lowest-row ()
  "`kuro--update-prompt-positions' with max-count 1 returns only the lowest-row entry."
  (let ((marks     '(("m" 4 0)))
        (positions '(("p" 2 0) ("p" 9 0))))
    (let ((result (kuro--update-prompt-positions marks positions 1)))
      (should (= (length result) 1))
      (should (= (cadr (car result)) 2)))))


(provide 'kuro-navigation-test-6)
;;; kuro-navigation-test-6.el ends here
