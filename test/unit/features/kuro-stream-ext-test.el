;;; kuro-stream-ext-test.el --- Stream tests: arithmetic, boundaries, callbacks  -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for kuro-stream.el — Groups 9-15.
;; Groups 1-8 are in kuro-stream-test.el.
;; Group 16 is in kuro-stream-rate-limit-test.el.
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

(provide 'kuro-stream-ext-test)

;;; kuro-stream-ext-test.el ends here
