;;; kuro-input.el --- Keyboard input handling for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; This module provides keyboard input handling for the Kuro terminal emulator.
;; It handles printable characters, special keys, arrow keys (in normal and
;; application modes), function keys, modifier combinations, and bracketed paste
;; mode.
;;
;; Mouse tracking is in kuro-input-mouse.el.
;; Bracketed paste is in kuro-input-paste.el.
;; Mouse scrollback fallback is in kuro-input-mouse-scroll.el.
;; Scroll-aware input helpers are in kuro-input-send-scroll.el.
;; Keymap construction is in kuro-input-keymap.el.
;; Key encoding and bypass dispatch are in kuro-input-encode.el.

;;; Code:

(require 'kuro-config)
(require 'kuro-ffi)
(require 'kuro-ffi-osc)
(require 'kuro-input-macros)
(require 'kuro-input-render)

;; Forward reference: kuro--update-scroll-indicator is defined in
;; kuro-render-buffer.el, which is loaded after kuro-input.el.
(declare-function kuro--update-scroll-indicator "kuro-render-buffer" ())


(require 'kuro-input-send)
(require 'kuro-input-send-scroll)
(require 'kuro-input-keys)
(require 'kuro-input-mouse)
(require 'kuro-input-mouse-scroll)
;;; Keymap Initialization

;; kuro-input-keymap.el is required here — AFTER all the behavior functions
;; above are defined — so that kuro--build-keymap can reference them via
;; declare-function without a circular require.
(require 'kuro-input-keymap)
(require 'kuro-input-encode)

;; Build kuro--keymap at load time so it is available immediately for tests
;; and for any kuro-mode buffer that calls (set-keymap-parent kuro-mode-map kuro--keymap).
(kuro--build-keymap)

(provide 'kuro-input)

;;; kuro-input.el ends here
