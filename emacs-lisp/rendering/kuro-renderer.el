;;; kuro-renderer.el --- Render loop and frame coalescing for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Timer-based render loop lifecycle, frame coalescing, and the top-level
;; render cycle.  Pipeline execution (dirty-line polling, resize, eviction,
;; frame budget) lives in `kuro-renderer-pipeline'.
;;
;; # Responsibilities
;;
;; - Render loop lifecycle: install/start/stop the per-buffer timer.
;; - Frame coalescing: `kuro--with-frame-coalescing' gates the expensive
;;   render work so that multiple rapid timer firings collapse into one.
;; - `kuro--render-cycle': the single entry point called by the timer;
;;   orchestrates the four pipeline stages.
;;
;; # Architecture
;;
;; Color conversion and face caching are in `kuro-faces'.
;; Overlay management (blink, image, hyperlink) is in `kuro-overlays'.
;; Input handling is in `kuro-input'.
;; TUI mode detection and adaptive frame rate are in `kuro-tui-mode'.
;; Tiered terminal mode polling is in `kuro-poll-modes'.
;; Pipeline execution (dirty lines, resize, eviction, budget) is in
;; `kuro-renderer-pipeline'.

;;; Code:

(require 'kuro-renderer-pipeline)
(require 'kuro-input)
(require 'kuro-config)
(require 'kuro-faces)
(require 'kuro-overlays)
(require 'kuro-stream)
(require 'kuro-tui-mode)

;; Bell function provided by the Rust dynamic module at runtime.
(declare-function kuro-core-take-bell-pending       "ext:kuro-core" (session-id))
(declare-function kuro--tick-blink-overlays         "kuro-overlays" ())
(declare-function kuro--recompute-blink-frame-intervals "kuro-overlays" ())
(declare-function kuro--start-stream-idle-timer     "kuro-stream"   ())
(declare-function kuro--stop-stream-idle-timer      "kuro-stream"   ())

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

(kuro--defvar-permanent-local kuro--half-frame-interval (/ 0.5 60.0)
  "Cached half-frame threshold in seconds for `kuro--with-frame-coalescing'.
Pre-computed from the active frame rate to avoid a floating-point division
and a branch on every timer tick.  Updated by `kuro--switch-render-timer'
and `kuro--start-render-loop' whenever the rate changes.")

(kuro--defvar-permanent-local kuro--frame-budget-seconds (/ 1.0 60.0)
  "Cached full-frame budget in seconds (= 1 / frame-rate).
Used by `kuro--update-frame-budget-ratio' and `kuro--poll-within-budget'
instead of computing `(/ 1.0 kuro-frame-rate)' on every 120fps tick.
Updated alongside `kuro--half-frame-interval' in `kuro--switch-render-timer'
and `kuro--start-render-loop'.")

(kuro--defvar-permanent-local kuro--budget-threshold-high (* 0.9 (/ 1.0 60.0))
  "Cached high-watermark budget threshold (= 0.9 * frame-budget-seconds).
Pre-computed from `kuro--frame-budget-seconds' to avoid two float multiplies
per frame in `kuro--update-frame-budget-ratio'.  Updated alongside
`kuro--frame-budget-seconds' in `kuro--start-render-loop' and
`kuro--switch-render-timer'.")

(kuro--defvar-permanent-local kuro--budget-threshold-low (* 0.5 (/ 1.0 60.0))
  "Cached low-watermark budget threshold (= 0.5 * frame-budget-seconds).
Pre-computed from `kuro--frame-budget-seconds'.  Updated alongside
`kuro--frame-budget-seconds' in `kuro--start-render-loop' and
`kuro--switch-render-timer'.")

(kuro--defvar-permanent-local kuro--budget-absolute-seconds (* 0.8 (/ 1.0 60.0))
  "Cached absolute frame budget in seconds (= ratio * frame-budget-seconds).
Pre-computed to avoid a float multiply per rendered frame in
`kuro--poll-within-budget'.  Updated in `kuro--start-render-loop',
`kuro--switch-render-timer', and `kuro--update-frame-budget-ratio'.")

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
  (setq kuro--half-frame-interval    (/ 0.5 kuro-frame-rate))
  (setq kuro--frame-budget-seconds   (/ 1.0 kuro-frame-rate))
  (setq kuro--budget-threshold-high  (* 0.9 kuro--frame-budget-seconds))
  (setq kuro--budget-threshold-low   (* 0.5 kuro--frame-budget-seconds))
  (setq kuro--budget-absolute-seconds (* kuro--frame-budget-ratio kuro--frame-budget-seconds))
  (kuro--install-render-timer kuro-frame-rate)
  ;; Start the zero-delay idle timer for streaming latency reduction
  (kuro--start-stream-idle-timer))

(defun kuro--stop-render-loop ()
  "Stop the render loop and streaming idle timer."
  (when (timerp kuro--timer)
    (cancel-timer kuro--timer)
    (setq kuro--timer nil))
  (kuro--stop-stream-idle-timer))

;;; Frame coalescing

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
  `(let ((now (float-time)))
     (when (>= (- now kuro--last-render-time) kuro--half-frame-interval)
       (setq kuro--last-render-time now)
       ,@body)))

;;; Render cycle utilities

(defun kuro--switch-render-timer (new-rate)
  "Cancel the current render timer and recreate it at NEW-RATE fps."
  (kuro--install-render-timer new-rate)
  (setq kuro--half-frame-interval  (/ 0.5 new-rate))
  (setq kuro--frame-budget-seconds (/ 1.0 new-rate))
  (setq kuro--budget-threshold-high   (* 0.9 kuro--frame-budget-seconds))
  (setq kuro--budget-threshold-low    (* 0.5 kuro--frame-budget-seconds))
  (setq kuro--budget-absolute-seconds (* kuro--frame-budget-ratio kuro--frame-budget-seconds))
  (kuro--recompute-blink-frame-intervals))

(defun kuro--ring-pending-bell ()
  "Ring the Emacs bell if a bell event is pending from the terminal."
  (when (kuro--call nil (kuro-core-take-bell-pending kuro--session-id))
    (ding)))

(defun kuro--tick-blink-if-active ()
  "Tick blink overlays if any are registered for the current buffer."
  (when kuro--blink-overlays
    (kuro--tick-blink-overlays)))

;;; Top-level render cycle

(defun kuro--render-cycle ()
  "Single render cycle composed of four sequential pipeline stages.

Stage 1 -- Resize (unconditional): synchronizes PTY dimensions before
  any display work, even when the frame is coalesced.

Stage 2 -- Coalesced render (gated by `kuro--with-frame-coalescing'):
  2a.  Bell: ring if pending.
  2b.  Dirty updates: rewrite changed rows and advance cursor.
  2c.  Mode poll: DECCKM, mouse, CWD, clipboard (budget-gated).
  2d.  Blink: tick overlay animations.

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
