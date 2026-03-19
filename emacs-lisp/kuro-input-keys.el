;;; kuro-input-keys.el --- Special key handlers for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

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

;;; Arrow Keys (Normal and Application Mode)

(defun kuro--arrow-up ()
  "Send arrow up key."
  (interactive)
  (kuro--send-key-sequence "\e[A" "\eOA"))

(defun kuro--arrow-down ()
  "Send arrow down key."
  (interactive)
  (kuro--send-key-sequence "\e[B" "\eOB"))

(defun kuro--arrow-left ()
  "Send arrow left key."
  (interactive)
  (kuro--send-key-sequence "\e[D" "\eOD"))

(defun kuro--arrow-right ()
  "Send arrow right key."
  (interactive)
  (kuro--send-key-sequence "\e[C" "\eOC"))

;;; Home/End/Page Keys

(defun kuro--HOME ()
  "Send Home key."
  (interactive)
  (kuro--send-key-sequence "\e[H" "\e[1~"))

(defun kuro--END ()
  "Send End key."
  (interactive)
  (kuro--send-key-sequence "\e[F" "\e[4~"))

(defun kuro--INSERT ()
  "Send Insert key."
  (interactive)
  (kuro--send-key-sequence "\e[2~" "\e[2~"))

(defun kuro--DELETE ()
  "Send Delete key."
  (interactive)
  (kuro--send-key-sequence "\e[3~" "\e[3~"))

(defun kuro--PAGE-UP ()
  "Send Page Up key."
  (interactive)
  (kuro--send-key-sequence "\e[5~" "\e[5~"))

(defun kuro--PAGE-DOWN ()
  "Send Page Down key."
  (interactive)
  (kuro--send-key-sequence "\e[6~" "\e[6~"))

;;; Function Keys F1-F12

(defun kuro--F1 ()  "Send F1 key."  (interactive) (kuro--send-key-sequence "\eOP"    "\eOP"))
(defun kuro--F2 ()  "Send F2 key."  (interactive) (kuro--send-key-sequence "\eOQ"    "\eOQ"))
(defun kuro--F3 ()  "Send F3 key."  (interactive) (kuro--send-key-sequence "\eOR"    "\eOR"))
(defun kuro--F4 ()  "Send F4 key."  (interactive) (kuro--send-key-sequence "\eOS"    "\eOS"))
(defun kuro--F5 ()  "Send F5 key."  (interactive) (kuro--send-key-sequence "\e[15~"  "\e[15~"))
(defun kuro--F6 ()  "Send F6 key."  (interactive) (kuro--send-key-sequence "\e[17~"  "\e[17~"))
(defun kuro--F7 ()  "Send F7 key."  (interactive) (kuro--send-key-sequence "\e[18~"  "\e[18~"))
(defun kuro--F8 ()  "Send F8 key."  (interactive) (kuro--send-key-sequence "\e[19~"  "\e[19~"))
(defun kuro--F9 ()  "Send F9 key."  (interactive) (kuro--send-key-sequence "\e[20~"  "\e[20~"))
(defun kuro--F10 () "Send F10 key." (interactive) (kuro--send-key-sequence "\e[21~"  "\e[21~"))
(defun kuro--F11 () "Send F11 key." (interactive) (kuro--send-key-sequence "\e[23~"  "\e[23~"))
(defun kuro--F12 () "Send F12 key." (interactive) (kuro--send-key-sequence "\e[24~"  "\e[24~"))

;;; Modifier Combinations

(defun kuro--ctrl-modified (char modifier)
  "Send Ctrl+CHAR.  MODIFIER is ignored (reserved for future use)."
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
