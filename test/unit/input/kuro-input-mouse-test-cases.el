;;; kuro-input-mouse-test-cases.el --- Mouse input test case data  -*- lexical-binding: t; -*-

;;; Commentary:

;; Data tables used by generated mouse input tests.

;;; Code:

(defconst kuro-input-mouse-test--dispatch-cases
  `((kuro-input-mouse-dispatch-gates-on-mouse-mode
     "kuro--dispatch-mouse-event is a no-op when kuro--mouse-mode is 0."
     0 nil nil 0 0 0 t nil)
    (kuro-input-mouse-dispatch-nil-btn-is-noop
     "kuro--dispatch-mouse-event with nil BTN does not send anything."
     1000 nil nil 0 0 nil t nil)
    (kuro-input-mouse-dispatch-routes-to-sgr-encoder
     "When kuro--mouse-sgr is t, dispatch calls kuro--encode-mouse-sgr."
     1000 t nil 2 3 1 t "\e[<1;3;4M")
    (kuro-input-mouse-dispatch-routes-to-x10-encoder
     "When kuro--mouse-sgr is nil, dispatch calls kuro--encode-mouse (X10 path)."
     1000 nil nil 0 0 0 t ,(format "\e[M%c%c%c" 32 33 33))
    (kuro-input-mouse-dispatch-sgr-scroll-up
     "dispatch-mouse-event in SGR mode sends button=64 scroll-up sequence."
     1000 t nil 0 0 64 t "\e[<64;1;1M")
    (kuro-input-mouse-dispatch-sgr-scroll-down
     "dispatch-mouse-event in SGR mode sends button=65 scroll-down sequence."
     1000 t nil 0 0 65 t "\e[<65;1;1M")
    (kuro-input-mouse-dispatch-x10-release
     "dispatch-mouse-event in X10 mode (press=nil) uses button 3 encoding."
     1000 nil nil 0 0 0 nil ,(format "\e[M%c%c%c" 35 33 33))
    (kuro-input-mouse-dispatch-does-not-send-when-overflow
     "dispatch-mouse-event with X10 and overflow coords sends nothing."
     1000 nil nil 223 0 0 t nil)
    (kuro-input-mouse-dispatch-pixel-mode-uses-sgr-format
     "dispatch-mouse-event with pixel mode uses SGR format with pixel coords."
     1000 nil t 10 20 0 t "\e[<0;10;20M")
    (kuro-input-mouse-dispatch-pixel-mode-release
     "dispatch-mouse-event with pixel mode and press=nil produces lowercase 'm'."
     1000 nil t 5 15 2 nil "\e[<2;5;15m")))

(defconst kuro-input-mouse-test--encode-cases
  `((kuro-input-mouse-mode-1002-enables-encoding
     "kuro--mouse-mode=1002 (button-event) also enables X10 encoding."
     1002 nil nil 0 0 0 t ,(format "\e[M%c%c%c" 32 33 33))
    (kuro-input-mouse-mode-1003-enables-encoding
     "kuro--mouse-mode=1003 (any-event) also enables X10 encoding."
     1003 nil nil 1 1 0 t ,(format "\e[M%c%c%c" 32 34 34))
    (kuro-input-mouse-encode-sgr-button1-press
     "kuro--encode-mouse-sgr with button=1 embeds 1 in the SGR sequence."
     1000 t nil 0 0 1 t "\e[<1;1;1M")
    (kuro-input-mouse-encode-sgr-button2-press
     "kuro--encode-mouse-sgr with button=2 embeds 2 in the SGR sequence."
     1000 t nil 0 0 2 t "\e[<2;1;1M")
    (kuro-input-mouse-encode-sgr-scroll-up-button64
     "kuro--encode-mouse-sgr with button=64 encodes scroll-up correctly."
     1000 t nil 9 4 64 t "\e[<64;10;5M")
    (kuro-input-mouse-encode-sgr-scroll-down-button65
     "kuro--encode-mouse-sgr with button=65 encodes scroll-down correctly."
     1000 t nil 9 4 65 t "\e[<65;10;5M")
    (kuro-input-mouse-sgr-button1-release
     "SGR mode: button=1 release produces ESC[<1;col;rowm."
     1000 t nil 3 7 1 nil "\e[<1;4;8m")
    (kuro-input-mouse-mode-1002-at-x10-limit-returns-nil
     "kuro--mouse-mode=1002 with col1=224 (overflow) returns nil like mode 1000."
     1002 nil nil 223 0 0 t nil)
    (kuro-input-mouse-mode-1003-with-sgr-no-overflow-guard
     "kuro--mouse-mode=1003 with SGR set ignores overflow guard."
     1003 t nil 300 300 0 t "\e[<0;301;301M")
    (kuro-input-mouse-sgr-shift-modifier-button
     "SGR mode: Shift+left-click encodes as button=4 (0 + Shift=4)."
     1000 t nil 0 0 4 t "\e[<4;1;1M")
    (kuro-input-mouse-sgr-meta-modifier-button
     "SGR mode: Meta+left-click encodes as button=8 (0 + Meta=8)."
     1000 t nil 0 0 8 t "\e[<8;1;1M")
    (kuro-input-mouse-sgr-ctrl-modifier-button
     "SGR mode: Ctrl+left-click encodes as button=16 (0 + Ctrl=16)."
     1000 t nil 0 0 16 t "\e[<16;1;1M")
    (kuro-input-mouse-sgr-meta-shift-modifier-button
     "SGR mode: Meta+Shift+left-click encodes as button=12 (0 + Meta=8 + Shift=4)."
     1000 t nil 0 0 12 t "\e[<12;1;1M")
    (kuro-input-mouse-sgr-ctrl-meta-shift-modifier-button
     "SGR mode: Ctrl+Meta+Shift+left-click encodes as button=28 (0+4+8+16)."
     1000 t nil 5 3 28 t "\e[<28;6;4M")
    (kuro-input-mouse-sgr-shift-scroll-up
     "SGR mode: Shift+scroll-up encodes as button=68 (64 + Shift=4)."
     1000 t nil 0 0 68 t "\e[<68;1;1M")
    (kuro-input-mouse-sgr-ctrl-scroll-down
     "SGR mode: Ctrl+scroll-down encodes as button=81 (65 + Ctrl=16)."
     1000 t nil 0 0 81 t "\e[<81;1;1M")
    (kuro-input-mouse-sgr-modifier-release-uses-lowercase-m
     "SGR mode: modifier+button release still uses lowercase 'm' terminator."
     1000 t nil 1 1 4 nil "\e[<4;2;2m")
    (kuro-input-mouse-x10-shift-modifier-btn4-overflow-check
     "X10 mode: Shift+button0 = button=4; btn-byte = 4+32 = 36, within range."
     1000 nil nil 0 0 4 t ,(format "\e[M%c%c%c" 36 33 33))
    (kuro-input-mouse-pixel-mode-modifier-button
     "Pixel mode: modifier+button embeds modifier bits in SGR sequence without offset."
     1000 nil t 120 80 10 t "\e[<10;120;80M")
    (kuro-input-mouse-pixel-sends-pixel-coords
     "Pixel mode reports posn-x-y coordinates (not col+1/row+1)."
     1000 nil t 42 99 0 t "\e[<0;42;99M")
    (kuro-input-mouse-x10-overflow-past-terminal-width-returns-nil
     "X10 mode returns nil when column exceeds the 223-cell limit (past terminal width)."
     1000 nil nil 300 0 0 t nil)
    (kuro-input-mouse-sgr-large-coords-not-clamped
     "SGR mode does not clamp large coordinates; values above 223 pass through."
     1000 t nil 500 300 0 t "\e[<0;501;301M")))

(defconst kuro-input-mouse-test--event-command-cases
  '((kuro-input-mouse-press-unknown-event-type-is-noop
     "kuro--mouse-press sends nothing when event-basic-type returns an unknown symbol."
     1000 nil nil 0 0 mouse-99 kuro--mouse-press nil)
    (kuro-input-mouse-release-unknown-event-type-is-noop
     "kuro--mouse-release sends nothing when event-basic-type returns an unknown symbol."
     1000 nil nil 0 0 mouse-99 kuro--mouse-release nil)
    (kuro-input-mouse-press-mouse1-sends-button0
     "kuro--mouse-press maps mouse-1 event type to button 0 in SGR mode."
     1000 t nil 0 0 mouse-1 kuro--mouse-press "\e[<0;1;1M")
    (kuro-input-mouse-release-mouse2-sends-button1
     "kuro--mouse-release maps mouse-2 event type to button 1 in SGR mode."
     1000 t nil 2 3 mouse-2 kuro--mouse-release "\e[<1;3;4m")
    (kuro-input-mouse-press-mouse3-sends-button2
     "kuro--mouse-press maps mouse-3 event type to button 2 in SGR mode."
     1000 t nil 1 2 mouse-3 kuro--mouse-press "\e[<2;2;3M")
    (kuro-input-mouse-button-code-mouse1-is-zero
     "mouse-1 event basic type maps to button code 0 (left button)."
     1000 t nil 0 0 mouse-1 kuro--mouse-press "\e[<0;1;1M")
    (kuro-input-mouse-button-code-mouse3-is-two
     "mouse-3 event basic type maps to button code 2 (right button)."
     1000 t nil 0 0 mouse-3 kuro--mouse-press "\e[<2;1;1M")))

(defconst kuro-input-mouse-test--scroll-command-cases
  `((kuro-input-mouse-scroll-up-sends-button64-sgr
     "kuro--mouse-scroll-up sends button=64 press in SGR mode."
     1000 t nil 4 7 kuro--mouse-scroll-up "\e[<64;5;8M")
    (kuro-input-mouse-scroll-down-sends-button65-sgr
     "kuro--mouse-scroll-down sends button=65 press in SGR mode."
     1000 t nil 0 0 kuro--mouse-scroll-down "\e[<65;1;1M")
    (kuro-input-mouse-scroll-up-x10-sends-correct-bytes
     "kuro--mouse-scroll-up in X10 mode sends button=64 (btn-byte=96)."
     1000 nil nil 0 0 kuro--mouse-scroll-up ,(format "\e[M%c%c%c" 96 33 33))
    (kuro-input-mouse-scroll-up-mode-off-is-noop
     "kuro--mouse-scroll-up sends nothing when kuro--mouse-mode is 0."
     0 nil nil 0 0 kuro--mouse-scroll-up nil)
    (kuro-input-mouse-scroll-down-mode-off-is-noop
     "kuro--mouse-scroll-down sends nothing when kuro--mouse-mode is 0."
     0 nil nil 0 0 kuro--mouse-scroll-down nil)))

(defconst kuro-input-mouse-test--button-alist-cases
  '((kuro-input-mouse-button-alist-has-mouse-1
     "`kuro--mouse-button-alist' maps `mouse-1' to button index 0."
     mouse-1 0)
    (kuro-input-mouse-button-alist-has-mouse-2
     "`kuro--mouse-button-alist' maps `mouse-2' to button index 1."
     mouse-2 1)
    (kuro-input-mouse-button-alist-has-mouse-3
     "`kuro--mouse-button-alist' maps `mouse-3' to button index 2."
     mouse-3 2)
    (kuro-input-mouse-button-alist-unknown-returns-nil
     "Looking up an unknown event type in `kuro--mouse-button-alist' returns nil."
     mouse-4 nil)))

(provide 'kuro-input-mouse-test-cases)

;;; kuro-input-mouse-test-cases.el ends here
