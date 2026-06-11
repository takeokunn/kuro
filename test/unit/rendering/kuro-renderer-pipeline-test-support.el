;;; kuro-renderer-pipeline-test-support.el --- Shared helpers for pipeline tests  -*- lexical-binding: t; -*-

;;; Commentary:
;; Shared test helpers for kuro-renderer-pipeline.el unit tests.
;; Required by both kuro-renderer-pipeline-test.el (Groups 11b-24c)
;; and kuro-renderer-pipeline-ext3-test.el (Groups 16-28).

;;; Code:

(require 'cl-lib)
(require 'kuro-renderer)

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

(defmacro kuro-renderer-coalesce-test--with-buffer (&rest body)
  "Run BODY with frame-coalescing state initialized in a temporary buffer."
  `(with-temp-buffer
     (let ((kuro--initialized t)
           (kuro--last-render-time 0.0)
           (kuro-frame-rate 120)
           (kuro-tui-frame-rate 30)
           (kuro--tui-mode-active nil))
       ,@body)))

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

(defmacro kuro-renderer-pipeline-test--with-tui-stubs (stop-var start-var switch-var &rest body)
  "Run BODY with TUI mode side-effect functions stubbed."
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
  "Run BODY in a temporary buffer with state for resize tests."
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
       ,@body)))

(provide 'kuro-renderer-pipeline-test-support)

;;; kuro-renderer-pipeline-test-support.el ends here
