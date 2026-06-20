;;; kuro-input-render.el --- Render scheduling helpers for Kuro input  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; This module owns the small render-scheduling contract used by input and
;; rendering tests.  The public symbol names stay in the kuro-input namespace;
;; this file only isolates the timer logic.

;;; Code:

(require 'kuro-config)
(require 'kuro-input-macros)

;; Forward reference: kuro--render-cycle is defined in kuro-renderer.el,
;; which is loaded after kuro-input.el. Declare it here to suppress warnings.
(declare-function kuro--render-cycle "kuro-renderer" ())

(defvar kuro-input-echo-delay nil
  "Forward reference; defined in kuro-config.el.")

(kuro--defvar-permanent-local kuro--pending-render-timer nil
  "One-shot idle timer that fires an immediate render cycle after input.
Buffer-local so that multiple kuro buffers each manage their own timer
independently and cannot cancel or interfere with each other.")

(defun kuro--do-pending-render (buf)
  "Execute a render cycle in BUF if it is still live.
Named helper for `kuro--schedule-immediate-render' so that
`run-with-idle-timer' can pass the buffer as an argument instead of
capturing it in a new closure on every keypress."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (kuro--render-cycle))))

(defun kuro--schedule-immediate-render ()
  "Schedule a render cycle after `kuro-input-echo-delay' seconds.
The small delay gives the PTY reader thread time to process the shell echo
and deposit it in the channel before we poll for dirty lines and cursor
updates. Cancels any previously pending timer so rapid typing coalesces
into a single render call."
  (when (timerp kuro--pending-render-timer)
    (cancel-timer kuro--pending-render-timer))
  (setq kuro--pending-render-timer
        (run-with-idle-timer
         kuro-input-echo-delay nil
         #'kuro--do-pending-render (current-buffer))))

(provide 'kuro-input-render)

;;; kuro-input-render.el ends here
