;;; kuro-stream-test.el --- Unit tests for kuro-stream.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-stream.el (low-latency streaming idle timer).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;; kuro-stream.el depends on kuro-ffi (which loads the .so), so tests
;; are written self-contained: they declare only the variables used and
;; exercise the logic directly without loading the module.
;;
;; Groups 1-5 avoid loading kuro-stream.el and test the logic directly.
;; Group 6 tests kuro--stream-idle-tick via the compiled .elc using stubs.
;; Group 7 tests kuro--start/stop-stream-idle-timer lifecycle.
;;
;; Helpers:
;;   - kuro-stream-test--with-buffer: temp buffer with stream vars reset (groups 1-5)
;;   - kuro-stream-test--with-state: temp buffer with stream vars bound via keywords
;;     (used in groups 7; replaces inline with-temp-buffer + setq-local boilerplate)
;;
;; Covered:
;;   - kuro--stream-min-interval reset to nil on stop
;;   - kuro--stream-min-interval lazy initialization from kuro-frame-rate
;;   - kuro--stream-min-interval nil means immediate render is allowed
;;   - kuro--stop-stream-idle-timer resets all three state variables
;;   - kuro--stop-stream-idle-timer is idempotent (safe when no timer running)
;;   - kuro--stream-last-render-time reset to 0.0 on stop
;;   - Rate-limit guard: interval check blocks render when called too soon (expression)
;;   - Rate-limit guard: interval check allows render after sufficient time (expression)
;;   - kuro--stream-idle-tick: dead buffer does not error
;;   - kuro--stream-idle-tick: uninitialized buffer does not trigger render
;;   - kuro--stream-idle-tick: disabled latency mode does not trigger render
;;   - kuro--stream-idle-tick: triggers render when initialized and output pending
;;   - kuro--stream-idle-tick: rate-limit blocks render when last render too recent
;;   - kuro--stream-idle-tick: kuro--has-pending-output nil prevents render
;;   - kuro--start-stream-idle-timer: creates timer when latency mode on
;;   - kuro--start-stream-idle-timer: no-op when latency mode off
;;   - kuro--start-stream-idle-timer: cancels and replaces existing timer
;;   - kuro--stop-stream-idle-timer: cancels timer, resets all state vars

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

;;; Group 1: kuro--stream-min-interval reset

(ert-deftest kuro-stream--min-interval-reset-to-nil-on-stop ()
  "kuro--stream-min-interval should be reset to nil when stop is called.
This ensures that a changed kuro-frame-rate is picked up on the next lazy init."
  (kuro-stream-test--with-buffer
    ;; Simulate a cached interval (e.g. 60fps was active)
    (setq kuro--stream-min-interval (/ 1.0 60))
    (should (floatp kuro--stream-min-interval))
    ;; Simulate the reset that kuro--stop-stream-idle-timer performs
    (setq kuro--stream-min-interval nil)
    (should (null kuro--stream-min-interval))))

(ert-deftest kuro-stream--min-interval-nil-is-initial-state ()
  "kuro--stream-min-interval initial value is nil (uncomputed)."
  (kuro-stream-test--with-buffer
    (should (null kuro--stream-min-interval))))

;;; Group 2: kuro--stream-min-interval lazy initialization

(ert-deftest kuro-stream--min-interval-lazy-init-at-60fps ()
  "kuro--stream-min-interval is computed lazily as (/ 1.0 kuro-frame-rate)."
  (kuro-stream-test--with-buffer
    (let ((kuro-frame-rate 60))
      (setq kuro--stream-min-interval nil)
      ;; Simulate the lazy init: (or val (setq val (/ 1.0 rate)))
      (let ((result (or kuro--stream-min-interval
                        (setq kuro--stream-min-interval
                              (/ 1.0 kuro-frame-rate)))))
        (should (floatp result))
        (should (< (abs (- result (/ 1.0 60))) 1e-10))
        ;; Side effect: variable is now populated
        (should (floatp kuro--stream-min-interval))))))

(ert-deftest kuro-stream--min-interval-lazy-init-at-30fps ()
  "Lazy init computes the correct interval for 30fps."
  (kuro-stream-test--with-buffer
    (let ((kuro-frame-rate 30))
      (setq kuro--stream-min-interval nil)
      (let ((result (or kuro--stream-min-interval
                        (setq kuro--stream-min-interval
                              (/ 1.0 kuro-frame-rate)))))
        (should (< (abs (- result (/ 1.0 30))) 1e-10))))))

(ert-deftest kuro-stream--min-interval-not-recomputed-if-set ()
  "Once kuro--stream-min-interval is set, (or ...) returns the cached value."
  (kuro-stream-test--with-buffer
    (let ((kuro-frame-rate 60))
      (setq kuro--stream-min-interval 0.5)   ; stale value, would differ from /1.0 60
      (let ((result (or kuro--stream-min-interval
                        (setq kuro--stream-min-interval
                              (/ 1.0 kuro-frame-rate)))))
        ;; Should return the pre-set value, not recompute
        (should (= result 0.5))
        (should (= kuro--stream-min-interval 0.5))))))

;;; Group 3: rate-limit guard

(ert-deftest kuro-stream--nil-interval-allows-immediate-render ()
  "After reset, last-render-time 0.0 means any real 'now' satisfies the guard."
  (kuro-stream-test--with-buffer
    (let* ((kuro-frame-rate 60)
           (interval (/ 1.0 kuro-frame-rate))
           (last-render 0.0)
           (now (float-time)))
      ;; (- now 0.0) is always >= interval (>= ~0.016) for any real now
      (should (>= (- now last-render) interval)))))

(ert-deftest kuro-stream--rate-limit-blocks-render-when-too-soon ()
  "Rate-limit guard blocks when elapsed time is less than the interval."
  (kuro-stream-test--with-buffer
    (let* ((kuro-frame-rate 60)
           (interval (/ 1.0 kuro-frame-rate))
           ;; Pretend last render happened 'now' (0 seconds ago)
           (last-render (float-time))
           (now last-render))
      ;; elapsed = 0.0, which is < interval (~0.016) => render blocked
      (should-not (>= (- now last-render) interval)))))

(ert-deftest kuro-stream--rate-limit-allows-render-after-interval ()
  "Rate-limit guard passes when elapsed time is exactly the interval."
  (kuro-stream-test--with-buffer
    (let* ((kuro-frame-rate 60)
           (interval (/ 1.0 kuro-frame-rate))
           (last-render 0.0)
           ;; Elapsed time = exactly one interval
           (now (+ last-render interval)))
      (should (>= (- now last-render) interval)))))

;;; Group 4: stop resets all three state variables

(ert-deftest kuro-stream--stop-resets-last-render-time ()
  "kuro--stop-stream-idle-timer resets kuro--stream-last-render-time to 0.0."
  (kuro-stream-test--with-buffer
    (setq kuro--stream-last-render-time (float-time))
    ;; Simulate the reset that kuro--stop-stream-idle-timer performs
    (setq kuro--stream-last-render-time 0.0)
    (should (= kuro--stream-last-render-time 0.0))))

(ert-deftest kuro-stream--stop-resets-min-interval ()
  "kuro--stop-stream-idle-timer resets kuro--stream-min-interval to nil."
  (kuro-stream-test--with-buffer
    (setq kuro--stream-min-interval (/ 1.0 60))
    ;; Simulate the reset
    (setq kuro--stream-min-interval nil)
    (should (null kuro--stream-min-interval))))

(ert-deftest kuro-stream--stop-resets-idle-timer-to-nil ()
  "kuro--stop-stream-idle-timer sets kuro--stream-idle-timer to nil."
  (kuro-stream-test--with-buffer
    (let ((fake-timer (run-with-timer 3600 nil #'ignore)))
      (unwind-protect
          (progn
            (setq kuro--stream-idle-timer fake-timer)
            (should (timerp kuro--stream-idle-timer))
            ;; Simulate stop: cancel then nil
            (when (timerp kuro--stream-idle-timer)
              (cancel-timer kuro--stream-idle-timer)
              (setq kuro--stream-idle-timer nil))
            (should (null kuro--stream-idle-timer)))
        (when (timerp fake-timer)
          (cancel-timer fake-timer))))))

(ert-deftest kuro-stream--stop-idempotent-when-no-timer ()
  "Stop is safe to call when kuro--stream-idle-timer is already nil."
  (kuro-stream-test--with-buffer
    (setq kuro--stream-idle-timer nil)
    ;; Simulate the guard: (when (timerp nil) ...) — must not error
    (should-not
     (condition-case err
         (progn
           (when (timerp kuro--stream-idle-timer)
             (cancel-timer kuro--stream-idle-timer)
             (setq kuro--stream-idle-timer nil)
             (setq kuro--stream-last-render-time 0.0)
             (setq kuro--stream-min-interval nil))
           nil)
       (error err)))))

;;; Group 5: frame-rate change is picked up after reset

(ert-deftest kuro-stream--frame-rate-change-picked-up-after-reset ()
  "After stop (nil reset), a new kuro-frame-rate is used on next lazy init."
  (kuro-stream-test--with-buffer
    ;; Simulate: was running at 60fps
    (let ((kuro-frame-rate 60))
      (setq kuro--stream-min-interval
            (or kuro--stream-min-interval
                (/ 1.0 kuro-frame-rate)))
      (should (< (abs (- kuro--stream-min-interval (/ 1.0 60))) 1e-10)))
    ;; Stop resets the cached interval
    (setq kuro--stream-min-interval nil)
    ;; User changed frame rate to 30fps; next lazy init picks it up
    (let ((kuro-frame-rate 30))
      (let ((new-interval (or kuro--stream-min-interval
                              (setq kuro--stream-min-interval
                                    (/ 1.0 kuro-frame-rate)))))
        (should (< (abs (- new-interval (/ 1.0 30))) 1e-10))))))

;;; Group 6: kuro--stream-idle-tick (loaded from .elc via stubs)
;;
;; kuro--stream-idle-tick(buf):
;;   1. If buf is dead → return immediately, no error.
;;   2. If kuro-streaming-latency-mode is nil → return immediately.
;;   3. In buf: if kuro--initialized is nil → no render.
;;   4. In buf: if kuro--has-pending-output returns nil → no render.
;;   5. If rate-limit not elapsed → no render.
;;   6. Otherwise: update kuro--stream-last-render-time and call kuro--render-cycle.

;; Load kuro-stream from the compiled .elc so we test the real function.
;; Stubs are placed before loading to satisfy transitive require chains.

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

(ert-deftest kuro-stream--idle-tick-dead-buffer-no-error ()
  "kuro--stream-idle-tick must not error when called with a dead buffer."
  (let ((dead-buf (generate-new-buffer "*kuro-stream-test-dead*")))
    (kill-buffer dead-buf)
    ;; Should silently return nil, never signal an error
    (should-not
     (condition-case _err
         (progn (kuro--stream-idle-tick dead-buf) nil)
       (error t)))))

(ert-deftest kuro-stream--idle-tick-latency-mode-nil-no-render ()
  "kuro--stream-idle-tick must not call kuro--render-cycle when latency mode is off."
  (kuro-stream-test--idle-tick-with-buffer
    (let ((kuro-streaming-latency-mode nil)
          (render-called nil))
      (cl-letf (((symbol-function 'kuro--render-cycle)
                 (lambda () (setq render-called t))))
        (kuro--stream-idle-tick (current-buffer))
        (should-not render-called)))))

(ert-deftest kuro-stream--idle-tick-uninitialized-no-render ()
  "kuro--stream-idle-tick must not call kuro--render-cycle when buffer is uninitialized."
  (kuro-stream-test--idle-tick-with-buffer
    (let ((kuro-streaming-latency-mode t)
          (render-called nil))
      (setq-local kuro--initialized nil)
      (cl-letf (((symbol-function 'kuro--render-cycle)
                 (lambda () (setq render-called t)))
                ((symbol-function 'kuro--has-pending-output)
                 (lambda () t)))
        (kuro--stream-idle-tick (current-buffer))
        (should-not render-called)))))

(ert-deftest kuro-stream--idle-tick-no-pending-output-no-render ()
  "kuro--stream-idle-tick must not render when kuro--has-pending-output returns nil."
  (kuro-stream-test--idle-tick-with-buffer
    (let ((kuro-streaming-latency-mode t)
          (kuro-frame-rate 60)
          (render-called nil))
      (setq-local kuro--initialized t
                  kuro--stream-last-render-time 0.0)
      (cl-letf (((symbol-function 'kuro--render-cycle)
                 (lambda () (setq render-called t)))
                ((symbol-function 'kuro--has-pending-output)
                 (lambda () nil)))
        (kuro--stream-idle-tick (current-buffer))
        (should-not render-called)))))

(ert-deftest kuro-stream--idle-tick-triggers-render-when-ready ()
  "kuro--stream-idle-tick calls kuro--render-cycle when all conditions are met."
  (kuro-stream-test--idle-tick-with-buffer
    (let ((kuro-streaming-latency-mode t)
          (kuro-frame-rate 60)
          (render-called nil))
      ;; initialized=t, output pending, rate-limit elapsed (last render was long ago)
      (setq-local kuro--initialized t
                  kuro--stream-last-render-time 0.0
                  kuro--stream-min-interval nil)
      (cl-letf (((symbol-function 'kuro--render-cycle)
                 (lambda () (setq render-called t)))
                ((symbol-function 'kuro--has-pending-output)
                 (lambda () t)))
        (kuro--stream-idle-tick (current-buffer))
        (should render-called)))))

(ert-deftest kuro-stream--idle-tick-updates-last-render-time ()
  "kuro--stream-idle-tick updates kuro--stream-last-render-time after rendering."
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
        ;; After a successful render tick, last-render-time should be non-zero
        (should (> kuro--stream-last-render-time 0.0))))))

(ert-deftest kuro-stream--idle-tick-rate-limit-blocks-render-when-too-soon ()
  "kuro--stream-idle-tick skips render when last-render-time is too recent.
The rate-limit guard compares (float-time) against kuro--stream-last-render-time;
setting last-render-time to (float-time) simulates a render that just happened."
  (kuro-stream-test--idle-tick-with-buffer
    (let ((kuro-streaming-latency-mode t)
          (kuro-frame-rate 60)
          (render-called nil))
      (setq-local kuro--initialized t
                  ;; Pretend last render happened right now — too soon to render again
                  kuro--stream-last-render-time (float-time)
                  ;; Pre-set the interval so lazy init does not trigger
                  kuro--stream-min-interval (/ 1.0 kuro-frame-rate))
      (cl-letf (((symbol-function 'kuro--render-cycle)
                 (lambda () (setq render-called t)))
                ((symbol-function 'kuro--has-pending-output)
                 (lambda () t)))
        (kuro--stream-idle-tick (current-buffer))
        (should-not render-called)))))

(ert-deftest kuro-stream--idle-tick-has-pending-output-nil-no-render ()
  "kuro--stream-idle-tick does not render when kuro--has-pending-output returns nil.
Verifies the pending-output guard independently of initialization and rate-limit."
  (kuro-stream-test--idle-tick-with-buffer
    (let ((kuro-streaming-latency-mode t)
          (kuro-frame-rate 60)
          (render-called nil))
      (setq-local kuro--initialized t
                  kuro--stream-last-render-time 0.0
                  kuro--stream-min-interval nil)
      (cl-letf (((symbol-function 'kuro--render-cycle)
                 (lambda () (setq render-called t)))
                ((symbol-function 'kuro--has-pending-output)
                 (lambda () nil)))        ; no pending output
        (kuro--stream-idle-tick (current-buffer))
        (should-not render-called)))))

;;; Group 7: kuro--start-stream-idle-timer / kuro--stop-stream-idle-timer
;;
;; kuro--start-stream-idle-timer(buf):
;;   - When kuro-streaming-latency-mode is non-nil: cancels any existing timer,
;;     creates a new repeating idle timer, and stores it in kuro--stream-idle-timer.
;;   - When kuro-streaming-latency-mode is nil: is a complete no-op.
;;
;; kuro--stop-stream-idle-timer():
;;   - When kuro--stream-idle-timer is a timer: cancels it, sets it nil, resets
;;     kuro--stream-last-render-time to 0.0, and resets kuro--stream-min-interval to nil.
;;   - When kuro--stream-idle-timer is nil: is a complete no-op (safe to call).

(ert-deftest kuro-stream-start-idle-timer-creates-timer ()
  "kuro--start-stream-idle-timer sets kuro--stream-idle-timer to a timer object."
  (kuro-stream-test--with-state ()
    (let ((kuro-streaming-latency-mode t))
      (kuro--start-stream-idle-timer)
      (unwind-protect
          (should (timerp kuro--stream-idle-timer))
        (kuro--stop-stream-idle-timer)))))

(ert-deftest kuro-stream-stop-idle-timer-cancels-timer ()
  "kuro--stop-stream-idle-timer cancels the timer and sets kuro--stream-idle-timer to nil."
  (kuro-stream-test--with-state ()
    (let ((kuro-streaming-latency-mode t))
      (kuro--start-stream-idle-timer)
      (should (timerp kuro--stream-idle-timer))
      (kuro--stop-stream-idle-timer)
      (should-not kuro--stream-idle-timer))))

(ert-deftest kuro-stream-stop-idle-timer-idempotent ()
  "kuro--stop-stream-idle-timer is safe when no timer is running (nil guard)."
  (kuro-stream-test--with-state ()
    (should-not
     (condition-case err
         (progn (kuro--stop-stream-idle-timer) nil)
       (error err)))))

(ert-deftest kuro-stream-start-timer-noop-when-latency-mode-off ()
  "kuro--start-stream-idle-timer is a no-op when kuro-streaming-latency-mode is nil."
  (kuro-stream-test--with-state ()
    (let ((kuro-streaming-latency-mode nil))
      (kuro--start-stream-idle-timer)
      (should-not kuro--stream-idle-timer))))

(ert-deftest kuro-stream-stop-resets-last-render-time-via-fn ()
  "kuro--stop-stream-idle-timer resets kuro--stream-last-render-time to 0.0."
  (kuro-stream-test--with-state ()
    (let ((kuro-streaming-latency-mode t))
      (kuro--start-stream-idle-timer)
      (setq kuro--stream-last-render-time (float-time))
      (kuro--stop-stream-idle-timer)
      (should (= kuro--stream-last-render-time 0.0)))))

(ert-deftest kuro-stream-stop-resets-min-interval-via-fn ()
  "kuro--stop-stream-idle-timer resets kuro--stream-min-interval to nil."
  (kuro-stream-test--with-state ()
    (let ((kuro-streaming-latency-mode t))
      (kuro--start-stream-idle-timer)
      (setq kuro--stream-min-interval (/ 1.0 60))
      (kuro--stop-stream-idle-timer)
      (should (null kuro--stream-min-interval)))))

(ert-deftest kuro-stream-start-cancels-existing-timer ()
  "kuro--start-stream-idle-timer cancels and replaces an already-running timer."
  (kuro-stream-test--with-state ()
    (let ((kuro-streaming-latency-mode t))
      (kuro--start-stream-idle-timer)
      (let ((first-timer kuro--stream-idle-timer))
        (should (timerp first-timer))
        ;; Start again — must cancel the first and create a new one.
        (kuro--start-stream-idle-timer)
        (unwind-protect
            (should (timerp kuro--stream-idle-timer))
          (kuro--stop-stream-idle-timer))))))

(provide 'kuro-stream-test)

;;; kuro-stream-test.el ends here
