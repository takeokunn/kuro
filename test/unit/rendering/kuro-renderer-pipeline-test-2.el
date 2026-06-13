;;; kuro-renderer-pipeline-test-2.el --- kuro-renderer pipeline tests (part 2) — Groups 22-23, constants  -*- lexical-binding: t; -*-

;;; Commentary:
;; Groups 22 (frame coalescing), 22b (timing pipeline), 23 (render-cycle),
;; and constant invariants for kuro-renderer-pipeline.el.
;; Helper macros are in kuro-renderer-pipeline-test-support.el.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-renderer-pipeline-test-support)

;;; Group 22: kuro--with-frame-coalescing

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

;;; Group 23: kuro--render-cycle

(ert-deftest kuro-renderer-render-cycle-calls-all-4-stages ()
  "kuro--render-cycle calls Stage 1 (resize), all Stage 2 substages, and Stage 3 (TUI timer)."
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
  "Stage 1 (kuro--handle-pending-resize) runs even when Stage 2 is coalesced."
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
  "Stage 3 (kuro--update-tui-streaming-timer) runs even when Stage 2 is coalesced."
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

;;; ── Constant invariants ───────────────────────────────────────────────────────

(ert-deftest kuro-renderer-pipeline-const-col-to-buf-evict-factor-positive ()
  "`kuro--col-to-buf-evict-factor' is a positive integer (triggers eviction at 2× last-rows)."
  (should (and (integerp kuro--col-to-buf-evict-factor)
               (> kuro--col-to-buf-evict-factor 0))))

(ert-deftest kuro-renderer-pipeline-const-frame-duration-ring-size-matches-ring ()
  "`kuro--frame-duration-ring-size' equals the length of `kuro--frame-duration-ring'."
  (should (= kuro--frame-duration-ring-size
             (length kuro--frame-duration-ring))))

(ert-deftest kuro-renderer-pipeline-const-title-sanitize-regexp-is-string ()
  "`kuro--title-sanitize-regexp' is a non-empty regexp string (Emacs regexps are strings)."
  (should (and (stringp kuro--title-sanitize-regexp)
               (> (length kuro--title-sanitize-regexp) 0))))

(provide 'kuro-renderer-pipeline-test-2)
;;; kuro-renderer-pipeline-test-2.el ends here
