;;; kuro-poll-modes-test-5.el --- kuro-poll-modes tests Group W: command-complete hook  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-poll-modes-test-support)


;;; Group W — kuro--run-command-complete-hook

(defmacro kuro-poll-modes-test--with-hook (hook-fn &rest body)
  "Run BODY with `kuro-on-command-complete-functions' set to HOOK-FN.
Uses cl-letf on symbol-value to ensure dynamic binding is always visible."
  `(cl-letf (((symbol-value 'kuro-on-command-complete-functions)
              (list ,hook-fn))
             ((symbol-function 'get-buffer-window) (lambda (_b _a) nil)))
     ,@body))

(ert-deftest kuro-poll-modes-run-cmd-hook-noop-when-hook-empty ()
  "`kuro--run-command-complete-hook' does nothing when hook variable is nil."
  (kuro-poll-test--with-buffer
    (cl-letf (((symbol-value 'kuro-on-command-complete-functions) nil))
      (let ((called nil))
        (kuro--run-command-complete-hook
         '(("command-end" 5 0 0 "aid" 100 nil)))
        (should-not called)))))

(ert-deftest kuro-poll-modes-run-cmd-hook-fires-for-command-end ()
  "`kuro--run-command-complete-hook' fires the hook for a `command-end' mark."
  (kuro-poll-test--with-buffer
    (let ((received nil))
      (kuro-poll-modes-test--with-hook
       (lambda (&rest args) (setq received args))
       (kuro--run-command-complete-hook
        '(("command-end" 5 0 42 "my-aid" 999 "/err"))))
      (should received)
      ;; Hook receives (exit-code duration-ms aid err-path visible)
      (should (= (nth 0 received) 42))
      (should (= (nth 1 received) 999))
      (should (equal (nth 2 received) "my-aid"))
      (should (equal (nth 3 received) "/err")))))

(defconst kuro-poll-modes-test--non-command-end-types
  '((kuro-poll-modes-run-cmd-hook-skips-prompt-start   "prompt-start")
    (kuro-poll-modes-run-cmd-hook-skips-prompt-end     "prompt-end")
    (kuro-poll-modes-run-cmd-hook-skips-command-start  "command-start"))
  "Table: (test-name mark-type) for mark types that must NOT fire the hook.")

(defmacro kuro-poll-modes-test--def-skip-non-command-end (test-name mark-type)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--run-command-complete-hook' skips `%s' mark type." mark-type)
     (kuro-poll-test--with-buffer
       (let ((called nil))
         (kuro-poll-modes-test--with-hook
          (lambda (&rest _) (setq called t))
          (kuro--run-command-complete-hook
           (list (list ,mark-type 1 0 0 nil nil nil))))
         (should-not called)))))

(kuro-poll-modes-test--def-skip-non-command-end
 kuro-poll-modes-run-cmd-hook-skips-prompt-start  "prompt-start")
(kuro-poll-modes-test--def-skip-non-command-end
 kuro-poll-modes-run-cmd-hook-skips-prompt-end    "prompt-end")
(kuro-poll-modes-test--def-skip-non-command-end
 kuro-poll-modes-run-cmd-hook-skips-command-start "command-start")

(ert-deftest kuro-poll-modes-run-cmd-hook-skip-invariant ()
  "Invariant: no non-command-end type fires the hook."
  (dolist (entry kuro-poll-modes-test--non-command-end-types)
    (pcase-let ((`(,_name ,mark-type) entry))
      (kuro-poll-test--with-buffer
        (let ((called nil))
          (kuro-poll-modes-test--with-hook
           (lambda (&rest _) (setq called t))
           (kuro--run-command-complete-hook
            (list (list mark-type 1 0 0 nil nil nil))))
          (should-not called))))))

(ert-deftest kuro-poll-modes-run-cmd-hook-fires-once-per-command-end ()
  "`kuro--run-command-complete-hook' fires once for each `command-end' mark."
  (kuro-poll-test--with-buffer
    (let ((count 0))
      (kuro-poll-modes-test--with-hook
       (lambda (&rest _) (cl-incf count))
       (kuro--run-command-complete-hook
        '(("prompt-start" 0 0 nil nil nil nil)
          ("command-end"  2 0 0   "a" 100 nil)
          ("command-end"  5 0 1   "b" 200 nil))))
      (should (= count 2)))))

(ert-deftest kuro-poll-modes-run-cmd-hook-visible-false-when-no-window ()
  "`kuro--run-command-complete-hook' passes visible=nil when buffer has no window."
  (kuro-poll-test--with-buffer
    (let ((received-visible :unset))
      (kuro-poll-modes-test--with-hook
       (lambda (_exit _dur _aid _err vis) (setq received-visible vis))
       (kuro--run-command-complete-hook
        '(("command-end" 3 0 0 nil nil nil))))
      (should (null received-visible)))))

(ert-deftest kuro-poll-modes-run-cmd-hook-visible-true-when-window-present ()
  "`kuro--run-command-complete-hook' passes visible=t when buffer has a window."
  (kuro-poll-test--with-buffer
    (let ((received-visible :unset))
      (cl-letf (((symbol-value 'kuro-on-command-complete-functions)
                 (list (lambda (_exit _dur _aid _err vis) (setq received-visible vis))))
                ((symbol-function 'get-buffer-window)
                 (lambda (_b _a) 'fake-window)))
        (kuro--run-command-complete-hook
         '(("command-end" 3 0 0 nil nil nil))))
      (should (eq received-visible t)))))


(provide 'kuro-poll-modes-test-5)
;;; kuro-poll-modes-test-5.el ends here
