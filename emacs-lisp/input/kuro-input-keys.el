;;; kuro-input-keys.el --- Special key handlers for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

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

;; kuro--app-keypad-mode is a defvar-permanent-local in kuro-input-send.el.
;; Forward-declare to silence byte-compiler (used by keypad senders below).
(defvar kuro--app-keypad-mode nil
  "Forward reference; defvar-permanent-local in kuro-input-send.el.")


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

;;; Shifted Function Keys S-F1..S-F12
;;
;; Generated from `kuro--shifted-fkey-bindings'.  Legacy form: F1-F4 use
;; CSI 1;2P..S, F5-F12 use CSI <n>;2~.  With KKP all-escape active, the
;; canonical CSI <codepoint>;2u form is sent (shift wire = 2).
(defmacro kuro--define-shifted-fkeys ()
  "Generate `kuro--S-F1' .. `kuro--S-F12' from `kuro--shifted-fkey-bindings'."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (let ((name (nth 1 entry))
                (legacy (nth 2 entry))
                (kkp-cp (nth 3 entry)))
            `(kuro--def-shifted-fkey ,name ,legacy ,kkp-cp
               ,(format "Send Shift+%s key." (upcase (symbol-name (nth 0 entry)))))))
        kuro--shifted-fkey-bindings)))
(kuro--define-shifted-fkeys)

;;; Numeric Keypad Keys KP-0..KP-9, kp-decimal/enter/add/subtract/multiply/divide
;;
;; Generated from `kuro--keypad-bindings'.  Each sends the plain character in
;; normal keypad mode (DECKPNM) or the SS3-prefixed application form in
;; application keypad mode (DECKPAM), dispatched on `kuro--app-keypad-mode'.
(defmacro kuro--define-keypad-keys ()
  "Generate `kuro--KP-*' senders from `kuro--keypad-bindings'."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (let ((name (nth 1 entry))
                (normal (nth 2 entry))
                (application (nth 3 entry)))
            `(kuro--def-keypad-key ,name ,normal ,application
               ,(format "Send keypad %s key." (symbol-name (nth 0 entry))))))
        kuro--keypad-bindings)))
(kuro--define-keypad-keys)

;;; Modifier Combinations
;;
;; All KKP modifier encoding is unified through `kuro--encode-kitty-key'
;; (kuro-input-keys-data.el), which applies the (bitmask + 1) wire offset.
;; This keeps Ctrl/Alt/Super/Hyper encoding identical and eliminates the
;; previously-inlined `format "\e[%d;Nu"' duplicates.

(defun kuro--ctrl-modified (char _modifier)
  "Send Ctrl+CHAR.  _MODIFIER is ignored (reserved for future use).
With KKP REPORT_ALL_KEYS flag (0x08), encodes as CSI char;5u (ctrl bit,
wire 4+1=5) via `kuro--encode-kitty-key' so the app can distinguish
Ctrl+I from Tab, Ctrl+M from Enter, etc.  Otherwise sends the raw C0 byte."
  (interactive "nChar: \nModifier: ")
  (kuro--with-kkp-all-escape (kuro--encode-kitty-key char kuro--kkp-mod-ctrl)
    (kuro--send-special (logand char 31))))

(defun kuro--alt-modified (char)
  "Send Alt+CHAR.
With KKP DISAMBIGUATE flag (0x01), encodes as CSI char;3u (alt bit,
wire 2+1=3) via `kuro--encode-kitty-key' so the app receives unambiguous
Alt+key events without escape-prefix ambiguity.
Without KKP, sends the legacy ESC prefix followed by CHAR."
  (interactive "nChar: ")
  (if (kuro--kkp-flag-p kuro--kkp-disambiguate)
      (kuro--send-key (kuro--encode-kitty-key char kuro--kkp-mod-alt))
    (kuro--send-key (string ?\e char)))
  (kuro--schedule-immediate-render))

(defun kuro--super-modified (char)
  "Send Super+CHAR (the s- modifier) in Kitty keyboard protocol form.
With any KKP flag active (DISAMBIGUATE 0x01 or ALL_ESCAPE 0x08), encodes
as CSI char;9u (super bit 8, wire 8+1=9) via `kuro--encode-kitty-key'.
Vanilla terminals have no legacy encoding for Super, so without KKP the
keypress is dropped (no bytes sent)."
  (interactive "nChar: ")
  (when (or (kuro--kkp-flag-p kuro--kkp-disambiguate)
            (kuro--kkp-flag-p kuro--kkp-all-escape))
    (kuro--send-key (kuro--encode-kitty-key char kuro--kkp-mod-super))
    (kuro--schedule-immediate-render)))

(defun kuro--hyper-modified (char)
  "Send Hyper+CHAR (the H- modifier) in Kitty keyboard protocol form.
With any KKP flag active (DISAMBIGUATE 0x01 or ALL_ESCAPE 0x08), encodes
as CSI char;17u (hyper bit 16, wire 16+1=17) via `kuro--encode-kitty-key'.
Vanilla terminals have no legacy encoding for Hyper, so without KKP the
keypress is dropped (no bytes sent)."
  (interactive "nChar: ")
  (when (or (kuro--kkp-flag-p kuro--kkp-disambiguate)
            (kuro--kkp-flag-p kuro--kkp-all-escape))
    (kuro--send-key (kuro--encode-kitty-key char kuro--kkp-mod-hyper))
    (kuro--schedule-immediate-render)))

(provide 'kuro-input-keys)

;;; kuro-input-keys.el ends here
