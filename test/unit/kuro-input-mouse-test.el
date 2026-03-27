;;; kuro-input-mouse-test.el --- Tests for kuro-input-mouse.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; ERT tests for kuro-input-mouse.el mouse encoding functions.
;; These tests exercise pure encoding logic and do not require
;; the Rust dynamic module.
;;
;; kuro--encode-mouse and kuro--encode-mouse-sgr are pure string-formatting
;; functions whose only dependencies are the buffer-local state variables
;; kuro--mouse-mode, kuro--mouse-sgr, and kuro--mouse-pixel-mode, plus
;; the event position returned by event-start / posn-col-row / posn-x-y.
;;
;; Strategy:
;;   - Stub event-start, posn-col-row, posn-x-y with cl-letf to return
;;     controlled position values.
;;   - Set kuro--mouse-mode / kuro--mouse-sgr / kuro--mouse-pixel-mode as
;;     buffer-local vars inside with-temp-buffer.
;;   - kuro--send-key and kuro--schedule-immediate-render are stubbed so
;;     the file loads without the Rust module.

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

(require 'kuro-input-mouse)


;;; Test helper

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


;;; Group 1: kuro--encode-mouse — mode disabled (returns nil)

(ert-deftest kuro-input-mouse-encode-returns-nil-when-mode-zero ()
  "kuro--encode-mouse returns nil when kuro--mouse-mode is 0 (disabled)."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 0)
    (setq-local kuro--mouse-sgr nil)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 4 9
      (should-not (kuro--encode-mouse 'fake-event 0 t)))))


;;; Group 2: kuro--encode-mouse — X10 encoding (cell mode, no SGR)

(ert-deftest kuro-input-mouse-x10-button0-press ()
  "X10 encoding: left-button press at col=1 row=1 produces correct sequence.
posn-col-row returns 0-based (0,0), so col1=1, row1=1.
btn-byte = button(0) + 32 = 32; col-byte = 1+32 = 33; row-byte = 1+32 = 33."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr nil)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 0 0
      (let ((result (kuro--encode-mouse 'fake-event 0 t)))
        (should (equal result (format "\e[M%c%c%c" 32 33 33)))))))

(ert-deftest kuro-input-mouse-x10-button1-press ()
  "X10 encoding: middle-button (button=1) press at col=5, row=10.
col1=6, row1=11; btn-byte=1+32=33; col-byte=6+32=38; row-byte=11+32=43."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr nil)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 5 10
      (let ((result (kuro--encode-mouse 'fake-event 1 t)))
        (should (equal result (format "\e[M%c%c%c" 33 38 43)))))))

(ert-deftest kuro-input-mouse-x10-button2-press ()
  "X10 encoding: right-button (button=2) press at col=9, row=3.
col1=10, row1=4; btn-byte=2+32=34; col-byte=10+32=42; row-byte=4+32=36."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr nil)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 9 3
      (let ((result (kuro--encode-mouse 'fake-event 2 t)))
        (should (equal result (format "\e[M%c%c%c" 34 42 36)))))))

(ert-deftest kuro-input-mouse-x10-release-uses-button3 ()
  "X10 encoding: release (press=nil) always encodes button as 3 (X10 convention).
btn-byte = 3 + 32 = 35."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr nil)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 2 2
      (let ((result (kuro--encode-mouse 'fake-event 0 nil)))
        ;; On release press=nil → btn-byte = 3+32 = 35
        (should (equal result (format "\e[M%c%c%c" 35 35 35)))))))

(ert-deftest kuro-input-mouse-x10-scroll-up-button64 ()
  "X10 encoding: scroll-up uses button index 64; btn-byte = 64+32 = 96."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr nil)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 0 0
      (let ((result (kuro--encode-mouse 'fake-event 64 t)))
        (should (equal result (format "\e[M%c%c%c" 96 33 33)))))))

(ert-deftest kuro-input-mouse-x10-scroll-down-button65 ()
  "X10 encoding: scroll-down uses button index 65; btn-byte = 65+32 = 97."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr nil)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 0 0
      (let ((result (kuro--encode-mouse 'fake-event 65 t)))
        (should (equal result (format "\e[M%c%c%c" 97 33 33)))))))


;;; Group 3: kuro--encode-mouse — X10 overflow guard

(ert-deftest kuro-input-mouse-x10-overflow-col-returns-nil ()
  "X10 encoding returns nil when column would overflow the 223-cell limit.
col1 = 224 exceeds the X10 limit; the function must return nil."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr nil)
    (setq-local kuro--mouse-pixel-mode nil)
    ;; posn-col-row 0-based col=223 → col1=224, which hits the (< col1 224) guard.
    (kuro-mouse-test--with-event 223 0
      (should-not (kuro--encode-mouse 'fake-event 0 t)))))

(ert-deftest kuro-input-mouse-x10-overflow-row-returns-nil ()
  "X10 encoding returns nil when row would overflow the 223-cell limit."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr nil)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 0 223
      (should-not (kuro--encode-mouse 'fake-event 0 t)))))

(ert-deftest kuro-input-mouse-x10-at-limit-succeeds ()
  "X10 encoding succeeds at the boundary: col1=223, row1=223.
posn-col-row 0-based (222,222) → col1=223, row1=223 which pass the guard."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr nil)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 222 222
      (let ((result (kuro--encode-mouse 'fake-event 0 t)))
        (should (stringp result))
        (should (string-prefix-p "\e[M" result))))))


;;; Group 4: kuro--encode-mouse — SGR path (kuro--mouse-sgr = t)

(ert-deftest kuro-input-mouse-sgr-press-format ()
  "SGR mode: press (press=t) produces ESC[<btn;col;rowM."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr t)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 4 9
      ;; col1 = 4+1 = 5, row1 = 9+1 = 10
      (let ((result (kuro--encode-mouse 'fake-event 0 t)))
        (should (equal result "\e[<0;5;10M"))))))

(ert-deftest kuro-input-mouse-sgr-release-format ()
  "SGR mode: release (press=nil) produces ESC[<btn;col;rowm (lowercase m)."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr t)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 4 9
      (let ((result (kuro--encode-mouse 'fake-event 0 nil)))
        (should (equal result "\e[<0;5;10m"))))))

(ert-deftest kuro-input-mouse-sgr-button-index-preserved ()
  "SGR mode: button index is embedded verbatim in the sequence."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr t)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 0 0
      (should (equal (kuro--encode-mouse 'fake-event 2 t)  "\e[<2;1;1M"))
      (should (equal (kuro--encode-mouse 'fake-event 64 t) "\e[<64;1;1M"))
      (should (equal (kuro--encode-mouse 'fake-event 65 t) "\e[<65;1;1M")))))

(ert-deftest kuro-input-mouse-sgr-no-overflow-guard ()
  "SGR mode has no column/row overflow guard; large coords are passed through."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr t)
    (setq-local kuro--mouse-pixel-mode nil)
    ;; col1 = 224, row1 = 224 — would be nil in X10, but SGR handles it fine.
    (kuro-mouse-test--with-event 223 223
      (let ((result (kuro--encode-mouse 'fake-event 0 t)))
        (should (equal result "\e[<0;224;224M"))))))


;;; Group 5: kuro--encode-mouse — pixel mode

(ert-deftest kuro-input-mouse-pixel-mode-uses-posn-x-y ()
  "Pixel mode: coordinates come from posn-x-y (not posn-col-row).
posn-x-y returns (px . py); these are used directly without +1 offset."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr nil)
    (setq-local kuro--mouse-pixel-mode t)
    ;; The stub returns (col . row) for both posn-col-row and posn-x-y.
    ;; In pixel mode posn-x-y is used, so col1=col, row1=row (no +1).
    (kuro-mouse-test--with-event 100 200
      ;; Pixel mode forces SGR format: ESC[<btn;px;pyM
      (let ((result (kuro--encode-mouse 'fake-event 0 t)))
        (should (equal result "\e[<0;100;200M"))))))

(ert-deftest kuro-input-mouse-pixel-mode-release-uses-lowercase-m ()
  "Pixel mode with press=nil produces lowercase 'm' terminator."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr nil)
    (setq-local kuro--mouse-pixel-mode t)
    (kuro-mouse-test--with-event 50 75
      (let ((result (kuro--encode-mouse 'fake-event 1 nil)))
        (should (equal result "\e[<1;50;75m"))))))


;;; Group 6: kuro--encode-mouse-sgr (standalone function)

(ert-deftest kuro-input-mouse-encode-sgr-direct-press ()
  "kuro--encode-mouse-sgr in cell mode produces ESC[<btn;col1;row1M."
  (with-temp-buffer
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 2 3
      ;; col1=3, row1=4
      (let ((result (kuro--encode-mouse-sgr 'fake-event 0 t)))
        (should (equal result "\e[<0;3;4M"))))))

(ert-deftest kuro-input-mouse-encode-sgr-direct-release ()
  "kuro--encode-mouse-sgr with press=nil produces lowercase 'm' terminator."
  (with-temp-buffer
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 2 3
      (let ((result (kuro--encode-mouse-sgr 'fake-event 0 nil)))
        (should (equal result "\e[<0;3;4m"))))))

(ert-deftest kuro-input-mouse-encode-sgr-pixel-uses-posn-x-y ()
  "kuro--encode-mouse-sgr in pixel mode uses posn-x-y coordinates directly."
  (with-temp-buffer
    (setq-local kuro--mouse-pixel-mode t)
    (kuro-mouse-test--with-event 300 400
      (let ((result (kuro--encode-mouse-sgr 'fake-event 2 t)))
        (should (equal result "\e[<2;300;400M"))))))


;;; Group 7: Buffer-local state isolation

(ert-deftest kuro-input-mouse-state-is-buffer-local ()
  "kuro--mouse-mode, kuro--mouse-sgr, and kuro--mouse-pixel-mode are buffer-local."
  (let ((buf1 (get-buffer-create " *kuro-mouse-test-1*"))
        (buf2 (get-buffer-create " *kuro-mouse-test-2*")))
    (unwind-protect
        (progn
          (with-current-buffer buf1
            (setq-local kuro--mouse-mode 1000)
            (setq-local kuro--mouse-sgr t)
            (setq-local kuro--mouse-pixel-mode nil))
          (with-current-buffer buf2
            (setq-local kuro--mouse-mode 0)
            (setq-local kuro--mouse-sgr nil)
            (setq-local kuro--mouse-pixel-mode t))
          (should (= (buffer-local-value 'kuro--mouse-mode buf1) 1000))
          (should (= (buffer-local-value 'kuro--mouse-mode buf2) 0))
          (should (buffer-local-value 'kuro--mouse-sgr buf1))
          (should-not (buffer-local-value 'kuro--mouse-sgr buf2))
          (should-not (buffer-local-value 'kuro--mouse-pixel-mode buf1))
          (should (buffer-local-value 'kuro--mouse-pixel-mode buf2)))
      (kill-buffer buf1)
      (kill-buffer buf2))))

;;; Group 8: kuro--mouse-coords helper

(ert-deftest kuro-input-mouse-coords-cell-mode-adds-one ()
  "In cell mode (pixel-mode nil), coords are posn-col-row incremented by 1."
  (with-temp-buffer
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 4 9
      ;; posn-col-row returns (4 . 9) → col1=5, row1=10
      (let ((coords (kuro--mouse-coords 'fake-event)))
        (should (= (car coords) 5))
        (should (= (cdr coords) 10))))))

(ert-deftest kuro-input-mouse-coords-pixel-mode-no-offset ()
  "In pixel mode, coords come from posn-x-y with no +1 offset."
  (with-temp-buffer
    (setq-local kuro--mouse-pixel-mode t)
    ;; kuro-mouse-test--with-event stubs posn-x-y with (col . row) as-is
    (kuro-mouse-test--with-event 100 200
      (let ((coords (kuro--mouse-coords 'fake-event)))
        (should (= (car coords) 100))
        (should (= (cdr coords) 200))))))

(ert-deftest kuro-input-mouse-coords-pixel-mode-nil-xy-becomes-zero ()
  "In pixel mode, nil posn-x-y values fall back to 0."
  (with-temp-buffer
    (setq-local kuro--mouse-pixel-mode t)
    (cl-letf (((symbol-function 'event-start) (lambda (_ev) 'fake-pos))
              ((symbol-function 'posn-x-y)    (lambda (_pos) (cons nil nil))))
      (let ((coords (kuro--mouse-coords 'fake-event)))
        (should (= (car coords) 0))
        (should (= (cdr coords) 0))))))

;;; Group 9: kuro--dispatch-mouse-event (via event handlers)

(ert-deftest kuro-input-mouse-dispatch-gates-on-mouse-mode ()
  "kuro--dispatch-mouse-event is a no-op when kuro--mouse-mode is 0."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 0
                kuro--mouse-sgr nil)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key) (lambda (s) (setq sent s))))
        (kuro-mouse-test--with-event 0 0
          (kuro--dispatch-mouse-event 0 t)))
      (should-not sent))))

(ert-deftest kuro-input-mouse-dispatch-nil-btn-is-noop ()
  "kuro--dispatch-mouse-event with nil BTN does not send anything."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr nil)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key) (lambda (s) (setq sent s))))
        (kuro-mouse-test--with-event 0 0
          (kuro--dispatch-mouse-event nil t)))
      (should-not sent))))

(ert-deftest kuro-input-mouse-dispatch-routes-to-sgr-encoder ()
  "When kuro--mouse-sgr is t, dispatch calls kuro--encode-mouse-sgr."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr t
                kuro--mouse-pixel-mode nil)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key) (lambda (s) (setq sent s))))
        (kuro-mouse-test--with-event 2 3   ; col1=3, row1=4
          (kuro--dispatch-mouse-event 1 t)))
      (should (equal sent "\e[<1;3;4M")))))

(ert-deftest kuro-input-mouse-dispatch-routes-to-x10-encoder ()
  "When kuro--mouse-sgr is nil, dispatch calls kuro--encode-mouse (X10 path)."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr nil
                kuro--mouse-pixel-mode nil)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key) (lambda (s) (setq sent s))))
        (kuro-mouse-test--with-event 0 0
          (kuro--dispatch-mouse-event 0 t)))
      ;; X10: btn-byte=32, col-byte=33, row-byte=33
      (should (equal sent (format "\e[M%c%c%c" 32 33 33))))))

;;; Group 10: kuro--encode-mouse — mode values 1002 and 1003

(ert-deftest kuro-input-mouse-mode-1002-enables-encoding ()
  "kuro--mouse-mode=1002 (button-event) also enables X10 encoding."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1002)
    (setq-local kuro--mouse-sgr nil)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 0 0
      (let ((result (kuro--encode-mouse 'fake-event 0 t)))
        (should (stringp result))
        (should (string-prefix-p "\e[M" result))))))

(ert-deftest kuro-input-mouse-mode-1003-enables-encoding ()
  "kuro--mouse-mode=1003 (any-event) also enables X10 encoding."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1003)
    (setq-local kuro--mouse-sgr nil)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 1 1
      (let ((result (kuro--encode-mouse 'fake-event 0 t)))
        (should (stringp result))
        (should (string-prefix-p "\e[M" result))))))

;;; Group 11: kuro--encode-mouse-sgr — button number encoding

(ert-deftest kuro-input-mouse-encode-sgr-button1-press ()
  "kuro--encode-mouse-sgr with button=1 embeds 1 in the SGR sequence."
  (with-temp-buffer
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 0 0
      (should (equal (kuro--encode-mouse-sgr 'fake-event 1 t) "\e[<1;1;1M")))))

(ert-deftest kuro-input-mouse-encode-sgr-button2-press ()
  "kuro--encode-mouse-sgr with button=2 embeds 2 in the SGR sequence."
  (with-temp-buffer
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 0 0
      (should (equal (kuro--encode-mouse-sgr 'fake-event 2 t) "\e[<2;1;1M")))))

(ert-deftest kuro-input-mouse-encode-sgr-scroll-up-button64 ()
  "kuro--encode-mouse-sgr with button=64 encodes scroll-up correctly."
  (with-temp-buffer
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 9 4
      ;; col1=10, row1=5
      (should (equal (kuro--encode-mouse-sgr 'fake-event 64 t) "\e[<64;10;5M")))))

(ert-deftest kuro-input-mouse-encode-sgr-scroll-down-button65 ()
  "kuro--encode-mouse-sgr with button=65 encodes scroll-down correctly."
  (with-temp-buffer
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 9 4
      (should (equal (kuro--encode-mouse-sgr 'fake-event 65 t) "\e[<65;10;5M")))))

;;; Group 12: kuro--encode-mouse — pixel mode with SGR also set

(ert-deftest kuro-input-mouse-pixel-and-sgr-both-set ()
  "When both pixel-mode and sgr are set, pixel-mode wins: SGR format, no +1 offset."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr t)
    (setq-local kuro--mouse-pixel-mode t)
    ;; kuro--encode-mouse checks (or kuro--mouse-sgr kuro--mouse-pixel-mode) → SGR format
    ;; kuro--mouse-coords uses posn-x-y when pixel-mode is set → no +1
    (kuro-mouse-test--with-event 150 200
      (let ((result (kuro--encode-mouse 'fake-event 0 t)))
        (should (equal result "\e[<0;150;200M"))))))

;;; Group 13: kuro--encode-mouse — X10 exact boundary (col1=223, row1=1)

(ert-deftest kuro-input-mouse-x10-col-boundary-222-passes ()
  "X10 col1=223 (posn-col-row=222) is the last valid column."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr nil)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 222 0
      (let ((result (kuro--encode-mouse 'fake-event 0 t)))
        (should (stringp result))))))

(ert-deftest kuro-input-mouse-x10-row-boundary-222-passes ()
  "X10 row1=223 (posn-col-row row=222) is the last valid row."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr nil)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 0 222
      (let ((result (kuro--encode-mouse 'fake-event 0 t)))
        (should (stringp result))))))

;;; Group 14: kuro--dispatch-mouse-event — SGR scroll events sent correctly

(ert-deftest kuro-input-mouse-dispatch-sgr-scroll-up ()
  "dispatch-mouse-event in SGR mode sends button=64 scroll-up sequence."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr t
                kuro--mouse-pixel-mode nil)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key) (lambda (s) (setq sent s))))
        (kuro-mouse-test--with-event 0 0
          (kuro--dispatch-mouse-event 64 t)))
      (should (equal sent "\e[<64;1;1M")))))

(ert-deftest kuro-input-mouse-dispatch-sgr-scroll-down ()
  "dispatch-mouse-event in SGR mode sends button=65 scroll-down sequence."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr t
                kuro--mouse-pixel-mode nil)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key) (lambda (s) (setq sent s))))
        (kuro-mouse-test--with-event 0 0
          (kuro--dispatch-mouse-event 65 t)))
      (should (equal sent "\e[<65;1;1M")))))

(ert-deftest kuro-input-mouse-dispatch-x10-release ()
  "dispatch-mouse-event in X10 mode (press=nil) uses button 3 encoding."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr nil
                kuro--mouse-pixel-mode nil)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key) (lambda (s) (setq sent s))))
        (kuro-mouse-test--with-event 0 0
          (kuro--dispatch-mouse-event 0 nil)))
      ;; X10 release: btn-byte = 3+32 = 35, col-byte = 1+32 = 33, row-byte = 33
      (should (equal sent (format "\e[M%c%c%c" 35 33 33))))))

(ert-deftest kuro-input-mouse-dispatch-does-not-send-when-overflow ()
  "dispatch-mouse-event with X10 and overflow coords sends nothing."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr nil
                kuro--mouse-pixel-mode nil)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key) (lambda (s) (setq sent s))))
        ;; col=223 → col1=224, triggers overflow guard → encode returns nil
        (kuro-mouse-test--with-event 223 0
          (kuro--dispatch-mouse-event 0 t)))
      (should-not sent))))

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

(ert-deftest kuro-input-mouse-sgr-button1-release ()
  "SGR mode: button=1 release produces ESC[<1;col;rowm."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr t)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 3 7
      ;; col1=4, row1=8
      (let ((result (kuro--encode-mouse 'fake-event 1 nil)))
        (should (equal result "\e[<1;4;8m"))))))

;;; Group 18: kuro--dispatch-mouse-event — pixel mode routing

(ert-deftest kuro-input-mouse-dispatch-pixel-mode-uses-sgr-format ()
  "dispatch-mouse-event with pixel mode uses SGR format with pixel coords."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr nil
                kuro--mouse-pixel-mode t)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key) (lambda (s) (setq sent s))))
        ;; posn-x-y and posn-col-row both return (col . row) from the stub.
        ;; pixel mode: no +1, uses posn-x-y → col=10, row=20
        (kuro-mouse-test--with-event 10 20
          (kuro--dispatch-mouse-event 0 t)))
      (should (equal sent "\e[<0;10;20M")))))

(ert-deftest kuro-input-mouse-dispatch-pixel-mode-release ()
  "dispatch-mouse-event with pixel mode and press=nil produces lowercase 'm'."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr nil
                kuro--mouse-pixel-mode t)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key) (lambda (s) (setq sent s))))
        (kuro-mouse-test--with-event 5 15
          (kuro--dispatch-mouse-event 2 nil)))
      (should (equal sent "\e[<2;5;15m")))))

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
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr nil
                kuro--mouse-pixel-mode nil)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key)
                 (lambda (s) (setq sent s)))
                ((symbol-function 'event-basic-type)
                 (lambda (_ev) 'mouse-99))
                ((symbol-function 'event-start)
                 (lambda (_ev) 'fake-pos))
                ((symbol-function 'posn-col-row)
                 (lambda (_pos) (cons 0 0)))
                ((symbol-function 'posn-x-y)
                 (lambda (_pos) (cons 0 0))))
        (kuro--mouse-press))
      (should-not sent))))

(ert-deftest kuro-input-mouse-release-unknown-event-type-is-noop ()
  "kuro--mouse-release sends nothing when event-basic-type returns an unknown symbol."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr nil
                kuro--mouse-pixel-mode nil)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key)
                 (lambda (s) (setq sent s)))
                ((symbol-function 'event-basic-type)
                 (lambda (_ev) 'mouse-99))
                ((symbol-function 'event-start)
                 (lambda (_ev) 'fake-pos))
                ((symbol-function 'posn-col-row)
                 (lambda (_pos) (cons 0 0)))
                ((symbol-function 'posn-x-y)
                 (lambda (_pos) (cons 0 0))))
        (kuro--mouse-release))
      (should-not sent))))

(ert-deftest kuro-input-mouse-press-mouse1-sends-button0 ()
  "kuro--mouse-press maps mouse-1 event type to button 0 in SGR mode."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr t
                kuro--mouse-pixel-mode nil)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key)
                 (lambda (s) (setq sent s)))
                ((symbol-function 'event-basic-type)
                 (lambda (_ev) 'mouse-1))
                ((symbol-function 'event-start)
                 (lambda (_ev) 'fake-pos))
                ((symbol-function 'posn-col-row)
                 (lambda (_pos) (cons 0 0)))
                ((symbol-function 'posn-x-y)
                 (lambda (_pos) (cons 0 0))))
        (kuro--mouse-press))
      ;; SGR: button=0, col1=1, row1=1, press → M
      (should (equal sent "\e[<0;1;1M")))))

(ert-deftest kuro-input-mouse-release-mouse2-sends-button1 ()
  "kuro--mouse-release maps mouse-2 event type to button 1 in SGR mode."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr t
                kuro--mouse-pixel-mode nil)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key)
                 (lambda (s) (setq sent s)))
                ((symbol-function 'event-basic-type)
                 (lambda (_ev) 'mouse-2))
                ((symbol-function 'event-start)
                 (lambda (_ev) 'fake-pos))
                ((symbol-function 'posn-col-row)
                 (lambda (_pos) (cons 2 3)))
                ((symbol-function 'posn-x-y)
                 (lambda (_pos) (cons 2 3))))
        (kuro--mouse-release))
      ;; SGR: button=1, col1=3, row1=4, release → m
      (should (equal sent "\e[<1;3;4m")))))

(ert-deftest kuro-input-mouse-scroll-up-sends-button64-sgr ()
  "kuro--mouse-scroll-up sends button=64 press in SGR mode."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr t
                kuro--mouse-pixel-mode nil)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key)
                 (lambda (s) (setq sent s)))
                ((symbol-function 'event-start)
                 (lambda (_ev) 'fake-pos))
                ((symbol-function 'posn-col-row)
                 (lambda (_pos) (cons 4 7)))
                ((symbol-function 'posn-x-y)
                 (lambda (_pos) (cons 4 7))))
        (kuro--mouse-scroll-up))
      ;; SGR: button=64, col1=5, row1=8, press → M
      (should (equal sent "\e[<64;5;8M")))))

(ert-deftest kuro-input-mouse-scroll-down-sends-button65-sgr ()
  "kuro--mouse-scroll-down sends button=65 press in SGR mode."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr t
                kuro--mouse-pixel-mode nil)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key)
                 (lambda (s) (setq sent s)))
                ((symbol-function 'event-start)
                 (lambda (_ev) 'fake-pos))
                ((symbol-function 'posn-col-row)
                 (lambda (_pos) (cons 0 0)))
                ((symbol-function 'posn-x-y)
                 (lambda (_pos) (cons 0 0))))
        (kuro--mouse-scroll-down))
      ;; SGR: button=65, col1=1, row1=1, press → M
      (should (equal sent "\e[<65;1;1M")))))

(ert-deftest kuro-input-mouse-scroll-up-x10-sends-correct-bytes ()
  "kuro--mouse-scroll-up in X10 mode sends button=64 (btn-byte=96)."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr nil
                kuro--mouse-pixel-mode nil)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key)
                 (lambda (s) (setq sent s)))
                ((symbol-function 'event-start)
                 (lambda (_ev) 'fake-pos))
                ((symbol-function 'posn-col-row)
                 (lambda (_pos) (cons 0 0)))
                ((symbol-function 'posn-x-y)
                 (lambda (_pos) (cons 0 0))))
        (kuro--mouse-scroll-up))
      ;; X10: btn-byte = 64+32 = 96, col-byte = 1+32 = 33, row-byte = 1+32 = 33
      (should (equal sent (format "\e[M%c%c%c" 96 33 33))))))

(ert-deftest kuro-input-mouse-press-mouse3-sends-button2 ()
  "kuro--mouse-press maps mouse-3 event type to button 2 in SGR mode."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr t
                kuro--mouse-pixel-mode nil)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key)
                 (lambda (s) (setq sent s)))
                ((symbol-function 'event-basic-type)
                 (lambda (_ev) 'mouse-3))
                ((symbol-function 'event-start)
                 (lambda (_ev) 'fake-pos))
                ((symbol-function 'posn-col-row)
                 (lambda (_pos) (cons 1 2)))
                ((symbol-function 'posn-x-y)
                 (lambda (_pos) (cons 1 2))))
        (kuro--mouse-press))
      ;; SGR: button=2, col1=2, row1=3, press → M
      (should (equal sent "\e[<2;2;3M")))))

(ert-deftest kuro-input-mouse-scroll-up-mode-off-is-noop ()
  "kuro--mouse-scroll-up sends nothing when kuro--mouse-mode is 0."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 0
                kuro--mouse-sgr nil
                kuro--mouse-pixel-mode nil)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key)
                 (lambda (s) (setq sent s)))
                ((symbol-function 'event-start)
                 (lambda (_ev) 'fake-pos))
                ((symbol-function 'posn-col-row)
                 (lambda (_pos) (cons 0 0)))
                ((symbol-function 'posn-x-y)
                 (lambda (_pos) (cons 0 0))))
        (kuro--mouse-scroll-up))
      (should-not sent))))

(ert-deftest kuro-input-mouse-scroll-down-mode-off-is-noop ()
  "kuro--mouse-scroll-down sends nothing when kuro--mouse-mode is 0."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 0
                kuro--mouse-sgr nil
                kuro--mouse-pixel-mode nil)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key)
                 (lambda (s) (setq sent s)))
                ((symbol-function 'event-start)
                 (lambda (_ev) 'fake-pos))
                ((symbol-function 'posn-col-row)
                 (lambda (_pos) (cons 0 0)))
                ((symbol-function 'posn-x-y)
                 (lambda (_pos) (cons 0 0))))
        (kuro--mouse-scroll-down))
      (should-not sent))))


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
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr nil
                kuro--mouse-pixel-mode nil)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key) (lambda (s) (setq sent s)))
                ((symbol-function 'event-start) (lambda (_ev) 'fake-pos))
                ((symbol-function 'posn-col-row) (lambda (_pos) (cons 0 0)))
                ((symbol-function 'posn-x-y) (lambda (_pos) (cons 0 0))))
        (kuro--mouse-scroll-up))
      ;; X10: btn-byte = 64+32 = 96
      (should (= (aref sent 3) 96)))))

(ert-deftest kuro-input-mouse-scroll-down-button-code-is-65 ()
  "kuro--mouse-scroll-down encodes as button 65 (scroll-down) in X10 format."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000
                kuro--mouse-sgr nil
                kuro--mouse-pixel-mode nil)
    (let ((sent nil))
      (cl-letf (((symbol-function 'kuro--send-key) (lambda (s) (setq sent s)))
                ((symbol-function 'event-start) (lambda (_ev) 'fake-pos))
                ((symbol-function 'posn-col-row) (lambda (_pos) (cons 0 0)))
                ((symbol-function 'posn-x-y) (lambda (_pos) (cons 0 0))))
        (kuro--mouse-scroll-down))
      ;; X10: btn-byte = 65+32 = 97
      (should (= (aref sent 3) 97)))))

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

(provide 'kuro-input-mouse-test)
;;; kuro-input-mouse-test.el ends here
