;;; kuro-input-mouse-test-2.el --- ERT tests for kuro-input-mouse.el — Groups 14-22  -*-  lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-input-mouse-test-support)


(kuro-input-mouse-test--deftest-dispatch-cases
 kuro-input-mouse-dispatch-sgr-scroll-up
 kuro-input-mouse-dispatch-sgr-scroll-down
 kuro-input-mouse-dispatch-x10-release
 kuro-input-mouse-dispatch-does-not-send-when-overflow)

;;; Group 15: kuro--mouse-coords — cell mode at origin

(ert-deftest kuro-input-mouse-coords-cell-mode-at-origin ()
  "In cell mode (pixel-mode nil), position (0,0) maps to col1=1, row1=1."
  (with-temp-buffer
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 0 0
      (let ((coords (kuro--mouse-coords 'fake-event)))
        (should (= (car coords) 1))
        (should (= (cdr coords) 1))))))

;;; Group 16: kuro--encode-mouse-sgr — pixel mode with press=nil

(ert-deftest kuro-input-mouse-encode-sgr-pixel-release ()
  "kuro--encode-mouse-sgr in pixel mode with press=nil produces lowercase 'm'."
  (with-temp-buffer
    (setq-local kuro--mouse-pixel-mode t)
    (kuro-mouse-test--with-event 50 80
      ;; pixel mode: no +1 offset; col=50, row=80
      (let ((result (kuro--encode-mouse-sgr 'fake-event 1 nil)))
        (should (equal result "\e[<1;50;80m"))))))

;;; Group 17: kuro--encode-mouse — SGR path with button=1 release

(kuro-input-mouse-test--deftest-encode-cases
 kuro-input-mouse-sgr-button1-release)

;;; Group 18: kuro--dispatch-mouse-event — pixel mode routing

(kuro-input-mouse-test--deftest-dispatch-cases
 kuro-input-mouse-dispatch-pixel-mode-uses-sgr-format
 kuro-input-mouse-dispatch-pixel-mode-release)

;;; Group 19: kuro--encode-mouse — mode 1002/1003 at boundary coordinates

(kuro-input-mouse-test--deftest-encode-cases
 kuro-input-mouse-mode-1002-at-x10-limit-returns-nil
 kuro-input-mouse-mode-1003-with-sgr-no-overflow-guard)

;;; Group 20: kuro--def-mouse-cmd generated handlers — unknown event type
;;  kuro--mouse-press and kuro--mouse-release use alist-get over event-basic-type;
;;  an unrecognised type produces nil btn, which must be a no-op.

(ert-deftest kuro-input-mouse-button-alist-covers-all-three-buttons ()
  "`kuro--mouse-button-alist' maps mouse-1/2/3 to button indices 0/1/2."
  (should (= (alist-get 'mouse-1 kuro--mouse-button-alist) 0))
  (should (= (alist-get 'mouse-2 kuro--mouse-button-alist) 1))
  (should (= (alist-get 'mouse-3 kuro--mouse-button-alist) 2)))

(kuro-input-mouse-test--deftest-event-command-cases
 kuro-input-mouse-press-unknown-event-type-is-noop
 kuro-input-mouse-release-unknown-event-type-is-noop
 kuro-input-mouse-press-mouse1-sends-button0
 kuro-input-mouse-release-mouse2-sends-button1
 kuro-input-mouse-press-mouse3-sends-button2)

(kuro-input-mouse-test--deftest-scroll-command-cases
 kuro-input-mouse-scroll-up-sends-button64-sgr
 kuro-input-mouse-scroll-down-sends-button65-sgr
 kuro-input-mouse-scroll-up-x10-sends-correct-bytes
 kuro-input-mouse-scroll-up-mode-off-is-noop
 kuro-input-mouse-scroll-down-mode-off-is-noop)


;;; Group 21: kuro--encode-mouse — modifier button bits (Shift/Meta/Ctrl)
;;  The terminal protocol encodes modifier keys by adding to the button number:
;;  +4 = Shift, +8 = Meta, +16 = Ctrl. These compound values must be
;;  embedded verbatim in SGR sequences (no overflow guard applies).

(kuro-input-mouse-test--deftest-encode-cases
 kuro-input-mouse-sgr-shift-modifier-button
 kuro-input-mouse-sgr-meta-modifier-button
 kuro-input-mouse-sgr-ctrl-modifier-button
 kuro-input-mouse-sgr-meta-shift-modifier-button
 kuro-input-mouse-sgr-ctrl-meta-shift-modifier-button
 kuro-input-mouse-sgr-shift-scroll-up
 kuro-input-mouse-sgr-ctrl-scroll-down
 kuro-input-mouse-sgr-modifier-release-uses-lowercase-m
 kuro-input-mouse-x10-shift-modifier-btn4-overflow-check
 kuro-input-mouse-pixel-mode-modifier-button)

;;; Group 22: kuro--mouse-button-to-code, col-row extraction, clamping

(kuro-input-mouse-test--deftest-event-command-cases
 kuro-input-mouse-button-code-mouse1-is-zero
 kuro-input-mouse-button-code-mouse3-is-two)

(ert-deftest kuro-input-mouse-scroll-up-button-code-is-64 ()
  "kuro--mouse-scroll-up encodes as button 64 (scroll-up) in X10 format."
  (kuro-input-mouse-test--with-send 1000 nil nil 0 0
    (kuro--mouse-scroll-up)
    ;; X10: btn-byte = 64+32 = 96
    (should (= (aref sent 3) 96))))

(ert-deftest kuro-input-mouse-scroll-down-button-code-is-65 ()
  "kuro--mouse-scroll-down encodes as button 65 (scroll-down) in X10 format."
  (kuro-input-mouse-test--with-send 1000 nil nil 0 0
    (kuro--mouse-scroll-down)
    ;; X10: btn-byte = 65+32 = 97
    (should (= (aref sent 3) 97))))

(ert-deftest kuro-input-mouse-x10-format-is-esclm-bxy ()
  "X10 encoding produces ESC[M followed by three bytes (btn, col, row)."
  (kuro-mouse-test--with-encode-buffer 1000 nil nil 2 5
    (let ((result (kuro--encode-mouse 'fake-event 0 t)))
      ;; Prefix is ESC[M (3 chars) + 3 byte values = 6 chars total
      (should (string-prefix-p "\e[M" result))
      (should (= (length result) 6)))))

(ert-deftest kuro-input-mouse-sgr-press-format-is-esclangle ()
  "SGR format for press uses ESC[< prefix and uppercase M terminator."
  (kuro-mouse-test--with-encode-buffer 1000 t nil 0 0
    (let ((result (kuro--encode-mouse 'fake-event 0 t)))
      (should (string-prefix-p "\e[<" result))
      (should (string-suffix-p "M" result)))))

(ert-deftest kuro-input-mouse-sgr-release-format-uses-lowercase-m ()
  "SGR format for release uses lowercase m terminator, not uppercase M."
  (kuro-mouse-test--with-encode-buffer 1000 t nil 0 0
    (let ((press-result   (kuro--encode-mouse 'fake-event 0 t))
          (release-result (kuro--encode-mouse 'fake-event 0 nil)))
      (should (string-suffix-p "M" press-result))
      (should (string-suffix-p "m" release-result))
      (should-not (string-suffix-p "m" press-result)))))

(kuro-input-mouse-test--deftest-encode-cases
 kuro-input-mouse-pixel-sends-pixel-coords)

(ert-deftest kuro-input-mouse-col-row-extraction-cell-mode ()
  "kuro--mouse-coords extracts posn-col-row and adds 1 to each coordinate."
  (with-temp-buffer
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 7 13
      (let ((coords (kuro--mouse-coords 'fake-event)))
        ;; 0-based (7,13) → 1-based (8,14)
        (should (= (car coords) 8))
        (should (= (cdr coords) 14))))))

(kuro-input-mouse-test--deftest-encode-cases
 kuro-input-mouse-x10-overflow-past-terminal-width-returns-nil
 kuro-input-mouse-sgr-large-coords-not-clamped)

;;; Group 23: kuro--mouse-scroll-up/down scrollback fallback path

(provide 'kuro-input-mouse-test-2)
;;; kuro-input-mouse-test-2.el ends here
