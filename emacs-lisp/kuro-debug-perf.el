;;; kuro-debug-perf.el --- Per-frame performance debugging for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; This file provides the per-frame performance measurement infrastructure
;; for Kuro.  It is intentionally kept separate from the render loop so that
;; the debug symbols can be loaded (or omitted) without touching hot paths.
;;
;; # Responsibilities
;;
;; - `kuro-debug-perf' defcustom: user-facing toggle for timing collection.
;; - `kuro--perf-frame-count' / `kuro--perf-sample-interval': sampling state.
;; - `kuro--perf-report': writes one timing line to the *kuro-perf* buffer.
;;
;; # Usage
;;
;;   (setq kuro-debug-perf t)   ; enable timing
;;   M-x switch-to-buffer RET *kuro-perf* RET

;;; Code:

;;; User-facing toggle

(defvar kuro-debug-perf nil
  "When non-nil, log per-frame timing to the *kuro-perf* buffer.
Toggle with (setq kuro-debug-perf t) to diagnose rendering bottlenecks.
Stats are written every `kuro--perf-sample-interval' frames so the
logging itself does not perturb the measurement.")

;;; Sampling state

(defvar kuro--perf-frame-count 0
  "Total render frame counter used by `kuro-debug-perf' sampling.")

(defconst kuro--perf-sample-interval 10
  "Log a perf line every N frames when `kuro-debug-perf' is non-nil.")

;;; Reporter

(defun kuro--perf-report (ffi-ms apply-ms cursor-ms total-ms dirty face-count)
  "Append one timing line to *kuro-perf*.
FFI-MS: Rust poll-updates-with-faces wall time.
APPLY-MS: kuro--apply-dirty-lines wall time.
CURSOR-MS: kuro--update-cursor wall time.
TOTAL-MS: entire inhibit-redisplay block wall time.
DIRTY: number of dirty rows sent by Rust.
FACE-COUNT: total face-range tuples across all dirty rows."
  (with-current-buffer (get-buffer-create "*kuro-perf*")
    (goto-char (point-max))
    (insert (format "[f%05d] rows=%2d faces=%4d | ffi=%5.1fms apply=%5.1fms cur=%4.2fms TOTAL=%5.1fms\n"
                    kuro--perf-frame-count dirty face-count
                    ffi-ms apply-ms cursor-ms total-ms))))

(provide 'kuro-debug-perf)

;;; kuro-debug-perf.el ends here
