;;; kuro-input-send.el --- Key sending helpers for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; This module owns the low-level send helpers and the keyboard mode state
;; shared by input key handlers.

;;; Code:

(require 'kuro-ffi)
(require 'kuro-input-macros)
(require 'kuro-input-keys-macros)
(require 'kuro-input-mouse-macros)
(require 'kuro-input-render)

;; Forward references.
(declare-function kuro--send-key "kuro-ffi" (str))
(declare-function kuro--render-cycle "kuro-renderer" ())
(declare-function kuro--update-scroll-indicator "kuro-render-buffer" ())
(declare-function kuro--schedule-immediate-render "kuro-input-render" ())

;; kuro--keyboard-flags is defvar-permanent-local in kuro-input-paste.el.
;; Forward-declare here so kuro--RET/TAB/DEL can reference it before that file loads.
(defvar kuro--keyboard-flags 0
  "Forward reference; defvar-permanent-local in kuro-input-paste.el.")


;;; Printable Characters

(defsubst kuro--send-char (char)
  "Send printable CHAR as UTF-8 to PTY."
  (kuro--send-key (string char)))

(defun kuro--self-insert ()
  "Send the typed character to the PTY (used via remap of `self-insert-command').
If `last-command-event' is a control character (< 32 or = 127), send it as a
control byte directly.  This handles the case where remap catches control-style
events that were not caught by the explicit Ctrl+letter bindings."
  (interactive)
  (let ((char last-command-event))
    (when (characterp char)
      (kuro--send-char char)
      ;; Schedule an immediate render so the echoed character appears without
      ;; waiting for the next periodic fps timer tick.
      (kuro--schedule-immediate-render))))


;;; Special Keys

(defun kuro--send-special (byte)
  "Send special key as single BYTE sequence to PTY; schedule immediate render."
  (kuro--send-key (string byte))
  (kuro--schedule-immediate-render))

(kuro--def-kkp-key kuro--RET "\e[13;1u" ?\r
  "Send Return key.
With KKP REPORT_ALL_KEYS flag (0x08), send CSI 13;1u for unambiguous reporting.
Otherwise send bare CR (\\r) as in the legacy protocol.")

(kuro--def-kkp-key kuro--TAB "\e[9;1u" ?\t
  "Send Tab key.
With KKP REPORT_ALL_KEYS flag (0x08), send CSI 9;1u so the app can
distinguish Tab from Ctrl+I (which becomes CSI 105;5u).
Otherwise send bare HT (\\t) as in the legacy protocol.")

(kuro--def-kkp-key kuro--DEL "\e[127;1u" ?\x7f
  "Send Delete (backspace) key.
With KKP REPORT_ALL_KEYS flag (0x08), send CSI 127;1u.
Otherwise send bare DEL (0x7f) as in the legacy protocol.")


;;; Helper Function for Key Sequences

(kuro--defvar-permanent-local kuro--application-cursor-keys-mode nil
  "Cached DECCKM (application cursor keys) mode state from Rust (?1).
Polled by render cycle.")

(kuro--defvar-permanent-local kuro--scroll-offset 0
  "Current scrollback offset. 0 means live terminal view.")

(kuro--defvar-permanent-local kuro--app-keypad-mode nil
  "Cached application keypad mode (DECKPAM/DECKPNM) state from Rust.
Polled by render cycle.  P1 scaffolding: declared and polled now so that
numeric keypad bindings (kp-0 through kp-9, kp-enter, etc.) can read it.")

(defun kuro--send-key-sequence (normal-sequence application-sequence)
  "Send key sequence, switching between normal and application cursor modes.
NORMAL-SEQUENCE is sent in normal mode.
APPLICATION-SEQUENCE is sent in application cursor keys mode.
Always schedules an immediate render so cursor movement feels instant."
  (kuro--send-key (if kuro--application-cursor-keys-mode
                      application-sequence
                    normal-sequence))
  (kuro--schedule-immediate-render))

(defun kuro--ctrl-alt-modified (char _modifier)
  "Send Ctrl+Alt+CHAR as ESC prefix followed by Ctrl-CHAR.  Ignore _MODIFIER."
  (interactive "nChar: \nModifier: ")
  (kuro--send-key (concat (string ?\e) (string (logand char 31))))
  (kuro--schedule-immediate-render))


;;; Keymap Helpers (used by kuro-input-keymap.el)

(kuro--def-key-sender kuro--send-ctrl
  (string byte) byte
  "Send a single control byte (0–31 or 127) to the PTY and schedule render.")

(kuro--def-key-sender kuro--send-meta
  (string ?\e char) char
  "Send ESC + CHAR to the PTY (readline Alt/Meta prefix) and schedule render.")

(provide 'kuro-input-send)

;;; kuro-input-send.el ends here
