;;; kuro-input-mode-test-support.el --- Shared helpers for input-mode tests  -*- lexical-binding: t; -*-

;;; Commentary:

;; Shared test support macros for kuro-input-mode unit tests.
;; This file provides setup macros used across multiple test files.

;;; Code:

(require 'kuro-test-stubs)
(require 'kuro-config)
(require 'kuro-ffi)
(require 'kuro-input-keymap)
(require 'kuro-input-mode)

;; Forward declaration: kuro-mode is defined in kuro.el but we test
;; kuro-input-mode.el in isolation.  Provide a minimal derived mode.
(unless (fboundp 'kuro-mode)
  (define-derived-mode kuro-mode fundamental-mode "Kuro-test"))

(defmacro kuro-input-mode-test--with-buffer (&rest body)
  "Run BODY in a fresh `kuro-mode' buffer with stubs active."
  `(with-temp-buffer
     (kuro-mode)
     ;; Ensure both keymaps are built before each test
     (kuro--build-keymap)
     ;; kuro-mode-map must have kuro--keymap as parent for mode switches to work
     (set-keymap-parent kuro-mode-map kuro--keymap)
     (use-local-map kuro-mode-map)
     ,@body))

(defmacro kuro-input-mode-test--with-line (buf-str point-pos &rest body)
  "Run BODY in line mode with `kuro--line-buffer' = BUF-STR and point at POINT-POS."
  `(kuro-input-mode-test--with-buffer
    (setq kuro--input-mode 'line
          kuro--line-buffer ,buf-str
          kuro--line-point  ,point-pos)
    ,@body))

(provide 'kuro-input-mode-test-support)

;;; kuro-input-mode-test-support.el ends here
