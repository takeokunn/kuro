;;; kuro-lifecycle-ext2-test-2.el --- Lifecycle tests (part 2)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-lifecycle-test-support)

;;; Group 23 (attach): kuro--init-session-buffer — font/remap calls forwarded
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

;;; ── Group 24 (cleanup): kuro--rollback-attach — kill-buffer arg, noop-dead, state ─────
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

;;; ── Group 25 (cleanup): kuro--schedule-initial-render — dead-buffer, live, timer ──────
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

;;; ── Group 26 (attach): kuro-create init-failure + kuro-attach switch-to-buffer guard ──
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
                 (lambda (_cmd _shell-args _rows _cols) nil)))
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
                 (lambda (_cmd _shell-args _rows _cols) nil))
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
                 (lambda (_cmd _shell-args _rows _cols) t))
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

;;; ── Group 27: kuro--module-loadable-p ───────────────────────────────────────

(ert-deftest kuro-lifecycle--module-loadable-p-returns-t-when-find-library-succeeds ()
  "`kuro--module-loadable-p' returns t when `kuro-core-init' is fbound."
  (cl-letf (((symbol-function 'kuro-core-init) (lambda () nil)))
    (should (kuro--module-loadable-p))))

(ert-deftest kuro-lifecycle--module-loadable-p-returns-nil-when-no-library ()
  "`kuro--module-loadable-p' returns nil when `kuro-core-init' is not fbound."
  (let ((was-bound (fboundp 'kuro-core-init)))
    (when was-bound (fmakunbound 'kuro-core-init))
    (unwind-protect
        (should-not (kuro--module-loadable-p))
      (when was-bound
        (fset 'kuro-core-init (lambda () nil))))))

;;; ── Group 28: kuro--try-load-module ─────────────────────────────────────────

(ert-deftest kuro-lifecycle--try-load-module-returns-t-on-success ()
  "`kuro--try-load-module' returns t when `kuro-module-load' binds `kuro-core-init'."
  (let ((was-bound (fboundp 'kuro-core-init)))
    (when was-bound (fmakunbound 'kuro-core-init))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-module-load)
                   (lambda () (fset 'kuro-core-init #'ignore))))
          (should (kuro--try-load-module)))
      ;; Restore: if it was not bound originally, unbind again
      (unless was-bound
        (ignore-errors (fmakunbound 'kuro-core-init))))))

(ert-deftest kuro-lifecycle--try-load-module-swallows-error-returns-nil ()
  "`kuro--try-load-module' returns nil without propagating errors from `kuro-module-load'."
  (let ((was-bound (fboundp 'kuro-core-init)))
    (when was-bound (fmakunbound 'kuro-core-init))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-module-load)
                   (lambda () (error "simulated load failure"))))
          (should-not (kuro--try-load-module)))
      (when was-bound
        (fset 'kuro-core-init (lambda () nil))))))

;;; ── Group 29: kuro--prompt-and-install-module ────────────────────────────────

(ert-deftest kuro-lifecycle--prompt-and-install-module-prebuilt-path ()
  "Answer 'd' → calls `kuro-module-download' then `kuro-module-load'."
  (let ((download-called nil)
        (load-called nil))
    (cl-letf (((symbol-function 'read-char-choice) (lambda (&rest _) ?d))
              ((symbol-function 'kuro-module-download)
               (lambda (&optional _v) (setq download-called t)))
              ((symbol-function 'kuro-module-load)
               (lambda () (setq load-called t) (fset 'kuro-core-init #'ignore)))
              ((symbol-function 'kuro--module-loadable-p) (lambda () t)))
      (let ((was-bound (fboundp 'kuro-core-init)))
        (when was-bound (fmakunbound 'kuro-core-init))
        (unwind-protect
            (progn
              (kuro--prompt-and-install-module)
              (should download-called)
              (should load-called))
          (unless was-bound
            (ignore-errors (fmakunbound 'kuro-core-init))))))))

(ert-deftest kuro-lifecycle--prompt-and-install-module-cargo-path ()
  "Answer 'b' → calls `kuro-module-build' then `kuro-module-load'."
  (let ((build-called nil)
        (load-called nil))
    (cl-letf (((symbol-function 'read-char-choice) (lambda (&rest _) ?b))
              ((symbol-function 'kuro-module-build)
               (lambda () (setq build-called t)))
              ((symbol-function 'kuro-module-load)
               (lambda () (setq load-called t) (fset 'kuro-core-init #'ignore)))
              ((symbol-function 'kuro--module-loadable-p) (lambda () t)))
      (let ((was-bound (fboundp 'kuro-core-init)))
        (when was-bound (fmakunbound 'kuro-core-init))
        (unwind-protect
            (progn
              (kuro--prompt-and-install-module)
              (should build-called)
              (should load-called))
          (unless was-bound
            (ignore-errors (fmakunbound 'kuro-core-init))))))))

(ert-deftest kuro-lifecycle--prompt-and-install-module-quit-path ()
  "Answer 'q' → signals `user-error'."
  (cl-letf (((symbol-function 'read-char-choice) (lambda (&rest _) ?q)))
    (should-error (kuro--prompt-and-install-module) :type 'user-error)))

;;; ── Group 30: kuro-create — buffer lifecycle ─────────────────────────────────

(ert-deftest kuro-lifecycle--create-returns-new-buffer ()
  "`kuro-create' returns a live buffer when all helpers are stubbed as no-ops."
  (let (result)
    (cl-letf (((symbol-function 'kuro--ensure-module-installed) #'ignore)
              ((symbol-function 'kuro-mode)
               (lambda () (setq major-mode 'kuro-mode)))
              ((symbol-function 'kuro--prefill-buffer)          #'ignore)
              ((symbol-function 'kuro--setup-shell-integration-env) #'ignore)
              ((symbol-function 'kuro--init)
               (lambda (_cmd _args _rows _cols) t))
              ((symbol-function 'kuro--init-session-buffer)     #'ignore)
              ((symbol-function 'kuro--start-render-loop)       #'ignore)
              ((symbol-function 'kuro--schedule-initial-render) #'ignore)
              ((symbol-function 'message)                       #'ignore))
      (setq result (kuro-create "echo" "*kuro-create-buf-test*")))
    (unwind-protect
        (should (buffer-live-p result))
      (when (buffer-live-p result)
        (kill-buffer result)))))

(ert-deftest kuro-lifecycle--create-buffer-has-kuro-mode ()
  "`kuro-create' returns a buffer with `major-mode' set to `kuro-mode'."
  (let (result)
    (cl-letf (((symbol-function 'kuro--ensure-module-installed) #'ignore)
              ((symbol-function 'kuro-mode)
               (lambda () (setq major-mode 'kuro-mode)))
              ((symbol-function 'kuro--prefill-buffer)          #'ignore)
              ((symbol-function 'kuro--setup-shell-integration-env) #'ignore)
              ((symbol-function 'kuro--init)
               (lambda (_cmd _args _rows _cols) t))
              ((symbol-function 'kuro--init-session-buffer)     #'ignore)
              ((symbol-function 'kuro--start-render-loop)       #'ignore)
              ((symbol-function 'kuro--schedule-initial-render) #'ignore)
              ((symbol-function 'message)                       #'ignore))
      (setq result (kuro-create "echo" "*kuro-create-mode-test*")))
    (unwind-protect
        (with-current-buffer result
          (should (eq major-mode 'kuro-mode)))
      (when (buffer-live-p result)
        (kill-buffer result)))))


;;; ── Group 31: kuro--detached-sessions / kuro--session-candidates / kuro--list-sessions-safe ──
;;
;; Pure-function coverage for the attach-session helpers.  Each entry in
;; SESSIONS is (ID COMMAND DETACHED-P ALIVE-P).

(ert-deftest kuro-lifecycle--detached-sessions-empty ()
  "`kuro--detached-sessions' returns nil for an empty list."
  (should (null (kuro--detached-sessions nil))))

(ert-deftest kuro-lifecycle--detached-sessions-all-attached ()
  "`kuro--detached-sessions' returns nil when no session is detached."
  (should (null (kuro--detached-sessions '((1 "sh" nil t) (2 "bash" nil t))))))

(ert-deftest kuro-lifecycle--detached-sessions-all-detached ()
  "`kuro--detached-sessions' returns all entries when all are detached."
  (let ((sessions '((1 "sh" t t) (2 "bash" t nil))))
    (should (equal (kuro--detached-sessions sessions) sessions))))

(ert-deftest kuro-lifecycle--detached-sessions-mixed ()
  "`kuro--detached-sessions' filters to only detached entries."
  (let* ((sessions '((1 "sh" nil t) (2 "bash" t t) (3 "zsh" nil nil)))
         (result   (kuro--detached-sessions sessions)))
    (should (= (length result) 1))
    (should (= (car (nth 0 result)) 2))))

(ert-deftest kuro-lifecycle--session-candidates-empty ()
  "`kuro--session-candidates' returns nil for an empty list."
  (should (null (kuro--session-candidates nil))))

(ert-deftest kuro-lifecycle--session-candidates-label-format ()
  "`kuro--session-candidates' produces (\"Session N: CMD\" . N) pairs."
  (let ((result (kuro--session-candidates '((42 "bash" t t)))))
    (should (= (length result) 1))
    (should (equal (car (nth 0 result)) "Session 42: bash"))
    (should (= (cdr (nth 0 result)) 42))))

(ert-deftest kuro-lifecycle--session-candidates-multiple ()
  "`kuro--session-candidates' produces one pair per entry, IDs preserved."
  (let ((result (kuro--session-candidates '((1 "sh" t t) (99 "fish" t nil)))))
    (should (= (length result) 2))
    (should (= (cdr (assoc "Session 1: sh" result)) 1))
    (should (= (cdr (assoc "Session 99: fish" result)) 99))))

(ert-deftest kuro-lifecycle--list-sessions-safe-returns-value ()
  "`kuro--list-sessions-safe' returns the value from kuro-core-list-sessions."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () '((1 "bash" nil t)))))
    (should (equal (kuro--list-sessions-safe) '((1 "bash" nil t))))))

(ert-deftest kuro-lifecycle--list-sessions-safe-returns-nil-on-error ()
  "`kuro--list-sessions-safe' returns nil when kuro-core-list-sessions signals an error."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () (error "FFI not available"))))
    (should (null (kuro--list-sessions-safe)))))

(ert-deftest kuro-lifecycle--list-sessions-safe-empty-list ()
  "`kuro--list-sessions-safe' passes through an empty list unchanged."
  (cl-letf (((symbol-function 'kuro-core-list-sessions) (lambda () nil)))
    (should (null (kuro--list-sessions-safe)))))


;;; ── Group 32: kuro--session-buffer-name / kuro--module-loadable-p / kuro--terminal-dimensions ──

(ert-deftest kuro-lifecycle--session-buffer-name-zero ()
  "`kuro--session-buffer-name' formats session-id 0 correctly."
  (should (equal "*kuro<0>*" (kuro--session-buffer-name 0))))

(ert-deftest kuro-lifecycle--session-buffer-name-positive ()
  "`kuro--session-buffer-name' formats a positive session-id correctly."
  (should (equal "*kuro<42>*" (kuro--session-buffer-name 42))))

(ert-deftest kuro-lifecycle--session-buffer-name-large ()
  "`kuro--session-buffer-name' handles large session IDs without truncation."
  (should (equal "*kuro<99999>*" (kuro--session-buffer-name 99999))))

(ert-deftest kuro-lifecycle--module-loadable-p-when-unbound ()
  "`kuro--module-loadable-p' returns nil when `kuro-core-init' is not bound."
  (let ((was-bound (fboundp 'kuro-core-init)))
    (unless was-bound
      (should (null (kuro--module-loadable-p))))))

(ert-deftest kuro-lifecycle--module-loadable-p-when-bound ()
  "`kuro--module-loadable-p' returns non-nil when `kuro-core-init' is fboundp."
  (cl-letf (((symbol-function 'kuro-core-init) (lambda () nil)))
    (should (kuro--module-loadable-p))))

(ert-deftest kuro-lifecycle--terminal-dimensions-noninteractive-rows ()
  "`kuro--terminal-dimensions' returns kuro--default-rows as car in batch mode."
  (let ((noninteractive t))
    (should (= kuro--default-rows (car (kuro--terminal-dimensions))))))

(ert-deftest kuro-lifecycle--terminal-dimensions-noninteractive-cols ()
  "`kuro--terminal-dimensions' returns kuro--default-cols as cdr in batch mode."
  (let ((noninteractive t))
    (should (= kuro--default-cols (cdr (kuro--terminal-dimensions))))))

(ert-deftest kuro-lifecycle--terminal-dimensions-returns-cons ()
  "`kuro--terminal-dimensions' always returns a cons cell."
  (let ((dims (kuro--terminal-dimensions)))
    (should (consp dims))
    (should (integerp (car dims)))
    (should (integerp (cdr dims)))))


(provide 'kuro-lifecycle-ext2-test-2)

;;; kuro-lifecycle-ext2-test-2.el ends here
