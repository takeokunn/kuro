;;; kuro-tui-mode-test-2.el --- TUI mode tests Groups F,H,I,J and constants  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-tui-mode)

(defvar-local kuro--last-rows 0)

(defmacro kuro-tui-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer with TUI mode state initialized."
  `(with-temp-buffer
     (let ((kuro--last-rows 24)
           (kuro--tui-mode-frame-count 0)
           (kuro--tui-mode-active nil)
           (kuro--last-dirty-count 0)
           (kuro-streaming-latency-mode t)
           kuro--stream-idle-timer)
       ,@body)))

(defmacro kuro-tui-test--with-stubs (stop-var start-var switch-var &rest body)
  "Run BODY with TUI side-effect functions stubbed.
STOP-VAR, START-VAR, SWITCH-VAR receive t or the rate when called."
  (declare (indent 3))
  `(let ((,stop-var nil) (,start-var nil) (,switch-var nil))
     (cl-letf (((symbol-function 'kuro--stop-stream-idle-timer)
                (lambda () (setq ,stop-var t)))
               ((symbol-function 'kuro--start-stream-idle-timer)
                (lambda () (setq ,start-var t)))
               ((symbol-function 'kuro--switch-render-timer)
                (lambda (rate) (setq ,switch-var rate)))
               ((symbol-function 'kuro--recompute-blink-frame-intervals)
                (lambda () nil)))
       ,@body)))

;;; Group F: kuro--update-tui-streaming-timer — counter accumulation and edge cases

(ert-deftest kuro-tui-mode-update-count-stays-zero-when-not-full-dirty-and-already-zero ()
  "Count stays at 0 when not full-dirty and count was already 0 (t-branch)."
  (kuro-tui-test--with-buffer
    (setq kuro--tui-mode-frame-count 0
          kuro--last-dirty-count 0)
    (kuro-tui-test--with-stubs stopped started switched
      (kuro--update-tui-streaming-timer)
      (should (= kuro--tui-mode-frame-count 0))
      (should-not stopped)
      (should-not started))))

(ert-deftest kuro-tui-mode-update-count-below-threshold-no-enter ()
  "kuro--update-tui-streaming-timer does not enter TUI mode until count equals threshold."
  (kuro-tui-test--with-buffer
    ;; One frame before the trigger
    (setq kuro--tui-mode-frame-count (- kuro--tui-mode-threshold 2)
          kuro--last-dirty-count 20)
    (kuro-tui-test--with-stubs stopped started switched
      (kuro--update-tui-streaming-timer)
      ;; Count should be (threshold - 1): still not triggering enter.
      (should (= kuro--tui-mode-frame-count (1- kuro--tui-mode-threshold)))
      (should-not stopped)
      (should-not kuro--tui-mode-active))))

(ert-deftest kuro-tui-mode-update-count-accumulates-across-calls ()
  "Calling kuro--update-tui-streaming-timer multiple times accumulates the count."
  (kuro-tui-test--with-buffer
    (setq kuro--last-dirty-count 20)
    (kuro-tui-test--with-stubs stopped started switched
      (kuro--update-tui-streaming-timer)
      (kuro--update-tui-streaming-timer)
      (kuro--update-tui-streaming-timer)
      (should (= kuro--tui-mode-frame-count 3)))))

(ert-deftest kuro-tui-mode-update-exits-only-when-count-at-or-above-threshold ()
  "kuro--update-tui-streaming-timer exits TUI mode only when count >= threshold, not before."
  (kuro-tui-test--with-buffer
    ;; count is below threshold — the >= branch should NOT fire.
    (setq kuro--tui-mode-frame-count (1- kuro--tui-mode-threshold)
          kuro--tui-mode-active t
          kuro--last-dirty-count 0)
    (kuro-tui-test--with-stubs stopped started switched
      (kuro--update-tui-streaming-timer)
      ;; Count resets to 0 (t-branch) but kuro--exit-tui-mode is NOT called.
      (should (= kuro--tui-mode-frame-count 0))
      (should-not started))))

(ert-deftest kuro-tui-mode-update-no-double-enter-when-already-active ()
  "kuro--update-tui-streaming-timer does not re-enter TUI mode when already active."
  (kuro-tui-test--with-buffer
    ;; Already active; count is at threshold so full-dirty increments beyond threshold.
    (setq kuro--tui-mode-frame-count kuro--tui-mode-threshold
          kuro--tui-mode-active t
          kuro--last-dirty-count 20)
    (kuro-tui-test--with-stubs stopped started switched
      (kuro--update-tui-streaming-timer)
      ;; Count incremented past threshold but enter should NOT be called again.
      (should (= kuro--tui-mode-frame-count (1+ kuro--tui-mode-threshold)))
      (should-not stopped))))

;; ------------------------------------------------------------
;; Group H: kuro--update-tui-streaming-timer — exit branch with inactive flag
;; ------------------------------------------------------------

(ert-deftest kuro-tui-mode-update-resets-count-when-above-threshold-but-inactive ()
  "kuro--update-tui-streaming-timer resets count when count >= threshold but mode is not active."
  (kuro-tui-test--with-buffer
    (setq kuro--tui-mode-frame-count kuro--tui-mode-threshold
          kuro--tui-mode-active nil
          kuro--last-dirty-count 0)
    (kuro-tui-test--with-stubs stopped started switched
      (kuro--update-tui-streaming-timer)
      (should (= kuro--tui-mode-frame-count 0))
      ;; kuro--exit-tui-mode should NOT have been called (active was nil)
      (should-not started))))

(ert-deftest kuro-tui-mode-update-no-exit-call-when-count-above-threshold-but-inactive ()
  "kuro--update-tui-streaming-timer does not call kuro--exit-tui-mode when already inactive."
  (kuro-tui-test--with-buffer
    (setq kuro--tui-mode-frame-count (* 2 kuro--tui-mode-threshold)
          kuro--tui-mode-active nil
          kuro--last-dirty-count 0)
    (kuro-tui-test--with-stubs stopped started switched
      (kuro--update-tui-streaming-timer)
      (should-not started)
      (should-not stopped))))

(ert-deftest kuro-tui-mode-update-count-resets-to-zero-not-negative ()
  "kuro--update-tui-streaming-timer resets count to exactly 0 (not negative) on clean frame."
  (kuro-tui-test--with-buffer
    (setq kuro--tui-mode-frame-count 5
          kuro--last-dirty-count 0)
    (kuro-tui-test--with-stubs stopped started switched
      (kuro--update-tui-streaming-timer)
      (should (= kuro--tui-mode-frame-count 0)))))

;; ------------------------------------------------------------
;; Group I: kuro--enter-tui-mode / kuro--exit-tui-mode call-order assertions
;; ------------------------------------------------------------

(ert-deftest kuro-tui-mode-enter-stop-before-switch ()
  "kuro--enter-tui-mode stops idle timer before switching render timer."
  (kuro-tui-test--with-buffer
    (let ((call-order nil))
      (cl-letf (((symbol-function 'kuro--stop-stream-idle-timer)
                 (lambda () (push 'stop call-order)))
                ((symbol-function 'kuro--switch-render-timer)
                 (lambda (_r) (push 'switch call-order)))
                ((symbol-function 'kuro--recompute-blink-frame-intervals)
                 (lambda () nil)))
        (kuro--enter-tui-mode)
        (should (equal call-order '(switch stop)))))))

(ert-deftest kuro-tui-mode-exit-switch-before-start ()
  "kuro--exit-tui-mode switches render timer before starting idle timer."
  (kuro-tui-test--with-buffer
    (let ((call-order nil))
      (cl-letf (((symbol-function 'kuro--switch-render-timer)
                 (lambda (_r) (push 'switch call-order)))
                ((symbol-function 'kuro--start-stream-idle-timer)
                 (lambda () (push 'start call-order)))
                ((symbol-function 'kuro--recompute-blink-frame-intervals)
                 (lambda () nil)))
        (kuro--exit-tui-mode)
        (should (equal call-order '(start switch)))))))

(ert-deftest kuro-tui-mode-enter-active-flag-set-after-switch ()
  "kuro--enter-tui-mode sets active flag; subsequent check sees it as t."
  (kuro-tui-test--with-buffer
    (kuro-tui-test--with-stubs stopped started switched
      (should-not kuro--tui-mode-active)
      (kuro--enter-tui-mode)
      (should kuro--tui-mode-active))))

;; ------------------------------------------------------------
;; Group J: kuro--update-tui-streaming-timer — frame-count boundary precision
;; ------------------------------------------------------------

(ert-deftest kuro-tui-mode-update-threshold-minus-one-increments-no-enter ()
  "Frame count at threshold-1 increments to threshold-1+1 but does not enter TUI mode."
  (kuro-tui-test--with-buffer
    (setq kuro--tui-mode-frame-count (- kuro--tui-mode-threshold 1)
          kuro--last-dirty-count 20)
    (kuro-tui-test--with-stubs stopped started switched
      (kuro--update-tui-streaming-timer)
      (should (= kuro--tui-mode-frame-count kuro--tui-mode-threshold))
      (should stopped)
      (should kuro--tui-mode-active))))

(ert-deftest kuro-tui-mode-update-threshold-plus-one-with-active-no-reenter ()
  "Frame count above threshold with mode active: increment continues, no re-enter."
  (kuro-tui-test--with-buffer
    (setq kuro--tui-mode-frame-count (+ kuro--tui-mode-threshold 1)
          kuro--tui-mode-active t
          kuro--last-dirty-count 20)
    (kuro-tui-test--with-stubs stopped started switched
      (kuro--update-tui-streaming-timer)
      (should (= kuro--tui-mode-frame-count (+ kuro--tui-mode-threshold 2)))
      (should-not stopped))))

(ert-deftest kuro-tui-mode-update-exact-exit-at-threshold ()
  "Frame count exactly at threshold with clean frame triggers exit when active."
  (kuro-tui-test--with-buffer
    (setq kuro--tui-mode-frame-count kuro--tui-mode-threshold
          kuro--tui-mode-active t
          kuro--last-dirty-count 1)         ; below 0.8 * 24 = 19.2, so not full-dirty
    (kuro-tui-test--with-stubs stopped started switched
      (kuro--update-tui-streaming-timer)
      (should (= kuro--tui-mode-frame-count 0))
      (should-not kuro--tui-mode-active)
      (should started))))

;;; Constant invariants

(ert-deftest kuro-tui-mode-dirty-threshold-is-fraction ()
  "`kuro--tui-dirty-threshold' is a float between 0 and 1 exclusive."
  (should (floatp kuro--tui-dirty-threshold))
  (should (> kuro--tui-dirty-threshold 0.0))
  (should (< kuro--tui-dirty-threshold 1.0)))

(ert-deftest kuro-tui-mode-dirty-threshold-scaled-matches-threshold ()
  "`kuro--tui-dirty-threshold-scaled' equals (round (* threshold 10))."
  (should (= kuro--tui-dirty-threshold-scaled
             (round (* kuro--tui-dirty-threshold 10)))))

(provide 'kuro-tui-mode-test-2)
;;; kuro-tui-mode-test-2.el ends here
