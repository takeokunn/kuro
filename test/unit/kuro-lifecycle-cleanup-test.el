;;; kuro-lifecycle-state-ext-test.el --- Extended unit tests for kuro-lifecycle.el state management  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;;; Commentary:

;; ERT tests for kuro-lifecycle.el — supplemental coverage.
;; Split from kuro-lifecycle-state-test.el to keep individual files under 500 lines.
;;
;; Tests run without the Rust dynamic module: all FFI primitives are stubbed
;; before `kuro-lifecycle' is loaded.  When loaded after kuro-test.el
;; (as the Makefile does), the stubs in kuro-test.el are already present;
;; the `unless (fboundp …)' guards here handle standalone loading.
;;
;; Groups:
;;   Group 17: kuro--rollback-attach — message and kill-buffer
;;   Group 18: kuro--teardown-session — process not alive
;;   Group 19: kuro--prefill-buffer — edge cases
;;   Group 24: kuro--rollback-attach — kill-buffer arg, noop-dead, state
;;   Group 25: kuro--schedule-initial-render — dead-buffer, live, timer

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-lifecycle-test-support)

;;; ── Group 24: kuro--rollback-attach — kill-buffer arg, noop-dead, state ─────
;;
;; Verifies the exact buffer argument passed to kill-buffer, that passing a
;; dead buffer causes no error, and that session state variables are cleared.

(ert-deftest kuro-lifecycle-ext-rollback-attach-kills-correct-buffer ()
  "kuro--rollback-attach calls kill-buffer with the exact buffer argument."
  (let* ((buf (generate-new-buffer " *kuro-ext-rollback-correct*"))
         (killed nil)
         (kuro--session-id 0)
         (kuro--initialized nil))
    (cl-letf (((symbol-function 'kuro-core-detach) #'ignore)
              ((symbol-function 'message)           #'ignore)
              ((symbol-function 'kill-buffer)
               (lambda (b) (setq killed b))))
      (kuro--rollback-attach 7 buf "err")
      (should (eq killed buf)))
    ;; Clean up in case our stub skipped the real kill.
    (when (buffer-live-p buf)
      (kill-buffer buf))))

(ert-deftest kuro-lifecycle-ext-rollback-attach-noop-when-buffer-dead ()
  "kuro--rollback-attach does not signal when the buffer is already dead."
  (let ((dead-buf (generate-new-buffer " *kuro-ext-rollback-dead*"))
        (kuro--session-id 0)
        (kuro--initialized nil))
    (kill-buffer dead-buf)
    (cl-letf (((symbol-function 'kuro-core-detach) #'ignore)
              ((symbol-function 'message)           #'ignore))
      ;; Pass the dead buffer; real kill-buffer on a dead buffer does not signal.
      (should-not (condition-case err
                      (progn (kuro--rollback-attach 0 dead-buf "e") nil)
                    (error err))))))

(ert-deftest kuro-lifecycle-ext-rollback-attach-clears-session-state ()
  "kuro--rollback-attach resets kuro--initialized to nil and kuro--session-id to 0."
  (with-temp-buffer
    (let ((kuro--session-id 42)
          (kuro--initialized t))
      (cl-letf (((symbol-function 'kuro-core-detach) #'ignore)
                ((symbol-function 'message)           #'ignore)
                ((symbol-function 'kill-buffer)       #'ignore))
        (kuro--rollback-attach 42 (current-buffer) "state-test")
        (should-not kuro--initialized)
        (should (= kuro--session-id 0))))))

;;; ── Group 25: kuro--schedule-initial-render — dead-buffer, live, timer ──────
;;
;; Supplemental coverage: render called when live, skipped when dead, and
;; that the function schedules via run-with-idle-timer (not a direct call).

(ert-deftest kuro-lifecycle-ext-schedule-initial-render-calls-render-when-buffer-live ()
  "Timer callback calls kuro--render-cycle when the buffer is still live."
  (let ((render-called nil)
        (captured-fn   nil))
    (cl-letf (((symbol-function 'run-with-idle-timer)
               (lambda (_delay _repeat fn &rest _args)
                 (setq captured-fn fn)))
              ((symbol-function 'kuro--render-cycle)
               (lambda () (setq render-called t))))
      (with-temp-buffer
        (let ((live-buf (current-buffer)))
          (kuro--schedule-initial-render live-buf)
          ;; Invoke callback while buffer is still live.
          (funcall captured-fn live-buf))))
    (should render-called)))

(ert-deftest kuro-lifecycle-ext-schedule-initial-render-skips-render-when-buffer-dead ()
  "Timer callback does not call kuro--render-cycle when the buffer is dead."
  (let ((render-called nil)
        (captured-fn   nil)
        (dead-buf      nil))
    (cl-letf (((symbol-function 'run-with-idle-timer)
               (lambda (_delay _repeat fn &rest _args)
                 (setq captured-fn fn))))
      (with-temp-buffer
        (setq dead-buf (current-buffer))
        (kuro--schedule-initial-render dead-buf)))
    ;; Kill the buffer so buffer-live-p returns nil.
    (when (buffer-live-p dead-buf)
      (kill-buffer dead-buf))
    (cl-letf (((symbol-function 'kuro--render-cycle)
               (lambda () (setq render-called t))))
      (funcall captured-fn dead-buf))
    (should-not render-called)))

(ert-deftest kuro-lifecycle-ext-schedule-initial-render-uses-run-with-idle-timer ()
  "kuro--schedule-initial-render schedules via run-with-idle-timer."
  (let ((timer-scheduled nil))
    (cl-letf (((symbol-function 'run-with-idle-timer)
               (lambda (_delay _repeat _fn &rest _args)
                 (setq timer-scheduled t))))
      (with-temp-buffer
        (kuro--schedule-initial-render (current-buffer))))
    (should timer-scheduled)))

;;; ── Group 17: kuro--rollback-attach — message and kill-buffer ───────────────
;;
;; Supplements Group 12 by verifying that rollback logs the session ID in
;; the message string and that it kills the supplied buffer.

(ert-deftest kuro-lifecycle--rollback-attach-logs-session-id ()
  "kuro--rollback-attach includes the session ID in the message it prints."
  (with-temp-buffer
    (let ((kuro--session-id 0)
          (kuro--initialized nil)
          (msg-logged nil))
      (cl-letf (((symbol-function 'kuro-core-detach) #'ignore)
                ((symbol-function 'kill-buffer)       #'ignore)
                ((symbol-function 'message)
                 (lambda (fmt &rest args)
                   (setq msg-logged (apply #'format fmt args)))))
        (kuro--rollback-attach 88 (current-buffer) "boom")
        (should (stringp msg-logged))
        (should (string-match-p "88" msg-logged))))))

(ert-deftest kuro-lifecycle--rollback-attach-kills-buffer ()
  "kuro--rollback-attach kills the buffer argument it receives."
  (let ((buf (generate-new-buffer " *kuro-rollback-test*"))
        (killed-buf nil))
    (let ((kuro--session-id 0)
          (kuro--initialized nil))
      (cl-letf (((symbol-function 'kuro-core-detach) #'ignore)
                ((symbol-function 'message)           #'ignore)
                ((symbol-function 'kill-buffer)
                 (lambda (b) (setq killed-buf b))))
        (kuro--rollback-attach 1 buf "err")
        (should (eq killed-buf buf))))))

(ert-deftest kuro-lifecycle--rollback-attach-returns-nil ()
  "kuro--rollback-attach always returns nil."
  (with-temp-buffer
    (let ((kuro--session-id 0)
          (kuro--initialized nil))
      (cl-letf (((symbol-function 'kuro-core-detach) #'ignore)
                ((symbol-function 'message)           #'ignore)
                ((symbol-function 'kill-buffer)       #'ignore))
        (should (null (kuro--rollback-attach 2 (current-buffer) "e")))))))

;;; ── Group 18: kuro--teardown-session — process not alive ────────────────────
;;
;; When kuro--initialized is t but kuro--is-process-alive returns nil, the
;; teardown must call kuro--shutdown directly without prompting the user.

(ert-deftest kuro-lifecycle--teardown-no-prompt-when-process-dead ()
  "kuro--teardown-session skips yes-or-no-p when the process is not alive."
  (let ((kuro--initialized   t)
        (kuro--session-id    40)
        (prompt-called       nil)
        (shutdown-called     nil))
    (cl-letf (((symbol-function 'kuro--is-process-alive)
               (lambda () nil))
              ((symbol-function 'yes-or-no-p)
               (lambda (_p) (setq prompt-called t) t))
              ((symbol-function 'kuro--shutdown)
               (lambda () (setq shutdown-called t))))
      (kuro--teardown-session)
      (should-not prompt-called)
      (should     shutdown-called))))

(ert-deftest kuro-lifecycle--teardown-calls-shutdown-when-not-alive ()
  "kuro--teardown-session calls kuro--shutdown when the process is not alive."
  (let ((kuro--initialized  t)
        (kuro--session-id   50)
        (shutdown-called    nil))
    (cl-letf (((symbol-function 'kuro--is-process-alive) (lambda () nil))
              ((symbol-function 'kuro--shutdown)
               (lambda () (setq shutdown-called t))))
      (kuro--teardown-session)
      (should shutdown-called))))

;;; ── Group 19: kuro--prefill-buffer — edge cases ─────────────────────────────
;;
;; Verifies zero-row behaviour and that buffer content is replaced (not appended).

(ert-deftest kuro-lifecycle--prefill-buffer-zero-rows-empty-buffer ()
  "kuro--prefill-buffer with 0 rows leaves the buffer empty (no newlines)."
  (with-temp-buffer
    (let ((inhibit-read-only t))
      (insert "existing text")
      (kuro--prefill-buffer 0)
      (should (= (buffer-size) 0)))))

(ert-deftest kuro-lifecycle--prefill-buffer-replaces-not-appends ()
  "kuro--prefill-buffer replaces existing content rather than appending to it."
  (with-temp-buffer
    (let ((inhibit-read-only t))
      (dotimes (_ 20)
        (insert "line\n"))
      (kuro--prefill-buffer 3)
      ;; Should have exactly 3 lines, not 20 + 3.
      (should (= (count-lines (point-min) (point-max)) 3)))))

(provide 'kuro-lifecycle-state-ext-test)

;;; kuro-lifecycle-state-ext-test.el ends here
