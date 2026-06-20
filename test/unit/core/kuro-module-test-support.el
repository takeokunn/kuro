;;; kuro-module-test-support.el --- Shared helpers for kuro-module ERT tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Shared bootstrap and fixtures for kuro-module ERT tests.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Stub module-load before loading kuro-module so the file can be required
;; safely in batch mode without a compiled Rust binary present.
(unless (fboundp 'module-load)
  (fset 'module-load (lambda (_path) nil)))

(require 'kuro-config)
(require 'kuro-module)

(defmacro kuro-module-test--with-env-var (var value &rest body)
  "Stub `getenv' so VAR returns VALUE; all other vars pass through."
  (declare (indent 2))
  `(let ((kuro-module-test--orig-getenv (symbol-function 'getenv)))
     (cl-letf (((symbol-function 'getenv)
                (lambda (name)
                  (if (equal name ,var)
                      ,value
                    (funcall kuro-module-test--orig-getenv name)))))
       ,@body)))

(defmacro kuro-module-test--with-dev-stubs (&rest body)
  "Stub `locate-library' and `file-exists-p' for tier-dev tests."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'locate-library)
              (lambda (_name) "/stub/emacs-lisp/core/kuro-module.el"))
             ((symbol-function 'file-exists-p) (lambda (_) t)))
     ,@body))

(defmacro kuro-module-test--with-temp-dir (spec &rest body)
  "Bind VAR to a temporary directory created from PREFIX for BODY."
  (declare (indent 1))
  (cl-destructuring-bind (var prefix) spec
    `(let ((,var (make-temp-file ,prefix t)))
       (unwind-protect
           (progn ,@body)
         (ignore-errors (delete-directory ,var t))))))

(defmacro kuro-module-test--with-temp-file (spec &rest body)
  "Bind VAR to a temporary file created from PREFIX for BODY."
  (declare (indent 1))
  (cl-destructuring-bind (var prefix) spec
    `(let ((,var (make-temp-file ,prefix)))
       (unwind-protect
           (progn ,@body)
         (ignore-errors (delete-file ,var))))))

(defmacro kuro-module-test--with-temp-dir-env (spec &rest body)
  "Create a temporary dir bound to VAR and expose it through ENV-VAR."
  (declare (indent 1))
  (cl-destructuring-bind (var prefix env-var) spec
    `(kuro-module-test--with-temp-dir (,var ,prefix)
       (kuro-module-test--with-env-var ,env-var ,var
         ,@body))))

(defmacro kuro-module-test--with-temp-dir-file (spec &rest body)
  "Create a temp dir and bind FILE-VAR to a file path inside it."
  (declare (indent 1))
  (cl-destructuring-bind (dir-var file-var prefix filename) spec
    `(kuro-module-test--with-temp-dir (,dir-var ,prefix)
       (let ((,file-var (expand-file-name ,filename ,dir-var)))
         (with-temp-file ,file-var)
         ,@body))))

(defmacro kuro-module-test--with-cargo-toml-tree (spec &rest body)
  "Create a temp checkout tree with rust-core/Cargo.toml and a nested subdir."
  (declare (indent 1))
  (cl-destructuring-bind (root-var rust-var sub-var prefix) spec
    `(kuro-module-test--with-temp-dir (,root-var ,prefix)
       (let ((,rust-var (expand-file-name "rust-core" ,root-var))
             (,sub-var (expand-file-name "a/b/c" ,root-var)))
         (make-directory ,rust-var t)
         (make-directory ,sub-var t)
         (with-temp-file (expand-file-name "Cargo.toml" ,rust-var))
         ,@body))))

(provide 'kuro-module-test-support)
;;; kuro-module-test-support.el ends here
