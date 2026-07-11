;;; kuro-renderer-pipeline.el --- Render pipeline execution for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Render pipeline execution: dirty-line polling, application, resize,
;; col-to-buf cache eviction, title/scroll updates, and budget-gated polling.
;;
;; # Responsibilities
;;
;; - `kuro--apply-dirty-updates': high-level pipeline entry point called once
;;   per coalesced render frame.
;; - `kuro--handle-pending-resize': drains the pending-resize slot before any
;;   display work so no race exists between the window-change hook and timer.
;; - col-to-buf cache eviction: removes stale entries after resize or CJK→ASCII
;;   transitions, using 2× hysteresis to prevent churn.
;; - `kuro--poll-within-budget': budget-gated mode polling (DECCKM, mouse,
;;   CWD, OSC events); process-exit check always runs regardless of budget.
;;
;; # Architecture
;;
;; `kuro-renderer.el' owns the timer loop and calls `kuro--apply-dirty-updates'
;; and `kuro--handle-pending-resize' from `kuro--render-cycle'.  This module
;; has no knowledge of timers or frame coalescing — those are higher-level
;; scheduling concerns.

;;; Code:

(require 'kuro-ffi)
(require 'kuro-ffi-osc)
(require 'kuro-config)
(require 'kuro-render-buffer)
(require 'kuro-binary-decoder)
(require 'kuro-debug-perf)
(require 'kuro-poll-modes)
(require 'kuro-renderer-pipeline-macros)

;; kuro-kill is defined in kuro-lifecycle.el which requires kuro-renderer.el;
;; use declare-function to avoid a circular require.
(declare-function kuro-kill "kuro-lifecycle" ())

;; Functions provided by kuro-render-buffer.el (loaded via (require 'kuro-render-buffer)).
(declare-function kuro--update-cursor         "kuro-render-buffer" ())
(declare-function kuro--update-scroll-indicator "kuro-render-buffer" ())
(declare-function kuro--shift-blink-overlay-rows "kuro-overlays" (up down rows))
(declare-function kuro--update-line-full      "kuro-render-buffer" (row text face-ranges col-to-buf))
(declare-function kuro--apply-buffer-scroll   "kuro-render-buffer" (up down))
(declare-function kuro--init-row-positions    "kuro-render-buffer" (rows))

;; Functions provided by kuro-ffi.el (loaded via (require 'kuro-ffi)).
(declare-function kuro--resize "kuro-ffi" (rows cols))

;; External C function used via kuro-binary-decoder.el.
(declare-function kuro-core-poll-updates-binary-with-strings
                  "ext:kuro-core" (session-id))
;; Frame-budget mutation lives in kuro-renderer.el, which owns the cached
;; timer-rate state.
(declare-function kuro--update-frame-budget-ratio "kuro-renderer" (duration))

;; Forward references: defvar-local symbols defined in other modules.
;; kuro-ffi.el
(defvar kuro--initialized nil
  "Forward reference; `defvar-local' in kuro-ffi.el.")
(defvar kuro--resize-pending nil
  "Forward reference; `defvar-local' in kuro-ffi.el.")
(defvar kuro--col-to-buf-map nil
  "Forward reference; `defvar-local' in kuro-ffi.el.")
;; kuro-render-buffer.el
(defvar kuro--last-cursor-row nil
  "Forward reference; `defvar-local' in kuro-render-buffer.el.")
(defvar kuro--last-cursor-col nil
  "Forward reference; `defvar-local' in kuro-render-buffer.el.")
(defvar kuro--last-cursor-visible nil
  "Forward reference; `defvar-local' in kuro-render-buffer.el.")
(defvar kuro--last-cursor-shape nil
  "Forward reference; `defvar-local' in kuro-render-buffer.el.")
;; kuro.el
(defvar kuro--last-rows 0
  "Forward reference; `defvar-local' in kuro.el.")
(defvar kuro--last-dirty-count 0
  "Forward reference; shared dirty-line count used by TUI mode.")
(defvar kuro--last-cols 0
  "Forward reference; `defvar-local' in kuro.el.")
;; kuro-input.el
(defvar kuro--scroll-offset 0
  "Forward reference; `defvar-local' in kuro-input.el.")
;; kuro-renderer.el (loaded after this file; forward-referenced here for
;; use in kuro--update-frame-budget-ratio and kuro--poll-within-budget).
(defvar kuro--frame-budget-seconds (/ 1.0 60.0)
  "Forward reference; `defvar-local' in kuro-renderer.el.")
(defvar kuro--budget-threshold-high (* 0.9 (/ 1.0 60.0))
  "Forward reference; `defvar-local' in kuro-renderer.el.")
(defvar kuro--budget-threshold-low (* 0.5 (/ 1.0 60.0))
  "Forward reference; `defvar-local' in kuro-renderer.el.")
(defvar kuro--budget-absolute-seconds (* 0.8 (/ 1.0 60.0))
  "Forward reference; `defvar-local' in kuro-renderer.el.")

;;; Utility

(defconst kuro--title-sanitize-regexp
  "[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069\u200f]"
  "Pre-compiled regexp for stripping control/bidi characters from OSC titles.
Strips ASCII control characters (U+0000-U+001F, U+007F), null bytes,
and Unicode bidirectional override codepoints (U+202A-U+202E, U+2066-U+2069,
U+200F) to prevent visual spoofing via malicious OSC title sequences.
Defined as a defconst so the regexp is compiled once at load time.")

(defun kuro--sanitize-title (title)
  "Sanitize TITLE string from PTY before using as buffer/frame name.
Uses the pre-compiled `kuro--title-sanitize-regexp'."
  (replace-regexp-in-string kuro--title-sanitize-regexp "" title))

;;; Resize

(defun kuro--pending-resize-valid-p (rows cols)
  "Return non-nil when ROWS and COLS describe an applicable resize."
  (and kuro--initialized (> rows 0) (> cols 0)))

(defun kuro--current-buffer-row-count ()
  "Return the renderer row count implied by the current buffer contents."
  ;; `count-lines' counts newlines, which overcounts by 1 when the buffer has
  ;; the normal trailing newline after each terminal row.
  (1- (line-number-at-pos (point-max))))

(defun kuro--adjust-buffer-row-count (rows)
  "Grow or shrink the current buffer to contain ROWS renderer rows."
  (kuro--with-render-buffer-mutation
    (let ((current-rows (kuro--current-buffer-row-count)))
      (cond
       ((< current-rows rows)
        (save-excursion
          (goto-char (point-max))
          (insert (make-string (- rows current-rows) ?\n))))
       ((> current-rows rows)
        (save-excursion
          (goto-char (point-max))
          (forward-line (- rows current-rows))
          (delete-region (line-end-position) (point-max))))))))

(defun kuro--reset-render-state-after-resize (rows cols)
  "Reset renderer-side state after applying a terminal resize to ROWS and COLS."
  (setq kuro--last-rows rows
        kuro--last-cols cols)
  (kuro--resize rows cols)
  ;; Invalidate col-to-buf mappings: column count changed so every row's
  ;; grid-column -> buffer-offset vector is stale.
  (clrhash kuro--col-to-buf-map)
  (kuro--init-row-positions rows)
  ;; Force the first post-resize render to query Rust for fresh cursor data.
  (kuro--reset-cursor-cache))

(defun kuro--handle-pending-resize ()
  "Apply any pending terminal resize to the PTY and the Emacs buffer.
Called at the start of each render cycle.  The window-change hook stores
a pending (ROWS . COLS) pair in `kuro--resize-pending'; this function
is the single authority that drains that slot, calls `kuro--resize', and
adjusts the number of lines in the buffer to match the new row count.
Separating resize from the rest of the render cycle eliminates the race
that previously existed when both the hook and the timer could issue
resize calls concurrently."
  (when (and kuro--resize-pending (buffer-live-p (current-buffer)))
    (let ((new-rows (car kuro--resize-pending))
          (new-cols (cdr kuro--resize-pending)))
      (setq kuro--resize-pending nil)
      (when (kuro--pending-resize-valid-p new-rows new-cols)
        (kuro--reset-render-state-after-resize new-rows new-cols)
        (kuro--adjust-buffer-row-count new-rows)))))

;;; Title and scroll event handling

(defun kuro--apply-title-update ()
  "Apply a pending window title from OSC 2, if any.
Renames the current buffer and the containing frame to the sanitized title."
  (let ((title (kuro--get-and-clear-title)))
    (when (and (stringp title) (not (string-empty-p title)))
      (let ((safe-title (kuro--sanitize-title title)))
        (rename-buffer (format "*kuro: %s*" safe-title) t)
        (let ((win (get-buffer-window (current-buffer) t)))
          (when win
            (set-frame-parameter (window-frame win) 'name safe-title)))))))

(defun kuro--apply-decoded-scroll-shift ()
  "Apply the scroll shift carried by the last decoded binary frame.
Reads `kuro--decode-scroll-up' / `kuro--decode-scroll-down' (set by
`kuro--poll-updates-binary-optimised' from the v3 frame header) and
replays the shift as a buffer-level edit via `kuro--apply-buffer-scroll'.
Must run AFTER the poll (the shift is part of the frame) and BEFORE
`kuro--apply-dirty-lines' (the frame's row indices are post-shift
positions).  Shift and rows are drained atomically under one FFI call
on the Rust side, so applying them in that order inside the same
`inhibit-redisplay' block reproduces the grid exactly.

Also re-keys the blink-overlay row index and resets the cursor cache:
the buffer edit moved the cursor marker along with the text, so the
cached (row . col) no longer maps to the marker position."
  (let ((up kuro--decode-scroll-up)
        (down kuro--decode-scroll-down))
    ;; Zero the scratch vars once read: the legacy cons-cell poll path never
    ;; writes them, so a stale shift must not survive a `kuro-use-binary-ffi'
    ;; toggle and replay on a later frame.
    (setq kuro--decode-scroll-up 0
          kuro--decode-scroll-down 0)
    (when (and (> (+ up down) 0) (> kuro--last-rows 0))
      (kuro--apply-buffer-scroll up down)
      (kuro--shift-blink-overlay-rows up down kuro--last-rows)
      (kuro--reset-cursor-cache))))

;;; col-to-buf cache eviction

(defconst kuro--col-to-buf-evict-factor 2
  "Hysteresis multiplier for the col-to-buf hash map eviction threshold.
When the hash map has more than this factor times the terminal row count,
stale entries are pruned to prevent unbounded growth during long sessions.")

(defun kuro--col-to-buf-map-should-evict-p ()
  "Return non-nil when stale col-to-buf entries should be pruned."
  (and (> kuro--last-rows 0)
       (> (hash-table-count kuro--col-to-buf-map)
          (* kuro--col-to-buf-evict-factor kuro--last-rows))))

(defun kuro--evict-out-of-bounds-col-to-buf-rows ()
  "Remove rows >= `kuro--last-rows' from `kuro--col-to-buf-map'."
  (maphash (lambda (k _v)
             (when (>= k kuro--last-rows)
               (remhash k kuro--col-to-buf-map)))
           kuro--col-to-buf-map))

(defun kuro--evict-empty-dirty-col-to-buf-rows (dirty-rows)
  "Remove DIRTY-ROWS entries whose updated col-to-buf vector is empty."
  (kuro--do-update-list dirty-rows row _text _face-ranges col-to-buf
    (when (zerop (length col-to-buf))
      (remhash row kuro--col-to-buf-map))))

(defun kuro--evict-stale-col-to-buf-entries (dirty-rows)
  "Remove stale col-to-buf mappings from `kuro--col-to-buf-map'.
DIRTY-ROWS is the update vector from the most recent render pipeline poll.
Rows >= `kuro--last-rows' are evicted after a resize, and dirty rows whose
updated col-to-buf vector is empty lose their stale CJK mapping.
Returns nil."
  (when (kuro--col-to-buf-map-should-evict-p)
    (kuro--evict-out-of-bounds-col-to-buf-rows)
    (kuro--evict-empty-dirty-col-to-buf-rows dirty-rows)))

;;; GC tuning constants

(defconst kuro--render-gc-threshold (* 64 1024 1024)
  "GC threshold used during render cycle to minimize collections.")

(defconst kuro--render-gc-percentage 0.6
  "GC percentage used during render cycle.")

;;; Dirty-line application

(defun kuro--dirty-update-error (format-string &rest args)
  "Signal a malformed dirty update error using FORMAT-STRING and ARGS."
  (apply #'error (concat "Kuro: malformed dirty update list: " format-string) args))

(defsubst kuro--dirty-update-u32-p (value)
  "Return non-nil when VALUE is an unsigned 32-bit integer."
  (and (integerp value) (<= 0 value) (<= value #xffffffff)))

(defun kuro--validate-dirty-face-ranges (face-ranges entry-index)
  "Validate FACE-RANGES for dirty update ENTRY-INDEX.
The vector length is hoisted out of the loop condition: `length' is a
C primitive but still a funcall bytecode per iteration, and this loop
runs over every face-range slot of every dirty row per frame."
  (unless (and (vectorp face-ranges)
               (zerop (% (length face-ranges) 6)))
    (kuro--dirty-update-error
     "Entry %d face-ranges must be a stride-6 vector, got %S"
     entry-index face-ranges))
  (let ((i 0)
        (len (length face-ranges)))
    (while (< i len)
      (unless (kuro--dirty-update-u32-p (aref face-ranges i))
        (kuro--dirty-update-error
         "Entry %d face-ranges[%d] must be u32, got %S"
         entry-index i (aref face-ranges i)))
      (setq i (1+ i)))))

(defun kuro--validate-dirty-col-to-buf (col-to-buf entry-index)
  "Validate COL-TO-BUF for dirty update ENTRY-INDEX.
See `kuro--validate-dirty-face-ranges' for the length-hoist rationale."
  (unless (vectorp col-to-buf)
    (kuro--dirty-update-error
     "Entry %d col-to-buf must be a vector, got %S"
     entry-index col-to-buf))
  (let ((i 0)
        (len (length col-to-buf)))
    (while (< i len)
      (unless (kuro--dirty-update-u32-p (aref col-to-buf i))
        (kuro--dirty-update-error
         "Entry %d col-to-buf[%d] must be u32, got %S"
         entry-index i (aref col-to-buf i)))
      (setq i (1+ i)))))

(defun kuro--validate-dirty-update-entry (entry entry-index)
  "Validate dirty update ENTRY at ENTRY-INDEX."
  (unless (and (vectorp entry) (= (length entry) 4))
    (kuro--dirty-update-error
     "Entry %d must be a 4-element vector, got %S" entry-index entry))
  (let ((row (aref entry 0))
        (text (aref entry 1))
        (face-ranges (aref entry 2))
        (col-to-buf (aref entry 3)))
    (unless (and (integerp kuro--last-rows) (> kuro--last-rows 0))
      (kuro--dirty-update-error
       "Renderer row count must be positive before dirty updates, got %S"
       kuro--last-rows))
    (unless (and (integerp row) (<= 0 row) (< row kuro--last-rows))
      (kuro--dirty-update-error
       "Entry %d row must be in [0,%d), got %S"
       entry-index kuro--last-rows row))
    (unless (stringp text)
      (kuro--dirty-update-error
       "Entry %d text must be a string, got %S" entry-index text))
    (kuro--validate-dirty-face-ranges face-ranges entry-index)
    (kuro--validate-dirty-col-to-buf col-to-buf entry-index)))

(defun kuro--validate-dirty-update-list (update-list)
  "Validate UPDATE-LIST before it enters the render buffer mutation path."
  (unless (vectorp update-list)
    (kuro--dirty-update-error
     "Update list must be a vector, got %S" update-list))
  (let ((entry-index 0))
    (while (< entry-index (length update-list))
      (kuro--validate-dirty-update-entry
       (aref update-list entry-index) entry-index)
      (setq entry-index (1+ entry-index))))
  update-list)

(defun kuro--apply-dirty-lines (update-list)
  "Rewrite each dirty row from UPDATE-LIST into the buffer.
UPDATE-LIST comes from `kuro--poll-updates-with-faces'.  Each element is
a flat 4-element vector [row text face-ranges col-to-buf].
A single `condition-case' wraps the entire loop (not each iteration) to avoid
installing a C-level setjmp target ~3,600 times per second.  In practice
`kuro--update-line-full' never signals, so the handler is a safety net only."
  (when update-list
    (kuro--validate-dirty-update-list update-list)
    (condition-case err
        (kuro--do-update-list update-list row text face-ranges col-to-buf
          (kuro--update-line-full row text face-ranges col-to-buf))
      (error (message "Kuro: apply-dirty-lines error: %S" err)))))

;;; Core render pipeline

(defun kuro--core-render-pipeline ()
  "Execute the core render pipeline and return the dirty-line update list.
Runs title update, scroll events, dirty-line polling, line rewrite, and
  cursor positioning under a single `inhibit-redisplay' block.
GC is suppressed during the render to reduce pause jitter."
  (kuro--core-render-pipeline-run updates
    (setq updates (if kuro-use-binary-ffi
                      (kuro--poll-updates-binary-optimised kuro--session-id)
                    (kuro--poll-updates-with-faces)))
    ;; Shift before rewrite: the frame's dirty rows are post-shift positions.
    (kuro--apply-decoded-scroll-shift)
    (when updates
      (kuro--apply-dirty-lines updates))
    (kuro--update-cursor)))

(defun kuro--core-render-pipeline-with-timing ()
  "Execute the core render pipeline with per-step timing.
Return the update list.  Appends one timing line to *kuro-perf* per
`kuro--perf-sample-interval' frames."
  (kuro--core-render-pipeline-run-with-timing updates t-total ffi-ms apply-ms cursor-ms
    (kuro--timed ffi-ms    (setq updates (if kuro-use-binary-ffi
                                             (kuro--poll-updates-binary-optimised kuro--session-id)
                                           (kuro--poll-updates-with-faces))))
    (kuro--timed apply-ms  (progn
                             ;; Shift before rewrite: dirty rows are post-shift.
                             (kuro--apply-decoded-scroll-shift)
                             (when updates (kuro--apply-dirty-lines updates))))
    (kuro--timed cursor-ms (kuro--update-cursor))))

(defun kuro--finalize-dirty-updates (update-list)
  "Evict stale col-to-buf entries and record the dirty-line count.
Called after every render pipeline invocation regardless of debug mode.
When UPDATE-LIST is nil, eviction is skipped: no new dirty rows implies no
new CJK entries, so `hash-table-count' is not worth calling."
  (setq kuro--last-dirty-count
        (if update-list
            (progn (kuro--evict-stale-col-to-buf-entries update-list)
                   (length update-list))
          0)))

;;; Pipeline entry point

(defun kuro--apply-dirty-updates ()
  "Apply dirty-line update data from Rust and advance the cursor position.
Called once per render frame after `kuro--handle-pending-resize' and
`kuro--poll-terminal-modes'."
  (let* ((t0 (float-time))
         (updates (if kuro-debug-perf
                      (kuro--core-render-pipeline-with-timing)
                    (kuro--core-render-pipeline))))
    (kuro--update-frame-budget-ratio (- (float-time) t0))
    (kuro--finalize-dirty-updates updates)))

;;; Budget-gated mode polling

(defun kuro--poll-within-budget (frame-start-time)
  "Poll terminal modes if FRAME-START-TIME is within the frame budget.
When dirty-line updates consumed less than `kuro--frame-budget-ratio' of
the frame interval, mode polling runs normally.  When over budget, only
process-exit detection runs to ensure prompt buffer cleanup."
  (let ((elapsed (- (float-time) frame-start-time)))
    (if (< elapsed kuro--budget-absolute-seconds)
        (progn
          (setq kuro--mode-poll-frame-count (1+ kuro--mode-poll-frame-count))
          (kuro--poll-terminal-modes))
      ;; Over budget: still check process exit to clean up promptly.
      (when (and kuro-kill-buffer-on-exit
                 (not (kuro--is-process-alive)))
        (kuro-kill)))))

(provide 'kuro-renderer-pipeline)

;;; kuro-renderer-pipeline.el ends here
