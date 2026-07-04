;;; kuro-color-scheme-test-macros.el --- Macros for color-scheme tests  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;;; Commentary:

;; Shared bootstrap, stubs, and continuation-style helper macros for
;; kuro-color-scheme-test.el.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let* ((this-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory)))
       (unit-dir (expand-file-name "../" this-dir))
       (el-root  (expand-file-name "../../../emacs-lisp" this-dir))
       (el-core  (expand-file-name "core" el-root))
       (el-feat  (expand-file-name "features" el-root))
       (el-ffi   (expand-file-name "ffi" el-root))
       (el-faces (expand-file-name "faces" el-root)))
  (dolist (d (list unit-dir el-core el-feat el-ffi el-faces))
    (add-to-list 'load-path d t)))

(require 'kuro-test-stubs)

(unless (fboundp 'kuro-core-set-color-scheme)
  (fset 'kuro-core-set-color-scheme (lambda (&rest _) nil)))

(require 'kuro-config)
(require 'kuro-color-scheme)

(defmacro kuro-color-scheme-test--with-stubbed-set (binding &rest body)
  "Stub `kuro-core-set-color-scheme' to BINDING while running BODY."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'kuro-core-set-color-scheme) ,binding))
     ,@body))

(defmacro kuro-color-scheme-test--with-fake-buffers (buffers &rest body)
  "Stub `kuro--kuro-buffers' to return BUFFERS while running BODY."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'kuro--kuro-buffers) (lambda () ,buffers)))
     ,@body))

(defmacro kuro-color-scheme-test--with-session-buffer (session-id &rest body)
  "Run BODY with one fake Kuro buffer whose session id is SESSION-ID."
  (declare (indent 1))
  `(with-temp-buffer
     (let ((buf (current-buffer)))
       (setq-local kuro--session-id ,session-id)
       (kuro-color-scheme-test--with-fake-buffers (list buf)
         ,@body))))

(defmacro kuro-color-scheme-test--with-detected-dark (dark &rest body)
  "Stub `kuro--color-scheme-detect-dark-p' to return DARK while running BODY."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'kuro--color-scheme-detect-dark-p)
              (lambda (&rest _) ,dark)))
     ,@body))

(defmacro kuro-color-scheme-test--with-color-mode (mode bg &rest body)
  "Stub frame-background MODE and default face BG while running BODY."
  (declare (indent 2))
  `(cl-letf (((symbol-function 'frame-parameter)
              (lambda (_f _p) ,mode))
             ((symbol-function 'face-attribute)
              (lambda (&rest _) ,bg)))
     ,@body))

(defmacro kuro-color-scheme-test--deftest-detect-dark
    (name doc mode bg expected)
  "Define a detect-dark test NAME with DOC, MODE, BG, and EXPECTED."
  (declare (indent 1))
  `(ert-deftest ,name ()
     ,doc
     (kuro-color-scheme-test--with-color-mode ,mode ,bg
       ,(if expected
            '(should (kuro--color-scheme-detect-dark-p))
          '(should-not (kuro--color-scheme-detect-dark-p))))))

(provide 'kuro-color-scheme-test-macros)

;;; kuro-color-scheme-test-macros.el ends here
