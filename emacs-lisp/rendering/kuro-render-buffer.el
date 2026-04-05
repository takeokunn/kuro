;;; kuro-render-buffer.el --- Buffer update functions for Kuro terminal  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; Buffer manipulation layer for the Kuro terminal display.
;;
;; Provides per-row text update (`kuro--update-line-full'), cursor
;; positioning (`kuro--update-cursor'), and full-screen scroll
;; application (`kuro--apply-buffer-scroll').  Also manages the
;; row-position cache, col-to-buf wide-character mapping, scroll
;; indicator overlay, and DECSCUSR cursor shape display.

;;; Code:

(require 'cl-lib)
(require 'kuro-ffi)
(require 'kuro-ffi-modes)
(require 'kuro-faces)
(require 'kuro-overlays)

(declare-function kuro--clear-row-image-overlays "kuro-overlays" (row))
(declare-function kuro--call-with-normalized-ffi-face-range "kuro-overlays" (range line-start line-end continuation))
(defvar kuro--has-images nil
  "Forward reference; defvar-local in kuro-overlays.el.")
(defvar kuro--blink-overlays-by-row nil
  "Forward reference; defvar-local in kuro-overlays.el.")
(defvar kuro--scroll-offset 0
  "Forward reference; defvar-local in kuro-input.el.")
(defvar kuro--cursor-marker nil
  "Forward reference; defvar-local in kuro-renderer.el.")
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

(kuro--defvar-permanent-local kuro--current-render-row -1
  "Row index (0-based) currently being rendered by `kuro--update-line-full'.
Set to ROW before `kuro--apply-face-ranges' is called so that
`kuro--apply-blink-overlay' can index `kuro--blink-overlays-by-row'
without calling `line-number-at-pos' (O(position)).
Reset to -1 after the render call completes.")

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
  "Move N terminal lines in DIRECTION (\\='up or \\='down) in the buffer.
_LAST-ROWS is accepted for interface symmetry but not used; N is applied as-is.
For \\='up: delete the first N lines and insert N blank lines at bottom.
For \\='down: delete the last N lines and insert N blank lines at top.
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

(defun kuro--clear-line-blink-overlays (line-start &optional row pre-end)
  "Remove blink overlays that fall within the current line.
LINE-START is the buffer position at the beginning of the line.
When ROW is provided, uses `kuro--blink-overlays-by-row' for O(1) lookup
instead of scanning the full overlay list.
PRE-END is the pre-replace line-end position (already computed by the caller
as `old-end').  When nil, `(line-end-position)' is called as fallback.
Passing PRE-END avoids a redundant O(cols) `line-end-position' scan per
dirty row (3,600 saved calls/sec at 30 rows × 120fps).
Must be called before the line text is replaced (uses pre-replace line-end)."
  (when kuro--blink-overlays
    (let ((line-end-before (1+ (or pre-end (line-end-position)))))
      (if (and row (hash-table-p kuro--blink-overlays-by-row))
          ;; Fast path: only scan overlays on this specific row.
          (let ((row-ovs (gethash row kuro--blink-overlays-by-row)))
            (when row-ovs
              (dolist (ov row-ovs)
                (when (and (overlay-buffer ov)
                           (>= (overlay-start ov) line-start)
                           (<= (overlay-end ov) line-end-before))
                  (delete-overlay ov)
                  (setq kuro--blink-overlays (delq ov kuro--blink-overlays))
                  ;; Maintain typed sub-lists; overlay-get on a deleted overlay
                  ;; is safe (properties survive delete-overlay).
                  (if (eq (overlay-get ov 'kuro-blink-type) 'slow)
                      (setq kuro--blink-overlays-slow
                            (delq ov kuro--blink-overlays-slow))
                    (setq kuro--blink-overlays-fast
                          (delq ov kuro--blink-overlays-fast)))))
              (remhash row kuro--blink-overlays-by-row)))
        ;; Fallback: full scan when row unavailable.
        ;; Rebuild typed sub-lists in the same pass to keep them in sync.
        (let ((remaining nil)
              (remaining-slow nil)
              (remaining-fast nil))
          (dolist (ov kuro--blink-overlays)
            (if (and (overlay-buffer ov)
                     (>= (overlay-start ov) line-start)
                     (<= (overlay-end ov) line-end-before))
                (delete-overlay ov)
              (if (eq (overlay-get ov 'kuro-blink-type) 'slow)
                  (push ov remaining-slow)
                (push ov remaining-fast))
              (push ov remaining)))
          (setq kuro--blink-overlays      (nreverse remaining)
                kuro--blink-overlays-slow remaining-slow
                kuro--blink-overlays-fast remaining-fast))))))

(defsubst kuro--apply-face-ranges (face-ranges line-start line-end)
  "Apply FACE-RANGES to the line bounded by LINE-START and LINE-END.
FACE-RANGES is a FLAT stride-6 vector produced by `kuro--decode-face-ranges',
or nil for no face data.  Layout: [s0 e0 fg0 bg0 f0 ul0 s1 e1 fg1 bg1 f1 ul1 …].
Each range occupies 6 consecutive slots — start-buf, end-buf, fg-enc, bg-enc,
flags, ul-color-enc — with byte offsets relative to LINE-START.
Must be called after the line text has been inserted (post-insert line-end).

Stride-6 flat layout eliminates the inner-vector allocation per range that the
old vector-of-vectors required (~21,600 allocs/sec at 120fps × 30 dirty rows ×
6 face ranges/row).  `(/ (length nil) 6)' = 0 so nil is handled safely.

`defsubst' inlines this at call sites in `kuro--update-line-full', eliminating
one function-call dispatch per dirty row per frame (~3,600/sec at 120fps × 30
dirty rows).  An advancing `base' pointer replaces the `(* i 6)' multiply in
the old dotimes variant — eliminates ~21,600 integer multiplies/sec.
`(when face-ranges ...)' nil guard avoids `(length nil)' + `<' on the ~50%
of plain-text rows with no face data — saves ~1,800 function calls/sec."
  (when face-ranges
    (let ((len (length face-ranges))
          (base 0))
      (while (< base len)
      (let* ((b1        (1+ base))
             (b2        (1+ b1))
             (b3        (1+ b2))
             (b4        (1+ b3))
             (b5        (1+ b4))
             (start-pos (min (+ line-start (aref face-ranges base)) line-end))
             (end-pos   (min (+ line-start (aref face-ranges b1))   line-end)))
        (when (> end-pos start-pos)
          (kuro--apply-ffi-face-at
           start-pos end-pos
           (aref face-ranges b2)
           (aref face-ranges b3)
           (aref face-ranges b4)
           (aref face-ranges b5)))
        (setq base (1+ b5)))))))

(defun kuro--update-row-position-cache-after-line-change (row old-len new-len new-line-end)
  "Refresh cached row positions after replacing ROW from OLD-LEN to NEW-LEN.
When the row length changes, ROW+1 is updated exactly from NEW-LINE-END,
and all later cached positions are adjusted by the length delta in a single
vector sweep.  This avoids the O(row × dirty-rows) fallback to `forward-line'
that occurs when downstream entries are simply cleared."
  (when (and (/= old-len new-len) kuro--row-positions)
    (let* ((rp   kuro--row-positions)
           (len  (length rp))
           (row1 (1+ row)))
      (when (< row1 len)
        (let ((delta (- new-len old-len)))
          (aset rp row1 (1+ new-line-end))
          (let ((i (1+ row1)))
            (while (< i len)
              (let ((cached (aref rp i)))
                (when cached
                  (aset rp i (+ cached delta))))
              (setq i (1+ i)))))))))

(defun kuro--ensure-buffer-row-exists (row)
  "Ensure the buffer has at least ROW+1 lines and position point at ROW start.
Uses `kuro--row-positions' cache to avoid repeated O(row) `forward-line'
traversals.  On a cache hit, jumps directly via `goto-char'.  On a miss,
falls back to `forward-line' and caches the result.
Must be called with `inhibit-read-only' and `inhibit-modification-hooks'
already bound non-nil by the caller."
  ;; Bind rp/len once: eliminates the double (< row (length kuro--row-positions))
  ;; call (cache-hit guard + cache-store guard) and double kuro--row-positions varref.
  (let* ((rp  kuro--row-positions)
         (len (if rp (length rp) 0))
         (cached (and (> len row) (aref rp row))))
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
        (when (> len row)
          (aset rp row (point)))))))

;;; Cursor shape data + helpers

(defconst kuro--decscusr-cursor-types
  [box box box (hbar . 2) (hbar . 2) (bar . 2) (bar . 2)]
  "Vector mapping DECSCUSR shape integers (0–6) to Emacs cursor-type values.
Indices per CSI Ps SP q spec: 0/1=blinking-block, 2=steady-block,
3=blinking-underline, 4=steady-underline, 5=blinking-bar, 6=steady-bar.")

(defsubst kuro--decscusr-to-cursor-type (shape)
  "Convert DECSCUSR SHAPE integer (0–6) to an Emacs `cursor-type' value.
Unknown shapes (negative, > 6, or non-integer) fall back to \\='box."
  (if (and (integerp shape)
           (>= shape 0)
           (< shape (length kuro--decscusr-cursor-types)))
      (aref kuro--decscusr-cursor-types shape)
    'box))

;;; Buffer update functions

(defun kuro--clear-row-overlays (row &optional pre-end)
  "Clear all blink and image overlays on ROW from the terminal buffer.
Updates `kuro--blink-overlays' and `kuro--image-overlays' in place.
PRE-END is the pre-replace line-end position forwarded to
`kuro--clear-line-blink-overlays' to avoid a duplicate `line-end-position'
scan.  When nil, `kuro--clear-line-blink-overlays' falls back to computing it.
Must be called inside `save-excursion' after `kuro--ensure-buffer-row-exists'
has positioned point at the start of ROW, so that `(point)' yields line-start
for the blink-overlay bounds check."
  ;; `kuro--has-images' is a dedicated flag set only when an image overlay
  ;; exists, avoiding the separate O(row) navigation in the common no-image case.
  (when kuro--has-images
    (kuro--clear-row-image-overlays row))
  (kuro--clear-line-blink-overlays (point) row pre-end))

(defsubst kuro--store-col-to-buf (row col-to-buf)
  "Store or remove the COL-TO-BUF mapping for ROW in `kuro--col-to-buf-map'.
If COL-TO-BUF is a non-empty vector, stores it.  If nil or empty, removes any
existing entry so stale CJK mappings do not persist after an ASCII redraw.
`(length nil)' = 0, so the nil and empty-vector cases are unified without a
`vectorp' guard.  `defsubst' inlines this into `kuro--update-line-full'.
`(and col-to-buf ...)' short-circuits on nil before calling `length' —
eliminates `(length nil)' + gethash on the ~90% ASCII rows (~3,240/sec)."
  (if (and col-to-buf (> (length col-to-buf) 0))
      (puthash row col-to-buf kuro--col-to-buf-map)
    ;; Guard remhash with gethash: avoids a hash-table write on every ASCII row
    ;; even when no CJK mapping exists (the common case at 120fps).
    (when (gethash row kuro--col-to-buf-map)
      (remhash row kuro--col-to-buf-map))))

(defun kuro--update-line-full (row text face-ranges col-to-buf)
  "Navigate to ROW once and perform all line-update operations atomically.
TEXT replaces the current line content.  FACE-RANGES is a list of FFI face
range 6-tuples (start-buf end-buf fg bg flags ul-color) or nil.
COL-TO-BUF is the grid-column → buffer-char-offset vector for this row, or nil.

Performs text replacement, blink-overlay clearing, and face application in a
single `save-excursion' block, reducing O(N²) triple-navigation to O(N)
single-pass when N rows are dirty.

Critical: `line-end' is recomputed with `(line-end-position)' AFTER the
delete+insert so face ranges use the new content offsets, not cached old ones."
  (when (and row text)
    (kuro--store-col-to-buf row col-to-buf)
    (kuro--with-buffer-edit
      (kuro--ensure-buffer-row-exists row)
      (let* ((line-start (point))
             (old-end (line-end-position))
             (old-len (- old-end line-start)))
        (kuro--clear-row-overlays row old-end)
        (delete-region line-start old-end)
        (insert text)
        ;; Capture new line-end once; used for both face application and cache update.
        ;; Derive new-len from buffer positions (character units) rather than
        ;; (length text) which returns byte-count for multibyte strings, causing
        ;; wrong deltas in kuro--row-positions for CJK/emoji rows.
        (let ((new-line-end (line-end-position)))
          (kuro--update-row-position-cache-after-line-change row old-len (- new-line-end line-start) new-line-end)
          ;; Bind current row so kuro--apply-blink-overlay can skip line-number-at-pos.
          (setq kuro--current-render-row row)
          ;; line-end MUST be recomputed after insert: multi-byte text means
          ;; (+ line-start (length text)) would be wrong.
          (kuro--apply-face-ranges face-ranges line-start new-line-end)
          (setq kuro--current-render-row -1))))))

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
(e.g. cursor past last content — trailing spaces are pure ASCII).
Uses `kuro--row-positions' cache for O(1) row navigation when available;
falls back to O(row) `forward-line' only when the cache misses."
  (let* ((row-map    (gethash row kuro--col-to-buf-map))
         (buf-offset (if (and row-map (< col (length row-map)))
                         (aref row-map col)
                       col)))
    (save-excursion
      ;; Fast path: use row-positions cache to jump directly to row start (O(1)).
      (let* ((rp        kuro--row-positions)
             (row-start (and rp
                             (< row (length rp))
                             (aref rp row))))
        (if row-start
            (goto-char row-start)
          ;; Slow path: linear scan from point-min (O(row)).
          (goto-char (point-min))
          (when (> (forward-line row) 0)
            (goto-char (point-max))
            (beginning-of-line))))
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

(defun kuro--apply-cursor-display (visible shape)
  "Set buffer-local `cursor-type' from VISIBLE flag and SHAPE integer.
SHAPE is a DECSCUSR value (0-6, see `kuro--decscusr-to-cursor-type').
When VISIBLE is nil the cursor is hidden by setting `cursor-type' to nil."
  (setq-local cursor-type
              (if visible
                  (kuro--decscusr-to-cursor-type (or shape 0))
                nil)))

;;; Cursor state macros + helpers

(defmacro kuro--cache-cursor-state (row col visible shape)
  "Store ROW, COL, VISIBLE, SHAPE into the per-buffer cursor cache variables."
  `(setq kuro--last-cursor-row     ,row
         kuro--last-cursor-col     ,col
         kuro--last-cursor-visible ,visible
         kuro--last-cursor-shape   ,shape))

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

;;; Cursor update

(defun kuro--update-cursor ()
  "Update cursor position and shape in buffer.
Uses the consolidated `kuro--get-cursor-state' to fetch position,
visibility, and shape in a single Mutex acquisition (PERF-004).
Skips buffer position computation when cursor state is unchanged,
but ALWAYS re-anchors the window at point-min to prevent Emacs'
native redisplay from drifting the viewport between render cycles."
  (unless (> kuro--scroll-offset 0)
    (when-let ((state (kuro--get-cursor-state)))
      ;; cdr-chain: each cdr advances the spine once (shared intermediate cells).
      ;; cadr/caddr/cadddr would re-traverse from head each time.
      (let* ((row     (car state))
             (s1      (cdr state))
             (col     (car s1))
             (s2      (cdr s1))
             (visible (car s2))
             (shape   (car (cdr s2))))
        ;; Fast path: reuse cached window (window-live-p is an O(1) C check).
        ;; Fallback to get-buffer-window (O(frames×windows)) only on miss.
        (when-let ((win (or (and (window-live-p kuro--cached-window)
                                 kuro--cached-window)
                            (setq kuro--cached-window
                                  (get-buffer-window (current-buffer) t)))))
          (if (kuro--cursor-state-changed-p row col visible shape)
              ;; State changed: update cache, position, and shape.
              (let ((target-pos (kuro--grid-col-to-buffer-pos row col)))
                (kuro--cache-cursor-state row col visible shape)
                ;; Always ensure the marker exists; create it on first use.
                (if kuro--cursor-marker
                    (set-marker kuro--cursor-marker target-pos)
                  (setq kuro--cursor-marker (copy-marker target-pos)))
                (kuro--anchor-window-at-pos win target-pos)
                (kuro--apply-cursor-display visible shape))
            ;; Cursor unchanged — still re-anchor to prevent viewport drift.
            (kuro--anchor-window-at-pos win (or (and kuro--cursor-marker
                                                     (marker-position kuro--cursor-marker))
                                                (kuro--grid-col-to-buffer-pos row col)))))))))

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

(provide 'kuro-render-buffer)

;;; kuro-render-buffer.el ends here
