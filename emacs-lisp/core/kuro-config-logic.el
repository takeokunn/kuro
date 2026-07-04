;;; kuro-config-logic.el --- Logic for Kuro configuration  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Runtime helpers and validation for Kuro configuration live here.
;; User-facing defcustom values live in `kuro-config.el'.

;;; Code:

(require 'subr-x)
(require 'kuro-config-macros)

;; Forward declarations for variables defined in `kuro-config.el'.
(defvar kuro-shell)
(defvar kuro-scrollback-size)
(defvar kuro-frame-rate)
(defvar kuro-tui-frame-rate)
(defvar kuro-font-size)
(defvar kuro--color-defcustom-vars)
(defvar kuro--positive-integer-config-vars)
(defvar kuro--optional-positive-integer-config-vars)

;; Forward declaration for kuro--keymap, defined in kuro-input-keymap.el.
(defvar kuro--keymap nil
  "Forward reference; defvar in kuro-input-keymap.el.")

;; Forward declaration for the font applicator defined in kuro-faces.el;
;; called from `kuro--set-font' without a compile-time `require' (avoids a
;; core->faces load cycle).
(declare-function kuro--apply-font-to-buffer "kuro-faces" (buf))

;;; Internal buffer iterator

(defun kuro--kuro-buffers ()
  "Return a list of all live Kuro terminal buffers."
  (when (fboundp 'kuro-mode)
    (let (result)
      (dolist (buf (buffer-list))
        (when (and (buffer-live-p buf)
                   (with-current-buffer buf
                     (derived-mode-p 'kuro-mode)))
          (push buf result)))
      (nreverse result))))

;;; Validation Primitives

(defsubst kuro--positive-integer-p (val)
  "Return non-nil if VAL is a positive integer (> 0)."
  (and (integerp val) (> val 0)))

(defsubst kuro--positive-integer-error (var value)
  "Return a validation error for VAR holding VALUE."
  (format "%s: must be a positive integer, got: %s" var value))

;;; :set handler functions

(defun kuro--set-shell (symbol value)
  "Validate and set SYMBOL to VALUE for `kuro-shell'."
  (unless (or (null value) (string-empty-p value) (executable-find value))
    (user-error "Kuro: shell executable not found: %s" value))
  (set-default symbol value))

(kuro--def-positive-int-setter kuro--set-scrollback-size
    "kuro: scrollback-size must be a positive integer, got: %s"
    "Set SYMBOL to VALUE and propagate to all live Kuro buffers."
  (kuro--broadcast-to-buffers kuro--set-scrollback-max-lines value))

(kuro--def-positive-int-setter kuro--set-frame-rate
    "kuro: frame-rate must be a positive integer, got: %s"
    "Set SYMBOL to VALUE and restart render loops in all active Kuro buffers."
  (when (and (fboundp 'kuro--stop-render-loop)
             (fboundp 'kuro--start-render-loop))
    (kuro--in-all-buffers
      (kuro--stop-render-loop)
      (kuro--start-render-loop))))

(kuro--def-positive-int-setter kuro--set-tui-frame-rate
    "kuro: tui-frame-rate must be a positive integer, got: %s"
    "Set SYMBOL to VALUE and switch render timer in TUI-mode Kuro buffers."
  (when (fboundp 'kuro--switch-render-timer)
    (kuro--in-all-buffers
      (when (bound-and-true-p kuro--tui-mode-active)
        (kuro--switch-render-timer value)))))

(defun kuro--set-font (symbol value)
  "Set SYMBOL to VALUE and apply font remap to all active Kuro buffers."
  (set-default symbol value)
  (kuro--in-all-buffers
    (kuro--apply-font-to-buffer (current-buffer))))

(defun kuro--set-keymap-exceptions (symbol value)
  "Set SYMBOL to VALUE and rebuild the Kuro input keymap.
Propagates the new keymap to all live `kuro-mode' buffers by updating
the parent of their local `kuro-mode-map'."
  (set-default-toplevel-value symbol value)
  (when (fboundp 'kuro--build-keymap)
    (kuro--build-keymap)
    (kuro--in-all-buffers
      (when (boundp 'kuro-mode-map)
        (set-keymap-parent kuro-mode-map kuro--keymap)))))

(defun kuro--set-input-echo-delay (symbol value)
  "Validate and set SYMBOL to VALUE for `kuro-input-echo-delay'.
VALUE must be a non-negative number."
  (unless (numberp value)
    (user-error "Kuro-input-echo-delay must be a number"))
  (when (< value 0)
    (user-error "Kuro-input-echo-delay must be non-negative"))
  (set-default symbol value))

;;; Validation

(defun kuro--validate-config ()
  "Validate all Kuro configuration settings.
Returns a list of error description strings.
An empty list indicates that all settings are valid."
  (let ((errors nil))
    (unless (or (null kuro-shell)
                (string-empty-p kuro-shell)
                (executable-find kuro-shell))
      (push (format "kuro-shell: executable not found: %s" kuro-shell) errors))
    (kuro--check-positive-integer-vars kuro--positive-integer-config-vars errors)
    (kuro--check-optional-positive-integer-vars
     kuro--optional-positive-integer-config-vars errors)
    (dolist (color-var kuro--color-defcustom-vars)
      (kuro--check-hex-color color-var errors))
    (nreverse errors)))

;;;###autoload
(defun kuro-validate-config ()
  "Check Kuro configuration and report any validation errors.
Displays results in the echo area."
  (interactive)
  (let ((errors (kuro--validate-config)))
    (if errors
        (message "Kuro configuration errors (%d):\n%s"
                 (length errors)
                 (mapconcat #'identity errors "\n"))
      (message "Kuro: all configuration settings are valid."))))

(provide 'kuro-config-logic)

;;; kuro-config-logic.el ends here
