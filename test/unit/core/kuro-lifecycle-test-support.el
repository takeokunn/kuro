;;; kuro-lifecycle-test-support.el --- Shared helpers for lifecycle tests  -*- lexical-binding: t; -*-

;;; Commentary:

;; Shared test support for kuro-lifecycle unit tests.
;; This file centralizes the Rust FFI stubs, load-path bootstrapping, and the
;; helper macros shared by the lifecycle split test files.

;;; Code:

(require 'cl-lib)

(let* ((this-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory)))
       (unit-dir (expand-file-name ".." this-dir)))
  (add-to-list 'load-path unit-dir))
(require 'kuro-test-stubs)

(let* ((this-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory)))
       (el-dir (expand-file-name "../../emacs-lisp" this-dir)))
  (add-to-list 'load-path el-dir t))

(require 'kuro-lifecycle)

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

(provide 'kuro-lifecycle-test-support)

;;; kuro-lifecycle-test-support.el ends here
