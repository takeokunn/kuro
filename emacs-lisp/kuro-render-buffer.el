;;; kuro-render-buffer.el --- Buffer update functions for Kuro terminal -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:
;; Buffer manipulation functions: line updates, cursor positioning, scroll application.

;;; Code:

(require 'kuro-ffi)
(require 'kuro-ffi-modes)
(require 'kuro-faces)
(require 'kuro-overlays)

(declare-function kuro--clear-row-image-overlays "kuro-overlays" (row))
(declare-function kuro--apply-ffi-face-at "kuro-overlays" (start-pos end-pos fg-enc bg-enc flags))
(declare-function kuro--get-cursor         "kuro-ffi"       ())
(declare-function kuro--get-cursor-visible "kuro-ffi-modes" ())
(declare-function kuro--get-cursor-shape   "kuro-ffi-modes" ())

;;; Scroll event application

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
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      ;; Scroll-up: terminal content moves up; top lines disappear, blank lines appear at bottom.
      (when (> up 0)
        (save-excursion
          (dotimes (_ up)
            (goto-char (point-min))
            (delete-region (point) (progn (forward-line 1) (point)))
            ;; Append exactly one blank line (newline) at the end.
            (goto-char (point-max))
            (insert "\n"))))
      ;; Scroll-down: terminal content moves down; bottom lines disappear, blank lines appear at top.
      (when (> down 0)
        (save-excursion
          (dotimes (_ down)
            ;; Delete the last line including its leading newline separator.
            (goto-char (point-max))
            (when (> (point) (point-min))
              (forward-line -1)
              (delete-region (point) (point-max)))
            ;; Prepend a blank line at the top.
            (goto-char (point-min))
            (insert "\n")))))
    (clrhash kuro--col-to-buf-map)))

;;; Internal helpers

(defun kuro--ensure-buffer-row-exists (row)
  "Ensure the buffer has at least ROW+1 lines.
When `forward-line' returns a positive NOT-MOVED count the buffer is shorter
than the terminal.  This helper appends the missing blank lines and then
repositions point at the start of ROW.
After this function returns, point is positioned at the beginning of line ROW.
Must be called with `inhibit-read-only' and `inhibit-modification-hooks'
already bound non-nil by the caller."
  (let ((not-moved (progn (goto-char (point-min)) (forward-line row))))
    (when (> not-moved 0)
      (goto-char (point-max))
      (unless (and (> (point-max) (point-min))
                   (= (char-before) ?\n))
        (insert "\n"))
      (dotimes (_ not-moved)
        (insert "\n"))
      (goto-char (point-min))
      (forward-line row))))

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

(defun kuro--update-line-full (row text face-ranges col-to-buf)
  "Navigate to ROW exactly once and perform all line-update operations atomically.
TEXT replaces the current line content.  FACE-RANGES is a list of FFI face
range 5-tuples as returned by `kuro-core-poll-updates-with-faces', or nil.
COL-TO-BUF is the grid-column → buffer-char-offset vector for this row, or nil.

Performs text replacement, blink-overlay clearing, and face application in a
single `save-excursion' block, reducing O(N²) triple-navigation to O(N)
single-pass when N rows are dirty.

Critical: `line-end' is recomputed with `(line-end-position)' AFTER the
delete+insert so face ranges use the new content offsets, not cached old ones."
  (when (and (integerp row) (stringp text))
    (if (vectorp col-to-buf)
        (puthash row col-to-buf kuro--col-to-buf-map)
      (when (and (integerp row) (null col-to-buf))
        (remhash row kuro--col-to-buf-map)))
    ;; Image overlay clearing: guard with nil-check so the separate O(row)
    ;; navigation is skipped entirely when no Kitty Graphics images are present.
    ;; Without this guard, kuro--clear-row-image-overlays would re-introduce an
    ;; O(N²) buffer traversal for N dirty rows even in the common no-image case.
    (when kuro--image-overlays
      (kuro--clear-row-image-overlays row))
    (save-excursion
      (let ((inhibit-read-only t)
            (inhibit-modification-hooks t))
        (kuro--ensure-buffer-row-exists row)
        (let ((line-start (point)))
            (when kuro--blink-overlays
              (let ((line-end-before (1+ (line-end-position)))
                    (remaining nil))
                (dolist (ov kuro--blink-overlays)
                  (if (and (overlay-buffer ov)
                           (>= (overlay-start ov) line-start)
                           (<= (overlay-end ov) line-end-before))
                      (delete-overlay ov)
                    (push ov remaining)))
                (setq kuro--blink-overlays (nreverse remaining))))
            ;; Replace line content (excluding trailing newline).
            (delete-region line-start (line-end-position))
            (insert text)
            ;; IMPORTANT: line-end MUST be recomputed after insert.
            ;; The new content may differ in length from the old content;
            ;; using (+ line-start (length text)) is incorrect for multi-byte text.
            (let ((line-end (line-end-position)))
              (when face-ranges
                (dolist (range face-ranges)
                  (let* ((start-buf (car range))
                         (rest1 (cdr range))
                         (end-buf (car rest1))
                         (rest2 (cdr rest1))
                         (fg-enc (car rest2))
                         (rest3 (cdr rest2))
                         (bg-enc (car rest3))
                         (flags (car (cdr rest3))))
                    (let* ((start-pos (min (+ line-start start-buf) line-end))
                           (end-pos   (min (+ line-start end-buf)   line-end)))
                      (when (> end-pos start-pos)
                        (kuro--apply-ffi-face-at start-pos end-pos
                                                 fg-enc bg-enc flags))))))))))))

(defvar-local kuro--last-cursor-row nil
  "Cached cursor row from the previous render frame.
Used to skip redundant cursor position computation when unchanged.")
(put 'kuro--last-cursor-row 'permanent-local t)

(defvar-local kuro--last-cursor-col nil
  "Cached cursor column from the previous render frame.
Used to skip redundant cursor position computation when unchanged.")
(put 'kuro--last-cursor-col 'permanent-local t)

(defvar-local kuro--last-cursor-visible nil
  "Cached cursor visibility from the previous render frame.")
(put 'kuro--last-cursor-visible 'permanent-local t)

(defvar-local kuro--last-cursor-shape nil
  "Cached cursor shape from the previous render frame.")
(put 'kuro--last-cursor-shape 'permanent-local t)

(defun kuro--update-cursor ()
  "Update cursor position and shape in buffer.
Uses the consolidated `kuro--get-cursor-state' to fetch position,
visibility, and shape in a single Mutex acquisition (PERF-004).
Skips buffer position computation when cursor state is unchanged."
  (unless (> kuro--scroll-offset 0)
    (let ((state (kuro--get-cursor-state)))
      (when state
        (let* ((row     (nth 0 state))
               (col     (nth 1 state))
               (visible (nth 2 state))
               (shape   (nth 3 state)))
          ;; Early return when cursor state is unchanged from last frame.
          (unless (and (eql row kuro--last-cursor-row)
                       (eql col kuro--last-cursor-col)
                       (eq visible kuro--last-cursor-visible)
                       (eql shape kuro--last-cursor-shape))
            (setq kuro--last-cursor-row row
                  kuro--last-cursor-col col
                  kuro--last-cursor-visible visible
                  kuro--last-cursor-shape shape)
            (let* (;; Convert grid column to buffer char offset using col_to_buf mapping.
                   ;; col_to_buf[col] gives the buffer offset for cursor column col.
                   ;; For pure ASCII lines, col == buf-offset; for CJK lines, col > buf-offset
                   ;; because wide placeholder cells are skipped in the buffer.
                   ;; We look up the per-row mapping from kuro--col-to-buf-map (a hash table
                   ;; keyed by row number) so each row's mapping is independent.
                   ;; If the vector is shorter than col (e.g. cursor past last content),
                   ;; fall back to col (works for trailing spaces which are pure ASCII).
                   (row-col-to-buf (gethash row kuro--col-to-buf-map))
                   (buf-offset
                    (if (and row-col-to-buf
                             (< col (length row-col-to-buf)))
                        (aref row-col-to-buf col)
                      col))
                   (target-pos
                    (save-excursion
                      (goto-char (point-min))
                      (forward-line row)
                      (let ((line-start (point))
                            (line-end (line-end-position)))
                        (goto-char (min (+ line-start buf-offset) line-end)))
                      (point))))
              (when kuro--cursor-marker
                (set-marker kuro--cursor-marker target-pos))
              ;; Keep the window anchored at point-min so the terminal viewport (rows 0..N-1)
              ;; always fills the Emacs window from top to bottom.  Without this, Emacs scrolls
              ;; automatically to keep `point' visible using its own heuristics — when a full-
              ;; screen app (vim, htop, …) moves the cursor to the last row, Emacs would scroll
              ;; the window down, hiding the top rows and showing only the bottom half of the
              ;; terminal content.  vterm avoids this by always calling set-window-start first.
              ;;
              ;; Do NOT anchor when the user is scrolled into the scrollback buffer —
              ;; the guard `unless (> kuro--scroll-offset 0)' at the top of this function
              ;; already prevents us from reaching here during scrollback, but be explicit.
              (let ((win (get-buffer-window (current-buffer) t)))
                (when win
                  ;; Anchor display at point-min on every frame so full-screen apps
                  ;; (htop, vim, …) fill the whole window.  set-window-start is called
                  ;; without a NOFORCE argument (nil, the default) so Emacs honours
                  ;; point-min as the window start.  It is called BEFORE set-window-point
                  ;; so that point is placed within the already-anchored viewport; this
                  ;; combination prevents Emacs from scrolling to keep the cursor visible
                  ;; when a full-screen app moves it to the last row.
                  ;; set-window-start MUST come before set-window-point.
                  (unless (= (window-start win) (point-min))
                    (set-window-start win (point-min)))
                  (unless (= (window-point win) target-pos)
                    (set-window-point win target-pos))))
              (if visible
                  ;; Apply cursor shape from terminal DECSCUSR (CSI Ps SP q)
                  (setq-local cursor-type
                              (kuro--decscusr-to-cursor-type (or shape 0)))
                (setq-local cursor-type nil)))))))))

(provide 'kuro-render-buffer)

;;; kuro-render-buffer.el ends here
