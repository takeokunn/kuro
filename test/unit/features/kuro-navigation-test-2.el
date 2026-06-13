;;; kuro-navigation-test-2.el --- Tests for kuro-navigation (part 2)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-navigation-test-support)

;;; Group 8: kuro--with-focus-guard macro

(ert-deftest kuro-navigation--focus-guard-executes-when-all-conditions-met ()
  "kuro--with-focus-guard runs body when mode, initialized, and focus-events are all true."
  (let ((kuro--initialized t)
        (ran nil))
    (cl-letf (((symbol-function 'derived-mode-p)        (lambda (&rest _) t))
              ((symbol-function 'kuro--get-focus-events) (lambda () t)))
      (kuro--with-focus-guard (setq ran t))
      (should ran))))

(defconst kuro-navigation-test--focus-guard-noop-table
  '((kuro-navigation--focus-guard-noop-when-not-initialized  nil t   t)
    (kuro-navigation--focus-guard-noop-when-focus-events-off t   nil t)
    (kuro-navigation--focus-guard-noop-when-wrong-mode       t   t   nil))
  "Table of (test-name initialized focus-events-p mode-p): each one condition false → body skipped.")

(defmacro kuro-navigation-test--def-focus-guard-noop
    (test-name initialized focus-events-p mode-p)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--with-focus-guard' skips body: initialized=%s focus=%s mode=%s."
              initialized focus-events-p mode-p)
     (let ((kuro--initialized ,initialized) (ran nil))
       (cl-letf (((symbol-function 'derived-mode-p)        (lambda (&rest _) ,mode-p))
                 ((symbol-function 'kuro--get-focus-events) (lambda () ,focus-events-p)))
         (kuro--with-focus-guard (setq ran t))
         (should-not ran)))))

(kuro-navigation-test--def-focus-guard-noop
 kuro-navigation--focus-guard-noop-when-not-initialized  nil t   t)
(kuro-navigation-test--def-focus-guard-noop
 kuro-navigation--focus-guard-noop-when-focus-events-off t   nil t)
(kuro-navigation-test--def-focus-guard-noop
 kuro-navigation--focus-guard-noop-when-wrong-mode       t   t   nil)

(ert-deftest kuro-navigation--focus-guard-all-noop-conditions ()
  "Invariant: focus-guard skips body whenever any one guard condition is false."
  (dolist (entry kuro-navigation-test--focus-guard-noop-table)
    (pcase-let ((`(,_name ,initialized ,focus-events-p ,mode-p) entry))
      (let ((kuro--initialized initialized) (ran nil))
        (cl-letf (((symbol-function 'derived-mode-p)        (lambda (&rest _) mode-p))
                  ((symbol-function 'kuro--get-focus-events) (lambda () focus-events-p)))
          (kuro--with-focus-guard (setq ran t))
          (should-not ran))))))

(ert-deftest kuro-navigation--focus-guard-splices-multiple-forms ()
  "kuro--with-focus-guard executes all body forms in sequence."
  (let ((kuro--initialized t)
        (log nil))
    (cl-letf (((symbol-function 'derived-mode-p)        (lambda (&rest _) t))
              ((symbol-function 'kuro--get-focus-events) (lambda () t)))
      (kuro--with-focus-guard (push 1 log) (push 2 log))
      (should (equal (nreverse log) '(1 2))))))

(ert-deftest kuro-navigation-focus-handlers-are-bound ()
  "Both focus handlers are fboundp after macro expansion."
  (should (fboundp 'kuro--handle-focus-in))
  (should (fboundp 'kuro--handle-focus-out)))

;;; Group 9: kuro--goto-prompt-row — row N places point at line N+1

(defconst kuro-nav-test--goto-prompt-row-line-table
  '((kuro-navigation--goto-prompt-row-zero-places-at-first-line 0 1)
    (kuro-navigation--goto-prompt-row-moves-to-correct-line     5 6)
    (kuro-navigation--goto-prompt-row-one                       1 2)
    (kuro-navigation-ext-goto-prompt-row-moves-to-prompt-row    7 8))
  "Table: (test-name row expected-line) for `kuro--goto-prompt-row' invariant.")

(defmacro kuro-nav-test--def-goto-prompt-row (test-name row expected-line)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--goto-prompt-row' %d places point at line %d." row expected-line)
     (with-temp-buffer
       (dotimes (_ 20) (insert "\n"))
       (goto-char (point-min))
       (kuro--goto-prompt-row ,row)
       (should (= (line-number-at-pos) ,expected-line)))))

(kuro-nav-test--def-goto-prompt-row kuro-navigation--goto-prompt-row-zero-places-at-first-line 0 1)
(kuro-nav-test--def-goto-prompt-row kuro-navigation--goto-prompt-row-moves-to-correct-line     5 6)
(kuro-nav-test--def-goto-prompt-row kuro-navigation--goto-prompt-row-one                       1 2)
(kuro-nav-test--def-goto-prompt-row kuro-navigation-ext-goto-prompt-row-moves-to-prompt-row    7 8)

(ert-deftest kuro-navigation--all-goto-prompt-row-cases ()
  "Invariant: `kuro--goto-prompt-row' N always places point at line N+1."
  (dolist (entry kuro-nav-test--goto-prompt-row-line-table)
    (pcase-let ((`(,_name ,row ,expected-line) entry))
      (with-temp-buffer
        (dotimes (_ 20) (insert "\n"))
        (goto-char (point-min))
        (kuro--goto-prompt-row row)
        (should (= (line-number-at-pos) expected-line))))))

(ert-deftest kuro-navigation--previous-prompt-from-row-zero-no-candidate ()
  "kuro-previous-prompt at row 0 (cur-line=0) finds no prompt before it."
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 3 0))
    ;; cursor at line 1 → cur-line = 0; no prompt at row < 0
    (goto-char (point-min))
    (let (msgs)
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
        (kuro-previous-prompt))
      (should (equal msgs '("kuro: no previous prompt"))))))

(ert-deftest kuro-navigation--update-prompt-positions-preserves-duplicates ()
  "kuro--update-prompt-positions keeps duplicate rows when both lists have same row."
  ;; Two marks at row 3 — one from each list — both should appear in result.
  (let* ((existing '(("prompt-start" 3 0)))
         (new-marks '(("prompt-end" 3 0)))
         (result (kuro--update-prompt-positions new-marks existing 100)))
    (should (= (length result) 2))
    (should (cl-every (lambda (e) (= (cadr e) 3)) result))))

(ert-deftest kuro-navigation--navigate-to-prompt-previous-single-prompt-at-start ()
  "Navigation 'previous with a single prompt at row 0 from row 5 reaches row 0."
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 0 0))
    (forward-line 5)   ; cur-line = 5
    (kuro--navigate-to-prompt 'previous)
    ;; row 0 → line 1
    (should (= (line-number-at-pos) 1))))

;;; Group 10: kuro--goto-prompt-row boundary conditions

(ert-deftest kuro-navigation--goto-prompt-row-beyond-buffer-end ()
  "kuro--goto-prompt-row beyond buffer line count lands at last line without error."
  (with-temp-buffer
    ;; Insert exactly 5 lines.
    (dotimes (_ 5) (insert "\n"))
    (goto-char (point-min))
    ;; forward-line clamps at end of buffer — no error.
    (should-not (condition-case err
                    (progn (kuro--goto-prompt-row 100) nil)
                  (error err)))
    ;; Point must be at or before point-max.
    (should (<= (point) (point-max)))))

;;; Group 11: kuro--def-focus-handler macro structure

(ert-deftest kuro-navigation--def-focus-handler-names-function ()
  "kuro--def-focus-handler creates a function with the given NAME."
  ;; kuro--handle-focus-in and kuro--handle-focus-out were created by the macro
  ;; at load time; verify they are fboundp.
  (should (fboundp 'kuro--handle-focus-in))
  (should (fboundp 'kuro--handle-focus-out)))

(defconst kuro-nav-test--focus-dispatch-table
  '((kuro-navigation--def-focus-handler-sends-correct-sequence-in  kuro--handle-focus-in  t   "\e[I")
    (kuro-navigation--def-focus-handler-sends-correct-sequence-out kuro--handle-focus-out t   "\e[O")
    (kuro-navigation--handle-focus-in-noop-when-wrong-mode         kuro--handle-focus-in  nil nil)
    (kuro-navigation--handle-focus-out-noop-when-wrong-mode        kuro--handle-focus-out nil nil))
  "Table of (test-name handler-fn mode-p expected-seq) for focus handler dispatch (2×2 matrix).")

(defmacro kuro-nav-test--def-focus-dispatch (test-name handler-fn mode-p expected-seq)
  `(ert-deftest ,test-name ()
     ,(format "`%s' (mode-p=%s) %s." handler-fn mode-p
              (if expected-seq (format "sends %S" expected-seq) "is a no-op"))
     (let ((kuro--initialized t)
           (sent nil))
       (cl-letf (((symbol-function 'derived-mode-p)        (lambda (&rest _) ,mode-p))
                 ((symbol-function 'kuro--get-focus-events) (lambda () t))
                 ((symbol-function 'kuro--send-key)         (lambda (s) (setq sent s))))
         (,handler-fn)
         ,(if expected-seq
              `(should     (string= sent ,expected-seq))
            `(should-not sent))))))

(kuro-nav-test--def-focus-dispatch kuro-navigation--def-focus-handler-sends-correct-sequence-in  kuro--handle-focus-in  t   "\e[I")
(kuro-nav-test--def-focus-dispatch kuro-navigation--def-focus-handler-sends-correct-sequence-out kuro--handle-focus-out t   "\e[O")
(kuro-nav-test--def-focus-dispatch kuro-navigation--handle-focus-in-noop-when-wrong-mode         kuro--handle-focus-in  nil nil)
(kuro-nav-test--def-focus-dispatch kuro-navigation--handle-focus-out-noop-when-wrong-mode        kuro--handle-focus-out nil nil)

(ert-deftest kuro-navigation--all-focus-dispatch-cases-correct ()
  "Every entry in `kuro-nav-test--focus-dispatch-table' dispatches correctly."
  (dolist (entry kuro-nav-test--focus-dispatch-table)
    (pcase-let ((`(,_name ,handler-fn ,mode-p ,expected-seq) entry))
      (let ((kuro--initialized t)
            (sent nil))
        (cl-letf (((symbol-function 'derived-mode-p)        (lambda (&rest _) mode-p))
                  ((symbol-function 'kuro--get-focus-events) (lambda () t))
                  ((symbol-function 'kuro--send-key)         (lambda (s) (setq sent s))))
          (funcall handler-fn)
          (if expected-seq
              (should     (string= sent expected-seq))
            (should-not sent)))))))

;;; Group 12: Navigation with non-zero COL values

(ert-deftest kuro-navigation--col-value-is-ignored-by-navigation ()
  "Navigation uses ROW (cadr) only; COL (caddr) is irrelevant."
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 3 99)   ; COL=99 — should not affect navigation
            '("prompt-start" 6 0))
    (forward-line 5)   ; cur-line = 5
    (kuro--navigate-to-prompt 'previous)
    ;; Nearest row < 5 with prompt-start is row 3 → line 4.
    (should (= (line-number-at-pos) 4))))

(ert-deftest kuro-navigation--update-prompt-positions-max-count-one-keeps-lowest-row ()
  "max-count=1 retains only the mark at the lowest row after sorting."
  (let* ((marks '(("prompt-start" 5 0) ("prompt-end" 2 0) ("command-start" 8 0)))
         (result (kuro--update-prompt-positions marks nil 1)))
    (should (= (length result) 1))
    (should (= (cadr (nth 0 result)) 2))))

(ert-deftest kuro-navigation--next-prompt-from-point-min ()
  "kuro-next-prompt at point-min (cur-line=0) finds the first prompt at row > 0."
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 1 0)
            '("prompt-start" 4 0))
    ;; cur-line = 0 (at point-min)
    (goto-char (point-min))
    (kuro-next-prompt)
    ;; First prompt-start after row 0 is row 1 → line 2.
    (should (= (line-number-at-pos) 2))))

(ert-deftest kuro-navigation--previous-prompt-at-row-adjacent-to-prompt ()
  "kuro-previous-prompt at cur-line=row+1 finds the prompt exactly one row behind."
  (kuro-nav-test--with-prompts
      (list '("prompt-start" 4 0))
    (forward-line 5)   ; cur-line = 5, prompt at row 4 (< 5) qualifies
    (kuro-previous-prompt)
    ;; row 4 → line 5.
    (should (= (line-number-at-pos) 5))))

;;; Group 13: kuro--goto-prompt-row return value

(ert-deftest kuro-navigation-ext-goto-prompt-row-returns-forward-line-value ()
  "kuro--goto-prompt-row returns the value of forward-line (0 when row is in range)."
  (with-temp-buffer
    (dotimes (_ 20) (insert "\n"))
    (goto-char (point-min))
    ;; Row 5 is within the 20-line buffer; forward-line returns 0.
    (let ((result (kuro--goto-prompt-row 5)))
      (should (= result 0)))))

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

(provide 'kuro-navigation-test-2)
;;; kuro-navigation-test-2.el ends here
