;;; kuro-input-mouse.el --- Mouse tracking for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Mouse event encoding and tracking for the Kuro terminal emulator.
;;
;; Supports three mouse coordinate modes: X10 (legacy 8-bit encoding),
;; SGR extended coordinates (mode 1006), and pixel coordinates
;; (mode 1016).  Provides press/release handlers that dispatch through
;; `kuro--encode-mouse' or `kuro--encode-mouse-sgr'.

;;; Code:

(require 'kuro-ffi)
(require 'kuro-ffi-osc)
(require 'kuro-input-mouse-macros)

(declare-function kuro--send-key "kuro-ffi" (data))
;;; Mouse Tracking State

(kuro--defvar-permanent-local kuro--mouse-mode 0
  "Cached mouse tracking mode from Rust: 0=off, 1000/1002/1003=on.")

(kuro--defvar-permanent-local kuro--mouse-sgr nil
  "Cached mouse SGR extended coordinates modifier state from Rust.")

(kuro--defvar-permanent-local kuro--mouse-pixel-mode nil
  "Cached mouse pixel coordinate mode (?1016) state from Rust.
When non-nil, mouse positions are reported in pixels instead of cells.")


;;; Mouse Coordinate Helper

(defsubst kuro--mouse-coords (event)
  "Return (COL1 . ROW1) for EVENT.
Pixel mode: `posn-x-y' coordinates (0-based pixel coords, no +1 offset).
Cell mode: `posn-col-row' coordinates incremented to 1-based."
  (let ((pos (event-start event)))
    (if kuro--mouse-pixel-mode
        (let ((xy (posn-x-y pos)))
          (cons (or (car xy) 0) (or (cdr xy) 0)))
      (let ((cr (posn-col-row pos)))
        (cons (1+ (car cr)) (1+ (cdr cr)))))))


;;; Mouse Encoding

(defun kuro--encode-mouse (event button press)
  "Encode mouse EVENT with BUTTON index as a PTY byte string.
BUTTON is 0=left, 1=middle, 2=right, 64=wheel-up, 65=wheel-down.
PRESS is non-nil for button press, nil for button release.
Returns the encoded string, or nil if mouse mode is off or position overflows."
  (when (> kuro--mouse-mode 0)
    (pcase-let* ((`(,col1 . ,row1) (kuro--mouse-coords event)))
      (if (or kuro--mouse-sgr kuro--mouse-pixel-mode)
          ;; SGR / pixel format: ESC[<btn;col;rowM/m
          (format "\e[<%d;%d;%d%s" button col1 row1 (if press "M" "m"))
        ;; X10 format: ESC[M{btn+32}{col+32}{row+32} — discard if out of range
        (when (and (< col1 224) (< row1 224))
          (let ((btn-byte (+ (if press button 3) 32)))
            (format "\e[M%c%c%c" btn-byte (+ col1 32) (+ row1 32))))))))

(defun kuro--encode-mouse-sgr (event button press)
  "Encode mouse EVENT with BUTTON index in SGR format; PRESS is non-nil for press."
  (pcase-let* ((`(,col1 . ,row1) (kuro--mouse-coords event)))
    (format "\e[<%d;%d;%d%s" button col1 row1 (if press "M" "m"))))


;;; Mouse Event Handlers

(kuro--def-mouse-cmd kuro--mouse-press
  (alist-get (event-basic-type last-input-event) kuro--mouse-button-alist)
  t
  "Handle mouse button press and forward to PTY.")

(kuro--def-mouse-cmd kuro--mouse-release
  (alist-get (event-basic-type last-input-event) kuro--mouse-button-alist)
  nil
  "Handle mouse button release and forward to PTY.")

(provide 'kuro-input-mouse)

;;; kuro-input-mouse.el ends here
