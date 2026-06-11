;;; kuro-stream-ext-test.el --- Stream tests: arithmetic, boundaries, callbacks  -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for kuro-stream.el — Groups 9-17.
;; Groups 1-8 are in kuro-stream-test.el.
;; Helper macros are in kuro-stream-test-support.el.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-stream-test-support)

;;; Group 9: kuro-streaming-latency-mode defcustom default

(ert-deftest kuro-stream--latency-mode-default-is-t ()
  "kuro-streaming-latency-mode default value must be t (enabled by default)."
  (should (default-value 'kuro-streaming-latency-mode)))

(ert-deftest kuro-stream--frame-rate-default-is-positive ()
  "kuro-frame-rate default must be a positive integer."
  (let ((val (default-value 'kuro-frame-rate)))
    (should (integerp val))
    (should (> val 0))))

;;; Group 10: min-interval arithmetic at various frame rates

(ert-deftest kuro-stream--min-interval-120fps ()
  "At 120fps, min-interval = 1/120 ≈ 0.00833."
  (kuro-stream-test--with-buffer
    (let* ((kuro-frame-rate 120)
           (interval (/ 1.0 kuro-frame-rate)))
      (should (floatp interval))
      (should (< (abs (- interval (/ 1.0 120))) 1e-12)))))

(ert-deftest kuro-stream--min-interval-1fps ()
  "At 1fps, min-interval = 1.0 exactly."
  (kuro-stream-test--with-buffer
    (let* ((kuro-frame-rate 1)
           (interval (/ 1.0 kuro-frame-rate)))
      (should (= interval 1.0)))))

(ert-deftest kuro-stream--rate-limit-blocks-at-fractional-elapsed ()
  "Elapsed time of half the interval does not satisfy the rate-limit guard."
  (kuro-stream-test--with-buffer
    (let* ((kuro-frame-rate 60)
           (interval (/ 1.0 kuro-frame-rate))
           (last-render 0.0)
           ;; Only half the interval has elapsed
           (now (+ last-render (/ interval 2.0))))
      (should-not (>= (- now last-render) interval)))))

(ert-deftest kuro-stream--rate-limit-passes-at-double-interval ()
  "Elapsed time of double the interval satisfies the rate-limit guard."
  (kuro-stream-test--with-buffer
    (let* ((kuro-frame-rate 60)
           (interval (/ 1.0 kuro-frame-rate))
           (last-render 0.0)
           (now (+ last-render (* 2.0 interval))))
      (should (>= (- now last-render) interval)))))

;;; Group 11: kuro--stream-idle-tick — latency mode boundary

(ert-deftest kuro-stream--idle-tick-renders-immediately-after-long-idle ()
  "After a very long idle (last render = 0.0), idle-tick renders without delay."
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

(ert-deftest kuro-stream--idle-tick-does-not-render-twice-when-called-twice ()
  "Two consecutive idle-tick calls: second is blocked by rate-limit after first."
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
        ;; First tick: renders, updates last-render-time to ~now
        (kuro--stream-idle-tick (current-buffer))
        (should (= render-count 1))
        ;; Second tick immediately after: last-render-time is ~now, elapsed ≈ 0
        ;; Rate-limit should block the second render.
        (kuro--stream-idle-tick (current-buffer))
        (should (= render-count 1))))))

(ert-deftest kuro-stream--idle-tick-min-interval-populated-after-first-render ()
  "After the first successful render tick, kuro--stream-min-interval is non-nil."
  (kuro-stream-test--idle-tick-with-buffer
    (let ((kuro-streaming-latency-mode t)
          (kuro-frame-rate 30))
      (setq-local kuro--initialized t
                  kuro--stream-last-render-time 0.0
                  kuro--stream-min-interval nil)
      (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore)
                ((symbol-function 'kuro--has-pending-output)
                 (lambda () t)))
        (kuro--stream-idle-tick (current-buffer))
        (should kuro--stream-min-interval)
        (should (< (abs (- kuro--stream-min-interval (/ 1.0 30))) 1e-10))))))

;;; Group 12: start timer creates a repeating idle timer

(ert-deftest kuro-stream-start-timer-is-repeating ()
  "The timer created by kuro--start-stream-idle-timer passes repeat=t.
The stub uses `run-with-timer' (not `run-with-idle-timer') so the stub body
does not re-enter itself via recursion."
  (kuro-stream-test--with-state ()
    (let ((kuro-streaming-latency-mode t)
          (captured-repeat nil))
      (cl-letf (((symbol-function 'run-with-idle-timer)
                 (lambda (_secs repeat _fn)
                   (setq captured-repeat repeat)
                   ;; Use run-with-timer (different function) to avoid recursion
                   (run-with-timer 3600 nil #'ignore))))
        (kuro--start-stream-idle-timer)
        (unwind-protect
            (should captured-repeat)
          (kuro--stop-stream-idle-timer))))))

(ert-deftest kuro-stream-start-timer-uses-zero-delay ()
  "kuro--start-stream-idle-timer passes secs=0 to run-with-idle-timer.
The stub uses `run-with-timer' (not `run-with-idle-timer') so the stub body
does not re-enter itself via recursion."
  (kuro-stream-test--with-state ()
    (let ((kuro-streaming-latency-mode t)
          (captured-delay nil))
      (cl-letf (((symbol-function 'run-with-idle-timer)
                 (lambda (secs _repeat _fn)
                   (setq captured-delay secs)
                   (run-with-timer 3600 nil #'ignore))))
        (kuro--start-stream-idle-timer)
        (unwind-protect
            (should (= captured-delay 0))
          (kuro--stop-stream-idle-timer))))))

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

;;; Group 17: kuro--stream-idle-tick interval staleness + timer callback edge cases

(ert-deftest kuro-stream-ext-stream-idle-tick-interval-initialized-from-frame-rate ()
  "kuro--stream-min-interval is lazily set to (/ 1.0 kuro-frame-rate) on first tick.
With kuro-frame-rate=60 and interval nil, one eligible tick must set the var to
approximately 1/60."
  (kuro-stream-test--idle-tick-with-buffer
    (let ((kuro-streaming-latency-mode t)
          (kuro-frame-rate 60))
      (setq-local kuro--initialized t
                  kuro--stream-last-render-time 0.0
                  kuro--stream-min-interval nil)
      (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore)
                ((symbol-function 'kuro--has-pending-output)
                 (lambda () t)))
        (kuro--stream-idle-tick (current-buffer))
        (should (floatp kuro--stream-min-interval))
        (should (< (abs (- kuro--stream-min-interval (/ 1.0 60))) 1e-10))))))

(ert-deftest kuro-stream-ext-stream-idle-tick-interval-stale-after-rate-change ()
  "kuro--stream-min-interval is NOT updated when kuro-frame-rate changes mid-stream.
Once the interval is cached (e.g. from 60fps), changing kuro-frame-rate to 30
without stopping/starting the timer leaves the cached 60fps value in place.
This documents the intended lazy-cache behavior: stop+start is required to pick
up a new frame rate."
  (kuro-stream-test--idle-tick-with-buffer
    (let ((kuro-streaming-latency-mode t)
          (kuro-frame-rate 60))
      (setq-local kuro--initialized t
                  kuro--stream-last-render-time 0.0
                  kuro--stream-min-interval nil)
      (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore)
                ((symbol-function 'kuro--has-pending-output)
                 (lambda () t)))
        ;; First tick: lazy-init sets interval from 60fps
        (kuro--stream-idle-tick (current-buffer))
        (let ((interval-at-60 kuro--stream-min-interval))
          (should (< (abs (- interval-at-60 (/ 1.0 60))) 1e-10))
          ;; Change frame rate to 30fps WITHOUT stopping the stream
          (setq kuro-frame-rate 30)
          ;; Age last-render-time so the rate-limit passes on next tick
          (setq kuro--stream-last-render-time 0.0)
          ;; Second tick: (or cached-interval ...) returns cached value, not recomputed
          (kuro--stream-idle-tick (current-buffer))
          ;; Interval must still be the 60fps value, not the new 30fps value
          (should (< (abs (- kuro--stream-min-interval (/ 1.0 60))) 1e-10))
          (should-not (< (abs (- kuro--stream-min-interval (/ 1.0 30))) 1e-10)))))))

(ert-deftest kuro-stream-ext-stop-stream-resets-interval ()
  "kuro--stop-stream-idle-timer sets kuro--stream-min-interval to nil.
After stop, the next start+tick will re-initialize the interval from the
then-current kuro-frame-rate, allowing a rate change to take effect."
  (kuro-stream-test--with-state ()
    (let ((kuro-streaming-latency-mode t)
          (kuro-frame-rate 60))
      ;; Simulate a cached interval from 60fps
      (setq kuro--stream-min-interval (/ 1.0 60))
      (kuro--start-stream-idle-timer)
      (unwind-protect
          (progn
            (should (floatp kuro--stream-min-interval))
            (kuro--stop-stream-idle-timer)
            ;; After stop, interval is nil — new rate will be picked up on next lazy init
            (should (null kuro--stream-min-interval)))
        ;; Cleanup in case stop wasn't reached
        (when (timerp kuro--stream-idle-timer)
          (kuro--stop-stream-idle-timer))))))

(ert-deftest kuro-stream-ext-stream-timer-callback-calls-render-when-live ()
  "The timer lambda calls kuro--render-cycle when the buffer is live and initialized.
Capture the lambda from run-with-idle-timer, then invoke it directly to verify
the render path is reached."
  (kuro-stream-test--with-state ()
    (let ((kuro-streaming-latency-mode t)
          (kuro-frame-rate 60)
          (captured-fn nil)
          (render-called nil))
      (setq-local kuro--initialized t
                  kuro--stream-last-render-time 0.0
                  kuro--stream-min-interval nil)
      (cl-letf (((symbol-function 'run-with-idle-timer)
                 (lambda (_secs _repeat fn)
                   (setq captured-fn fn)
                   (run-with-timer 3600 nil #'ignore))))
        (kuro--start-stream-idle-timer)
        (unwind-protect
            (progn
              (should (functionp captured-fn))
              (cl-letf (((symbol-function 'kuro--render-cycle)
                         (lambda () (setq render-called t)))
                        ((symbol-function 'kuro--has-pending-output)
                         (lambda () t)))
                (funcall captured-fn)
                (should render-called)))
          (kuro--stop-stream-idle-timer))))))

(ert-deftest kuro-stream-ext-stream-timer-callback-skips-dead-buffer ()
  "The timer lambda is a no-op when the captured buffer has been killed.
Kill the buffer, invoke the lambda, verify no error and render not called."
  (let ((kuro-streaming-latency-mode t)
        (captured-fn nil)
        (render-called nil)
        (test-buf (generate-new-buffer "*kuro-stream-ext-dead-test*")))
    (with-current-buffer test-buf
      (setq-local kuro--initialized t
                  kuro--stream-idle-timer nil
                  kuro--stream-last-render-time 0.0
                  kuro--stream-min-interval nil)
      (cl-letf (((symbol-function 'run-with-idle-timer)
                 (lambda (_secs _repeat fn)
                   (setq captured-fn fn)
                   (run-with-timer 3600 nil #'ignore))))
        (kuro--start-stream-idle-timer)
        ;; Cleanup the real timer before killing the buffer
        (when (timerp kuro--stream-idle-timer)
          (cancel-timer kuro--stream-idle-timer)
          (setq kuro--stream-idle-timer nil))))
    ;; Kill the buffer so callback sees a dead buffer
    (kill-buffer test-buf)
    (should (functionp captured-fn))
    (cl-letf (((symbol-function 'kuro--render-cycle)
               (lambda () (setq render-called t)))
              ((symbol-function 'kuro--has-pending-output)
               (lambda () t)))
      ;; Must not error even with dead buffer
      (should-not
       (condition-case err
           (progn (funcall captured-fn) nil)
         (error err)))
      (should-not render-called))))

(ert-deftest kuro-stream-ext-stop-stream-handles-non-timer-symbol ()
  "kuro--stop-stream-idle-timer is a no-op when kuro--stream-idle-timer holds a
non-timerp symbol (e.g. 'fake-timer).  The (when (timerp ...)) guard prevents
the body from executing, so the timer var retains the symbol value and other
state vars remain unchanged.  No error must be signalled."
  (kuro-stream-test--with-buffer
    ;; Store a non-timer symbol in the timer slot
    (setq kuro--stream-idle-timer 'fake-timer
          kuro--stream-last-render-time 7.0
          kuro--stream-min-interval 0.1)
    ;; Must not error
    (should-not
     (condition-case err
         (progn (kuro--stop-stream-idle-timer) nil)
       (error err)))
    ;; Guard prevents body: timer var keeps the non-timer symbol
    (should (eq kuro--stream-idle-timer 'fake-timer))
    ;; Other state vars also unchanged (body never ran)
    (should (= kuro--stream-last-render-time 7.0))
    (should (= kuro--stream-min-interval 0.1))))

(provide 'kuro-stream-test)

;;; kuro-stream-test.el ends here


(provide 'kuro-stream-ext-test)

;;; kuro-stream-ext-test.el ends here
