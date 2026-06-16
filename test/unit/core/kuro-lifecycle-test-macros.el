;;; kuro-lifecycle-test-macros.el --- Shared lifecycle test macros  -*- lexical-binding: t; -*-

;;; Commentary:

;; Rust FFI stubs, load-path bootstrapping, and helper macros shared by the
;; lifecycle split test files.

;;; Code:

(require 'cl-lib)

(let* ((this-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory)))
       (unit-dir (expand-file-name ".." this-dir)))
  (add-to-list 'load-path unit-dir))
(require 'kuro-test-stubs)
(require 'kuro-lifecycle-test-cases)

(let* ((this-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory)))
       (el-dir (expand-file-name "../../emacs-lisp" this-dir)))
  (add-to-list 'load-path el-dir t))

(require 'kuro-lifecycle)

(defvar kuro-module-installation-method nil
  "Test binding for lifecycle module installation tests.")

(unless (fboundp 'kuro-module-download)
  (defun kuro-module-download (&optional _version)
    "Test stub for lifecycle module download tests."
    nil))

(unless (fboundp 'kuro-module-build)
  (defun kuro-module-build ()
    "Test stub for lifecycle module build tests."
    nil))

(unless (fboundp 'kuro-mode)
  (define-derived-mode kuro-mode fundamental-mode "Kuro-test"
    "Minimal `kuro-mode' stub for lifecycle tests."))

(defmacro kuro-lifecycle-test--capture-send-key (&rest body)
  "Execute BODY with `kuro--send-key' stubbed and capture the calls."
  `(let ((captured nil)
         (kuro--initialized t))
     (cl-letf (((symbol-function 'kuro--send-key)
                (lambda (data) (push data captured))))
       ,@body)
     (nreverse captured)))

(defmacro kuro-lifecycle-test--with-kill-stubs (&rest body)
  "Execute BODY with the common `kuro-kill' dependencies stubbed."
  `(cl-letf (((symbol-function 'kuro--stop-render-loop)         (lambda () nil))
             ((symbol-function 'kuro--cleanup-render-state)     (lambda () nil))
             ((symbol-function 'kuro--clear-all-image-overlays) (lambda () nil))
             ((symbol-function 'kuro--shutdown)                 (lambda () nil))
             ((symbol-function 'kill-buffer)                    (lambda (_buf) nil)))
     ,@body))

(defmacro kuro-lifecycle-test--with-init-stubs (&rest body)
  "Execute BODY with `kuro--init-session-buffer' dependencies stubbed."
  `(cl-letf (((symbol-function 'kuro--set-scrollback-max-lines)  (lambda (_n) nil))
             ((symbol-function 'kuro--apply-font-to-buffer)       (lambda (_b) nil))
             ((symbol-function 'kuro--setup-char-width-table)     (lambda () nil))
             ((symbol-function 'kuro--setup-fontset)              (lambda () nil))
             ((symbol-function 'kuro--remap-default-face)         (lambda (_fg _bg) nil))
             ((symbol-function 'kuro--reset-cursor-cache)         (lambda () nil))
             ((symbol-function 'kuro--setup-dnd)                  (lambda () nil))
             ((symbol-function 'kuro--setup-compilation)          (lambda () nil))
             ((symbol-function 'kuro--setup-bookmark)             (lambda () nil)))
     ,@body))

(defmacro kuro-lifecycle-test--with-attach-stubs (&rest body)
  "Execute BODY with `kuro--do-attach' dependencies stubbed."
  `(cl-letf (((symbol-function 'kuro-core-attach)         #'ignore)
             ((symbol-function 'kuro--prefill-buffer)      #'ignore)
             ((symbol-function 'kuro--init-session-buffer) #'ignore)
             ((symbol-function 'kuro--resize)              #'ignore)
             ((symbol-function 'kuro--start-render-loop)   #'ignore))
     ,@body))

(defmacro kuro-lifecycle-test--assert-noop-when-uninitialized (fn-call)
  "Assert FN-CALL is a no-op when `kuro--initialized' is nil.
Verifies that `kuro-core-send-key' (the Rust FFI) is never reached,
i.e. the init guard in `kuro--send-key' / `kuro--call' short-circuits."
  `(let ((kuro--initialized nil)
         (called nil))
     (cl-letf (((symbol-function 'kuro-core-send-key)
                (lambda (_bytes) (setq called t))))
       ,fn-call)
     (should-not called)))

(defmacro kuro-lifecycle-test--check-kill-shutdown (mode expected-form)
  "Call `kuro-kill' in a temp buffer with MAJOR-MODE; check if shutdown was called.
EXPECTED-FORM is the assertion form - `should' or `should-not'."
  `(with-temp-buffer
     (setq major-mode ,mode)
     (let ((shutdown-called nil))
       (kuro-lifecycle-test--with-kill-stubs
         (cl-letf (((symbol-function 'kuro--shutdown)
                    (lambda () (setq shutdown-called t))))
           (kuro-kill)
           (,expected-form shutdown-called))))))

(defmacro kuro-lifecycle-test--with-rollback-stubs (msg-fn kill-fn &rest body)
  "Stub the three `kuro--rollback-attach' dependencies.
MSG-FN stubs `message', KILL-FN stubs `kill-buffer'.
Callers manage `kuro--session-id' and `kuro--initialized' themselves."
  `(cl-letf (((symbol-function 'kuro-core-detach) #'ignore)
             ((symbol-function 'message)           ,msg-fn)
             ((symbol-function 'kill-buffer)       ,kill-fn))
     ,@body))

(defmacro kuro-lifecycle-test--with-init-session-buffer (&rest body)
  "Run BODY in a temp buffer with `kuro--init-session-buffer' deps stubbed.
Initializes the buffer-local vars that `kuro--init-session-buffer' expects."
  `(with-temp-buffer
     (setq-local kuro--cursor-marker nil
                 kuro--last-rows     0
                 kuro--last-cols     0
                 kuro--scroll-offset 0)
     (kuro-lifecycle-test--with-init-stubs
       ,@body)))

(defmacro kuro-lifecycle-test--with-kuro-attach (&rest body)
  "Stub `kuro--ensure-module-loaded' and `kuro-mode' for attach tests.
BODY runs with `kuro-attach-result' bound; the buffer is cleaned up afterward."
  `(let ((kuro-attach-result nil))
     (cl-letf (((symbol-function 'kuro--ensure-module-loaded) #'ignore)
               ((symbol-function 'kuro-mode)
                (lambda () (setq major-mode 'kuro-mode))))
       (unwind-protect
           (progn ,@body)
         (when (buffer-live-p kuro-attach-result)
           (kill-buffer kuro-attach-result))))))

(defmacro kuro-lifecycle-test--def-session-status
    (test-name raw-entry expected-status)
  "Generate a test verifying `kuro-sessions--entry' produces EXPECTED-STATUS."
  `(ert-deftest ,test-name ()
     ,(format "`kuro-sessions--entry' converts session to status %S."
              expected-status)
     (let ((row (kuro-sessions--entry ',raw-entry)))
       (should row)
       (should (equal (aref (cadr row) 2) ,expected-status)))))

(defmacro kuro-lifecycle-test--with-create-stubs (&rest body)
  "Run BODY with every kuro-create side-effecting helper stubbed.
Stubs kuro--ensure-module-loaded, kuro-mode, kuro--prefill-buffer,
kuro--init-session-buffer, kuro--start-render-loop, and
kuro--schedule-initial-render as no-ops so the test controls only
`kuro--init' behaviour.  Override individual stubs inside BODY via
`cl-letf'."
  `(cl-letf (((symbol-function 'kuro--ensure-module-loaded)   #'ignore)
             ((symbol-function 'kuro-mode)
              (lambda () (setq major-mode 'kuro-mode)))
             ((symbol-function 'kuro--prefill-buffer)          #'ignore)
             ((symbol-function 'kuro--init-session-buffer)     #'ignore)
             ((symbol-function 'kuro--start-render-loop)       #'ignore)
             ((symbol-function 'kuro--schedule-initial-render) #'ignore)
             ((symbol-function 'message)                       #'ignore))
     ,@body))

(defmacro kuro-lifecycle-test--with-start-session-stubs (init-result &rest body)
  "Stub `kuro--start-session-in-buffer' dependencies for BODY.
INIT-RESULT is the value `kuro--init' should return."
  `(cl-letf (((symbol-function 'kuro--terminal-dimensions)         (lambda () '(24 . 80)))
             ((symbol-function 'kuro--prefill-buffer)              #'ignore)
             ((symbol-function 'kuro--setup-shell-integration-env) #'ignore)
             ((symbol-function 'kuro--init)                        (lambda (&rest _) ,init-result))
             ((symbol-function 'kuro--init-session-buffer)         #'ignore)
             ((symbol-function 'kuro--start-render-loop)           #'ignore)
             ((symbol-function 'kuro--schedule-initial-render)     #'ignore))
     ,@body))

(provide 'kuro-lifecycle-test-macros)

;;; kuro-lifecycle-test-macros.el ends here
