;;; kuro-stream-rate-limit-test.el --- Stream tests: rate-limit boundary arithmetic  -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for kuro-stream.el — Group 16.
;; Groups 9-15 are in kuro-stream-ext-test.el.
;; Helper macros are in kuro-stream-test-support.el.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-stream-test-support)

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


(provide 'kuro-stream-rate-limit-test)

;;; kuro-stream-rate-limit-test.el ends here
