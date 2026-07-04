;;; kuro-navigation-test-5.el --- Direct unit tests for kuro--find-mark-in-direction  -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for kuro-navigation.el — Group 19: kuro--find-mark-in-direction.
;;
;; kuro--find-mark-in-direction is a pure filtering helper used by all
;; kuro--def-navigator-generated commands.  Its indirect coverage through
;; those callers is high, but this file adds direct tests that pin the
;; semantics of:
;;   - direction 'previous: picks the LAST entry before current line
;;   - direction 'next:     picks the FIRST entry after current line
;;   - type-pred filtering: entries rejected by type-pred are excluded
;;   - boundary conditions: nil when no matches

;;; Code:

(require 'kuro-navigation-test-support)

;;; Group 19: kuro--find-mark-in-direction

(ert-deftest kuro-navigation--find-mark-no-positions-returns-nil ()
  "kuro--find-mark-in-direction returns nil when kuro--prompt-positions is nil."
  (kuro-nav-test--with-prompts nil
    (forward-line 5)
    (should-not (kuro--find-mark-in-direction 'next #'identity))
    (should-not (kuro--find-mark-in-direction 'previous #'identity))))

(ert-deftest kuro-navigation--find-mark-next-returns-first-after-point ()
  "kuro--find-mark-in-direction 'next returns the first entry whose row > cur-line."
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 3 0)
            '("prompt-start" 7 0)
            '("prompt-start" 12 0))
    (forward-line 4)   ; cur-line = 4, so row > 4 means rows 7 and 12
    (let ((result (kuro--find-mark-in-direction 'next
                    (lambda (e) (equal (car e) "prompt-start")))))
      ;; First entry after line 4 is row 7.
      (should (equal result '("prompt-start" 7 0))))))

(ert-deftest kuro-navigation--find-mark-previous-returns-last-before-point ()
  "kuro--find-mark-in-direction 'previous returns the closest entry whose row < cur-line."
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 2 0)
            '("prompt-start" 5 0)
            '("prompt-start" 9 0))
    (forward-line 10)  ; cur-line = 10, so row < 10 means rows 2, 5, 9
    (let ((result (kuro--find-mark-in-direction 'previous
                    (lambda (e) (equal (car e) "prompt-start")))))
      ;; Last entry before line 10 is row 9.
      (should (equal result '("prompt-start" 9 0))))))

(ert-deftest kuro-navigation--find-mark-type-pred-filters-entries ()
  "kuro--find-mark-in-direction respects type-pred: only matching types are returned."
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 2 0)
            '("command-end"  4 0 0)
            '("prompt-start" 6 0))
    (forward-line 0)   ; cur-line = 0, all entries have row > 0
    ;; next + command-end pred → row 4 only
    (let ((result (kuro--find-mark-in-direction 'next
                    (lambda (e) (equal (car e) "command-end")))))
      (should (equal result '("command-end" 4 0 0))))))

(ert-deftest kuro-navigation--find-mark-next-no-candidate-returns-nil ()
  "kuro--find-mark-in-direction 'next returns nil when all entries are before point."
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 1 0)
            '("prompt-start" 3 0))
    (forward-line 10)  ; cur-line = 10, all rows < 10
    (should-not (kuro--find-mark-in-direction 'next
                  (lambda (e) (equal (car e) "prompt-start"))))))

(ert-deftest kuro-navigation--find-mark-previous-no-candidate-returns-nil ()
  "kuro--find-mark-in-direction 'previous returns nil when all entries are after point."
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 8 0)
            '("prompt-start" 12 0))
    (forward-line 2)   ; cur-line = 2, all rows > 2
    (should-not (kuro--find-mark-in-direction 'previous
                  (lambda (e) (equal (car e) "prompt-start"))))))

(ert-deftest kuro-navigation--find-mark-excludes-entry-at-current-line ()
  "kuro--find-mark-in-direction excludes entries exactly at cur-line (strict < / >)."
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 5 0)
            '("prompt-start" 8 0))
    (forward-line 5)   ; cur-line = 5; entry at row 5 is NOT < 5, so excluded by 'previous
    (should-not (kuro--find-mark-in-direction 'previous
                  (lambda (e) (equal (car e) "prompt-start"))))
    ;; entry at row 5 is NOT > 5, so excluded by 'next; row 8 is returned
    (let ((result (kuro--find-mark-in-direction 'next
                    (lambda (e) (equal (car e) "prompt-start")))))
      (should (equal result '("prompt-start" 8 0))))))

(ert-deftest kuro-navigation--find-mark-previous-picks-nearest-not-first ()
  "kuro--find-mark-in-direction 'previous picks (car (last matches)), i.e. closest."
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 1 0)
            '("prompt-start" 4 0)
            '("prompt-start" 7 0))
    (forward-line 10)  ; cur-line=10, all rows < 10, sorted list keeps order
    (let ((result (kuro--find-mark-in-direction 'previous
                    (lambda (e) (equal (car e) "prompt-start")))))
      ;; All three match; (car (last matches)) picks row 7.
      (should (equal result '("prompt-start" 7 0))))))


(provide 'kuro-navigation-test-5)
;;; kuro-navigation-test-5.el ends here
