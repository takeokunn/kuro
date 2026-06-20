;;; kuro-overlays.el --- Overlay management for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

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

(require 'seq)
(require 'kuro-ffi)
(require 'kuro-faces)
(require 'kuro-faces-attrs)
(require 'kuro-overlays-macros)

(declare-function kuro--get-image "kuro-ffi-osc" (image-id))
(declare-function kuro--image-frame-count "kuro-ffi-osc" (image-id))
(declare-function kuro--image-frame-png "kuro-ffi-osc" (image-id frame-index))
(declare-function kuro--image-frame-gap "kuro-ffi-osc" (image-id frame-index))
(declare-function kuro--image-animation-state "kuro-ffi-osc" (image-id))
(declare-function kuro--goto-row-start "kuro-render-buffer" (row))

(defvar kuro--current-render-row -1
  "Forward reference; `defvar-local' in kuro-render-buffer.el.
Holds the 0-based row index being rendered by `kuro--update-line-full'.
Read by `kuro--apply-blink-overlay' to avoid O(position) `line-number-at-pos'.")

(defvar kuro--row-positions nil
  "Forward reference; `defvar-local' in kuro-render-buffer.el.
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

(defconst kuro--animation-default-gap-ms 100
  "Default per-frame gap in milliseconds when a Kitty frame specifies z=0.
Used by `kuro--animation-advance' to clamp the playback timer interval.")

(defconst kuro--animation-min-gap-ms 20
  "Lower bound on the animation frame gap to avoid runaway timer churn.")

(kuro--defvar-permanent-local kuro--animation-timers
  (make-hash-table :test 'eql)
  "Hash table mapping image-id to its active playback timer.
Each entry holds the `run-with-timer' object driving frame advancement for a
playing multi-frame Kitty image.  Used to cancel/replace timers on re-render.")

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
    (kuro--register-blink-overlay ov blink-type row)))

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
  "Remove all Kitty Graphics image overlays from the current buffer.
Also cancels any in-flight animation playback timers."
  (kuro--clear-all-animations)
  (dolist (ov kuro--image-overlays)
    (when (overlay-buffer ov)
      (delete-overlay ov)))
  (setq kuro--image-overlays nil)
  (setq kuro--has-images nil))

(defun kuro--filter-overlays (overlays predicate &optional on-delete)
  "Delete overlays from OVERLAYS when PREDICATE returns non-nil.
Return the surviving overlays in original order.  Call ON-DELETE for each
deleted overlay after removing it from the buffer."
  (let ((remaining nil))
    (dolist (ov overlays)
      (if (funcall predicate ov)
          (progn
            (delete-overlay ov)
            (when on-delete
              (funcall on-delete ov)))
        (push ov remaining)))
    (nreverse remaining)))

(defun kuro--clear-row-image-overlays (row)
  "Remove image overlays that overlap ROW.
An overlay overlaps when it starts before row end
and ends after row start.
Uses `kuro--row-positions' cache for O(1) row navigation when available."
  (save-excursion
    (kuro--goto-row-start row)
    (let ((line-start (point))
          (line-end (1+ (line-end-position))))
      (setq kuro--image-overlays
            (kuro--filter-overlays
             kuro--image-overlays
             (lambda (ov)
               (and (overlay-buffer ov)
                    (< (overlay-start ov) line-end)
                    (> (overlay-end ov) line-start)))))
      (unless kuro--image-overlays
        (setq kuro--has-images nil)))))

(defun kuro--decode-png-image (b64)
  "Decode base64 B64 and return an Emacs PNG image object.
May signal an error if B64 is malformed or `create-image' fails."
  (create-image
   (encode-coding-string (base64-decode-string b64) 'binary)
   'png t))

(defun kuro--place-image-overlay (img row col cell-width &optional image-id)
  "Create a display overlay for IMG at grid (ROW, COL) spanning CELL-WIDTH cols.
Uses `forward-char' for column positioning so wide characters (2 terminal
columns, 1 buffer position) are handled correctly.  Pushes the new overlay
onto `kuro--image-overlays'.  No-op if the grid position is beyond the buffer.
When IMAGE-ID is non-nil it is stored on the overlay so animation playback
\(`kuro--animation-advance') can locate and update the right overlay.
Returns the created overlay, or nil when out of bounds."
  (let* ((start (save-excursion
                  (kuro--goto-row-start row)
                  (forward-char col)
                  (point)))
         (end (min (+ start cell-width) (point-max))))
    (when (< start (point-max))
      (let ((ov (make-overlay start end)))
        (overlay-put ov 'kuro-image t)
        (when image-id (overlay-put ov 'kuro-image-id image-id))
        (overlay-put ov 'display    img)
        (overlay-put ov 'evaporate  t)   ; auto-delete if region deleted
        (push ov kuro--image-overlays)
        (setq kuro--has-images t)
        ov))))

(defun kuro--render-image-notification (notif)
  "Render a single Kitty Graphics image placement NOTIF in the terminal buffer.
NOTIF is a list of the form (IMAGE-ID ROW COL CELL-WIDTH CELL-HEIGHT).
Creates an overlay with a `display' property at the correct grid position.
When the image is a playing multi-frame Kitty animation, a timer-driven
playback loop is (re)started via `kuro--maybe-start-animation'."
  (pcase-let* ((`(,image-id ,row ,col ,raw-width . ,_) notif)
               (cell-width (max 1 raw-width))
               (b64 (kuro--get-image image-id)))
    (when (and b64 (stringp b64) (not (string-empty-p b64)))
      (condition-case err
          (when-let* ((img (kuro--decode-png-image b64)))
            (kuro--place-image-overlay img row col cell-width image-id)
            (kuro--maybe-start-animation image-id))
        (error
         (message "kuro: image render error for id %d: %s" image-id err))))))

;;; Animation playback (Kitty a=f frames + a=a control)

(defun kuro--animation-clamp-gap (gap-ms)
  "Clamp Kitty frame GAP-MS to a sane timer interval in seconds.
A GAP-MS of 0 falls back to `kuro--animation-default-gap-ms'; all values are
floored at `kuro--animation-min-gap-ms' to avoid runaway timers."
  (let ((ms (if (and (integerp gap-ms) (> gap-ms 0))
                gap-ms
              kuro--animation-default-gap-ms)))
    (/ (max kuro--animation-min-gap-ms ms) 1000.0)))

(defun kuro--animation-cancel (image-id)
  "Cancel and forget any running playback timer for IMAGE-ID."
  (when-let* ((timer (gethash image-id kuro--animation-timers)))
    (cancel-timer timer)
    (remhash image-id kuro--animation-timers)))

(defun kuro--animation-overlay-for-id (image-id)
  "Return the live image overlay tagged with IMAGE-ID, or nil."
  (seq-find (lambda (ov)
              (and (overlay-buffer ov)
                   (eql (overlay-get ov 'kuro-image-id) image-id)))
            kuro--image-overlays))

(defun kuro--animation-advance (buffer image-id frame-index)
  "Advance IMAGE-ID's animation in BUFFER to FRAME-INDEX and reschedule.
Renders the frame's PNG onto the tagged overlay's `display' property and arms
the next tick using the frame gap.  Stops cleanly when the buffer is gone, the
overlay disappeared, playback was halted (a=a,s=1), or the loop count is
exhausted."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (kuro--animation-cancel image-id)
      (let* ((state (kuro--image-animation-state image-id))
             (playing (nth 0 state))
             (count (kuro--image-frame-count image-id))
             (ov (kuro--animation-overlay-for-id image-id)))
        (when (and state playing ov (> count 1))
          (let* ((idx (mod frame-index count))
                 (b64 (kuro--image-frame-png image-id idx)))
            (when (and b64 (stringp b64) (not (string-empty-p b64)))
              (condition-case err
                  (overlay-put ov 'display (kuro--decode-png-image b64))
                (error
                 (message "kuro: animation frame error id %d: %s" image-id err))))
            (let ((gap (kuro--animation-clamp-gap
                        (kuro--image-frame-gap image-id idx))))
              (puthash image-id
                       (run-with-timer gap nil
                                       #'kuro--animation-advance
                                       buffer image-id (1+ idx))
                       kuro--animation-timers))))))))

(defun kuro--maybe-start-animation (image-id)
  "Start timer-driven playback for IMAGE-ID when it is a playing animation.
No-op for still images, paused animations, or single-frame images.  Always
restarts from the backend's current frame so a=a control changes take effect."
  (let* ((state (kuro--image-animation-state image-id))
         (playing (nth 0 state))
         (current (or (nth 1 state) 1))
         (count (kuro--image-frame-count image-id)))
    (if (and state playing (> count 1))
        ;; current is 1-based from the backend; advance shows the 0-based frame.
        (kuro--animation-advance (current-buffer) image-id (1- current))
      (kuro--animation-cancel image-id))))

(defun kuro--clear-all-animations ()
  "Cancel every running animation playback timer in the current buffer."
  (when (hash-table-p kuro--animation-timers)
    (maphash (lambda (_id timer) (cancel-timer timer)) kuro--animation-timers)
    (clrhash kuro--animation-timers)))

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

(defsubst kuro--apply-ffi-face-effects (start-pos end-pos flags)
  "Apply blink and hidden effects for FLAGS to START-POS..END-POS."
  (cond
   ((/= 0 (logand flags kuro--sgr-flag-blink-fast))
    (kuro--apply-blink-overlay start-pos end-pos 'fast))
   ((/= 0 (logand flags kuro--sgr-flag-blink-slow))
    (kuro--apply-blink-overlay start-pos end-pos 'slow)))
  (when (/= 0 (logand flags kuro--sgr-flag-hidden))
    (add-text-properties start-pos end-pos '(invisible t))))

(defsubst kuro--apply-ffi-face-properties (start-pos end-pos face)
  "Apply FACE to START-POS..END-POS using the active Emacs code path."
  (if (>= emacs-major-version 29)
      (add-face-text-property start-pos end-pos face)
    (setcar (cdr kuro--face-prop-template) face)
    (add-text-properties start-pos end-pos kuro--face-prop-template)))

(defun kuro--remove-blink-overlay-from-lists (ov)
  "Remove OV from the blink overlay collections."
  (setq kuro--blink-overlays (delq ov kuro--blink-overlays))
  (if (eq (overlay-get ov 'kuro-blink-type) 'slow)
      (setq kuro--blink-overlays-slow
            (delq ov kuro--blink-overlays-slow))
    (setq kuro--blink-overlays-fast
          (delq ov kuro--blink-overlays-fast))))

(defun kuro--reset-blink-overlays (remaining)
  "Replace blink overlay collections with REMAINING and rebuild type lists."
  (let ((remaining-slow nil)
        (remaining-fast nil))
    (dolist (ov remaining)
      (if (eq (overlay-get ov 'kuro-blink-type) 'slow)
          (push ov remaining-slow)
        (push ov remaining-fast)))
    (setq kuro--blink-overlays remaining
          kuro--blink-overlays-slow (nreverse remaining-slow)
          kuro--blink-overlays-fast (nreverse remaining-fast))))

(defsubst kuro--call-with-normalized-ffi-face-range (face-ranges base line-start line-end continuation)
  "Normalize a FACE-RANGES chunk at BASE, then call CONTINUATION.
FACE-RANGES is a flat stride-6 vector with layout
[start end fg bg flags ul ...].  BASE points at the first slot of one range.
The start and end offsets are relative to LINE-START.  If the normalized
range is empty after clamping, return nil without invoking CONTINUATION."
  (let* ((start-pos (max line-start
                         (min line-end (+ line-start (aref face-ranges base)))))
         (end-pos   (max line-start
                         (min line-end (+ line-start (aref face-ranges (1+ base)))))))
    (when (> end-pos start-pos)
      (funcall continuation
               start-pos end-pos
               (aref face-ranges (+ base 2))
               (aref face-ranges (+ base 3))
               (aref face-ranges (+ base 4))
               (aref face-ranges (+ base 5))))))

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
    (let ((face (kuro--get-cached-face-raw fg-enc bg-enc flags ul-color-enc)))
      (kuro--apply-ffi-face-properties start-pos end-pos face)
      (when (kuro--ffi-face-has-visual-effects-p flags)
        (kuro--apply-ffi-face-effects start-pos end-pos flags)))))

(provide 'kuro-overlays)

;;; kuro-overlays.el ends here
