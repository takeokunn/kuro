;;; kuro-render-cursor.el --- Cursor state and display for Kuro terminal  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Cursor position, shape, and window-anchoring for the Kuro terminal display.
;;
;; Provides `kuro--update-cursor' (position + shape update per frame) and
;; `kuro--update-scroll-indicator' (header-line scrollback hint).
;; Split from kuro-render-buffer.el to keep both files ≤ 500L.

;;; Code:

(require 'kuro-ffi)
(require 'kuro-ffi-modes)
(require 'kuro-render-cursor-macros)

;; Forward references for vars defined in kuro-render-buffer.el
(defvar kuro--row-positions)
(defvar kuro--col-to-buf-map)
(defvar kuro--cursor-marker)
(defvar kuro--scroll-offset)

(declare-function kuro--decscusr-to-cursor-type "kuro-render-buffer" (shape))
(declare-function kuro--goto-row-start "kuro-render-buffer" (row))

;;; Cursor state cache

(kuro--defvar-permanent-local kuro--last-cursor-row nil
  "Cached cursor row from the previous render frame.
Used to skip redundant cursor position computation when unchanged.")

(kuro--defvar-permanent-local kuro--last-cursor-col nil
  "Cached cursor column from the previous render frame.
Used to skip redundant cursor position computation when unchanged.")

(kuro--defvar-permanent-local kuro--last-cursor-visible nil
  "Cached cursor visibility from the previous render frame.")

(kuro--defvar-permanent-local kuro--last-cursor-shape nil
  "Cached cursor shape from the previous render frame.")

;;; Cursor position helpers

(defun kuro--grid-col-to-buffer-pos (row col)
  "Convert grid (ROW, COL) to a buffer position using the col-to-buf map.
The `col-to-buf' vector gives the buffer char offset for cursor column COL on
ROW.  For pure ASCII lines, COL == buf-offset; for CJK lines, COL > buf-offset
because wide placeholder cells are skipped in the buffer.
Falls back to COL when the mapping is absent or shorter than COL
\(e.g. cursor past last content - trailing spaces are pure ASCII).
Uses `kuro--row-positions' cache for O(1) row navigation when available;
falls back to O(row) `forward-line' only when the cache misses."
  (let* ((row-map    (gethash row kuro--col-to-buf-map))
         (buf-offset (if (and row-map (< col (length row-map)))
                         (aref row-map col)
                       col)))
    (save-excursion
      (kuro--goto-row-start row)
      (goto-char (min (+ (point) buf-offset) (line-end-position)))
      (point))))

(defun kuro--anchor-window-at-pos (win target-pos)
  "Anchor WIN display at point-min and move its point to TARGET-POS.
`set-window-start' must precede `set-window-point' so TARGET-POS lands
within the already-anchored viewport; together they prevent Emacs from
scrolling when a full-screen app (vim, htop) moves the cursor to the
last row.  Both calls are guarded by equality checks to avoid
unnecessary redisplay triggers.
Also resets vscroll and hscroll to zero: tall image overlays
\(Sixel/Kitty) can leave non-zero vscroll, and horizontal scroll
drift can accumulate even with `auto-hscroll-mode' disabled."
  (unless (= (window-start win) (point-min))
    (set-window-start win (point-min)))
  (unless (= (window-point win) target-pos)
    (set-window-point win target-pos))
  (when (> (window-vscroll win) 0)
    (set-window-vscroll win 0))
  (when (> (window-hscroll win) 0)
    (set-window-hscroll win 0)))

(defconst kuro--decscusr-blinking-shapes '(0 1 3 5)
  "DECSCUSR shape codes that request a BLINKING cursor.
Per CSI Ps SP q: 0/1=blinking block, 3=blinking underline, 5=blinking bar.
The steady variants are 2 (block), 4 (underline), 6 (bar).")

(defsubst kuro--decscusr-blinking-p (shape)
  "Return non-nil when DECSCUSR SHAPE requests a blinking cursor.
Codes 0/1/3/5 blink; 2/4/6 are steady.  A non-integer or unknown SHAPE is
treated as the default (blinking) so it matches the DECSCUSR 0 default."
  (or (not (integerp shape))
      (memq shape kuro--decscusr-blinking-shapes)))

(defun kuro--apply-cursor-blink (visible shape)
  "Drive `blink-cursor-mode' from the DECSCUSR VISIBLE flag and SHAPE.
A visible blinking shape (DECSCUSR 0/1/3/5) enables `blink-cursor-mode';
a visible steady shape (2/4/6) disables it; a hidden cursor leaves blink
state untouched (nothing is shown anyway).  `blink-cursor-mode' is a global
minor mode, so it is only toggled when its state actually needs to change,
avoiding redundant timer churn."
  (when visible
    (let ((want (kuro--decscusr-blinking-p shape)))
      (cond
       ((and want (not (bound-and-true-p blink-cursor-mode)))
        (blink-cursor-mode 1))
       ((and (not want) (bound-and-true-p blink-cursor-mode))
        (blink-cursor-mode -1))))))

(defun kuro--apply-cursor-display (visible shape)
  "Set buffer-local `cursor-type' from VISIBLE flag and SHAPE integer.
SHAPE is a DECSCUSR value (0-6, see `kuro--decscusr-to-cursor-type').
When VISIBLE is nil the cursor is hidden by setting `cursor-type' to nil.
Also drives `blink-cursor-mode' so DECSCUSR blinking shapes (0/1/3/5)
blink and steady shapes (2/4/6) do not (see `kuro--apply-cursor-blink')."
  (setq-local cursor-type
              (if visible
                  (kuro--decscusr-to-cursor-type (or shape 0))
                nil))
  (kuro--apply-cursor-blink visible shape))

(defsubst kuro--cursor-state-changed-p (row col visible shape)
  "Return non-nil when (ROW COL VISIBLE SHAPE) differs from the cached state."
  (or (not (eql row     kuro--last-cursor-row))
      (not (eql col     kuro--last-cursor-col))
      (not (eq  visible kuro--last-cursor-visible))
      (not (eql shape   kuro--last-cursor-shape))))

;;; Cursor window cache

(kuro--defvar-permanent-local kuro--cached-window nil
  "Cached window object for this terminal buffer.
Validated with `window-live-p' (O(1) C check) on each frame instead of
calling `get-buffer-window' with t (walks every live frame's window tree).
Reset to nil by `kuro--start-render-loop' so the cache is rebuilt after
buffer re-display in a new window.")

;;; Cursor update helpers

(defsubst kuro--resolve-window ()
  "Return the live window for this buffer, refreshing the cache if stale.
`window-live-p' is an O(1) C predicate; `get-buffer-window' with t walks
every live frame's window tree — called only on cache miss."
  (if (window-live-p kuro--cached-window)
      kuro--cached-window
    (setq kuro--cached-window (get-buffer-window (current-buffer) t))))

(defsubst kuro--ensure-cursor-marker (pos)
  "Ensure `kuro--cursor-marker' exists and points to POS."
  (if kuro--cursor-marker
      (set-marker kuro--cursor-marker pos)
    (setq kuro--cursor-marker (copy-marker pos))))

(defsubst kuro--cursor-fallback-pos (row col)
  "Return cursor buffer position at ROW and COL from marker or grid."
  (or (and kuro--cursor-marker (marker-position kuro--cursor-marker))
      (kuro--grid-col-to-buffer-pos row col)))

(defsubst kuro--cursor-state-parts (state)
  "Return cursor STATE as a list of row, col, visibility, and shape."
  (pcase-let ((`(,row ,col ,visible ,shape) state))
    (list row col visible shape)))

(defsubst kuro--apply-cursor-state-change (win row col visible shape)
  "Persist cursor state for WIN, ROW, COL, VISIBLE, and SHAPE."
  (let ((target-pos (kuro--grid-col-to-buffer-pos row col)))
    (kuro--cache-cursor-state row col visible shape)
    (kuro--ensure-cursor-marker target-pos)
    (kuro--anchor-window-at-pos win target-pos)
    (kuro--apply-cursor-display visible shape)))

(defsubst kuro--reanchor-cursor-window (win row col)
  "Re-anchor WIN to the cached or fallback cursor position for ROW and COL."
  (kuro--anchor-window-at-pos win (kuro--cursor-fallback-pos row col)))

;;; Cursor update

(defun kuro--update-cursor ()
  "Update cursor position and shape in buffer.
Uses the consolidated `kuro--get-cursor-state' to fetch position,
visibility, and shape in a single Mutex acquisition (PERF-004).
Skips buffer position computation when cursor state is unchanged,
but ALWAYS re-anchors the window at point-min to prevent Emacs'
native redisplay from drifting the viewport between render cycles."
  (unless (> kuro--scroll-offset 0)
    (when-let* ((state (kuro--get-cursor-state))
                (win (kuro--resolve-window)))
      (pcase-let ((`(,row ,col ,visible ,shape) (kuro--cursor-state-parts state)))
        (if (kuro--cursor-state-changed-p row col visible shape)
            (kuro--apply-cursor-state-change win row col visible shape)
          (kuro--reanchor-cursor-window win row col))))))

;;; Scrollback indicator

(kuro--defvar-permanent-local kuro--last-scroll-indicator-offset -1
  "Cached `kuro--scroll-offset' value from the last header-line update.
Initialized to -1 (impossible offset) so the first render always writes the
header-line even when the initial offset is 0.  Compared with `eql' (integer
equality, no allocation) to avoid calling `format' + `equal' every frame.")

(defun kuro--update-scroll-indicator ()
  "Update header-line to show scrollback position.
When `kuro--scroll-offset' is positive, display a header-line indicating
how many lines into scrollback history the user has scrolled.
When at live view (offset 0), remove the header-line.

Uses an integer cache (`kuro--last-scroll-indicator-offset') so that string
construction runs only when the offset changes — not every frame.
`concat' + `number-to-string' avoids the printf-style parse overhead of
`format' for this single-integer case."
  (let ((offset kuro--scroll-offset))
    (unless (eql offset kuro--last-scroll-indicator-offset)
      (setq kuro--last-scroll-indicator-offset offset)
      (setq header-line-format
            (when (> offset 0)
              (concat " ↑ Scrollback: +" (number-to-string offset) " lines (S-End to return) "))))))

(provide 'kuro-render-cursor)

;;; kuro-render-cursor.el ends here
