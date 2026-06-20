;;; kuro-input-keys.el --- Special key handlers for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; This file provides function key (F1-F12), arrow key, navigation key,
;; and modifier key handlers for the Kuro terminal emulator.
;;
;; # Responsibilities
;;
;; - Arrow keys (up/down/left/right) in normal and application cursor mode
;; - Home/End/Insert/Delete/Page-Up/Page-Down
;; - Function keys F1-F12
;; - Ctrl-modified and Alt-modified key senders
;;
;; # Dependencies
;;
;; Depends on `kuro--send-key-sequence' and `kuro--send-special' which are
;; defined in `kuro-input-send'.  Shared KKP constants live in
;; `kuro-input-keys-data'.  This file is required by kuro-input.el after that
;; module is loaded, so no circular dependency arises.

;;; Code:

(require 'kuro-input-keys-macros)
(require 'kuro-input-keys-data)
(require 'kuro-input-macros)

;; Forward references: defined in kuro-input-send.el, loaded before this file.
(declare-function kuro--send-key-sequence "kuro-input-send" (normal-sequence application-sequence))
(declare-function kuro--send-special "kuro-input-send" (byte))
(declare-function kuro--send-key "kuro-ffi" (str))
(declare-function kuro--schedule-immediate-render "kuro-input-render" ())

;; kuro--keyboard-flags is a defvar-permanent-local in kuro-input-paste.el.
;; Forward-declare to silence byte-compiler.
(defvar kuro--keyboard-flags 0
  "Forward reference; defvar-permanent-local in kuro-input-paste.el.")


;;; KKP key-sender helper

(defsubst kuro--kkp-flag-p (flag)
  "Return non-nil if KKP FLAG bit is set in the current session's keyboard flags."
  (not (zerop (logand kuro--keyboard-flags flag))))

(defsubst kuro--send-kkp-functional (codepoint legacy-normal legacy-application)
  "Send a functional key using KKP or legacy encoding.
When the REPORT_ALL_KEYS_AS_ESCAPE_CODES flag (0x08) is set, send the
canonical CSI CODEPOINT ; 1 u form.  Otherwise fall back to the legacy
LEGACY-NORMAL / LEGACY-APPLICATION pair via `kuro--send-key-sequence'."
  (kuro--with-kkp-all-escape (format "\e[%d;1u" codepoint)
    (kuro--send-key-sequence legacy-normal legacy-application)))

;;; Arrow Keys (Normal and Application Mode)
(kuro--def-key-sequence kuro--arrow-up    "Send arrow up key."    "\e[A" "\eOA" kuro--kkp-cp-up)
(kuro--def-key-sequence kuro--arrow-down  "Send arrow down key."  "\e[B" "\eOB" kuro--kkp-cp-down)
(kuro--def-key-sequence kuro--arrow-left  "Send arrow left key."  "\e[D" "\eOD" kuro--kkp-cp-left)
(kuro--def-key-sequence kuro--arrow-right "Send arrow right key." "\e[C" "\eOC" kuro--kkp-cp-right)

;;; Home/End/Page Keys
(kuro--def-key-sequence kuro--HOME      "Send Home key."      "\e[H"  "\e[1~"  kuro--kkp-cp-home)
(kuro--def-key-sequence kuro--END       "Send End key."       "\e[F"  "\e[4~"  kuro--kkp-cp-end)
(kuro--def-key-sequence kuro--INSERT    "Send Insert key."    "\e[2~" "\e[2~"  kuro--kkp-cp-insert)
(kuro--def-key-sequence kuro--DELETE    "Send Delete key."    "\e[3~" "\e[3~"  kuro--kkp-cp-delete)
(kuro--def-key-sequence kuro--PAGE-UP   "Send Page Up key."   "\e[5~" "\e[5~"  kuro--kkp-cp-page-up)
(kuro--def-key-sequence kuro--PAGE-DOWN "Send Page Down key." "\e[6~" "\e[6~"  kuro--kkp-cp-page-down)

;;; Function Keys F1-F12
(kuro--def-key-sequence kuro--F1  "Send F1 key."  "\eOP"   "\eOP"   kuro--kkp-cp-f1)
(kuro--def-key-sequence kuro--F2  "Send F2 key."  "\eOQ"   "\eOQ"   kuro--kkp-cp-f2)
(kuro--def-key-sequence kuro--F3  "Send F3 key."  "\eOR"   "\eOR"   kuro--kkp-cp-f3)
(kuro--def-key-sequence kuro--F4  "Send F4 key."  "\eOS"   "\eOS"   kuro--kkp-cp-f4)
(kuro--def-key-sequence kuro--F5  "Send F5 key."  "\e[15~" "\e[15~" kuro--kkp-cp-f5)
(kuro--def-key-sequence kuro--F6  "Send F6 key."  "\e[17~" "\e[17~" kuro--kkp-cp-f6)
(kuro--def-key-sequence kuro--F7  "Send F7 key."  "\e[18~" "\e[18~" kuro--kkp-cp-f7)
(kuro--def-key-sequence kuro--F8  "Send F8 key."  "\e[19~" "\e[19~" kuro--kkp-cp-f8)
(kuro--def-key-sequence kuro--F9  "Send F9 key."  "\e[20~" "\e[20~" kuro--kkp-cp-f9)
(kuro--def-key-sequence kuro--F10 "Send F10 key." "\e[21~" "\e[21~" kuro--kkp-cp-f10)
(kuro--def-key-sequence kuro--F11 "Send F11 key." "\e[23~" "\e[23~" kuro--kkp-cp-f11)
(kuro--def-key-sequence kuro--F12 "Send F12 key." "\e[24~" "\e[24~" kuro--kkp-cp-f12)

;;; Modifier Combinations

(defun kuro--ctrl-modified (char _modifier)
  "Send Ctrl+CHAR.  _MODIFIER is ignored (reserved for future use).
With KKP REPORT_ALL_KEYS flag (0x08), encodes as CSI char;5u so the app
can distinguish Ctrl+I from Tab, Ctrl+M from Enter, etc."
  (interactive "nChar: \nModifier: ")
  (kuro--with-kkp-all-escape (format "\e[%d;5u" char)
    (kuro--send-special (logand char 31))))

(defun kuro--alt-modified (char)
  "Send Alt+CHAR.
With KKP DISAMBIGUATE flag (0x01), encodes as CSI char;3u so the app
receives unambiguous Alt+key events without escape-prefix ambiguity.
Without KKP, sends the legacy ESC prefix followed by CHAR."
  (interactive "nChar: ")
  (if (kuro--kkp-flag-p kuro--kkp-disambiguate)
      ;; KKP Alt modifier: alt=2 → wire modifier = (2+1)=3
      (kuro--send-key (format "\e[%d;3u" char))
    (kuro--send-key (string ?\e char)))
  (kuro--schedule-immediate-render))

(provide 'kuro-input-keys)

;;; kuro-input-keys.el ends here
