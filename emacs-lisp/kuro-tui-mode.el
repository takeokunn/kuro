;;; kuro-tui-mode.el --- TUI mode detection and adaptive frame rate for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; This file provides TUI mode detection and adaptive frame-rate management
;; for the Kuro terminal emulator.
;;
;; # Responsibilities
;;
;; - Detect full-screen TUI applications (vim, htop, cmatrix, etc.) by
;;   measuring the fraction of dirty rows per render frame.
;; - Switch the render timer between normal and TUI frame rates when the
;;   dirty-row fraction crosses the configured threshold.
;; - Suppress the streaming idle timer during TUI sessions to avoid
;;   spurious render cycles on top of the normal high-fps ticker.
;;
;; # Architecture
;;
;; `kuro-renderer.el' calls `kuro--update-tui-streaming-timer' once per
;; timer invocation (outside the frame-coalescing guard) so that
;; `kuro--tui-mode-frame-count' accumulates on every tick, not only on
;; frames that actually render.
;;
;; `kuro-stream.el' owns the streaming idle timer lifecycle; this module
;; only calls `kuro--start-stream-idle-timer' and
;; `kuro--stop-stream-idle-timer' through the declared interface.

;;; Code:

(require 'kuro-ffi)
(require 'kuro-config)

(declare-function kuro--switch-render-timer     "kuro-renderer"       (new-rate))
(declare-function kuro--start-stream-idle-timer "kuro-stream"         ())
(declare-function kuro--stop-stream-idle-timer  "kuro-stream"         ())

;; Forward reference: defvar-permanent-local in kuro.el.
(defvar kuro--last-rows 0
  "Forward reference; defvar-permanent-local in kuro.el.")

;;; Constants

(defconst kuro--tui-dirty-threshold 0.8
  "Fraction of dirty lines (0.0-1.0) that triggers TUI mode detection.
A value of 0.8 means 80% of rows must be dirty before the renderer
switches to TUI mode.")

(defconst kuro--tui-mode-threshold 10
  "Consecutive full-dirty frames before suppressing the streaming idle timer.
At 120fps this is ~83ms — fast enough to detect a TUI app within ~83ms
but slow enough to avoid false suppression during a burst of AI output.")

;;; Buffer-local TUI state

(kuro--defvar-permanent-local kuro--tui-mode-frame-count 0
  "Consecutive frames with dirty-row fraction >= `kuro--tui-dirty-threshold'.
When this reaches `kuro--tui-mode-threshold', the streaming idle timer is
suppressed because TUI apps (cmatrix, htop, vim, etc.) always have pending
output and the idle timer would only add spurious render cycles on top of
the normal 120fps ticker.")

(kuro--defvar-permanent-local kuro--tui-mode-active nil
  "Non-nil when TUI mode is active (render timer at `kuro-tui-frame-rate').")

(kuro--defvar-permanent-local kuro--last-dirty-count 0
  "Number of dirty lines from the last actual render.
Stored during `kuro--apply-dirty-updates' and read by the TUI detection
logic in `kuro--render-cycle' which runs outside the frame coalescing guard.")

;;; TUI mode detection

(defsubst kuro--detect-tui-mode (dirty-lines total-rows threshold)
  "Return t when the dirty-line fraction indicates a full-screen TUI app.
DIRTY-LINES is the number of terminal rows updated this frame.
TOTAL-ROWS is the total number of terminal rows.
THRESHOLD is the minimum fraction (0.0–1.0) of rows that must be dirty.
Uses integer arithmetic (both sides multiplied by 10) to avoid
floating-point precision issues in `ceiling'.  For THRESHOLD=0.8:
\(round (* 0.8 10)) = 8, so the check becomes >= (* 10 dirty) (* 8 rows)."
  (>= (* 10 dirty-lines) (* (round (* threshold 10)) total-rows)))

;;; TUI mode transitions

(defun kuro--enter-tui-mode ()
  "Activate TUI mode: use TUI frame rate and suppress the streaming idle timer."
  (kuro--stop-stream-idle-timer)
  (kuro--switch-render-timer kuro-tui-frame-rate)
  (setq kuro--tui-mode-active t))

(defun kuro--exit-tui-mode ()
  "Deactivate TUI mode: restore normal frame rate and restart the idle timer."
  (kuro--switch-render-timer kuro-frame-rate)
  (setq kuro--tui-mode-active nil)
  (kuro--start-stream-idle-timer))

;;; TUI streaming-timer update

(defun kuro--update-tui-streaming-timer ()
  "Update TUI mode state based on `kuro--last-dirty-count'.
Called OUTSIDE the frame coalescing guard in `kuro--render-cycle' so it
runs on every timer invocation, not just non-coalesced frames.  This fixes
the bug where frame coalescing prevented `kuro--tui-mode-frame-count'
from ever accumulating to the threshold.

When >= `kuro--tui-dirty-threshold' of terminal rows are dirty for
>= `kuro--tui-mode-threshold' consecutive frames, enters TUI mode:
stops the streaming idle timer and switches the render timer to
`kuro-tui-frame-rate'.  When dirty-row fraction drops below the threshold,
exits TUI mode and restores the normal `kuro-frame-rate' timer."
  (when (and kuro-streaming-latency-mode (> kuro--last-rows 0))
    (let ((full-dirty-p (kuro--detect-tui-mode kuro--last-dirty-count kuro--last-rows kuro--tui-dirty-threshold)))
      (cond
       (full-dirty-p
        (setq kuro--tui-mode-frame-count (1+ kuro--tui-mode-frame-count))
        (when (and (= kuro--tui-mode-frame-count kuro--tui-mode-threshold)
                   (not kuro--tui-mode-active))
          (kuro--enter-tui-mode)))
       ((>= kuro--tui-mode-frame-count kuro--tui-mode-threshold)
        (setq kuro--tui-mode-frame-count 0)
        (when kuro--tui-mode-active
          (kuro--exit-tui-mode)))
       (t
        (setq kuro--tui-mode-frame-count 0))))))

(provide 'kuro-tui-mode)

;;; kuro-tui-mode.el ends here
