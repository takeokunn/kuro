;;; kuro-stream.el --- Smooth streaming output for AI agents in Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; This file provides smooth streaming output rendering for AI agent output
;; (Claude Code, aider, etc.) in the Kuro terminal emulator.
;;
;; # Features
;;
;; 1. **Low-latency PTY notification**: A fast idle timer fires immediately
;;    when PTY data arrives, bypassing the normal 120fps polling interval.
;;    This makes streaming text appear token-by-token without batching delay.
;;
;; 2. **Adaptive frame rate**: When PTY output is flowing (AI streaming),
;;    the render loop automatically increases its poll frequency.  When the
;;    terminal is idle, it returns to the configured `kuro-frame-rate'.
;;
;; 3. **Typewriter animation effect**: Optional character-by-character
;;    display that makes AI output appear to "type itself".  Configurable
;;    speed via `kuro-typewriter-chars-per-second'.
;;
;; 4. **Synchronized output integration**: When the terminal sends
;;    `?2026 h` (Synchronized Output), pending lines are held until `?2026 l`
;;    is received, preventing partial-frame flicker.
;;
;; # Architecture
;;
;; - `kuro--stream-idle-timer': 0-delay idle timer, fires when Emacs is idle.
;;   Calls `kuro--render-cycle' if PTY has pending output.
;; - `kuro--typewriter-queue': Buffer of (row . text) updates waiting to
;;   be displayed character-by-character.
;; - `kuro--typewriter-timer': Fast timer (default 120fps) draining the queue.

;;; Code:

(require 'kuro-ffi)
(require 'kuro-ffi-osc)
(require 'kuro-typewriter)

;; Forward declare to avoid circular dependency with kuro-renderer.el
(declare-function kuro--render-cycle      "kuro-renderer" ())
(declare-function kuro--has-pending-output "kuro-ffi-osc"  ())

;; Variables defined in kuro-config.el; loaded before kuro-stream at runtime
;; via kuro-renderer.el.  Declared here to suppress byte-compiler warnings.
(defvar kuro-streaming-latency-mode)
(defvar kuro-frame-rate)

;;; Internal state

(kuro--defvar-permanent-local kuro--stream-idle-timer nil
  "One-shot idle timer for low-latency PTY output detection.
Fires when Emacs is idle and PTY has pending data.
Set to nil when streaming latency mode is disabled.")

(kuro--defvar-permanent-local kuro--stream-last-render-time 0.0
  "Float-time of last render triggered by the streaming idle timer.
Used to rate-limit idle renders to at most `kuro-frame-rate' times/second.")

(kuro--defvar-permanent-local kuro--stream-min-interval nil
  "Minimum seconds between idle-timer render cycles.
Derived from `kuro-frame-rate'.
Computed lazily: nil means unset, will be computed on first idle render.")

;;; Low-latency idle timer

(defun kuro--stream-idle-tick (buf)
  "Timer tick handler for Kuro stream polling in buffer BUF.
Called on every Emacs idle event when the streaming idle timer is active.
Checks that BUF is live and streaming latency mode is enabled, then
rate-limits render calls to at most `kuro-frame-rate' times per second.
When PTY has pending output and the rate-limit interval has elapsed,
triggers `kuro--render-cycle' to flush the new data immediately."
  (when (and (buffer-live-p buf)
             kuro-streaming-latency-mode)
    (with-current-buffer buf
      (when kuro--initialized
        (when (kuro--has-pending-output)
          ;; Rate-limit: fire render at most kuro-frame-rate times/sec.
          ;; kuro--has-pending-output is checked at full idle frequency
          ;; (not rate-limited) so streaming detection stays responsive.
          (let ((now (float-time)))
            (when (>= (- now kuro--stream-last-render-time)
                      (or kuro--stream-min-interval
                          (setq kuro--stream-min-interval
                                (/ 1.0 kuro-frame-rate))))
              ;; Reuse `now' to avoid a second gettimeofday syscall.
              (setq kuro--stream-last-render-time now)
              (kuro--render-cycle))))))))

(defun kuro--start-stream-idle-timer ()
  "Start the zero-delay idle timer for low-latency streaming output.
When `kuro-streaming-latency-mode' is non-nil, this fires a render
cycle immediately whenever Emacs becomes idle and PTY has data."
  (when kuro-streaming-latency-mode
    (when (timerp kuro--stream-idle-timer)
      (cancel-timer kuro--stream-idle-timer)
      (setq kuro--stream-idle-timer nil))
    (let ((buf (current-buffer)))
      (setq kuro--stream-idle-timer
            (run-with-idle-timer
             0 t                           ; repeat=t: fire every time Emacs is idle
             (lambda () (kuro--stream-idle-tick buf)))))))

(defun kuro--stop-stream-idle-timer ()
  "Stop the streaming idle timer.
Also resets `kuro--stream-min-interval' to nil so that if `kuro-frame-rate'
is changed before the timer is restarted, the new rate is picked up on the
next lazy computation instead of reusing the stale cached interval."
  (when (timerp kuro--stream-idle-timer)
    (cancel-timer kuro--stream-idle-timer)
    (setq kuro--stream-idle-timer nil)
    (setq kuro--stream-last-render-time 0.0)
    (setq kuro--stream-min-interval nil)))

(provide 'kuro-stream)

;;; kuro-stream.el ends here
