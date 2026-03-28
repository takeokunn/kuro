;;; kuro-input-mouse-ext-test.el --- Extended tests for kuro-input-mouse.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; Extended ERT tests for kuro-input-mouse.el (Groups 19–22).
;; Split from kuro-input-mouse-test.el for file-size management.
;;
;; Covers: mode 1002/1003 boundary coords, SGR modifier bits,
;; kuro--mouse-button-to-code extraction, col-row extraction, and clamping.
;; Groups 23–24 are in kuro-input-mouse-ext2-test.el.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; kuro-input-mouse requires kuro-ffi at load time.  Stub the FFI symbols
;; it uses so the file loads in a batch/test environment without the module.
(unless (fboundp 'kuro--send-key)
  (defalias 'kuro--send-key (lambda (_data) nil)))
(unless (fboundp 'kuro--schedule-immediate-render)
  (defalias 'kuro--schedule-immediate-render (lambda () nil)))
(unless (fboundp 'kuro--mouse-mode-query)
  (defalias 'kuro--mouse-mode-query (lambda () 0)))
(unless (fboundp 'kuro--scroll-up)
  (defalias 'kuro--scroll-up (lambda (_n) nil)))
(unless (fboundp 'kuro--scroll-down)
  (defalias 'kuro--scroll-down (lambda (_n) nil)))
(unless (fboundp 'kuro--get-scroll-offset)
  (defalias 'kuro--get-scroll-offset (lambda () 0)))
(unless (fboundp 'kuro--render-cycle)
  (defalias 'kuro--render-cycle (lambda () nil)))
(unless (fboundp 'kuro--update-scroll-indicator)
  (defalias 'kuro--update-scroll-indicator (lambda () nil)))

(require 'kuro-input-mouse)


;;; Test helpers

(defmacro kuro-input-mouse-test--with-send (mode sgr pixel col row &rest body)
  "Execute BODY with mouse stubs installed; bind `sent' to capture kuro--send-key arg.
MODE is kuro--mouse-mode, SGR is kuro--mouse-sgr, PIXEL is kuro--mouse-pixel-mode.
COL and ROW are the cell coords returned by posn-col-row (and posn-x-y)."
  (declare (indent 5))
  `(with-temp-buffer
     (setq-local kuro--mouse-mode ,mode
                 kuro--mouse-sgr ,sgr
                 kuro--mouse-pixel-mode ,pixel)
     (let ((sent nil))
       (cl-letf (((symbol-function 'kuro--send-key)
                  (lambda (s) (setq sent s)))
                 ((symbol-function 'event-start)
                  (lambda (_ev) 'fake-pos))
                 ((symbol-function 'posn-col-row)
                  (lambda (_pos) (cons ,col ,row)))
                 ((symbol-function 'posn-x-y)
                  (lambda (_pos) (cons ,col ,row))))
         ,@body))))

(defmacro kuro-input-mouse-test--with-send-and-type (mode sgr pixel col row event-type &rest body)
  "Like `kuro-input-mouse-test--with-send' but also stubs `event-basic-type' to return EVENT-TYPE."
  (declare (indent 6))
  `(with-temp-buffer
     (setq-local kuro--mouse-mode ,mode
                 kuro--mouse-sgr ,sgr
                 kuro--mouse-pixel-mode ,pixel)
     (let ((sent nil))
       (cl-letf (((symbol-function 'kuro--send-key)
                  (lambda (s) (setq sent s)))
                 ((symbol-function 'event-basic-type)
                  (lambda (_ev) ,event-type))
                 ((symbol-function 'event-start)
                  (lambda (_ev) 'fake-pos))
                 ((symbol-function 'posn-col-row)
                  (lambda (_pos) (cons ,col ,row)))
                 ((symbol-function 'posn-x-y)
                  (lambda (_pos) (cons ,col ,row))))
         ,@body))))

(defmacro kuro-mouse-test--with-event (col row &rest body)
  "Execute BODY with event-start, posn-col-row, and posn-x-y stubbed.
COL and ROW are the 0-based cell coordinates posn-col-row returns.
posn-x-y returns the same values as pixel coordinates for pixel-mode tests."
  (declare (indent 2))
  `(cl-letf (((symbol-function 'event-start)
               (lambda (_ev) 'fake-pos))
              ((symbol-function 'posn-col-row)
               (lambda (_pos) (cons ,col ,row)))
              ((symbol-function 'posn-x-y)
               (lambda (_pos) (cons ,col ,row))))
     ,@body))


;;; Group 19: kuro--encode-mouse — mode 1002/1003 at boundary coordinates

(ert-deftest kuro-input-mouse-mode-1002-at-x10-limit-returns-nil ()
  "kuro--mouse-mode=1002 with col1=224 (overflow) returns nil like mode 1000."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1002)
    (setq-local kuro--mouse-sgr nil)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 223 0
      (should-not (kuro--encode-mouse 'fake-event 0 t)))))

(ert-deftest kuro-input-mouse-mode-1003-with-sgr-no-overflow-guard ()
  "kuro--mouse-mode=1003 with SGR set ignores overflow guard."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1003)
    (setq-local kuro--mouse-sgr t)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 300 300
      ;; col1=301, row1=301 — SGR has no overflow guard
      (let ((result (kuro--encode-mouse 'fake-event 0 t)))
        (should (equal result "\e[<0;301;301M"))))))

;;; Group 20: kuro--def-mouse-cmd generated handlers — unknown event type
;;  kuro--mouse-press and kuro--mouse-release use pcase over event-basic-type;
;;  an unrecognised type produces nil btn, which must be a no-op.

(ert-deftest kuro-input-mouse-press-unknown-event-type-is-noop ()
  "kuro--mouse-press sends nothing when event-basic-type returns an unknown symbol."
  (kuro-input-mouse-test--with-send-and-type 1000 nil nil 0 0 'mouse-99
    (kuro--mouse-press)
    (should-not sent)))

(ert-deftest kuro-input-mouse-release-unknown-event-type-is-noop ()
  "kuro--mouse-release sends nothing when event-basic-type returns an unknown symbol."
  (kuro-input-mouse-test--with-send-and-type 1000 nil nil 0 0 'mouse-99
    (kuro--mouse-release)
    (should-not sent)))

(ert-deftest kuro-input-mouse-press-mouse1-sends-button0 ()
  "kuro--mouse-press maps mouse-1 event type to button 0 in SGR mode."
  (kuro-input-mouse-test--with-send-and-type 1000 t nil 0 0 'mouse-1
    (kuro--mouse-press)
    ;; SGR: button=0, col1=1, row1=1, press → M
    (should (equal sent "\e[<0;1;1M"))))

(ert-deftest kuro-input-mouse-release-mouse2-sends-button1 ()
  "kuro--mouse-release maps mouse-2 event type to button 1 in SGR mode."
  (kuro-input-mouse-test--with-send-and-type 1000 t nil 2 3 'mouse-2
    (kuro--mouse-release)
    ;; SGR: button=1, col1=3, row1=4, release → m
    (should (equal sent "\e[<1;3;4m"))))

(ert-deftest kuro-input-mouse-scroll-up-sends-button64-sgr ()
  "kuro--mouse-scroll-up sends button=64 press in SGR mode."
  (kuro-input-mouse-test--with-send 1000 t nil 4 7
    (kuro--mouse-scroll-up)
    ;; SGR: button=64, col1=5, row1=8, press → M
    (should (equal sent "\e[<64;5;8M"))))

(ert-deftest kuro-input-mouse-scroll-down-sends-button65-sgr ()
  "kuro--mouse-scroll-down sends button=65 press in SGR mode."
  (kuro-input-mouse-test--with-send 1000 t nil 0 0
    (kuro--mouse-scroll-down)
    ;; SGR: button=65, col1=1, row1=1, press → M
    (should (equal sent "\e[<65;1;1M"))))

(ert-deftest kuro-input-mouse-scroll-up-x10-sends-correct-bytes ()
  "kuro--mouse-scroll-up in X10 mode sends button=64 (btn-byte=96)."
  (kuro-input-mouse-test--with-send 1000 nil nil 0 0
    (kuro--mouse-scroll-up)
    ;; X10: btn-byte = 64+32 = 96, col-byte = 1+32 = 33, row-byte = 1+32 = 33
    (should (equal sent (format "\e[M%c%c%c" 96 33 33)))))

(ert-deftest kuro-input-mouse-press-mouse3-sends-button2 ()
  "kuro--mouse-press maps mouse-3 event type to button 2 in SGR mode."
  (kuro-input-mouse-test--with-send-and-type 1000 t nil 1 2 'mouse-3
    (kuro--mouse-press)
    ;; SGR: button=2, col1=2, row1=3, press → M
    (should (equal sent "\e[<2;2;3M"))))

(ert-deftest kuro-input-mouse-scroll-up-mode-off-is-noop ()
  "kuro--mouse-scroll-up sends nothing when kuro--mouse-mode is 0."
  (kuro-input-mouse-test--with-send 0 nil nil 0 0
    (kuro--mouse-scroll-up)
    (should-not sent)))

(ert-deftest kuro-input-mouse-scroll-down-mode-off-is-noop ()
  "kuro--mouse-scroll-down sends nothing when kuro--mouse-mode is 0."
  (kuro-input-mouse-test--with-send 0 nil nil 0 0
    (kuro--mouse-scroll-down)
    (should-not sent)))


;;; Group 21: kuro--encode-mouse — modifier button bits (Shift/Meta/Ctrl)
;;  The terminal protocol encodes modifier keys by adding to the button number:
;;  +4 = Shift, +8 = Meta, +16 = Ctrl. These compound values must be
;;  embedded verbatim in SGR sequences (no overflow guard applies).

(ert-deftest kuro-input-mouse-sgr-shift-modifier-button ()
  "SGR mode: Shift+left-click encodes as button=4 (0 + Shift=4)."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr t)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 0 0
      (should (equal (kuro--encode-mouse 'fake-event 4 t) "\e[<4;1;1M")))))

(ert-deftest kuro-input-mouse-sgr-meta-modifier-button ()
  "SGR mode: Meta+left-click encodes as button=8 (0 + Meta=8)."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr t)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 0 0
      (should (equal (kuro--encode-mouse 'fake-event 8 t) "\e[<8;1;1M")))))

(ert-deftest kuro-input-mouse-sgr-ctrl-modifier-button ()
  "SGR mode: Ctrl+left-click encodes as button=16 (0 + Ctrl=16)."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr t)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 0 0
      (should (equal (kuro--encode-mouse 'fake-event 16 t) "\e[<16;1;1M")))))

(ert-deftest kuro-input-mouse-sgr-meta-shift-modifier-button ()
  "SGR mode: Meta+Shift+left-click encodes as button=12 (0 + Meta=8 + Shift=4)."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr t)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 0 0
      (should (equal (kuro--encode-mouse 'fake-event 12 t) "\e[<12;1;1M")))))

(ert-deftest kuro-input-mouse-sgr-ctrl-meta-shift-modifier-button ()
  "SGR mode: Ctrl+Meta+Shift+left-click encodes as button=28 (0+4+8+16)."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr t)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 5 3
      ;; col1=6, row1=4
      (should (equal (kuro--encode-mouse 'fake-event 28 t) "\e[<28;6;4M")))))

(ert-deftest kuro-input-mouse-sgr-shift-scroll-up ()
  "SGR mode: Shift+scroll-up encodes as button=68 (64 + Shift=4)."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr t)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 0 0
      (should (equal (kuro--encode-mouse 'fake-event 68 t) "\e[<68;1;1M")))))

(ert-deftest kuro-input-mouse-sgr-ctrl-scroll-down ()
  "SGR mode: Ctrl+scroll-down encodes as button=81 (65 + Ctrl=16)."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr t)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 0 0
      (should (equal (kuro--encode-mouse 'fake-event 81 t) "\e[<81;1;1M")))))

(ert-deftest kuro-input-mouse-sgr-modifier-release-uses-lowercase-m ()
  "SGR mode: modifier+button release still uses lowercase 'm' terminator."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr t)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 1 1
      ;; col1=2, row1=2; button=4 (Shift+left), release → m
      (should (equal (kuro--encode-mouse 'fake-event 4 nil) "\e[<4;2;2m")))))

(ert-deftest kuro-input-mouse-x10-shift-modifier-btn4-overflow-check ()
  "X10 mode: Shift+button0 = button=4; btn-byte = 4+32 = 36, within range."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr nil)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 0 0
      (let ((result (kuro--encode-mouse 'fake-event 4 t)))
        ;; btn-byte = 4+32 = 36; col-byte = 1+32 = 33; row-byte = 1+32 = 33
        (should (equal result (format "\e[M%c%c%c" 36 33 33)))))))

(ert-deftest kuro-input-mouse-pixel-mode-modifier-button ()
  "Pixel mode: modifier+button embeds modifier bits in SGR sequence without offset."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr nil)
    (setq-local kuro--mouse-pixel-mode t)
    ;; posn-x-y returns pixel coords directly (no +1)
    (kuro-mouse-test--with-event 120 80
      ;; Meta+right = button=10 (2+8); col=120, row=80
      (should (equal (kuro--encode-mouse 'fake-event 10 t) "\e[<10;120;80M")))))

;;; Group 22: kuro--mouse-button-to-code, col-row extraction, clamping

(defmacro kuro-mouse-test--full-stub (col row btn-type &rest body)
  "Stub all event functions and run BODY with COL/ROW position and BTN-TYPE basic type."
  (declare (indent 3))
  `(cl-letf (((symbol-function 'event-start)
               (lambda (_ev) 'fake-pos))
              ((symbol-function 'event-basic-type)
               (lambda (_ev) ,btn-type))
              ((symbol-function 'posn-col-row)
               (lambda (_pos) (cons ,col ,row)))
              ((symbol-function 'posn-x-y)
               (lambda (_pos) (cons ,col ,row))))
     ,@body))

(ert-deftest kuro-input-mouse-button-code-mouse1-is-zero ()
  "mouse-1 event basic type maps to button code 0 (left button)."
  ;; kuro--def-mouse-cmd uses pcase over event-basic-type: mouse-1 → 0
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr t
                kuro--mouse-pixel-mode nil)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key) (lambda (s) (setq sent s))))
        (kuro-mouse-test--full-stub 0 0 'mouse-1
          (kuro--mouse-press)))
      ;; SGR button=0, col1=1, row1=1 → ESC[<0;1;1M
      (should (equal sent "\e[<0;1;1M")))))

(ert-deftest kuro-input-mouse-button-code-mouse3-is-two ()
  "mouse-3 event basic type maps to button code 2 (right button)."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr t
                kuro--mouse-pixel-mode nil)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key) (lambda (s) (setq sent s))))
        (kuro-mouse-test--full-stub 0 0 'mouse-3
          (kuro--mouse-press)))
      ;; SGR button=2, col1=1, row1=1 → ESC[<2;1;1M
      (should (equal sent "\e[<2;1;1M")))))

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
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr nil
                kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 2 5
      (let ((result (kuro--encode-mouse 'fake-event 0 t)))
        ;; Prefix is ESC[M (3 chars) + 3 byte values = 6 chars total
        (should (string-prefix-p "\e[M" result))
        (should (= (length result) 6))))))

(ert-deftest kuro-input-mouse-sgr-press-format-is-esclangle ()
  "SGR format for press uses ESC[< prefix and uppercase M terminator."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr t
                kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 0 0
      (let ((result (kuro--encode-mouse 'fake-event 0 t)))
        (should (string-prefix-p "\e[<" result))
        (should (string-suffix-p "M" result))))))

(ert-deftest kuro-input-mouse-sgr-release-format-uses-lowercase-m ()
  "SGR format for release uses lowercase m terminator, not uppercase M."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr t
                kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 0 0
      (let ((press-result   (kuro--encode-mouse 'fake-event 0 t))
            (release-result (kuro--encode-mouse 'fake-event 0 nil)))
        (should (string-suffix-p "M" press-result))
        (should (string-suffix-p "m" release-result))
        (should-not (string-suffix-p "m" press-result))))))

(ert-deftest kuro-input-mouse-pixel-sends-pixel-coords ()
  "Pixel mode reports posn-x-y coordinates (not col+1/row+1)."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr nil
                kuro--mouse-pixel-mode t)
    ;; posn-x-y stub returns (42 . 99); pixel mode uses these directly
    (kuro-mouse-test--with-event 42 99
      (let ((result (kuro--encode-mouse 'fake-event 0 t)))
        (should (equal result "\e[<0;42;99M"))))))

(ert-deftest kuro-input-mouse-col-row-extraction-cell-mode ()
  "kuro--mouse-coords extracts posn-col-row and adds 1 to each coordinate."
  (with-temp-buffer
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 7 13
      (let ((coords (kuro--mouse-coords 'fake-event)))
        ;; 0-based (7,13) → 1-based (8,14)
        (should (= (car coords) 8))
        (should (= (cdr coords) 14))))))

(ert-deftest kuro-input-mouse-x10-overflow-past-terminal-width-returns-nil ()
  "X10 mode returns nil when column exceeds the 223-cell limit (past terminal width)."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr nil
                kuro--mouse-pixel-mode nil)
    ;; col=300 → col1=301, overflows the (< col1 224) guard → returns nil
    (kuro-mouse-test--with-event 300 0
      (should-not (kuro--encode-mouse 'fake-event 0 t)))))

(ert-deftest kuro-input-mouse-sgr-large-coords-not-clamped ()
  "SGR mode does not clamp large coordinates; values above 223 pass through."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr t
                kuro--mouse-pixel-mode nil)
    ;; col=500 → col1=501, should appear verbatim in SGR sequence
    (kuro-mouse-test--with-event 500 300
      (let ((result (kuro--encode-mouse 'fake-event 0 t)))
        (should (equal result "\e[<0;501;301M"))))))

(provide 'kuro-input-mouse-ext-test)
;;; kuro-input-mouse-ext-test.el ends here
