;;; kuro-renderer.el --- Render loop and buffer management for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; This file provides the render loop and buffer update functions for Kuro.
;; It manages the Emacs buffer display and updates based on terminal state.
;;
;; # Responsibilities
;;
;; - Timer-based render loop lifecycle (start/stop)
;; - Per-frame render cycle: dirty line updates, cursor, title,
;;   and col-to-buf cache eviction
;; - Cursor position and shape updates
;; - Window title sanitization
;; - Frame coalescing and budget-gated mode polling
;;
;; # Architecture
;;
;; Color conversion and face caching are in `kuro-faces'.
;; Overlay management (blink, image, hyperlink) is in `kuro-overlays'.
;; Input handling is in `kuro-input'.
;; TUI mode detection and adaptive frame rate are in `kuro-tui-mode'.
;; Tiered terminal mode polling is in `kuro-poll-modes'.

;;; Code:

(require 'cl-lib)
(require 'kuro-ffi)
(require 'kuro-ffi-osc)
(require 'kuro-input)
(require 'kuro-config)
(require 'kuro-faces)
(require 'kuro-overlays)
(require 'kuro-stream)
(require 'kuro-render-buffer)
(require 'kuro-binary-decoder)
(require 'kuro-debug-perf)
(require 'kuro-tui-mode)
(require 'kuro-poll-modes)

;; Forward declarations for defvar-local symbols defined in other modules that
;; kuro-renderer.el writes to or reads directly.
;; kuro-ffi.el
(defvar kuro--initialized nil
  "Forward reference; defvar-local in kuro-ffi.el.")
(defvar kuro--resize-pending nil
  "Forward reference; defvar-local in kuro-ffi.el.")
(defvar kuro--col-to-buf-map nil
  "Forward reference; defvar-local in kuro-ffi.el.")
;; kuro-render-buffer.el
(defvar kuro--last-cursor-row nil
  "Forward reference; defvar-local in kuro-render-buffer.el.")
(defvar kuro--last-cursor-col nil
  "Forward reference; defvar-local in kuro-render-buffer.el.")
(defvar kuro--last-cursor-visible nil
  "Forward reference; defvar-local in kuro-render-buffer.el.")
(defvar kuro--last-cursor-shape nil
  "Forward reference; defvar-local in kuro-render-buffer.el.")
;; kuro.el
(defvar kuro--last-rows 0
  "Forward reference; defvar-local in kuro.el.")
(defvar kuro--last-cols 0
  "Forward reference; defvar-local in kuro.el.")
;; kuro-input.el
(defvar kuro--scroll-offset 0
  "Forward reference; defvar-local in kuro-input.el.")

;; kuro-kill is defined in kuro-lifecycle.el which requires kuro-renderer.el;
;; use declare-function to avoid a circular require.
(declare-function kuro-kill "kuro-lifecycle" ())

;; Bell function provided by the Rust dynamic module at runtime.
(declare-function kuro-core-take-bell-pending "ext:kuro-core" (session-id))
(declare-function kuro--update-line-full        "kuro-render-buffer" (row text face-ranges col-to-buf))
(declare-function kuro--resize                  "kuro-ffi"           (rows cols))
(declare-function kuro--apply-buffer-scroll     "kuro-render-buffer" (up down))
(declare-function kuro--init-row-positions      "kuro-render-buffer" (rows))
(declare-function kuro--tick-blink-overlays     "kuro-overlays"      ())
(declare-function kuro--recompute-blink-frame-intervals "kuro-overlays" ())
(declare-function kuro--start-stream-idle-timer    "kuro-stream"        ())
(declare-function kuro--stop-stream-idle-timer     "kuro-stream"        ())

;;; Binary FFI poll wrapper

(defun kuro--poll-updates-binary ()
  "Poll terminal updates via binary FFI protocol.
Returns the same format as `kuro--poll-updates-with-faces'."
  (let ((raw (kuro--call nil (kuro-core-poll-updates-binary kuro--session-id))))
    (when raw
      (condition-case err
          (kuro--decode-binary-updates raw)
        (args-out-of-range
         (message "kuro: binary FFI decoder error (malformed frame): %S" err)
         nil)))))

;;; col-to-buf eviction constant

(defconst kuro--col-to-buf-evict-factor 2
  "Hysteresis multiplier for the col-to-buf hash map eviction threshold.
When the hash map has more than this factor times the terminal row count,
stale entries are pruned to prevent unbounded growth during long sessions.")

;;; Buffer-local render state

(kuro--defvar-permanent-local kuro--timer nil
  "Timer object for the Kuro render loop.
Internal state; do not set directly.
Each Kuro buffer maintains its own independent timer.")

(kuro--defvar-permanent-local kuro--cursor-marker nil
  "Marker for cursor position.")

(kuro--defvar-permanent-local kuro--last-render-time 0.0
  "Float-time of the last completed render cycle.
Used for frame coalescing: when multiple timer sources (120fps periodic,
streaming idle, input echo delay) all fire within the same frame period,
only the first actually renders.  Subsequent fires within half a frame
period are skipped, preventing redundant partial-screen redraws that
manifest as flickering on complex TUI apps like Claude Code.")

;;; Render loop lifecycle

(defun kuro--install-render-timer (rate)
  "Cancel any existing render timer and install a new one firing at RATE fps.
Captures the current buffer so the lambda stays bound to the right buffer
after any `with-current-buffer' context switches."
  (when (timerp kuro--timer)
    (cancel-timer kuro--timer))
  (let ((buf (current-buffer)))
    (setq kuro--timer
          (run-with-timer
           0
           (/ 1.0 rate)
           (lambda () (when (buffer-live-p buf)
                         (with-current-buffer buf
                           (kuro--render-cycle))))))))

(defun kuro--start-render-loop ()
  "Start the render loop targeting the current buffer.
Also starts the low-latency streaming idle timer when
`kuro-streaming-latency-mode' is non-nil."
  ;; Recompute cached blink intervals in case kuro-frame-rate changed.
  (kuro--recompute-blink-frame-intervals)
  (kuro--install-render-timer kuro-frame-rate)
  ;; Start the zero-delay idle timer for streaming latency reduction
  (kuro--start-stream-idle-timer))

(defun kuro--stop-render-loop ()
  "Stop the render loop and streaming idle timer."
  (when (timerp kuro--timer)
    (cancel-timer kuro--timer)
    (setq kuro--timer nil))
  (kuro--stop-stream-idle-timer))

;;; Render pipeline macros

(defmacro kuro--with-frame-coalescing (&rest body)
  "Execute BODY only when enough time has elapsed since the last render frame.
Implements frame coalescing: when multiple timer sources (120fps periodic,
streaming idle, input echo delay) all fire within the same frame period,
only the first call executes BODY.  Subsequent calls within half a frame
period are skipped, preventing redundant partial-screen redraws.

At 120fps, the half-frame threshold is 4.2ms — sufficient to coalesce
the input echo timer (10ms) and streaming idle timer into the next tick.

Updates `kuro--last-render-time' on the first non-coalesced call, so that
`kuro--update-tui-streaming-timer' (which runs outside this guard) always
observes the dirty count from the most recently rendered frame."
  (declare (indent 0))
  `(let ((now (float-time))
         (half-frame (/ 0.5 (if kuro--tui-mode-active
                                kuro-tui-frame-rate
                              kuro-frame-rate))))
     (when (>= (- now kuro--last-render-time) half-frame)
       (setq kuro--last-render-time now)
       ,@body)))

(defmacro kuro--reset-cursor-cache ()
  "Clear all cached cursor state so the next render recomputes from scratch.
Must be called after resize, attach, or any operation that invalidates the
cursor's grid position.  The nil values cause `kuro--update-cursor' to skip
the unchanged-state fast path and always query Rust for fresh cursor data."
  `(setq kuro--last-cursor-row     nil
         kuro--last-cursor-col     nil
         kuro--last-cursor-visible nil
         kuro--last-cursor-shape   nil))

;;; Utility functions

(defun kuro--sanitize-title (title)
  "Sanitize TITLE string from PTY before using as buffer/frame name.
Strips ASCII control characters (U+0000-U+001F, U+007F), null bytes,
and Unicode bidirectional override codepoints (U+202A-U+202E, U+2066-U+2069)
to prevent visual spoofing attacks via malicious OSC title sequences."
  (replace-regexp-in-string
   "[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069\u200f]" "" title))

;;; Render cycle helpers

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
      (when (and kuro--initialized (> new-rows 0) (> new-cols 0))
        (setq kuro--last-rows new-rows
              kuro--last-cols new-cols)
        (kuro--resize new-rows new-cols)
        ;; Invalidate col-to-buf mappings: column count changed so every
        ;; row's grid-column → buffer-offset vector is stale.
        (clrhash kuro--col-to-buf-map)
        ;; Reinitialize row-position cache for the new row count.
        (kuro--init-row-positions new-rows)
        ;; Reset cursor cache so the first post-resize render recomputes
        ;; cursor position instead of hitting the unchanged-state fast path.
        (kuro--reset-cursor-cache)
        ;; Adjust buffer line count to match new rows.
        ;; Use line-number-at-pos instead of count-lines: count-lines counts
        ;; newlines, which overcounts by 1 when the buffer has a trailing \n
        ;; (the normal state — each row is terminated by \n).
        (let ((inhibit-read-only t)
              (inhibit-modification-hooks t)
              (current-rows (1- (line-number-at-pos (point-max)))))
          (cond
           ((< current-rows new-rows)
            (save-excursion
              (goto-char (point-max))
              (dotimes (_ (- new-rows current-rows))
                (insert "\n"))))
           ((> current-rows new-rows)
            (save-excursion
              (goto-char (point-max))
              (dotimes (_ (- current-rows new-rows))
                (when (> (point) (point-min))
                  (forward-line -1)
                  (delete-region (line-end-position) (point-max))))))))))))

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

(defun kuro--process-scroll-events ()
  "Consume pending full-screen scroll events and apply them to the buffer.
Must be called before polling dirty lines so that buffer-level
delete+insert happens before per-row text rewrites.
No-op when the user is viewing scrollback (`kuro--scroll-offset' > 0)
because the Rust side also suppresses events in that state, and applying
scroll shifts to a frozen scrollback view would corrupt the display."
  (unless (> kuro--scroll-offset 0)
    (let ((scroll-ev (kuro--consume-scroll-events)))
      (when (and scroll-ev (> kuro--last-rows 0))
        (kuro--apply-buffer-scroll (car scroll-ev) (cdr scroll-ev))))))

;;; col-to-buf cache eviction

(defun kuro--collect-out-of-bounds-rows ()
  "Return keys from `kuro--col-to-buf-map' that are >= `kuro--last-rows'.
These rows are out-of-bounds after a terminal resize."
  (let (stale)
    (maphash (lambda (k _v) (when (>= k kuro--last-rows) (push k stale)))
             kuro--col-to-buf-map)
    stale))

(defun kuro--collect-empty-col-to-buf-rows (dirty-rows)
  "Return row numbers from DIRTY-ROWS with empty col-to-buf vectors.
Empty vectors indicate a CJK → ASCII transition; the identity fallback is
correct for these rows, so the stale CJK mapping must not linger."
  (let (stale)
    (dolist (line-update dirty-rows)
      (pcase-let* ((`((,line-data . ,_faces) . ,col-to-buf) line-update)
                   (`(,row . ,_text) line-data))
        (when (and (integerp row) (vectorp col-to-buf) (zerop (length col-to-buf)))
          (push row stale))))
    stale))

(defun kuro--evict-stale-col-to-buf-entries (dirty-rows)
  "Remove stale col-to-buf mappings from `kuro--col-to-buf-map'.
Evicts entries for:
  1. Rows >= `kuro--last-rows' (out-of-bounds after resize).
  2. Dirty rows whose updated col-to-buf is empty (transitioned from CJK
     to ASCII) — the identity fallback is correct for these rows, so the
     stale CJK mapping must not linger.
Guard `kuro--last-rows' > 0 to avoid spurious eviction before the first resize.
2x hysteresis: only triggers when the map exceeds 2x the current row count.
Returns nil."
  (when (and (> kuro--last-rows 0)
             (> (hash-table-count kuro--col-to-buf-map) (* kuro--col-to-buf-evict-factor kuro--last-rows)))
    (let ((stale-keys (append (kuro--collect-out-of-bounds-rows)
                              (kuro--collect-empty-col-to-buf-rows dirty-rows))))
      (dolist (k stale-keys) (remhash k kuro--col-to-buf-map)))))

;;; Dirty-line application

(defun kuro--apply-dirty-lines (updates)
  "Rewrite each dirty row from UPDATES into the buffer.
UPDATES is the list from `kuro--poll-updates-with-faces'.  Each entry is:
  (((row . text) . face-list) . col-to-buf-vector)
Per-row errors are swallowed individually so a failure on row K does not
discard subsequent rows — wrapping the entire dolist would silently drop
all remaining rows after the first error."
  (dolist (line-update updates)
    (pcase-let* ((`((,line-data . ,face-ranges) . ,col-to-buf) line-update)
                 (`(,row . ,text) line-data))
      (condition-case nil
          (kuro--update-line-full row text face-ranges col-to-buf)
        (error nil)))))

;;; Core render pipeline

(defun kuro--core-render-pipeline ()
  "Execute the core render pipeline and return the dirty-line update list.
Runs title update, scroll events, dirty-line polling, line rewrite, and
cursor positioning under a single `inhibit-redisplay' block.
GC is suppressed during the render to reduce pause jitter."
  (let ((gc-cons-threshold (* 64 1024 1024))
        (gc-cons-percentage 0.6)
        updates)
    (let ((inhibit-redisplay t))
      (kuro--apply-title-update)
      (kuro--process-scroll-events)
      (setq updates (if kuro-use-binary-ffi
                        (kuro--poll-updates-binary)
                      (kuro--poll-updates-with-faces)))
      (when updates (kuro--apply-dirty-lines updates))
      (kuro--update-cursor))
    updates))

(defun kuro--core-render-pipeline-with-timing ()
  "Execute the core render pipeline with per-step timing and return updates.
Appends one timing line to *kuro-perf* every `kuro--perf-sample-interval' frames."
  (let ((gc-cons-threshold (* 64 1024 1024))
        (gc-cons-percentage 0.6)
        (t-total (float-time)) t-ffi t-apply t-cursor ffi-ms apply-ms cursor-ms updates)
    (let ((inhibit-redisplay t))
      (kuro--apply-title-update)
      (kuro--process-scroll-events)
      (setq t-ffi    (float-time)
            updates  (if kuro-use-binary-ffi
                         (kuro--poll-updates-binary)
                       (kuro--poll-updates-with-faces))
            ffi-ms   (* 1000.0 (- (float-time) t-ffi))
            t-apply  (float-time))
      (when updates (kuro--apply-dirty-lines updates))
      (setq apply-ms  (* 1000.0 (- (float-time) t-apply))
            t-cursor  (float-time))
      (kuro--update-cursor)
      (setq cursor-ms (* 1000.0 (- (float-time) t-cursor))))
    (setq kuro--perf-frame-count (1+ kuro--perf-frame-count))
    (when (zerop (mod kuro--perf-frame-count kuro--perf-sample-interval))
      (let* ((total-ms  (* 1000.0 (- (float-time) t-total)))
             (face-count (if updates
                             (apply #'+ (mapcar (lambda (u) (length (cdr (car u)))) updates))
                           0)))
        (kuro--perf-report ffi-ms apply-ms cursor-ms total-ms (length updates) face-count)))
    updates))

(defun kuro--finalize-dirty-updates (updates)
  "Evict stale col-to-buf entries and record the dirty-line count for UPDATES.
Called after every render pipeline invocation regardless of debug mode."
  (kuro--evict-stale-col-to-buf-entries updates)
  (setq kuro--last-dirty-count (if updates (length updates) 0)))

(defun kuro--apply-dirty-updates ()
  "Apply dirty-line updates from Rust and advance the cursor position.
Called once per render frame after `kuro--handle-pending-resize' and
`kuro--poll-terminal-modes'.

Responsibilities:
  1. Consume pending full-screen scroll events BEFORE polling dirty lines
     so that buffer-level delete+insert happens before per-row text rewrites.
  2. Poll the Rust side for dirty lines with face data and rewrite each row
     via `kuro--apply-dirty-lines', batched under `inhibit-redisplay' so Emacs
     performs exactly one display flush per frame.
  3. Move point to the current cursor position (`kuro--update-cursor').
  4. Evict stale entries from `kuro--col-to-buf-map' when the table grows
     beyond 2x the current row count (hysteresis prevents churn).
  5. Store the dirty line count in `kuro--last-dirty-count' for TUI
     detection (performed outside the frame coalescing guard)."
  (let* ((t0 (float-time))
         (updates (if kuro-debug-perf
                      (kuro--core-render-pipeline-with-timing)
                    (kuro--core-render-pipeline))))
    (kuro--update-frame-budget-ratio (- (float-time) t0))
    (kuro--finalize-dirty-updates updates)))

;;; Render cycle

(defvar kuro--frame-budget-ratio 0.8
  "Fraction of frame interval available for render work before yielding.
When dirty-line updates consume more than this fraction of the frame
interval, mode polling is deferred to the next frame.  This prevents
high-throughput TUI apps (cmatrix, btop) from starving the Emacs event
loop.  Process-exit detection is always performed regardless of budget.")

(defvar kuro--frame-duration-ring (make-vector 10 0.0)
  "Ring buffer of the last 10 frame durations in seconds.")

(defvar kuro--frame-duration-ring-index 0
  "Current write index into `kuro--frame-duration-ring'.")

(defun kuro--update-frame-budget-ratio (duration)
  "Record frame DURATION and adjust `kuro--frame-budget-ratio' dynamically.
Maintains a rolling average of the last 10 frame durations.  When
consistently over-budget the ratio is nudged down; when consistently
under-budget it is nudged back toward 0.8."
  (aset kuro--frame-duration-ring kuro--frame-duration-ring-index duration)
  (setq kuro--frame-duration-ring-index
        (mod (1+ kuro--frame-duration-ring-index) 10))
  (let ((avg (/ (cl-reduce #'+ kuro--frame-duration-ring) 10.0))
        (budget (/ 1.0 kuro-frame-rate)))
    (cond
     ((> avg (* 0.9 budget))
      (setq kuro--frame-budget-ratio (max 0.5 (- kuro--frame-budget-ratio 0.05))))
     ((< avg (* 0.5 budget))
      (setq kuro--frame-budget-ratio (min 0.8 (+ kuro--frame-budget-ratio 0.02)))))))

(defun kuro--switch-render-timer (new-rate)
  "Cancel the current render timer and recreate it at NEW-RATE fps."
  (kuro--install-render-timer new-rate)
  (kuro--recompute-blink-frame-intervals))

(defun kuro--ring-pending-bell ()
  "Ring the Emacs bell if a bell event is pending from the terminal."
  (when (kuro--call nil (kuro-core-take-bell-pending kuro--session-id))
    (ding)))

(defun kuro--poll-within-budget (frame-start-time)
  "Poll terminal modes if FRAME-START-TIME is within the frame budget.
When dirty-line updates consumed less than `kuro--frame-budget-ratio' of
the frame interval, mode polling runs normally.  When over budget, only
process-exit detection runs to ensure prompt buffer cleanup."
  (let ((elapsed (- (float-time) frame-start-time))
        (budget  (/ kuro--frame-budget-ratio kuro-frame-rate)))
    (if (< elapsed budget)
        (progn
          (setq kuro--mode-poll-frame-count (1+ kuro--mode-poll-frame-count))
          (kuro--poll-terminal-modes))
      ;; Over budget: still check process exit to clean up promptly.
      (when (and kuro-kill-buffer-on-exit
                 (not (kuro--is-process-alive)))
        (kuro-kill)))))

(defun kuro--tick-blink-if-active ()
  "Tick blink overlays if any are registered for the current buffer."
  (when kuro--blink-overlays
    (kuro--tick-blink-overlays)))

(defun kuro--render-cycle ()
  "Single render cycle composed of four sequential pipeline stages.

Stage 1 -- Resize (unconditional): synchronizes PTY dimensions before
  any display work, even when the frame is coalesced.

Stage 2 -- Coalesced render (gated by `kuro--with-frame-coalescing'):
  2a. Bell: ring if pending.
  2b. Dirty updates: rewrite changed rows and advance cursor.
  2c. Mode poll: DECCKM, mouse, CWD, clipboard (budget-gated).
  2d. Blink: tick overlay animations.

Stage 3 -- TUI detection (unconditional): must run on every timer
  invocation so `kuro--tui-mode-frame-count' accumulates correctly
  even when Stage 2 is coalesced away."
  ;; Stage 1: Resize -- always, never gated.
  (kuro--handle-pending-resize)
  ;; Stage 2: Coalesced render pipeline.
  (kuro--with-frame-coalescing
    (when (buffer-live-p (current-buffer))
      (let ((frame-start (float-time)))
        ;; 2a. Bell
        (kuro--ring-pending-bell)
        ;; 2b. Dirty updates (heaviest work; must complete first)
        (kuro--apply-dirty-updates)
        ;; 2c. Mode poll (budget-gated to protect event loop)
        (kuro--poll-within-budget frame-start)
        ;; 2d. Blink (after dirty so all rows share the same blink phase)
        (kuro--tick-blink-if-active))))
  ;; Stage 3: TUI detection -- always, never gated.
  (kuro--update-tui-streaming-timer))

(provide 'kuro-renderer)

;;; kuro-renderer.el ends here
