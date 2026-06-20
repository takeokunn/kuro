;;; kuro-poll-modes-test-2.el --- kuro-poll-modes-test (part 2)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-poll-modes-test-support)

;;; Group L: kuro--poll-prompt-mark-updates — result stored

(ert-deftest kuro-poll-modes-prompt-mark-updates-stores-result ()
  "kuro--poll-prompt-mark-updates stores the return value from kuro--update-prompt-positions."
  (kuro-poll-test--with-buffer
    (cl-letf (((symbol-function 'kuro--poll-prompt-marks)
               (lambda () '(("prompt-start" 1 0 nil nil nil nil))))
              ((symbol-function 'kuro--update-prompt-positions)
               (lambda (_marks _positions _max) '(42 . stored))))
      (kuro--poll-prompt-mark-updates)
      (should (equal kuro--prompt-positions '(42 . stored))))))

(ert-deftest kuro-poll-modes-prompt-mark-updates-passes-max-count ()
  "kuro--poll-prompt-mark-updates passes kuro--max-prompt-positions to update fn."
  (kuro-poll-test--with-buffer
    (let ((received-max nil))
      (cl-letf (((symbol-function 'kuro--poll-prompt-marks)
                 (lambda () '(("prompt-start" 1 0 nil nil nil nil))))
                ((symbol-function 'kuro--update-prompt-positions)
                 (lambda (_marks _positions max)
                   (setq received-max max)
                   nil)))
        (kuro--poll-prompt-mark-updates)
        (should (= received-max kuro--max-prompt-positions))))))

;;; Group M: kuro--poll-cwd — already has nil/empty; add trailing slash

(defconst kuro-poll-modes-test--poll-cwd-table
  '((kuro-poll-modes-poll-cwd-adds-trailing-slash           "/home/user/project" "/home/user/project/")
    (kuro-poll-modes-poll-cwd-idempotent-with-trailing-slash "/tmp/"              "/tmp/"))
  "Table of (test-name input expected-dir) for `kuro--poll-cwd'.")

(defmacro kuro-poll-modes-test--def-poll-cwd (test-name input expected)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--poll-cwd' %S → default-directory=%S." input expected)
     (kuro-poll-test--with-buffer
       (cl-letf (((symbol-function 'kuro--get-cwd) (lambda () ,input)))
         (kuro--poll-cwd)
         (should (equal default-directory ,expected))))))

(kuro-poll-modes-test--def-poll-cwd
 kuro-poll-modes-poll-cwd-adds-trailing-slash           "/home/user/project" "/home/user/project/")
(kuro-poll-modes-test--def-poll-cwd
 kuro-poll-modes-poll-cwd-idempotent-with-trailing-slash "/tmp/"              "/tmp/")

(ert-deftest kuro-poll-modes-test--poll-cwd-all-cases-correct ()
  "Invariant: kuro--poll-cwd normalizes every input to the expected directory."
  (dolist (entry kuro-poll-modes-test--poll-cwd-table)
    (pcase-let ((`(,_name ,input ,expected) entry))
      (kuro-poll-test--with-buffer
        (cl-letf (((symbol-function 'kuro--get-cwd) (lambda () input)))
          (kuro--poll-cwd)
          (should (equal default-directory expected)))))))

;; ------------------------------------------------------------
;; Group N — kuro--send-osc52-clipboard-response
;; ------------------------------------------------------------

(ert-deftest kuro-poll-modes-osc52-response-format ()
  "kuro--send-osc52-clipboard-response sends correctly formatted OSC 52 sequence."
  (kuro-poll-test--with-osc52-response "hello"
    (should (string-prefix-p "\e]52;c;" sent))
    (should (string-suffix-p "\a" sent))))

(ert-deftest kuro-poll-modes-osc52-response-contains-base64 ()
  "kuro--send-osc52-clipboard-response encodes kill-ring text as base64."
  ;; base64 of "abc" is "YWJj"
  (kuro-poll-test--with-osc52-response "abc"
    (should (string-match-p "YWJj" sent))))

(ert-deftest kuro-poll-modes-osc52-response-empty-kill-ring-sends-empty ()
  "kuro--send-osc52-clipboard-response sends empty base64 when kill-ring errors."
  ;; base64 of "" is ""
  (kuro-poll-test--with-osc52-response (error "kill-ring is empty")
    (should (string-match-p "\e]52;c;\a" sent))))

;; ------------------------------------------------------------
;; Group O — kuro--handle-clipboard-actions multiple/compound scenarios
;; ------------------------------------------------------------

(ert-deftest kuro-poll-modes-clipboard-multiple-write-actions ()
  "kuro--handle-clipboard-actions processes all write actions in the list."
  (kuro-poll-test--with-buffer
    (let ((written nil)
          (kuro-clipboard-policy 'allow))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((write . "first") (write . "second"))))
                ((symbol-function 'kill-new)
                 (lambda (text) (push text written)))
                ((symbol-function 'message) #'ignore))
        (kuro--handle-clipboard-actions)
        (should (member "first" written))
        (should (member "second" written))))))

(ert-deftest kuro-poll-modes-clipboard-prompt-query-accepted ()
  "kuro--handle-clipboard-actions sends OSC 52 response for query under prompt policy when user accepts."
  (kuro-poll-test--with-buffer
    (let ((sent-key nil)
          (kuro-clipboard-policy 'prompt))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((query))))
                ((symbol-function 'yes-or-no-p) (lambda (_prompt) t))
                ((symbol-function 'current-kill) (lambda (_n _no-move) "clip"))
                ((symbol-function 'kuro--send-key)
                 (lambda (s) (setq sent-key s))))
        (kuro--handle-clipboard-actions)
        (should (stringp sent-key))
        (should (string-prefix-p "\e]52;c;" sent-key))))))

(ert-deftest kuro-poll-modes-clipboard-prompt-query-rejected ()
  "kuro--handle-clipboard-actions does NOT send OSC 52 under prompt policy when user declines."
  (kuro-poll-test--with-buffer
    (let ((sent-key nil)
          (kuro-clipboard-policy 'prompt))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((query))))
                ((symbol-function 'yes-or-no-p) (lambda (_prompt) nil))
                ((symbol-function 'kuro--send-key)
                 (lambda (s) (setq sent-key s))))
        (kuro--handle-clipboard-actions)
        (should-not sent-key)))))

(ert-deftest kuro-poll-modes-clipboard-write-then-query-both-processed ()
  "kuro--handle-clipboard-actions handles a write action followed by a query action."
  (kuro-poll-test--with-buffer
    (let ((kill-ring-text nil)
          (sent-key nil)
          (kuro-clipboard-policy 'allow))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((write . "written") (query))))
                ((symbol-function 'kill-new)
                 (lambda (text) (setq kill-ring-text text)))
                ((symbol-function 'message) #'ignore)
                ((symbol-function 'current-kill)
                 (lambda (_n _no-move) "previous"))
                ((symbol-function 'kuro--send-key)
                 (lambda (s) (setq sent-key s))))
        (kuro--handle-clipboard-actions)
        (should (equal kill-ring-text "written"))
        (should (stringp sent-key))))))

;; ------------------------------------------------------------
;; Group P — kuro--poll-tier1-modes detailed behavior
;; ------------------------------------------------------------

(ert-deftest kuro-poll-modes-tier1-modes-tier1-fns-run-even-when-modes-nil ()
  "kuro--poll-tier1-modes always runs tier1 fns even when kuro--get-terminal-modes returns nil."
  (kuro-poll-test--with-buffer
    (let ((cwd-called nil))
      (cl-letf (((symbol-function 'kuro--get-terminal-modes) (lambda () nil))
                ((symbol-function 'kuro--poll-cwd)
                 (lambda () (setq cwd-called t)))
                ((symbol-function 'kuro--handle-clipboard-actions) #'ignore)
                ((symbol-function 'kuro--poll-prompt-mark-updates) #'ignore)
                ((symbol-function 'kuro--poll-image-events) #'ignore)
                ((symbol-function 'kuro--check-process-exit) #'ignore))
        (kuro--poll-tier1-modes)
        (should cwd-called)))))

(ert-deftest kuro-poll-modes-tier1-modes-fns-called-in-order ()
  "kuro--poll-tier1-modes calls tier1 functions in the order listed in kuro--tier1-poll-fns."
  (kuro-poll-test--with-buffer
    (let ((call-order nil))
      (cl-letf (((symbol-function 'kuro--poll-terminal-mode-state)
                 (lambda () (push 'modes call-order)))
                ((symbol-function 'kuro--poll-cwd)
                 (lambda () (push 'cwd call-order)))
                ((symbol-function 'kuro--handle-clipboard-actions)
                 (lambda () (push 'clipboard call-order)))
                ((symbol-function 'kuro--poll-prompt-mark-updates)
                 (lambda () (push 'prompts call-order)))
                ((symbol-function 'kuro--poll-eval-command-updates)
                 (lambda () (push 'eval call-order)))
                ((symbol-function 'kuro--poll-image-events)
                 (lambda () (push 'images call-order)))
                ((symbol-function 'kuro--apply-hyperlink-ranges)
                 (lambda () (push 'hyperlinks call-order)))
                ((symbol-function 'kuro--check-process-exit)
                 (lambda () (push 'exit call-order))))
        (kuro--poll-tier1-modes)
        (should (equal (nreverse call-order)
                       '(modes cwd clipboard prompts eval images hyperlinks exit)))))))

(ert-deftest kuro-poll-modes-tier1-modes-apply-modes-called-with-ffi-result ()
  "kuro--poll-tier1-modes passes the FFI result to kuro--apply-terminal-modes."
  (kuro-poll-test--with-buffer
    (let ((applied nil))
      (cl-letf (((symbol-function 'kuro--get-terminal-modes)
                 (lambda () '(nil t 0 nil nil nil 4)))
                ((symbol-function 'kuro--apply-terminal-modes)
                 (lambda (modes) (setq applied modes)))
                ((symbol-function 'kuro--poll-cwd) #'ignore)
                ((symbol-function 'kuro--handle-clipboard-actions) #'ignore)
                ((symbol-function 'kuro--poll-prompt-mark-updates) #'ignore)
                ((symbol-function 'kuro--poll-image-events) #'ignore)
                ((symbol-function 'kuro--check-process-exit) #'ignore))
        (kuro--poll-tier1-modes)
        (should (equal applied '(nil t 0 nil nil nil 4)))))))

;; ------------------------------------------------------------
;; Group P2 — kuro--poll-terminal-mode-state unit tests
;; ------------------------------------------------------------

(ert-deftest kuro-poll-modes-poll-terminal-mode-state-applies-when-ffi-returns-list ()
  "`kuro--poll-terminal-mode-state' calls `kuro--apply-terminal-modes' when FFI returns a list."
  (kuro-poll-test--with-buffer
    (let ((applied nil))
      (cl-letf (((symbol-function 'kuro--get-terminal-modes)
                 (lambda () '(t nil 1000 nil nil t 8)))
                ((symbol-function 'kuro--apply-terminal-modes)
                 (lambda (modes) (setq applied modes))))
        (kuro--poll-terminal-mode-state)
        (should (equal applied '(t nil 1000 nil nil t 8)))))))

(ert-deftest kuro-poll-modes-poll-terminal-mode-state-noop-when-ffi-returns-nil ()
  "`kuro--poll-terminal-mode-state' does not call `kuro--apply-terminal-modes' when FFI returns nil."
  (kuro-poll-test--with-buffer
    (setq kuro--application-cursor-keys-mode 'sentinel)
    (cl-letf (((symbol-function 'kuro--get-terminal-modes) (lambda () nil))
              ((symbol-function 'kuro--apply-terminal-modes)
               (lambda (_modes) (error "should not be called"))))
      (kuro--poll-terminal-mode-state)
      (should (eq kuro--application-cursor-keys-mode 'sentinel)))))

(ert-deftest kuro-poll-modes-tier1-poll-fns-starts-with-mode-state ()
  "`kuro--tier1-poll-fns' must have `kuro--poll-terminal-mode-state' as its first entry.
This invariant ensures the consolidated FFI call runs before any function
that reads terminal mode variables set by `kuro--apply-terminal-modes'."
  (should (eq (car kuro--tier1-poll-fns) 'kuro--poll-terminal-mode-state)))

(ert-deftest kuro-poll-modes-tier1-poll-fns-all-bound ()
  "Every symbol in `kuro--tier1-poll-fns' is a bound function."
  (dolist (fn kuro--tier1-poll-fns)
    (should (fboundp fn))))

(ert-deftest kuro-poll-modes-run-tier1-poll-fns-macroexpands-to-progn ()
  "`kuro--run-tier1-poll-fns' expands to the fixed tier-1 poll sequence."
  (should (equal (macroexpand-1 '(kuro--run-tier1-poll-fns))
                 '(progn
                    (kuro--poll-terminal-mode-state)
                    (kuro--poll-cwd)
                    (kuro--poll-progress)
                    (kuro--poll-user-vars)
                    (kuro--handle-clipboard-actions)
                    (kuro--poll-prompt-mark-updates)
                    (kuro--poll-eval-command-updates)
                    (kuro--poll-image-events)
                    (kuro--apply-hyperlink-ranges)
                    (kuro--apply-text-size-ranges)
                    (kuro--check-process-exit)))))

(ert-deftest kuro-poll-modes-dispatch-clipboard-action-routes-write-payload-and-target ()
  "`kuro--dispatch-clipboard-action' forwards a 3-element write's payload and target."
  (let ((written nil)
        (target nil))
    (cl-letf (((symbol-function 'kuro--clipboard-write)
               (lambda (text &optional tgt) (setq written text target tgt)))
              ((symbol-function 'kuro--clipboard-query) #'ignore))
      (kuro--dispatch-clipboard-action '(write "payload" "primary"))
      (should (equal written "payload"))
      (should (equal target "primary")))))

(ert-deftest kuro-poll-modes-dispatch-clipboard-action-dispatches-query ()
  "`kuro--dispatch-clipboard-action' dispatches a query action to the query handler."
  (let ((queried nil))
    (cl-letf (((symbol-function 'kuro--clipboard-write) #'ignore)
              ((symbol-function 'kuro--clipboard-query)
               (lambda () (setq queried t))))
      (kuro--dispatch-clipboard-action '(query nil "clipboard"))
      (should queried))))

(ert-deftest kuro-poll-modes-dispatch-clipboard-action-legacy-cons-defaults-target-nil ()
  "`kuro--dispatch-clipboard-action' accepts a legacy cons and yields nil target."
  (let ((written nil)
        (target 'unset))
    (cl-letf (((symbol-function 'kuro--clipboard-write)
               (lambda (text &optional tgt) (setq written text target tgt)))
              ((symbol-function 'kuro--clipboard-query) #'ignore))
      (kuro--dispatch-clipboard-action '(write . "legacy"))
      (should (equal written "legacy"))
      (should (null target)))))

(provide 'kuro-poll-modes-test-2)

;;; kuro-poll-modes-test-2.el ends here
