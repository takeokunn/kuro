;;; kuro-renderer-pipeline-ext2-test.el --- Extended pipeline tests (Groups 25-28)  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-renderer.el pipeline — switch-render-timer, eviction,
;; scroll suppression, title sanitization, stop-render-loop, finalize-dirty-updates,
;; apply-dirty-lines, pipeline-step-ffi, and frame-budget-ratio.
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;; All FFI and stream functions are stubbed with cl-letf.
;;
;; Groups covered:
;;     Group 25:  kuro--switch-render-timer
;;     Group 26:  kuro--evict-stale-col-to-buf-entries (threshold + eviction paths)
;;     Group 27:  kuro--process-scroll-events suppression paths and kuro--apply-title-update
;;     Group 28:  kuro--sanitize-title, kuro--stop-render-loop, and additional pipeline edge cases
;;     Group 25 (pipeline-step-ffi / frame-budget-ratio from kuro-renderer-pipeline-test.el)
;;
;; Groups 22-24c are in kuro-renderer-pipeline-ext-test.el.
;; Groups 11-21 are in kuro-renderer-pipeline-test.el.
;; Basic renderer tests (Groups 1-10b) are in kuro-renderer-test.el.

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

(defmacro kuro-renderer-pipeline-test--with-buffer (&rest body)
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

;;; Group 25: kuro--switch-render-timer

(ert-deftest kuro-renderer-pipeline-switch-render-timer-calls-install-with-rate ()
  "kuro--switch-render-timer calls kuro--install-render-timer with the given rate."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((install-rate :unset))
      (cl-letf (((symbol-function 'kuro--install-render-timer)
                 (lambda (r) (setq install-rate r)))
                ((symbol-function 'kuro--recompute-blink-frame-intervals) #'ignore))
        (kuro--switch-render-timer 30)
        (should (= install-rate 30))))))

(ert-deftest kuro-renderer-pipeline-switch-render-timer-calls-recompute-blink ()
  "kuro--switch-render-timer calls kuro--recompute-blink-frame-intervals."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((blink-calls 0))
      (cl-letf (((symbol-function 'kuro--install-render-timer) #'ignore)
                ((symbol-function 'kuro--recompute-blink-frame-intervals)
                 (lambda () (cl-incf blink-calls))))
        (kuro--switch-render-timer 60)
        (should (= blink-calls 1))))))

(ert-deftest kuro-renderer-pipeline-switch-render-timer-passes-rate-verbatim ()
  "kuro--switch-render-timer forwards the exact rate value to kuro--install-render-timer."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((captured-rate :unset))
      (cl-letf (((symbol-function 'kuro--install-render-timer)
                 (lambda (r) (setq captured-rate r)))
                ((symbol-function 'kuro--recompute-blink-frame-intervals) #'ignore))
        (kuro--switch-render-timer 120)
        (should (= captured-rate 120))))))

;;; Group 26: kuro--evict-stale-col-to-buf-entries (threshold + eviction paths)

(ert-deftest kuro-renderer-pipeline-evict-stale-noop-when-last-rows-zero ()
  "kuro--evict-stale-col-to-buf-entries is a no-op when kuro--last-rows is 0."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--last-rows 0)
    (puthash 0 [0 1] kuro--col-to-buf-map)
    (puthash 1 [0 1] kuro--col-to-buf-map)
    (kuro--evict-stale-col-to-buf-entries nil)
    ;; Nothing should be removed — guard prevents eviction before first resize.
    (should (= (hash-table-count kuro--col-to-buf-map) 2))))

(ert-deftest kuro-renderer-pipeline-evict-stale-noop-below-threshold ()
  "kuro--evict-stale-col-to-buf-entries is a no-op when map size <= 2x row count."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--last-rows 4)
    ;; 4 rows * 2 = 8 threshold; put 8 entries (at threshold, not above).
    (dotimes (i 8) (puthash i [0] kuro--col-to-buf-map))
    (kuro--evict-stale-col-to-buf-entries nil)
    ;; Map should be unchanged — 8 is not > 8.
    (should (= (hash-table-count kuro--col-to-buf-map) 8))))

(ert-deftest kuro-renderer-pipeline-evict-stale-triggers-above-threshold ()
  "kuro--evict-stale-col-to-buf-entries evicts when map size > 2x row count."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--last-rows 4)
    ;; 4 rows * 2 = 8; put 9 entries to exceed threshold.
    ;; Rows 4-8 are out-of-bounds (>= kuro--last-rows=4).
    (dotimes (i 9) (puthash i [0] kuro--col-to-buf-map))
    (kuro--evict-stale-col-to-buf-entries nil)
    ;; Out-of-bounds rows (4,5,6,7,8) should be removed; in-bounds (0,1,2,3) kept.
    (should (= (hash-table-count kuro--col-to-buf-map) 4))
    (dotimes (i 4) (should (gethash i kuro--col-to-buf-map)))))

(ert-deftest kuro-renderer-pipeline-evict-stale-removes-empty-c2b-dirty-rows ()
  "kuro--evict-stale-col-to-buf-entries removes rows with empty col-to-buf vectors from dirty list."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--last-rows 2)
    ;; Put 5 entries to exceed 2*2=4 threshold.
    (dotimes (i 5) (puthash i [0 1] kuro--col-to-buf-map))
    ;; dirty-rows: row 0 has empty vector (CJK→ASCII transition).
    (let ((dirty-rows '((((0 . "ascii") . nil) . []))))
      (kuro--evict-stale-col-to-buf-entries dirty-rows))
    ;; Row 0 should be evicted (empty c2b) + rows 2,3,4 (out-of-bounds >= 2).
    (should-not (gethash 0 kuro--col-to-buf-map))
    ;; Row 1 is in-bounds with non-empty vector — should remain.
    (should (gethash 1 kuro--col-to-buf-map))))

(ert-deftest kuro-renderer-pipeline-evict-stale-returns-nil ()
  "kuro--evict-stale-col-to-buf-entries always returns nil."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--last-rows 4)
    ;; Exceed threshold so eviction actually runs.
    (dotimes (i 9) (puthash i [0] kuro--col-to-buf-map))
    (should (null (kuro--evict-stale-col-to-buf-entries nil)))))

;;; Group 27: kuro--process-scroll-events suppression paths and kuro--apply-title-update no-window

(ert-deftest kuro-renderer-pipeline-process-scroll-events-suppressed-when-scrolled ()
  "kuro--process-scroll-events does nothing when kuro--scroll-offset > 0 (scrollback active)."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--scroll-offset 3)
    (let ((consume-called nil)
          (apply-called nil))
      (cl-letf (((symbol-function 'kuro--consume-scroll-events)
                 (lambda () (setq consume-called t) '(1 . 0)))
                ((symbol-function 'kuro--apply-buffer-scroll)
                 (lambda (_up _down) (setq apply-called t))))
        (kuro--process-scroll-events)
        ;; Neither consume nor apply should be called when scrolled back.
        (should-not consume-called)
        (should-not apply-called)))))

(ert-deftest kuro-renderer-pipeline-process-scroll-events-runs-at-scroll-offset-zero ()
  "kuro--process-scroll-events calls kuro--consume-scroll-events when offset is 0."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--scroll-offset 0)
    (let ((consume-called nil))
      (cl-letf (((symbol-function 'kuro--consume-scroll-events)
                 (lambda () (setq consume-called t) nil))
                ((symbol-function 'kuro--apply-buffer-scroll) #'ignore))
        (kuro--process-scroll-events)
        (should consume-called)))))

(ert-deftest kuro-renderer-pipeline-apply-title-update-no-window-skips-frame-rename ()
  "kuro--apply-title-update does not call set-frame-parameter when no window shows the buffer."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((frame-param-called nil))
      (cl-letf (((symbol-function 'kuro--get-and-clear-title)
                 (lambda () "vim"))
                ((symbol-function 'get-buffer-window)
                 (lambda (_buf _all) nil))  ; no window
                ((symbol-function 'set-frame-parameter)
                 (lambda (_frame _param _val) (setq frame-param-called t))))
        (kuro--apply-title-update)
        ;; Buffer must still be renamed.
        (should (string-match-p "\\*kuro: vim\\*" (buffer-name)))
        ;; But set-frame-parameter must NOT have been called.
        (should-not frame-param-called)))))

(ert-deftest kuro-renderer-pipeline-apply-title-update-all-control-chars-stripped ()
  "kuro--apply-title-update strips all C0 control chars including CR and LF."
  (kuro-renderer-pipeline-test--with-buffer
    (cl-letf (((symbol-function 'kuro--get-and-clear-title)
               ;; Title with CR (0x0d) and LF (0x0a) injected.
               (lambda () (concat "bash" (string #x0d #x0a) "injected"))))
      (kuro--apply-title-update)
      ;; CR and LF should be stripped; result: "bashinjected"
      (should (string-match-p "\\*kuro: bashinjected\\*" (buffer-name))))))

(ert-deftest kuro-renderer-pipeline-start-render-loop-calls-recompute-blink ()
  "kuro--start-render-loop calls kuro--recompute-blink-frame-intervals."
  (kuro-renderer-pipeline-test--with-buffer
    (setq-local kuro-frame-rate 30)
    (let ((recompute-calls 0))
      (cl-letf (((symbol-function 'kuro--recompute-blink-frame-intervals)
                 (lambda () (cl-incf recompute-calls)))
                ((symbol-function 'kuro--start-stream-idle-timer) #'ignore))
        (kuro--start-render-loop)
        (when kuro--timer
          (cancel-timer kuro--timer)
          (setq kuro--timer nil))
        (should (= recompute-calls 1))))))

(ert-deftest kuro-renderer-pipeline-start-render-loop-calls-stream-idle-timer ()
  "kuro--start-render-loop calls kuro--start-stream-idle-timer."
  (kuro-renderer-pipeline-test--with-buffer
    (setq-local kuro-frame-rate 30)
    (let ((stream-started nil))
      (cl-letf (((symbol-function 'kuro--recompute-blink-frame-intervals) #'ignore)
                ((symbol-function 'kuro--start-stream-idle-timer)
                 (lambda () (setq stream-started t))))
        (kuro--start-render-loop)
        (when kuro--timer
          (cancel-timer kuro--timer)
          (setq kuro--timer nil))
        (should stream-started)))))

;;; Group 28: kuro--sanitize-title, kuro--stop-render-loop, and additional pipeline edge cases

(defmacro kuro-renderer-pipeline-test--check-sanitize (input expected)
  "Assert that (kuro--sanitize-title INPUT) equals EXPECTED."
  `(should (equal (kuro--sanitize-title ,input) ,expected)))

(ert-deftest kuro-renderer-pipeline-sanitize-title-strips-null-byte ()
  "kuro--sanitize-title removes null bytes (U+0000)."
  (kuro-renderer-pipeline-test--check-sanitize
   (concat "bash" (string 0) "name")
   "bashname"))

(ert-deftest kuro-renderer-pipeline-sanitize-title-strips-escape-char ()
  "kuro--sanitize-title removes ESC (U+001B) and other C0 controls."
  (kuro-renderer-pipeline-test--check-sanitize
   (concat "vim" (string #x1b) "[31m")
   "vim[31m"))

(ert-deftest kuro-renderer-pipeline-sanitize-title-preserves-normal-ascii ()
  "kuro--sanitize-title leaves regular ASCII text unchanged."
  (kuro-renderer-pipeline-test--check-sanitize "bash" "bash"))

(ert-deftest kuro-renderer-pipeline-sanitize-title-strips-bidi-override ()
  "kuro--sanitize-title removes Unicode bidi-override codepoints (U+202A-U+202E)."
  (kuro-renderer-pipeline-test--check-sanitize
   (concat "safe" (string #x202e) "text")
   "safetext"))

(ert-deftest kuro-renderer-pipeline-sanitize-title-strips-del-char ()
  "kuro--sanitize-title removes DEL (U+007F)."
  (kuro-renderer-pipeline-test--check-sanitize
   (concat "abc" (string #x7f) "def")
   "abcdef"))

(ert-deftest kuro-renderer-pipeline-sanitize-title-empty-string-stays-empty ()
  "kuro--sanitize-title returns an empty string when given an empty string."
  (kuro-renderer-pipeline-test--check-sanitize "" ""))

(ert-deftest kuro-renderer-pipeline-stop-render-loop-cancels-timer ()
  "kuro--stop-render-loop cancels the render timer and sets kuro--timer to nil."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--timer (run-with-timer 9999 nil #'ignore))
    (cl-letf (((symbol-function 'kuro--stop-stream-idle-timer) #'ignore))
      (kuro--stop-render-loop))
    (should (null kuro--timer))))

(ert-deftest kuro-renderer-pipeline-stop-render-loop-calls-stop-stream-idle-timer ()
  "kuro--stop-render-loop calls kuro--stop-stream-idle-timer."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((idle-stopped nil))
      (cl-letf (((symbol-function 'kuro--stop-stream-idle-timer)
                 (lambda () (setq idle-stopped t))))
        (kuro--stop-render-loop))
      (should idle-stopped))))

(ert-deftest kuro-renderer-pipeline-finalize-dirty-updates-sets-count ()
  "kuro--finalize-dirty-updates sets kuro--last-dirty-count to (length updates)."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--last-dirty-count 0)
    (cl-letf (((symbol-function 'kuro--evict-stale-col-to-buf-entries) #'ignore))
      (kuro--finalize-dirty-updates '(a b c))
      (should (= kuro--last-dirty-count 3)))))

(ert-deftest kuro-renderer-pipeline-apply-dirty-lines-single-row-calls-update-once ()
  "kuro--apply-dirty-lines calls kuro--update-line-full exactly once for a 1-entry list."
  (kuro-renderer-pipeline-test--with-buffer
    (insert "row\n")
    (let ((call-count 0))
      (cl-letf (((symbol-function 'kuro--update-line-full)
                 (lambda (_row _text _faces _c2b) (cl-incf call-count))))
        (kuro--apply-dirty-lines '((((0 . "hello") . nil) . nil)))
        (should (= call-count 1))))))

;;; Group 25: kuro--pipeline-step-ffi

(ert-deftest kuro-renderer-pipeline-step-ffi-binary-path ()
  "kuro--pipeline-step-ffi calls kuro--poll-updates-binary-optimised when kuro-use-binary-ffi is t."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((kuro-use-binary-ffi t)
          (called nil))
      (cl-letf (((symbol-function 'kuro--poll-updates-binary-optimised)
                 (lambda (_id) (setq called t) '(sentinel)))
                ((symbol-function 'kuro--poll-updates-with-faces)
                 (lambda () (error "must not call faces path"))))
        (let ((result (kuro--pipeline-step-ffi)))
          (should called)
          (should (equal result '(sentinel))))))))

(ert-deftest kuro-renderer-pipeline-step-ffi-faces-path ()
  "kuro--pipeline-step-ffi calls kuro--poll-updates-with-faces when kuro-use-binary-ffi is nil."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((kuro-use-binary-ffi nil)
          (called nil))
      (cl-letf (((symbol-function 'kuro--poll-updates-with-faces)
                 (lambda () (setq called t) '(sentinel)))
                ((symbol-function 'kuro--poll-updates-binary-optimised)
                 (lambda (_id) (error "must not call binary path"))))
        (let ((result (kuro--pipeline-step-ffi)))
          (should called)
          (should (equal result '(sentinel))))))))

;;; Group 26: kuro--update-frame-budget-ratio

(ert-deftest kuro-renderer-update-frame-budget-ratio-decreases-when-over-budget ()
  "kuro--update-frame-budget-ratio nudges ratio down when avg frame time exceeds 0.9 * budget."
  (kuro-renderer-pipeline-test--with-buffer
    ;; Fill ring with durations that average to 95% of the frame budget.
    ;; Budget = 1/30 ≈ 0.0333s.  0.95 * budget ≈ 0.0317s → avg > 0.9 * budget triggers decrease.
    (let ((kuro--frame-budget-ratio 0.8)
          (kuro--frame-duration-ring (make-vector 10 (* 0.95 (/ 1.0 kuro-frame-rate))))
          (kuro--frame-duration-ring-index 0)
          (kuro-frame-rate kuro-frame-rate))
      (kuro--update-frame-budget-ratio (* 0.95 (/ 1.0 kuro-frame-rate)))
      (should (< kuro--frame-budget-ratio 0.8)))))

(ert-deftest kuro-renderer-update-frame-budget-ratio-increases-when-under-budget ()
  "kuro--update-frame-budget-ratio nudges ratio up when avg frame time is below 0.5 * budget."
  (kuro-renderer-pipeline-test--with-buffer
    ;; Fill ring with very short durations — 10% of the frame budget.
    (let ((kuro--frame-budget-ratio 0.6)
          (kuro--frame-duration-ring (make-vector 10 (* 0.1 (/ 1.0 kuro-frame-rate))))
          (kuro--frame-duration-ring-index 0)
          (kuro-frame-rate kuro-frame-rate))
      (kuro--update-frame-budget-ratio (* 0.1 (/ 1.0 kuro-frame-rate)))
      (should (> kuro--frame-budget-ratio 0.6)))))

(ert-deftest kuro-renderer-update-frame-budget-ratio-clamped-at-minimum ()
  "kuro--update-frame-budget-ratio does not decrease below 0.5."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((kuro--frame-budget-ratio 0.5)
          (kuro--frame-duration-ring (make-vector 10 1.0))
          (kuro--frame-duration-ring-index 0)
          (kuro-frame-rate kuro-frame-rate))
      (kuro--update-frame-budget-ratio 1.0)
      (should (>= kuro--frame-budget-ratio 0.5)))))

(ert-deftest kuro-renderer-update-frame-budget-ratio-clamped-at-maximum ()
  "kuro--update-frame-budget-ratio does not increase above 0.8."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((kuro--frame-budget-ratio 0.78)
          (kuro--frame-duration-ring (make-vector 10 0.0))
          (kuro--frame-duration-ring-index 0)
          (kuro-frame-rate kuro-frame-rate))
      (kuro--update-frame-budget-ratio 0.0)
      (should (<= kuro--frame-budget-ratio 0.8)))))

(ert-deftest kuro-renderer-update-frame-budget-ratio-stable-in-midrange ()
  "kuro--update-frame-budget-ratio leaves ratio unchanged when avg is between 0.5 and 0.9 of budget."
  (kuro-renderer-pipeline-test--with-buffer
    ;; 70% of frame budget — in the stable zone.
    (let* ((duration (* 0.7 (/ 1.0 kuro-frame-rate)))
           (kuro--frame-budget-ratio 0.65)
           (kuro--frame-duration-ring (make-vector 10 duration))
           (kuro--frame-duration-ring-index 0)
           (kuro-frame-rate kuro-frame-rate))
      (kuro--update-frame-budget-ratio duration)
      (should (= kuro--frame-budget-ratio 0.65)))))

(provide 'kuro-renderer-pipeline-ext2-test)

;;; kuro-renderer-pipeline-ext2-test.el ends here
