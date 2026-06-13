;;; kuro-navigation-test-3.el --- Tests for kuro-navigation.el — prompt-line-text, navigate-to-failed  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-navigation-test-support)

;;; ── kuro--prompt-line-text ────────────────────────────────────────────────────

(ert-deftest kuro-nav-prompt-line-text-returns-trimmed-row-text ()
  "`kuro--prompt-line-text' returns trimmed text of the given 0-based row."
  (kuro-nav-test--with-content
      "$ git status  \nsecond line\n"
      nil
    (should (equal (kuro--prompt-line-text 0) "$ git status"))))

(ert-deftest kuro-nav-prompt-line-text-row-1 ()
  "`kuro--prompt-line-text' returns text from a non-zero row."
  (kuro-nav-test--with-content
      "row0\n  row1 text  \nrow2\n"
      nil
    (should (equal (kuro--prompt-line-text 1) "row1 text"))))

;;; ── kuro--navigate-to-failed-command ─────────────────────────────────────────

(ert-deftest kuro-nav-failed-command-previous-jumps-to-row ()
  "`kuro--navigate-to-failed-command' 'previous moves point to the last failed row < current."
  (kuro-nav-test--with-content
      "ok\nfailed\nok2\ncurrent\n"
      (list '("command-end" 0 0 0)
            '("command-end" 1 0 1)   ; row 1, exit 1 (failure)
            '("command-end" 2 0 0))
    (forward-line 3)  ; current row = 3, so row 1 is "previous"
    (let (msgs)
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
        (kuro--navigate-to-failed-command 'previous)))
    (should (= (line-number-at-pos) 2))))  ; row 1 = line 2

(ert-deftest kuro-nav-failed-command-next-jumps-to-row ()
  "`kuro--navigate-to-failed-command' 'next moves point to the first failed row > current."
  (kuro-nav-test--with-content
      "current\nok\nfailed\n"
      (list '("command-end" 1 0 0)
            '("command-end" 2 0 2))  ; row 2, exit 2 (failure)
    (goto-char (point-min))  ; row 0
    (let (msgs)
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
        (kuro--navigate-to-failed-command 'next)))
    (should (= (line-number-at-pos) 3))))  ; row 2 = line 3

(ert-deftest kuro-nav-failed-command-no-match-messages ()
  "`kuro--navigate-to-failed-command' messages \"no next failed command\" when none found."
  (kuro-nav-test--with-content
      "ok\n"
      (list '("command-end" 0 0 0))  ; exit 0, not a failure
    (goto-char (point-min))
    (let (msgs)
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
        (kuro--navigate-to-failed-command 'next))
      (should (cl-some (lambda (m) (string-match-p "no next failed" m)) msgs)))))

;;; ── kuro--find-mark-in-direction ─────────────────────────────────────────────

(ert-deftest kuro-nav-find-mark-previous-returns-closest-before-point ()
  "`kuro--find-mark-in-direction' 'previous returns the closest entry before current row."
  (kuro-nav-test--with-prompts
    (list '("prompt-start" 2 0 nil)
          '("prompt-start" 5 0 nil)
          '("prompt-start" 9 0 nil))
    (forward-line 7)   ; current row = 7; rows 2 and 5 are candidates
    (let ((result (kuro--find-mark-in-direction
                   'previous (lambda (e) (equal (car e) "prompt-start")))))
      (should result)
      (should (= (cadr result) 5)))))   ; row 5 is closest before row 7

(ert-deftest kuro-nav-find-mark-next-returns-closest-after-point ()
  "`kuro--find-mark-in-direction' 'next returns the closest entry after current row."
  (kuro-nav-test--with-prompts
    (list '("prompt-start" 3 0 nil)
          '("prompt-start" 8 0 nil)
          '("prompt-start" 12 0 nil))
    (forward-line 5)   ; current row = 5; rows 8 and 12 are candidates
    (let ((result (kuro--find-mark-in-direction
                   'next (lambda (e) (equal (car e) "prompt-start")))))
      (should result)
      (should (= (cadr result) 8)))))   ; row 8 is closest after row 5

(ert-deftest kuro-nav-find-mark-returns-nil-when-no-match ()
  "`kuro--find-mark-in-direction' returns nil when TYPE-PRED matches nothing."
  (kuro-nav-test--with-prompts
    (list '("prompt-start" 4 0 nil))
    (forward-line 6)   ; current row = 6; no entries after row 6
    (should-not (kuro--find-mark-in-direction
                 'next (lambda (e) (equal (car e) "prompt-start"))))))

(ert-deftest kuro-nav-find-mark-type-pred-filters-correctly ()
  "`kuro--find-mark-in-direction' only returns entries matching TYPE-PRED."
  (kuro-nav-test--with-prompts
    (list '("command-end"  2 0 0)
          '("prompt-start" 4 0 nil)
          '("command-end"  6 0 1))
    (forward-line 1)   ; current row = 1
    (let ((result (kuro--find-mark-in-direction
                   'next (lambda (e) (equal (car e) "command-end")))))
      (should result)
      (should (equal (car result) "command-end"))
      (should (= (cadr result) 2)))))

(provide 'kuro-navigation-test-3)
;;; kuro-navigation-test-3.el ends here
