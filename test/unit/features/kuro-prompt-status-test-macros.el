;;; kuro-prompt-status-test-macros.el --- Macros for prompt-status tests  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;;; Commentary:

;; Shared setup and test-generation macros for kuro-prompt-status-test.el.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-prompt-status-test-cases)

;; Stub FFI symbols so kuro-prompt-status loads without the Rust module.
(dolist (sym '(kuro-core-init
               kuro-core-send-key
               kuro-core-poll-updates
               kuro-core-poll-updates-with-faces
               kuro-core-resize
               kuro-core-shutdown
               kuro-core-get-cursor
               kuro-core-get-cursor-visible
               kuro-core-get-cursor-shape
               kuro-core-is-process-alive))
  (unless (fboundp sym)
    (fset sym (lambda (&rest _) nil))))

(unless (fboundp 'module-load)
  (fset 'module-load (lambda (_path) nil)))

(let* ((this-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory)))
       (el-dir (expand-file-name "../../../emacs-lisp" this-dir)))
  (add-to-list 'load-path el-dir t))

(require 'kuro-prompt-status)

(defmacro kuro-prompt-status-test--with-buffer (&rest body)
  "Run BODY in a temp buffer with prompt status state initialized."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (kuro--prompt-status-overlays nil)
           (kuro-prompt-status-annotations t)
           (kuro-prompt-status-success-indicator "✓")
           (kuro-prompt-status-failure-indicator "✗"))
       ,@body)))

(defmacro kuro-prompt-status-test--def-indicator-result
    (test-name exit-code expected-text expected-face)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--prompt-status-indicator' exit=%d -> %S face=%s."
              exit-code expected-text expected-face)
     (let ((result (kuro--prompt-status-indicator ,exit-code)))
       (should (stringp result))
       (should (string= (substring-no-properties result) ,expected-text))
       (should (eq (get-text-property 0 'face result) ',expected-face)))))

(defmacro kuro-prompt-status-test--def-format-duration (test-name ms expected)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--format-prompt-duration' %d ms -> %S." ms expected)
     (should (equal (kuro--format-prompt-duration ,ms) ,expected))))

(defmacro kuro-prompt-status-test--def-face-exists (test-name face-sym)
  `(ert-deftest ,test-name ()
     ,(format "`%s' face is defined." face-sym)
     (should (facep ',face-sym))))

(provide 'kuro-prompt-status-test-macros)

;;; kuro-prompt-status-test-macros.el ends here
