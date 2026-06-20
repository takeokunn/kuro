;;; kuro-input-keys-test-cases.el --- Shared key input test data  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-input)

(defconst kuro-input-keys-test--cursor-modes '(nil t)
  "Cursor modes exercised by input key sequence tests.")

(defconst kuro-input-keys-test--function-key-sequences
  '((kuro--F1  . "\eOP")
    (kuro--F2  . "\eOQ")
    (kuro--F3  . "\eOR")
    (kuro--F4  . "\eOS")
    (kuro--F5  . "\e[15~")
    (kuro--F6  . "\e[17~")
    (kuro--F7  . "\e[18~")
    (kuro--F8  . "\e[19~")
    (kuro--F9  . "\e[20~")
    (kuro--F10 . "\e[21~")
    (kuro--F11 . "\e[23~")
    (kuro--F12 . "\e[24~"))
  "Function-key handlers and sequences shared by both cursor modes.")

(defconst kuro-input-keys-test--arrow-sequences
  '((kuro--arrow-up    "\e[A" "\eOA")
    (kuro--arrow-down  "\e[B" "\eOB")
    (kuro--arrow-left  "\e[D" "\eOD")
    (kuro--arrow-right "\e[C" "\eOC"))
  "Arrow-key handlers with normal and application cursor sequences.")

(defconst kuro-input-keys-test--navigation-sequences
  '((kuro--HOME      "\e[H"  "\e[1~")
    (kuro--END       "\e[F"  "\e[4~")
    (kuro--INSERT    "\e[2~" "\e[2~")
    (kuro--DELETE    "\e[3~" "\e[3~")
    (kuro--PAGE-UP   "\e[5~" "\e[5~")
    (kuro--PAGE-DOWN "\e[6~" "\e[6~"))
  "Navigation-key handlers with normal and application cursor sequences.")

(defconst kuro-input-keys-test--primary-sequence-cases
  '((kuro-input-keys--f1-sends-correct-sequence
     kuro--F1 nil "\eOP"
     "F1 handler sends SS3 P sequence.")
    (kuro-input-keys--f2-sends-correct-sequence
     kuro--F2 nil "\eOQ"
     "F2 handler sends SS3 Q sequence.")
    (kuro-input-keys--f3-sends-correct-sequence
     kuro--F3 nil "\eOR"
     "F3 handler sends SS3 R sequence.")
    (kuro-input-keys--f4-sends-correct-sequence
     kuro--F4 nil "\eOS"
     "F4 handler sends SS3 S sequence.")
    (kuro-input-keys--f5-sends-correct-sequence
     kuro--F5 nil "\e[15~"
     "F5 handler sends CSI 15~ sequence.")
    (kuro-input-keys--arrow-up-sends-csi-A
     kuro--arrow-up nil "\e[A"
     "Arrow up sends CSI A in normal mode.")
    (kuro-input-keys--arrow-down-sends-csi-B
     kuro--arrow-down nil "\e[B"
     "Arrow down sends CSI B in normal mode.")
    (kuro-input-keys--arrow-left-sends-csi-D
     kuro--arrow-left nil "\e[D"
     "Arrow left sends CSI D in normal mode.")
    (kuro-input-keys--arrow-right-sends-csi-C
     kuro--arrow-right nil "\e[C"
     "Arrow right sends CSI C in normal mode.")
    (kuro-input-keys--arrow-up-app-mode-sends-ss3-A
     kuro--arrow-up t "\eOA"
     "Arrow up sends SS3 A in application cursor keys mode.")
    (kuro-input-keys--arrow-down-app-mode-sends-ss3-B
     kuro--arrow-down t "\eOB"
     "Arrow down sends SS3 B in application cursor keys mode.")
    (kuro-input-keys--arrow-left-app-mode-sends-ss3-D
     kuro--arrow-left t "\eOD"
     "Arrow left sends SS3 D in application cursor keys mode.")
    (kuro-input-keys--arrow-right-app-mode-sends-ss3-C
     kuro--arrow-right t "\eOC"
     "Arrow right sends SS3 C in application cursor keys mode.")
    (kuro-input-keys--home-sends-csi-H
     kuro--HOME nil "\e[H"
     "Home key sends CSI H in normal mode.")
    (kuro-input-keys--end-sends-csi-F
     kuro--END nil "\e[F"
     "End key sends CSI F in normal mode.")
    (kuro-input-keys--home-app-mode-sends-csi-1-tilde
     kuro--HOME t "\e[1~"
     "Home key sends CSI 1~ in application cursor keys mode.")
    (kuro-input-keys--end-app-mode-sends-csi-4-tilde
     kuro--END t "\e[4~"
     "End key sends CSI 4~ in application cursor keys mode.")
    (kuro-input-keys--insert-sends-csi-2-tilde
     kuro--INSERT nil "\e[2~"
     "Insert key sends CSI 2~ sequence.")
    (kuro-input-keys--delete-sends-csi-3-tilde
     kuro--DELETE nil "\e[3~"
     "Delete key sends CSI 3~ sequence.")
    (kuro-input-keys--page-up-sends-csi-5-tilde
     kuro--PAGE-UP nil "\e[5~"
     "Page Up key sends CSI 5~ sequence.")
    (kuro-input-keys--page-down-sends-csi-6-tilde
     kuro--PAGE-DOWN nil "\e[6~"
     "Page Down key sends CSI 6~ sequence."))
  "Primary sequence tests as NAME, FN, MODE, EXPECTED, DOCSTRING.")

(defconst kuro-input-keys-test--ctrl-modified-cases
  '((kuro-input-keys--ctrl-modified-sends-control-byte
     "kuro--ctrl-modified sends the correct control byte (char AND 31)."
     ?a 0 1)
    (kuro-input-keys--ctrl-modified-uppercase-A
     "Ctrl+A (char=?A=65) produces control byte 1 (65 AND 31 = 1)."
     ?A 0 1)
    (kuro-input-keys--ctrl-modified-lowercase-a
     "Ctrl+a (char=?a=97) produces control byte 1 (97 AND 31 = 1)."
     ?a 0 1)
    (kuro-input-keys--ctrl-modified-char-c
     "Ctrl+C (char=?C=67) produces control byte 3 (67 AND 31 = 3)."
     ?C 0 3)
    (kuro-input-keys--ctrl-modified-char-z
     "Ctrl+Z (char=?Z=90) produces control byte 26 (90 AND 31 = 26)."
     ?Z 0 26)
    (kuro-input-keys--ctrl-modified-bracket
     "Ctrl+[ (char=?[=91) produces control byte 27 (ESC) (91 AND 31 = 27)."
     ?\[ 0 27)
    (kuro-input-keys--ctrl-modified-space
     "Ctrl+Space (char=?\\s=32) produces control byte 0 (32 AND 31 = 0)."
     ?\s 0 0))
  "Ctrl-modified send cases as NAME, DOCSTRING, CHAR, MODIFIER, EXPECTED-BYTE.")

(defconst kuro-input-keys-test--alt-modified-cases
  '((kuro-input-keys--alt-modified-sends-esc-prefix
     "kuro--alt-modified sends ESC followed by the character."
     ?x "\ex")
    (kuro-input-keys--alt-modified-sends-esc-a
     "Alt+a sends ESC followed by ?a."
     ?a "\ea")
    (kuro-input-keys--alt-modified-sends-esc-digit
     "Alt+1 sends ESC followed by ?1."
     ?1 "\e1")
    (kuro-input-keys--alt-modified-sends-esc-z
     "Alt+z sends ESC followed by ?z."
     ?z "\ez")
    (kuro-input-keys--alt-modified-sends-esc-space
     "Alt+Space sends ESC followed by a space character."
     ?\s "\e ")
    (kuro-input-keys--alt-modified-sends-esc-dot
     "Alt+. sends ESC followed by a period."
     ?. "\e.")
    (kuro-input-keys--alt-modified-uppercase-a
     "Alt+A (uppercase) sends ESC followed by uppercase A."
     ?A "\eA")
    (kuro-input-keys--alt-modified-uppercase-z
     "Alt+Z (uppercase) sends ESC followed by uppercase Z."
     ?Z "\eZ")
    (kuro-input-keys--alt-modified-sends-esc-backspace
     "Alt+Backspace (char=\\x7f) sends ESC followed by DEL byte."
     ?\x7f "\e\x7f"))
  "Alt-modified send cases as NAME, DOCSTRING, CHAR, EXPECTED.")

(defconst kuro-input-keys-test--same-sequence-navigation-cases
  '((kuro-input-keys--insert-same-in-both-modes
     "INSERT sends CSI 2~ in both normal and application cursor modes."
     kuro--INSERT "\e[2~")
    (kuro-input-keys--delete-same-in-both-modes
     "DELETE sends CSI 3~ in both normal and application cursor modes."
     kuro--DELETE "\e[3~")
    (kuro-input-keys--page-up-same-in-both-modes
     "PAGE-UP sends CSI 5~ in both normal and application cursor modes."
     kuro--PAGE-UP "\e[5~")
    (kuro-input-keys--page-down-same-in-both-modes
     "PAGE-DOWN sends CSI 6~ in both normal and application cursor modes."
     kuro--PAGE-DOWN "\e[6~"))
  "Navigation cases whose sequence is invariant across cursor modes.")

(defconst kuro-input-keys-test--kkp-send-cases
  `((kuro-input-keys--g21-kkp-flags-zero-legacy-arrow
     "With keyboard-flags=0, arrow up sends legacy sequence."
     0
     (kuro-input-keys-test--with-cursor-mode nil
       (kuro--arrow-up))
     "\e[A")
    (kuro-input-keys--g21-kkp-all-escape-arrow-up-csi-u
     "With flag 0x08 (ALL_ESCAPE), arrow up sends KKP codepoint CSI 57352;1u."
     #x08
     (kuro--arrow-up)
     ,(format "\e[%d;1u" kuro--kkp-cp-up))
    (kuro-input-keys--g21-kkp-all-escape-f1-csi-u
     "With flag 0x08, F1 sends CSI 57364;1u."
     #x08
     (kuro--F1)
     ,(format "\e[%d;1u" kuro--kkp-cp-f1))
    (kuro-input-keys--g21-kkp-all-escape-home-csi-u
     "With flag 0x08, Home sends CSI 57356;1u."
     #x08
     (kuro--HOME)
     ,(format "\e[%d;1u" kuro--kkp-cp-home))
    (kuro-input-keys--g21-kkp-all-escape-delete-csi-u
     "With flag 0x08, Delete sends CSI 57349;1u."
     #x08
     (kuro--DELETE)
     ,(format "\e[%d;1u" kuro--kkp-cp-delete))
    (kuro-input-keys--g21-kkp-only-disambiguate-arrow-legacy
     "With only flag 0x01 (DISAMBIGUATE), arrow keys still use legacy encoding."
     #x01
     (kuro-input-keys-test--with-cursor-mode nil
       (kuro--arrow-down))
     "\e[B")
    (kuro-input-keys--g21-kkp-ctrl-all-escape-sends-csi-u
     "With flag 0x08, Ctrl+A sends CSI 65;5u."
     #x08
     (kuro--ctrl-modified ?A nil)
     "\e[65;5u")
    (kuro-input-keys--g21-kkp-ctrl-zero-flags-sends-c0
     "With flags=0, Ctrl+A sends raw C0 control byte."
     0
     (kuro--ctrl-modified ?A nil)
     "\x01")
    (kuro-input-keys--g21-kkp-alt-disambiguate-sends-csi-u
     "With flag 0x01 (DISAMBIGUATE), Alt+a sends CSI 97;3u instead of ESC+a."
     #x01
     (kuro--alt-modified ?a)
     "\e[97;3u")
    (kuro-input-keys--g21-kkp-alt-zero-flags-sends-esc-prefix
     "With flags=0, Alt+a sends legacy ESC+a."
     0
     (kuro--alt-modified ?a)
     "\ea")
    (kuro-input-keys--g21-kkp-super-disambiguate-sends-csi-9u
     "With flag 0x01, Super+x sends CSI 120;9u (super bit 8, wire 9)."
     #x01
     (kuro--super-modified ?x)
     "\e[120;9u")
    (kuro-input-keys--g21-kkp-super-all-escape-sends-csi-9u
     "With flag 0x08, Super+a sends CSI 97;9u."
     #x08
     (kuro--super-modified ?a)
     "\e[97;9u")
    (kuro-input-keys--g21-kkp-hyper-disambiguate-sends-csi-17u
     "With flag 0x01, Hyper+x sends CSI 120;17u (hyper bit 16, wire 17)."
     #x01
     (kuro--hyper-modified ?x)
     "\e[120;17u")
    (kuro-input-keys--g21-kkp-hyper-all-escape-sends-csi-17u
     "With flag 0x08, Hyper+a sends CSI 97;17u."
     #x08
     (kuro--hyper-modified ?a)
     "\e[97;17u")
    (kuro-input-keys--g21-kkp-super-zero-flags-sends-nothing
     "With flags=0, Super+a sends nothing (no legacy encoding)."
     0
     (kuro--super-modified ?a)
     nil)
    (kuro-input-keys--g21-kkp-hyper-zero-flags-sends-nothing
     "With flags=0, Hyper+a sends nothing (no legacy encoding)."
     0
     (kuro--hyper-modified ?a)
     nil))
  "KKP send behavior cases as NAME, DOCSTRING, FLAGS, BODY, EXPECTED.")

(defconst kuro-input-keys-test--encode-kitty-key-cases
  '((kuro-input-keys--g21-kkp-encode-kitty-key-no-modifier
     "kuro--encode-kitty-key with modifier 0 produces ESC [ key u."
     97 0 "\e[97u")
    (kuro-input-keys--g21-kkp-encode-kitty-key-with-ctrl
     "kuro--encode-kitty-key with ctrl modifier encodes as ESC [ key ; 5 u."
     65 4 "\e[65;5u")
    (kuro-input-keys--g21-kkp-encode-kitty-key-shift-only
     "kuro--encode-kitty-key with shift (1) encodes wire 2: ESC [ key ; 2 u."
     97 1 "\e[97;2u")
    (kuro-input-keys--g21-kkp-encode-kitty-key-alt-only
     "kuro--encode-kitty-key with alt (2) encodes wire 3: ESC [ key ; 3 u."
     97 2 "\e[97;3u")
    (kuro-input-keys--g21-kkp-encode-kitty-key-super-only
     "kuro--encode-kitty-key with super (8) encodes wire 9: ESC [ key ; 9 u."
     97 8 "\e[97;9u")
    (kuro-input-keys--g21-kkp-encode-kitty-key-hyper-only
     "kuro--encode-kitty-key with hyper (16) encodes wire 17: ESC [ key ; 17 u."
     97 16 "\e[97;17u")
    (kuro-input-keys--g21-kkp-encode-kitty-key-meta-only
     "kuro--encode-kitty-key with meta (32) encodes wire 33: ESC [ key ; 33 u."
     97 32 "\e[97;33u")
    (kuro-input-keys--g21-kkp-encode-kitty-key-ctrl-super
     "kuro--encode-kitty-key with ctrl+super (4+8=12) encodes wire 13."
     97 12 "\e[97;13u")
    (kuro-input-keys--g21-kkp-encode-kitty-key-shift-hyper
     "kuro--encode-kitty-key with shift+hyper (1+16=17) encodes wire 18."
     97 17 "\e[97;18u"))
  "Encode-kitty-key cases as NAME, DOCSTRING, KEY, MODIFIER, EXPECTED.")

(defconst kuro-input-keys-test--kkp-flag-p-cases
  '((kuro-input-keys--g22-kkp-flag-p-returns-t-when-bit-set
     "kuro--kkp-flag-p returns non-nil when the flag bit is set in keyboard-flags."
     kuro--kkp-disambiguate
     kuro--kkp-disambiguate
     t)
    (kuro-input-keys--g22-kkp-flag-p-returns-nil-when-bit-clear
     "kuro--kkp-flag-p returns nil when the flag bit is not set."
     0
     kuro--kkp-disambiguate
     nil)
    (kuro-input-keys--g22-kkp-flag-p-checks-specific-bit-only
     "kuro--kkp-flag-p is false for a clear bit when another bit is set."
     kuro--kkp-disambiguate
     kuro--kkp-all-escape
     nil))
  "KKP flag predicate cases as NAME, DOCSTRING, FLAGS, FLAG, EXPECTED.")

(provide 'kuro-input-keys-test-cases)
;;; kuro-input-keys-test-cases.el ends here
