;;; kuro-overlays.el --- Overlay management for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; This file provides overlay management for the Kuro terminal emulator.
;; It handles blink text overlays, Kitty Graphics image overlays,
;; and FFI face application with SGR attribute support.
;;
;; # Responsibilities
;;
;; - Blink overlay creation and visibility toggling (SGR 5/6)
;; - Kitty Graphics Protocol image overlay rendering
;; - FFI face application: color, blink, and invisible (SGR 8) attributes
;;
;; # Dependencies
;;
;; Depends on `kuro-ffi-osc' for `kuro--get-image'.
;; Depends on `kuro-faces' for `kuro--get-cached-face-raw'.
;; Depends on `kuro-navigation' for hyperlink, prompt, and focus overlay support.

;;; Code:

(require 'cl-lib)
(require 'kuro-ffi)
(require 'kuro-faces)
(require 'kuro-faces-attrs)
(require 'kuro-navigation)

(declare-function kuro--get-image "kuro-ffi-osc" (image-id))

(defconst kuro--blink-slow-frames 30
  "Frame interval for slow text blink cycle (SGR 5). At 30 fps this gives ~0.5 Hz toggle rate.")

(defconst kuro--blink-fast-frames 10
  "Frame interval for fast text blink cycle (SGR 6). At 30 fps this gives ~1.5 Hz toggle rate.")

;;; Buffer-local state

(defvar-local kuro--blink-overlays nil
  "List of active blink overlays in the current kuro buffer.")
(put 'kuro--blink-overlays 'permanent-local t)

(defvar-local kuro--image-overlays nil
  "List of image display overlays in the current kuro buffer.
Each overlay has a `kuro-image' property and a `display' image spec.")
(put 'kuro--image-overlays 'permanent-local t)

(defvar-local kuro--blink-frame-count 0
  "Frame counter used for blink animation timing.")
(put 'kuro--blink-frame-count 'permanent-local t)

(defvar-local kuro--blink-visible-slow t
  "Non-nil when slow-blink text is currently in the visible phase.")
(put 'kuro--blink-visible-slow 'permanent-local t)

(defvar-local kuro--blink-visible-fast t
  "Non-nil when fast-blink text is currently in the visible phase.")
(put 'kuro--blink-visible-fast 'permanent-local t)

;;; Blink overlays

(defun kuro--apply-blink-overlay (start end blink-type)
  "Create a blink overlay covering buffer positions START to END.
BLINK-TYPE is the symbol `slow' or `fast', controlling which blink
visibility state variable is consulted."
  (let* ((visible (if (eq blink-type 'slow)
                      kuro--blink-visible-slow
                    kuro--blink-visible-fast))
         (ov (make-overlay start end)))
    (overlay-put ov 'kuro-blink t)
    (overlay-put ov 'kuro-blink-type blink-type)
    (overlay-put ov 'invisible (not visible))
    (push ov kuro--blink-overlays)))

(defun kuro--clear-line-blink-overlays (row)
  "Remove blink overlays on line ROW and remove them from `kuro--blink-overlays'."
  (save-excursion
    (goto-char (point-min))
    (forward-line row)
    (let ((line-start (point))
          (line-end (1+ (line-end-position)))
          (remaining nil))
      (dolist (ov kuro--blink-overlays)
        (if (and (overlay-buffer ov)
                 (>= (overlay-start ov) line-start)
                 (<= (overlay-end ov) line-end))
            (delete-overlay ov)
          (push ov remaining)))
      (setq kuro--blink-overlays (nreverse remaining)))))

(defun kuro--tick-blink-overlays ()
  "Advance the blink frame counter and toggle overlay visibility at correct intervals.
Slow blink (SGR 5): ~0.5 Hz — toggle every 30 frames at 30 fps (1 s per phase).
Fast blink (SGR 6): ~1.5 Hz — toggle every 10 frames at 30 fps (~0.33 s per phase).
Called once per render cycle from `kuro--render-cycle'."
  (setq kuro--blink-frame-count (1+ kuro--blink-frame-count))
  (when (zerop (mod kuro--blink-frame-count kuro--blink-slow-frames))
    (setq kuro--blink-visible-slow (not kuro--blink-visible-slow))
    (dolist (ov kuro--blink-overlays)
      (when (and (overlay-buffer ov)
                 (eq (overlay-get ov 'kuro-blink-type) 'slow))
        (overlay-put ov 'invisible (not kuro--blink-visible-slow)))))
  (when (zerop (mod kuro--blink-frame-count kuro--blink-fast-frames))
    (setq kuro--blink-visible-fast (not kuro--blink-visible-fast))
    (dolist (ov kuro--blink-overlays)
      (when (and (overlay-buffer ov)
                 (eq (overlay-get ov 'kuro-blink-type) 'fast))
        (overlay-put ov 'invisible (not kuro--blink-visible-fast))))))

;;; Image overlays (Kitty Graphics Protocol)

(defun kuro--clear-all-image-overlays ()
  "Remove all Kitty Graphics image overlays from the current buffer."
  (dolist (ov kuro--image-overlays)
    (when (overlay-buffer ov)
      (delete-overlay ov)))
  (setq kuro--image-overlays nil))

(defun kuro--clear-row-image-overlays (row)
  "Remove image overlays that start on ROW."
  (save-excursion
    (goto-char (point-min))
    (forward-line row)
    (let ((line-start (point))
          (line-end (1+ (line-end-position)))
          (remaining nil))
      (dolist (ov kuro--image-overlays)
        (if (and (overlay-buffer ov)
                 (>= (overlay-start ov) line-start)
                 (< (overlay-start ov) line-end))
            (delete-overlay ov)
          (push ov remaining)))
      (setq kuro--image-overlays (nreverse remaining)))))

(defun kuro--render-image-notification (notif)
  "Render a single Kitty Graphics image placement NOTIF in the terminal buffer.
NOTIF is a list of the form (IMAGE-ID ROW COL CELL-WIDTH CELL-HEIGHT).
Creates an overlay with a `display' image property at the correct grid position."
  (let* ((image-id   (nth 0 notif))
         (row        (nth 1 notif))
         (col        (nth 2 notif))
         (cell-width (max 1 (nth 3 notif)))
         (b64        (kuro--get-image image-id)))
    (when (and b64 (stringp b64) (not (string-empty-p b64)))
      (condition-case err
          (let* (                 ;; Decode base64 → raw PNG bytes (binary string)
                 (png-data (encode-coding-string (base64-decode-string b64) 'binary))
                 ;; Build Emacs image object
                 (img      (create-image png-data 'png t))
                 ;; Locate buffer position for (row, col)
                 ;; Use forward-char rather than (+ line-pos col) so wide characters
                 ;; (which occupy 2 terminal columns but 1 buffer position) are handled correctly.
                 (start    (save-excursion
                             (goto-char (point-min))
                             (forward-line row)
                             (forward-char col)
                             (point)))
                 ;; Span cell-width characters so the image occludes the right cells
                 (end      (+ start cell-width)))
            (when (and img (< start (point-max)))
              (let ((ov (make-overlay start (min end (point-max)))))
                (overlay-put ov 'kuro-image    t)
                (overlay-put ov 'display       img)
                (overlay-put ov 'evaporate     t)  ; auto-delete if region deleted
                (push ov kuro--image-overlays))))
        (error
         (message "kuro: image render error for id %d: %s" image-id err))))))

;;; FFI face application with blink and hidden support

(defsubst kuro--unpack-ffi-face-range (range)
  "Unpack FFI face RANGE 5-tuple into (start end fg bg flags).
RANGE is a proper list of the form (start-buf end-buf fg bg flags)
as returned by `kuro-core-poll-updates-with-faces'."
  (list (car range) (cadr range) (caddr range) (cadddr range) (car (cddddr range))))

(defsubst kuro--apply-ffi-face-at (start-pos end-pos fg-enc bg-enc flags)
  "Apply FFI face data to the buffer region from START-POS to END-POS.
FG-ENC and BG-ENC are encoded foreground/background colors (u32).
FLAGS is the SGR attribute bitmask.  Applies the face, blink overlays
(SGR 5/6), and invisible property (SGR 8) as appropriate.

Fast-path: returns immediately when FG-ENC, BG-ENC, and FLAGS are all at
their default/zero values (no color, no attributes).  Callers do not need
to repeat this guard."
  (unless (and (= fg-enc kuro--ffi-color-default)
               (= bg-enc kuro--ffi-color-default)
               (= flags 0))
    (let ((face (kuro--get-cached-face-raw fg-enc bg-enc flags 0)))
      (add-text-properties start-pos end-pos `(face ,face)))
    (cond
     ((/= 0 (logand flags kuro--sgr-flag-blink-fast))
      (kuro--apply-blink-overlay start-pos end-pos 'fast))
     ((/= 0 (logand flags kuro--sgr-flag-blink-slow))
      (kuro--apply-blink-overlay start-pos end-pos 'slow)))
    (when (/= 0 (logand flags kuro--sgr-flag-hidden))
      (add-text-properties start-pos end-pos '(invisible t)))))

(provide 'kuro-overlays)

;;; kuro-overlays.el ends here
