;;; kuro-tui-mode-test.el --- Unit tests for kuro-tui-mode.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-tui-mode.el (TUI mode detection and adaptive frame rate).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;; All timer and stream functions are stubbed with cl-letf.
;;
;; These tests verify the TUI mode subsystem in isolation, independently
;; of kuro-renderer.el.  The same functions are also exercised through
;; kuro-renderer-test.el (Group 8, Group 9, Group 16) since kuro-renderer
;; re-exports everything via its (require 'kuro-tui-mode).

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-tui-mode)

;; kuro--last-rows is defvar-permanent-local in kuro.el (not required here).
;; Declare it so tests can bind it locally.
(defvar-local kuro--last-rows 0)

;;; Test helpers

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

;;; Group A: kuro--detect-tui-mode (pure heuristic)

(defconst kuro-tui-test--detect-table
  '((kuro-tui-mode-detect-above-threshold                      9  10 0.8 t)
    (kuro-tui-mode-detect-below-threshold                      1  10 0.8 nil)
    (kuro-tui-mode-detect-at-exact-threshold                   8  10 0.8 t)
    (kuro-tui-mode-detect-one-below-threshold                  7  10 0.8 nil)
    (kuro-tui-mode-detect-all-dirty                           24  24 0.8 t)
    (kuro-tui-mode-detect-zero-dirty                           0  24 0.8 nil)
    (kuro-tui-mode-detect-single-row-terminal-full-dirty       1   1 0.8 t)
    (kuro-tui-mode-detect-single-row-terminal-zero-dirty       0   1 0.8 nil)
    (kuro-tui-mode-detect-large-terminal-just-below-threshold 80 100 0.8 t)
    (kuro-tui-mode-detect-large-terminal-one-under-threshold  79 100 0.8 nil)
    (kuro-tui-mode-detect-high-threshold                       9  10 0.9 t)
    (kuro-tui-mode-detect-high-threshold-one-below             8  10 0.9 nil)
    (kuro-tui-mode-detect-zero-total-rows                      0   0 0.8 t)
    ;; Group G: alternate threshold values
    (kuro-tui-mode-detect-threshold-half                       5  10 0.5 t)
    (kuro-tui-mode-detect-threshold-half-below                 4  10 0.5 nil)
    (kuro-tui-mode-detect-threshold-one                       10  10 1.0 t)
    (kuro-tui-mode-detect-threshold-one-one-below              9  10 1.0 nil)
    (kuro-tui-mode-detect-dirty-equals-total-24-09            24  24 0.9 t)
    (kuro-tui-mode-detect-dirty-equals-total-80-08            80  80 0.8 t))
  "Table of (test-name dirty total threshold expectedp) for `kuro--detect-tui-mode'.")

(defmacro kuro-tui-test--def-detect (test-name dirty total threshold expectedp)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--detect-tui-mode' %d/%d@%.1f => %s." dirty total threshold expectedp)
     ,(if expectedp
          `(should (kuro--detect-tui-mode ,dirty ,total ,threshold))
        `(should-not (kuro--detect-tui-mode ,dirty ,total ,threshold)))))

(kuro-tui-test--def-detect kuro-tui-mode-detect-above-threshold                      9  10 0.8 t)
(kuro-tui-test--def-detect kuro-tui-mode-detect-below-threshold                      1  10 0.8 nil)
(kuro-tui-test--def-detect kuro-tui-mode-detect-at-exact-threshold                   8  10 0.8 t)
(kuro-tui-test--def-detect kuro-tui-mode-detect-one-below-threshold                  7  10 0.8 nil)
(kuro-tui-test--def-detect kuro-tui-mode-detect-all-dirty                           24  24 0.8 t)
(kuro-tui-test--def-detect kuro-tui-mode-detect-zero-dirty                           0  24 0.8 nil)
(kuro-tui-test--def-detect kuro-tui-mode-detect-single-row-terminal-full-dirty       1   1 0.8 t)
(kuro-tui-test--def-detect kuro-tui-mode-detect-single-row-terminal-zero-dirty       0   1 0.8 nil)
(kuro-tui-test--def-detect kuro-tui-mode-detect-large-terminal-just-below-threshold 80 100 0.8 t)
(kuro-tui-test--def-detect kuro-tui-mode-detect-large-terminal-one-under-threshold  79 100 0.8 nil)
(kuro-tui-test--def-detect kuro-tui-mode-detect-high-threshold                       9  10 0.9 t)
(kuro-tui-test--def-detect kuro-tui-mode-detect-high-threshold-one-below             8  10 0.9 nil)
(kuro-tui-test--def-detect kuro-tui-mode-detect-zero-total-rows                      0   0 0.8 t)
;; Group G — alternate threshold values
(kuro-tui-test--def-detect kuro-tui-mode-detect-threshold-half                        5  10 0.5 t)
(kuro-tui-test--def-detect kuro-tui-mode-detect-threshold-half-below                  4  10 0.5 nil)
(kuro-tui-test--def-detect kuro-tui-mode-detect-threshold-one                        10  10 1.0 t)
(kuro-tui-test--def-detect kuro-tui-mode-detect-threshold-one-one-below               9  10 1.0 nil)
(kuro-tui-test--def-detect kuro-tui-mode-detect-dirty-equals-total-24-09             24  24 0.9 t)
(kuro-tui-test--def-detect kuro-tui-mode-detect-dirty-equals-total-80-08             80  80 0.8 t)

(ert-deftest kuro-tui-test--all-detect-cases-correct ()
  "All entries in `kuro-tui-test--detect-table' match `kuro--detect-tui-mode'."
  (dolist (entry kuro-tui-test--detect-table)
    (pcase-let ((`(,_name ,dirty ,total ,threshold ,expectedp) entry))
      (if expectedp
          (should (kuro--detect-tui-mode dirty total threshold))
        (should-not (kuro--detect-tui-mode dirty total threshold))))))

;;; Group B: kuro--enter-tui-mode / kuro--exit-tui-mode

;; ── Timer side-effects ─────────────────────────────────────────────────────

(defconst kuro-tui-mode-test--enter-exit-timer-table
  '((kuro-tui-mode-enter-stops-idle-timer            kuro--enter-tui-mode stopped t)
    (kuro-tui-mode-enter-does-not-start-idle-timer   kuro--enter-tui-mode started nil)
    (kuro-tui-mode-exit-restarts-idle-timer          kuro--exit-tui-mode  started t)
    (kuro-tui-mode-exit-does-not-stop-idle-timer     kuro--exit-tui-mode  stopped nil))
  "Table of (test-name fn check-sym expectedp) for timer side-effects of enter/exit.")

(defmacro kuro-tui-mode-test--def-enter-exit-timer (test-name fn check-sym expectedp)
  `(ert-deftest ,test-name ()
     ,(format "Timer side-effect: `%s' — %s %s." fn check-sym
              (if expectedp "fires" "does not fire"))
     (kuro-tui-test--with-buffer
       (kuro-tui-test--with-stubs stopped started switched
         (,fn)
         ,(if expectedp `(should ,check-sym) `(should-not ,check-sym))))))

(kuro-tui-mode-test--def-enter-exit-timer kuro-tui-mode-enter-stops-idle-timer           kuro--enter-tui-mode stopped t)
(kuro-tui-mode-test--def-enter-exit-timer kuro-tui-mode-enter-does-not-start-idle-timer  kuro--enter-tui-mode started nil)
(kuro-tui-mode-test--def-enter-exit-timer kuro-tui-mode-exit-restarts-idle-timer         kuro--exit-tui-mode  started t)
(kuro-tui-mode-test--def-enter-exit-timer kuro-tui-mode-exit-does-not-stop-idle-timer    kuro--exit-tui-mode  stopped nil)

(ert-deftest kuro-tui-mode-test--all-timer-side-effects-correct ()
  "All entries in `kuro-tui-mode-test--enter-exit-timer-table' match actual behavior."
  (dolist (entry kuro-tui-mode-test--enter-exit-timer-table)
    (pcase-let ((`(,_name ,fn ,check-sym ,expectedp) entry))
      (kuro-tui-test--with-buffer
        (kuro-tui-test--with-stubs stopped started switched
          (funcall fn)
          (let ((val (if (eq check-sym 'stopped) stopped started)))
            (if expectedp (should val) (should-not val))))))))

;; ── Rate-switch assertions ──────────────────────────────────────────────────

(defconst kuro-tui-mode-test--enter-exit-rate-table
  '((kuro-tui-mode-enter-switches-to-tui-rate          kuro--enter-tui-mode kuro-tui-frame-rate t)
    (kuro-tui-mode-exit-switches-to-normal-rate         kuro--exit-tui-mode  kuro-frame-rate     t)
    (kuro-tui-mode-enter-uses-tui-frame-rate-not-normal kuro--enter-tui-mode kuro-frame-rate     nil)
    (kuro-tui-mode-exit-uses-normal-frame-rate-not-tui  kuro--exit-tui-mode  kuro-tui-frame-rate nil))
  "Table of (test-name fn rate expectedp) for rate-switch assertions of enter/exit.")

(defmacro kuro-tui-mode-test--def-enter-exit-rate (test-name fn rate expectedp)
  `(ert-deftest ,test-name ()
     ,(format "Rate-switch: `%s' switched to %s %s." fn rate
              (if expectedp "as expected" "not expected"))
     (kuro-tui-test--with-buffer
       (kuro-tui-test--with-stubs stopped started switched
         (,fn)
         ,(if expectedp `(should (= switched ,rate)) `(should-not (= switched ,rate)))))))

(kuro-tui-mode-test--def-enter-exit-rate kuro-tui-mode-enter-switches-to-tui-rate          kuro--enter-tui-mode kuro-tui-frame-rate t)
(kuro-tui-mode-test--def-enter-exit-rate kuro-tui-mode-exit-switches-to-normal-rate         kuro--exit-tui-mode  kuro-frame-rate     t)
(kuro-tui-mode-test--def-enter-exit-rate kuro-tui-mode-enter-uses-tui-frame-rate-not-normal kuro--enter-tui-mode kuro-frame-rate     nil)
(kuro-tui-mode-test--def-enter-exit-rate kuro-tui-mode-exit-uses-normal-frame-rate-not-tui  kuro--exit-tui-mode  kuro-tui-frame-rate nil)

(ert-deftest kuro-tui-mode-test--all-rate-switches-correct ()
  "All entries in `kuro-tui-mode-test--enter-exit-rate-table' match actual behavior."
  (dolist (entry kuro-tui-mode-test--enter-exit-rate-table)
    (pcase-let ((`(,_name ,fn ,rate ,expectedp) entry))
      (kuro-tui-test--with-buffer
        (kuro-tui-test--with-stubs stopped started switched
          (funcall fn)
          (if expectedp
              (should (= switched (symbol-value rate)))
            (should-not (= switched (symbol-value rate)))))))))

;; ── Active-flag assertions ──────────────────────────────────────────────────

(defconst kuro-tui-mode-test--enter-exit-flag-table
  '((kuro-tui-mode-enter-sets-active-flag   kuro--enter-tui-mode nil t)
    (kuro-tui-mode-exit-clears-active-flag  kuro--exit-tui-mode  t   nil))
  "Table of (test-name fn init-active expected-active) for flag toggles of enter/exit.")

(defmacro kuro-tui-mode-test--def-enter-exit-flag (test-name fn init-val expected-val)
  `(ert-deftest ,test-name ()
     ,(format "Active flag: `%s' %s." fn (if expected-val "sets to t" "clears to nil"))
     (kuro-tui-test--with-buffer
       (setq kuro--tui-mode-active ,init-val)
       (kuro-tui-test--with-stubs stopped started switched
         (,fn)
         ,(if expected-val `(should kuro--tui-mode-active) `(should-not kuro--tui-mode-active))))))

(kuro-tui-mode-test--def-enter-exit-flag kuro-tui-mode-enter-sets-active-flag   kuro--enter-tui-mode nil t)
(kuro-tui-mode-test--def-enter-exit-flag kuro-tui-mode-exit-clears-active-flag  kuro--exit-tui-mode  t   nil)

(ert-deftest kuro-tui-mode-test--all-flag-toggles-correct ()
  "All entries in `kuro-tui-mode-test--enter-exit-flag-table' match actual behavior."
  (dolist (entry kuro-tui-mode-test--enter-exit-flag-table)
    (pcase-let ((`(,_name ,fn ,init-val ,expected-val) entry))
      (kuro-tui-test--with-buffer
        (setq kuro--tui-mode-active init-val)
        (kuro-tui-test--with-stubs stopped started switched
          (funcall fn)
          (if expected-val
              (should kuro--tui-mode-active)
            (should-not kuro--tui-mode-active)))))))

;;; Group C: kuro--update-tui-streaming-timer

(ert-deftest kuro-tui-mode-update-increments-count-when-full-dirty ()
  "kuro--update-tui-streaming-timer increments frame count on full-dirty frames."
  (kuro-tui-test--with-buffer
    (setq kuro--last-dirty-count 20)
    (kuro-tui-test--with-stubs stopped started switched
      (kuro--update-tui-streaming-timer)
      (should (= kuro--tui-mode-frame-count 1)))))

(ert-deftest kuro-tui-mode-update-resets-count-when-below-threshold ()
  "kuro--update-tui-streaming-timer resets frame count when below threshold."
  (kuro-tui-test--with-buffer
    (setq kuro--tui-mode-frame-count 3
          kuro--last-dirty-count 5)
    (kuro-tui-test--with-stubs stopped started switched
      (kuro--update-tui-streaming-timer)
      (should (= kuro--tui-mode-frame-count 0)))))

(ert-deftest kuro-tui-mode-update-enters-tui-at-threshold ()
  "kuro--update-tui-streaming-timer enters TUI mode when threshold is reached."
  (kuro-tui-test--with-buffer
    (setq kuro--tui-mode-frame-count (1- kuro--tui-mode-threshold)
          kuro--last-dirty-count 20)
    (kuro-tui-test--with-stubs stopped started switched
      (kuro--update-tui-streaming-timer)
      (should stopped)
      (should kuro--tui-mode-active)
      (should (= switched kuro-tui-frame-rate)))))

(ert-deftest kuro-tui-mode-update-exits-tui-when-clean ()
  "kuro--update-tui-streaming-timer exits TUI mode when dirty count drops."
  (kuro-tui-test--with-buffer
    (setq kuro--tui-mode-frame-count kuro--tui-mode-threshold
          kuro--tui-mode-active t
          kuro--last-dirty-count 5)
    (kuro-tui-test--with-stubs stopped started switched
      (kuro--update-tui-streaming-timer)
      (should started)
      (should-not kuro--tui-mode-active)
      (should (= switched kuro-frame-rate)))))

(ert-deftest kuro-tui-mode-update-noop-when-streaming-mode-disabled ()
  "kuro--update-tui-streaming-timer is a no-op when streaming latency mode is nil."
  (kuro-tui-test--with-buffer
    (setq kuro-streaming-latency-mode nil
          kuro--last-dirty-count 20)
    (kuro-tui-test--with-stubs stopped started switched
      (kuro--update-tui-streaming-timer)
      (should-not stopped)
      (should (= kuro--tui-mode-frame-count 0)))))

(ert-deftest kuro-tui-mode-update-noop-when-last-rows-zero ()
  "kuro--update-tui-streaming-timer is a no-op when kuro--last-rows is 0."
  (kuro-tui-test--with-buffer
    (setq kuro--last-rows 0
          kuro--last-dirty-count 20)
    (kuro-tui-test--with-stubs stopped started switched
      (kuro--update-tui-streaming-timer)
      (should (= kuro--tui-mode-frame-count 0)))))

(provide 'kuro-tui-mode-test)

;;; kuro-tui-mode-test.el ends here
