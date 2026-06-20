;;; kuro-input-keymap-navigation.el --- Navigation key bindings for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Navigation-related key bindings and shifted-key helpers for
;; `kuro-input-keymap.el'.  This module keeps the arrow/function-key logic
;; separate from the lower-level keymap builder and exception handling.

;;; Code:

(require 'kuro-ffi)
(require 'kuro-input-keys-data)
(require 'kuro-input-keymap-data)
(require 'kuro-keymap)
(require 'kuro-keymap-macros)
(require 'kuro-input-keymap-navigation-macros)

;; Forward references from kuro-input-send.el, kuro-input-send-scroll.el, and
;; kuro-input-keys.el.
(declare-function kuro--send-key "kuro-ffi" (key))
(declare-function kuro--schedule-immediate-render "kuro-input-render" ())
(declare-function kuro--arrow-up "kuro-input-keys" ())
(declare-function kuro--arrow-down "kuro-input-keys" ())
(declare-function kuro--arrow-left "kuro-input-keys" ())
(declare-function kuro--arrow-right "kuro-input-keys" ())
(declare-function kuro--HOME "kuro-input-keys" ())
(declare-function kuro--END "kuro-input-keys" ())
(declare-function kuro--PAGE-UP "kuro-input-keys" ())
(declare-function kuro--PAGE-DOWN "kuro-input-keys" ())
(declare-function kuro--INSERT "kuro-input-keys" ())
(declare-function kuro--DELETE "kuro-input-keys" ())
(declare-function kuro-scroll-up "kuro-input-send-scroll" ())
(declare-function kuro-scroll-down "kuro-input-send-scroll" ())
(declare-function kuro-scroll-bottom "kuro-input-send-scroll" ())
(declare-function kuro--F1 "kuro-input-keys" ())
(declare-function kuro--F2 "kuro-input-keys" ())
(declare-function kuro--F3 "kuro-input-keys" ())
(declare-function kuro--F4 "kuro-input-keys" ())
(declare-function kuro--F5 "kuro-input-keys" ())
(declare-function kuro--F6 "kuro-input-keys" ())
(declare-function kuro--F7 "kuro-input-keys" ())
(declare-function kuro--F8 "kuro-input-keys" ())
(declare-function kuro--F9 "kuro-input-keys" ())
(declare-function kuro--F10 "kuro-input-keys" ())
(declare-function kuro--F11 "kuro-input-keys" ())
(declare-function kuro--F12 "kuro-input-keys" ())
(declare-function kuro--kkp-flag-p "kuro-input-keys" (flag))

(kuro--def-shifted-key kuro--send-shifted-tab
  "\e[9;2u" "\e[Z"
  "Send Shift+Tab to the PTY: KKP CSI 9;2u or legacy ESC [ Z.")

(kuro--def-shifted-key kuro--send-shifted-return
  "\e[13;2u" "\r"
  "Send Shift+Return to the PTY: KKP CSI 13;2u or legacy CR.")

(defun kuro--keymap-setup-navigation (map)
  "Install navigation and function-key bindings into MAP."
  ;; Static navigation keys: arrows, home/end/page/insert/delete, scrollback
  (kuro--define-key-bindings map kuro--nav-key-bindings
    (lambda (binding) (car binding))
    #'cdr)

  ;; Function keys F1–F12
  (kuro--define-key-bindings map kuro--fkey-handlers
    (lambda (binding) (vector (car binding)))
    #'cdr)

  ;; Modifier + arrow keys: xterm CSI 1;Nm sequences (or KKP with flag 0x08)
  (kuro--define-modifier-arrow-bindings map
    kuro--xterm-modifier-codes
    kuro--xterm-arrow-codes)

  ;; Shift+Tab: [backtab] (X11) and [S-tab] (some terminals) are the same event.
  (kuro--bind-keys map #'kuro--send-shifted-tab [backtab] [S-tab])
  ;; Shift+Return: legacy = CR; KKP = CSI 13;2u
  (define-key map [S-return] #'kuro--send-shifted-return))

(provide 'kuro-input-keymap-navigation)
;;; kuro-input-keymap-navigation.el ends here
