;;; kuro-debug-perf.el --- Per-frame performance debugging for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

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

(defcustom kuro-debug-perf nil
  "When non-nil, log per-frame timing to the *kuro-perf* buffer.
Toggle with (setq kuro-debug-perf t) to diagnose rendering bottlenecks.
Stats are written every `kuro--perf-sample-interval' frames so the
logging itself does not perturb the measurement."
  :type 'boolean
  :group 'kuro)

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
TOTAL-MS: entire `inhibit-redisplay' block wall time.
DIRTY: number of dirty rows sent by Rust.
FACE-COUNT: total face-range tuples across all dirty rows."
  (with-current-buffer (get-buffer-create "*kuro-perf*")
    (goto-char (point-max))
    (insert (format "[f%05d] rows=%2d faces=%4d | ffi=%5.1fms apply=%5.1fms cur=%4.2fms TOTAL=%5.1fms\n"
                    kuro--perf-frame-count dirty face-count
                    ffi-ms apply-ms cursor-ms total-ms))))

;;; Diagnostic command

;; Forward declarations for buffer-local variables used by the diagnostic.
(defvar kuro--initialized)
(defvar kuro--session-id)
(defvar kuro--last-rows)
(defvar kuro--last-cols)
(defvar kuro--resize-pending)
(defvar kuro--scroll-offset)
(defvar kuro--tui-mode-active)
(defvar kuro--last-cursor-row)
(defvar kuro--last-cursor-col)
(defvar kuro--col-to-buf-map)

;;;###autoload
(defun kuro-debug-state ()
  "Display terminal state diagnostics for the current kuro buffer.
Useful for diagnosing TUI rendering issues.  Reports buffer line
count, PTY dimensions, window geometry, scroll state, and cursor."
  (interactive)
  (unless (derived-mode-p 'kuro-mode)
    (user-error "Not in a kuro buffer"))
  (let* ((win (get-buffer-window (current-buffer) t))
         (buf-lines (1- (line-number-at-pos (point-max))))
         (win-rows (and win (window-body-height win)))
         (win-cols (and win (window-body-width win)))
         (win-start (and win (window-start win)))
         (win-vscroll (and win (window-vscroll win)))
         (win-hscroll (and win (window-hscroll win)))
         (msg (format
               (concat "--- kuro-debug-state ---\n"
                       "init=%s session=%d\n"
                       "buf-lines=%d last-rows=%d last-cols=%d\n"
                       "win-rows=%s win-cols=%s\n"
                       "win-start=%s point-min=%d vscroll=%s hscroll=%s\n"
                       "resize-pending=%s scroll-offset=%d tui=%s\n"
                       "cursor-row=%s cursor-col=%s\n"
                       "col-to-buf-count=%d\n"
                       "scroll-margin=%s scroll-conservatively=%s auto-window-vscroll=%s\n"
                       "frame-char-width=%s frame-char-height=%s")
               kuro--initialized kuro--session-id
               buf-lines kuro--last-rows kuro--last-cols
               win-rows win-cols
               win-start (point-min) win-vscroll win-hscroll
               kuro--resize-pending kuro--scroll-offset kuro--tui-mode-active
               kuro--last-cursor-row kuro--last-cursor-col
               (if (hash-table-p kuro--col-to-buf-map) (hash-table-count kuro--col-to-buf-map) 0)
               scroll-margin scroll-conservatively auto-window-vscroll
               (frame-char-width) (frame-char-height))))
    (message "%s" msg)))

;;;###autoload
(defun kuro-debug-line-widths ()
  "Report per-row display width vs expected terminal columns.
Identifies rows where the Emacs `string-width' of the line text
differs from `kuro--last-cols', which would cause horizontal
misalignment in TUI apps.  Only anomalous rows are listed."
  (interactive)
  (unless (derived-mode-p 'kuro-mode)
    (user-error "Not in a kuro buffer"))
  (let ((expected kuro--last-cols)
        (anomalies nil))
    (save-excursion
      (goto-char (point-min))
      (dotimes (row kuro--last-rows)
        (let* ((line-start (point))
               (line-end   (line-end-position))
               (text       (buffer-substring-no-properties line-start line-end))
               (display-w  (string-width text))
               (char-count (length text)))
          (unless (or (= display-w expected) (= display-w 0))
            (push (format "  row %2d: display-w=%d chars=%d delta=%+d | %.40s"
                          row display-w char-count (- display-w expected)
                          (replace-regexp-in-string "[\x00-\x1f]" "?" text))
                  anomalies)))
        (forward-line 1)))
    (if anomalies
        (message "--- line width anomalies (expected %d) ---\n%s"
                 expected (mapconcat #'identity (nreverse anomalies) "\n"))
      (message "All %d rows have expected display width %d (or are empty)"
               kuro--last-rows expected))))

(provide 'kuro-debug-perf)

;;; kuro-debug-perf.el ends here
