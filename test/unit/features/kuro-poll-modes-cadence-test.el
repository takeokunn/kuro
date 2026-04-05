;;; kuro-poll-modes-ext-test.el --- Extended unit tests for kuro-poll-modes.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Extended unit tests for kuro-poll-modes.el (Groups L–T).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;; All FFI functions are stubbed with cl-letf.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-poll-modes)

;;; Test helpers

(defmacro kuro-poll-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer with poll-modes state initialized."
  `(with-temp-buffer
     (let ((kuro--initialized t)
           (kuro--mode-poll-frame-count 0)
           (kuro--prompt-positions nil)
           (kuro--application-cursor-keys-mode nil)
           (kuro--app-keypad-mode nil)
           (kuro--mouse-mode nil)
           (kuro--mouse-sgr nil)
           (kuro--mouse-pixel-mode nil)
           (kuro--bracketed-paste-mode nil)
           (kuro--keyboard-flags 0)
           (kuro-kill-buffer-on-exit nil))
       ,@body)))

;;; Group L: kuro--poll-prompt-mark-updates — result stored

(ert-deftest kuro-poll-modes-prompt-mark-updates-stores-result ()
  "kuro--poll-prompt-mark-updates stores the return value from kuro--update-prompt-positions."
  (kuro-poll-test--with-buffer
    (cl-letf (((symbol-function 'kuro--poll-prompt-marks)
               (lambda () '(("prompt-start" 1 0))))
              ((symbol-function 'kuro--update-prompt-positions)
               (lambda (_marks _positions _max) '(42 . stored))))
      (kuro--poll-prompt-mark-updates)
      (should (equal kuro--prompt-positions '(42 . stored))))))

(ert-deftest kuro-poll-modes-prompt-mark-updates-passes-max-count ()
  "kuro--poll-prompt-mark-updates passes kuro--max-prompt-positions to update fn."
  (kuro-poll-test--with-buffer
    (let ((received-max nil))
      (cl-letf (((symbol-function 'kuro--poll-prompt-marks)
                 (lambda () '(("prompt-start" 1 0))))
                ((symbol-function 'kuro--update-prompt-positions)
                 (lambda (_marks _positions max)
                   (setq received-max max)
                   nil)))
        (kuro--poll-prompt-mark-updates)
        (should (= received-max kuro--max-prompt-positions))))))

;;; Group M: kuro--poll-cwd — already has nil/empty; add trailing slash

(ert-deftest kuro-poll-modes-poll-cwd-adds-trailing-slash ()
  "kuro--poll-cwd ensures default-directory has a trailing slash via file-name-as-directory."
  (kuro-poll-test--with-buffer
    (cl-letf (((symbol-function 'kuro--get-cwd) (lambda () "/home/user/project")))
      (kuro--poll-cwd)
      (should (string-suffix-p "/" default-directory)))))

(ert-deftest kuro-poll-modes-poll-cwd-idempotent-with-trailing-slash ()
  "kuro--poll-cwd works correctly when CWD already has a trailing slash."
  (kuro-poll-test--with-buffer
    (cl-letf (((symbol-function 'kuro--get-cwd) (lambda () "/tmp/")))
      (kuro--poll-cwd)
      (should (equal default-directory "/tmp/")))))

;; ------------------------------------------------------------
;; Group N — kuro--send-osc52-clipboard-response
;; ------------------------------------------------------------

(ert-deftest kuro-poll-modes-osc52-response-format ()
  "kuro--send-osc52-clipboard-response sends correctly formatted OSC 52 sequence."
  (kuro-poll-test--with-buffer
    (let ((sent nil))
      (cl-letf (((symbol-function 'current-kill) (lambda (_n _no-move) "hello"))
                ((symbol-function 'kuro--send-key) (lambda (s) (setq sent s))))
        (kuro--send-osc52-clipboard-response)
        (should (string-prefix-p "\e]52;c;" sent))
        (should (string-suffix-p "\a" sent))))))

(ert-deftest kuro-poll-modes-osc52-response-contains-base64 ()
  "kuro--send-osc52-clipboard-response encodes kill-ring text as base64."
  (kuro-poll-test--with-buffer
    (let ((sent nil))
      (cl-letf (((symbol-function 'current-kill) (lambda (_n _no-move) "abc"))
                ((symbol-function 'kuro--send-key) (lambda (s) (setq sent s))))
        (kuro--send-osc52-clipboard-response)
        ;; base64 of "abc" is "YWJj"
        (should (string-match-p "YWJj" sent))))))

(ert-deftest kuro-poll-modes-osc52-response-empty-kill-ring-sends-empty ()
  "kuro--send-osc52-clipboard-response sends empty base64 when kill-ring errors."
  (kuro-poll-test--with-buffer
    (let ((sent nil))
      (cl-letf (((symbol-function 'current-kill)
                 (lambda (_n _no-move) (error "kill-ring is empty")))
                ((symbol-function 'kuro--send-key) (lambda (s) (setq sent s))))
        (kuro--send-osc52-clipboard-response)
        ;; base64 of "" is ""
        (should (string-match-p "\e]52;c;\a" sent))))))

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
      (cl-letf (((symbol-function 'kuro--get-terminal-modes) (lambda () nil))
                ((symbol-function 'kuro--poll-cwd)
                 (lambda () (push 'cwd call-order)))
                ((symbol-function 'kuro--handle-clipboard-actions)
                 (lambda () (push 'clipboard call-order)))
                ((symbol-function 'kuro--poll-prompt-mark-updates)
                 (lambda () (push 'prompts call-order)))
                ((symbol-function 'kuro--poll-image-events)
                 (lambda () (push 'images call-order)))
                ((symbol-function 'kuro--check-process-exit)
                 (lambda () (push 'exit call-order))))
        (kuro--poll-tier1-modes)
        (should (equal (nreverse call-order)
                       '(cwd clipboard prompts images exit)))))))

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

(ert-deftest kuro-poll-modes-apply-modes-mouse-mode-set ()
  "kuro--apply-terminal-modes correctly sets mouse-mode to 1002."
  (kuro-poll-test--with-buffer
    (kuro--apply-terminal-modes '(nil nil 1002 nil nil nil 0))
    (should (= kuro--mouse-mode 1002))))

(ert-deftest kuro-poll-modes-apply-modes-bracketed-paste-set ()
  "kuro--apply-terminal-modes correctly sets bracketed-paste-mode."
  (kuro-poll-test--with-buffer
    (kuro--apply-terminal-modes '(nil nil 0 nil nil t 0))
    (should (eq kuro--bracketed-paste-mode t))))

(ert-deftest kuro-poll-modes-apply-modes-keyboard-flags-set ()
  "kuro--apply-terminal-modes correctly sets keyboard-flags to a non-zero value."
  (kuro-poll-test--with-buffer
    (kuro--apply-terminal-modes '(nil nil 0 nil nil nil 31))
    (should (= kuro--keyboard-flags 31))))

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
                 (lambda () '(("prompt-start" 5 0))))
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
               (lambda () '(("prompt-start" 99 0))))
              ((symbol-function 'kuro--update-prompt-positions)
               (lambda (_marks _positions _max) '(99))))
      (kuro--poll-prompt-mark-updates)
      (should (equal kuro--prompt-positions '(99))))))

;; ------------------------------------------------------------
;; Group T — kuro--gated-poll macro
;; ------------------------------------------------------------

(ert-deftest kuro-poll-modes-gated-poll-fires-at-multiple ()
  "kuro--gated-poll invokes FN when frame count is an exact multiple of cadence."
  (kuro-poll-test--with-buffer
    (setq kuro--mode-poll-frame-count 20)
    (let ((called nil))
      (kuro--gated-poll 10 (lambda () (setq called t)))
      (should called))))

(ert-deftest kuro-poll-modes-gated-poll-silent-on-non-multiple ()
  "kuro--gated-poll does NOT invoke FN on non-multiple frame counts."
  (kuro-poll-test--with-buffer
    (setq kuro--mode-poll-frame-count 11)
    (let ((called nil))
      (kuro--gated-poll 10 (lambda () (setq called t)))
      (should-not called))))

(ert-deftest kuro-poll-modes-gated-poll-fires-at-zero ()
  "kuro--gated-poll fires when frame count is zero (initial state)."
  (kuro-poll-test--with-buffer
    (setq kuro--mode-poll-frame-count 0)
    (let ((called nil))
      (kuro--gated-poll 10 (lambda () (setq called t)))
      (should called))))

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

(provide 'kuro-poll-modes-ext-test)

;;; kuro-poll-modes-ext-test.el ends here
