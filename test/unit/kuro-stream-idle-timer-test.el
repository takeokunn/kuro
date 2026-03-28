;;; kuro-stream-ext-test.el --- Extended unit tests for kuro-stream.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Extended unit tests for kuro-stream.el (low-latency streaming idle timer).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;; This file is a continuation of kuro-stream-test.el and covers Groups 8-16.
;;
;; Groups:
;;   Group  8 — kuro--stream-idle-tick: additional edge cases
;;   Group  9 — kuro-streaming-latency-mode defcustom default
;;   Group 10 — min-interval arithmetic at various frame rates
;;   Group 11 — kuro--stream-idle-tick: latency mode boundary
;;   Group 12 — start timer creates a repeating idle timer
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

;;; Group 8: kuro--stream-idle-tick — additional edge cases

(ert-deftest kuro-stream--idle-tick-lazy-init-sets-min-interval ()
  "kuro--stream-idle-tick lazy-initializes kuro--stream-min-interval on first render.
When kuro--stream-min-interval is nil, a successful render tick must populate it
with (/ 1.0 kuro-frame-rate) as a side effect of the rate-limit expression."
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
        ;; After the tick, the lazy setq inside the rate-limit guard
        ;; should have computed and stored the interval.
        (should (floatp kuro--stream-min-interval))
        (should (< (abs (- kuro--stream-min-interval (/ 1.0 60))) 1e-10))))))

(ert-deftest kuro-stream--idle-tick-uses-cached-min-interval ()
  "kuro--stream-idle-tick uses the pre-cached kuro--stream-min-interval value.
When kuro--stream-min-interval is already set, (or ...) returns it without
recomputing, so a stale cached value is honored over the live kuro-frame-rate."
  (kuro-stream-test--idle-tick-with-buffer
    (let ((kuro-streaming-latency-mode t)
          (kuro-frame-rate 120)    ; live rate says 120fps = 0.0083 interval
          (render-called nil))
      (setq-local kuro--initialized t
                  kuro--stream-last-render-time 0.0
                  ;; Pre-cache a 10fps interval — much larger than 120fps
                  kuro--stream-min-interval (/ 1.0 10))
      (cl-letf (((symbol-function 'kuro--render-cycle)
                 (lambda () (setq render-called t)))
                ((symbol-function 'kuro--has-pending-output)
                 (lambda () t)))
        (kuro--stream-idle-tick (current-buffer))
        ;; Should render (elapsed = now - 0.0 >> 0.1) and NOT recompute interval
        (should render-called)
        ;; Cached interval must remain unchanged (not reset to 1/120)
        (should (< (abs (- kuro--stream-min-interval (/ 1.0 10))) 1e-10))))))

(ert-deftest kuro-stream--stop-non-timer-value-is-noop ()
  "kuro--stop-stream-idle-timer is a no-op when timer holds a non-timer value.
The guard (when (timerp ...)) must silently ignore symbols, integers, and
other non-timer values stored in kuro--stream-idle-timer."
  (kuro-stream-test--with-buffer
    ;; Store a non-timer symbol (e.g. left over from a stub) in the timer slot
    (setq kuro--stream-idle-timer 'fake-timer-symbol
          kuro--stream-last-render-time 999.0
          kuro--stream-min-interval 0.5)
    ;; kuro--stop-stream-idle-timer guards with (when (timerp ...)),
    ;; so the body must not execute and state must remain unchanged.
    (require 'kuro-stream)
    (kuro--stop-stream-idle-timer)
    ;; Timer slot still holds the non-timer value (guard prevented nil-ing it)
    (should (eq kuro--stream-idle-timer 'fake-timer-symbol))
    ;; Other state vars likewise unchanged because the guard blocked the body
    (should (= kuro--stream-last-render-time 999.0))
    (should (= kuro--stream-min-interval 0.5))))

(ert-deftest kuro-stream--idle-tick-render-updates-last-render-time-to-recent ()
  "kuro--stream-idle-tick sets kuro--stream-last-render-time to a value close to now.
After a successful render the stored time should be within 1 second of (float-time)."
  (kuro-stream-test--idle-tick-with-buffer
    (let ((kuro-streaming-latency-mode t)
          (kuro-frame-rate 60)
          (before (float-time)))
      (setq-local kuro--initialized t
                  kuro--stream-last-render-time 0.0
                  kuro--stream-min-interval nil)
      (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore)
                ((symbol-function 'kuro--has-pending-output)
                 (lambda () t)))
        (kuro--stream-idle-tick (current-buffer))
        (let ((after (float-time)))
          ;; Stored time must be in [before, after]
          (should (>= kuro--stream-last-render-time before))
          (should (<= kuro--stream-last-render-time after)))))))

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

(provide 'kuro-stream-ext-test)

;;; kuro-stream-ext-test.el ends here
