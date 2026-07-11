;;; kuro-input-keys-data.el --- Static KKP constants for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Kitty Keyboard Protocol constants shared by `kuro-input-keys.el' and
;; navigation helpers.

;;; Code:

(defconst kuro--kkp-disambiguate  #x01
  "KKP flag for disambiguating escape codes.")
(defconst kuro--kkp-report-events #x02
  "KKP flag: report key press/repeat/release event types.
Not implementable in vanilla Emacs: Emacs delivers only key-press events
to its input loop and exposes no key-release events, so a faithful
press/repeat/release report cannot be synthesized.  Documented here for
completeness; intentionally out of scope.")
(defconst kuro--kkp-all-escape    #x08
  "KKP flag for reporting all keys as escape codes.")

;; KKP modifier bitmask values (Kitty keyboard protocol §Modifiers).
;; The WIRE value transmitted in CSI key;<mod>u is (bitmask + 1); see
;; `kuro--kitty-modifier-offset' and `kuro--encode-kitty-key'.
(defconst kuro--kkp-mod-alt   2  "KKP modifier bit: Alt.")
(defconst kuro--kkp-mod-ctrl  4  "KKP modifier bit: Ctrl.")
(defconst kuro--kkp-mod-super 8  "KKP modifier bit: Super (the s- modifier).")
(defconst kuro--kkp-mod-hyper 16 "KKP modifier bit: Hyper (the H- modifier).")
(defconst kuro--kitty-modifier-offset 1
  "Offset added to the modifier bitmask in the Kitty keyboard protocol.
The Kitty protocol encodes modifiers as (bitmask + 1) on the wire:
no modifier = parameter omitted (implicit 1), shift-only = 2,
alt-only = 3, ctrl-only = 5, super-only = 9, hyper-only = 17, etc.
Reference: https://sw.kovidgoyal.net/kitty/keyboard-protocol/#modifiers")

(defun kuro--encode-kitty-key (key modifiers)
  "Encode KEY with MODIFIERS in Kitty keyboard protocol format.
KEY is a Unicode codepoint integer.
MODIFIERS is a bitmask: shift=1, alt=2, ctrl=4, super=8, hyper=16, meta=32.
With no modifiers, returns CSI KEY u; otherwise CSI KEY ; (MODIFIERS+1) u.
Returns the encoded escape sequence string."
  (if (= modifiers 0)
      (format "\e[%du" key)
    (format "\e[%d;%du" key (+ modifiers kuro--kitty-modifier-offset))))

;; KKP codepoints for functional (non-Unicode) keys.
;; Source: https://sw.kovidgoyal.net/kitty/keyboard-protocol/#functional-keys
(defconst kuro--kkp-cp-up        57352)
(defconst kuro--kkp-cp-down      57353)
(defconst kuro--kkp-cp-left      57350)
(defconst kuro--kkp-cp-right     57351)
(defconst kuro--kkp-cp-home      57356)
(defconst kuro--kkp-cp-end       57357)
(defconst kuro--kkp-cp-insert    57348)
(defconst kuro--kkp-cp-delete    57349)
(defconst kuro--kkp-cp-page-up   57354)
(defconst kuro--kkp-cp-page-down 57355)
(defconst kuro--kkp-cp-f1        57364)
(defconst kuro--kkp-cp-f2        57365)
(defconst kuro--kkp-cp-f3        57366)
(defconst kuro--kkp-cp-f4        57367)
(defconst kuro--kkp-cp-f5        57368)
(defconst kuro--kkp-cp-f6        57369)
(defconst kuro--kkp-cp-f7        57370)
(defconst kuro--kkp-cp-f8        57371)
(defconst kuro--kkp-cp-f9        57372)
(defconst kuro--kkp-cp-f10       57373)
(defconst kuro--kkp-cp-f11       57374)
(defconst kuro--kkp-cp-f12       57375)

;; Shifted function keys F1-F12.
;; Each entry is (EVENT HANDLER LEGACY-SEQUENCE KKP-CODEPOINT):
;;   EVENT          — Emacs event symbol used to build the [S-fN] key vector.
;;   HANDLER        — generated interactive command name.
;;   LEGACY-SEQUENCE— xterm legacy form: F1-F4 use CSI 1;2P..S, F5-F12 use
;;                    CSI <n>;2~ (n = 15/17/18/19/20/21/23/24 matching the
;;                    unshifted F5-F12 numbers).
;;   KKP-CODEPOINT  — Kitty functional-key codepoint, reused from the
;;                    unshifted definitions; with all-escape active the key is
;;                    sent as CSI <cp>;2u (shift wire = shift-bit 1 + offset 1).
(defconst kuro--shifted-fkey-bindings
  `((f1  kuro--S-F1  "\e[1;2P"  ,kuro--kkp-cp-f1)
    (f2  kuro--S-F2  "\e[1;2Q"  ,kuro--kkp-cp-f2)
    (f3  kuro--S-F3  "\e[1;2R"  ,kuro--kkp-cp-f3)
    (f4  kuro--S-F4  "\e[1;2S"  ,kuro--kkp-cp-f4)
    (f5  kuro--S-F5  "\e[15;2~" ,kuro--kkp-cp-f5)
    (f6  kuro--S-F6  "\e[17;2~" ,kuro--kkp-cp-f6)
    (f7  kuro--S-F7  "\e[18;2~" ,kuro--kkp-cp-f7)
    (f8  kuro--S-F8  "\e[19;2~" ,kuro--kkp-cp-f8)
    (f9  kuro--S-F9  "\e[20;2~" ,kuro--kkp-cp-f9)
    (f10 kuro--S-F10 "\e[21;2~" ,kuro--kkp-cp-f10)
    (f11 kuro--S-F11 "\e[23;2~" ,kuro--kkp-cp-f11)
    (f12 kuro--S-F12 "\e[24;2~" ,kuro--kkp-cp-f12))
  "Shifted function keys: (EVENT HANDLER LEGACY-SEQUENCE KKP-CODEPOINT).
Used to generate `kuro--S-F1' .. `kuro--S-F12' senders and bind `[S-fN]'.")

;; Numeric keypad keys.
;; Each entry is (EVENT HANDLER NORMAL-CHAR APPLICATION-SEQUENCE):
;;   EVENT               — Emacs keypad event symbol for the [EVENT] key vector.
;;   HANDLER             — generated interactive command name.
;;   NORMAL-CHAR         — character string sent in DECKPNM (normal) keypad mode.
;;   APPLICATION-SEQUENCE— SS3-prefixed string sent in DECKPAM (application)
;;                         keypad mode.  Mappings follow the VT100 keypad:
;;                         0-9 = ESC O p..y, . = ESC O n, Enter = ESC O M,
;;                         + = ESC O l, - = ESC O m, * = ESC O j, / = ESC O o.
(defconst kuro--keypad-bindings
  '((kp-0        kuro--KP-0        "0" "\eOp")
    (kp-1        kuro--KP-1        "1" "\eOq")
    (kp-2        kuro--KP-2        "2" "\eOr")
    (kp-3        kuro--KP-3        "3" "\eOs")
    (kp-4        kuro--KP-4        "4" "\eOt")
    (kp-5        kuro--KP-5        "5" "\eOu")
    (kp-6        kuro--KP-6        "6" "\eOv")
    (kp-7        kuro--KP-7        "7" "\eOw")
    (kp-8        kuro--KP-8        "8" "\eOx")
    (kp-9        kuro--KP-9        "9" "\eOy")
    (kp-decimal  kuro--KP-DECIMAL  "." "\eOn")
    (kp-enter    kuro--KP-ENTER    "\r" "\eOM")
    (kp-add      kuro--KP-ADD      "+" "\eOl")
    (kp-subtract kuro--KP-SUBTRACT "-" "\eOm")
    (kp-multiply kuro--KP-MULTIPLY "*" "\eOj")
    (kp-divide   kuro--KP-DIVIDE   "/" "\eOo"))
  "Numeric keypad keys: (EVENT HANDLER NORMAL-CHAR APPLICATION-SEQUENCE).
Used to generate `kuro--KP-*' senders and bind the `[kp-*]' events.
Dispatch between NORMAL-CHAR and APPLICATION-SEQUENCE is driven by
`kuro--app-keypad-mode' (DECKPAM/DECKPNM).")

(provide 'kuro-input-keys-data)

;;; kuro-input-keys-data.el ends here
