;;; kuro-color-scheme.el --- Emacs theme bridge for DEC mode 2031  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; Bridges Emacs's current theme (dark/light) to Kuro sessions so that
;; DSR 996 (CSI ? 996 n) responds with the real Emacs theme and DEC private
;; mode 2031 emits accurate color-scheme-change notifications to guest apps.
;;
;; See: https://contour-terminal.org/vt-extensions/color-palette-update-notifications/

;;; Code:

(require 'cl-lib)
(require 'kuro-config)

(declare-function kuro-core-set-color-scheme "ext:kuro-core" (session-id is-dark))

;; kuro--session-id is the buffer-local session identifier installed by
;; kuro-ffi.el via `kuro--defvar-permanent-local'.  It is non-nil and
;; positive in any live Kuro buffer.
(defvar kuro--session-id)

;;; Customization

(defgroup kuro-color-scheme nil
  "Color scheme notifications for Kuro."
  :group 'kuro)

(defcustom kuro-color-scheme-debounce-seconds 0.05
  "Debounce window for `enable-theme-functions' bursts (seconds).
Theme switches frequently fire a burst of `enable-theme-functions'
calls (one per loaded theme).  This idle delay collapses them into a
single push to all live Kuro sessions."
  :type 'number
  :group 'kuro-color-scheme)

;;; Internal state

(defvar kuro--color-scheme-debounce-timer nil
  "Pending debounce timer; coalesces back-to-back theme events.")

;;; Luminance / detection

(defun kuro--color-scheme-luminance (hex-or-name)
  "Return Rec.709 relative luminance (0..1) for HEX-OR-NAME, or nil on failure.
Uses `color-values' to normalize to 0-1 RGB, then
Y = 0.2126 R + 0.7152 G + 0.0722 B."
  (when-let ((rgb (ignore-errors (color-values hex-or-name))))
    (cl-destructuring-bind (r g b) (mapcar (lambda (c) (/ c 65535.0)) rgb)
      (+ (* 0.2126 r) (* 0.7152 g) (* 0.0722 b)))))

(defun kuro--color-scheme-detect-dark-p (&optional frame)
  "Return t if FRAME (or selected frame) is using a dark color scheme.
Preference order:
  1. `frame-background-mode' if set to `dark' or `light'.
  2. Luminance of default face :background (Y < 0.5 = dark).
  3. Fallback: t (conservative — most TUIs expect bright-on-dark)."
  (let* ((f    (or frame (selected-frame)))
         (mode (frame-parameter f 'background-mode))
         (bg   (face-attribute 'default :background f 'default)))
    (cond
     ((eq mode 'dark)  t)
     ((eq mode 'light) nil)
     ((or (null bg) (eq bg 'unspecified)) t)
     ((stringp bg)
      (let ((y (kuro--color-scheme-luminance bg)))
        (if y (< y 0.5) t)))
     (t t))))

;;; Push to Rust

(defun kuro--color-scheme-apply-now ()
  "Compute current theme and push to every live Kuro session.
Used by both `kuro-color-scheme-refresh' and the debounced
`enable-theme-functions' hook."
  (setq kuro--color-scheme-debounce-timer nil)
  (let ((dark (kuro--color-scheme-detect-dark-p)))
    (kuro--in-all-buffers
     (when (and (boundp 'kuro--session-id)
                kuro--session-id
                (integerp kuro--session-id)
                (> kuro--session-id 0))
       (ignore-errors
         (kuro-core-set-color-scheme kuro--session-id (if dark t nil)))))))

(defun kuro--color-scheme-schedule (&rest _args)
  "Debounced trigger for `enable-theme-functions'.
Coalesces back-to-back theme events into a single
`kuro--color-scheme-apply-now' invocation after
`kuro-color-scheme-debounce-seconds' of idle time."
  (when kuro--color-scheme-debounce-timer
    (cancel-timer kuro--color-scheme-debounce-timer))
  (setq kuro--color-scheme-debounce-timer
        (run-with-idle-timer kuro-color-scheme-debounce-seconds nil
                             #'kuro--color-scheme-apply-now)))

;;;###autoload
(defun kuro-color-scheme-refresh ()
  "Manually push the current Emacs theme to all Kuro sessions.
Useful when `enable-theme-functions' is unavailable (Emacs < 29.1) or
when external code mutates faces without firing a theme event."
  (interactive)
  (kuro--color-scheme-apply-now))

;;; Hook lifecycle

(defun kuro--color-scheme-install-hook ()
  "Install the theme-change hook if Emacs supports it.
On Emacs 29.1+ adds `kuro--color-scheme-schedule' to
`enable-theme-functions'.  On older Emacsen emits a one-time warning
and falls back to manual `kuro-color-scheme-refresh'.
After installation, immediately push the current Emacs theme state to
all live Kuro sessions so the Rust-side `color_scheme_dark' flag is in
sync — otherwise it stays at its default (`true') until the user next
switches themes."
  (if (boundp 'enable-theme-functions)
      (add-hook 'enable-theme-functions #'kuro--color-scheme-schedule)
    (display-warning 'kuro
                     "Color scheme notifications require Emacs 29.1+; \
falling back to manual M-x kuro-color-scheme-refresh."
                     :warning))
  (ignore-errors (kuro--color-scheme-apply-now)))

(defun kuro--color-scheme-uninstall-hook ()
  "Remove the theme-change hook installed by `kuro--color-scheme-install-hook'."
  (when (boundp 'enable-theme-functions)
    (remove-hook 'enable-theme-functions #'kuro--color-scheme-schedule))
  (when kuro--color-scheme-debounce-timer
    (cancel-timer kuro--color-scheme-debounce-timer)
    (setq kuro--color-scheme-debounce-timer nil)))

(provide 'kuro-color-scheme)

;;; kuro-color-scheme.el ends here
