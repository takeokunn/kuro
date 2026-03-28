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
                 (lambda () '(("prompt-start" 5 0))))
                ((symbol-function 'kuro--update-prompt-positions)
                 (lambda (marks positions max)
                   (setq update-called-with (list marks positions max))
                   positions)))
        (kuro--poll-prompt-mark-updates)
        (should (equal (car update-called-with) '(("prompt-start" 5 0))))))))

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

(provide 'kuro-poll-modes-test)

;;; kuro-poll-modes-test.el ends here
