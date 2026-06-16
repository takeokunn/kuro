;;; kuro-test-support.el --- Shared helpers for kuro.el unit tests  -*- lexical-binding: t; -*-

;;; Commentary:

;; Shared test support for kuro.el unit tests.
;; This file centralises the Rust FFI stubs, load-path bootstrapping, and the
;; helper macros and functions shared across the kuro.el split test files:
;;   kuro-test.el, kuro-test-keymap.el, kuro-copy-mode-test.el,
;;   kuro-copy-mode-adv-test.el.

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; ── Stub Rust FFI symbols ────────────────────────────────────────────────────
(let* ((this-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory)))
       (unit-dir (expand-file-name ".." this-dir)))
  (add-to-list 'load-path unit-dir))
(require 'kuro-test-stubs)

;;; ── Load kuro.el and its full dependency chain ──────────────────────────────
(let* ((this-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory)))
       (el-dir (expand-file-name "../../../emacs-lisp/core" this-dir)))
  (add-to-list 'load-path el-dir t))
(require 'kuro)

;;; ── Shared test macros and helpers ──────────────────────────────────────────

(defmacro kuro-el-test--with-kuro-buffer (&rest body)
  "Run BODY in a temp buffer simulating a live kuro-mode buffer."
  `(with-temp-buffer
     (setq major-mode 'kuro-mode)
     (setq-local kuro--initialized t)
     (setq-local kuro--last-rows 24)
     (setq-local kuro--last-cols 80)
     (setq-local kuro--resize-pending nil)
     ,@body))

(defun kuro-el-test--apply-resize-logic (initialized new-rows new-cols last-rows last-cols)
  "Evaluate the resize-pending predicate used inside `kuro--window-size-change'.
Returns the value that `kuro--resize-pending' would be set to, or nil."
  (when (and initialized
             (or (/= new-rows last-rows)
                 (/= new-cols last-cols)))
    (cons new-rows new-cols)))

(defmacro kuro-el-test--with-kuro-mode-buffer (&rest body)
  "Run BODY in a temp buffer with major-mode set to kuro-mode (no real init)."
  `(with-temp-buffer
     (setq major-mode 'kuro-mode)
     (setq-local kuro--copy-mode nil)
     (setq mode-name "Kuro")
     (use-local-map kuro-mode-map)
     ,@body))

(defmacro kuro-copy-mode-test--with-prompt-overlays (positions &rest body)
  "Evaluate BODY in a temp buffer that has `kuro-prompt-status' overlays at POSITIONS."
  (declare (indent 1))
  `(with-temp-buffer
     (insert (make-string 30 ?x))
     (dolist (p ,positions)
       (let ((ov (make-overlay p p)))
         (overlay-put ov 'kuro-prompt-status t)))
     ,@body))

(provide 'kuro-test-support)
;;; kuro-test-support.el ends here
