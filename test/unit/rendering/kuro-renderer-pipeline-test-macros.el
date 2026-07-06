;;; kuro-renderer-pipeline-test-macros.el --- Pipeline test macros  -*- lexical-binding: t; -*-

;;; Commentary:
;; Macro helpers and test generators for kuro-renderer-pipeline.el unit tests.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'kuro-renderer)
(require 'kuro-renderer-pipeline-test-cases)

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

(defmacro kuro-renderer-pipeline-test--with-core-pipeline-timing-stubs (updates-var &rest body)
  "Run BODY with the core timing pipeline stubbed and return value captured in UPDATES-VAR."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'kuro--apply-title-update) #'ignore)
             ((symbol-function 'kuro--apply-decoded-scroll-shift) #'ignore)
             ((symbol-function 'kuro--poll-updates-with-faces)
              (lambda () ,updates-var))
             ((symbol-function 'kuro--apply-dirty-lines) #'ignore)
             ((symbol-function 'kuro--update-cursor) #'ignore)
             ((symbol-function 'kuro--perf-report) #'ignore))
     ,@body))

(defmacro kuro-renderer-pipeline-test--with-apply-dirty-updates-stubs
    (core-calls-var timing-calls-var finalize-var core-return timing-return &rest body)
  "Run BODY with dirty-update pipeline stubs and capture the call counts."
  (declare (indent 5))
  `(let ((,core-calls-var 0)
         (,timing-calls-var 0)
         (,finalize-var :unset))
     (cl-letf (((symbol-function 'kuro--core-render-pipeline)
                (lambda () (cl-incf ,core-calls-var) ,core-return))
               ((symbol-function 'kuro--core-render-pipeline-with-timing)
                (lambda () (cl-incf ,timing-calls-var) ,timing-return))
               ((symbol-function 'kuro--finalize-dirty-updates)
                (lambda (updates) (setq ,finalize-var updates))))
       ,@body)))

(defmacro kuro-renderer-pipeline-test--deftest-table-cases
    (test-name doc table pattern &rest body)
  "Define TEST-NAME by iterating TABLE with PATTERN over each entry."
  (declare (indent 4))
  `(ert-deftest ,test-name ()
     ,doc
     (dolist (entry ,table)
       (pcase-let ((,pattern entry))
         ,@body))))

(defmacro kuro-renderer-pipeline-test--with-render-cycle-stubs
    (resize-calls-var bell-calls-var dirty-calls-var poll-calls-var blink-calls-var tui-calls-var
     &rest body)
  "Run BODY with render-cycle stage counters bound and the stage functions stubbed."
  (declare (indent 6))
  `(let ((,resize-calls-var 0)
         (,bell-calls-var 0)
         (,dirty-calls-var 0)
         (,poll-calls-var 0)
         (,blink-calls-var 0)
         (,tui-calls-var 0))
     (cl-letf (((symbol-function 'kuro--handle-pending-resize)
                (lambda () (cl-incf ,resize-calls-var)))
               ((symbol-function 'kuro--ring-pending-bell)
                (lambda () (cl-incf ,bell-calls-var)))
               ((symbol-function 'kuro--apply-dirty-updates)
                (lambda () (cl-incf ,dirty-calls-var)))
               ((symbol-function 'kuro--poll-within-budget)
                (lambda (_fs) (cl-incf ,poll-calls-var)))
               ((symbol-function 'kuro--tick-blink-if-active)
                (lambda () (cl-incf ,blink-calls-var)))
               ((symbol-function 'kuro--update-tui-streaming-timer)
                (lambda () (cl-incf ,tui-calls-var))))
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

(defmacro kuro-renderer-pipeline-test--def-constant-invariant-case (case)
  "Define one constant invariant test from CASE."
  (pcase-let ((`(,name ,doc ,predicate) case))
    `(ert-deftest ,name ()
       ,doc
       (should ,predicate))))

(defmacro kuro-renderer-pipeline-test--deftest-constant-invariant-cases ()
  "Define constant invariant tests for `kuro-renderer-pipeline.el'."
  `(progn
     ,@(mapcar
        (lambda (case)
          `(kuro-renderer-pipeline-test--def-constant-invariant-case ,case))
        kuro-renderer-pipeline-test--constant-invariant-cases)))

(defmacro kuro-renderer-pipeline-test--def-resize-skips-zero-case (case)
  "Define one pending-resize zero-dimension test from CASE."
  (pcase-let ((`(,name ,pending-dims) case))
    `(ert-deftest ,name ()
       ,(format "`kuro--handle-pending-resize' skips resize for pending=%s."
                pending-dims)
       (kuro-renderer-pipeline-resize-test--with-buffer
         (setq kuro--resize-pending ',pending-dims)
         (let ((resize-called nil))
           (cl-letf (((symbol-function 'kuro--resize)
                      (lambda (_r _c) (setq resize-called t))))
             (kuro--handle-pending-resize)
             (should-not resize-called)))))))

(defmacro kuro-renderer-pipeline-test--deftest-resize-skips-zero-cases ()
  "Define pending-resize zero-dimension tests."
  `(progn
     ,@(mapcar
        (lambda (case)
          `(kuro-renderer-pipeline-test--def-resize-skips-zero-case ,case))
        kuro-renderer-pipeline-test--resize-skips-zero-cases)))

(defmacro kuro-renderer-pipeline-test--def-row-count-case (case)
  "Define one renderer row count helper test from CASE."
  (pcase-let ((`(,name ,doc ,initial-rows ,target-rows ,expected-rows ,preservep) case))
    `(ert-deftest ,name ()
       ,doc
       (with-temp-buffer
         (dotimes (_ ,initial-rows) (insert "\n"))
         ,(if target-rows
              `(let ((before (buffer-string)))
                 (kuro--adjust-buffer-row-count ,target-rows)
                 (should (= (kuro--current-buffer-row-count) ,expected-rows))
                 ,(when preservep
                    `(should (equal (buffer-string) before))))
            `(should (= (kuro--current-buffer-row-count) ,expected-rows)))))))

(defmacro kuro-renderer-pipeline-test--deftest-row-count-cases ()
  "Define renderer buffer row count helper tests."
  `(progn
     ,@(mapcar
        (lambda (case)
          `(kuro-renderer-pipeline-test--def-row-count-case ,case))
        kuro-renderer-pipeline-test--row-count-cases)))

(defmacro kuro-renderer-pipeline-test--def-render-env-gc-case (case)
  "Define one `kuro--with-render-env' GC binding test from CASE."
  (pcase-let ((`(,name ,gc-var ,expected-const) case))
    `(ert-deftest ,name ()
       ,(format "`kuro--with-render-env' binds %s to %s."
                gc-var expected-const)
       (let (captured)
         (kuro--with-render-env
           (setq captured ,gc-var))
         (should (= captured ,expected-const))))))

(defmacro kuro-renderer-pipeline-test--deftest-render-env-gc-cases ()
  "Define `kuro--with-render-env' GC binding tests."
  `(progn
     ,@(mapcar
        (lambda (case)
          `(kuro-renderer-pipeline-test--def-render-env-gc-case ,case))
        kuro-renderer-pipeline-test--render-env-gc-cases)))

(defmacro kuro-renderer-pipeline-test--def-apply-dirty-updates-case (case)
  "Define one `kuro--apply-dirty-updates' dispatch test from CASE."
  (pcase-let ((`(,name ,doc ,debug-perf ,core-calls ,timing-calls
                       ,core-return ,timing-return ,expected-finalize) case))
    `(ert-deftest ,name ()
       ,doc
       (kuro-renderer-pipeline-test--with-buffer
         (let ((kuro-debug-perf ,debug-perf))
           (kuro-renderer-pipeline-test--with-apply-dirty-updates-stubs
               core-call-count timing-call-count finalize-arg ,core-return ,timing-return
             (kuro--apply-dirty-updates)
             (should (= core-call-count ,core-calls))
             (should (= timing-call-count ,timing-calls))
             (should (equal finalize-arg ,expected-finalize))))))))

(defmacro kuro-renderer-pipeline-test--deftest-apply-dirty-updates-cases ()
  "Define `kuro--apply-dirty-updates' dispatch and finalize tests."
  `(progn
     ,@(mapcar
        (lambda (case)
          `(kuro-renderer-pipeline-test--def-apply-dirty-updates-case ,case))
        kuro-renderer-pipeline-test--apply-dirty-updates-cases)))

(provide 'kuro-renderer-pipeline-test-macros)

;;; kuro-renderer-pipeline-test-macros.el ends here
