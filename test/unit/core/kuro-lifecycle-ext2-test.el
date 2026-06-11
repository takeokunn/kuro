;;; kuro-lifecycle-ext2-test.el --- Lifecycle tests: cleanup, attach, module  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;;; Commentary:

;; ERT tests for kuro-lifecycle.el — Groups 17–30.
;; Groups 1–12 are in kuro-lifecycle-test.el.
;; Groups 13–26 are in kuro-lifecycle-ext-test.el.
;;
;; Groups:
;;   Group 17 (cleanup): kuro--rollback-attach — message and kill-buffer
;;   Group 18 (cleanup): kuro--teardown-session — process not alive
;;   Group 19 (cleanup): kuro--prefill-buffer — edge cases
;;   Group 20 (attach): kuro--do-attach — resize and prefill args
;;   Group 21 (attach): kuro-attach — public API
;;   Group 22 (attach): kuro--schedule-initial-render — live-buffer path

;;   Group 23 (attach): kuro--init-session-buffer — font/remap calls
;;   Group 24 (cleanup): kuro--rollback-attach — kill-buffer arg, noop-dead
;;   Group 25 (cleanup): kuro--schedule-initial-render — dead-buffer, live
;;   Group 27: kuro--module-loadable-p
;;   Group 28: kuro--try-load-module
;;   Group 29: kuro--prompt-and-install-module
;;   Group 30: kuro-create — buffer lifecycle

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-lifecycle-test-support)

;;; ── Group 17 (cleanup): kuro--rollback-attach — message and kill-buffer ──────
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

;;; ── Group 18 (cleanup): kuro--teardown-session — process not alive ───────────
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

;;; ── Group 19 (cleanup): kuro--prefill-buffer — edge cases ───────────────────
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

;;; ── Group 20 (attach): kuro--do-attach — resize and prefill args ────────────
;;
;; Verifies that kuro--do-attach forwards rows/cols to kuro--resize and that
;; kuro--prefill-buffer receives the row count.

(ert-deftest kuro-lifecycle--do-attach-calls-resize-with-rows-cols ()
  "kuro--do-attach calls kuro--resize with the supplied rows and cols."
  (with-temp-buffer
    (let (kuro--session-id kuro--initialized
          (resize-rows nil)
          (resize-cols nil))
      (kuro-lifecycle-test--with-attach-stubs
        (cl-letf (((symbol-function 'kuro--resize)
                   (lambda (r c) (setq resize-rows r resize-cols c))))
          (kuro--do-attach 3 15 60)
          (should (= resize-rows 15))
          (should (= resize-cols 60)))))))

(ert-deftest kuro-lifecycle--do-attach-calls-prefill-with-rows ()
  "kuro--do-attach passes the rows argument to kuro--prefill-buffer."
  (with-temp-buffer
    (let (kuro--session-id kuro--initialized
          (prefill-rows nil))
      (kuro-lifecycle-test--with-attach-stubs
        (cl-letf (((symbol-function 'kuro--prefill-buffer)
                   (lambda (r) (setq prefill-rows r))))
          (kuro--do-attach 4 18 72)
          (should (= prefill-rows 18)))))))

;;; Group 21 (attach): kuro-attach — public API (error rollback, success message, buffer naming)
;;
;; kuro-attach creates a fresh buffer, enters kuro-mode, then calls kuro--do-attach.
;; On error it calls kuro--rollback-attach; on success it prints a message.

(ert-deftest kuro-lifecycle--attach-calls-rollback-on-do-attach-error ()
  "kuro-attach calls kuro--rollback-attach when kuro--do-attach signals."
  (let ((rollback-called-with-id nil)
        (result nil))
    (cl-letf (((symbol-function 'kuro--ensure-module-loaded) #'ignore)
              ((symbol-function 'kuro-mode)
               (lambda () (setq major-mode 'kuro-mode)))
              ((symbol-function 'kuro--do-attach)
               (lambda (_id _r _c) (error "attach failed")))
              ((symbol-function 'kuro--rollback-attach)
               (lambda (id _buf _err) (setq rollback-called-with-id id))))
      (setq result (kuro-attach 7))
      (when (buffer-live-p result) (kill-buffer result))
      (should (= rollback-called-with-id 7)))))

(ert-deftest kuro-lifecycle--attach-prints-success-message ()
  "kuro-attach prints a message mentioning the session ID on success."
  (let ((msgs nil)
        (result nil))
    (cl-letf (((symbol-function 'kuro--ensure-module-loaded) #'ignore)
              ((symbol-function 'kuro-mode)
               (lambda () (setq major-mode 'kuro-mode)))
              ((symbol-function 'kuro--do-attach) #'ignore)
              ((symbol-function 'message)
               (lambda (fmt &rest args)
                 (push (apply #'format fmt args) msgs))))
      (setq result (kuro-attach 42))
      (unwind-protect
          (should (cl-some (lambda (m) (string-match-p "42" m)) msgs))
        (when (buffer-live-p result) (kill-buffer result))))))

(ert-deftest kuro-lifecycle--attach-buffer-name-includes-session-id ()
  "kuro-attach creates a buffer whose name contains the session ID."
  (let ((created-buf nil))
    (cl-letf (((symbol-function 'kuro--ensure-module-loaded) #'ignore)
              ((symbol-function 'kuro-mode)
               (lambda () (setq major-mode 'kuro-mode)))
              ((symbol-function 'kuro--do-attach) #'ignore)
              ((symbol-function 'message)          #'ignore))
      (setq created-buf (kuro-attach 99))
      (unwind-protect
          (should (string-match-p "99" (buffer-name created-buf)))
        (when (buffer-live-p created-buf)
          (kill-buffer created-buf))))))

(ert-deftest kuro-lifecycle--attach-returns-buffer ()
  "kuro-attach returns the newly created buffer."
  (let ((result nil))
    (cl-letf (((symbol-function 'kuro--ensure-module-loaded) #'ignore)
              ((symbol-function 'kuro-mode)
               (lambda () (setq major-mode 'kuro-mode)))
              ((symbol-function 'kuro--do-attach) #'ignore)
              ((symbol-function 'message)          #'ignore))
      (setq result (kuro-attach 3))
      (unwind-protect
          (should (bufferp result))
        (when (buffer-live-p result)
          (kill-buffer result))))))

;;; Group 22 (attach): kuro--schedule-initial-render — live-buffer path and timer lambda
;;
;; Supplements Group 14: verifies that when the buffer IS live, the timer lambda
;; calls kuro--render-cycle.

(ert-deftest kuro-lifecycle--schedule-initial-render-fires-render-when-live ()
  "Timer lambda calls kuro--render-cycle when the buffer is still live."
  (let ((render-called nil)
        (captured-fn nil))
    (cl-letf (((symbol-function 'run-with-idle-timer)
               (lambda (_delay _repeat fn &rest _args)
                 (setq captured-fn fn)))
              ((symbol-function 'kuro--render-cycle)
               (lambda () (setq render-called t))))
      (with-temp-buffer
        (let ((live-buf (current-buffer)))
          (kuro--schedule-initial-render live-buf)
          ;; Invoke the timer lambda directly while the buffer is still live.
          (funcall captured-fn live-buf))))
    (should render-called)))

(ert-deftest kuro-lifecycle--schedule-initial-render-uses-startup-delay-constant ()
  "kuro--schedule-initial-render uses kuro--startup-render-delay (0.05 s)."
  (should (= kuro--startup-render-delay 0.05)))

(provide 'kuro-lifecycle-ext2-test)
;;; kuro-lifecycle-ext2-test.el ends here
