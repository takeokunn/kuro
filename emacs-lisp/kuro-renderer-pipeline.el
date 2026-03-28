;;; kuro-renderer-pipeline.el --- Render pipeline execution for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; Render pipeline execution: dirty-line polling, application, resize,
;; col-to-buf cache eviction, title/scroll updates, and adaptive frame budget.
;;
;; # Responsibilities
;;
;; - `kuro--apply-dirty-updates': high-level pipeline entry point called once
;;   per coalesced render frame.
;; - `kuro--handle-pending-resize': drains the pending-resize slot before any
;;   display work so no race exists between the window-change hook and timer.
;; - col-to-buf cache eviction: removes stale entries after resize or CJK→ASCII
;;   transitions, using 2× hysteresis to prevent churn.
;; - Adaptive frame budget: 10-frame rolling average adjusts
;;   `kuro--frame-budget-ratio' to protect the Emacs event loop from high-
;;   throughput TUI apps.
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

;; kuro-kill is defined in kuro-lifecycle.el which requires kuro-renderer.el;
;; use declare-function to avoid a circular require.
(declare-function kuro-kill "kuro-lifecycle" ())

;; Functions provided by kuro-render-buffer.el (loaded via (require 'kuro-render-buffer)).
(declare-function kuro--update-cursor         "kuro-render-buffer" ())
(declare-function kuro--update-scroll-indicator "kuro-render-buffer" ())
(declare-function kuro--update-line-full      "kuro-render-buffer" (row text face-ranges col-to-buf))
(declare-function kuro--apply-buffer-scroll   "kuro-render-buffer" (up down))
(declare-function kuro--init-row-positions    "kuro-render-buffer" (rows))

;; Functions provided by kuro-ffi.el (loaded via (require 'kuro-ffi)).
(declare-function kuro--resize "kuro-ffi" (rows cols))

;; External C function used via kuro-binary-decoder.el.
(declare-function kuro-core-poll-updates-binary-with-strings
                  "ext:kuro-core" (session-id))

;; Forward references: defvar-local symbols defined in other modules.
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

;;; Render pipeline macros

(defmacro kuro--timed (ms-var &rest body)
  "Execute BODY, store elapsed milliseconds in MS-VAR, return BODY's value.
Uses a private time variable so BODY cannot accidentally shadow it."
  (declare (indent 1))
  `(let ((--timed-start (float-time)))
     (prog1 (progn ,@body)
       (setq ,ms-var (* 1000.0 (- (float-time) --timed-start))))))

(defmacro kuro--with-render-env (&rest body)
  "Execute BODY under render-optimized GC and `inhibit-redisplay' settings.
Sets `gc-cons-threshold' and `gc-cons-percentage' to suppress collection
jitter, then wraps BODY in `inhibit-redisplay' to prevent partial redraws."
  (declare (indent 0))
  `(let ((gc-cons-threshold kuro--render-gc-threshold)
         (gc-cons-percentage kuro--render-gc-percentage))
     (let ((inhibit-redisplay t))
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

;;; Binary FFI poll wrapper

(defun kuro--poll-updates-binary ()
  "Poll terminal updates via binary FFI protocol (with-strings optimised path).
Returns the same format as `kuro--poll-updates-with-faces'."
  (let ((result (kuro--call nil (kuro-core-poll-updates-binary-with-strings kuro--session-id))))
    (when result
      (condition-case err
          (kuro--decode-binary-updates-with-strings (car result) (cdr result))
        (args-out-of-range
         (message "kuro: binary FFI decoder error (malformed frame): %S" err)
         nil)))))

;;; Utility

(defun kuro--sanitize-title (title)
  "Sanitize TITLE string from PTY before using as buffer/frame name.
Strips ASCII control characters (U+0000-U+001F, U+007F), null bytes,
and Unicode bidirectional override codepoints (U+202A-U+202E, U+2066-U+2069)
to prevent visual spoofing attacks via malicious OSC title sequences."
  (replace-regexp-in-string
   "[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069\u200f]" "" title))

;;; Resize

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

(defconst kuro--col-to-buf-evict-factor 2
  "Hysteresis multiplier for the col-to-buf hash map eviction threshold.
When the hash map has more than this factor times the terminal row count,
stale entries are pruned to prevent unbounded growth during long sessions.")

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
    (let (stale-keys)
      ;; Collect rows that are out-of-bounds after a terminal resize.
      (maphash (lambda (k _v) (when (>= k kuro--last-rows) (push k stale-keys)))
               kuro--col-to-buf-map)
      ;; Collect dirty rows with empty col-to-buf vectors (CJK → ASCII transition).
      (dolist (line-update dirty-rows)
        (pcase-let* ((`((,line-data . ,_faces) . ,col-to-buf) line-update)
                     (`(,row . ,_text) line-data))
          (when (and (integerp row) (vectorp col-to-buf) (zerop (length col-to-buf)))
            (push row stale-keys))))
      (dolist (k stale-keys) (remhash k kuro--col-to-buf-map)))))

;;; GC tuning constants

(defconst kuro--render-gc-threshold (* 64 1024 1024)
  "GC threshold used during render cycle to minimize collections.")

(defconst kuro--render-gc-percentage 0.6
  "GC percentage used during render cycle.")

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

;;; Core render pipeline steps (data/logic separation)

(defsubst kuro--pipeline-step-ffi ()
  "Poll dirty lines from Rust and return the update list."
  (if kuro-use-binary-ffi
      (kuro--poll-updates-binary-optimised kuro--session-id)
    (kuro--poll-updates-with-faces)))

(defsubst kuro--pipeline-step-apply (updates)
  "Apply UPDATES to the buffer, or no-op when nil."
  (when updates (kuro--apply-dirty-lines updates)))

(defsubst kuro--pipeline-face-count (updates)
  "Sum the number of face ranges across all UPDATES entries, 0 when nil."
  (if updates
      (apply #'+ (mapcar (lambda (u) (length (cdr (car u)))) updates))
    0))

;;; Core render pipeline

(defun kuro--core-render-pipeline ()
  "Execute the core render pipeline and return the dirty-line update list.
Runs title update, scroll events, dirty-line polling, line rewrite, and
cursor positioning under a single `inhibit-redisplay' block.
GC is suppressed during the render to reduce pause jitter."
  (let (updates)
    (kuro--with-render-env
      (kuro--apply-title-update)
      (kuro--process-scroll-events)
      (setq updates (kuro--pipeline-step-ffi))
      (kuro--pipeline-step-apply updates)
      (kuro--update-cursor)
      (kuro--update-scroll-indicator))
    updates))

(defun kuro--core-render-pipeline-with-timing ()
  "Execute the core render pipeline with per-step timing and return updates.
Appends one timing line to *kuro-perf* per `kuro--perf-sample-interval' frames."
  (let ((t-total (float-time))
        ffi-ms apply-ms cursor-ms updates)
    (kuro--with-render-env
      (kuro--apply-title-update)
      (kuro--process-scroll-events)
      (kuro--timed ffi-ms    (setq updates (kuro--pipeline-step-ffi)))
      (kuro--timed apply-ms  (kuro--pipeline-step-apply updates))
      (kuro--timed cursor-ms (kuro--update-cursor))
      (kuro--update-scroll-indicator))
    (setq kuro--perf-frame-count (1+ kuro--perf-frame-count))
    (kuro--when-divisible kuro--perf-frame-count kuro--perf-sample-interval
      (let ((total-ms   (* 1000.0 (- (float-time) t-total)))
            (face-count (kuro--pipeline-face-count updates)))
        (kuro--perf-report ffi-ms apply-ms cursor-ms total-ms (length updates) face-count)))
    updates))

(defun kuro--finalize-dirty-updates (updates)
  "Evict stale col-to-buf entries and record the dirty-line count for UPDATES.
Called after every render pipeline invocation regardless of debug mode."
  (kuro--evict-stale-col-to-buf-entries updates)
  (setq kuro--last-dirty-count (if updates (length updates) 0)))

;;; Adaptive frame budget

(defconst kuro--frame-duration-ring-size 10
  "Number of frame durations tracked for budget averaging.")

(defvar kuro--frame-budget-ratio 0.8
  "Fraction of frame interval available for render work before yielding.
When dirty-line updates consume more than this fraction of the frame
interval, mode polling is deferred to the next frame.  This prevents
high-throughput TUI apps (cmatrix, btop) from starving the Emacs event
loop.  Process-exit detection is always performed regardless of budget.")

(defvar kuro--frame-duration-ring (make-vector kuro--frame-duration-ring-size 0.0)
  "Ring buffer of the last `kuro--frame-duration-ring-size' frame durations
\(seconds).")

(defvar kuro--frame-duration-ring-index 0
  "Current write index into `kuro--frame-duration-ring'.")

(defun kuro--ring-average (ring size)
  "Return the arithmetic mean of SIZE elements from RING vector."
  (let ((sum 0.0))
    (dotimes (i size)
      (setq sum (+ sum (aref ring i))))
    (/ sum (float size))))

(defun kuro--update-frame-budget-ratio (duration)
  "Record frame DURATION and adjust `kuro--frame-budget-ratio' dynamically.
Maintains a rolling average of the last 10 frame durations.  When
consistently over-budget the ratio is nudged down; when consistently
under-budget it is nudged back toward 0.8."
  (aset kuro--frame-duration-ring kuro--frame-duration-ring-index duration)
  (setq kuro--frame-duration-ring-index
        (mod (1+ kuro--frame-duration-ring-index) kuro--frame-duration-ring-size))
  (let ((avg    (kuro--ring-average kuro--frame-duration-ring kuro--frame-duration-ring-size))
        (budget (/ 1.0 kuro-frame-rate)))
    (cond
     ((> avg (* 0.9 budget))
      (setq kuro--frame-budget-ratio (max 0.5 (- kuro--frame-budget-ratio 0.05))))
     ((< avg (* 0.5 budget))
      (setq kuro--frame-budget-ratio (min 0.8 (+ kuro--frame-budget-ratio 0.02)))))))

;;; Pipeline entry point

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

;;; Budget-gated mode polling

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

(provide 'kuro-renderer-pipeline)

;;; kuro-renderer-pipeline.el ends here
