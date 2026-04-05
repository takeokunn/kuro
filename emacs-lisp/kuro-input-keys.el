;;; kuro-input-keys.el --- Special key handlers for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

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
;; defined in `kuro-input'.  This file is required by kuro-input.el AFTER
;; those functions are defined, so no circular dependency arises.

;;; Code:

;; Forward references: defined in kuro-input.el, loaded before this file.
(declare-function kuro--send-key-sequence "kuro-input" (normal-sequence application-sequence))
(declare-function kuro--send-special "kuro-input" (byte))
(declare-function kuro--send-key "kuro-ffi" (str))
(declare-function kuro--schedule-immediate-render "kuro-input" ())

(defmacro kuro--def-key-sequence (name doc normal application)
  "Define an interactive command NAME that sends a key sequence to the PTY.
NORMAL is sent in normal cursor mode; APPLICATION in application cursor mode.
DOC is the function docstring."
  `(defun ,name () ,doc
     (interactive)
     (kuro--send-key-sequence ,normal ,application)))

;;; Arrow Keys (Normal and Application Mode)
(kuro--def-key-sequence kuro--arrow-up    "Send arrow up key."    "\e[A" "\eOA")
(kuro--def-key-sequence kuro--arrow-down  "Send arrow down key."  "\e[B" "\eOB")
(kuro--def-key-sequence kuro--arrow-left  "Send arrow left key."  "\e[D" "\eOD")
(kuro--def-key-sequence kuro--arrow-right "Send arrow right key." "\e[C" "\eOC")

;;; Home/End/Page Keys
(kuro--def-key-sequence kuro--HOME      "Send Home key."      "\e[H"  "\e[1~")
(kuro--def-key-sequence kuro--END       "Send End key."       "\e[F"  "\e[4~")
(kuro--def-key-sequence kuro--INSERT    "Send Insert key."    "\e[2~" "\e[2~")
(kuro--def-key-sequence kuro--DELETE    "Send Delete key."    "\e[3~" "\e[3~")
(kuro--def-key-sequence kuro--PAGE-UP   "Send Page Up key."   "\e[5~" "\e[5~")
(kuro--def-key-sequence kuro--PAGE-DOWN "Send Page Down key." "\e[6~" "\e[6~")

;;; Function Keys F1-F12
(kuro--def-key-sequence kuro--F1  "Send F1 key."  "\eOP"   "\eOP")
(kuro--def-key-sequence kuro--F2  "Send F2 key."  "\eOQ"   "\eOQ")
(kuro--def-key-sequence kuro--F3  "Send F3 key."  "\eOR"   "\eOR")
(kuro--def-key-sequence kuro--F4  "Send F4 key."  "\eOS"   "\eOS")
(kuro--def-key-sequence kuro--F5  "Send F5 key."  "\e[15~" "\e[15~")
(kuro--def-key-sequence kuro--F6  "Send F6 key."  "\e[17~" "\e[17~")
(kuro--def-key-sequence kuro--F7  "Send F7 key."  "\e[18~" "\e[18~")
(kuro--def-key-sequence kuro--F8  "Send F8 key."  "\e[19~" "\e[19~")
(kuro--def-key-sequence kuro--F9  "Send F9 key."  "\e[20~" "\e[20~")
(kuro--def-key-sequence kuro--F10 "Send F10 key." "\e[21~" "\e[21~")
(kuro--def-key-sequence kuro--F11 "Send F11 key." "\e[23~" "\e[23~")
(kuro--def-key-sequence kuro--F12 "Send F12 key." "\e[24~" "\e[24~")

;;; Modifier Combinations

(defun kuro--ctrl-modified (char _modifier)
  "Send Ctrl+CHAR.  _MODIFIER is ignored (reserved for future use)."
  (interactive "nChar: \nModifier: ")
  (kuro--send-special (logand char 31)))
;; Note: kuro--send-special already calls kuro--schedule-immediate-render.

(defun kuro--alt-modified (char)
  "Send Alt+CHAR as ESC prefix followed by the character."
  (interactive "nChar: ")
  (kuro--send-key (string ?\e char))
  (kuro--schedule-immediate-render))

(provide 'kuro-input-keys)

;;; kuro-input-keys.el ends here
