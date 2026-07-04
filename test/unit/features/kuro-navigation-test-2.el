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


;;; Group 14 — kuro--def-nav-cmd / kuro--def-navigator structural tests

(ert-deftest kuro-navigation-def-nav-cmd-expands-to-defun ()
  "`kuro--def-nav-cmd' single-step expands to a `defun' form."
  (let ((exp (macroexpand-1
              '(kuro--def-nav-cmd kuro-test--fake-nav kuro--navigate-to-prompt previous "doc"))))
    (should (eq (car exp) 'defun))
    (should (eq (cadr exp) 'kuro-test--fake-nav))))

(ert-deftest kuro-navigation-def-nav-cmd-expansion-has-interactive ()
  "`kuro--def-nav-cmd' expansion contains `(interactive)' in the body."
  (let ((exp (macroexpand-1
              '(kuro--def-nav-cmd kuro-test--fake-nav2 kuro--navigate-to-prompt next "doc"))))
    (should (member '(interactive) (cddr exp)))))

(ert-deftest kuro-navigation-def-navigator-expands-to-defun-with-direction-arg ()
  "`kuro--def-navigator' generates a `defun' with `(direction)' arglist.
Unlike `kuro--def-nav-cmd', the navigator is called programmatically (no
`(interactive)'), and takes a DIRECTION argument at call time."
  (let* ((exp (macroexpand-1
               '(kuro--def-navigator kuro-test--fake-navigator
                  (lambda (e) t) (goto-char (cadr target))
                  (message "no target")
                  "doc")))
         (arglist (caddr exp)))
    (should (eq (car exp) 'defun))
    (should (eq (cadr exp) 'kuro-test--fake-navigator))
    (should (equal arglist '(direction)))))

(ert-deftest kuro-navigation-def-navigator-expansion-is-not-interactive ()
  "`kuro--def-navigator' generates a NON-interactive helper (called programmatically)."
  (let* ((exp (macroexpand-1
               '(kuro--def-navigator kuro-test--fake-navigator2
                  (lambda (e) t) (ignore) (ignore) "doc")))
         (body (cddr exp)))
    (should-not (member '(interactive) body))))

(provide 'kuro-navigation-test-2)
;;; kuro-navigation-test-2.el ends here
