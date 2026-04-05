;;; kuro-renderer-pipeline-ext-test.el --- Extended pipeline tests (Groups 22-24c)  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-renderer.el pipeline — frame coalescing, render-cycle,
;; and dirty-update dispatch.
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;; All FFI and stream functions are stubbed with cl-letf.
;;
;; Groups covered:
;;     Group 22:  kuro--with-frame-coalescing
;;     Group 22b: kuro--core-render-pipeline-with-timing
;;     Group 22c: kuro--poll-updates-binary error handling
;;     Group 23:  kuro--render-cycle stage-order
;;     Group 24a: kuro--apply-dirty-updates non-debug path
;;     Group 24b: kuro--apply-dirty-updates debug path (kuro-debug-perf non-nil)
;;     Group 24c: kuro--apply-dirty-updates delegates to kuro--finalize-dirty-updates
;;
;; Groups 25-28 are in kuro-renderer-pipeline-ext2-test.el.
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

;;; Group 22: kuro--with-frame-coalescing

(defmacro kuro-renderer-coalesce-test--with-buffer (&rest body)
  "Run BODY with frame-coalescing state initialized in a temporary buffer."
  `(with-temp-buffer
     (let ((kuro--initialized t)
           (kuro--last-render-time 0.0)
           (kuro-frame-rate 120)
           (kuro-tui-frame-rate 30)
           (kuro--tui-mode-active nil))
       ,@body)))

(ert-deftest test-kuro-pipeline-with-frame-coalescing-executes-when-fresh ()
  "Body IS executed when kuro--last-render-time is 0.0 (far in the past)."
  (kuro-renderer-coalesce-test--with-buffer
    (let ((executed nil))
      (kuro--with-frame-coalescing
        (setq executed t))
      (should executed))))

(ert-deftest test-kuro-pipeline-with-frame-coalescing-skips-when-too-recent ()
  "Body is NOT executed when kuro--last-render-time is (float-time) (just now)."
  (kuro-renderer-coalesce-test--with-buffer
    ;; Set last render to right now — within the 4.2ms half-frame at 120fps
    (setq kuro--last-render-time (float-time))
    (let ((executed nil))
      (kuro--with-frame-coalescing
        (setq executed t))
      (should-not executed))))

(ert-deftest test-kuro-pipeline-with-frame-coalescing-executes-after-half-frame ()
  "Body IS executed when kuro--last-render-time is 100ms ago (past half-frame)."
  (kuro-renderer-coalesce-test--with-buffer
    ;; 100ms ago is well past the 4.2ms half-frame at 120fps
    (setq kuro--last-render-time (- (float-time) 0.1))
    (let ((executed nil))
      (kuro--with-frame-coalescing
        (setq executed t))
      (should executed))))

(ert-deftest test-kuro-pipeline-with-frame-coalescing-updates-last-render-time ()
  "After execution, kuro--last-render-time is updated to approximately (float-time)."
  (kuro-renderer-coalesce-test--with-buffer
    (let ((before (float-time)))
      (kuro--with-frame-coalescing
        nil)  ; body does nothing; we only care about the timestamp update
      (should (>= kuro--last-render-time before))
      (should (< (- (float-time) kuro--last-render-time) 0.1)))))

(ert-deftest test-kuro-pipeline-with-frame-coalescing-uses-tui-rate-when-active ()
  "With TUI mode active (30fps), body is skipped when only 5ms have elapsed.
At 30fps, half-frame = 16.7ms; 5ms < 16.7ms so the call is coalesced."
  (kuro-renderer-coalesce-test--with-buffer
    (setq kuro--tui-mode-active t
          ;; 5ms ago — under the 16.7ms half-frame at 30fps
          kuro--last-render-time (- (float-time) 0.005))
    (let ((executed nil))
      (kuro--with-frame-coalescing
        (setq executed t))
      (should-not executed))))

;;; Group 22b: kuro--core-render-pipeline-with-timing

(defmacro kuro-renderer-timing-test--with-buffer (&rest body)
  "Run BODY with all state needed for kuro--core-render-pipeline-with-timing."
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
           (kuro-use-binary-ffi nil)
           (kuro-debug-perf t)
           (kuro--perf-frame-count 0)
           kuro--stream-idle-timer
           kuro--cursor-marker
           kuro--blink-overlays
           kuro--image-overlays
           kuro--timer)
       ,@body)))

(ert-deftest test-kuro-pipeline-core-render-pipeline-with-timing-returns-updates ()
  "kuro--core-render-pipeline-with-timing returns the stubbed update list."
  (kuro-renderer-timing-test--with-buffer
    (let ((fake-updates '((((0 . "hello") . nil) . nil))))
      (cl-letf (((symbol-function 'kuro--apply-title-update)      #'ignore)
                ((symbol-function 'kuro--process-scroll-events)   #'ignore)
                ((symbol-function 'kuro--poll-updates-with-faces) (lambda () fake-updates))
                ((symbol-function 'kuro--apply-dirty-lines)       #'ignore)
                ((symbol-function 'kuro--update-cursor)           #'ignore)
                ((symbol-function 'kuro--perf-report)             #'ignore))
        (should (equal (kuro--core-render-pipeline-with-timing) fake-updates))))))

(ert-deftest test-kuro-pipeline-core-render-pipeline-with-timing-increments-frame-count ()
  "kuro--core-render-pipeline-with-timing increments kuro--perf-frame-count by 1."
  (kuro-renderer-timing-test--with-buffer
    (setq kuro--perf-frame-count 7)
    (cl-letf (((symbol-function 'kuro--apply-title-update)      #'ignore)
              ((symbol-function 'kuro--process-scroll-events)   #'ignore)
              ((symbol-function 'kuro--poll-updates-with-faces) (lambda () nil))
              ((symbol-function 'kuro--apply-dirty-lines)       #'ignore)
              ((symbol-function 'kuro--update-cursor)           #'ignore)
              ((symbol-function 'kuro--perf-report)             #'ignore))
      (kuro--core-render-pipeline-with-timing)
      (should (= kuro--perf-frame-count 8)))))

;;; Group 22c: kuro--poll-updates-binary error handling

(ert-deftest test-kuro-pipeline-poll-updates-binary-returns-nil-on-error ()
  "kuro--poll-updates-binary returns nil when kuro--decode-binary-updates signals args-out-of-range."
  (with-temp-buffer
    (let ((kuro--initialized t)
          (kuro--session-id 1))
      (cl-letf (((symbol-function 'kuro-core-poll-updates-binary)
                 (lambda (_sid) [0 1 2 3]))  ; fake binary vector
                ((symbol-function 'kuro--decode-binary-updates)
                 (lambda (_raw) (signal 'args-out-of-range '(0)))))
        (should-not (kuro--poll-updates-binary))))))

;;; Group 23: kuro--render-cycle

(ert-deftest kuro-renderer-render-cycle-calls-all-4-stages ()
  "kuro--render-cycle calls Stage 1 (resize), all Stage 2 substages, and Stage 3 (TUI timer).
Each stage function is stubbed to record a call; we verify all are called exactly once."
  (kuro-renderer-coalesce-test--with-buffer
    ;; Set last-render-time far in the past so Stage 2 is NOT coalesced.
    (setq kuro--last-render-time 0.0)
    (let ((resize-calls 0)
          (bell-calls 0)
          (dirty-calls 0)
          (poll-calls 0)
          (blink-calls 0)
          (tui-calls 0))
      (cl-letf (((symbol-function 'kuro--handle-pending-resize)
                 (lambda () (cl-incf resize-calls)))
                ((symbol-function 'kuro--ring-pending-bell)
                 (lambda () (cl-incf bell-calls)))
                ((symbol-function 'kuro--apply-dirty-updates)
                 (lambda () (cl-incf dirty-calls)))
                ((symbol-function 'kuro--poll-within-budget)
                 (lambda (_fs) (cl-incf poll-calls)))
                ((symbol-function 'kuro--tick-blink-if-active)
                 (lambda () (cl-incf blink-calls)))
                ((symbol-function 'kuro--update-tui-streaming-timer)
                 (lambda () (cl-incf tui-calls))))
        (kuro--render-cycle)
        (should (= resize-calls 1))   ; Stage 1
        (should (= bell-calls 1))     ; Stage 2a
        (should (= dirty-calls 1))    ; Stage 2b
        (should (= poll-calls 1))     ; Stage 2c
        (should (= blink-calls 1))    ; Stage 2d
        (should (= tui-calls 1))))))  ; Stage 3

(ert-deftest kuro-renderer-render-cycle-resize-always-runs-even-when-coalesced ()
  "Stage 1 (kuro--handle-pending-resize) runs even when Stage 2 is coalesced.
When kuro--last-render-time is (float-time) the half-frame guard suppresses
Stage 2, but Stage 1 must still execute unconditionally."
  (kuro-renderer-coalesce-test--with-buffer
    ;; Render just happened — Stage 2 will be coalesced.
    (setq kuro--last-render-time (float-time))
    (let ((resize-calls 0)
          (bell-calls 0))
      (cl-letf (((symbol-function 'kuro--handle-pending-resize)
                 (lambda () (cl-incf resize-calls)))
                ((symbol-function 'kuro--ring-pending-bell)
                 (lambda () (cl-incf bell-calls)))
                ((symbol-function 'kuro--apply-dirty-updates) #'ignore)
                ((symbol-function 'kuro--poll-within-budget)  (lambda (_fs) nil))
                ((symbol-function 'kuro--tick-blink-if-active) #'ignore)
                ((symbol-function 'kuro--update-tui-streaming-timer) #'ignore))
        (kuro--render-cycle)
        ;; Stage 1 must have run despite coalescing
        (should (= resize-calls 1))
        ;; Stage 2a (bell) must NOT have run — it is inside the coalescing gate
        (should (= bell-calls 0))))))

(ert-deftest kuro-renderer-render-cycle-tui-timer-always-runs-even-when-coalesced ()
  "Stage 3 (kuro--update-tui-streaming-timer) runs even when Stage 2 is coalesced.
When kuro--last-render-time is (float-time) the half-frame guard suppresses
Stage 2, but Stage 3 must still execute unconditionally on every timer tick."
  (kuro-renderer-coalesce-test--with-buffer
    ;; Render just happened — Stage 2 will be coalesced.
    (setq kuro--last-render-time (float-time))
    (let ((tui-calls 0))
      (cl-letf (((symbol-function 'kuro--handle-pending-resize) #'ignore)
                ((symbol-function 'kuro--ring-pending-bell)     #'ignore)
                ((symbol-function 'kuro--apply-dirty-updates)   #'ignore)
                ((symbol-function 'kuro--poll-within-budget)    (lambda (_fs) nil))
                ((symbol-function 'kuro--tick-blink-if-active)  #'ignore)
                ((symbol-function 'kuro--update-tui-streaming-timer)
                 (lambda () (cl-incf tui-calls))))
        (kuro--render-cycle)
        ;; Stage 3 must have run despite Stage 2 being coalesced
        (should (= tui-calls 1))))))

;;; Group 24a: kuro--apply-dirty-updates — non-debug path

(ert-deftest kuro-renderer-pipeline-apply-dirty-updates-calls-core-pipeline ()
  "kuro--apply-dirty-updates calls kuro--core-render-pipeline when kuro-debug-perf is nil."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((core-calls 0)
          (timing-calls 0)
          (kuro-debug-perf nil))
      (cl-letf (((symbol-function 'kuro--core-render-pipeline)
                 (lambda () (cl-incf core-calls) nil))
                ((symbol-function 'kuro--core-render-pipeline-with-timing)
                 (lambda () (cl-incf timing-calls) nil))
                ((symbol-function 'kuro--finalize-dirty-updates) #'ignore))
        (kuro--apply-dirty-updates)
        (should (= core-calls 1))
        (should (= timing-calls 0))))))

(ert-deftest kuro-renderer-pipeline-apply-dirty-updates-does-not-call-timing-on-non-debug ()
  "kuro--apply-dirty-updates never calls the timing variant when kuro-debug-perf is nil."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((timing-calls 0)
          (kuro-debug-perf nil))
      (cl-letf (((symbol-function 'kuro--core-render-pipeline) (lambda () nil))
                ((symbol-function 'kuro--core-render-pipeline-with-timing)
                 (lambda () (cl-incf timing-calls) nil))
                ((symbol-function 'kuro--finalize-dirty-updates) #'ignore))
        (kuro--apply-dirty-updates)
        (should (= timing-calls 0))))))

;;; Group 24b: kuro--apply-dirty-updates — debug path (kuro-debug-perf non-nil)

(ert-deftest kuro-renderer-pipeline-apply-dirty-updates-calls-timing-when-debug-perf ()
  "kuro--apply-dirty-updates calls kuro--core-render-pipeline-with-timing when kuro-debug-perf is non-nil."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((core-calls 0)
          (timing-calls 0)
          (kuro-debug-perf t)
          (kuro--perf-frame-count 0))
      (cl-letf (((symbol-function 'kuro--core-render-pipeline)
                 (lambda () (cl-incf core-calls) nil))
                ((symbol-function 'kuro--core-render-pipeline-with-timing)
                 (lambda () (cl-incf timing-calls) nil))
                ((symbol-function 'kuro--finalize-dirty-updates) #'ignore))
        (kuro--apply-dirty-updates)
        (should (= timing-calls 1))
        (should (= core-calls 0))))))

(ert-deftest kuro-renderer-pipeline-apply-dirty-updates-does-not-call-core-on-debug ()
  "kuro--apply-dirty-updates never calls kuro--core-render-pipeline when kuro-debug-perf is non-nil."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((core-calls 0)
          (kuro-debug-perf t)
          (kuro--perf-frame-count 0))
      (cl-letf (((symbol-function 'kuro--core-render-pipeline)
                 (lambda () (cl-incf core-calls) nil))
                ((symbol-function 'kuro--core-render-pipeline-with-timing) (lambda () nil))
                ((symbol-function 'kuro--finalize-dirty-updates) #'ignore))
        (kuro--apply-dirty-updates)
        (should (= core-calls 0))))))

;;; Group 24c: kuro--apply-dirty-updates — delegates result to kuro--finalize-dirty-updates

(ert-deftest kuro-renderer-pipeline-apply-dirty-updates-passes-result-to-finalize ()
  "kuro--apply-dirty-updates passes the pipeline result to kuro--finalize-dirty-updates."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((finalize-arg :unset)
          (fake-updates '(a b c))
          (kuro-debug-perf nil))
      (cl-letf (((symbol-function 'kuro--core-render-pipeline)
                 (lambda () fake-updates))
                ((symbol-function 'kuro--finalize-dirty-updates)
                 (lambda (u) (setq finalize-arg u))))
        (kuro--apply-dirty-updates)
        (should (equal finalize-arg fake-updates))))))

(ert-deftest kuro-renderer-pipeline-apply-dirty-updates-passes-nil-to-finalize ()
  "kuro--apply-dirty-updates passes nil to kuro--finalize-dirty-updates when pipeline returns nil."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((finalize-arg :unset)
          (kuro-debug-perf nil))
      (cl-letf (((symbol-function 'kuro--core-render-pipeline)
                 (lambda () nil))
                ((symbol-function 'kuro--finalize-dirty-updates)
                 (lambda (u) (setq finalize-arg u))))
        (kuro--apply-dirty-updates)
        (should (null finalize-arg))))))

(provide 'kuro-renderer-pipeline-ext-test)

;;; kuro-renderer-pipeline-ext-test.el ends here
