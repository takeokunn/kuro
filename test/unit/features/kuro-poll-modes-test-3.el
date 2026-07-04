;;; kuro-poll-modes-test-3.el --- kuro-poll-modes-test (part 3)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-poll-modes-test-support)

;; ------------------------------------------------------------
;; Group Q — kuro--apply-terminal-modes field isolation
;; ------------------------------------------------------------

(ert-deftest kuro-poll-modes-apply-modes-acm-only-changed ()
  "kuro--apply-terminal-modes sets only application-cursor-keys-mode when others were nil."
  (kuro-poll-test--with-buffer
    (kuro--apply-terminal-modes '(t nil 0 nil nil nil 0))
    (should (eq kuro--application-cursor-keys-mode t))
    (should-not kuro--app-keypad-mode)
    (should (= kuro--mouse-mode 0))))

(ert-deftest kuro-poll-modes-apply-modes-akm-only-changed ()
  "kuro--apply-terminal-modes sets only app-keypad-mode when others are nil/0."
  (kuro-poll-test--with-buffer
    (kuro--apply-terminal-modes '(nil t 0 nil nil nil 0))
    (should-not kuro--application-cursor-keys-mode)
    (should (eq kuro--app-keypad-mode t))
    (should (= kuro--mouse-mode 0))))

(defconst kuro-poll-modes-test--apply-modes-field-table
  '((kuro-poll-modes-apply-modes-mouse-mode-set
     (nil nil 1002 nil nil nil 0) kuro--mouse-mode 1002)
    (kuro-poll-modes-apply-modes-bracketed-paste-set
     (nil nil 0 nil nil t 0) kuro--bracketed-paste-mode t)
    (kuro-poll-modes-apply-modes-keyboard-flags-set
     (nil nil 0 nil nil nil 31) kuro--keyboard-flags 31))
  "Table: (test-name modes check-sym expected) for single-field apply-terminal-modes tests.")

(defmacro kuro-poll-modes-test--def-apply-modes-field (test-name modes check-sym expected)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--apply-terminal-modes' sets `%s' to %S." check-sym expected)
     (kuro-poll-test--with-buffer
       (kuro--apply-terminal-modes ',modes)
       (should (equal ,check-sym ,expected)))))

(kuro-poll-modes-test--def-apply-modes-field
 kuro-poll-modes-apply-modes-mouse-mode-set
 (nil nil 1002 nil nil nil 0) kuro--mouse-mode 1002)
(kuro-poll-modes-test--def-apply-modes-field
 kuro-poll-modes-apply-modes-bracketed-paste-set
 (nil nil 0 nil nil t 0) kuro--bracketed-paste-mode t)
(kuro-poll-modes-test--def-apply-modes-field
 kuro-poll-modes-apply-modes-keyboard-flags-set
 (nil nil 0 nil nil nil 31) kuro--keyboard-flags 31)

(ert-deftest kuro-poll-modes-test--all-apply-modes-fields-correct ()
  "Invariant: each single-field modes entry sets the expected variable."
  (dolist (entry kuro-poll-modes-test--apply-modes-field-table)
    (pcase-let ((`(,_name ,modes ,check-sym ,expected) entry))
      (kuro-poll-test--with-buffer
        (kuro--apply-terminal-modes modes)
        (should (equal (symbol-value check-sym) expected))))))

;; ------------------------------------------------------------
;; Group R — kuro--poll-image-events single notification and order
;; ------------------------------------------------------------

(ert-deftest kuro-poll-modes-poll-image-events-single-notification ()
  "kuro--poll-image-events handles exactly one notification correctly."
  (kuro-poll-test--with-buffer
    (let ((rendered nil))
      (cl-letf (((symbol-function 'kuro--poll-image-notifications)
                 (lambda () '(notif-only)))
                ((symbol-function 'kuro--render-image-notification)
                 (lambda (n) (push n rendered))))
        (kuro--poll-image-events)
        (should (equal rendered '(notif-only)))))))

(ert-deftest kuro-poll-modes-poll-image-events-preserves-order ()
  "kuro--poll-image-events renders notifications in the order returned by FFI."
  (kuro-poll-test--with-buffer
    (let ((rendered nil))
      (cl-letf (((symbol-function 'kuro--poll-image-notifications)
                 (lambda () '(first second third)))
                ((symbol-function 'kuro--render-image-notification)
                 (lambda (n) (push n rendered))))
        (kuro--poll-image-events)
        (should (equal (nreverse rendered) '(first second third)))))))

;; ------------------------------------------------------------
;; Group S — kuro--poll-prompt-mark-updates positions passed through
;; ------------------------------------------------------------

(ert-deftest kuro-poll-modes-prompt-mark-updates-passes-existing-positions ()
  "kuro--poll-prompt-mark-updates passes existing kuro--prompt-positions to update fn."
  (kuro-poll-test--with-buffer
    (setq kuro--prompt-positions '(10 20 30))
    (let ((received-positions nil))
      (cl-letf (((symbol-function 'kuro--poll-prompt-marks)
                 (lambda () '(("prompt-start" 5 0 nil nil nil nil))))
                ((symbol-function 'kuro--update-prompt-positions)
                 (lambda (_marks positions _max)
                   (setq received-positions positions)
                   positions)))
        (kuro--poll-prompt-mark-updates)
        (should (equal received-positions '(10 20 30)))))))

(ert-deftest kuro-poll-modes-prompt-mark-updates-result-replaces-positions ()
  "kuro--poll-prompt-mark-updates replaces kuro--prompt-positions with the new result."
  (kuro-poll-test--with-buffer
    (setq kuro--prompt-positions '(1 2 3))
    (cl-letf (((symbol-function 'kuro--poll-prompt-marks)
               (lambda () '(("prompt-start" 99 0 nil nil nil nil))))
              ((symbol-function 'kuro--update-prompt-positions)
               (lambda (_marks _positions _max) '(99))))
      (kuro--poll-prompt-mark-updates)
      (should (equal kuro--prompt-positions '(99))))))

;; ------------------------------------------------------------
;; Group T — kuro--gated-poll macro
;; ------------------------------------------------------------

(defconst kuro-poll-modes-test--gated-poll-fires-table
  '((kuro-poll-modes-gated-poll-fires-at-multiple      20 10 t)
    (kuro-poll-modes-gated-poll-silent-on-non-multiple 11 10 nil)
    (kuro-poll-modes-gated-poll-fires-at-zero           0 10 t))
  "Table of (test-name frame cadence expectedp) for `kuro--gated-poll' gate behavior.")

(defmacro kuro-poll-modes-test--def-gated-poll-fires (test-name frame cadence expectedp)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--gated-poll' frame=%d cadence=%d → fires=%s." frame cadence expectedp)
     (kuro-poll-test--with-buffer
       (setq kuro--mode-poll-frame-count ,frame)
       (let ((called nil))
         (kuro--gated-poll ,cadence (lambda () (setq called t)))
         ,(if expectedp `(should called) `(should-not called))))))

(kuro-poll-modes-test--def-gated-poll-fires kuro-poll-modes-gated-poll-fires-at-multiple      20 10 t)
(kuro-poll-modes-test--def-gated-poll-fires kuro-poll-modes-gated-poll-silent-on-non-multiple 11 10 nil)
(kuro-poll-modes-test--def-gated-poll-fires kuro-poll-modes-gated-poll-fires-at-zero           0 10 t)

(ert-deftest kuro-poll-modes-test--gated-poll-fires-all-cases ()
  "Invariant: kuro--gated-poll fires correctly for all gate boundary cases."
  (dolist (entry kuro-poll-modes-test--gated-poll-fires-table)
    (pcase-let ((`(,_name ,frame ,cadence ,expectedp) entry))
      (kuro-poll-test--with-buffer
        (setq kuro--mode-poll-frame-count frame)
        (let ((called nil))
          (kuro--gated-poll cadence (lambda () (setq called t)))
          (should (eq called (not (not expectedp)))))))))

(ert-deftest kuro-poll-modes-gated-poll-passes-result-through ()
  "kuro--gated-poll returns the return value of FN when invoked."
  (kuro-poll-test--with-buffer
    (setq kuro--mode-poll-frame-count 30)
    (should (eq (kuro--gated-poll 10 (lambda () 'result)) 'result))))

(ert-deftest kuro-poll-modes-gated-poll-returns-nil-when-skipped ()
  "kuro--gated-poll returns nil when the cadence gate is not satisfied."
  (kuro-poll-test--with-buffer
    (setq kuro--mode-poll-frame-count 11)
    (should (null (kuro--gated-poll 10 (lambda () 'result))))))

(ert-deftest kuro-poll-modes-gated-poll-different-cadences-independent ()
  "kuro--gated-poll with cadence 10 and 30 behave independently at frame 10."
  (kuro-poll-test--with-buffer
    (setq kuro--mode-poll-frame-count 10)
    (let ((tier1-called nil) (tier2-called nil))
      (kuro--gated-poll 10  (lambda () (setq tier1-called t)))
      (kuro--gated-poll 30  (lambda () (setq tier2-called t)))
      (should tier1-called)
      (should-not tier2-called))))

;; ------------------------------------------------------------
;; Group U — kuro--poll-prompt-mark-updates 7-tuple forwarding
;; ------------------------------------------------------------

(ert-deftest kuro-poll-modes-prompt-mark-updates-forwards-7tuple-unchanged ()
  "T2g: a 7-tuple emitted by FFI passes through unchanged into the update fn
and the resulting positions are stored in `kuro--prompt-positions'."
  (kuro-poll-test--with-buffer
    (let* ((mark      '("command-end" 8 0 0 "aid42" 1234 nil))
           (input     (list mark))
           (forwarded nil))
      (cl-letf (((symbol-function 'kuro--poll-prompt-marks)
                 (lambda () input))
                ((symbol-function 'kuro--update-prompt-status) #'ignore)
                ((symbol-function 'kuro--update-prompt-positions)
                 (lambda (marks _positions _max)
                   (setq forwarded marks)
                   marks)))
        (kuro--poll-prompt-mark-updates)
        ;; Same shape, same length, same fields — no truncation.
        (should (equal forwarded input))
        (should (= (length (car forwarded)) 7))
        (should (equal kuro--prompt-positions input))))))


;; Group V — kuro--clipboard-write and kuro--clipboard-query direct tests
;; ------------------------------------------------------------

(defconst kuro-poll-modes-test--clipboard-write-policy-table
  '((kuro-poll-modes-clipboard-write-allow-policy-adds-to-kill-ring      allow       nil t)
    (kuro-poll-modes-clipboard-write-write-only-policy-adds-to-kill-ring write-only  nil t)
    (kuro-poll-modes-clipboard-write-deny-policy-does-nothing            deny        nil nil)
    (kuro-poll-modes-clipboard-write-prompt-accepted                     prompt      t   t)
    (kuro-poll-modes-clipboard-write-prompt-rejected                     prompt      nil nil))
  "Table: (test-name policy yes-or-no-result added-p) for `kuro--clipboard-write' policy matrix.")

(defmacro kuro-poll-modes-test--def-clipboard-write-policy
    (test-name policy yes-or-no-result added-p)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--clipboard-write' policy=%s yes=%s → kill-ring added=%s."
              policy yes-or-no-result added-p)
     (kuro-poll-test--with-buffer
       (let ((kuro-clipboard-policy ',policy)
             (added nil))
         (cl-letf (((symbol-function 'kill-new) (lambda (t) (setq added t)))
                   ((symbol-function 'message) #'ignore)
                   ,@(when (eq policy 'prompt)
                       `(((symbol-function 'yes-or-no-p)
                          (lambda (_) ,yes-or-no-result)))))
           (kuro--clipboard-write "hello" "clipboard")
           ,(if added-p
                `(should (equal added "hello"))
              `(should-not added)))))))

(kuro-poll-modes-test--def-clipboard-write-policy
 kuro-poll-modes-clipboard-write-allow-policy-adds-to-kill-ring      allow       nil t)
(kuro-poll-modes-test--def-clipboard-write-policy
 kuro-poll-modes-clipboard-write-write-only-policy-adds-to-kill-ring write-only  nil t)
(kuro-poll-modes-test--def-clipboard-write-policy
 kuro-poll-modes-clipboard-write-deny-policy-does-nothing            deny        nil nil)
(kuro-poll-modes-test--def-clipboard-write-policy
 kuro-poll-modes-clipboard-write-prompt-accepted                     prompt      t   t)
(kuro-poll-modes-test--def-clipboard-write-policy
 kuro-poll-modes-clipboard-write-prompt-rejected                     prompt      nil nil)

(ert-deftest kuro-poll-modes-test--all-clipboard-write-policies-correct ()
  "Invariant: every entry in the write-policy table produces the expected kill-ring effect."
  (dolist (entry kuro-poll-modes-test--clipboard-write-policy-table)
    (pcase-let ((`(,_name ,policy ,yes-or-no ,added-p) entry))
      (kuro-poll-test--with-buffer
        (let ((kuro-clipboard-policy policy)
              (added nil))
          (cl-letf (((symbol-function 'kill-new) (lambda (t) (setq added t)))
                    ((symbol-function 'message) #'ignore)
                    ((symbol-function 'yes-or-no-p) (lambda (_) yes-or-no)))
            (kuro--clipboard-write "hello" "clipboard")
            (if added-p
                (should (equal added "hello"))
              (should-not added))))))))

(defconst kuro-poll-modes-test--clipboard-query-policy-table
  '((kuro-poll-modes-clipboard-query-allow-sends-response  allow  nil t)
    (kuro-poll-modes-clipboard-query-deny-does-nothing     deny   nil nil)
    (kuro-poll-modes-clipboard-query-prompt-accepted       prompt t   t)
    (kuro-poll-modes-clipboard-query-prompt-rejected       prompt nil nil))
  "Table: (test-name policy yes-or-no-result sent-p) for `kuro--clipboard-query' policy matrix.")

(defmacro kuro-poll-modes-test--def-clipboard-query-policy
    (test-name policy yes-or-no-result sent-p)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--clipboard-query' policy=%s yes=%s → osc52 sent=%s."
              policy yes-or-no-result sent-p)
     (kuro-poll-test--with-buffer
       (let ((kuro-clipboard-policy ',policy)
             (sent nil))
         (cl-letf (((symbol-function 'kuro--send-osc52-clipboard-response)
                    (lambda () (setq sent t)))
                   ,@(when (eq policy 'prompt)
                       `(((symbol-function 'yes-or-no-p)
                          (lambda (_) ,yes-or-no-result)))))
           (kuro--clipboard-query "clipboard")
           ,(if sent-p `(should sent) `(should-not sent)))))))

(kuro-poll-modes-test--def-clipboard-query-policy
 kuro-poll-modes-clipboard-query-allow-sends-response  allow  nil t)
(kuro-poll-modes-test--def-clipboard-query-policy
 kuro-poll-modes-clipboard-query-deny-does-nothing     deny   nil nil)
(kuro-poll-modes-test--def-clipboard-query-policy
 kuro-poll-modes-clipboard-query-prompt-accepted       prompt t   t)
(kuro-poll-modes-test--def-clipboard-query-policy
 kuro-poll-modes-clipboard-query-prompt-rejected       prompt nil nil)

(ert-deftest kuro-poll-modes-test--all-clipboard-query-policies-correct ()
  "Invariant: every entry in the query-policy table produces the expected OSC 52 send effect."
  (dolist (entry kuro-poll-modes-test--clipboard-query-policy-table)
    (pcase-let ((`(,_name ,policy ,yes-or-no ,sent-p) entry))
      (kuro-poll-test--with-buffer
        (let ((kuro-clipboard-policy policy)
              (sent nil))
          (cl-letf (((symbol-function 'kuro--send-osc52-clipboard-response)
                     (lambda () (setq sent t)))
                    ((symbol-function 'yes-or-no-p) (lambda (_) yes-or-no)))
            (kuro--clipboard-query "clipboard")
            (if sent-p (should sent) (should-not sent))))))))

(provide 'kuro-poll-modes-test-3)

;;; kuro-poll-modes-test-3.el ends here
