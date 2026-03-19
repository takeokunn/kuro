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

(defvar-local kuro--mouse-mode 0
  "Cached mouse tracking mode from Rust: 0=off, 1000/1002/1003=on.")
(put 'kuro--mouse-mode 'permanent-local t)

(defvar-local kuro--mouse-sgr nil
  "Cached mouse SGR extended coordinates modifier state from Rust.")
(put 'kuro--mouse-sgr 'permanent-local t)

(defvar-local kuro--mouse-pixel-mode nil
  "Cached mouse pixel coordinate mode (?1016) state from Rust.
When non-nil, mouse positions are reported in pixels instead of cells.")
(put 'kuro--mouse-pixel-mode 'permanent-local t)


;;; Mouse Encoding

(defun kuro--encode-mouse (event button press)
  "Encode mouse EVENT with BUTTON index as a PTY byte string.
BUTTON is 0=left, 1=middle, 2=right, 64=scroll-up, 65=scroll-down.
PRESS is non-nil for button press, nil for button release.
Returns the encoded string, or nil if mouse mode is off or position overflows."
  (when (> kuro--mouse-mode 0)
    (let* ((pos (event-start event))
           (col-row (if kuro--mouse-pixel-mode
                        ;; Pixel mode: report pixel coordinates
                        (let ((xy (posn-x-y pos)))
                          (cons (or (car xy) 0) (or (cdr xy) 0)))
                      ;; Cell mode: report 1-based cell coordinates
                      (let ((cr (posn-col-row pos)))
                        (cons (1+ (car cr)) (1+ (cdr cr))))))
           (col1 (car col-row))
           (row1 (cdr col-row)))
      (if (or kuro--mouse-sgr kuro--mouse-pixel-mode)
          ;; SGR pixel format: ESC[<btn;px;pyM/m
          (format "\e[<%d;%d;%d%s" button col1 row1 (if press "M" "m"))
        ;; X10 format: ESC[M{btn+32}{col+32}{row+32} — discard if out of range
        (when (and (< col1 224) (< row1 224))
          (let ((btn-byte (+ (if press button 3) 32)))
            (format "\e[M%c%c%c" btn-byte (+ col1 32) (+ row1 32))))))))

(defun kuro--encode-mouse-sgr (event button press)
  "Encode mouse EVENT in SGR format (used when kuro--mouse-sgr is set)."
  (let* ((pos (event-start event))
         (col-row (if kuro--mouse-pixel-mode
                      ;; Pixel mode
                      (let ((xy (posn-x-y pos)))
                        (cons (or (car xy) 0) (or (cdr xy) 0)))
                    (let ((cr (posn-col-row pos)))
                      (cons (1+ (car cr)) (1+ (cdr cr))))))
         (col1 (car col-row))
         (row1 (cdr col-row)))
    (format "\e[<%d;%d;%d%s" button col1 row1 (if press "M" "m"))))


;;; Mouse Event Handlers

(defun kuro--mouse-press ()
  "Handle mouse button press and forward to PTY."
  (interactive)
  (when (> kuro--mouse-mode 0)
    (let* ((btn (pcase (event-basic-type last-input-event)
                  ('mouse-1 0) ('mouse-2 1) ('mouse-3 2) (_ nil)))
           (seq (when btn
                  (if kuro--mouse-sgr
                      (kuro--encode-mouse-sgr last-input-event btn t)
                    (kuro--encode-mouse last-input-event btn t)))))
      (when seq (kuro--send-key seq)))))

(defun kuro--mouse-release ()
  "Handle mouse button release and forward to PTY."
  (interactive)
  (when (> kuro--mouse-mode 0)
    (let* ((btn (pcase (event-basic-type last-input-event)
                  ('mouse-1 0) ('mouse-2 1) ('mouse-3 2) (_ nil)))
           (seq (when btn
                  (if kuro--mouse-sgr
                      (kuro--encode-mouse-sgr last-input-event btn nil)
                    (kuro--encode-mouse last-input-event btn nil)))))
      (when seq (kuro--send-key seq)))))

(defun kuro--mouse-scroll-up ()
  "Handle scroll-up mouse event and forward to PTY."
  (interactive)
  (when (> kuro--mouse-mode 0)
    (let ((seq (if kuro--mouse-sgr
                   (kuro--encode-mouse-sgr last-input-event 64 t)
                 (kuro--encode-mouse last-input-event 64 t))))
      (when seq (kuro--send-key seq)))))

(defun kuro--mouse-scroll-down ()
  "Handle scroll-down mouse event and forward to PTY."
  (interactive)
  (when (> kuro--mouse-mode 0)
    (let ((seq (if kuro--mouse-sgr
                   (kuro--encode-mouse-sgr last-input-event 65 t)
                 (kuro--encode-mouse last-input-event 65 t))))
      (when seq (kuro--send-key seq)))))

(provide 'kuro-input-mouse)

;;; kuro-input-mouse.el ends here
