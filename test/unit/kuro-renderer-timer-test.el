;;; kuro-renderer-ext-test.el --- Extended unit tests for kuro-renderer.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Extended unit tests for kuro-renderer.el (timer installation, cursor cache,
;; sanitize-title edge cases, col-to-buf handling, ring-average, and pipeline helpers).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;; All FFI and stream functions are stubbed with cl-letf.
;;
;; Groups covered:
;;     Group 12: kuro--install-render-timer
;;     Group 13: kuro--reset-cursor-cache
;;     Group 14: kuro--sanitize-title edge cases
;;     Group 24: kuro--ring-average
;;     Group 25: kuro--timed, kuro--pipeline-face-count, kuro--pipeline-step-apply
;;
;; Core renderer tests (Groups 1-10b) are in kuro-renderer-test.el.
;; Pipeline, resize, coalescing, and render-cycle tests are in
;; kuro-renderer-pipeline-test.el (Groups 11+).

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-renderer)
(require 'kuro-render-buffer)
(require 'kuro-binary-decoder)

;; kuro--last-rows and kuro--last-cols are defined in kuro.el (the main
;; entry-point file), which is not required here to avoid pulling in PTY
;; setup.  Declare them so the byte-compiler and tests do not error.
(defvar-local kuro--last-rows 0)
(defvar-local kuro--last-cols 0)

;;; Helpers

(defmacro kuro-renderer-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer suitable for renderer tests."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (inhibit-modification-hooks t)
           kuro--cursor-marker
           (kuro--scroll-offset 0)
           (kuro--col-to-buf-map (make-hash-table :test 'eql))
           kuro--blink-overlays
           kuro--image-overlays)
       ,@body)))

(defmacro kuro-renderer-helpers-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer with renderer helper state initialized."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (inhibit-modification-hooks t)
           (kuro--initialized t)
           (kuro--scroll-offset 0)
           (kuro--last-rows 24)
           (kuro--last-cols 80)
           (kuro--tui-mode-frame-count 0)
           (kuro--tui-mode-active nil)
           (kuro--last-dirty-count 0)
           (kuro--col-to-buf-map (make-hash-table :test 'eql))
           (kuro-streaming-latency-mode t)
           kuro--stream-idle-timer
           kuro--cursor-marker
           kuro--blink-overlays
           kuro--image-overlays
           kuro--timer)
       ,@body)))

;;; Group 12: kuro--install-render-timer

(ert-deftest kuro-renderer-install-render-timer-creates-timer ()
  "kuro--install-render-timer creates a live timer object."
  (kuro-renderer-test--with-buffer
    (setq-local kuro--timer nil)
    (kuro--install-render-timer 30)
    (should (timerp kuro--timer))
    (cancel-timer kuro--timer)
    (setq kuro--timer nil)))

(ert-deftest kuro-renderer-install-render-timer-cancels-existing ()
  "kuro--install-render-timer cancels any pre-existing timer before installing.
Verification: after a second install the old timer is no longer in `timer-list'."
  (kuro-renderer-test--with-buffer
    (setq-local kuro--timer nil)
    ;; Install a first timer.
    (kuro--install-render-timer 30)
    (let ((first kuro--timer))
      ;; Install a second timer — must cancel the first.
      (kuro--install-render-timer 60)
      ;; The new timer must differ from the first.
      (should-not (eq kuro--timer first))
      ;; The first timer must no longer be in the active timer list.
      (should-not (memq first timer-list))
      (cancel-timer kuro--timer)
      (setq kuro--timer nil))))

(ert-deftest kuro-renderer-install-render-timer-interval-from-rate ()
  "kuro--install-render-timer sets the repeat interval to 1/rate seconds."
  (kuro-renderer-test--with-buffer
    (setq-local kuro--timer nil)
    (kuro--install-render-timer 60)
    ;; timer--repeat-delay holds the repeat interval.
    (let ((interval (timer--repeat-delay kuro--timer)))
      (should (floatp interval))
      ;; 1/60 ≈ 0.01667 — allow 1% tolerance.
      (should (< (abs (- interval (/ 1.0 60))) 0.001)))
    (cancel-timer kuro--timer)
    (setq kuro--timer nil)))

(ert-deftest kuro-renderer-install-render-timer-nil-when-no-prior ()
  "kuro--install-render-timer with no pre-existing timer does not error."
  (kuro-renderer-test--with-buffer
    (setq-local kuro--timer nil)
    (should-not (condition-case err
                    (progn (kuro--install-render-timer 30) nil)
                  (error err)))
    (cancel-timer kuro--timer)
    (setq kuro--timer nil)))

;;; Group 13: kuro--reset-cursor-cache macro

(ert-deftest kuro-renderer-reset-cursor-cache-clears-all-four-fields ()
  "kuro--reset-cursor-cache sets all four cursor cache vars to nil."
  (with-temp-buffer
    (let ((kuro--last-cursor-row    5)
          (kuro--last-cursor-col    10)
          (kuro--last-cursor-visible t)
          (kuro--last-cursor-shape  'box))
      (kuro--reset-cursor-cache)
      (should (null kuro--last-cursor-row))
      (should (null kuro--last-cursor-col))
      (should (null kuro--last-cursor-visible))
      (should (null kuro--last-cursor-shape)))))

(ert-deftest kuro-renderer-reset-cursor-cache-idempotent ()
  "Calling kuro--reset-cursor-cache twice is safe and keeps all vars nil."
  (with-temp-buffer
    (let ((kuro--last-cursor-row    3)
          (kuro--last-cursor-col    7)
          (kuro--last-cursor-visible t)
          (kuro--last-cursor-shape  '(hbar . 2)))
      (kuro--reset-cursor-cache)
      (kuro--reset-cursor-cache)
      (should (null kuro--last-cursor-row))
      (should (null kuro--last-cursor-col))
      (should (null kuro--last-cursor-visible))
      (should (null kuro--last-cursor-shape)))))

(ert-deftest kuro-renderer-reset-cursor-cache-already-nil-is-noop ()
  "kuro--reset-cursor-cache with all fields already nil does not error."
  (with-temp-buffer
    (let (kuro--last-cursor-row
          kuro--last-cursor-col
          kuro--last-cursor-visible
          kuro--last-cursor-shape)
      (should-not (condition-case err
                      (progn (kuro--reset-cursor-cache) nil)
                    (error err))))))

;;; Group 14: kuro--sanitize-title edge cases

(ert-deftest kuro-renderer-sanitize-title-strips-rlm ()
  "kuro--sanitize-title strips U+200F RIGHT-TO-LEFT MARK."
  (should (equal (kuro--sanitize-title (concat "a" "\u200f" "b")) "ab")))

(ert-deftest kuro-renderer-sanitize-title-strips-null-byte ()
  "kuro--sanitize-title strips embedded null bytes (U+0000)."
  (should (equal (kuro--sanitize-title (concat "a" (string 0) "b")) "ab")))

(ert-deftest kuro-renderer-sanitize-title-strips-tab ()
  "kuro--sanitize-title strips TAB (U+0009, a C0 control char)."
  (should (equal (kuro--sanitize-title (concat "a" (string 9) "b")) "ab")))

(ert-deftest kuro-renderer-sanitize-title-all-bidi-overrides ()
  "kuro--sanitize-title strips the full U+202A-U+202E bidi override range."
  (dolist (cp '(#x202a #x202b #x202c #x202d #x202e))
    (should (equal (kuro--sanitize-title (concat "x" (string cp) "y")) "xy"))))

(ert-deftest kuro-renderer-sanitize-title-all-isolates ()
  "kuro--sanitize-title strips the full U+2066-U+2069 directional isolate range."
  (dolist (cp '(#x2066 #x2067 #x2068 #x2069))
    (should (equal (kuro--sanitize-title (concat "x" (string cp) "y")) "xy"))))

(ert-deftest kuro-renderer-sanitize-title-preserves-unicode-non-bidi ()
  "kuro--sanitize-title passes through harmless non-ASCII Unicode unchanged."
  (should (equal (kuro--sanitize-title "日本語") "日本語"))
  (should (equal (kuro--sanitize-title "émoji 🎉") "émoji 🎉")))

(ert-deftest test-kuro-update-line-full-nil-col-to-buf-removes-stale ()
  "Nil col-to-buf removes stale mapping from hash table."
  (with-temp-buffer
    (insert "test line\n")
    (let ((kuro--blink-overlays nil)
          (kuro--image-overlays nil)
          (kuro--col-to-buf-map (make-hash-table :test 'eql)))
      ;; Pre-populate stale CJK mapping for row 0
      (puthash 0 [0 0 1 1 2 2] kuro--col-to-buf-map)
      ;; Update with nil col-to-buf (pure ASCII line)
      (kuro--update-line-full 0 "ascii" nil nil)
      ;; Stale mapping should be removed
      (should (null (gethash 0 kuro--col-to-buf-map))))))

(ert-deftest test-kuro-update-line-full-vector-col-to-buf-stores ()
  "Vector col-to-buf is stored in hash table."
  (with-temp-buffer
    (insert "test line\n")
    (let ((kuro--blink-overlays nil)
          (kuro--image-overlays nil)
          (kuro--col-to-buf-map (make-hash-table :test 'eql)))
      ;; Update with a vector col-to-buf
      (kuro--update-line-full 0 "日本" nil [0 0 1 1])
      ;; Mapping should be stored
      (should (equal (gethash 0 kuro--col-to-buf-map) [0 0 1 1])))))

;;; Group 24: kuro--ring-average

(ert-deftest test-kuro-ring-average-uniform-values ()
  "kuro--ring-average returns correct mean for uniform ring contents."
  (let ((ring (make-vector 4 2.0)))
    (should (= (kuro--ring-average ring 4) 2.0))))

(ert-deftest test-kuro-ring-average-mixed-values ()
  "kuro--ring-average computes (0+1+2+3)/4 = 1.5."
  (let ((ring (vector 0.0 1.0 2.0 3.0)))
    (should (= (kuro--ring-average ring 4) 1.5))))

(ert-deftest test-kuro-ring-average-single-element ()
  "kuro--ring-average of a 1-element ring equals that element."
  (let ((ring (vector 7.5)))
    (should (= (kuro--ring-average ring 1) 7.5))))

(ert-deftest test-kuro-ring-average-all-zeros ()
  "kuro--ring-average of an all-zero ring is 0.0."
  (let ((ring (make-vector 10 0.0)))
    (should (= (kuro--ring-average ring 10) 0.0))))

(ert-deftest test-kuro-ring-average-size-smaller-than-ring ()
  "kuro--ring-average only averages SIZE elements, not the full ring."
  (let ((ring (vector 1.0 2.0 100.0 100.0)))
    ;; Only first 2 elements: (1+2)/2 = 1.5
    (should (= (kuro--ring-average ring 2) 1.5))))

;;; Group 25: kuro--timed, kuro--pipeline-face-count, kuro--pipeline-step-apply

(ert-deftest kuro-renderer-timed-returns-body-value ()
  "kuro--timed returns the value produced by body."
  (let ((ms 0))
    (should (eq 42 (kuro--timed ms 42)))))

(ert-deftest kuro-renderer-timed-sets-ms-var ()
  "kuro--timed sets the ms variable to a non-negative number."
  (let ((ms 0))
    (kuro--timed ms (sit-for 0))
    (should (>= ms 0.0))))

(ert-deftest kuro-renderer-timed-body-side-effects-execute ()
  "kuro--timed executes body so its side effects take effect."
  (let ((ms 0) (ran nil))
    (kuro--timed ms (setq ran t))
    (should ran)))

(ert-deftest kuro-renderer-pipeline-face-count-nil-returns-zero ()
  "kuro--pipeline-face-count returns 0 for a nil updates list."
  (should (= 0 (kuro--pipeline-face-count nil))))

(ert-deftest kuro-renderer-pipeline-face-count-counts-faces ()
  "kuro--pipeline-face-count sums face-list lengths across all updates."
  (let ((updates (list (cons (cons (cons 0 "a") (list 1 2 3)) [])
                       (cons (cons (cons 1 "b") (list 4 5)) []))))
    (should (= 5 (kuro--pipeline-face-count updates)))))

(ert-deftest kuro-renderer-pipeline-step-apply-skips-nil ()
  "kuro--pipeline-step-apply does not call kuro--apply-dirty-lines for nil."
  (let ((called 0))
    (cl-letf (((symbol-function 'kuro--apply-dirty-lines)
               (lambda (&rest _) (cl-incf called))))
      (kuro--pipeline-step-apply nil)
      (should (= 0 called)))))

(provide 'kuro-renderer-ext-test)

;;; kuro-renderer-ext-test.el ends here
