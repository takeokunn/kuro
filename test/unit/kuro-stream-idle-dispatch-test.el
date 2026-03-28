;;; kuro-stream-ext2-test.el --- Extended unit tests for kuro-stream.el (part 2)  -*- lexical-binding: t; -*-

;;; Commentary:
;; Second extension of unit tests for kuro-stream.el (low-latency streaming idle timer).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;; This file is a continuation of kuro-stream-ext-test.el and covers Groups 13-16.
;;
;; Groups:
;;   Group 13 — stop timer full-state verification
;;   Group 14 — truthy latency-mode values and start-timer state
;;   Group 15 — kuro--start-stream-idle-timer: callback closure captures correct buffer
;;   Group 16 — kuro--stream-idle-tick: rate-limit boundary arithmetic

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Declare the buffer-local variables we test against, without loading
;; kuro-stream.el (which would pull in kuro-ffi and the Rust .so).
(defvar-local kuro--stream-idle-timer nil)
(defvar-local kuro--stream-last-render-time 0.0)
(defvar-local kuro--stream-min-interval nil)

;;; Helpers

(defmacro kuro-stream-test--with-buffer (&rest body)
  "Run BODY in a temp buffer with stream state reset to initial values."
  `(with-temp-buffer
     (setq kuro--stream-idle-timer nil
           kuro--stream-last-render-time 0.0
           kuro--stream-min-interval nil)
     ,@body))

(cl-defmacro kuro-stream-test--with-state ((&key (initialized t) timer interval) &rest body)
  "Run BODY in a temp buffer with stream state variables bound.
INITIALIZED is bound as `kuro--initialized' (default t).
TIMER is bound as `kuro--stream-idle-timer' (default nil).
INTERVAL is bound as `kuro--stream-min-interval' (default nil).
`kuro--stream-last-render-time' is always reset to 0.0."
  (declare (indent 1))
  `(with-temp-buffer
     (setq-local kuro--initialized ,initialized
                 kuro--stream-idle-timer ,timer
                 kuro--stream-last-render-time 0.0
                 kuro--stream-min-interval ,interval)
     ,@body))

;; Stubs required by kuro-stream.el transitive require chain.
(unless (fboundp 'kuro-core-init)
  (fset 'kuro-core-init (lambda (&rest _) t)))
(unless (fboundp 'kuro-core-resize)
  (fset 'kuro-core-resize (lambda (&rest _) t)))
(unless (fboundp 'kuro-core-send-key)
  (fset 'kuro-core-send-key (lambda (&rest _) nil)))
(unless (fboundp 'kuro-core-poll-updates)
  (fset 'kuro-core-poll-updates (lambda () nil)))
(unless (fboundp 'kuro-core-poll-updates-with-faces)
  (fset 'kuro-core-poll-updates-with-faces (lambda () nil)))
(unless (fboundp 'kuro-core-get-cursor)
  (fset 'kuro-core-get-cursor (lambda () nil)))
(unless (fboundp 'kuro-core-is-cursor-visible)
  (fset 'kuro-core-is-cursor-visible (lambda () t)))
(unless (fboundp 'kuro-core-get-cursor-shape)
  (fset 'kuro-core-get-cursor-shape (lambda () 0)))
(unless (fboundp 'kuro-core-get-mouse-tracking-mode)
  (fset 'kuro-core-get-mouse-tracking-mode (lambda () nil)))
(unless (fboundp 'kuro-core-get-bracketed-paste)
  (fset 'kuro-core-get-bracketed-paste (lambda () nil)))
(unless (fboundp 'kuro-core-is-alt-screen-active)
  (fset 'kuro-core-is-alt-screen-active (lambda () nil)))
(unless (fboundp 'kuro-core-get-focus-tracking)
  (fset 'kuro-core-get-focus-tracking (lambda () nil)))
(unless (fboundp 'kuro-core-get-kitty-kb-flags)
  (fset 'kuro-core-get-kitty-kb-flags (lambda () 0)))
(unless (fboundp 'kuro-core-get-sync-update-active)
  (fset 'kuro-core-get-sync-update-active (lambda () nil)))
(unless (fboundp 'kuro-core-shutdown)
  (fset 'kuro-core-shutdown (lambda () nil)))
(unless (fboundp 'kuro-core-has-pending-output)
  (fset 'kuro-core-has-pending-output (lambda () nil)))
(unless (fboundp 'kuro-core-get-and-clear-title)
  (fset 'kuro-core-get-and-clear-title (lambda () nil)))
(unless (fboundp 'kuro-core-get-cwd)
  (fset 'kuro-core-get-cwd (lambda () nil)))
(unless (fboundp 'kuro-core-poll-clipboard-actions)
  (fset 'kuro-core-poll-clipboard-actions (lambda () nil)))
(unless (fboundp 'kuro-core-poll-prompt-marks)
  (fset 'kuro-core-poll-prompt-marks (lambda () nil)))
(unless (fboundp 'kuro-core-get-image)
  (fset 'kuro-core-get-image (lambda (_id) nil)))
(unless (fboundp 'kuro-core-poll-image-notifications)
  (fset 'kuro-core-poll-image-notifications (lambda () nil)))
(unless (fboundp 'kuro-core-consume-scroll-events)
  (fset 'kuro-core-consume-scroll-events (lambda () nil)))
(unless (fboundp 'kuro-core-get-palette-updates)
  (fset 'kuro-core-get-palette-updates (lambda () nil)))
(unless (fboundp 'kuro-core-get-default-colors)
  (fset 'kuro-core-get-default-colors (lambda () nil)))
(unless (fboundp 'kuro-core-get-scrollback)
  (fset 'kuro-core-get-scrollback (lambda (_n) nil)))
(unless (fboundp 'kuro-core-clear-scrollback)
  (fset 'kuro-core-clear-scrollback (lambda () nil)))
(unless (fboundp 'kuro-core-set-scrollback-max-lines)
  (fset 'kuro-core-set-scrollback-max-lines (lambda (_n) nil)))
(unless (fboundp 'kuro-core-get-scrollback-count)
  (fset 'kuro-core-get-scrollback-count (lambda () 0)))
(unless (fboundp 'kuro-core-scroll-up)
  (fset 'kuro-core-scroll-up (lambda (_n) nil)))
(unless (fboundp 'kuro-core-scroll-down)
  (fset 'kuro-core-scroll-down (lambda (_n) nil)))
(unless (fboundp 'kuro-core-get-scroll-offset)
  (fset 'kuro-core-get-scroll-offset (lambda () 0)))
;; Typewriter stubs (required by kuro-typewriter.el transitively)
(unless (fboundp 'kuro--typewriter-enqueue)
  (fset 'kuro--typewriter-enqueue (lambda (&rest _) nil)))
(unless (fboundp 'kuro--start-typewriter-timer)
  (fset 'kuro--start-typewriter-timer (lambda () nil)))
(unless (fboundp 'kuro--stop-typewriter-timer)
  (fset 'kuro--stop-typewriter-timer (lambda () nil)))

;; Load the real kuro-stream module now that all stubs are in place.
(require 'kuro-stream)

(defmacro kuro-stream-test--idle-tick-with-buffer (&rest body)
  "Run BODY in a fresh temp buffer with streaming state initialized."
  `(with-temp-buffer
     (setq-local kuro--initialized nil
                 kuro--stream-idle-timer nil
                 kuro--stream-last-render-time 0.0
                 kuro--stream-min-interval nil)
     ,@body))

;;; Group 13: stop timer full-state verification

(ert-deftest kuro-stream-ext2-stop-resets-all-three-vars-atomically ()
  "After kuro--stop-stream-idle-timer, all three vars are at their initial values."
  (kuro-stream-test--with-state ()
    (let ((kuro-streaming-latency-mode t))
      (kuro--start-stream-idle-timer)
      ;; Simulate active state
      (setq kuro--stream-last-render-time (float-time)
            kuro--stream-min-interval (/ 1.0 60))
      (kuro--stop-stream-idle-timer)
      ;; All three must be at initial/reset values
      (should (null kuro--stream-idle-timer))
      (should (= kuro--stream-last-render-time 0.0))
      (should (null kuro--stream-min-interval)))))

;;; Group 14: truthy latency-mode values and start-timer state

(ert-deftest kuro-stream-ext2-idle-tick-truthy-latency-mode-triggers-render ()
  "kuro--stream-idle-tick treats any truthy kuro-streaming-latency-mode as enabled.
A non-t truthy value (e.g. 1 or a string) must pass the `when' guard and
allow a render when all other conditions are met."
  (kuro-stream-test--idle-tick-with-buffer
    (let ((kuro-streaming-latency-mode 1)   ; truthy but not t
          (kuro-frame-rate 60)
          (render-called nil))
      (setq-local kuro--initialized t
                  kuro--stream-last-render-time 0.0
                  kuro--stream-min-interval nil)
      (cl-letf (((symbol-function 'kuro--render-cycle)
                 (lambda () (setq render-called t)))
                ((symbol-function 'kuro--has-pending-output)
                 (lambda () t)))
        (kuro--stream-idle-tick (current-buffer))
        (should render-called)))))

(ert-deftest kuro-stream-ext2-start-timer-does-not-set-min-interval ()
  "kuro--start-stream-idle-timer must NOT eagerly compute kuro--stream-min-interval.
The interval is computed lazily on the first render tick, not at timer-start time."
  (kuro-stream-test--with-state ()
    (let ((kuro-streaming-latency-mode t)
          (kuro-frame-rate 60))
      (kuro--start-stream-idle-timer)
      (unwind-protect
          ;; Starting the timer must not set min-interval; it remains nil.
          (should (null kuro--stream-min-interval))
        (kuro--stop-stream-idle-timer)))))

(ert-deftest kuro-stream-ext2-idle-tick-second-render-allowed-after-elapsed-interval ()
  "Two idle-tick calls with simulated elapsed interval both render successfully.
After the first render sets last-render-time, manually aging it by one interval
allows the second call to render as well."
  (kuro-stream-test--idle-tick-with-buffer
    (let ((kuro-streaming-latency-mode t)
          (kuro-frame-rate 60)
          (render-count 0))
      (setq-local kuro--initialized t
                  kuro--stream-last-render-time 0.0
                  kuro--stream-min-interval nil)
      (cl-letf (((symbol-function 'kuro--render-cycle)
                 (lambda () (cl-incf render-count)))
                ((symbol-function 'kuro--has-pending-output)
                 (lambda () t)))
        ;; First tick renders.
        (kuro--stream-idle-tick (current-buffer))
        (should (= render-count 1))
        ;; Age last-render-time by more than one frame interval so the
        ;; second tick's rate-limit check passes.
        (setq kuro--stream-last-render-time
              (- (float-time) (* 2.0 kuro--stream-min-interval)))
        ;; Second tick must also render.
        (kuro--stream-idle-tick (current-buffer))
        (should (= render-count 2))))))

(ert-deftest kuro-stream-ext2-stop-timer-when-already-cancelled-is-noop ()
  "Cancelling a timer and then calling kuro--stop-stream-idle-timer again is safe.
Once the timer has been cancelled and set to nil by stop, a second stop call
must be a complete no-op (guarded by (when (timerp ...)))."
  (kuro-stream-test--with-state ()
    (let ((kuro-streaming-latency-mode t))
      (kuro--start-stream-idle-timer)
      ;; First stop: cancels and nils the timer.
      (kuro--stop-stream-idle-timer)
      (should (null kuro--stream-idle-timer))
      ;; Second stop: must not error.
      (should-not
       (condition-case err
           (progn (kuro--stop-stream-idle-timer) nil)
         (error err))))))

;;; Group 15 — kuro--start-stream-idle-timer: callback closure captures correct buffer

(ert-deftest kuro-stream-ext2-start-timer-callback-receives-current-buffer ()
  "The lambda passed to run-with-idle-timer captures the buffer at call time.
Stub run-with-idle-timer, extract the fn argument, then verify it calls
kuro--stream-idle-tick with that buffer."
  (kuro-stream-test--with-state ()
    (let ((kuro-streaming-latency-mode t)
          (captured-fn nil)
          (outer-buf nil))
      (setq outer-buf (current-buffer))
      (cl-letf (((symbol-function 'run-with-idle-timer)
                 (lambda (_secs _repeat fn)
                   (setq captured-fn fn)
                   (run-with-timer 3600 nil #'ignore))))
        (kuro--start-stream-idle-timer)
        (unwind-protect
            (progn
              (should (functionp captured-fn))
              ;; Fire the lambda; it should call kuro--stream-idle-tick with outer-buf
              (let ((tick-arg nil))
                (cl-letf (((symbol-function 'kuro--stream-idle-tick)
                           (lambda (buf) (setq tick-arg buf))))
                  (funcall captured-fn)
                  (should (eq tick-arg outer-buf)))))
          (kuro--stop-stream-idle-timer))))))

(ert-deftest kuro-stream-ext2-start-timer-callback-is-lambda ()
  "run-with-idle-timer receives a lambda (not a symbol) as the callback."
  (kuro-stream-test--with-state ()
    (let ((kuro-streaming-latency-mode t)
          (captured-fn nil))
      (cl-letf (((symbol-function 'run-with-idle-timer)
                 (lambda (_secs _repeat fn)
                   (setq captured-fn fn)
                   (run-with-timer 3600 nil #'ignore))))
        (kuro--start-stream-idle-timer)
        (unwind-protect
            (should (functionp captured-fn))
          (kuro--stop-stream-idle-timer))))))

;;; Group 16 — kuro--stream-idle-tick: rate-limit boundary arithmetic

(ert-deftest kuro-stream-ext2-idle-tick-exactly-at-interval-allows-render ()
  "idle-tick renders when elapsed time equals exactly kuro--stream-min-interval.
The guard uses >=, so equality must pass."
  (kuro-stream-test--idle-tick-with-buffer
    (let ((kuro-streaming-latency-mode t)
          (kuro-frame-rate 60)
          (render-called nil)
          (interval (/ 1.0 60)))
      (setq-local kuro--initialized t
                  kuro--stream-min-interval interval
                  ;; Set last-render-time so that (float-time) - last = exactly interval
                  kuro--stream-last-render-time (- (float-time) interval))
      (cl-letf (((symbol-function 'kuro--render-cycle)
                 (lambda () (setq render-called t)))
                ((symbol-function 'kuro--has-pending-output)
                 (lambda () t)))
        (kuro--stream-idle-tick (current-buffer))
        (should render-called)))))

(ert-deftest kuro-stream-ext2-idle-tick-just-below-interval-blocks-render ()
  "idle-tick skips render when elapsed time is effectively 0 (just rendered).
Set last-render-time to a value in the future relative to a large interval so
elapsed = last_render - future > 0 but always < interval.  Use a 1-second
interval so that zero real elapsed time is safely below the threshold."
  (kuro-stream-test--idle-tick-with-buffer
    (let ((kuro-streaming-latency-mode t)
          (kuro-frame-rate 60)
          (render-called nil))
      (setq-local kuro--initialized t
                  ;; Use a 1-second interval so that zero real elapsed time is
                  ;; always < 1.0 — no timing-dependent test fragility.
                  kuro--stream-min-interval 1.0
                  ;; last-render-time = now, so elapsed ≈ 0 << 1.0
                  kuro--stream-last-render-time (float-time))
      (cl-letf (((symbol-function 'kuro--render-cycle)
                 (lambda () (setq render-called t)))
                ((symbol-function 'kuro--has-pending-output)
                 (lambda () t)))
        (kuro--stream-idle-tick (current-buffer))
        (should-not render-called)))))

(ert-deftest kuro-stream-ext2-idle-tick-1fps-interval-is-one-second ()
  "At kuro-frame-rate=1, lazy-init sets kuro--stream-min-interval to exactly 1.0."
  (kuro-stream-test--idle-tick-with-buffer
    (let ((kuro-streaming-latency-mode t)
          (kuro-frame-rate 1))
      (setq-local kuro--initialized t
                  kuro--stream-last-render-time 0.0
                  kuro--stream-min-interval nil)
      (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore)
                ((symbol-function 'kuro--has-pending-output)
                 (lambda () t)))
        (kuro--stream-idle-tick (current-buffer))
        (should (= kuro--stream-min-interval 1.0))))))

(ert-deftest kuro-stream-ext2-idle-tick-render-cycle-called-once-per-tick ()
  "kuro--stream-idle-tick calls kuro--render-cycle exactly once per eligible tick.
The function must not call render more than once even if the state allows it."
  (kuro-stream-test--idle-tick-with-buffer
    (let ((kuro-streaming-latency-mode t)
          (kuro-frame-rate 60)
          (render-count 0))
      (setq-local kuro--initialized t
                  kuro--stream-last-render-time 0.0
                  kuro--stream-min-interval nil)
      (cl-letf (((symbol-function 'kuro--render-cycle)
                 (lambda () (cl-incf render-count)))
                ((symbol-function 'kuro--has-pending-output)
                 (lambda () t)))
        (kuro--stream-idle-tick (current-buffer))
        (should (= render-count 1))))))

(ert-deftest kuro-stream-ext2-stop-when-min-interval-never-set-is-safe ()
  "kuro--stop-stream-idle-timer is safe when kuro--stream-min-interval was never set.
Starting with nil (never initialised) and stopping must leave it nil."
  (kuro-stream-test--with-state ()
    (let ((kuro-streaming-latency-mode t))
      (kuro--start-stream-idle-timer)
      ;; min-interval was never set (remains nil from lazy init)
      (should (null kuro--stream-min-interval))
      (kuro--stop-stream-idle-timer)
      ;; Still nil after stop
      (should (null kuro--stream-min-interval)))))

(ert-deftest kuro-stream-ext2-stop-does-not-reset-vars-when-no-timer-running ()
  "kuro--stop-stream-idle-timer leaves state vars intact when no timer is running.
The guard (when (timerp ...)) prevents the body from executing when the timer
slot is nil, so manually-set last-render-time and min-interval are preserved."
  (kuro-stream-test--with-buffer
    ;; Set non-initial values without starting a timer
    (setq kuro--stream-idle-timer nil
          kuro--stream-last-render-time 42.0
          kuro--stream-min-interval 0.25)
    (require 'kuro-stream)
    (kuro--stop-stream-idle-timer)
    ;; The guard prevented the body — vars must be unchanged
    (should (= kuro--stream-last-render-time 42.0))
    (should (= kuro--stream-min-interval 0.25))))

(ert-deftest kuro-stream-ext2-idle-tick-initialized-becomes-nil-between-calls ()
  "If kuro--initialized is flipped to nil between two ticks, the second tick
must not call kuro--render-cycle."
  (kuro-stream-test--idle-tick-with-buffer
    (let ((kuro-streaming-latency-mode t)
          (kuro-frame-rate 60)
          (render-count 0))
      (setq-local kuro--initialized t
                  kuro--stream-last-render-time 0.0
                  kuro--stream-min-interval nil)
      (cl-letf (((symbol-function 'kuro--render-cycle)
                 (lambda () (cl-incf render-count)))
                ((symbol-function 'kuro--has-pending-output)
                 (lambda () t)))
        ;; First tick: initialized=t, should render
        (kuro--stream-idle-tick (current-buffer))
        (should (= render-count 1))
        ;; Simulate module being torn down (uninitialized)
        (setq-local kuro--initialized nil)
        ;; Also age last-render-time so the rate-limit would pass
        (setq kuro--stream-last-render-time 0.0)
        ;; Second tick: initialized=nil, must not render
        (kuro--stream-idle-tick (current-buffer))
        (should (= render-count 1))))))

(ert-deftest kuro-stream-ext2-idle-tick-has-pending-output-called-in-buffer ()
  "kuro--stream-idle-tick calls kuro--has-pending-output from within the target buffer.
Verify that the call happens while the current-buffer is the buffer passed to tick."
  (kuro-stream-test--idle-tick-with-buffer
    (let ((kuro-streaming-latency-mode t)
          (kuro-frame-rate 60)
          (checked-buf nil))
      (setq-local kuro--initialized t
                  kuro--stream-last-render-time 0.0
                  kuro--stream-min-interval nil)
      (let ((target-buf (current-buffer)))
        (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore)
                  ((symbol-function 'kuro--has-pending-output)
                   (lambda ()
                     (setq checked-buf (current-buffer))
                     t)))
          (kuro--stream-idle-tick target-buf)
          (should (eq checked-buf target-buf)))))))

(provide 'kuro-stream-ext2-test)

;;; kuro-stream-ext2-test.el ends here
