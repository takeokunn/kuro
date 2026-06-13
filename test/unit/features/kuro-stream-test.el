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
(require 'kuro-stream-test-support)

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

(defconst kuro-stream-test--min-interval-lazy-init-table
  '((kuro-stream--min-interval-lazy-init-at-60fps 60)
    (kuro-stream--min-interval-lazy-init-at-30fps 30))
  "Table of (test-name frame-rate) for lazy kuro--stream-min-interval init tests.")

(defmacro kuro-stream-test--def-min-interval-lazy-init (test-name frame-rate)
  `(ert-deftest ,test-name ()
     ,(format "kuro--stream-min-interval lazy init computes correct interval for %dfps." frame-rate)
     (kuro-stream-test--with-buffer
       (let ((kuro-frame-rate ,frame-rate))
         (setq kuro--stream-min-interval nil)
         (let ((result (or kuro--stream-min-interval
                           (setq kuro--stream-min-interval
                                 (/ 1.0 kuro-frame-rate)))))
           (should (floatp result))
           (should (< (abs (- result (/ 1.0 ,frame-rate))) 1e-10))
           (should (floatp kuro--stream-min-interval)))))))

(kuro-stream-test--def-min-interval-lazy-init kuro-stream--min-interval-lazy-init-at-60fps 60)
(kuro-stream-test--def-min-interval-lazy-init kuro-stream--min-interval-lazy-init-at-30fps 30)

(ert-deftest kuro-stream-test--min-interval-lazy-init-all-rates-correct ()
  "Invariant: lazy init computes correct interval for all listed frame rates."
  (dolist (entry kuro-stream-test--min-interval-lazy-init-table)
    (pcase-let ((`(,_name ,frame-rate) entry))
      (kuro-stream-test--with-buffer
        (let ((kuro-frame-rate frame-rate))
          (setq kuro--stream-min-interval nil)
          (let ((result (or kuro--stream-min-interval
                            (setq kuro--stream-min-interval (/ 1.0 kuro-frame-rate)))))
            (should (< (abs (- result (/ 1.0 frame-rate))) 1e-10))))))))

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

(defconst kuro-stream-test--stop-reset-sim-table
  '((kuro-stream--stop-resets-last-render-time kuro--stream-last-render-time 0.0)
    (kuro-stream--stop-resets-min-interval     kuro--stream-min-interval     nil))
  "Table: (test-name var-sym expected-after-reset) for simulated stop reset tests.")

(defmacro kuro-stream-test--def-stop-reset-sim (test-name var-sym expected)
  `(ert-deftest ,test-name ()
     ,(format "Simulated stop resets `%s' to %S." var-sym expected)
     (kuro-stream-test--with-buffer
       ,(cond ((null expected)    `(setq ,var-sym (/ 1.0 60)))
              ((zerop expected)   `(setq ,var-sym (float-time)))
              (t                  `(setq ,var-sym t)))
       (setq ,var-sym ,expected)
       ,(if (null expected)
            `(should (null ,var-sym))
          `(should (= ,var-sym ,expected))))))

(kuro-stream-test--def-stop-reset-sim
 kuro-stream--stop-resets-last-render-time kuro--stream-last-render-time 0.0)
(kuro-stream-test--def-stop-reset-sim
 kuro-stream--stop-resets-min-interval kuro--stream-min-interval nil)

(ert-deftest kuro-stream-test--all-stop-resets-sim-correct ()
  "Invariant: simulated stop resets each state variable to its initial value."
  (dolist (entry kuro-stream-test--stop-reset-sim-table)
    (pcase-let ((`(,_name ,var-sym ,expected) entry))
      (kuro-stream-test--with-buffer
        (set var-sym (if expected (float-time) (/ 1.0 60)))
        (set var-sym expected)
        (if expected
            (should (= (symbol-value var-sym) expected))
          (should (null (symbol-value var-sym))))))))

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

;; Load and shared helpers are provided by `kuro-stream-test-support'.

(ert-deftest kuro-stream--idle-tick-dead-buffer-no-error ()
  "kuro--stream-idle-tick must not error when called with a dead buffer."
  (let ((dead-buf (generate-new-buffer "*kuro-stream-test-dead*")))
    (kill-buffer dead-buf)
    ;; Should silently return nil, never signal an error
    (should-not
     (condition-case _err
         (progn (kuro--stream-idle-tick dead-buf) nil)
       (error t)))))

(defconst kuro-stream-test--idle-tick-guard-table
  '((kuro-stream--idle-tick-latency-mode-nil-no-render  nil t   t   t   nil)
    (kuro-stream--idle-tick-uninitialized-no-render     t   nil t   t   nil)
    (kuro-stream--idle-tick-no-pending-output-no-render t   t   nil t   nil)
    (kuro-stream--idle-tick-rate-limit-blocks           t   t   t   nil nil)
    (kuro-stream--idle-tick-triggers-render-when-ready  t   t   t   t   t))
  "Table: (test-name latency init pending elapsed? render?) for idle-tick guard tests.
`elapsed?' t means last-render-time=0.0 (long ago); nil means just-now (rate-limit fires).")

(defmacro kuro-stream-test--def-idle-tick-guard (test-name latency init pending elapsed render)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--stream-idle-tick' latency=%s init=%s pending=%s elapsed=%s → render=%s."
              latency init pending elapsed render)
     (kuro-stream-test--idle-tick-with-buffer
       (let ((kuro-streaming-latency-mode ,latency)
             (kuro-frame-rate 60)
             (render-called nil))
         (setq-local kuro--initialized ,init
                     kuro--stream-last-render-time ,(if elapsed '0.0 '(float-time))
                     kuro--stream-min-interval ,(if elapsed 'nil '(/ 1.0 60)))
         (cl-letf (((symbol-function 'kuro--render-cycle)
                    (lambda () (setq render-called t)))
                   ((symbol-function 'kuro--has-pending-output)
                    (lambda () ,pending)))
           (kuro--stream-idle-tick (current-buffer))
           ,(if render '(should render-called) '(should-not render-called)))))))

(kuro-stream-test--def-idle-tick-guard
 kuro-stream--idle-tick-latency-mode-nil-no-render nil t t t nil)
(kuro-stream-test--def-idle-tick-guard
 kuro-stream--idle-tick-uninitialized-no-render t nil t t nil)
(kuro-stream-test--def-idle-tick-guard
 kuro-stream--idle-tick-no-pending-output-no-render t t nil t nil)
(kuro-stream-test--def-idle-tick-guard
 kuro-stream--idle-tick-rate-limit-blocks t t t nil nil)
(kuro-stream-test--def-idle-tick-guard
 kuro-stream--idle-tick-triggers-render-when-ready t t t t t)

(ert-deftest kuro-stream-test--all-idle-tick-guards-correct ()
  "Invariant: every entry in the idle-tick guard table fires or skips render as expected."
  (dolist (entry kuro-stream-test--idle-tick-guard-table)
    (pcase-let ((`(,_name ,latency ,init ,pending ,elapsed ,render) entry))
      (kuro-stream-test--idle-tick-with-buffer
        (let ((kuro-streaming-latency-mode latency)
              (kuro-frame-rate 60)
              (render-called nil))
          (setq-local kuro--initialized init
                      kuro--stream-last-render-time (if elapsed 0.0 (float-time))
                      kuro--stream-min-interval (if elapsed nil (/ 1.0 60)))
          (cl-letf (((symbol-function 'kuro--render-cycle)
                     (lambda () (setq render-called t)))
                    ((symbol-function 'kuro--has-pending-output)
                     (lambda () pending)))
            (kuro--stream-idle-tick (current-buffer))
            (if render (should render-called) (should-not render-called))))))))

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
        (should (> kuro--stream-last-render-time 0.0))))))

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

(defconst kuro-stream-test--stop-reset-via-fn-table
  '((kuro-stream-stop-resets-last-render-time-via-fn kuro--stream-last-render-time 0.0)
    (kuro-stream-stop-resets-min-interval-via-fn     kuro--stream-min-interval     nil))
  "Table: (test-name var-sym expected-after-reset) for stop-via-function reset tests.")

(defmacro kuro-stream-test--def-stop-reset-via-fn (test-name var-sym expected)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--stop-stream-idle-timer' resets `%s' to %S." var-sym expected)
     (kuro-stream-test--with-state ()
       (let ((kuro-streaming-latency-mode t))
         (kuro--start-stream-idle-timer)
         ,(cond ((null expected)   `(setq ,var-sym (/ 1.0 60)))
                ((zerop expected)  `(setq ,var-sym (float-time)))
                (t                 `(setq ,var-sym t)))
         (kuro--stop-stream-idle-timer)
         ,(if (null expected)
              `(should (null ,var-sym))
            `(should (= ,var-sym ,expected)))))))

(kuro-stream-test--def-stop-reset-via-fn
 kuro-stream-stop-resets-last-render-time-via-fn kuro--stream-last-render-time 0.0)
(kuro-stream-test--def-stop-reset-via-fn
 kuro-stream-stop-resets-min-interval-via-fn kuro--stream-min-interval nil)

(ert-deftest kuro-stream-test--all-stop-resets-via-fn-correct ()
  "Invariant: `kuro--stop-stream-idle-timer' resets each state variable to its initial value."
  (dolist (entry kuro-stream-test--stop-reset-via-fn-table)
    (pcase-let ((`(,_name ,var-sym ,expected) entry))
      (kuro-stream-test--with-state ()
        (let ((kuro-streaming-latency-mode t))
          (kuro--start-stream-idle-timer)
          (set var-sym (if expected (float-time) (/ 1.0 60)))
          (kuro--stop-stream-idle-timer)
          (if expected
              (should (= (symbol-value var-sym) expected))
            (should (null (symbol-value var-sym)))))))))

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

(provide 'kuro-stream-test)

;;; kuro-stream-test.el ends here
