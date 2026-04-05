;;; kuro-renderer-pipeline-ext3-test.el --- Unit tests for kuro-renderer.el pipeline (part 2)  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-renderer.el pipeline, TUI mode, resize, and related functions.
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;; All FFI and stream functions are stubbed with cl-letf.
;;
;; Groups covered:
;;     Group 16:  kuro--enter-tui-mode / kuro--exit-tui-mode
;;     Group 18:  kuro--finalize-dirty-updates
;;     Group 19:  kuro--core-render-pipeline
;;     Group 20:  kuro--core-render-pipeline binary FFI dispatch
;;     Group 21:  kuro--handle-pending-resize
;;
;; Groups 11b–15 (terminal modes, poll-cwd, process-exit, prompt marks,
;; bell, blink, budget, dirty-lines) are in kuro-renderer-pipeline-test.el.
;; Groups 22+ (frame coalescing, render-cycle, eviction, scroll suppression,
;; title sanitization) are in kuro-renderer-pipeline-ext-test.el.
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

;;; Group 16: kuro--enter-tui-mode / kuro--exit-tui-mode

(ert-deftest kuro-renderer-pipeline-ext3-enter-tui-mode-stops-idle-timer ()
  "kuro--enter-tui-mode stops the streaming idle timer."
  (kuro-renderer-pipeline-test--with-buffer
    (kuro-renderer-pipeline-test--with-tui-stubs stopped started switched
      (kuro--enter-tui-mode)
      (should stopped))))

(ert-deftest kuro-renderer-pipeline-ext3-enter-tui-mode-switches-to-tui-rate ()
  "kuro--enter-tui-mode switches the render timer to kuro-tui-frame-rate."
  (kuro-renderer-pipeline-test--with-buffer
    (kuro-renderer-pipeline-test--with-tui-stubs stopped started switched
      (kuro--enter-tui-mode)
      (should (= switched kuro-tui-frame-rate)))))

(ert-deftest kuro-renderer-pipeline-ext3-enter-tui-mode-sets-active-flag ()
  "kuro--enter-tui-mode sets kuro--tui-mode-active to t."
  (kuro-renderer-pipeline-test--with-buffer
    (kuro-renderer-pipeline-test--with-tui-stubs stopped started switched
      (kuro--enter-tui-mode)
      (should kuro--tui-mode-active))))

(ert-deftest kuro-renderer-pipeline-ext3-exit-tui-mode-switches-to-normal-rate ()
  "kuro--exit-tui-mode switches the render timer back to kuro-frame-rate."
  (kuro-renderer-pipeline-test--with-buffer
    (kuro-renderer-pipeline-test--with-tui-stubs stopped started switched
      (kuro--exit-tui-mode)
      (should (= switched kuro-frame-rate)))))

(ert-deftest kuro-renderer-pipeline-ext3-exit-tui-mode-clears-active-flag ()
  "kuro--exit-tui-mode sets kuro--tui-mode-active to nil."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--tui-mode-active t)
    (kuro-renderer-pipeline-test--with-tui-stubs stopped started switched
      (kuro--exit-tui-mode)
      (should-not kuro--tui-mode-active))))

(ert-deftest kuro-renderer-pipeline-ext3-exit-tui-mode-restarts-idle-timer ()
  "kuro--exit-tui-mode restarts the streaming idle timer."
  (kuro-renderer-pipeline-test--with-buffer
    (kuro-renderer-pipeline-test--with-tui-stubs stopped started switched
      (kuro--exit-tui-mode)
      (should started))))

;;; Group 18: kuro--finalize-dirty-updates

(ert-deftest kuro-renderer-pipeline-ext3-finalize-dirty-updates-records-count ()
  "kuro--finalize-dirty-updates sets kuro--last-dirty-count to (length updates)."
  (kuro-renderer-pipeline-test--with-buffer
    (cl-letf (((symbol-function 'kuro--evict-stale-col-to-buf-entries) #'ignore))
      (kuro--finalize-dirty-updates '(a b c))
      (should (= kuro--last-dirty-count 3)))))

(ert-deftest kuro-renderer-pipeline-ext3-finalize-dirty-updates-zero-on-nil ()
  "kuro--finalize-dirty-updates sets kuro--last-dirty-count to 0 for nil."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--last-dirty-count 99)
    (cl-letf (((symbol-function 'kuro--evict-stale-col-to-buf-entries) #'ignore))
      (kuro--finalize-dirty-updates nil)
      (should (= kuro--last-dirty-count 0)))))

(ert-deftest kuro-renderer-pipeline-ext3-finalize-dirty-updates-calls-evict ()
  "kuro--finalize-dirty-updates calls kuro--evict-stale-col-to-buf-entries."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((evict-called-with :unset))
      (cl-letf (((symbol-function 'kuro--evict-stale-col-to-buf-entries)
                 (lambda (u) (setq evict-called-with u))))
        (kuro--finalize-dirty-updates '(x y))
        (should (equal evict-called-with '(x y)))))))

;;; Group 19: kuro--core-render-pipeline

(ert-deftest kuro-renderer-pipeline-ext3-core-pipeline-returns-updates ()
  "kuro--core-render-pipeline returns the list from kuro--poll-updates-with-faces."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((fake-updates '((((0 . "text") . nil) . nil)))
          (kuro-use-binary-ffi nil))
      (cl-letf (((symbol-function 'kuro--apply-title-update)      #'ignore)
                ((symbol-function 'kuro--process-scroll-events)   #'ignore)
                ((symbol-function 'kuro--poll-updates-with-faces) (lambda () fake-updates))
                ((symbol-function 'kuro--apply-dirty-lines)       #'ignore)
                ((symbol-function 'kuro--update-cursor)           #'ignore))
        (should (equal (kuro--core-render-pipeline) fake-updates))))))

(ert-deftest kuro-renderer-pipeline-ext3-core-pipeline-returns-nil-when-no-updates ()
  "kuro--core-render-pipeline returns nil when poll returns nil."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((kuro-use-binary-ffi nil))
      (cl-letf (((symbol-function 'kuro--apply-title-update)      #'ignore)
                ((symbol-function 'kuro--process-scroll-events)   #'ignore)
                ((symbol-function 'kuro--poll-updates-with-faces) (lambda () nil))
                ((symbol-function 'kuro--apply-dirty-lines)       #'ignore)
                ((symbol-function 'kuro--update-cursor)           #'ignore))
        (should-not (kuro--core-render-pipeline))))))

(ert-deftest kuro-renderer-pipeline-ext3-core-pipeline-calls-all-steps ()
  "kuro--core-render-pipeline calls all 5 pipeline steps in order."
  (kuro-renderer-pipeline-test--with-buffer
    (let (log
          (kuro-use-binary-ffi nil))
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

(ert-deftest kuro-renderer-pipeline-ext3-core-pipeline-dispatches-binary-when-flag-set ()
  "kuro--core-render-pipeline calls kuro--poll-updates-binary-optimised when kuro-use-binary-ffi is t."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((binary-called nil)
          (faces-called nil)
          (kuro-use-binary-ffi t))
      (cl-letf (((symbol-function 'kuro--apply-title-update)    #'ignore)
                ((symbol-function 'kuro--process-scroll-events) #'ignore)
                ((symbol-function 'kuro--poll-updates-binary-optimised)
                 (lambda (_session-id) (setq binary-called t) nil))
                ((symbol-function 'kuro--poll-updates-with-faces)
                 (lambda () (setq faces-called t) (error "should not be called")))
                ((symbol-function 'kuro--apply-dirty-lines)     #'ignore)
                ((symbol-function 'kuro--update-cursor)         #'ignore))
        (kuro--core-render-pipeline)
        (should binary-called)
        (should-not faces-called)))))

;;; Group 21: kuro--handle-pending-resize

(ert-deftest test-kuro-pipeline-ext3-handle-pending-resize-noop-when-nil ()
  "kuro--handle-pending-resize does nothing when kuro--resize-pending is nil."
  (kuro-renderer-pipeline-resize-test--with-buffer
    (let ((resize-called nil))
      (cl-letf (((symbol-function 'kuro--resize)
                 (lambda (_r _c) (setq resize-called t))))
        (kuro--handle-pending-resize)
        (should-not resize-called)
        (should (= kuro--last-rows 24))
        (should (= kuro--last-cols 80))))))

(ert-deftest test-kuro-pipeline-ext3-handle-pending-resize-calls-resize ()
  "kuro--handle-pending-resize calls kuro--resize with (new-rows new-cols)."
  (kuro-renderer-pipeline-resize-test--with-buffer
    (setq kuro--resize-pending '(30 . 100))
    (let ((resize-args nil))
      (cl-letf (((symbol-function 'kuro--resize)
                 (lambda (r c) (setq resize-args (list r c)))))
        (kuro--handle-pending-resize)
        (should (equal resize-args '(30 100)))))))

(ert-deftest test-kuro-pipeline-ext3-handle-pending-resize-clears-pending ()
  "After kuro--handle-pending-resize runs, kuro--resize-pending is nil."
  (kuro-renderer-pipeline-resize-test--with-buffer
    (setq kuro--resize-pending '(24 . 80))
    (cl-letf (((symbol-function 'kuro--resize) #'ignore))
      (kuro--handle-pending-resize)
      (should-not kuro--resize-pending))))

(ert-deftest test-kuro-pipeline-ext3-handle-pending-resize-updates-last-rows-cols ()
  "kuro--handle-pending-resize updates kuro--last-rows and kuro--last-cols."
  (kuro-renderer-pipeline-resize-test--with-buffer
    (setq kuro--resize-pending '(30 . 120))
    (cl-letf (((symbol-function 'kuro--resize) #'ignore))
      (kuro--handle-pending-resize)
      (should (= kuro--last-rows 30))
      (should (= kuro--last-cols 120)))))

(ert-deftest test-kuro-pipeline-ext3-handle-pending-resize-clears-col-to-buf-map ()
  "kuro--handle-pending-resize clears kuro--col-to-buf-map via clrhash."
  (kuro-renderer-pipeline-resize-test--with-buffer
    (puthash 0 [0 1 2] kuro--col-to-buf-map)
    (puthash 5 [0 2 4] kuro--col-to-buf-map)
    (setq kuro--resize-pending '(24 . 80))
    (cl-letf (((symbol-function 'kuro--resize) #'ignore))
      (kuro--handle-pending-resize)
      (should (= (hash-table-count kuro--col-to-buf-map) 0)))))

(ert-deftest test-kuro-pipeline-ext3-handle-pending-resize-skips-when-not-initialized ()
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

(ert-deftest test-kuro-pipeline-ext3-handle-pending-resize-skips-zero-rows ()
  "kuro--handle-pending-resize does not call kuro--resize for (0 . 80)."
  (kuro-renderer-pipeline-resize-test--with-buffer
    (setq kuro--resize-pending '(0 . 80))
    (let ((resize-called nil))
      (cl-letf (((symbol-function 'kuro--resize)
                 (lambda (_r _c) (setq resize-called t))))
        (kuro--handle-pending-resize)
        (should-not resize-called)))))

(ert-deftest test-kuro-pipeline-ext3-handle-pending-resize-skips-zero-cols ()
  "kuro--handle-pending-resize does not call kuro--resize for (24 . 0)."
  (kuro-renderer-pipeline-resize-test--with-buffer
    (setq kuro--resize-pending '(24 . 0))
    (let ((resize-called nil))
      (cl-letf (((symbol-function 'kuro--resize)
                 (lambda (_r _c) (setq resize-called t))))
        (kuro--handle-pending-resize)
        (should-not resize-called)))))

(ert-deftest test-kuro-pipeline-ext3-handle-pending-resize-adds-buffer-lines ()
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

(ert-deftest test-kuro-pipeline-ext3-handle-pending-resize-removes-buffer-lines ()
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

;;; Group 22: kuro--with-render-env macro

(ert-deftest kuro-renderer-pipeline-ext3-with-render-env-sets-gc-threshold ()
  "`kuro--with-render-env' binds gc-cons-threshold to kuro--render-gc-threshold."
  (let (captured)
    (kuro--with-render-env
      (setq captured gc-cons-threshold))
    (should (= captured kuro--render-gc-threshold))))

(ert-deftest kuro-renderer-pipeline-ext3-with-render-env-sets-gc-percentage ()
  "`kuro--with-render-env' binds gc-cons-percentage to kuro--render-gc-percentage."
  (let (captured)
    (kuro--with-render-env
      (setq captured gc-cons-percentage))
    (should (= captured kuro--render-gc-percentage))))

(ert-deftest kuro-renderer-pipeline-ext3-with-render-env-returns-body-value ()
  "`kuro--with-render-env' propagates the return value of BODY."
  (should (equal (kuro--with-render-env (+ 1 2)) 3)))

(ert-deftest kuro-renderer-pipeline-ext3-with-render-env-restores-gc-threshold ()
  "`kuro--with-render-env' restores gc-cons-threshold after body."
  (let ((before gc-cons-threshold))
    (kuro--with-render-env t)
    (should (= gc-cons-threshold before))))

(ert-deftest kuro-renderer-pipeline-ext3-with-render-env-executes-body ()
  "`kuro--with-render-env' evaluates all body forms as a progn."
  (let (a b)
    (kuro--with-render-env
      (setq a 1)
      (setq b 2))
    (should (= a 1))
    (should (= b 2))))

(provide 'kuro-renderer-pipeline-ext3-test)

;;; kuro-renderer-pipeline-ext3-test.el ends here
