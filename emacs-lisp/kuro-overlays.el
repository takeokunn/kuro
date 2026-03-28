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

(defvar kuro--blink-slow-frames-cached (max 1 (round (* 60 0.5)))
  "Cached frame interval for slow text blink cycle (SGR 5).
Number of render frames between each visibility toggle,
yielding a ~0.5 Hz toggle rate (1.0 s per phase).
Recomputed by `kuro--recompute-blink-frame-intervals' on frame-rate change.")

(defvar kuro--blink-fast-frames-cached (max 1 (round (* 60 0.167)))
  "Cached frame interval for fast text blink cycle (SGR 6).
Number of render frames between each visibility toggle,
yielding a ~1.5 Hz toggle rate (~0.33 s per phase).
Recomputed by `kuro--recompute-blink-frame-intervals' on frame-rate change.")

(defun kuro--recompute-blink-frame-intervals ()
  "Recompute cached blink frame intervals from current `kuro-frame-rate'.
Called from `kuro--start-render-loop' when the render loop starts."
  (setq kuro--blink-slow-frames-cached (max 1 (round (* kuro-frame-rate 0.5))))
  (setq kuro--blink-fast-frames-cached (max 1 (round (* kuro-frame-rate 0.167)))))

(defsubst kuro--blink-slow-frames ()
  "Return frame interval for slow text blink cycle (SGR 5).
Returns the cached value from `kuro--blink-slow-frames-cached'."
  kuro--blink-slow-frames-cached)

(defsubst kuro--blink-fast-frames ()
  "Return frame interval for fast text blink cycle (SGR 6).
Returns the cached value from `kuro--blink-fast-frames-cached'."
  kuro--blink-fast-frames-cached)

;;; Buffer-local state

(kuro--defvar-permanent-local kuro--blink-overlays nil
  "List of active blink overlays in the current kuro buffer.")

(kuro--defvar-permanent-local kuro--blink-overlays-by-row
  (make-hash-table :test 'eql)
  "Hash table mapping row index to a list of blink overlays on that row.
Used by `kuro--clear-line-blink-overlays' to avoid scanning the full
`kuro--blink-overlays' list for each dirty row update.")

(kuro--defvar-permanent-local kuro--image-overlays nil
  "List of image display overlays in the current kuro buffer.
Each overlay has a `kuro-image' property and a `display' image spec.")

(kuro--defvar-permanent-local kuro--has-images nil
  "Non-nil when the current buffer has at least one active image overlay.
Used as a fast guard to skip `kuro--clear-row-image-overlays' on rows
when no Kitty Graphics images are present.")

(defvar kuro--face-prop-template (list 'face nil)
  "Reusable property list for face application to avoid per-call allocation.")

(kuro--defvar-permanent-local kuro--blink-frame-count 0
  "Frame counter used for blink animation timing.")

(kuro--defvar-permanent-local kuro--blink-visible-slow t
  "Non-nil when slow-blink text is currently in the visible phase.")

(kuro--defvar-permanent-local kuro--blink-visible-fast t
  "Non-nil when fast-blink text is currently in the visible phase.")

;;; Blink helpers

(defsubst kuro--blink-visible (blink-type)
  "Return the current visibility state for BLINK-TYPE (`slow' or `fast')."
  (if (eq blink-type 'slow) kuro--blink-visible-slow kuro--blink-visible-fast))

(defmacro kuro--toggle-blink-state (blink-type)
  "Toggle the visibility state variable for BLINK-TYPE and return the new value.
Modifies `kuro--blink-visible-slow' or `kuro--blink-visible-fast' in-place."
  `(if (eq ,blink-type 'slow)
       (setq kuro--blink-visible-slow (not kuro--blink-visible-slow))
     (setq kuro--blink-visible-fast (not kuro--blink-visible-fast))))

;;; Blink overlays

(defun kuro--apply-blink-overlay (start end blink-type)
  "Create a blink overlay covering buffer positions START to END.
BLINK-TYPE is the symbol `slow' or `fast', controlling which blink
visibility state variable is consulted."
  (let* ((visible (kuro--blink-visible blink-type))
         (ov (make-overlay start end))
         ;; Derive row (0-based) from buffer position for the by-row index.
         (row (1- (line-number-at-pos start))))
    (overlay-put ov 'kuro-blink t)
    (overlay-put ov 'kuro-blink-type blink-type)
    (overlay-put ov 'invisible (not visible))
    (push ov kuro--blink-overlays)
    (puthash row (cons ov (gethash row kuro--blink-overlays-by-row))
             kuro--blink-overlays-by-row)))

(defun kuro--toggle-blink-phase (blink-type)
  "Toggle BLINK-TYPE (`slow' or `fast') visibility; update matching overlays.
The state variable is toggled first; the new state is then applied to every
live overlay whose `kuro-blink-type' matches BLINK-TYPE."
  (let ((visible (kuro--toggle-blink-state blink-type)))
    (dolist (ov kuro--blink-overlays)
      (when (and (overlay-buffer ov)
                 (eq (overlay-get ov 'kuro-blink-type) blink-type))
        (overlay-put ov 'invisible (not visible))))))

(defun kuro--tick-blink-overlays ()
  "Advance the blink frame counter; toggle overlay visibility at each interval.
Slow blink (SGR 5): ~0.5 Hz — toggle every `kuro--blink-slow-frames' frames
\(1 s per phase).
Fast blink (SGR 6): ~1.5 Hz — toggle every `kuro--blink-fast-frames' frames
\(~0.33 s per phase).
Frame intervals are computed dynamically from `kuro-frame-rate' so that
blink timing is correct at any frame rate (not just 30 fps).
Called once per render cycle from `kuro--render-cycle'."
  (setq kuro--blink-frame-count (1+ kuro--blink-frame-count))
  (kuro--when-divisible kuro--blink-frame-count (kuro--blink-slow-frames)
    (kuro--toggle-blink-phase 'slow))
  (kuro--when-divisible kuro--blink-frame-count (kuro--blink-fast-frames)
    (kuro--toggle-blink-phase 'fast)))

;;; Image overlays (Kitty Graphics Protocol)

(defun kuro--clear-all-image-overlays ()
  "Remove all Kitty Graphics image overlays from the current buffer."
  (dolist (ov kuro--image-overlays)
    (when (overlay-buffer ov)
      (delete-overlay ov)))
  (setq kuro--image-overlays nil)
  (setq kuro--has-images nil))

(defun kuro--clear-row-image-overlays (row)
  "Remove image overlays that overlap ROW.
An overlay overlaps when it starts before row end
and ends after row start."
  (save-excursion
    (goto-char (point-min))
    (forward-line row)
    (let ((line-start (point))
          (line-end (1+ (line-end-position)))
          (remaining nil))
      (dolist (ov kuro--image-overlays)
        (if (and (overlay-buffer ov)
                 (< (overlay-start ov) line-end)
                 (> (overlay-end ov) line-start))
            (delete-overlay ov)
          (push ov remaining)))
      (setq kuro--image-overlays (nreverse remaining))
      (unless kuro--image-overlays
        (setq kuro--has-images nil)))))

(defun kuro--decode-png-image (b64)
  "Decode base64 B64 and return an Emacs PNG image object.
May signal an error if B64 is malformed or `create-image' fails."
  (create-image
   (encode-coding-string (base64-decode-string b64) 'binary)
   'png t))

(defun kuro--place-image-overlay (img row col cell-width)
  "Create a display overlay for IMG at grid (ROW, COL) spanning CELL-WIDTH cols.
Uses `forward-char' for column positioning so wide characters (2 terminal
columns, 1 buffer position) are handled correctly.  Pushes the new overlay
onto `kuro--image-overlays'.  No-op if the grid position is beyond the buffer."
  (let* ((start (save-excursion
                  (goto-char (point-min))
                  (forward-line row)
                  (forward-char col)
                  (point)))
         (end (min (+ start cell-width) (point-max))))
    (when (< start (point-max))
      (let ((ov (make-overlay start end)))
        (overlay-put ov 'kuro-image t)
        (overlay-put ov 'display    img)
        (overlay-put ov 'evaporate  t)   ; auto-delete if region deleted
        (push ov kuro--image-overlays)
        (setq kuro--has-images t)))))

(defun kuro--render-image-notification (notif)
  "Render a single Kitty Graphics image placement NOTIF in the terminal buffer.
NOTIF is a list of the form (IMAGE-ID ROW COL CELL-WIDTH CELL-HEIGHT).
Creates an overlay with a `display' property at the correct grid position."
  (pcase-let* ((`(,image-id ,row ,col ,raw-width . ,_) notif)
               (cell-width (max 1 raw-width))
               (b64 (kuro--get-image image-id)))
    (when (and b64 (stringp b64) (not (string-empty-p b64)))
      (condition-case err
          (when-let ((img (kuro--decode-png-image b64)))
            (kuro--place-image-overlay img row col cell-width))
        (error
         (message "kuro: image render error for id %d: %s" image-id err))))))

;;; FFI face application with blink and hidden support

(defsubst kuro--apply-ffi-face-at (start-pos end-pos fg-enc bg-enc flags ul-color-enc)
  "Apply FFI face data to the buffer region from START-POS to END-POS.
FG-ENC and BG-ENC are encoded foreground/background colors (u32).
FLAGS is the SGR attribute bitmask.  UL-COLOR-ENC is the encoded underline
color (u32) transmitted in the version-2 binary wire format.
Applies the face, blink overlays (SGR 5/6), and invisible property (SGR 8).

Fast-path: returns immediately when FG-ENC, BG-ENC, FLAGS, and UL-COLOR-ENC
are all at their default/zero values (no color, no attributes).  Callers do
not need to repeat this guard."
  (unless (and (= fg-enc kuro--ffi-color-default)
               (= bg-enc kuro--ffi-color-default)
               (= flags 0))
    (let ((face (kuro--get-cached-face-raw fg-enc bg-enc flags ul-color-enc)))
      (if (>= emacs-major-version 29)
          (add-face-text-property start-pos end-pos face)
        (setcar (cdr kuro--face-prop-template) face)
        (add-text-properties start-pos end-pos kuro--face-prop-template)))
    (when (/= 0 (logand flags (logior kuro--sgr-flag-blink-fast kuro--sgr-flag-blink-slow kuro--sgr-flag-hidden)))
      (cond
       ((/= 0 (logand flags kuro--sgr-flag-blink-fast))
        (kuro--apply-blink-overlay start-pos end-pos 'fast))
       ((/= 0 (logand flags kuro--sgr-flag-blink-slow))
        (kuro--apply-blink-overlay start-pos end-pos 'slow)))
      (when (/= 0 (logand flags kuro--sgr-flag-hidden))
        (add-text-properties start-pos end-pos '(invisible t))))))

(provide 'kuro-overlays)

;;; kuro-overlays.el ends here
