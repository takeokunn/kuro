;;; kuro-renderer-pipeline-test.el --- Unit tests for kuro-renderer.el pipeline functions  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-renderer.el pipeline and related functions.
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;; All FFI and stream functions are stubbed with cl-letf.
;;
;; Groups covered:
;;     Group 11b: kuro--apply-terminal-modes
;;     Group 11c: kuro--poll-cwd
;;     Group 11d: kuro--check-process-exit
;;     Group 11e: kuro--poll-prompt-mark-updates
;;     Group 12:  kuro--ring-pending-bell
;;     Group 13:  kuro--tick-blink-if-active
;;     Group 14:  kuro--poll-within-budget
;;     Group 15:  kuro--apply-dirty-lines
;;
;; Groups 16-21 (TUI mode, OOB rows, finalize-dirty, core pipeline,
;; binary FFI dispatch, resize) are in kuro-renderer-pipeline-ext3-test.el.
;; Groups 22-28 (frame coalescing, render-cycle, eviction, scroll suppression,
;; title sanitization) are in kuro-renderer-pipeline-ext-test.el.
;; Basic renderer tests (Groups 1-10b) are in kuro-renderer-test.el.
;; Color, face, and attribute decoding tests are in kuro-faces-test.el.
;; Overlay management tests are in kuro-overlays-test.el.
;; Binary FFI decoder tests are in kuro-binary-decoder-test.el.

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

;;; Group 11b: kuro--apply-terminal-modes

(ert-deftest kuro-renderer-pipeline-apply-terminal-modes-maps-all-fields ()
  "kuro--apply-terminal-modes assigns all 7 mode values to buffer-local vars."
  (kuro-renderer-pipeline-test--with-buffer
    (kuro--apply-terminal-modes '(t t 1003 t t t 8))
    (should (eq kuro--application-cursor-keys-mode t))
    (should (eq kuro--app-keypad-mode t))
    (should (= kuro--mouse-mode 1003))
    (should (eq kuro--mouse-sgr t))
    (should (eq kuro--mouse-pixel-mode t))
    (should (eq kuro--bracketed-paste-mode t))
    (should (= kuro--keyboard-flags 8))))

(ert-deftest kuro-renderer-pipeline-apply-terminal-modes-nil-kbf-defaults-to-zero ()
  "kuro--apply-terminal-modes defaults keyboard-flags to 0 when 7th element is nil."
  (kuro-renderer-pipeline-test--with-buffer
    (kuro--apply-terminal-modes '(nil nil 0 nil nil nil nil))
    (should (= kuro--keyboard-flags 0))))

(ert-deftest kuro-renderer-pipeline-apply-terminal-modes-false-values ()
  "kuro--apply-terminal-modes correctly sets all fields to nil/false."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--application-cursor-keys-mode t
          kuro--mouse-mode 1003)
    (kuro--apply-terminal-modes '(nil nil 0 nil nil nil 0))
    (should-not kuro--application-cursor-keys-mode)
    (should (= kuro--mouse-mode 0))))

;;; Group 11c: kuro--poll-cwd

(ert-deftest kuro-renderer-pipeline-poll-cwd-updates-default-directory ()
  "kuro--poll-cwd sets default-directory from OSC 7."
  (kuro-renderer-pipeline-test--with-buffer
    (cl-letf (((symbol-function 'kuro--get-cwd) (lambda () "/tmp/test")))
      (kuro--poll-cwd)
      (should (equal default-directory "/tmp/test/")))))

(ert-deftest kuro-renderer-pipeline-poll-cwd-noop-on-nil ()
  "kuro--poll-cwd does not modify default-directory when FFI returns nil."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((dir-before default-directory))
      (cl-letf (((symbol-function 'kuro--get-cwd) (lambda () nil)))
        (kuro--poll-cwd)
        (should (equal default-directory dir-before))))))

(ert-deftest kuro-renderer-pipeline-poll-cwd-noop-on-empty-string ()
  "kuro--poll-cwd does not modify default-directory when FFI returns \"\"."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((dir-before default-directory))
      (cl-letf (((symbol-function 'kuro--get-cwd) (lambda () "")))
        (kuro--poll-cwd)
        (should (equal default-directory dir-before))))))

;;; Group 11d: kuro--check-process-exit

(ert-deftest kuro-renderer-pipeline-check-process-exit-kills-when-dead ()
  "kuro--check-process-exit calls kuro-kill when process is dead and kill-on-exit is set."
  (kuro-renderer-pipeline-test--with-buffer
    (setq-local kuro-kill-buffer-on-exit t)
    (let ((kill-called nil))
      (cl-letf (((symbol-function 'kuro--is-process-alive) (lambda () nil))
                ((symbol-function 'kuro-kill)              (lambda () (setq kill-called t))))
        (kuro--check-process-exit)
        (should kill-called)))))

(ert-deftest kuro-renderer-pipeline-check-process-exit-noop-when-alive ()
  "kuro--check-process-exit does not call kuro-kill when process is alive."
  (kuro-renderer-pipeline-test--with-buffer
    (setq-local kuro-kill-buffer-on-exit t)
    (let ((kill-called nil))
      (cl-letf (((symbol-function 'kuro--is-process-alive) (lambda () t))
                ((symbol-function 'kuro-kill)              (lambda () (setq kill-called t))))
        (kuro--check-process-exit)
        (should-not kill-called)))))

(ert-deftest kuro-renderer-pipeline-check-process-exit-noop-when-kill-disabled ()
  "kuro--check-process-exit does not call kuro-kill when kill-on-exit is nil."
  (kuro-renderer-pipeline-test--with-buffer
    (setq-local kuro-kill-buffer-on-exit nil)
    (let ((kill-called nil))
      (cl-letf (((symbol-function 'kuro--is-process-alive) (lambda () nil))
                ((symbol-function 'kuro-kill)              (lambda () (setq kill-called t))))
        (kuro--check-process-exit)
        (should-not kill-called)))))

;;; Group 11e: kuro--poll-prompt-mark-updates

(ert-deftest kuro-renderer-pipeline-poll-prompt-mark-updates-merges-marks ()
  "kuro--poll-prompt-mark-updates calls kuro--update-prompt-positions with marks."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--prompt-positions nil)
    (let ((update-called-with nil))
      (cl-letf (((symbol-function 'kuro--poll-prompt-marks)
                 (lambda () '(("prompt-start" 5 0 nil nil nil nil))))
                ((symbol-function 'kuro--update-prompt-positions)
                 (lambda (marks positions max)
                   (setq update-called-with (list marks positions max))
                   positions)))
        (kuro--poll-prompt-mark-updates)
        (should (equal (car update-called-with) '(("prompt-start" 5 0 nil nil nil nil))))))))

(ert-deftest kuro-renderer-pipeline-poll-prompt-mark-updates-noop-on-nil ()
  "kuro--poll-prompt-mark-updates does nothing when FFI returns nil."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((update-called nil))
      (cl-letf (((symbol-function 'kuro--poll-prompt-marks) (lambda () nil))
                ((symbol-function 'kuro--update-prompt-positions)
                 (lambda (_m _p _mx) (setq update-called t) nil)))
        (kuro--poll-prompt-mark-updates)
        (should-not update-called)))))

;;; Group 12: kuro--ring-pending-bell

(ert-deftest kuro-renderer-pipeline-ring-pending-bell-rings-when-pending ()
  "kuro--ring-pending-bell calls ding when a bell event is pending.
`kuro--call' is a macro that checks `kuro--initialized' then calls
`kuro-core-take-bell-pending'; stub the FFI function directly."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((ding-called nil)
          (kuro--session-id 1))
      (cl-letf (((symbol-function 'kuro-core-take-bell-pending)
                 (lambda (_sid) t))
                ((symbol-function 'ding)
                 (lambda () (setq ding-called t))))
        (kuro--ring-pending-bell)
        (should ding-called)))))

(ert-deftest kuro-renderer-pipeline-ring-pending-bell-silent-when-no-bell ()
  "kuro--ring-pending-bell does not call ding when no bell is pending."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((ding-called nil)
          (kuro--session-id 1))
      (cl-letf (((symbol-function 'kuro-core-take-bell-pending)
                 (lambda (_sid) nil))
                ((symbol-function 'ding)
                 (lambda () (setq ding-called t))))
        (kuro--ring-pending-bell)
        (should-not ding-called)))))

;;; Group 13: kuro--tick-blink-if-active

(ert-deftest kuro-renderer-pipeline-tick-blink-calls-tick-when-overlays ()
  "kuro--tick-blink-if-active calls kuro--tick-blink-overlays when overlays exist."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((tick-called nil))
      (setq kuro--blink-overlays (list (make-overlay 1 1)))
      (cl-letf (((symbol-function 'kuro--tick-blink-overlays)
                 (lambda () (setq tick-called t))))
        (kuro--tick-blink-if-active)
        (should tick-called)))))

(ert-deftest kuro-renderer-pipeline-tick-blink-noop-when-no-overlays ()
  "kuro--tick-blink-if-active is a no-op when kuro--blink-overlays is nil."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--blink-overlays nil)
    (let ((tick-called nil))
      (cl-letf (((symbol-function 'kuro--tick-blink-overlays)
                 (lambda () (setq tick-called t))))
        (kuro--tick-blink-if-active)
        (should-not tick-called)))))

;;; Group 14: kuro--poll-within-budget

(ert-deftest kuro-renderer-pipeline-poll-within-budget-calls-poll-when-under-budget ()
  "kuro--poll-within-budget calls kuro--poll-terminal-modes when under budget."
  (kuro-renderer-pipeline-test--with-buffer
    (setq-local kuro-frame-rate 30)
    (let ((poll-called nil))
      (cl-letf (((symbol-function 'kuro--poll-terminal-modes)
                 (lambda () (setq poll-called t)))
                ((symbol-function 'kuro--is-process-alive)
                 (lambda () t)))
        ;; Use a frame-start well in the past so elapsed time > budget
        ;; Actually for under-budget: use float-time directly (near zero elapsed)
        (kuro--poll-within-budget (float-time))
        (should poll-called)))))

(ert-deftest kuro-renderer-pipeline-poll-within-budget-checks-exit-when-over-budget ()
  "kuro--poll-within-budget checks process-alive when over budget."
  (kuro-renderer-pipeline-test--with-buffer
    (setq-local kuro-frame-rate 30
                kuro-kill-buffer-on-exit t)
    (let ((is-alive-called nil))
      (cl-letf (((symbol-function 'kuro--poll-terminal-modes)
                 (lambda () (error "should not be called over-budget")))
                ((symbol-function 'kuro--is-process-alive)
                 (lambda () (setq is-alive-called t) t)))
        ;; Pass a frame-start 10 seconds ago — definitely over budget
        (kuro--poll-within-budget (- (float-time) 10.0))
        (should is-alive-called)))))

;;; Group 15: kuro--apply-dirty-lines

(ert-deftest kuro-renderer-pipeline-apply-dirty-lines-calls-update-for-each-row ()
  "kuro--apply-dirty-lines calls kuro--update-line-full for each update entry."
  (kuro-renderer-pipeline-test--with-buffer
    (insert "row0\nrow1\n")
    (let ((updated-rows nil))
      (cl-letf (((symbol-function 'kuro--update-line-full)
                 (lambda (row _text _faces _c2b)
                   (push row updated-rows))))
        (kuro--apply-dirty-lines
         (vector (vector 0 "new0" nil nil)
                 (vector 1 "new1" nil nil)))
        (should (= (length updated-rows) 2))
        (should (member 0 updated-rows))
        (should (member 1 updated-rows))))))

(ert-deftest kuro-renderer-pipeline-apply-dirty-lines-swallows-per-row-errors ()
  "kuro--apply-dirty-lines catches frame-level errors without propagating.
The condition-case is hoisted outside the loop for performance (avoids
installing a C-level setjmp target per-iteration).  When an error occurs
on row 0, the loop aborts and remaining rows are not attempted — this is
acceptable because `kuro--update-line-full' never signals in production."
  (kuro-renderer-pipeline-test--with-buffer
    (insert "row0\nrow1\n")
    (let ((rows-attempted nil))
      (cl-letf (((symbol-function 'kuro--update-line-full)
                 (lambda (row _text _faces _c2b)
                   (push row rows-attempted)
                   (when (= row 0)
                     (error "simulated row error")))))
        ;; Error is caught inside kuro--apply-dirty-lines; nothing propagates.
        (kuro--apply-dirty-lines
         (vector (vector 0 "bad" nil nil)
                 (vector 1 "ok" nil nil)))
        ;; Only row 0 was attempted; frame-level abort skipped row 1.
        (should (= (length rows-attempted) 1))
        (should (equal rows-attempted '(0)))))))

(ert-deftest kuro-renderer-pipeline-apply-dirty-lines-empty-updates-is-noop ()
  "kuro--apply-dirty-lines with an empty list is a no-op."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((called nil))
      (cl-letf (((symbol-function 'kuro--update-line-full)
                 (lambda (&rest _) (setq called t))))
        (kuro--apply-dirty-lines nil)
        (should-not called)))))

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

(provide 'kuro-renderer-pipeline-test)
;;; kuro-renderer-pipeline-test.el ends here
