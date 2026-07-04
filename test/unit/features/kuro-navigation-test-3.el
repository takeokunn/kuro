;;; kuro-navigation-test-3.el --- Tests for command-output, history, failed-cmd navigation  -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for kuro-navigation.el — Groups 15-18.
;; Groups 1-14 are in kuro-navigation-test.el and kuro-navigation-test-2.el.
;; Covers: kuro--command-output-region, kuro-copy-command-output,
;;   kuro--prompt-line-text, kuro--command-history-entries,
;;   kuro--command-history-label, kuro--navigate-to-failed-command,
;;   kuro-next-failed-command, kuro-previous-failed-command.

;;; Code:

(require 'kuro-navigation-test-support)

;;; Group 15: kuro--command-output-region

(ert-deftest kuro-navigation--command-output-region-no-marks-returns-nil ()
  "kuro--command-output-region returns nil when no OSC 133 marks are present."
  (kuro-nav-test--with-content "line0\nline1\nline2\n" nil
    (forward-line 1)
    (should-not (kuro--command-output-region))))

(ert-deftest kuro-navigation--command-output-region-no-command-start-returns-nil ()
  "kuro--command-output-region returns nil when no command-start precedes point."
  (kuro-nav-test--with-content "line0\nline1\nline2\n"
      (list '("prompt-start" 0 0))
    (forward-line 2)
    (should-not (kuro--command-output-region))))

(ert-deftest kuro-navigation--command-output-region-no-next-prompt-uses-point-max ()
  "When there is no following prompt-start, region end is point-max."
  (kuro-nav-test--with-content "line0\nline1\nline2\nline3\n"
      (list '("command-start" 0 0))
    (forward-line 2)   ; cur-line = 2, command-start at row 0 <= 2
    (let ((region (kuro--command-output-region)))
      (should (consp region))
      (should (= (cdr region) (point-max))))))

(ert-deftest kuro-navigation--command-output-region-with-next-prompt-ends-at-prompt ()
  "When a prompt-start follows command-start, region end is that prompt row."
  (kuro-nav-test--with-content "line0\nline1\nline2\nline3\nline4\n"
      (list '("command-start" 0 0)
            '("prompt-start"  3 0))
    (forward-line 1)   ; cur-line=1, between command-start(0) and prompt-start(3)
    (let ((region (kuro--command-output-region)))
      (should (consp region))
      (save-excursion
        (goto-char (cdr region))
        (should (= (line-number-at-pos) 4))))))

(ert-deftest kuro-navigation--command-output-region-picks-nearest-command-start ()
  "kuro--command-output-region picks the nearest command-start at or before point."
  (kuro-nav-test--with-content "l0\nl1\nl2\nl3\nl4\n"
      (list '("command-start" 1 0)
            '("command-start" 3 0))
    (forward-line 4)   ; cur-line=4; both command-starts <= 4; nearest is row 3
    (let ((region (kuro--command-output-region)))
      (should (consp region))
      (save-excursion
        (goto-char (car region))
        (should (= (line-number-at-pos) 4))))))  ; row 3 -> line 4

;;; Group 16: kuro-copy-command-output

(ert-deftest kuro-navigation--copy-command-output-no-region-emits-message ()
  "kuro-copy-command-output messages when no command output region found."
  (kuro-nav-test--with-content "line0\nline1\n" nil
    (let (msgs)
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
        (kuro-copy-command-output))
      (should (= (length msgs) 1))
      (should (string-match-p "no command output" (car msgs))))))

(ert-deftest kuro-navigation--copy-command-output-copies-text-to-kill-ring ()
  "kuro-copy-command-output copies the command output region to the kill ring."
  (kuro-nav-test--with-content "line0\noutput-line\nline2\n"
      (list '("command-start" 0 0))
    (forward-line 1)   ; cur-line=1; command-start at row 0 <= 1
    (let ((kill-ring nil)
          msgs)
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
        (kuro-copy-command-output))
      (should (car kill-ring))
      (should (car msgs))
      (should (string-match-p "copied" (car msgs))))))

;;; Group 17: kuro--prompt-line-text and kuro--command-history-entries / label

(ert-deftest kuro-navigation--prompt-line-text-returns-trimmed-row ()
  "kuro--prompt-line-text returns trimmed text at the given 0-based row."
  (kuro-nav-test--with-content "  hello  \nworld\n" nil
    (should (equal (kuro--prompt-line-text 0) "hello"))))

(ert-deftest kuro-navigation--prompt-line-text-empty-row ()
  "kuro--prompt-line-text returns empty string for a blank row."
  (kuro-nav-test--with-content "\n\n" nil
    (should (equal (kuro--prompt-line-text 0) ""))))

(ert-deftest kuro-navigation--command-history-label-nil-exit ()
  "kuro--command-history-label with nil exit produces a marker followed by the text."
  (let ((result (kuro--command-history-label nil "ls -la")))
    (should (stringp result))
    (should (string-match-p "ls -la" result))
    ;; nil exit marker differs from success (exit=0)
    (should-not (equal result (kuro--command-history-label 0 "ls -la")))))

(ert-deftest kuro-navigation--command-history-label-zero-exit ()
  "kuro--command-history-label with exit=0 produces success marker + text."
  (let ((result (kuro--command-history-label 0 "echo ok")))
    (should (stringp result))
    (should (string-match-p "echo ok" result))))

(ert-deftest kuro-navigation--command-history-label-nonzero-exit ()
  "kuro--command-history-label with non-zero exit includes the exit code number."
  (let ((result (kuro--command-history-label 1 "bad-cmd")))
    (should (stringp result))
    (should (string-match-p "1" result))
    (should (string-match-p "bad-cmd" result))))

(ert-deftest kuro-navigation--command-history-label-empty-text-becomes-prompt ()
  "kuro--command-history-label uses '(prompt)' placeholder for empty text."
  (let ((result (kuro--command-history-label 0 "")))
    (should (string-match-p "(prompt)" result))))

(ert-deftest kuro-navigation--command-history-entries-empty-positions ()
  "kuro--command-history-entries returns nil when prompt-positions is empty."
  (kuro-nav-test--with-content "\n" nil
    (should-not (kuro--command-history-entries))))

(ert-deftest kuro-navigation--command-history-entries-no-command-end-returns-nil ()
  "kuro--command-history-entries returns nil when no command-end marks are present."
  (kuro-nav-test--with-content "line0\nline1\n"
      (list '("prompt-start" 0 0))
    (should-not (kuro--command-history-entries))))

(ert-deftest kuro-navigation--command-history-entries-pairs-prompt-with-command-end ()
  "kuro--command-history-entries returns one entry per paired prompt-start+command-end."
  (kuro-nav-test--with-content "$ ls\noutput\n"
      (list '("prompt-start" 0 0)
            '("command-end"  1 0 0))   ; exit code 0
    (let ((entries (kuro--command-history-entries)))
      (should (= (length entries) 1))
      (pcase-let ((`(,row ,exit ,_text) (car entries)))
        (should (= row 0))
        (should (= exit 0))))))

(ert-deftest kuro-navigation--command-history-entries-multiple-commands ()
  "kuro--command-history-entries handles multiple prompt+command-end pairs."
  (kuro-nav-test--with-content "cmd1\nout1\ncmd2\nout2\n"
      (list '("prompt-start" 0 0)
            '("command-end"  1 0 0)
            '("prompt-start" 2 0)
            '("command-end"  3 0 1))   ; exit code 1
    (let ((entries (kuro--command-history-entries)))
      (should (= (length entries) 2)))))

;;; Group 18: kuro--navigate-to-failed-command / kuro-next/previous-failed-command

(ert-deftest kuro-navigation--navigate-to-failed-command-finds-next-failure ()
  "kuro-next-failed-command jumps to the nearest command-end with non-zero exit."
  (kuro-nav-test--with-prompts
      (list '("command-end" 5 0 1)    ; failed, row 5
            '("command-end" 9 0 0))   ; success, row 9
    (forward-line 2)   ; cur-line=2
    (kuro-next-failed-command)
    (should (= (line-number-at-pos) 6))))  ; row 5 -> line 6

(ert-deftest kuro-navigation--navigate-to-failed-command-finds-previous-failure ()
  "kuro-previous-failed-command jumps to the nearest failed command before cursor."
  (kuro-nav-test--with-prompts
      (list '("command-end" 2 0 42)   ; failed, row 2
            '("command-end" 5 0 0))   ; success
    (forward-line 8)   ; cur-line=8
    (kuro-previous-failed-command)
    (should (= (line-number-at-pos) 3))))  ; row 2 -> line 3

(ert-deftest kuro-navigation--navigate-to-failed-command-skips-successes ()
  "kuro-next-failed-command ignores command-end entries with exit code 0."
  (kuro-nav-test--with-prompts
      (list '("command-end" 3 0 0)    ; success
            '("command-end" 7 0 2))   ; failure
    (forward-line 1)   ; cur-line=1
    (kuro-next-failed-command)
    (should (= (line-number-at-pos) 8))))  ; row 7 -> line 8

(ert-deftest kuro-navigation--navigate-to-failed-command-no-failure-emits-message ()
  "kuro-next-failed-command emits a message when no failed command exists."
  (kuro-nav-test--with-prompts
      (list '("command-end" 3 0 0))   ; success only
    (let (msgs)
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
        (kuro-next-failed-command))
      (should (= (length msgs) 1))
      (should (string-match-p "failed" (car msgs))))))

(ert-deftest kuro-navigation--previous-failed-command-no-failure-emits-message ()
  "kuro-previous-failed-command emits a message when no previous failure found."
  (kuro-nav-test--with-prompts
      (list '("command-end" 8 0 1))   ; failure is AFTER cursor
    (forward-line 2)
    (let (msgs)
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
        (kuro-previous-failed-command))
      (should (= (length msgs) 1))
      (should (string-match-p "failed" (car msgs))))))

(ert-deftest kuro-navigation--failed-command-message-includes-exit-code ()
  "kuro-next-failed-command includes the exit code in its navigation message."
  (kuro-nav-test--with-prompts
      (list '("command-end" 3 0 42))
    (forward-line 1)
    (let (msgs)
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
        (kuro-next-failed-command))
      (should (car msgs))
      (should (string-match-p "42" (car msgs))))))


(provide 'kuro-navigation-test-3)
;;; kuro-navigation-test-3.el ends here
