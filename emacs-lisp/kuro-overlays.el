;;; kuro-overlays.el --- Overlay management for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

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

;;; Code:

(require 'kuro-ffi)
(require 'kuro-faces)
(require 'kuro-faces-attrs)

(declare-function kuro--get-image "kuro-ffi-osc" (image-id))

(defvar kuro--current-render-row -1
  "Forward reference; defvar-local in kuro-render-buffer.el.
Holds the 0-based row index being rendered by `kuro--update-line-full'.
Read by `kuro--apply-blink-overlay' to avoid O(position) `line-number-at-pos'.")

(defvar kuro--row-positions nil
  "Forward reference; defvar-local in kuro-render-buffer.el.
Vector mapping row index to buffer position for O(1) row navigation.
Read by `kuro--clear-row-image-overlays' to skip O(row) `forward-line'.")

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
  "List of active blink overlays in the current kuro buffer.
Used as a guard (`when kuro--blink-overlays') and for full-list operations.
The typed sub-lists `kuro--blink-overlays-slow' and `kuro--blink-overlays-fast'
mirror this list partitioned by blink type, enabling O(type-count) iteration
in `kuro--toggle-blink-phase' without per-overlay `overlay-get' dispatch.")

(kuro--defvar-permanent-local kuro--blink-overlays-slow nil
  "Subset of `kuro--blink-overlays' containing only slow-blink (SGR 5) overlays.
Maintained in sync with `kuro--blink-overlays' by `kuro--apply-blink-overlay'
and `kuro--clear-line-blink-overlays'.  Allows `kuro--toggle-blink-phase' to
iterate only the relevant half without calling `overlay-get' per overlay.")

(kuro--defvar-permanent-local kuro--blink-overlays-fast nil
  "Subset of `kuro--blink-overlays' containing only fast-blink (SGR 6) overlays.
See `kuro--blink-overlays-slow' for the design rationale.")

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

(defconst kuro--sgr-visual-flags-mask
  (logior kuro--sgr-flag-blink-fast kuro--sgr-flag-blink-slow kuro--sgr-flag-hidden)
  "SGR flags that require blink overlays or invisible text properties.")

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

(defsubst kuro--apply-blink-overlay (start end blink-type)
  "Create a blink overlay covering buffer positions START to END.
BLINK-TYPE is the symbol `slow' or `fast', controlling which blink
visibility state variable is consulted.
Uses `kuro--current-render-row' when set (O(1)); falls back to
`line-number-at-pos' (O(position)) only when called outside a render cycle."
  (let* ((visible (kuro--blink-visible blink-type))
         (ov (make-overlay start end))
         ;; Fast path: kuro--current-render-row is set by kuro--update-line-full.
         ;; Slow path: line-number-at-pos for calls outside the render cycle.
         (row (if (>= kuro--current-render-row 0)
                  kuro--current-render-row
                (1- (line-number-at-pos start)))))
    (overlay-put ov 'kuro-blink t)
    (overlay-put ov 'kuro-blink-type blink-type)
    (overlay-put ov 'invisible (not visible))
    (push ov kuro--blink-overlays)
    ;; Also push into the typed sub-list so kuro--toggle-blink-phase can iterate
    ;; only the relevant half without an overlay-get dispatch per overlay.
    (if (eq blink-type 'slow)
        (push ov kuro--blink-overlays-slow)
      (push ov kuro--blink-overlays-fast))
    (puthash row (cons ov (gethash row kuro--blink-overlays-by-row))
             kuro--blink-overlays-by-row)))

(defun kuro--toggle-blink-phase (blink-type)
  "Toggle BLINK-TYPE (`slow' or `fast') visibility; update matching overlays.
Uses pre-segregated typed lists (`kuro--blink-overlays-slow' /
`kuro--blink-overlays-fast') so no per-overlay `overlay-get' dispatch is
needed to match type — iterates only the relevant half of all blink overlays."
  (let* ((visible (kuro--toggle-blink-state blink-type))
         (inv     (not visible))
         (ovs     (if (eq blink-type 'slow)
                      kuro--blink-overlays-slow
                    kuro--blink-overlays-fast)))
    (dolist (ov ovs)
      (when (overlay-buffer ov)
        (overlay-put ov 'invisible inv)))))

(defun kuro--tick-blink-overlays ()
  "Advance the blink frame counter; toggle overlay visibility at each interval.
Slow blink (SGR 5): ~0.5 Hz — toggle every `kuro--blink-slow-frames' frames
\(1 s per phase).
Fast blink (SGR 6): ~1.5 Hz — toggle every `kuro--blink-fast-frames' frames
\(~0.33 s per phase).
Frame intervals are computed dynamically from `kuro-frame-rate' so that
blink timing is correct at any frame rate (not just 30 fps).
Called once per render cycle from `kuro--render-cycle'."
  (let ((n (setq kuro--blink-frame-count (1+ kuro--blink-frame-count))))
    (kuro--when-divisible n kuro--blink-slow-frames-cached
      (kuro--toggle-blink-phase 'slow))
    (kuro--when-divisible n kuro--blink-fast-frames-cached
      (kuro--toggle-blink-phase 'fast))))

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
and ends after row start.
Uses `kuro--row-positions' cache for O(1) row navigation when available."
  (save-excursion
    (let ((cached (and kuro--row-positions
                       (< row (length kuro--row-positions))
                       (aref kuro--row-positions row))))
      (if cached
          (goto-char cached)
        (goto-char (point-min))
        (forward-line row)))
    (let ((line-start (point))
          (line-end (1+ (line-end-position)))
          (remaining nil))
      (dolist (ov kuro--image-overlays)
        (if (and (overlay-buffer ov)
                 (< (overlay-start ov) line-end)
                 (> (overlay-end ov) line-start))
            (delete-overlay ov)
          (push ov remaining)))
      ;; Order of kuro--image-overlays is irrelevant (only used for membership
      ;; tests and delete-overlay iteration) — nreverse is unnecessary overhead.
      (setq kuro--image-overlays remaining)
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

(defsubst kuro--ffi-face-default-p (fg-enc bg-enc flags ul-color-enc)
  "Return non-nil when FFI face payload is visually a no-op.
FG-ENC and BG-ENC are encoded colors, FLAGS is the SGR bitmask, and
UL-COLOR-ENC is the encoded underline color where 0 means default.

`(zerop (logior flags ul-color-enc))' combines the two zero-checks into one
`logior' plus one `zerop': if either FLAGS or UL-COLOR-ENC is non-zero the
result is non-zero and `and' short-circuits before reaching the color tests.
For styled ranges (non-zero flags, the common non-default case) this is one
operation instead of two separate `=' comparisons."
  (and (zerop (logior flags ul-color-enc))
       (= fg-enc kuro--ffi-color-default)
       (= bg-enc kuro--ffi-color-default)))

(defsubst kuro--ffi-face-has-visual-effects-p (flags)
  "Return non-nil when FLAGS require blink or hidden side effects."
  (/= 0 (logand flags kuro--sgr-visual-flags-mask)))

(if (>= emacs-major-version 29)
    (defsubst kuro--apply-ffi-face-text-properties (start-pos end-pos face)
      "Apply FACE to START-POS..END-POS using `add-face-text-property' (Emacs ≥29).
Load-time dispatch: the bytecode for each Emacs version contains no runtime
version check — eliminates one branch per face range in the innermost render loop."
      (add-face-text-property start-pos end-pos face))
  (defsubst kuro--apply-ffi-face-text-properties (start-pos end-pos face)
    "Apply FACE to START-POS..END-POS using add-text-properties (Emacs <29).
Load-time dispatch: the bytecode for each Emacs version contains no runtime
version check — eliminates one branch per face range in the innermost render loop."
    (setcar (cdr kuro--face-prop-template) face)
    (add-text-properties start-pos end-pos kuro--face-prop-template)))

(defsubst kuro--apply-ffi-face-effects (start-pos end-pos flags)
  "Apply blink and hidden effects for FLAGS to START-POS..END-POS."
  (cond
   ((/= 0 (logand flags kuro--sgr-flag-blink-fast))
    (kuro--apply-blink-overlay start-pos end-pos 'fast))
   ((/= 0 (logand flags kuro--sgr-flag-blink-slow))
    (kuro--apply-blink-overlay start-pos end-pos 'slow)))
  (when (/= 0 (logand flags kuro--sgr-flag-hidden))
    (add-text-properties start-pos end-pos '(invisible t))))

(defsubst kuro--apply-ffi-face-at (start-pos end-pos fg-enc bg-enc flags ul-color-enc)
  "Apply FFI face data to the buffer region from START-POS to END-POS.
FG-ENC and BG-ENC are encoded foreground/background colors (u32).
FLAGS is the SGR attribute bitmask.  UL-COLOR-ENC is the encoded underline
color (u32) transmitted in the version-2 binary wire format.
Applies the face, blink overlays (SGR 5/6), and invisible property (SGR 8).

  Fast-path: returns immediately when FG-ENC, BG-ENC, FLAGS, and UL-COLOR-ENC
  are all at their default/zero values (no color, no attributes).  Callers do
  not need to repeat this guard."
  (unless (kuro--ffi-face-default-p fg-enc bg-enc flags ul-color-enc)
    (kuro--apply-ffi-face-text-properties
     start-pos end-pos
     (kuro--get-cached-face-raw fg-enc bg-enc flags ul-color-enc))
    (when (kuro--ffi-face-has-visual-effects-p flags)
      (kuro--apply-ffi-face-effects start-pos end-pos flags))))

(defun kuro--call-with-normalized-ffi-face-range (range line-start line-end continuation)
  "Normalize FFI face RANGE and call CONTINUATION with the computed arguments.
RANGE is a 6-element vector [START-BUF END-BUF FG-ENC BG-ENC FLAGS UL-COLOR-ENC].
LINE-START and LINE-END bound the inserted line. CONTINUATION runs only for
non-empty ranges after clamping. Returns non-nil when CONTINUATION ran."
  (let* ((start-pos (min (+ line-start (aref range 0)) line-end))
         (end-pos   (min (+ line-start (aref range 1)) line-end)))
    (when (> end-pos start-pos)
      (funcall continuation start-pos end-pos
               (aref range 2) (aref range 3) (aref range 4) (aref range 5))
      t)))

(provide 'kuro-overlays)

;;; kuro-overlays.el ends here
