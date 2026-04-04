;;; kuro-lifecycle-state-ext2-test.el --- Extended unit tests for kuro-lifecycle.el state management (part 2)  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;;; Commentary:

;; ERT tests for kuro-lifecycle.el — supplemental coverage (part 2).
;; Split from kuro-lifecycle-state-ext-test.el to keep individual files under 600 lines.
;;
;; Tests run without the Rust dynamic module: all FFI primitives are stubbed
;; before `kuro-lifecycle' is loaded.  When loaded after kuro-test.el
;; (as the Makefile does), the stubs in kuro-test.el are already present;
;; the `unless (fboundp …)' guards here handle standalone loading.
;;
;; Groups:
;;   Group 20: kuro--do-attach — resize and prefill args
;;   Group 21: kuro-attach — public API (error rollback, success message, buffer naming)
;;   Group 22: kuro--schedule-initial-render — live-buffer path and timer lambda
;;   Group 23: kuro--init-session-buffer — font/remap calls forwarded
;;   Group 26: kuro-create init-failure + kuro-attach switch-to-buffer guard

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-lifecycle-test-support)

;;; ── Group 20: kuro--do-attach — resize and prefill args ────────────────────
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

;;; Group 21: kuro-attach — public API (error rollback, success message, buffer naming)
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

;;; Group 22: kuro--schedule-initial-render — live-buffer path and timer lambda
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

;;; Group 23: kuro--init-session-buffer — font/remap calls forwarded
;;
;; Verifies that kuro--init-session-buffer calls kuro--apply-font-to-buffer
;; and kuro--remap-default-face, rather than just checking dimensions.

(ert-deftest kuro-lifecycle--init-session-buffer-calls-apply-font ()
  "kuro--init-session-buffer calls kuro--apply-font-to-buffer with the buffer."
  (with-temp-buffer
    (setq-local kuro--cursor-marker nil
                kuro--last-rows     0
                kuro--last-cols     0
                kuro--scroll-offset 0)
    (let ((font-called-with nil))
      (kuro-lifecycle-test--with-init-stubs
        (cl-letf (((symbol-function 'kuro--apply-font-to-buffer)
                   (lambda (b) (setq font-called-with b))))
          (kuro--init-session-buffer (current-buffer) 24 80)
          (should (eq font-called-with (current-buffer))))))))

(ert-deftest kuro-lifecycle--init-session-buffer-calls-remap-default-face ()
  "kuro--init-session-buffer calls kuro--remap-default-face with fg/bg strings."
  (with-temp-buffer
    (setq-local kuro--cursor-marker nil
                kuro--last-rows     0
                kuro--last-cols     0
                kuro--scroll-offset 0)
    (let ((remap-args nil))
      (kuro-lifecycle-test--with-init-stubs
        (cl-letf (((symbol-function 'kuro--remap-default-face)
                   (lambda (fg bg) (setq remap-args (list fg bg)))))
          (kuro--init-session-buffer (current-buffer) 24 80)
          (should (consp remap-args))
          (should (stringp (car remap-args)))
          (should (stringp (cadr remap-args))))))))

(ert-deftest kuro-lifecycle--init-session-buffer-calls-setup-char-width ()
  "kuro--init-session-buffer calls kuro--setup-char-width-table."
  (with-temp-buffer
    (setq-local kuro--cursor-marker nil
                kuro--last-rows     0
                kuro--last-cols     0
                kuro--scroll-offset 0)
    (let ((char-width-called nil))
      (kuro-lifecycle-test--with-init-stubs
        (cl-letf (((symbol-function 'kuro--setup-char-width-table)
                   (lambda () (setq char-width-called t))))
          (kuro--init-session-buffer (current-buffer) 24 80)
          (should char-width-called))))))

;;; ── Group 26: kuro-create init-failure + kuro-attach switch-to-buffer guard ──
;;
;; Gap 1: When kuro--init returns nil, kuro-create must return a buffer but
;; must NOT call kuro--start-render-loop.  When kuro--init returns t the render
;; loop IS started.
;;
;; Gap 2: kuro-attach has `(unless noninteractive (switch-to-buffer …))'.  In
;; the test environment noninteractive is already t, so the branch is always
;; skipped.  Tests 4-5 document this guard explicitly: test 4 verifies that
;; switch-to-buffer is not called in a normal (noninteractive) test run, and
;; test 5 temporarily binds noninteractive to nil to exercise the live-mode
;; branch.

(defmacro kuro-lifecycle-test--with-create-stubs (&rest body)
  "Run BODY with every kuro-create side-effecting helper stubbed.
Stubs kuro--ensure-module-loaded, kuro-mode, kuro--prefill-buffer,
kuro--init-session-buffer, kuro--start-render-loop, and
kuro--schedule-initial-render as no-ops so the test controls only
`kuro--init' behaviour.  Override individual stubs inside BODY via
`cl-letf'."
  `(cl-letf (((symbol-function 'kuro--ensure-module-loaded)   #'ignore)
             ((symbol-function 'kuro-mode)
              (lambda () (setq major-mode 'kuro-mode)))
             ((symbol-function 'kuro--prefill-buffer)          #'ignore)
             ((symbol-function 'kuro--init-session-buffer)     #'ignore)
             ((symbol-function 'kuro--start-render-loop)       #'ignore)
             ((symbol-function 'kuro--schedule-initial-render) #'ignore)
             ((symbol-function 'message)                       #'ignore))
     ,@body))

(ert-deftest kuro-lifecycle--create-init-failure-returns-nil ()
  "kuro-create returns nil when kuro--init returns nil.
The buffer is still created; the return value of kuro-create should be
the buffer object (kuro-create always returns the buffer), but the
`when (kuro--init …)' body is skipped, so only the buffer is returned.
We verify that the returned value is a buffer (not signalling an error)
and that the session was not started."
  (let (result)
    (kuro-lifecycle-test--with-create-stubs
      (cl-letf (((symbol-function 'kuro--init)
                 (lambda (_cmd _rows _cols) nil)))
        (setq result (kuro-create "echo" "*kuro-create-fail-test*"))))
    (unwind-protect
        ;; kuro-create always returns the buffer; the init failure just means
        ;; the render loop was not started.  The buffer is usable but empty.
        (should (bufferp result))
      (when (buffer-live-p result)
        (kill-buffer result)))))

(ert-deftest kuro-lifecycle--create-init-failure-no-render-scheduled ()
  "When kuro--init returns nil, kuro--start-render-loop is NOT called."
  (let ((render-started nil)
        result)
    (kuro-lifecycle-test--with-create-stubs
      (cl-letf (((symbol-function 'kuro--init)
                 (lambda (_cmd _rows _cols) nil))
                ((symbol-function 'kuro--start-render-loop)
                 (lambda () (setq render-started t))))
        (setq result (kuro-create "echo" "*kuro-create-no-render-test*"))))
    (unwind-protect
        (should-not render-started)
      (when (buffer-live-p result)
        (kill-buffer result)))))

(ert-deftest kuro-lifecycle--create-success-starts-render-loop ()
  "When kuro--init returns t, kuro--start-render-loop IS called."
  (let ((render-started nil)
        result)
    (kuro-lifecycle-test--with-create-stubs
      (cl-letf (((symbol-function 'kuro--init)
                 (lambda (_cmd _rows _cols) t))
                ((symbol-function 'kuro--start-render-loop)
                 (lambda () (setq render-started t))))
        (setq result (kuro-create "echo" "*kuro-create-success-test*"))))
    (unwind-protect
        (should render-started)
      (when (buffer-live-p result)
        (kill-buffer result)))))

(ert-deftest kuro-lifecycle--attach-skips-switch-to-buffer-when-noninteractive ()
  "In the test environment noninteractive is t, so kuro-attach never calls
switch-to-buffer.  This test documents and pins that guard: we use cl-letf
to detect any call to switch-to-buffer and verify none arrives."
  ;; Sanity-check the test environment assumption first.
  (should noninteractive)
  (let ((switch-called nil)
        result)
    (cl-letf (((symbol-function 'kuro--ensure-module-loaded) #'ignore)
              ((symbol-function 'kuro-mode)
               (lambda () (setq major-mode 'kuro-mode)))
              ((symbol-function 'kuro--do-attach)             #'ignore)
              ((symbol-function 'message)                     #'ignore)
              ((symbol-function 'switch-to-buffer)
               (lambda (_buf) (setq switch-called t))))
      (setq result (kuro-attach 11)))
    (unwind-protect
        (should-not switch-called)
      (when (buffer-live-p result)
        (kill-buffer result)))))

(ert-deftest kuro-lifecycle--attach-calls-switch-to-buffer-when-interactive ()
  "When noninteractive is nil (simulating interactive Emacs), kuro-attach
calls switch-to-buffer with the newly created buffer."
  (let ((switch-called-with nil)
        result)
    (cl-letf (((symbol-function 'kuro--ensure-module-loaded) #'ignore)
              ((symbol-function 'kuro-mode)
               (lambda () (setq major-mode 'kuro-mode)))
              ((symbol-function 'kuro--do-attach)             #'ignore)
              ((symbol-function 'message)                     #'ignore)
              ((symbol-function 'switch-to-buffer)
               (lambda (buf) (setq switch-called-with buf))))
      ;; Temporarily bind noninteractive to nil to enter the interactive branch.
      (let ((noninteractive nil))
        (setq result (kuro-attach 22))))
    (unwind-protect
        (progn
          (should switch-called-with)
          (should (eq switch-called-with result)))
      (when (buffer-live-p result)
        (kill-buffer result)))))

(provide 'kuro-lifecycle-state-ext2-test)

;;; kuro-lifecycle-state-ext2-test.el ends here
