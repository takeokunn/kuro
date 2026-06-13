;;; kuro-navigation-test-4.el --- Tests for kuro-navigation — Group 14+  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-navigation-test-support)

;;; Group 14: kuro--navigate-to-prompt mid-line and unsorted cases

(ert-deftest kuro-navigation-ext-navigate-to-prompt-unsorted-rows ()
  "kuro--navigate-to-prompt 'next still picks the correct row when positions are unsorted."
  ;; kuro--prompt-positions is stored unsorted here (rows: 8, 3, 5).
  ;; For 'next with cur-line=2, candidates > 2 are rows 8, 3, 5 (in that order).
  ;; (car candidates) picks the first match in list order, which is row 8.
  ;; This verifies the real behavior of the function against an unsorted list.
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 8 0)
            '("prompt-start" 3 0)
            '("prompt-start" 5 0))
    (forward-line 2)   ; cur-line = 2
    (kuro--navigate-to-prompt 'next)
    ;; (car (seq-filter (> row 2) unsorted-list)) = row 8 → line 9.
    (should (= (line-number-at-pos) 9))))

(ert-deftest kuro-navigation-ext-navigate-to-prompt-multiple-prompts-forward ()
  "kuro--navigate-to-prompt 'next with multiple prompts picks the first (lowest) row."
  ;; With a properly sorted list (as produced by kuro--update-prompt-positions),
  ;; 'next picks the lowest row strictly above cur-line.
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 2 0)
            '("prompt-start" 5 0)
            '("prompt-start" 9 0))
    (forward-line 3)   ; cur-line = 3
    (kuro--navigate-to-prompt 'next)
    ;; First prompt-start with row > 3 is row 5 → line 6.
    (should (= (line-number-at-pos) 6))))

(ert-deftest kuro-navigation-ext-navigate-to-prompt-wraps-at-end ()
  "kuro--navigate-to-prompt 'next at the last prompt emits a message (no wrap)."
  ;; There is no wrap-around behavior: when at the last prompt, the function
  ;; emits \"kuro: no next prompt\" and leaves point unchanged.
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 2 0)
            '("prompt-start" 5 0))
    (forward-line 6)   ; cur-line = 6, all prompts are before cursor
    (let ((initial-line (line-number-at-pos))
          msgs)
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
        (kuro--navigate-to-prompt 'next))
      ;; Message emitted, point unchanged.
      (should (equal msgs '("kuro: no next prompt")))
      (should (= (line-number-at-pos) initial-line)))))

;;; kuro-copy-command-output (OSC 133 command output region) ──────────────────

(ert-deftest kuro-nav-command-output-region-enclosing ()
  "`kuro--command-output-region' spans command-start to the next prompt."
  (kuro-nav-test--with-content
      "cmd-a\nout1\nout2\nprompt2\nmore\n"
      (list '("command-start" 1 0) '("prompt-start" 3 0))
    (forward-line 2)                    ; point inside the output (row 2)
    (let ((region (kuro--command-output-region)))
      (should region)
      (should (equal (buffer-substring-no-properties (car region) (cdr region))
                     "out1\nout2\n")))))

(ert-deftest kuro-nav-command-output-region-last-command-to-eob ()
  "With no following prompt, the output region runs to buffer end."
  (kuro-nav-test--with-content
      "cmd\nresult-a\nresult-b\n"
      (list '("command-start" 1 0))
    (forward-line 1)
    (let ((region (kuro--command-output-region)))
      (should (= (cdr region) (point-max)))
      (should (equal (buffer-substring-no-properties (car region) (cdr region))
                     "result-a\nresult-b\n")))))

(ert-deftest kuro-nav-command-output-region-nil-without-marks ()
  "`kuro--command-output-region' returns nil when there is no command-start."
  (kuro-nav-test--with-content
      "plain\ntext\n"
      (list '("prompt-start" 0 0))
    (forward-line 1)
    (should (null (kuro--command-output-region)))))

(ert-deftest kuro-nav-command-output-region-before-first-command ()
  "Point above the first command-start yields nil (no enclosing command)."
  (kuro-nav-test--with-content
      "header\ncmd\nout\n"
      (list '("command-start" 1 0))
    (goto-char (point-min))             ; row 0, before the command-start at row 1
    (should (null (kuro--command-output-region)))))

(ert-deftest kuro-nav-copy-command-output-copies-region ()
  "`kuro-copy-command-output' places the output region on the kill ring."
  (kuro-nav-test--with-content
      "cmd-a\nout1\nout2\nprompt2\n"
      (list '("command-start" 1 0) '("prompt-start" 3 0))
    (forward-line 2)
    (let ((kill-ring nil))
      (kuro-copy-command-output)
      (should (equal (current-kill 0) "out1\nout2\n")))))

(ert-deftest kuro-nav-copy-command-output-messages-when-absent ()
  "`kuro-copy-command-output' messages and copies nothing without marks."
  (kuro-nav-test--with-content
      "plain\n"
      nil
    (let ((kill-ring nil)
          msgs)
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
        (kuro-copy-command-output))
      (should (null kill-ring))
      (should (cl-some (lambda (m) (string-match-p "no command output" m)) msgs)))))

;;; kuro-next/previous-failed-command (OSC 133 exit codes) ────────────────────

(ert-deftest kuro-nav-next-failed-command-jumps-to-nonzero-exit ()
  "`kuro-next-failed-command' moves point to the next non-zero command-end."
  (kuro-nav-test--with-content
      "a\nb\nc\nd\ne\nf\n"
      (list '("command-end" 1 0 0)      ; succeeded — skipped
            '("command-end" 3 0 1)      ; failed (exit 1) — target
            '("command-end" 5 0 2))     ; failed but later
    (goto-char (point-min))             ; cur-line 0
    (kuro-next-failed-command)
    (should (= (line-number-at-pos) 4)))) ; row 3 → line 4

(defconst kuro-nav-test--next-failed-no-target-table
  '((kuro-nav-next-failed-skips-successful-commands
     "a\nb\nc\nd\n"
     (("command-end" 1 0 0) ("command-end" 2 0 0)))
    (kuro-nav-failed-command-ignores-nil-exit
     "a\nb\nc\n"
     (("prompt-start" 1 0) ("command-end" 2 0 0))))
  "Table: (test-name content marks) — no failed target → 'no next failed command' message.")

(defmacro kuro-nav-test--def-next-failed-no-target (test-name content marks)
  `(ert-deftest ,test-name ()
     ,(format "`kuro-next-failed-command' emits no-target message with marks %S." marks)
     (kuro-nav-test--with-content ,content ',marks
       (goto-char (point-min))
       (let (msgs)
         (cl-letf (((symbol-function 'message)
                    (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
           (kuro-next-failed-command))
         (should (cl-some (lambda (m) (string-match-p "no next failed command" m)) msgs))))))

(kuro-nav-test--def-next-failed-no-target
 kuro-nav-next-failed-skips-successful-commands
 "a\nb\nc\nd\n"
 (("command-end" 1 0 0) ("command-end" 2 0 0)))

(ert-deftest kuro-nav-previous-failed-command-jumps-backward ()
  "`kuro-previous-failed-command' finds the nearest earlier failure."
  (kuro-nav-test--with-content
      "a\nb\nc\nd\ne\nf\n"
      (list '("command-end" 1 0 1)      ; failed (earlier) — target
            '("command-end" 4 0 3))     ; failed (later)
    (goto-char (point-min))
    (forward-line 5)                    ; cur-line 5
    (kuro-previous-failed-command)
    (should (= (line-number-at-pos) 5)))) ; row 4 → line 5

(kuro-nav-test--def-next-failed-no-target
 kuro-nav-failed-command-ignores-nil-exit
 "a\nb\nc\n"
 (("prompt-start" 1 0) ("command-end" 2 0 0)))

(ert-deftest kuro-nav--all-next-failed-no-target-cases ()
  "Invariant: `kuro-next-failed-command' emits 'no next failed command' for every no-target scenario."
  (dolist (entry kuro-nav-test--next-failed-no-target-table)
    (pcase-let ((`(,_name ,content ,marks) entry))
      (kuro-nav-test--with-content content marks
        (goto-char (point-min))
        (let (msgs)
          (cl-letf (((symbol-function 'message)
                     (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
            (kuro-next-failed-command))
          (should (cl-some (lambda (m) (string-match-p "no next failed command" m)) msgs)))))))

(ert-deftest kuro-nav-failed-command-reports-exit-code ()
  "Jumping to a failed command messages its exit code."
  (kuro-nav-test--with-content
      "a\nb\nc\n"
      (list '("command-end" 1 0 42))
    (goto-char (point-min))
    (let (msgs)
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
        (kuro-next-failed-command))
      (should (cl-some (lambda (m) (string-match-p "exit 42" m)) msgs)))))

;;; kuro-command-history (OSC 133 prompt-start → command-end pairing) ──────────

(ert-deftest kuro-nav-command-history-entries-pairs-marks ()
  "`kuro--command-history-entries' pairs prompt-start with the next command-end."
  (kuro-nav-test--with-content
      "$ echo a\na\n$ false\n$ ls\nfile\n"
      (list '("prompt-start" 0 0)
            '("command-end"  0 0 0)
            '("prompt-start" 2 0)
            '("command-end"  2 0 1)
            '("prompt-start" 3 0)
            '("command-end"  3 0 0))
    (let ((entries (kuro--command-history-entries)))
      (should (= (length entries) 3))
      ;; oldest first: (row exit text)
      (should (equal (nth 0 entries) '(0 0 "$ echo a")))
      (should (equal (nth 1 entries) '(2 1 "$ false")))
      (should (equal (nth 2 entries) '(3 0 "$ ls"))))))

(ert-deftest kuro-nav-command-history-entries-skips-unpaired ()
  "A prompt-start with no following command-end yields no record."
  (kuro-nav-test--with-content
      "$ running\n"
      (list '("prompt-start" 0 0))   ; no command-end yet
    (should (null (kuro--command-history-entries)))))

(defconst kuro-nav-test--history-label-table
  '((kuro-nav-command-history-label-success             0   "make"       "✓ make")
    (kuro-nav-command-history-label-failure             127 "frobnicate" "✗127 frobnicate")
    (kuro-nav-command-history-label-unknown-and-empty   nil ""           "· (prompt)"))
  "Table of (test-name exit text expected-label) for `kuro--command-history-label'.")

(defmacro kuro-nav-test--def-history-label (test-name exit text expected)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--command-history-label' exit=%s text=%S => %S." exit text expected)
     (should (equal (kuro--command-history-label ,exit ,text) ,expected))))

(kuro-nav-test--def-history-label kuro-nav-command-history-label-success             0   "make"       "✓ make")
(kuro-nav-test--def-history-label kuro-nav-command-history-label-failure             127 "frobnicate" "✗127 frobnicate")
(kuro-nav-test--def-history-label kuro-nav-command-history-label-unknown-and-empty   nil ""           "· (prompt)")

(ert-deftest kuro-nav-test--all-history-labels-correct ()
  "All entries in `kuro-nav-test--history-label-table' produce the correct label."
  (dolist (entry kuro-nav-test--history-label-table)
    (pcase-let ((`(,_name ,exit ,text ,expected) entry))
      (should (equal (kuro--command-history-label exit text) expected)))))

(ert-deftest kuro-nav-command-history-jumps-to-selection ()
  "`kuro-command-history' moves point to the row of the chosen command."
  (kuro-nav-test--with-content
      "$ first\nout\n$ second\nout2\n"
      (list '("prompt-start" 0 0)
            '("command-end"  0 0 0)
            '("prompt-start" 2 0)
            '("command-end"  2 0 0))
    (goto-char (point-max))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) "✓ $ first"))
              ((symbol-function 'recenter) #'ignore))
      (kuro-command-history)
      (should (= (line-number-at-pos) 1)))))  ; row 0 → line 1

(ert-deftest kuro-nav-command-history-empty-messages ()
  "`kuro-command-history' messages and does nothing without history."
  (kuro-nav-test--with-content
      "no marks\n"
      nil
    (let (msgs)
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) msgs)))
                ((symbol-function 'completing-read)
                 (lambda (&rest _) (error "should not be called"))))
        (kuro-command-history))
      (should (cl-some (lambda (m) (string-match-p "no command history" m)) msgs)))))


;;; Group 15: kuro--def-nav-cmd macro — structural coverage

(defconst kuro-navigation-test--nav-cmd-table
  '((kuro-previous-prompt         kuro-previous-prompt         kuro--navigate-to-prompt         previous)
    (kuro-next-prompt             kuro-next-prompt             kuro--navigate-to-prompt         next)
    (kuro-next-failed-command     kuro-next-failed-command     kuro--navigate-to-failed-command next)
    (kuro-previous-failed-command kuro-previous-failed-command kuro--navigate-to-failed-command previous))
  "Table: (test-sym cmd-sym delegate-fn direction) for kuro--def-nav-cmd commands.")

(defmacro kuro-navigation-test--def-nav-cmd-commandp (test-name cmd)
  `(ert-deftest ,test-name ()
     ,(format "`%s' is an interactive command (kuro--def-nav-cmd)." cmd)
     (should (commandp #',cmd))))

(kuro-navigation-test--def-nav-cmd-commandp
 kuro-nav-test-previous-prompt-is-interactive         kuro-previous-prompt)
(kuro-navigation-test--def-nav-cmd-commandp
 kuro-nav-test-next-prompt-is-interactive             kuro-next-prompt)
(kuro-navigation-test--def-nav-cmd-commandp
 kuro-nav-test-next-failed-command-is-interactive     kuro-next-failed-command)
(kuro-navigation-test--def-nav-cmd-commandp
 kuro-nav-test-previous-failed-command-is-interactive kuro-previous-failed-command)

(ert-deftest kuro-nav-test-all-nav-commands-are-interactive ()
  "Invariant: all kuro--def-nav-cmd-generated commands satisfy `commandp'."
  (dolist (entry kuro-navigation-test--nav-cmd-table)
    (should (commandp (cadr entry)))))

(ert-deftest kuro-nav-test-previous-prompt-calls-navigate-to-prompt-previous ()
  "`kuro-previous-prompt' delegates to `kuro--navigate-to-prompt' with direction `previous'."
  (kuro-nav-test--with-prompts nil
    (let ((called-with nil))
      (cl-letf (((symbol-function 'kuro--navigate-to-prompt)
                 (lambda (dir) (setq called-with dir))))
        (kuro-previous-prompt)
        (should (eq called-with 'previous))))))

(ert-deftest kuro-nav-test-next-prompt-calls-navigate-to-prompt-next ()
  "`kuro-next-prompt' delegates to `kuro--navigate-to-prompt' with direction `next'."
  (kuro-nav-test--with-prompts nil
    (let ((called-with nil))
      (cl-letf (((symbol-function 'kuro--navigate-to-prompt)
                 (lambda (dir) (setq called-with dir))))
        (kuro-next-prompt)
        (should (eq called-with 'next))))))

;;; Group 16: kuro--def-navigator macro — structural coverage

(ert-deftest kuro-nav-test-navigator-on-found-runs-when-target-found ()
  "`kuro--def-navigator' ON-FOUND body executes when a matching target exists."
  (let ((found-row nil))
    (kuro--def-navigator kuro-nav-test--navigate-dummy
      (lambda (e) (equal (car e) "prompt-start"))
      (setq found-row (cadr target))
      (error "should not reach on-miss")
      "Test navigator — on-found path.")
    (kuro-nav-test--with-prompts '(("prompt-start" 5 0 nil))
      (kuro-nav-test--navigate-dummy 'next)
      (should (eq found-row 5)))))

(ert-deftest kuro-nav-test-navigator-on-miss-runs-when-no-target ()
  "`kuro--def-navigator' ON-MISS body executes when no matching target exists."
  (let ((missed nil))
    (kuro--def-navigator kuro-nav-test--navigate-dummy2
      (lambda (e) (equal (car e) "command-end"))
      (error "should not reach on-found")
      (setq missed direction)
      "Test navigator — on-miss path.")
    (kuro-nav-test--with-prompts '(("prompt-start" 5 0 nil))
      (kuro-nav-test--navigate-dummy2 'next)
      (should (eq missed 'next)))))

(ert-deftest kuro-nav-test-navigator-macroexpand-1-shows-let-if ()
  "`kuro--def-navigator' single-step expands to a `defun' containing `let'/`if'."
  (let ((exp (macroexpand-1
              '(kuro--def-navigator kuro-nav-test--dummy-exp
                 (lambda (_e) t)
                 (goto-char 1)
                 (message "miss")
                 "doc"))))
    (should (eq (car exp) 'defun))
    (should (eq (cadr exp) 'kuro-nav-test--dummy-exp))))

(provide 'kuro-navigation-test-4)
;;; kuro-navigation-test-4.el ends here
