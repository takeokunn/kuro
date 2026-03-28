;;; kuro-render-buffer.el --- Buffer update functions for Kuro terminal -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:
;; Buffer manipulation functions: line updates, cursor positioning, scroll application.

;;; Code:

(require 'cl-lib)
(require 'kuro-ffi)
(require 'kuro-ffi-modes)
(require 'kuro-faces)
(require 'kuro-overlays)

(declare-function kuro--clear-row-image-overlays "kuro-overlays" (row))
(defvar kuro--has-images nil
  "Forward reference; defvar-local in kuro-overlays.el.")
(defvar kuro--blink-overlays-by-row nil
  "Forward reference; defvar-local in kuro-overlays.el.")
(declare-function kuro--apply-ffi-face-at "kuro-overlays" (start-pos end-pos fg-enc bg-enc flags ul-color-enc))
(declare-function kuro--get-cursor         "kuro-ffi"       ())
(declare-function kuro--get-cursor-visible "kuro-ffi-modes" ())
(declare-function kuro--get-cursor-shape   "kuro-ffi-modes" ())

;;; Buffer-local row position cache

(kuro--defvar-permanent-local kuro--row-positions nil
  "Vector mapping row index to buffer position, or nil when uninitialized.
Set to `(make-vector rows nil)' during buffer setup / resize.
Entries are set on first access and invalidated (reset to nil) on scroll
and resize.  Avoids repeated O(row) `forward-line' traversals.")

;;; Edit guard macro

(defmacro kuro--with-buffer-edit (&rest body)
  "Execute BODY with read-only and modification hooks suppressed.
Saves and restores point via `save-excursion'."
  `(let ((inhibit-read-only t)
         (inhibit-modification-hooks t))
     (save-excursion
       ,@body)))

;;; Row position cache helpers

(defun kuro--init-row-positions (rows)
  "Initialize `kuro--row-positions' as a vector of ROWS nil entries."
  (setq kuro--row-positions (make-vector rows nil)))

(defun kuro--invalidate-row-positions ()
  "Clear all cached row positions (called after scroll or resize)."
  (when kuro--row-positions
    (fillarray kuro--row-positions nil)))

;;; Scroll event application

(defun kuro--scroll-lines (direction n _last-rows)
  "Move N terminal lines in DIRECTION (\\='up or \\='down) within the current buffer.
_LAST-ROWS is accepted for interface symmetry but not used; N is applied as-is.
For \\='up: delete the first N lines in one operation and insert N blank lines at bottom.
For \\='down: delete the last N lines in one operation and insert N blank lines at top.
Must be called with `inhibit-read-only' and `inhibit-modification-hooks'
already bound non-nil by the caller.  The outer `kuro--with-buffer-edit' already
provides `save-excursion', so no inner save-excursion is needed here."
  (if (eq direction 'up)
      ;; Scroll-up: delete first N lines then append N blank lines.
      (progn
        (goto-char (point-min))
        (delete-region (point-min) (progn (forward-line n) (point)))
        (goto-char (point-max))
        (insert (make-string n ?\n)))
    ;; Scroll-down: delete last N lines then prepend N blank lines.
    (goto-char (point-max))
    (delete-region (progn (forward-line (- n)) (point)) (point-max))
    (goto-char (point-min))
    (insert (make-string n ?\n)))
  ;; Buffer positions shifted; cached row positions are invalid.
  (kuro--invalidate-row-positions))

(defun kuro--apply-buffer-scroll (up down)
  "Apply pending full-screen scroll events to the Emacs buffer.
UP and DOWN are the number of full-screen scroll-up and scroll-down steps
accumulated in the Rust core since the last call.

NOTE: Currently `pending_scroll_up'/`pending_scroll_down' in Rust are never
incremented — full-screen scrolls use `full_dirty = true' instead.  This
function exists for a potential future two-path scroll design.

For each scroll-up step: delete the first buffer line and append a blank.
For each scroll-down step: delete the last buffer line and prepend a blank.
Also clears `kuro--col-to-buf-map' since row-indexed mappings are stale."
  (when (> (+ up down) 0)
    (kuro--with-buffer-edit
      (let ((last-rows kuro--last-rows))
        (when (> up 0)   (kuro--scroll-lines 'up   up   last-rows))
        (when (> down 0) (kuro--scroll-lines 'down down last-rows))))
    (clrhash kuro--col-to-buf-map)))

;;; Internal helpers

(defun kuro--clear-line-blink-overlays (line-start &optional row)
  "Remove blink overlays that fall within the current line.
LINE-START is the buffer position at the beginning of the line.
When ROW is provided, uses `kuro--blink-overlays-by-row' for O(1) lookup
instead of scanning the full overlay list.
Overlays spanning [LINE-START, (1+ (line-end-position))] are deleted;
all others are retained in `kuro--blink-overlays'.
Must be called before the line text is replaced (uses pre-replace line-end)."
  (when kuro--blink-overlays
    (if (and row (hash-table-p kuro--blink-overlays-by-row))
        ;; Fast path: only scan overlays on this specific row.
        (let ((row-ovs (gethash row kuro--blink-overlays-by-row))
              (line-end-before (1+ (line-end-position))))
          (when row-ovs
            (dolist (ov row-ovs)
              (when (and (overlay-buffer ov)
                         (>= (overlay-start ov) line-start)
                         (<= (overlay-end ov) line-end-before))
                (delete-overlay ov)
                (setq kuro--blink-overlays (delq ov kuro--blink-overlays))))
            (remhash row kuro--blink-overlays-by-row)))
      ;; Fallback: full scan when row unavailable.
      (let ((line-end-before (1+ (line-end-position)))
            (remaining nil))
        (dolist (ov kuro--blink-overlays)
          (if (and (overlay-buffer ov)
                   (>= (overlay-start ov) line-start)
                   (<= (overlay-end ov) line-end-before))
              (delete-overlay ov)
            (push ov remaining)))
        (setq kuro--blink-overlays (nreverse remaining))))))

(defun kuro--apply-face-ranges (face-ranges line-start line-end)
  "Apply FACE-RANGES to the line bounded by LINE-START and LINE-END.
Each range is a 6-element list (START-BUF END-BUF FG-ENC BG-ENC FLAGS UL-COLOR-ENC)
with byte offsets relative to LINE-START.  UL-COLOR-ENC is the encoded
underline color transmitted in the version-2 binary wire format (0 = default).
Must be called after the line text has been inserted (uses post-insert line-end)."
  (when face-ranges
    (dolist (range face-ranges)
      (pcase-let* ((`(,start-buf ,end-buf ,fg-enc ,bg-enc ,flags ,ul-color-enc) range))
        (let ((start-pos (min (+ line-start start-buf) line-end))
              (end-pos   (min (+ line-start end-buf)   line-end)))
          (when (> end-pos start-pos)
            (kuro--apply-ffi-face-at start-pos end-pos fg-enc bg-enc flags ul-color-enc)))))))

(defun kuro--ensure-buffer-row-exists (row)
  "Ensure the buffer has at least ROW+1 lines and position point at ROW start.
Uses `kuro--row-positions' cache to avoid repeated O(row) `forward-line'
traversals.  On a cache hit, jumps directly via `goto-char'.  On a miss,
falls back to `forward-line' and caches the result.
Must be called with `inhibit-read-only' and `inhibit-modification-hooks'
already bound non-nil by the caller."
  (let ((cached (and kuro--row-positions
                     (< row (length kuro--row-positions))
                     (aref kuro--row-positions row))))
    (if cached
        (goto-char cached)
      (let ((not-moved (progn (goto-char (point-min)) (forward-line row))))
        (when (> not-moved 0)
          (goto-char (point-max))
          (unless (and (> (point-max) (point-min))
                       (= (char-before) ?\n))
            (insert "\n"))
          (dotimes (_ not-moved)
            (insert "\n"))
          (goto-char (point-min))
          (forward-line row))
        ;; Cache the resolved position for future calls.
        (when (and kuro--row-positions (< row (length kuro--row-positions)))
          (aset kuro--row-positions row (point)))))))

;;; Cursor shape helpers

(defun kuro--decscusr-to-cursor-type (shape)
  "Convert DECSCUSR SHAPE integer to Emacs cursor-type symbol.
SHAPE is 0-6 per the DECSCUSR specification (CSI Ps SP q):
  0/1 = blinking block, 2 = steady block,
  3 = blinking underline, 4 = steady underline,
  5 = blinking bar (I-beam), 6 = steady bar (I-beam).
Returns a `cursor-type' value suitable for `setq-local cursor-type'."
  (pcase shape
    (0 'box)          ; default blinking block
    (1 'box)          ; blinking block
    (2 'box)          ; steady block
    (3 '(hbar . 2))   ; blinking underline
    (4 '(hbar . 2))   ; steady underline
    (5 '(bar . 2))    ; blinking bar (I-beam)
    (6 '(bar . 2))    ; steady bar (I-beam)
    (_ 'box)))

;;; Buffer update functions

(defun kuro--clear-row-overlays (row)
  "Clear all blink and image overlays on ROW from the terminal buffer.
Updates `kuro--blink-overlays' and `kuro--image-overlays' in place.
Must be called inside `save-excursion' after `kuro--ensure-buffer-row-exists'
has positioned point at the start of ROW, so that `(point)' yields line-start
for the blink-overlay bounds check."
  ;; `kuro--has-images' is a dedicated flag set only when an image overlay
  ;; exists, avoiding the separate O(row) navigation in the common no-image case.
  (when kuro--has-images
    (kuro--clear-row-image-overlays row))
  (kuro--clear-line-blink-overlays (point) row))

(defun kuro--store-col-to-buf (row col-to-buf)
  "Store or remove the COL-TO-BUF mapping for ROW in `kuro--col-to-buf-map'.
If COL-TO-BUF is a non-empty vector, stores it.  If nil or empty, removes any
existing entry so stale CJK mappings do not persist after an ASCII redraw."
  (if (and (vectorp col-to-buf) (> (length col-to-buf) 0))
      (puthash row col-to-buf kuro--col-to-buf-map)
    (when (integerp row)
      (remhash row kuro--col-to-buf-map))))

(defun kuro--update-line-full (row text face-ranges col-to-buf)
  "Navigate to ROW exactly once and perform all line-update operations atomically.
TEXT replaces the current line content.  FACE-RANGES is a list of FFI face
range 5-tuples as returned by `kuro-core-poll-updates-with-faces', or nil.
COL-TO-BUF is the grid-column → buffer-char-offset vector for this row, or nil.
FACE-RANGES is a list of FFI face range 6-tuples as returned by the render FFI,
or nil.

Performs text replacement, blink-overlay clearing, and face application in a
single `save-excursion' block, reducing O(N²) triple-navigation to O(N)
single-pass when N rows are dirty.

Critical: `line-end' is recomputed with `(line-end-position)' AFTER the
delete+insert so face ranges use the new content offsets, not cached old ones."
  (when (and (integerp row) (stringp text))
    (kuro--store-col-to-buf row col-to-buf)
    (kuro--with-buffer-edit
      (kuro--ensure-buffer-row-exists row)
      (let* ((line-start (point))
             (old-end (line-end-position))
             (old-len (- old-end line-start)))
        (kuro--clear-row-overlays row)
        (delete-region line-start old-end)
        (insert text)
        ;; Capture new line-end once; used for both face application and cache update.
        (let ((new-line-end (line-end-position)))
          ;; When line length changed, buffer positions for rows after this one
          ;; are shifted.  Row+1's start is exactly (1+ new-line-end), which we
          ;; can cache directly; rows +2 and beyond are unknown and cleared.
          (unless (= (length text) old-len)
            (when (and kuro--row-positions (< (1+ row) (length kuro--row-positions)))
              (let ((len (length kuro--row-positions)))
                ;; Cache row+1's exact start position instead of invalidating it.
                (aset kuro--row-positions (1+ row) (1+ new-line-end))
                (cl-loop for i from (+ row 2) below len
                         do (aset kuro--row-positions i nil)))))
          ;; line-end MUST be recomputed after insert: multi-byte text means
          ;; (+ line-start (length text)) would be wrong.
                              (kuro--apply-face-ranges face-ranges line-start new-line-end))))))

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
col_to_buf[col] gives the buffer char offset for cursor column COL on ROW.
For pure ASCII lines, col == buf-offset; for CJK lines, col > buf-offset
because wide placeholder cells are skipped in the buffer.
Falls back to COL when the mapping is absent or shorter than COL
(e.g. cursor past last content — trailing spaces are pure ASCII)."
  (let* ((row-map    (gethash row kuro--col-to-buf-map))
         (buf-offset (if (and row-map (< col (length row-map)))
                         (aref row-map col)
                       col)))
    (save-excursion
      (goto-char (point-min))
      (forward-line row)
      (goto-char (min (+ (point) buf-offset) (line-end-position)))
      (point))))

(defun kuro--anchor-window-at-pos (win target-pos)
  "Anchor WIN display at point-min and move its point to TARGET-POS.
`set-window-start' must precede `set-window-point' so TARGET-POS lands
within the already-anchored viewport; together they prevent Emacs from
scrolling when a full-screen app (vim, htop) moves the cursor to the
last row.  Both calls are guarded by equality checks to avoid
unnecessary redisplay triggers."
  (unless (= (window-start win) (point-min))
    (set-window-start win (point-min)))
  (unless (= (window-point win) target-pos)
    (set-window-point win target-pos)))

(defun kuro--apply-cursor-display (visible shape)
  "Set buffer-local `cursor-type' from VISIBLE flag and SHAPE integer.
SHAPE is a DECSCUSR value (0-6, see `kuro--decscusr-to-cursor-type').
When VISIBLE is nil the cursor is hidden by setting `cursor-type' to nil."
  (setq-local cursor-type
              (if visible
                  (kuro--decscusr-to-cursor-type (or shape 0))
                nil)))

;;; Cursor update

(defun kuro--update-cursor ()
  "Update cursor position and shape in buffer.
Uses the consolidated `kuro--get-cursor-state' to fetch position,
visibility, and shape in a single Mutex acquisition (PERF-004).
Skips buffer position computation when cursor state is unchanged."
  (unless (> kuro--scroll-offset 0)
    (when-let ((state (kuro--get-cursor-state)))
      (pcase-let* ((`(,row ,col ,visible ,shape) state))
        (unless (and (eql row kuro--last-cursor-row)
                     (eql col kuro--last-cursor-col)
                     (eq  visible kuro--last-cursor-visible)
                     (eql shape kuro--last-cursor-shape))
          (setq kuro--last-cursor-row     row
                kuro--last-cursor-col     col
                kuro--last-cursor-visible visible
                kuro--last-cursor-shape   shape)
          (let ((target-pos (kuro--grid-col-to-buffer-pos row col)))
            (when kuro--cursor-marker
              (set-marker kuro--cursor-marker target-pos))
            (when-let ((win (get-buffer-window (current-buffer) t)))
              (kuro--anchor-window-at-pos win target-pos))
            (kuro--apply-cursor-display visible shape)))))))

(provide 'kuro-render-buffer)

;;; kuro-render-buffer.el ends here
