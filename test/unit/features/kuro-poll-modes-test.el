;;; kuro-poll-modes-test.el --- Unit tests for kuro-poll-modes.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-poll-modes.el (tiered terminal mode polling).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;; All FFI functions are stubbed with cl-letf.
;;
;; These tests verify the polling subsystem in isolation, independently
;; of kuro-renderer.el.  The same functions are also exercised through
;; kuro-renderer-test.el (Groups 10, 11b, 11c, 11d, 11e) since
;; kuro-renderer re-exports everything via its (require 'kuro-poll-modes).

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

;;; Group A: kuro--apply-terminal-modes

(ert-deftest kuro-poll-modes-apply-modes-all-fields ()
  "kuro--apply-terminal-modes assigns all 7 mode values."
  (kuro-poll-test--with-buffer
    (kuro--apply-terminal-modes '(t t 1003 t t t 8))
    (should (eq kuro--application-cursor-keys-mode t))
    (should (eq kuro--app-keypad-mode t))
    (should (= kuro--mouse-mode 1003))
    (should (eq kuro--mouse-sgr t))
    (should (eq kuro--mouse-pixel-mode t))
    (should (eq kuro--bracketed-paste-mode t))
    (should (= kuro--keyboard-flags 8))))

(ert-deftest kuro-poll-modes-apply-modes-nil-kbf-defaults-zero ()
  "kuro--apply-terminal-modes defaults keyboard-flags to 0 when nil."
  (kuro-poll-test--with-buffer
    (kuro--apply-terminal-modes '(nil nil 0 nil nil nil nil))
    (should (= kuro--keyboard-flags 0))))

(ert-deftest kuro-poll-modes-apply-modes-false-values ()
  "kuro--apply-terminal-modes correctly sets all fields to nil."
  (kuro-poll-test--with-buffer
    (setq kuro--application-cursor-keys-mode t
          kuro--mouse-mode 1003)
    (kuro--apply-terminal-modes '(nil nil 0 nil nil nil 0))
    (should-not kuro--application-cursor-keys-mode)
    (should (= kuro--mouse-mode 0))))

;;; Group B: kuro--poll-cwd

(ert-deftest kuro-poll-modes-poll-cwd-updates-directory ()
  "kuro--poll-cwd sets default-directory from OSC 7."
  (kuro-poll-test--with-buffer
    (cl-letf (((symbol-function 'kuro--get-cwd) (lambda () "/tmp/test")))
      (kuro--poll-cwd)
      (should (equal default-directory "/tmp/test/")))))

(ert-deftest kuro-poll-modes-poll-cwd-noop-on-nil ()
  "kuro--poll-cwd does not modify default-directory when FFI returns nil."
  (kuro-poll-test--with-buffer
    (let ((dir-before default-directory))
      (cl-letf (((symbol-function 'kuro--get-cwd) (lambda () nil)))
        (kuro--poll-cwd)
        (should (equal default-directory dir-before))))))

(ert-deftest kuro-poll-modes-poll-cwd-noop-on-empty ()
  "kuro--poll-cwd does not modify default-directory when FFI returns empty string."
  (kuro-poll-test--with-buffer
    (let ((dir-before default-directory))
      (cl-letf (((symbol-function 'kuro--get-cwd) (lambda () "")))
        (kuro--poll-cwd)
        (should (equal default-directory dir-before))))))

;;; Group C: kuro--check-process-exit

(ert-deftest kuro-poll-modes-check-exit-kills-when-dead ()
  "kuro--check-process-exit calls kuro-kill when process is dead and flag is set."
  (kuro-poll-test--with-buffer
    (setq-local kuro-kill-buffer-on-exit t)
    (let ((kill-called nil))
      (cl-letf (((symbol-function 'kuro--is-process-alive) (lambda () nil))
                ((symbol-function 'kuro-kill)              (lambda () (setq kill-called t))))
        (kuro--check-process-exit)
        (should kill-called)))))

(ert-deftest kuro-poll-modes-check-exit-noop-when-alive ()
  "kuro--check-process-exit does not call kuro-kill when process is alive."
  (kuro-poll-test--with-buffer
    (setq-local kuro-kill-buffer-on-exit t)
    (let ((kill-called nil))
      (cl-letf (((symbol-function 'kuro--is-process-alive) (lambda () t))
                ((symbol-function 'kuro-kill)              (lambda () (setq kill-called t))))
        (kuro--check-process-exit)
        (should-not kill-called)))))

(ert-deftest kuro-poll-modes-check-exit-noop-when-flag-nil ()
  "kuro--check-process-exit does not call kuro-kill when kill-on-exit is nil."
  (kuro-poll-test--with-buffer
    (setq-local kuro-kill-buffer-on-exit nil)
    (let ((kill-called nil))
      (cl-letf (((symbol-function 'kuro--is-process-alive) (lambda () nil))
                ((symbol-function 'kuro-kill)              (lambda () (setq kill-called t))))
        (kuro--check-process-exit)
        (should-not kill-called)))))

;;; Group D: kuro--poll-prompt-mark-updates

(ert-deftest kuro-poll-modes-prompt-mark-updates-merges-marks ()
  "kuro--poll-prompt-mark-updates calls kuro--update-prompt-positions with marks."
  (kuro-poll-test--with-buffer
    (let ((update-called-with nil))
      (cl-letf (((symbol-function 'kuro--poll-prompt-marks)
                 (lambda () '(("prompt-start" 5 0 nil nil nil nil))))
                ((symbol-function 'kuro--update-prompt-positions)
                 (lambda (marks positions max)
                   (setq update-called-with (list marks positions max))
                   positions)))
        (kuro--poll-prompt-mark-updates)
        (should (equal (car update-called-with) '(("prompt-start" 5 0 nil nil nil nil))))))))

(ert-deftest kuro-poll-modes-prompt-mark-updates-noop-on-nil ()
  "kuro--poll-prompt-mark-updates does nothing when FFI returns nil."
  (kuro-poll-test--with-buffer
    (let ((update-called nil))
      (cl-letf (((symbol-function 'kuro--poll-prompt-marks) (lambda () nil))
                ((symbol-function 'kuro--update-prompt-positions)
                 (lambda (_m _p _mx) (setq update-called t) nil)))
        (kuro--poll-prompt-mark-updates)
        (should-not update-called)))))

;;; Group E: kuro--handle-clipboard-actions

(ert-deftest kuro-poll-modes-clipboard-write-only-policy ()
  "kuro--handle-clipboard-actions calls kill-new for write actions under write-only policy."
  (kuro-poll-test--with-buffer
    (let ((kill-new-called-with nil)
          (kuro-clipboard-policy 'write-only))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((write . "hello from terminal"))))
                ((symbol-function 'kill-new)
                 (lambda (text) (setq kill-new-called-with text)))
                ((symbol-function 'message) #'ignore))
        (kuro--handle-clipboard-actions)
        (should (equal kill-new-called-with "hello from terminal"))))))

(ert-deftest kuro-poll-modes-clipboard-deny-policy-does-not-write ()
  "kuro--handle-clipboard-actions does NOT call kill-new under deny policy."
  (kuro-poll-test--with-buffer
    (let ((kill-new-called nil)
          (kuro-clipboard-policy 'deny))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((write . "secret"))))
                ((symbol-function 'kill-new)
                 (lambda (_text) (setq kill-new-called t))))
        (kuro--handle-clipboard-actions)
        (should-not kill-new-called)))))

(ert-deftest kuro-poll-modes-clipboard-empty-actions-noop ()
  "kuro--handle-clipboard-actions is a no-op when the action list is nil."
  (kuro-poll-test--with-buffer
    (let ((kill-new-called nil))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () nil))
                ((symbol-function 'kill-new)
                 (lambda (_text) (setq kill-new-called t))))
        (kuro--handle-clipboard-actions)
        (should-not kill-new-called)))))

;;; Group F: kuro--poll-terminal-modes (cadence gating)

(ert-deftest kuro-poll-modes-tier1-fires-at-cadence-multiple ()
  "kuro--poll-terminal-modes calls kuro--poll-tier1-modes at cadence multiples."
  (kuro-poll-test--with-buffer
    (setq kuro--mode-poll-frame-count (* 2 kuro--mode-poll-cadence))
    (let ((tier1-called nil))
      (cl-letf (((symbol-function 'kuro--poll-tier1-modes)
                 (lambda () (setq tier1-called t)))
                ((symbol-function 'kuro--poll-osc-events) #'ignore))
        (kuro--poll-terminal-modes)
        (should tier1-called)))))

(ert-deftest kuro-poll-modes-tier1-silent-on-non-cadence-frame ()
  "kuro--poll-terminal-modes does NOT call tier1 on non-cadence frames."
  (kuro-poll-test--with-buffer
    (setq kuro--mode-poll-frame-count (1+ kuro--mode-poll-cadence))
    (let ((tier1-called nil))
      (cl-letf (((symbol-function 'kuro--poll-tier1-modes)
                 (lambda () (setq tier1-called t)))
                ((symbol-function 'kuro--poll-osc-events) #'ignore))
        (kuro--poll-terminal-modes)
        (should-not tier1-called)))))

;;; Group G: kuro--poll-terminal-modes tier-2 cadence

(ert-deftest kuro-poll-modes-tier2-fires-at-rare-cadence-multiple ()
  "kuro--poll-terminal-modes calls kuro--poll-osc-events at rare cadence multiples."
  (kuro-poll-test--with-buffer
    (setq kuro--mode-poll-frame-count (* 3 kuro--osc-rare-poll-cadence))
    (let ((osc-called nil))
      (cl-letf (((symbol-function 'kuro--poll-tier1-modes) #'ignore)
                ((symbol-function 'kuro--poll-osc-events)
                 (lambda () (setq osc-called t))))
        (kuro--poll-terminal-modes)
        (should osc-called)))))

(ert-deftest kuro-poll-modes-tier2-silent-on-non-rare-cadence-frame ()
  "kuro--poll-terminal-modes does NOT call kuro--poll-osc-events on non-rare-cadence frames."
  (kuro-poll-test--with-buffer
    ;; tier-1 fires (multiple of cadence) but NOT tier-2
    (setq kuro--mode-poll-frame-count kuro--mode-poll-cadence)
    (let ((osc-called nil))
      (cl-letf (((symbol-function 'kuro--poll-tier1-modes) #'ignore)
                ((symbol-function 'kuro--poll-osc-events)
                 (lambda () (setq osc-called t))))
        (kuro--poll-terminal-modes)
        (should-not osc-called)))))

(ert-deftest kuro-poll-modes-tier1-and-tier2-both-fire-at-lcm ()
  "Both tier-1 and tier-2 fire when frame count is a multiple of the rare cadence."
  (kuro-poll-test--with-buffer
    (setq kuro--mode-poll-frame-count kuro--osc-rare-poll-cadence)
    (let ((tier1-called nil) (osc-called nil))
      (cl-letf (((symbol-function 'kuro--poll-tier1-modes)
                 (lambda () (setq tier1-called t)))
                ((symbol-function 'kuro--poll-osc-events)
                 (lambda () (setq osc-called t))))
        (kuro--poll-terminal-modes)
        (should tier1-called)
        (should osc-called)))))

;;; Group H: kuro--poll-osc-events

(ert-deftest kuro-poll-modes-poll-osc-events-calls-palette-and-default-colors ()
  "kuro--poll-osc-events calls both kuro--apply-palette-updates and kuro--apply-default-colors."
  (kuro-poll-test--with-buffer
    (let ((palette-called nil) (default-colors-called nil))
      (cl-letf (((symbol-function 'kuro--apply-palette-updates)
                 (lambda () (setq palette-called t)))
                ((symbol-function 'kuro--apply-default-colors)
                 (lambda () (setq default-colors-called t))))
        (kuro--poll-osc-events)
        (should palette-called)
        (should default-colors-called)))))

;;; Group I: kuro--poll-image-events

(ert-deftest kuro-poll-modes-poll-image-events-calls-render-for-each-notification ()
  "kuro--poll-image-events calls kuro--render-image-notification for each entry."
  (kuro-poll-test--with-buffer
    (let ((rendered nil))
      (cl-letf (((symbol-function 'kuro--poll-image-notifications)
                 (lambda () '(notif-a notif-b)))
                ((symbol-function 'kuro--render-image-notification)
                 (lambda (n) (push n rendered))))
        (kuro--poll-image-events)
        (should (equal (nreverse rendered) '(notif-a notif-b)))))))

(ert-deftest kuro-poll-modes-poll-image-events-noop-on-empty-list ()
  "kuro--poll-image-events does nothing when no notifications are pending."
  (kuro-poll-test--with-buffer
    (let ((render-called nil))
      (cl-letf (((symbol-function 'kuro--poll-image-notifications)
                 (lambda () nil))
                ((symbol-function 'kuro--render-image-notification)
                 (lambda (_n) (setq render-called t))))
        (kuro--poll-image-events)
        (should-not render-called)))))

;;; Group J: kuro--poll-tier1-modes

(ert-deftest kuro-poll-modes-tier1-modes-applies-modes-when-ffi-returns-list ()
  "kuro--poll-tier1-modes applies terminal modes when kuro--get-terminal-modes returns a list."
  (kuro-poll-test--with-buffer
    (cl-letf (((symbol-function 'kuro--get-terminal-modes)
               (lambda () '(t nil 1003 t nil t 0)))
              ((symbol-function 'kuro--poll-cwd) #'ignore)
              ((symbol-function 'kuro--handle-clipboard-actions) #'ignore)
              ((symbol-function 'kuro--poll-prompt-mark-updates) #'ignore)
              ((symbol-function 'kuro--poll-image-events) #'ignore)
              ((symbol-function 'kuro--check-process-exit) #'ignore))
      (kuro--poll-tier1-modes)
      (should (eq kuro--application-cursor-keys-mode t))
      (should (= kuro--mouse-mode 1003)))))

(ert-deftest kuro-poll-modes-tier1-modes-skips-apply-when-ffi-returns-nil ()
  "kuro--poll-tier1-modes skips kuro--apply-terminal-modes when FFI returns nil."
  (kuro-poll-test--with-buffer
    (setq kuro--application-cursor-keys-mode 'original)
    (cl-letf (((symbol-function 'kuro--get-terminal-modes) (lambda () nil))
              ((symbol-function 'kuro--poll-cwd) #'ignore)
              ((symbol-function 'kuro--handle-clipboard-actions) #'ignore)
              ((symbol-function 'kuro--poll-prompt-mark-updates) #'ignore)
              ((symbol-function 'kuro--poll-image-events) #'ignore)
              ((symbol-function 'kuro--check-process-exit) #'ignore))
      (kuro--poll-tier1-modes)
      ;; Flag must be unchanged because apply-terminal-modes was not called.
      (should (eq kuro--application-cursor-keys-mode 'original)))))

(ert-deftest kuro-poll-modes-tier1-modes-calls-all-tier1-fns ()
  "kuro--poll-tier1-modes invokes every function in kuro--tier1-poll-fns."
  (kuro-poll-test--with-buffer
    (let ((calls nil))
      (cl-letf (((symbol-function 'kuro--get-terminal-modes) (lambda () nil))
                ((symbol-function 'kuro--poll-cwd)
                 (lambda () (push 'cwd calls)))
                ((symbol-function 'kuro--handle-clipboard-actions)
                 (lambda () (push 'clipboard calls)))
                ((symbol-function 'kuro--poll-prompt-mark-updates)
                 (lambda () (push 'prompts calls)))
                ((symbol-function 'kuro--poll-image-events)
                 (lambda () (push 'images calls)))
                ((symbol-function 'kuro--check-process-exit)
                 (lambda () (push 'exit calls))))
        (kuro--poll-tier1-modes)
        (should (memq 'cwd calls))
        (should (memq 'clipboard calls))
        (should (memq 'prompts calls))
        (should (memq 'images calls))
        (should (memq 'exit calls))))))

;;; Group K: kuro--handle-clipboard-actions — allow and prompt policies

(ert-deftest kuro-poll-modes-clipboard-allow-policy-writes-kill-ring ()
  "kuro--handle-clipboard-actions calls kill-new for write actions under allow policy."
  (kuro-poll-test--with-buffer
    (let ((kill-new-called-with nil)
          (kuro-clipboard-policy 'allow))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((write . "allowed text"))))
                ((symbol-function 'kill-new)
                 (lambda (text) (setq kill-new-called-with text)))
                ((symbol-function 'message) #'ignore))
        (kuro--handle-clipboard-actions)
        (should (equal kill-new-called-with "allowed text"))))))

(ert-deftest kuro-poll-modes-clipboard-prompt-write-accepted ()
  "kuro--handle-clipboard-actions calls kill-new under prompt policy when user accepts."
  (kuro-poll-test--with-buffer
    (let ((kill-new-called nil)
          (kuro-clipboard-policy 'prompt))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((write . "prompted text"))))
                ((symbol-function 'yes-or-no-p) (lambda (_prompt) t))
                ((symbol-function 'kill-new)
                 (lambda (_text) (setq kill-new-called t))))
        (kuro--handle-clipboard-actions)
        (should kill-new-called)))))

(ert-deftest kuro-poll-modes-clipboard-prompt-write-rejected ()
  "kuro--handle-clipboard-actions does NOT call kill-new under prompt policy when user declines."
  (kuro-poll-test--with-buffer
    (let ((kill-new-called nil)
          (kuro-clipboard-policy 'prompt))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((write . "rejected text"))))
                ((symbol-function 'yes-or-no-p) (lambda (_prompt) nil))
                ((symbol-function 'kill-new)
                 (lambda (_text) (setq kill-new-called t))))
        (kuro--handle-clipboard-actions)
        (should-not kill-new-called)))))

(ert-deftest kuro-poll-modes-clipboard-allow-policy-sends-query-response ()
  "kuro--handle-clipboard-actions sends OSC 52 response for query under allow policy."
  (kuro-poll-test--with-buffer
    (let ((sent-key nil)
          (kuro-clipboard-policy 'allow))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((query))))
                ((symbol-function 'current-kill) (lambda (_n _do-not-move) "clip text"))
                ((symbol-function 'kuro--send-key)
                 (lambda (s) (setq sent-key s))))
        (kuro--handle-clipboard-actions)
        (should (stringp sent-key))
        (should (string-prefix-p "\e]52;c;" sent-key))))))

(ert-deftest kuro-poll-modes-clipboard-query-deny-policy-does-not-send ()
  "kuro--handle-clipboard-actions does NOT send query response under deny policy."
  (kuro-poll-test--with-buffer
    (let ((sent-key nil)
          (kuro-clipboard-policy 'deny))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((query))))
                ((symbol-function 'kuro--send-key)
                 (lambda (s) (setq sent-key s))))
        (kuro--handle-clipboard-actions)
        (should-not sent-key)))))

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

(provide 'kuro-poll-modes-test)

;;; kuro-poll-modes-test.el ends here
