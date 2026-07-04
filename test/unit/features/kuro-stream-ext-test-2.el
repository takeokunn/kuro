;;; kuro-stream-ext-test-2.el --- Stream tests: interval staleness, timer callbacks  -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for kuro-stream.el — Group 17.
;; Groups 9-16 are in kuro-stream-ext-test.el.
;; Helper macros are in kuro-stream-test-support.el.

;;; Code:

(require 'ert)
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


(provide 'kuro-stream-ext-test-2)

;;; kuro-stream-ext-test-2.el ends here
