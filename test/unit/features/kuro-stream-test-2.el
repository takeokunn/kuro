;;; kuro-stream-test-2.el --- kuro-stream-test (part 2)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-stream-test-support)

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


(provide 'kuro-stream-test-2)

;;; kuro-stream-test-2.el ends here
