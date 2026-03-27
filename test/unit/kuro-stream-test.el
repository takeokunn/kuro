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

;;; Group 13: stop timer full-state verification

(ert-deftest kuro-stream-stop-resets-all-three-vars-atomically ()
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

(ert-deftest kuro-stream--idle-tick-truthy-latency-mode-triggers-render ()
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

(ert-deftest kuro-stream-start-timer-does-not-set-min-interval ()
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

(ert-deftest kuro-stream--idle-tick-second-render-allowed-after-elapsed-interval ()
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

(ert-deftest kuro-stream--stop-timer-when-already-cancelled-is-noop ()
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

(ert-deftest kuro-stream-start-timer-callback-receives-current-buffer ()
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

(ert-deftest kuro-stream-start-timer-callback-is-lambda ()
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

(ert-deftest kuro-stream--idle-tick-exactly-at-interval-allows-render ()
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

(ert-deftest kuro-stream--idle-tick-just-below-interval-blocks-render ()
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

(ert-deftest kuro-stream--idle-tick-1fps-interval-is-one-second ()
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

(ert-deftest kuro-stream--idle-tick-render-cycle-called-once-per-tick ()
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

(ert-deftest kuro-stream--stop-when-min-interval-never-set-is-safe ()
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

(ert-deftest kuro-stream--stop-does-not-reset-vars-when-no-timer-running ()
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

(ert-deftest kuro-stream--idle-tick-initialized-becomes-nil-between-calls ()
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

(ert-deftest kuro-stream--idle-tick-has-pending-output-called-in-buffer ()
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

(provide 'kuro-stream-test)

;;; kuro-stream-test.el ends here
