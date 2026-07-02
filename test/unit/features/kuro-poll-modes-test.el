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

(require 'kuro-poll-modes-test-support)

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
  (kuro-poll-test--check-exit nil t should))

(ert-deftest kuro-poll-modes-check-exit-noop-when-alive ()
  "kuro--check-process-exit does not call kuro-kill when process is alive."
  (kuro-poll-test--check-exit t t should-not))

(ert-deftest kuro-poll-modes-check-exit-noop-when-flag-nil ()
  "kuro--check-process-exit does not call kuro-kill when kill-on-exit is nil."
  (kuro-poll-test--check-exit nil nil should-not))

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
                 (lambda () '((write "hello from terminal" "clipboard"))))
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
                 (lambda () '((write "secret" "clipboard"))))
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

;;; Group E2: kuro--handle-notifications (OSC 9 / OSC 777)

(ert-deftest kuro-poll-modes-notifications-displayed-when-enabled ()
  "kuro--handle-notifications invokes kuro-notification-function per notification."
  (kuro-poll-test--with-buffer
    ;; let* so the notification lambda closes over the just-bound `calls'.
    (let* ((calls nil)
           (kuro-notifications-enabled t)
           (kuro-notification-function
            (lambda (title body &optional _id _report) (push (cons title body) calls))))
      (cl-letf (((symbol-function 'kuro--poll-notifications)
                 (lambda () '(("Build" "done" nil nil) (nil "ping" nil nil)))))
        (kuro--handle-notifications)
        (should (equal (nreverse calls)
                       '(("Build" . "done") (nil . "ping"))))))))

(ert-deftest kuro-poll-modes-notifications-suppressed-when-disabled ()
  "kuro--handle-notifications drains the queue but displays nothing when disabled."
  (kuro-poll-test--with-buffer
    (let ((displayed nil)
          (drained nil)
          (kuro-notifications-enabled nil)
          (kuro-notification-function (lambda (_t _b &optional _id _report) (setq displayed t))))
      (cl-letf (((symbol-function 'kuro--poll-notifications)
                 (lambda () (setq drained t) '((nil "ignored" nil nil)))))
        (kuro--handle-notifications)
        (should drained)         ; always drains so the queue cannot grow
        (should-not displayed))))) ; but nothing is shown

(ert-deftest kuro-poll-modes-notifications-empty-noop ()
  "kuro--handle-notifications is a no-op when nothing is pending."
  (kuro-poll-test--with-buffer
    (let ((displayed nil)
          (kuro-notifications-enabled t)
          (kuro-notification-function (lambda (_t _b &optional _id _report) (setq displayed t))))
      (cl-letf (((symbol-function 'kuro--poll-notifications) (lambda () nil)))
        (kuro--handle-notifications)
        (should-not displayed)))))

(ert-deftest kuro-poll-modes-default-notify-falls-back-to-message ()
  "kuro--default-notify uses the echo area (TITLE: BODY) when D-Bus is unavailable."
  (kuro-poll-test--assert-default-notify "Title" "Body" "Title: Body"))

(ert-deftest kuro-poll-modes-default-notify-no-title-omits-prefix ()
  "kuro--default-notify shows only BODY when TITLE is nil."
  (kuro-poll-test--assert-default-notify nil "Body only" "Body only"))

(ert-deftest kuro-poll-modes-default-notify-empty-title-omits-prefix ()
  "kuro--default-notify shows only BODY when TITLE is an empty string."
  (kuro-poll-test--assert-default-notify "" "Body only" "Body only"))

;;; Group F: kuro--poll-terminal-modes (cadence gating)

(ert-deftest kuro-poll-modes-tier1-fires-at-cadence-multiple ()
  "kuro--poll-terminal-modes calls kuro--poll-tier1-modes at cadence multiples."
  (kuro-poll-test--assert-tier1 (* 2 kuro--mode-poll-cadence) should))

(ert-deftest kuro-poll-modes-tier1-silent-on-non-cadence-frame ()
  "kuro--poll-terminal-modes does NOT call tier1 on non-cadence frames."
  (kuro-poll-test--assert-tier1 (1+ kuro--mode-poll-cadence) should-not))

;;; Group G: kuro--poll-terminal-modes tier-2 cadence

(ert-deftest kuro-poll-modes-tier2-fires-at-rare-cadence-multiple ()
  "kuro--poll-terminal-modes calls kuro--poll-osc-events at rare cadence multiples."
  (kuro-poll-test--assert-tier2 (* 3 kuro--osc-rare-poll-cadence) should))

(ert-deftest kuro-poll-modes-tier2-silent-on-non-rare-cadence-frame ()
  "kuro--poll-terminal-modes does NOT call kuro--poll-osc-events on non-rare-cadence frames."
  ;; tier-1 fires (multiple of cadence) but NOT tier-2
  (kuro-poll-test--assert-tier2 kuro--mode-poll-cadence should-not))

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
                 (lambda () (setq default-colors-called t)))
                ((symbol-function 'kuro--handle-notifications) #'ignore))
        (kuro--poll-osc-events)
        (should palette-called)
        (should default-colors-called)))))

(ert-deftest kuro-poll-modes-poll-osc-events-calls-handle-notifications ()
  "kuro--poll-osc-events calls kuro--handle-notifications."
  (kuro-poll-test--with-buffer
    (let ((notif-called nil))
      (cl-letf (((symbol-function 'kuro--apply-palette-updates) #'ignore)
                ((symbol-function 'kuro--apply-default-colors) #'ignore)
                ((symbol-function 'kuro--handle-notifications)
                 (lambda () (setq notif-called t))))
        (kuro--poll-osc-events)
        (should notif-called)))))

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
  (kuro-poll-test--with-tier1-stubs (lambda () '(t nil 1003 t nil t 0))
    (kuro--poll-tier1-modes)
    (should (eq kuro--application-cursor-keys-mode t))
    (should (= kuro--mouse-mode 1003))))

(ert-deftest kuro-poll-modes-tier1-modes-skips-apply-when-ffi-returns-nil ()
  "kuro--poll-tier1-modes skips kuro--apply-terminal-modes when FFI returns nil."
  (kuro-poll-test--with-tier1-stubs (lambda () nil)
    (setq kuro--application-cursor-keys-mode 'original)
    (kuro--poll-tier1-modes)
    ;; Flag must be unchanged because apply-terminal-modes was not called.
    (should (eq kuro--application-cursor-keys-mode 'original))))

(ert-deftest kuro-poll-modes-tier1-modes-calls-all-tier1-fns ()
  "kuro--poll-tier1-modes invokes every function in kuro--tier1-poll-fns."
  (kuro-poll-test--with-buffer
    (let ((calls nil))
      (cl-letf (((symbol-function 'kuro--poll-terminal-mode-state)
                 (lambda () (push 'modes calls)))
                ((symbol-function 'kuro--poll-cwd)
                 (lambda () (push 'cwd calls)))
                ((symbol-function 'kuro--handle-clipboard-actions)
                 (lambda () (push 'clipboard calls)))
                ((symbol-function 'kuro--poll-prompt-mark-updates)
                 (lambda () (push 'prompts calls)))
                ((symbol-function 'kuro--poll-eval-command-updates)
                 (lambda () (push 'eval calls)))
                ((symbol-function 'kuro--poll-image-events)
                 (lambda () (push 'images calls)))
                ((symbol-function 'kuro--apply-hyperlink-ranges)
                 (lambda () (push 'hyperlinks calls)))
                ((symbol-function 'kuro--poll-progress)
                 (lambda () (push 'progress calls)))
                ((symbol-function 'kuro--poll-user-vars)
                 (lambda () (push 'user-vars calls)))
                ((symbol-function 'kuro--check-process-exit)
                 (lambda () (push 'exit calls))))
        (kuro--poll-tier1-modes)
        (should (memq 'modes calls))
        (should (memq 'cwd calls))
        (should (memq 'progress calls))
        (should (memq 'user-vars calls))
        (should (memq 'clipboard calls))
        (should (memq 'prompts calls))
        (should (memq 'eval calls))
        (should (memq 'images calls))
        (should (memq 'hyperlinks calls))
        (should (memq 'exit calls))))))

;;; Group: OSC 9;4 progress (ConEmu) mode-line indicator

(ert-deftest kuro-poll-modes-progress-state-glyph-known ()
  "kuro--progress-state-glyph maps known states to their glyph strings."
  (let ((kuro-progress-state-glyphs '((1 . "A") (2 . "B"))))
    (should (equal (kuro--progress-state-glyph 1) "A"))
    (should (equal (kuro--progress-state-glyph 2) "B"))))

(ert-deftest kuro-poll-modes-progress-state-glyph-unknown ()
  "kuro--progress-state-glyph returns empty string for unknown states."
  (let ((kuro-progress-state-glyphs '((1 . "A"))))
    (should (equal (kuro--progress-state-glyph 9) ""))))

(ert-deftest kuro-poll-modes-progress-mode-line-string-formats ()
  "kuro--progress-mode-line-string formats glyph + percent via kuro-progress-format."
  (let ((kuro-progress-format " %s%d%% ")
        (kuro-progress-state-glyphs '((1 . "X"))))
    (should (equal (kuro--progress-mode-line-string 1 42) " X42% "))))

(ert-deftest kuro-poll-modes-progress-mode-line-string-nil-format ()
  "kuro--progress-mode-line-string returns nil when kuro-progress-format is nil."
  (let ((kuro-progress-format nil))
    (should-not (kuro--progress-mode-line-string 1 42))))

(ert-deftest kuro-poll-modes-apply-progress-stores-active ()
  "kuro--apply-progress stores a non-zero-state progress cons when enabled."
  (kuro-poll-test--with-buffer
    (let ((kuro-progress-enabled t))
      (cl-letf (((symbol-function 'force-mode-line-update) #'ignore))
        (kuro--apply-progress '(1 . 50)))
      (should (equal kuro--progress-state '(1 . 50))))))

(ert-deftest kuro-poll-modes-apply-progress-state-zero-clears ()
  "kuro--apply-progress clears the indicator on state 0 (done)."
  (kuro-poll-test--with-buffer
    (setq kuro--progress-state '(1 . 50))
    (let ((kuro-progress-enabled t))
      (cl-letf (((symbol-function 'force-mode-line-update) #'ignore))
        (kuro--apply-progress '(0 . 0)))
      (should-not kuro--progress-state))))

(ert-deftest kuro-poll-modes-apply-progress-disabled-clears ()
  "kuro--apply-progress clears the indicator when kuro-progress-enabled is nil."
  (kuro-poll-test--with-buffer
    (let ((kuro-progress-enabled nil))
      (cl-letf (((symbol-function 'force-mode-line-update) #'ignore))
        (kuro--apply-progress '(2 . 75)))
      (should-not kuro--progress-state))))

(ert-deftest kuro-poll-modes-poll-progress-applies-ffi ()
  "kuro--poll-progress routes a non-nil FFI result into kuro--progress-state."
  (kuro-poll-test--with-buffer
    (let ((kuro-progress-enabled t))
      (cl-letf (((symbol-function 'kuro--get-progress) (lambda () '(2 . 80)))
                ((symbol-function 'force-mode-line-update) #'ignore))
        (kuro--poll-progress)
        (should (equal kuro--progress-state '(2 . 80)))))))

(ert-deftest kuro-poll-modes-poll-progress-nil-leaves-state ()
  "kuro--poll-progress leaves the cached indicator untouched on nil FFI result."
  (kuro-poll-test--with-buffer
    (setq kuro--progress-state '(1 . 10))
    (cl-letf (((symbol-function 'kuro--get-progress) (lambda () nil))
              ((symbol-function 'force-mode-line-update) #'ignore))
      (kuro--poll-progress)
      (should (equal kuro--progress-state '(1 . 10))))))

(ert-deftest kuro-poll-modes-progress-mode-line-active-and-inactive ()
  "kuro--progress-mode-line yields a string when active, nil when inactive."
  (kuro-poll-test--with-buffer
    (let ((kuro-progress-format " %s%d%% ")
          (kuro-progress-state-glyphs '((1 . "X"))))
      (setq kuro--progress-state '(1 . 33))
      (should (equal (kuro--progress-mode-line) " X33% "))
      (setq kuro--progress-state nil)
      (should-not (kuro--progress-mode-line)))))

;;; Group: OSC 1337 SetUserVar user variables

(ert-deftest kuro-poll-modes-poll-user-vars-stores-alist ()
  "kuro--poll-user-vars stores the FFI alist into kuro--user-vars."
  (kuro-poll-test--with-buffer
    (cl-letf (((symbol-function 'kuro--poll-user-vars-raw)
               (lambda () '(("FOO" . "bar") ("BAZ" . "qux")))))
      (kuro--poll-user-vars)
      (should (equal kuro--user-vars '(("FOO" . "bar") ("BAZ" . "qux"))))
      (should (equal (cdr (assoc "FOO" kuro--user-vars)) "bar")))))

(ert-deftest kuro-poll-modes-poll-user-vars-nil-leaves-cache ()
  "kuro--poll-user-vars leaves the cached alist untouched on nil FFI result."
  (kuro-poll-test--with-buffer
    (setq kuro--user-vars '(("OLD" . "v")))
    (cl-letf (((symbol-function 'kuro--poll-user-vars-raw) (lambda () nil)))
      (kuro--poll-user-vars)
      (should (equal kuro--user-vars '(("OLD" . "v")))))))

(provide 'kuro-poll-modes-test)
;;; kuro-poll-modes-test.el ends here
