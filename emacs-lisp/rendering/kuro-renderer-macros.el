;;; kuro-renderer-macros.el --- Renderer macros -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Macro helpers for `kuro-renderer.el'.

;;; Code:

(defmacro kuro--recompute-budget-vars (rate)
  "Set all five frame-budget cached variables from RATE fps.
Used identically by `kuro--start-render-loop' and `kuro--switch-render-timer'
to keep thresholds in sync whenever the active timer period changes."
  `(progn
     (setq kuro--frame-budget-seconds    (/ 1.0 ,rate))
     (setq kuro--half-frame-interval     (/ 0.5 ,rate))
     (setq kuro--budget-threshold-high   (* 0.9 kuro--frame-budget-seconds))
     (setq kuro--budget-threshold-low    (* 0.5 kuro--frame-budget-seconds))
     (setq kuro--budget-absolute-seconds (* kuro--frame-budget-ratio kuro--frame-budget-seconds))))

(defmacro kuro--with-frame-coalescing (&rest body)
  "Execute BODY only when enough time has elapsed since the last render frame.
Implements frame coalescing: when multiple timer sources (120fps periodic,
streaming idle, input echo delay) all fire within the same frame period,
only the first call executes BODY.  Subsequent calls within half a frame
period are skipped, preventing redundant partial-screen redraws.

At 120fps, the half-frame threshold is 4.2ms - sufficient to coalesce
the input echo timer (10ms) and streaming idle timer into the next tick.

Updates `kuro--last-render-time' on the first non-coalesced call, so that
`kuro--update-tui-streaming-timer' (which runs outside this guard) always
observes the dirty count from the most recently rendered frame."
  (declare (indent 0))
  `(let ((now (float-time)))
     (when (>= (- now kuro--last-render-time) kuro--half-frame-interval)
       (setq kuro--last-render-time now)
       ,@body)))

(defmacro kuro--with-live-render-frame (&rest body)
  "Execute BODY for the live current buffer and bind `frame-start'.

The coalescing guard stays outside this macro so the stage-2 work can be
reused by tests and timed independently."
  `(when (buffer-live-p (current-buffer))
     (let ((frame-start (float-time)))
       ,@body)))

(provide 'kuro-renderer-macros)

;;; kuro-renderer-macros.el ends here
