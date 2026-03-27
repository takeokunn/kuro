;;; kuro-input-mouse.el --- Mouse tracking for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:
;; Mouse encoding and tracking event handlers for X10, SGR, and pixel modes.

;;; Code:

(require 'kuro-ffi)

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
BUTTON is 0=left, 1=middle, 2=right, 64=scroll-up, 65=scroll-down.
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
  "Encode mouse EVENT in SGR format (used when kuro--mouse-sgr is set)."
  (pcase-let* ((`(,col1 . ,row1) (kuro--mouse-coords event)))
    (format "\e[<%d;%d;%d%s" button col1 row1 (if press "M" "m"))))


;;; Mouse Event Dispatch

(defmacro kuro--dispatch-mouse-event (btn press)
  "When mouse tracking is active and BTN is non-nil, encode and forward the event.
BTN is an integer button index (0/1/2/64/65) or nil to skip.
PRESS is non-nil for press, nil for release.
Routes through `kuro--encode-mouse-sgr' or `kuro--encode-mouse' based on mode."
  `(when (and (> kuro--mouse-mode 0) ,btn)
     (let ((seq (if kuro--mouse-sgr
                    (kuro--encode-mouse-sgr last-input-event ,btn ,press)
                  (kuro--encode-mouse last-input-event ,btn ,press))))
       (when seq (kuro--send-key seq)))))


;;; Mouse Event Handler Macro

(defmacro kuro--def-mouse-cmd (name btn-form press doc)
  "Define interactive mouse command NAME dispatching BTN-FORM / PRESS to the PTY.
BTN-FORM is evaluated at call time: a literal integer for scroll commands, or a
pcase expression over `event-basic-type' for button commands.
PRESS is t for press events, nil for release."
  `(defun ,name ()
     ,doc
     (interactive)
     (let ((btn ,btn-form))
       (kuro--dispatch-mouse-event btn ,press))))


;;; Mouse Event Handlers

(kuro--def-mouse-cmd kuro--mouse-press
  (pcase (event-basic-type last-input-event)
    ('mouse-1 0) ('mouse-2 1) ('mouse-3 2) (_ nil))
  t
  "Handle mouse button press and forward to PTY.")

(kuro--def-mouse-cmd kuro--mouse-release
  (pcase (event-basic-type last-input-event)
    ('mouse-1 0) ('mouse-2 1) ('mouse-3 2) (_ nil))
  nil
  "Handle mouse button release and forward to PTY.")

(kuro--def-mouse-cmd kuro--mouse-scroll-up
  64
  t
  "Handle scroll-up mouse event and forward to PTY.")

(kuro--def-mouse-cmd kuro--mouse-scroll-down
  65
  t
  "Handle scroll-down mouse event and forward to PTY.")

(provide 'kuro-input-mouse)

;;; kuro-input-mouse.el ends here
