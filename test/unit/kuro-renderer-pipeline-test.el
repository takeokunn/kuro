;;; kuro-renderer-pipeline-test.el --- Unit tests for kuro-renderer.el pipeline functions  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-renderer.el pipeline, resize, coalescing, and render-cycle
;; functions.  Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;; All FFI and stream functions are stubbed with cl-letf.
;;
;; Groups covered:
;;     Group 11:  col-to-buf nil handling (kuro--apply-terminal-modes, poll-cwd, etc.)
;;     Group 11b: kuro--apply-terminal-modes
;;     Group 11c: kuro--poll-cwd
;;     Group 11d: kuro--check-process-exit
;;     Group 11e: kuro--poll-prompt-mark-updates
;;     Group 12:  kuro--ring-pending-bell
;;     Group 13:  kuro--tick-blink-if-active
;;     Group 14:  kuro--poll-within-budget
;;     Group 15:  kuro--apply-dirty-lines
;;     Group 16:  kuro--enter-tui-mode / kuro--exit-tui-mode
;;     Group 17:  kuro--collect-out-of-bounds-rows / kuro--collect-empty-col-to-buf-rows
;;     Group 18:  kuro--finalize-dirty-updates
;;     Group 19:  kuro--core-render-pipeline
;;     Group 20:  kuro--core-render-pipeline binary FFI dispatch
;;     Group 21:  kuro--handle-pending-resize
;;     Group 22:  kuro--with-frame-coalescing
;;     Group 22b: kuro--core-render-pipeline-with-timing
;;     Group 22c: kuro--poll-updates-binary error handling
;;     Group 23:  kuro--render-cycle stage-order
;;     Group 24a: kuro--apply-dirty-updates non-debug path
;;     Group 24b: kuro--apply-dirty-updates debug path (kuro-debug-perf non-nil)
;;     Group 24c: kuro--apply-dirty-updates delegates to kuro--finalize-dirty-updates
;;     Group 25:  kuro--switch-render-timer
;;
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
                 (lambda () '(("prompt-start" 5 0))))
                ((symbol-function 'kuro--update-prompt-positions)
                 (lambda (marks positions max)
                   (setq update-called-with (list marks positions max))
                   positions)))
        (kuro--poll-prompt-mark-updates)
        (should (equal (car update-called-with) '(("prompt-start" 5 0))))))))

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
         '((((0 . "new0") . nil) . nil)
           (((1 . "new1") . nil) . nil)))
        (should (= (length updated-rows) 2))
        (should (member 0 updated-rows))
        (should (member 1 updated-rows))))))

(ert-deftest kuro-renderer-pipeline-apply-dirty-lines-swallows-per-row-errors ()
  "kuro--apply-dirty-lines swallows per-row errors and continues."
  (kuro-renderer-pipeline-test--with-buffer
    (insert "row0\nrow1\n")
    (let ((rows-attempted nil))
      (cl-letf (((symbol-function 'kuro--update-line-full)
                 (lambda (row _text _faces _c2b)
                   (push row rows-attempted)
                   (when (= row 0)
                     (error "simulated row error")))))
        (kuro--apply-dirty-lines
         '((((0 . "bad") . nil) . nil)
           (((1 . "ok") . nil) . nil)))
        ;; Both rows should have been attempted despite error on row 0
        (should (= (length rows-attempted) 2))))))

(ert-deftest kuro-renderer-pipeline-apply-dirty-lines-empty-updates-is-noop ()
  "kuro--apply-dirty-lines with an empty list is a no-op."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((called nil))
      (cl-letf (((symbol-function 'kuro--update-line-full)
                 (lambda (&rest _) (setq called t))))
        (kuro--apply-dirty-lines nil)
        (should-not called)))))

;;; Group 16: kuro--enter-tui-mode / kuro--exit-tui-mode

(defmacro kuro-renderer-pipeline-test--with-tui-stubs (stop-var start-var switch-var &rest body)
  "Run BODY with TUI mode side-effect functions stubbed.
STOP-VAR, START-VAR, SWITCH-VAR capture whether the corresponding
functions were called (and at what rate for switch)."
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

(ert-deftest kuro-renderer-pipeline-enter-tui-mode-stops-idle-timer ()
  "kuro--enter-tui-mode stops the streaming idle timer."
  (kuro-renderer-pipeline-test--with-buffer
    (kuro-renderer-pipeline-test--with-tui-stubs stopped started switched
      (kuro--enter-tui-mode)
      (should stopped))))

(ert-deftest kuro-renderer-pipeline-enter-tui-mode-switches-to-tui-rate ()
  "kuro--enter-tui-mode switches the render timer to kuro-tui-frame-rate."
  (kuro-renderer-pipeline-test--with-buffer
    (kuro-renderer-pipeline-test--with-tui-stubs stopped started switched
      (kuro--enter-tui-mode)
      (should (= switched kuro-tui-frame-rate)))))

(ert-deftest kuro-renderer-pipeline-enter-tui-mode-sets-active-flag ()
  "kuro--enter-tui-mode sets kuro--tui-mode-active to t."
  (kuro-renderer-pipeline-test--with-buffer
    (kuro-renderer-pipeline-test--with-tui-stubs stopped started switched
      (kuro--enter-tui-mode)
      (should kuro--tui-mode-active))))

(ert-deftest kuro-renderer-pipeline-exit-tui-mode-switches-to-normal-rate ()
  "kuro--exit-tui-mode switches the render timer back to kuro-frame-rate."
  (kuro-renderer-pipeline-test--with-buffer
    (kuro-renderer-pipeline-test--with-tui-stubs stopped started switched
      (kuro--exit-tui-mode)
      (should (= switched kuro-frame-rate)))))

(ert-deftest kuro-renderer-pipeline-exit-tui-mode-clears-active-flag ()
  "kuro--exit-tui-mode sets kuro--tui-mode-active to nil."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--tui-mode-active t)
    (kuro-renderer-pipeline-test--with-tui-stubs stopped started switched
      (kuro--exit-tui-mode)
      (should-not kuro--tui-mode-active))))

(ert-deftest kuro-renderer-pipeline-exit-tui-mode-restarts-idle-timer ()
  "kuro--exit-tui-mode restarts the streaming idle timer."
  (kuro-renderer-pipeline-test--with-buffer
    (kuro-renderer-pipeline-test--with-tui-stubs stopped started switched
      (kuro--exit-tui-mode)
      (should started))))

;;; Group 17: kuro--collect-out-of-bounds-rows / kuro--collect-empty-col-to-buf-rows

(ert-deftest kuro-renderer-pipeline-collect-oob-rows-returns-rows-past-last-rows ()
  "kuro--collect-out-of-bounds-rows returns keys >= kuro--last-rows."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--last-rows 10)
    (puthash 5  [0 1] kuro--col-to-buf-map)  ; in bounds
    (puthash 10 [0 1] kuro--col-to-buf-map)  ; out of bounds (== last-rows)
    (puthash 15 [0 1] kuro--col-to-buf-map)  ; out of bounds (> last-rows)
    (let ((stale (kuro--collect-out-of-bounds-rows)))
      (should (= (length stale) 2))
      (should (member 10 stale))
      (should (member 15 stale))
      (should-not (member 5 stale)))))

(ert-deftest kuro-renderer-pipeline-collect-oob-rows-empty-when-all-in-bounds ()
  "kuro--collect-out-of-bounds-rows returns nil when all keys are in bounds."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--last-rows 24)
    (puthash 0 [0] kuro--col-to-buf-map)
    (puthash 23 [0] kuro--col-to-buf-map)
    (should (null (kuro--collect-out-of-bounds-rows)))))

(ert-deftest kuro-renderer-pipeline-collect-empty-c2b-rows-finds-cjk-to-ascii ()
  "kuro--collect-empty-col-to-buf-rows finds rows with empty [] vectors."
  (let* ((empty-update  '((( 3 . "abc") . nil) . []))   ; row 3, empty vector
         (normal-update '((( 7 . "xyz") . nil) . [0 1])) ; row 7, non-empty
         (stale (kuro--collect-empty-col-to-buf-rows (list empty-update normal-update))))
    (should (= (length stale) 1))
    (should (member 3 stale))
    (should-not (member 7 stale))))

(ert-deftest kuro-renderer-pipeline-collect-empty-c2b-rows-nil-col-to-buf-ignored ()
  "kuro--collect-empty-col-to-buf-rows ignores updates with nil (not vector) col-to-buf."
  (let* ((nil-update '((( 2 . "text") . nil) . nil))
         (stale (kuro--collect-empty-col-to-buf-rows (list nil-update))))
    (should (null stale))))

;;; Group 18: kuro--finalize-dirty-updates

(ert-deftest kuro-renderer-pipeline-finalize-dirty-updates-records-count ()
  "kuro--finalize-dirty-updates sets kuro--last-dirty-count to (length updates)."
  (kuro-renderer-pipeline-test--with-buffer
    (cl-letf (((symbol-function 'kuro--evict-stale-col-to-buf-entries) #'ignore))
      (kuro--finalize-dirty-updates '(a b c))
      (should (= kuro--last-dirty-count 3)))))

(ert-deftest kuro-renderer-pipeline-finalize-dirty-updates-zero-on-nil ()
  "kuro--finalize-dirty-updates sets kuro--last-dirty-count to 0 for nil."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--last-dirty-count 99)
    (cl-letf (((symbol-function 'kuro--evict-stale-col-to-buf-entries) #'ignore))
      (kuro--finalize-dirty-updates nil)
      (should (= kuro--last-dirty-count 0)))))

(ert-deftest kuro-renderer-pipeline-finalize-dirty-updates-calls-evict ()
  "kuro--finalize-dirty-updates calls kuro--evict-stale-col-to-buf-entries."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((evict-called-with :unset))
      (cl-letf (((symbol-function 'kuro--evict-stale-col-to-buf-entries)
                 (lambda (u) (setq evict-called-with u))))
        (kuro--finalize-dirty-updates '(x y))
        (should (equal evict-called-with '(x y)))))))

;;; Group 19: kuro--core-render-pipeline

(ert-deftest kuro-renderer-pipeline-core-pipeline-returns-updates ()
  "kuro--core-render-pipeline returns the list from kuro--poll-updates-with-faces."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((fake-updates '((((0 . "text") . nil) . nil))))
      (cl-letf (((symbol-function 'kuro--apply-title-update)      #'ignore)
                ((symbol-function 'kuro--process-scroll-events)   #'ignore)
                ((symbol-function 'kuro--poll-updates-with-faces) (lambda () fake-updates))
                ((symbol-function 'kuro--apply-dirty-lines)       #'ignore)
                ((symbol-function 'kuro--update-cursor)           #'ignore))
        (should (equal (kuro--core-render-pipeline) fake-updates))))))

(ert-deftest kuro-renderer-pipeline-core-pipeline-returns-nil-when-no-updates ()
  "kuro--core-render-pipeline returns nil when poll returns nil."
  (kuro-renderer-pipeline-test--with-buffer
    (cl-letf (((symbol-function 'kuro--apply-title-update)      #'ignore)
              ((symbol-function 'kuro--process-scroll-events)   #'ignore)
              ((symbol-function 'kuro--poll-updates-with-faces) (lambda () nil))
              ((symbol-function 'kuro--apply-dirty-lines)       #'ignore)
              ((symbol-function 'kuro--update-cursor)           #'ignore))
      (should-not (kuro--core-render-pipeline)))))

(ert-deftest kuro-renderer-pipeline-core-pipeline-calls-all-steps ()
  "kuro--core-render-pipeline calls all 5 pipeline steps in order."
  (kuro-renderer-pipeline-test--with-buffer
    (let (log)
      (cl-letf (((symbol-function 'kuro--apply-title-update)      (lambda () (push 'title log)))
                ((symbol-function 'kuro--process-scroll-events)   (lambda () (push 'scroll log)))
                ((symbol-function 'kuro--poll-updates-with-faces) (lambda () (push 'poll log) '(x)))
                ((symbol-function 'kuro--apply-dirty-lines)       (lambda (_) (push 'dirty log)))
                ((symbol-function 'kuro--update-cursor)           (lambda () (push 'cursor log))))
        (kuro--core-render-pipeline)
        (should (equal (nreverse log) '(title scroll poll dirty cursor)))))))

;;; Group 20: kuro--core-render-pipeline binary FFI dispatch
;; Full binary decoder unit tests are in kuro-binary-decoder-test.el.
;; This group retains only the renderer-level dispatch test.

(ert-deftest kuro-renderer-pipeline-core-pipeline-dispatches-binary-when-flag-set ()
  "kuro--core-render-pipeline calls kuro--poll-updates-binary when kuro-use-binary-ffi is t."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((binary-called nil)
          (faces-called nil)
          (kuro-use-binary-ffi t))
      (cl-letf (((symbol-function 'kuro--apply-title-update)    #'ignore)
                ((symbol-function 'kuro--process-scroll-events) #'ignore)
                ((symbol-function 'kuro--poll-updates-binary)
                 (lambda () (setq binary-called t) nil))
                ((symbol-function 'kuro--poll-updates-with-faces)
                 (lambda () (setq faces-called t) (error "should not be called")))
                ((symbol-function 'kuro--apply-dirty-lines)     #'ignore)
                ((symbol-function 'kuro--update-cursor)         #'ignore))
        (kuro--core-render-pipeline)
        (should binary-called)
        (should-not faces-called)))))

;;; Group 21: kuro--handle-pending-resize

(defmacro kuro-renderer-pipeline-resize-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer with state for resize tests.
Stubs `kuro--reset-cursor-cache' to avoid missing-variable errors."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (inhibit-modification-hooks t)
           (kuro--initialized t)
           (kuro--resize-pending nil)
           (kuro--last-rows 24)
           (kuro--last-cols 80)
           (kuro--col-to-buf-map (make-hash-table :test 'eql))
           kuro--last-cursor-row
           kuro--last-cursor-col
           kuro--last-cursor-visible
           kuro--last-cursor-shape)
       ;; Insert the default 24-line buffer content expected by most tests.
       (dotimes (_ 24) (insert "\n"))
       ,@body)))

(ert-deftest test-kuro-pipeline-handle-pending-resize-noop-when-nil ()
  "kuro--handle-pending-resize does nothing when kuro--resize-pending is nil."
  (kuro-renderer-pipeline-resize-test--with-buffer
    (let ((resize-called nil))
      (cl-letf (((symbol-function 'kuro--resize)
                 (lambda (_r _c) (setq resize-called t))))
        (kuro--handle-pending-resize)
        (should-not resize-called)
        (should (= kuro--last-rows 24))
        (should (= kuro--last-cols 80))))))

(ert-deftest test-kuro-pipeline-handle-pending-resize-calls-resize ()
  "kuro--handle-pending-resize calls kuro--resize with (new-rows new-cols)."
  (kuro-renderer-pipeline-resize-test--with-buffer
    (setq kuro--resize-pending '(30 . 100))
    (let ((resize-args nil))
      (cl-letf (((symbol-function 'kuro--resize)
                 (lambda (r c) (setq resize-args (list r c)))))
        (kuro--handle-pending-resize)
        (should (equal resize-args '(30 100)))))))

(ert-deftest test-kuro-pipeline-handle-pending-resize-clears-pending ()
  "After kuro--handle-pending-resize runs, kuro--resize-pending is nil."
  (kuro-renderer-pipeline-resize-test--with-buffer
    (setq kuro--resize-pending '(24 . 80))
    (cl-letf (((symbol-function 'kuro--resize) #'ignore))
      (kuro--handle-pending-resize)
      (should-not kuro--resize-pending))))

(ert-deftest test-kuro-pipeline-handle-pending-resize-updates-last-rows-cols ()
  "kuro--handle-pending-resize updates kuro--last-rows and kuro--last-cols."
  (kuro-renderer-pipeline-resize-test--with-buffer
    (setq kuro--resize-pending '(30 . 120))
    (cl-letf (((symbol-function 'kuro--resize) #'ignore))
      (kuro--handle-pending-resize)
      (should (= kuro--last-rows 30))
      (should (= kuro--last-cols 120)))))

(ert-deftest test-kuro-pipeline-handle-pending-resize-clears-col-to-buf-map ()
  "kuro--handle-pending-resize clears kuro--col-to-buf-map via clrhash."
  (kuro-renderer-pipeline-resize-test--with-buffer
    (puthash 0 [0 1 2] kuro--col-to-buf-map)
    (puthash 5 [0 2 4] kuro--col-to-buf-map)
    (setq kuro--resize-pending '(24 . 80))
    (cl-letf (((symbol-function 'kuro--resize) #'ignore))
      (kuro--handle-pending-resize)
      (should (= (hash-table-count kuro--col-to-buf-map) 0)))))

(ert-deftest test-kuro-pipeline-handle-pending-resize-skips-when-not-initialized ()
  "kuro--handle-pending-resize skips kuro--resize when kuro--initialized is nil."
  (kuro-renderer-pipeline-resize-test--with-buffer
    (setq kuro--initialized nil
          kuro--resize-pending '(24 . 80))
    (let ((resize-called nil))
      (cl-letf (((symbol-function 'kuro--resize)
                 (lambda (_r _c) (setq resize-called t))))
        (kuro--handle-pending-resize)
        (should-not resize-called)
        ;; pending is drained even when not initialized
        (should-not kuro--resize-pending)))))

(ert-deftest test-kuro-pipeline-handle-pending-resize-skips-zero-rows ()
  "kuro--handle-pending-resize does not call kuro--resize for (0 . 80)."
  (kuro-renderer-pipeline-resize-test--with-buffer
    (setq kuro--resize-pending '(0 . 80))
    (let ((resize-called nil))
      (cl-letf (((symbol-function 'kuro--resize)
                 (lambda (_r _c) (setq resize-called t))))
        (kuro--handle-pending-resize)
        (should-not resize-called)))))

(ert-deftest test-kuro-pipeline-handle-pending-resize-skips-zero-cols ()
  "kuro--handle-pending-resize does not call kuro--resize for (24 . 0)."
  (kuro-renderer-pipeline-resize-test--with-buffer
    (setq kuro--resize-pending '(24 . 0))
    (let ((resize-called nil))
      (cl-letf (((symbol-function 'kuro--resize)
                 (lambda (_r _c) (setq resize-called t))))
        (kuro--handle-pending-resize)
        (should-not resize-called)))))

(ert-deftest test-kuro-pipeline-handle-pending-resize-adds-buffer-lines ()
  "Resizing from 10 to 15 rows inserts 5 newlines at end of buffer."
  (with-temp-buffer
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t)
          (kuro--initialized t)
          (kuro--resize-pending '(15 . 80))
          (kuro--last-rows 10)
          (kuro--last-cols 80)
          (kuro--col-to-buf-map (make-hash-table :test 'eql))
          kuro--last-cursor-row kuro--last-cursor-col
          kuro--last-cursor-visible kuro--last-cursor-shape)
      (dotimes (_ 10) (insert "\n"))
      (should (= (1- (line-number-at-pos (point-max))) 10))
      (cl-letf (((symbol-function 'kuro--resize) #'ignore))
        (kuro--handle-pending-resize))
      (should (= (1- (line-number-at-pos (point-max))) 15)))))

(ert-deftest test-kuro-pipeline-handle-pending-resize-removes-buffer-lines ()
  "Resizing from 20 to 15 rows deletes 5 lines from end of buffer."
  (with-temp-buffer
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t)
          (kuro--initialized t)
          (kuro--resize-pending '(15 . 80))
          (kuro--last-rows 20)
          (kuro--last-cols 80)
          (kuro--col-to-buf-map (make-hash-table :test 'eql))
          kuro--last-cursor-row kuro--last-cursor-col
          kuro--last-cursor-visible kuro--last-cursor-shape)
      (dotimes (_ 20) (insert "\n"))
      (should (= (1- (line-number-at-pos (point-max))) 20))
      (cl-letf (((symbol-function 'kuro--resize) #'ignore))
        (kuro--handle-pending-resize))
      (should (= (1- (line-number-at-pos (point-max))) 15)))))

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

(provide 'kuro-renderer-pipeline-test)

;;; kuro-renderer-pipeline-test.el ends here
