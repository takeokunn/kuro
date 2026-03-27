;;; kuro-lifecycle-state-test.el --- Unit tests for kuro-lifecycle.el state management  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;;; Commentary:

;; ERT tests for kuro-lifecycle.el session-state and buffer-initialization API.
;; Split from kuro-lifecycle-test.el to keep individual files under 500 lines.
;;
;; Tests run without the Rust dynamic module: all FFI primitives are stubbed
;; before `kuro-lifecycle' is loaded.  When loaded after kuro-test.el
;; (as the Makefile does), the stubs in kuro-test.el are already present;
;; the `unless (fboundp …)' guards here handle standalone loading.
;;
;; Groups:
;;   Group 10: kuro--init-session-buffer
;;   Group 11: kuro--prefill-buffer
;;   Group 12: kuro--do-attach and kuro--rollback-attach
;;   Group 13: kuro--teardown-session
;;   Group 14: kuro--schedule-initial-render
;;   Group 15: kuro--do-attach additional coverage
;;   Group 16: kuro--init-session-buffer additional coverage

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; ── Stub Rust FFI symbols before loading kuro-lifecycle ─────────────────────
;; These symbols are provided by the Rust dynamic module at runtime.
;; Guard with `unless (fboundp …)' so a real loaded module is not overridden.

(dolist (sym '(kuro-core-init
               kuro-core-send-key
               kuro-core-poll-updates
               kuro-core-poll-updates-with-faces
               kuro-core-resize
               kuro-core-shutdown
               kuro-core-get-cursor
               kuro-core-get-cursor-visible
               kuro-core-get-cursor-shape
               kuro-core-get-scroll-offset
               kuro-core-get-and-clear-title
               kuro-core-get-default-colors
               kuro-core-get-palette-updates
               kuro-core-get-image
               kuro-core-take-bell-pending
               kuro-core-get-focus-events
               kuro-core-get-app-cursor-keys
               kuro-core-get-app-keypad
               kuro-core-get-bracketed-paste
               kuro-core-get-mouse-mode
               kuro-core-get-mouse-sgr
               kuro-core-get-mouse-pixel
               kuro-core-get-keyboard-flags
               kuro-core-get-scrollback-count
               kuro-core-get-scrollback
               kuro-core-get-sync-output
               kuro-core-get-cwd
               kuro-core-has-pending-output
               kuro-core-is-process-alive
               kuro-core-poll-clipboard-actions
               kuro-core-poll-image-notifications
               kuro-core-poll-prompt-marks
               kuro-core-scroll-up
               kuro-core-scroll-down
               kuro-core-consume-scroll-events
               kuro-core-clear-scrollback
               kuro-core-set-scrollback-max-lines
               kuro-core-detach
               kuro-core-attach
               kuro-core-list-sessions))
  (unless (fboundp sym)
    (fset sym (lambda (&rest _) nil))))

(unless (fboundp 'module-load)
  (fset 'module-load (lambda (_path) nil)))

;;; ── Ensure emacs-lisp/ is on load-path ─────────────────────────────────────

(let* ((this-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory)))
       (el-dir (expand-file-name "../../emacs-lisp" this-dir)))
  (add-to-list 'load-path el-dir t))

(require 'kuro-lifecycle)

;;; ── Helper macros ───────────────────────────────────────────────────────────

(defmacro kuro-lifecycle-test--with-init-stubs (&rest body)
  "Execute BODY with all helpers called by `kuro--init-session-buffer' stubbed.
Stubs `kuro--set-scrollback-max-lines', `kuro--apply-font-to-buffer',
`kuro--setup-char-width-table', `kuro--setup-fontset',
`kuro--remap-default-face', and `kuro--reset-cursor-cache'
as no-ops.  Override individual stubs inside BODY via `cl-letf'
when a test needs to observe their behavior."
  `(cl-letf (((symbol-function 'kuro--set-scrollback-max-lines)  (lambda (_n)      nil))
             ((symbol-function 'kuro--apply-font-to-buffer)       (lambda (_b)      nil))
             ((symbol-function 'kuro--setup-char-width-table)     (lambda ()        nil))
             ((symbol-function 'kuro--setup-fontset)              (lambda ()        nil))
             ((symbol-function 'kuro--remap-default-face)         (lambda (_fg _bg) nil))
             ((symbol-function 'kuro--reset-cursor-cache)         (lambda ()        nil)))
     ,@body))

(defmacro kuro-lifecycle-test--with-attach-stubs (&rest body)
  "Run BODY with all kuro--do-attach dependencies stubbed."
  `(cl-letf (((symbol-function 'kuro-core-attach)           #'ignore)
             ((symbol-function 'kuro--prefill-buffer)        #'ignore)
             ((symbol-function 'kuro--init-session-buffer)   #'ignore)
             ((symbol-function 'kuro--resize)                #'ignore)
             ((symbol-function 'kuro--start-render-loop)     #'ignore))
     ,@body))

;;; ── Group 10: kuro--init-session-buffer ────────────────────────────────────
;;
;; kuro--init-session-buffer initializes a buffer as a kuro session display.
;; It sets cursor-marker, last-rows, last-cols, scroll-offset, calls five
;; side-effecting helpers, and resets cursor cache.  Tests stub every outward
;; call and verify the buffer-local variables directly.

(ert-deftest kuro-lifecycle--init-session-buffer-sets-dimensions ()
  "kuro--init-session-buffer stores rows/cols in kuro--last-rows/kuro--last-cols."
  (with-temp-buffer
    (setq-local kuro--last-rows 0
                kuro--last-cols 0
                kuro--scroll-offset 99
                kuro--cursor-marker nil)
    (kuro-lifecycle-test--with-init-stubs
      (kuro--init-session-buffer (current-buffer) 24 80)
      (should (= kuro--last-rows 24))
      (should (= kuro--last-cols 80)))))

(ert-deftest kuro-lifecycle--init-session-buffer-resets-scroll-offset ()
  "kuro--init-session-buffer resets kuro--scroll-offset to 0."
  (with-temp-buffer
    (setq-local kuro--scroll-offset 42
                kuro--cursor-marker nil
                kuro--last-rows 0
                kuro--last-cols 0)
    (kuro-lifecycle-test--with-init-stubs
      (kuro--init-session-buffer (current-buffer) 24 80)
      (should (= kuro--scroll-offset 0)))))

(ert-deftest kuro-lifecycle--init-session-buffer-sets-cursor-marker ()
  "kuro--init-session-buffer sets kuro--cursor-marker to a live marker."
  (with-temp-buffer
    (setq-local kuro--cursor-marker nil
                kuro--last-rows 0
                kuro--last-cols 0
                kuro--scroll-offset 0)
    (kuro-lifecycle-test--with-init-stubs
      (kuro--init-session-buffer (current-buffer) 24 80)
      (should (markerp kuro--cursor-marker))
      (should (marker-buffer kuro--cursor-marker)))))

(ert-deftest kuro-lifecycle--init-session-buffer-calls-scrollback ()
  "kuro--init-session-buffer calls kuro--set-scrollback-max-lines."
  (with-temp-buffer
    (setq-local kuro--cursor-marker nil
                kuro--last-rows 0
                kuro--last-cols 0
                kuro--scroll-offset 0)
    (let ((scrollback-called nil))
      (kuro-lifecycle-test--with-init-stubs
        (cl-letf (((symbol-function 'kuro--set-scrollback-max-lines)
                   (lambda (_n) (setq scrollback-called t))))
          (kuro--init-session-buffer (current-buffer) 24 80)
          (should scrollback-called))))))

(ert-deftest kuro-lifecycle--init-session-buffer-resets-cursor-cache ()
  "kuro--init-session-buffer clears all cursor cache variables to nil.
kuro--reset-cursor-cache is a macro; we verify its expansion side effects
rather than stubbing it through symbol-function."
  (with-temp-buffer
    (setq-local kuro--cursor-marker nil
                kuro--last-rows 0
                kuro--last-cols 0
                kuro--scroll-offset 0
                kuro--last-cursor-row    42
                kuro--last-cursor-col    10
                kuro--last-cursor-visible t
                kuro--last-cursor-shape  'block)
    (kuro-lifecycle-test--with-init-stubs
      (kuro--init-session-buffer (current-buffer) 24 80)
      (should (null kuro--last-cursor-row))
      (should (null kuro--last-cursor-col))
      (should (null kuro--last-cursor-visible))
      (should (null kuro--last-cursor-shape)))))

;;; ── Group 11: kuro--prefill-buffer ─────────────────────────────────────────
;;
;; kuro--prefill-buffer erases the buffer, inserts ROWS newlines, and moves
;; point to point-min.  Must be called with inhibit-read-only bound by caller.

(ert-deftest kuro-lifecycle--prefill-buffer-inserts-correct-line-count ()
  "kuro--prefill-buffer inserts exactly ROWS newlines."
  (with-temp-buffer
    (let ((inhibit-read-only t))
      (kuro--prefill-buffer 10)
      ;; 10 newlines produce 11 positions (point-min to point-max);
      ;; count lines: (count-lines point-min point-max) = 10.
      (should (= (count-lines (point-min) (point-max)) 10)))))

(ert-deftest kuro-lifecycle--prefill-buffer-leaves-point-at-min ()
  "kuro--prefill-buffer leaves point at point-min."
  (with-temp-buffer
    (let ((inhibit-read-only t))
      (insert "old content")
      (kuro--prefill-buffer 5)
      (should (= (point) (point-min))))))

(ert-deftest kuro-lifecycle--prefill-buffer-erases-existing-content ()
  "kuro--prefill-buffer erases any pre-existing buffer content."
  (with-temp-buffer
    (let ((inhibit-read-only t))
      (insert "some old text")
      (kuro--prefill-buffer 3)
      (should-not (string-match-p "old" (buffer-string))))))

;;; ── Group 12: kuro--do-attach and kuro--rollback-attach ────────────────────
;;
;; kuro--do-attach performs the six-step core attach sequence inside an
;; inhibit-read-only binding.  kuro--rollback-attach logs, clears state,
;; tries to detach, and kills the buffer.

(ert-deftest kuro-lifecycle-do-attach-sets-session-id ()
  "kuro--do-attach sets kuro--session-id and kuro--initialized."
  (with-temp-buffer
    (let (kuro--session-id kuro--initialized)
      (kuro-lifecycle-test--with-attach-stubs
        (kuro--do-attach 42 24 80)
        (should (= kuro--session-id 42))
        (should kuro--initialized)))))

(ert-deftest kuro-lifecycle-do-attach-calls-core-attach ()
  "kuro--do-attach calls kuro-core-attach with the session ID."
  (with-temp-buffer
    (let (kuro--session-id kuro--initialized
          (attach-called-with nil))
      (kuro-lifecycle-test--with-attach-stubs
        (cl-letf (((symbol-function 'kuro-core-attach)
                   (lambda (id) (setq attach-called-with id))))
          (kuro--do-attach 7 24 80)
          (should (= attach-called-with 7)))))))

(ert-deftest kuro-lifecycle-do-attach-calls-start-render-loop ()
  "kuro--do-attach calls kuro--start-render-loop."
  (with-temp-buffer
    (let (kuro--session-id kuro--initialized
          (render-started nil))
      (kuro-lifecycle-test--with-attach-stubs
        (cl-letf (((symbol-function 'kuro--start-render-loop)
                   (lambda () (setq render-started t))))
          (kuro--do-attach 1 24 80)
          (should render-started))))))

(ert-deftest kuro-lifecycle-rollback-attach-clears-state ()
  "kuro--rollback-attach resets kuro--initialized to nil and kuro--session-id to 0.
kuro--clear-session-state is a macro so we verify its expanded effects directly."
  (with-temp-buffer
    (let ((kuro--session-id 1)
          (kuro--initialized t))
      (cl-letf (((symbol-function 'kuro-core-detach) #'ignore)
                ((symbol-function 'message)           #'ignore)
                ((symbol-function 'kill-buffer)       #'ignore))
        (kuro--rollback-attach 1 (current-buffer) "test error")
        (should-not kuro--initialized)
        (should (= kuro--session-id 0))))))

(ert-deftest kuro-lifecycle-rollback-attach-attempts-detach ()
  "kuro--rollback-attach attempts kuro-core-detach with the session ID."
  (with-temp-buffer
    (let ((kuro--session-id 5)
          (kuro--initialized nil)
          (detach-called-with nil))
      (cl-letf (((symbol-function 'kuro-core-detach)
                 (lambda (id) (setq detach-called-with id)))
                ((symbol-function 'message)    #'ignore)
                ((symbol-function 'kill-buffer) #'ignore))
        (kuro--rollback-attach 5 (current-buffer) "oops")
        (should (= detach-called-with 5))))))

(ert-deftest kuro-lifecycle-rollback-attach-swallows-detach-error ()
  "kuro--rollback-attach does not propagate an error from kuro-core-detach."
  (with-temp-buffer
    (let ((kuro--session-id 0)
          (kuro--initialized nil))
      (cl-letf (((symbol-function 'kuro-core-detach)
                 (lambda (_id) (error "detach failed")))
                ((symbol-function 'message)    #'ignore)
                ((symbol-function 'kill-buffer) #'ignore))
        ;; Must not signal.
        (should-not (condition-case err
                        (progn (kuro--rollback-attach 0 (current-buffer) "e") nil)
                      (error err)))))))

;;; ── Group 13: kuro--teardown-session ────────────────────────────────────────
;;
;; kuro--teardown-session branches on kuro--initialized, kuro--is-process-alive,
;; and the yes-or-no-p prompt.  Three paths: shutdown (not initialized),
;; shutdown (user says yes), detach (user says no).

(ert-deftest kuro-lifecycle-teardown-calls-shutdown-when-not-initialized ()
  "kuro--teardown-session calls kuro--shutdown when kuro--initialized is nil."
  (let (kuro--initialized
        (shutdown-called nil))
    (cl-letf (((symbol-function 'kuro--shutdown)
               (lambda () (setq shutdown-called t))))
      (kuro--teardown-session)
      (should shutdown-called))))

(ert-deftest kuro-lifecycle-teardown-calls-shutdown-when-user-says-yes ()
  "kuro--teardown-session calls kuro--shutdown when user answers yes to prompt."
  (let ((kuro--initialized t)
        (kuro--session-id 10)
        (shutdown-called nil)
        (detach-called nil))
    (cl-letf (((symbol-function 'kuro--is-process-alive) (lambda () t))
              ((symbol-function 'yes-or-no-p)            (lambda (_p) t))
              ((symbol-function 'kuro--shutdown)
               (lambda () (setq shutdown-called t)))
              ((symbol-function 'kuro-core-detach)
               (lambda (_id) (setq detach-called t))))
      (kuro--teardown-session)
      (should shutdown-called)
      (should-not detach-called))))

(ert-deftest kuro-lifecycle-teardown-detaches-when-user-says-no ()
  "kuro--teardown-session calls kuro-core-detach and clears state when user says no."
  (let ((kuro--initialized t)
        (kuro--session-id 20)
        (detach-called-with nil)
        (shutdown-called nil))
    (cl-letf (((symbol-function 'kuro--is-process-alive) (lambda () t))
              ((symbol-function 'yes-or-no-p)            (lambda (_p) nil))
              ((symbol-function 'kuro-core-detach)
               (lambda (id) (setq detach-called-with id)))
              ((symbol-function 'kuro--shutdown)
               (lambda () (setq shutdown-called t))))
      (kuro--teardown-session)
      (should (= detach-called-with 20))
      (should-not shutdown-called)
      (should-not kuro--initialized)
      (should (= kuro--session-id 0)))))

(ert-deftest kuro-lifecycle-teardown-clears-state-even-if-detach-errors ()
  "kuro--teardown-session clears state even when kuro-core-detach signals."
  (let ((kuro--initialized t)
        (kuro--session-id 30))
    (cl-letf (((symbol-function 'kuro--is-process-alive) (lambda () t))
              ((symbol-function 'yes-or-no-p)            (lambda (_p) nil))
              ((symbol-function 'kuro-core-detach)
               (lambda (_id) (error "detach blew up")))
              ((symbol-function 'kuro--shutdown)          #'ignore))
      (kuro--teardown-session)
      (should-not kuro--initialized)
      (should (= kuro--session-id 0)))))

;;; ── Group 14: kuro--schedule-initial-render ─────────────────────────────────
;;
;; kuro--schedule-initial-render posts a one-shot idle timer that fires
;; kuro--render-cycle only when the buffer is still live.  Tests verify the
;; timer arguments and the buffer-live-p guard without actually waiting for
;; idle time.

(ert-deftest kuro-lifecycle--schedule-initial-render-posts-idle-timer ()
  "kuro--schedule-initial-render calls run-with-idle-timer with the right delay.
The first argument must equal kuro--startup-render-delay; the second must
be nil (one-shot, never rescheduled)."
  (let ((timer-delay nil)
        (timer-repeat nil))
    (cl-letf (((symbol-function 'run-with-idle-timer)
               (lambda (delay repeat _fn &rest _args)
                 (setq timer-delay  delay
                       timer-repeat repeat))))
      (with-temp-buffer
        (kuro--schedule-initial-render (current-buffer))))
    (should (equal timer-delay  kuro--startup-render-delay))
    (should (null  timer-repeat))))

(ert-deftest kuro-lifecycle--schedule-initial-render-passes-buffer-arg ()
  "kuro--schedule-initial-render passes the buffer as the timer function arg.
We capture the extra args list supplied to run-with-idle-timer and verify
the first element is the buffer we passed in."
  (let ((timer-args nil))
    (cl-letf (((symbol-function 'run-with-idle-timer)
               (lambda (_delay _repeat _fn &rest args)
                 (setq timer-args args))))
      (with-temp-buffer
        (let ((buf (current-buffer)))
          (kuro--schedule-initial-render buf)
          (should (eq (car timer-args) buf)))))))

(ert-deftest kuro-lifecycle--schedule-initial-render-skips-dead-buffer ()
  "The timer lambda does not call kuro--render-cycle when the buffer is dead.
We extract the lambda from the timer and invoke it directly with a buffer
that has already been killed."
  (let ((render-called nil)
        (captured-fn nil)
        (dead-buf nil))
    ;; Capture the lambda passed to run-with-idle-timer.
    (cl-letf (((symbol-function 'run-with-idle-timer)
               (lambda (_delay _repeat fn &rest _args)
                 (setq captured-fn fn))))
      (with-temp-buffer
        (setq dead-buf (current-buffer))
        (kuro--schedule-initial-render dead-buf)))
    ;; Kill the buffer so buffer-live-p returns nil.
    (when (buffer-live-p dead-buf)
      (kill-buffer dead-buf))
    ;; Invoke the captured lambda with the dead buffer.
    (cl-letf (((symbol-function 'kuro--render-cycle)
               (lambda () (setq render-called t))))
      (funcall captured-fn dead-buf))
    (should-not render-called)))

;;; ── Group 15: kuro--do-attach additional coverage ───────────────────────────
;;
;; Supplement the Group 12 tests with error-propagation and state-variable
;; assertions that were not covered there.

(ert-deftest kuro-lifecycle--do-attach-propagates-core-attach-error ()
  "kuro--do-attach does not swallow errors from kuro-core-attach.
When kuro-core-attach signals, the error must propagate to the caller."
  (with-temp-buffer
    (let (kuro--session-id kuro--initialized)
      (cl-letf (((symbol-function 'kuro-core-attach)
                 (lambda (_id) (user-error "attach failed")))
                ((symbol-function 'kuro--prefill-buffer)      #'ignore)
                ((symbol-function 'kuro--init-session-buffer) #'ignore)
                ((symbol-function 'kuro--resize)              #'ignore)
                ((symbol-function 'kuro--start-render-loop)   #'ignore))
        (should-error (kuro--do-attach 1 24 80) :type 'user-error)))))

(ert-deftest kuro-lifecycle--do-attach-sets-session-id-on-success ()
  "kuro--do-attach sets kuro--session-id to the passed session-id value."
  (with-temp-buffer
    (let (kuro--session-id kuro--initialized)
      (kuro-lifecycle-test--with-attach-stubs
        (kuro--do-attach 55 24 80)
        (should (= kuro--session-id 55))))))

(ert-deftest kuro-lifecycle--do-attach-sets-initialized-on-success ()
  "kuro--do-attach sets kuro--initialized to t after a successful attach."
  (with-temp-buffer
    (let (kuro--session-id kuro--initialized)
      (kuro-lifecycle-test--with-attach-stubs
        (kuro--do-attach 55 24 80)
        (should kuro--initialized)))))

;;; ── Group 16: kuro--init-session-buffer additional coverage ─────────────────
;;
;; Supplement the Group 10 tests with explicit assertions about scrollback-size
;; argument value and cursor-marker non-nil guarantee.

(ert-deftest kuro-lifecycle--init-session-buffer-cursor-marker-non-nil ()
  "kuro--init-session-buffer leaves kuro--cursor-marker non-nil.
Exercises the marker-creation path in a fresh temp buffer."
  (with-temp-buffer
    (setq-local kuro--cursor-marker nil
                kuro--last-rows     0
                kuro--last-cols     0
                kuro--scroll-offset 0)
    (kuro-lifecycle-test--with-init-stubs
      (kuro--init-session-buffer (current-buffer) 30 120)
      (should kuro--cursor-marker))))

(ert-deftest kuro-lifecycle--init-session-buffer-scrollback-size-arg ()
  "kuro--init-session-buffer calls kuro--set-scrollback-max-lines with kuro-scrollback-size.
Verifies the exact argument value rather than just presence of a call."
  (with-temp-buffer
    (setq-local kuro--cursor-marker nil
                kuro--last-rows     0
                kuro--last-cols     0
                kuro--scroll-offset 0)
    (let ((received-size nil))
      (kuro-lifecycle-test--with-init-stubs
        (cl-letf (((symbol-function 'kuro--set-scrollback-max-lines)
                   (lambda (n) (setq received-size n))))
          (kuro--init-session-buffer (current-buffer) 24 80)
          (should (= received-size kuro-scrollback-size)))))))

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

(provide 'kuro-lifecycle-state-test)

;;; kuro-lifecycle-state-test.el ends here
