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
;; - Per-frame render cycle: dirty line updates, cursor, title, CWD,
;;   clipboard (OSC 52), prompt marks (OSC 133), Kitty Graphics images
;; - Cursor position and shape updates
;; - Window title sanitization
;;
;; # Architecture
;;
;; Color conversion and face caching are in `kuro-faces'.
;; Overlay management (blink, image, hyperlink) is in `kuro-overlays'.
;; Input handling is in `kuro-input'.

;;; Code:

(require 'kuro-ffi)
(require 'kuro-ffi-modes)
(require 'kuro-ffi-osc)
(require 'kuro-input)
(require 'kuro-config)
(require 'kuro-faces)
(require 'kuro-overlays)
(require 'kuro-stream)
(require 'kuro-render-buffer)
(require 'kuro-navigation)

;; Forward declarations for symbols defined in transitively-loaded modules.
;; These are always available at runtime because `kuro-input' (required above)
;; loads `kuro-input-keymap', which in turn loads `kuro-input-mouse' and
;; `kuro-input-paste'.  The declarations below suppress byte-compiler warnings
;; when those modules have not yet been seen during compilation.
(defvar kuro--mouse-mode)
(defvar kuro--mouse-sgr)
(defvar kuro--mouse-pixel-mode)
(defvar kuro--bracketed-paste-mode)
(defvar kuro--keyboard-flags)

;; Forward declarations for defvar-local symbols defined in other modules that
;; kuro-renderer.el writes to or reads directly.
;; kuro-ffi.el
(defvar kuro--initialized nil
  "Forward reference; defvar-local in kuro-ffi.el.")
(defvar kuro--resize-pending nil
  "Forward reference; defvar-local in kuro-ffi.el.")
(defvar kuro--col-to-buf-map nil
  "Forward reference; defvar-local in kuro-ffi.el.")
;; kuro.el
(defvar kuro--last-rows 0
  "Forward reference; defvar-local in kuro.el.")
(defvar kuro--last-cols 0
  "Forward reference; defvar-local in kuro.el.")
;; kuro-input.el
(defvar kuro--application-cursor-keys-mode nil
  "Forward reference; defvar-local in kuro-input.el.")
(defvar kuro--app-keypad-mode nil
  "Forward reference; defvar-local in kuro-input.el.")
(defvar kuro--scroll-offset 0
  "Forward reference; defvar-local in kuro-input.el.")
;; kuro-navigation.el
(defvar kuro--prompt-positions nil
  "Forward reference; defvar-local in kuro-navigation.el.")

;; kuro-kill is defined in kuro-lifecycle.el which requires kuro-renderer.el;
;; use declare-function to avoid a circular require.
(declare-function kuro-kill "kuro-lifecycle" ())

;; Bell function provided by the Rust dynamic module at runtime.
(declare-function kuro-core-take-bell-pending "ext:kuro-core" ())
(declare-function kuro--update-line-full        "kuro-render-buffer" (row text face-ranges col-to-buf))
(declare-function kuro--resize                  "kuro-ffi"           (rows cols))
(declare-function kuro--apply-palette-updates   "kuro-faces"         ())
(declare-function kuro--apply-default-colors    "kuro-faces"         ())
(declare-function kuro--render-image-notification "kuro-overlays"    (notif))
(declare-function kuro--apply-buffer-scroll     "kuro-render-buffer" (up down))
(declare-function kuro--tick-blink-overlays     "kuro-overlays"      ())
(declare-function kuro--start-stream-idle-timer    "kuro-stream"        ())
(declare-function kuro--stop-stream-idle-timer     "kuro-stream"        ())
(declare-function kuro--update-prompt-positions    "kuro-navigation"    (marks positions max-count))

;;; Render cadence constants

(defconst kuro--mode-poll-cadence 10
  "Poll terminal modes (DECCKM, cursor shape, OSC 10/11) every N render frames.
At 30 fps this yields approximately 333 ms between polls.")

(defconst kuro--osc-rare-poll-cadence 30
  "Poll rare OSC events (color palette, default colors) every N render frames.
At 30 fps this yields approximately 1 second between polls.")

(defconst kuro--max-prompt-positions 1000
  "Maximum number of prompt positions to track.")

(defconst kuro--tui-dirty-threshold 0.8
  "Fraction of dirty lines (0.0–1.0) that triggers TUI mode detection. A value of 0.8 means 80% of rows must be dirty before the renderer switches to TUI mode.")

(defconst kuro--col-to-buf-evict-factor 2
  "Hysteresis multiplier for the col-to-buf hash map eviction threshold.
When the hash map has more than this factor times the terminal row count,
stale entries are pruned to prevent unbounded growth during long sessions.")

(defconst kuro--tui-mode-threshold 10
  "Consecutive full-dirty frames before suppressing the streaming idle timer.
At 60fps this is ~167ms — fast enough to detect a TUI app within ~167ms
but slow enough to avoid false suppression during a burst of AI output.")

;;; Buffer-local render state

(defvar-local kuro--timer nil
  "Timer object for the Kuro render loop.
Internal state; do not set directly.
Each Kuro buffer maintains its own independent timer.")
(put 'kuro--timer 'permanent-local t)

(defvar-local kuro--cursor-marker nil
  "Marker for cursor position.")
(put 'kuro--cursor-marker 'permanent-local t)

(defvar-local kuro--mode-poll-frame-count (1- kuro--mode-poll-cadence)
  "Frame counter for all terminal mode polling (DECCKM, mouse, OSC, etc.).
Incremented each render frame and used to gate tiered polling cadences.
Initialized to (1- kuro--mode-poll-cadence) so the first poll fires
at the end of frame N rather than immediately at frame 0.
See `kuro--mode-poll-cadence' and `kuro--osc-rare-poll-cadence'.")
(put 'kuro--mode-poll-frame-count 'permanent-local t)

(defvar-local kuro--tui-mode-frame-count 0
  "Consecutive frames with dirty-row fraction >= `kuro--tui-dirty-threshold'.
When this reaches `kuro--tui-mode-threshold', the streaming idle timer is
suppressed because TUI apps (cmatrix, htop, vim, etc.) always have pending
output and the idle timer would only add spurious render cycles on top of
the normal 60fps ticker.")
(put 'kuro--tui-mode-frame-count 'permanent-local t)

(defvar-local kuro--last-render-time 0.0
  "Float-time of the last completed render cycle.
Used for frame coalescing: when multiple timer sources (60fps periodic,
streaming idle, input echo delay) all fire within the same frame period,
only the first actually renders.  Subsequent fires within half a frame
period are skipped, preventing redundant partial-screen redraws that
manifest as flickering on complex TUI apps like Claude Code.")
(put 'kuro--last-render-time 'permanent-local t)

;;; Render loop lifecycle

(defun kuro--start-render-loop ()
  "Start the render loop targeting the current buffer.
Also starts the low-latency streaming idle timer when
`kuro-streaming-latency-mode' is non-nil."
  (when (timerp kuro--timer)
    (cancel-timer kuro--timer))
  (let ((buf (current-buffer)))
    (setq kuro--timer
          (run-with-timer
           0
           (/ 1.0 kuro-frame-rate)
           (lambda () (when (buffer-live-p buf)
                         (with-current-buffer buf
                           (kuro--render-cycle)))))))
  ;; Start the zero-delay idle timer for streaming latency reduction
  (kuro--start-stream-idle-timer))

(defun kuro--stop-render-loop ()
  "Stop the render loop and streaming idle timer."
  (when (timerp kuro--timer)
    (cancel-timer kuro--timer)
    (setq kuro--timer nil))
  (kuro--stop-stream-idle-timer))

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
  (when kuro--resize-pending
    (let ((new-rows (car kuro--resize-pending))
          (new-cols (cdr kuro--resize-pending)))
      (setq kuro--resize-pending nil)
      (when (and kuro--initialized (> new-rows 0) (> new-cols 0))
        (setq kuro--last-rows new-rows
              kuro--last-cols new-cols)
        (kuro--resize new-rows new-cols)
        ;; Adjust buffer line count to match new rows.
        ;; Use line-number-at-pos instead of count-lines: count-lines counts
        ;; newlines, which overcounts by 1 when the buffer has a trailing \n
        ;; (the normal state — each row is terminated by \n).
        (let ((inhibit-read-only t)
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

(defun kuro--handle-clipboard-actions ()
  "Process pending OSC 52 clipboard actions according to `kuro-clipboard-policy'.
Drains the action queue returned by `kuro--poll-clipboard-actions' and
dispatches each entry:
  `write' — place terminal-supplied text on the kill ring (with optional prompt).
  `query' — respond with the current kill-ring head (with optional prompt).

On `query': sends an OSC 52 response with the current kill-ring head
  back to the PTY via `kuro--send-key' (active-terminal output).
Returns nil."
  (let ((actions (kuro--poll-clipboard-actions)))
    (dolist (action actions)
      (pcase (car action)
        ('write
         (pcase kuro-clipboard-policy
           ((or 'write-only 'allow)
            (kill-new (cdr action))
            (message "kuro: clipboard updated from terminal"))
           ('prompt
            (when (yes-or-no-p
                   (format "kuro: terminal wants to set clipboard (%d chars). Allow? "
                           (length (cdr action))))
              (kill-new (cdr action))))))
        ('query
         (pcase kuro-clipboard-policy
           ('allow
            (let ((text (condition-case nil (current-kill 0 t) (error ""))))
              (kuro--send-key
               (format "\e]52;c;%s\a"
                       (base64-encode-string (or text "") t)))))
           ('prompt
            (when (yes-or-no-p "kuro: terminal wants to read clipboard. Allow? ")
              (let ((text (condition-case nil (current-kill 0 t) (error ""))))
                (kuro--send-key
                 (format "\e]52;c;%s\a"
                         (base64-encode-string (or text "") t))))))))))))

(defun kuro--poll-osc-events ()
  "Poll rare OSC events: color palette (OSC 4) and default colors (OSC 10/11/12).
Called every `kuro--osc-rare-poll-cadence' frames.  At 30 fps this fires
approximately once per second.  Changes occur at user-action timescale
(theme switch, startup), so a ~1 second lag is invisible."
  (kuro--apply-palette-updates)
  (kuro--apply-default-colors))

(defun kuro--poll-terminal-modes ()
  "Poll terminal mode state and OSC events at a tiered cadence.
Uses `kuro--mode-poll-frame-count' (incremented by the caller before this
function runs) to gate two polling tiers:

  Every `kuro--mode-poll-cadence' frames  — DECCKM, mouse, bracketed-paste,
    keyboard flags, CWD (OSC 7), clipboard (OSC 52), prompt marks (OSC 133),
    and Kitty Graphics image notifications.

  Every `kuro--osc-rare-poll-cadence' frames — color palette (OSC 4) and
    default fg/bg colors (OSC 10/11).

Tiering reduces unconditional per-frame Mutex acquisitions from ~11 to ~5,
cutting lock contention between the Emacs timer thread and the PTY reader."
  (when (zerop (mod kuro--mode-poll-frame-count kuro--mode-poll-cadence))
    ;; Terminal mode queries (changes are rare; 167ms lag is imperceptible)
    (setq kuro--application-cursor-keys-mode (kuro--get-app-cursor-keys))
    (setq kuro--app-keypad-mode (kuro--get-app-keypad))
    (setq kuro--mouse-mode (kuro--get-mouse-mode))
    (setq kuro--mouse-sgr (kuro--get-mouse-sgr))
    (setq kuro--mouse-pixel-mode (kuro--get-mouse-pixel))
    (setq kuro--bracketed-paste-mode (kuro--get-bracketed-paste))
    (setq kuro--keyboard-flags (or (kuro--get-keyboard-flags) 0))
    ;; CWD (OSC 7): shell-rate events; 167ms lag acceptable
    (let ((cwd (kuro--get-cwd)))
      (when (and cwd (stringp cwd) (not (string-empty-p cwd)))
        (setq default-directory (file-name-as-directory cwd))))
    ;; Clipboard (OSC 52): user-triggered; 167ms lag acceptable (yes-or-no-p blocks anyway)
    (kuro--handle-clipboard-actions)
    ;; Prompt marks (OSC 133): arrive with shell prompts; 167ms lag acceptable
    (let ((marks (kuro--poll-prompt-marks)))
      (when marks
        (setq kuro--prompt-positions
              (kuro--update-prompt-positions
               marks kuro--prompt-positions kuro--max-prompt-positions))))
    ;; Kitty Graphics image notifications: low-frequency async events
    (let ((image-notifs (kuro--poll-image-notifications)))
      (dolist (notif image-notifs)
        (kuro--render-image-notification notif)))
    ;; Process exit detection: kill buffer when shell has exited
    (when (and kuro-kill-buffer-on-exit
               (not (kuro--is-process-alive)))
      (kuro-kill)))
  (when (zerop (mod kuro--mode-poll-frame-count kuro--osc-rare-poll-cadence))
    (kuro--poll-osc-events)))

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

(defsubst kuro--detect-tui-mode (dirty-lines total-rows threshold)
  "Return t if the dirty-line fraction indicates a full-screen TUI app is active.
DIRTY-LINES is the number of terminal rows updated this frame.
TOTAL-ROWS is the total number of terminal rows.
THRESHOLD is the minimum fraction (0.0–1.0) of rows that must be dirty.
Returns t when DIRTY-LINES >= ceiling(THRESHOLD * TOTAL-ROWS), nil otherwise."
  (>= dirty-lines (ceiling (* threshold total-rows))))

(defun kuro--update-tui-streaming-timer (updates)
  "Update streaming idle timer state based on dirty-row fraction in UPDATES.
When >= `kuro--tui-dirty-threshold' of terminal rows are dirty for
>= `kuro--tui-mode-threshold' consecutive frames, stops the streaming
idle timer.  Restarts it when dirty-row fraction drops below the threshold."
  (when (and kuro-streaming-latency-mode (> kuro--last-rows 0))
    (let* ((dirty-count (if updates (length updates) 0))
           (full-dirty-p (kuro--detect-tui-mode dirty-count kuro--last-rows kuro--tui-dirty-threshold)))
      (cond
       (full-dirty-p
        (setq kuro--tui-mode-frame-count (1+ kuro--tui-mode-frame-count))
        (when (= kuro--tui-mode-frame-count kuro--tui-mode-threshold)
          (kuro--stop-stream-idle-timer)))
       ((>= kuro--tui-mode-frame-count kuro--tui-mode-threshold)
        ;; Transition: leaving TUI mode — restart idle timer
        (setq kuro--tui-mode-frame-count 0)
        (kuro--start-stream-idle-timer))
       (t
        (setq kuro--tui-mode-frame-count 0))))))

(defun kuro--evict-stale-col-to-buf-entries (dirty-rows)
  "Remove stale col-to-buf mappings from `kuro--col-to-buf-map'.
Evicts entries for:
  1. Rows >= `kuro--last-rows' (out-of-bounds after resize).
  2. Dirty rows whose updated col-to-buf is empty (transitioned from CJK
     to ASCII) — the identity fallback is correct for these rows, so the
     stale CJK mapping must not linger.
Guard `kuro--last-rows' > 0 to avoid spurious eviction before the first resize.
2x hysteresis: only triggers when the map exceeds 2× the current row count.
Returns nil."
  (when (and (> kuro--last-rows 0)
             (> (hash-table-count kuro--col-to-buf-map) (* kuro--col-to-buf-evict-factor kuro--last-rows)))
    (let ((max-row kuro--last-rows)
          stale-keys)
      ;; Collect out-of-bounds rows.
      (maphash (lambda (k _v)
                 (when (>= k max-row)
                   (push k stale-keys)))
               kuro--col-to-buf-map)
      ;; Collect dirty rows that now have empty col-to-buf (CJK → ASCII transition).
      (when dirty-rows
        (dolist (line-update dirty-rows)
          (let* ((col-to-buf (cdr line-update))
                 (row (car (car (car line-update)))))
            (when (and (integerp row)
                       (vectorp col-to-buf)
                       (zerop (length col-to-buf)))
              (push row stale-keys)))))
      (dolist (k stale-keys)
        (remhash k kuro--col-to-buf-map)))))

(defun kuro--apply-dirty-updates ()
  "Apply dirty-line updates from Rust and advance the cursor position.
Called once per render frame after `kuro--handle-pending-resize' and
`kuro--poll-terminal-modes'.

Responsibilities:
  1. Consume pending full-screen scroll events BEFORE polling dirty lines
     so that buffer-level delete+insert happens before per-row text rewrites.
  2. Poll the Rust side for dirty lines with face data
     (`kuro--poll-updates-with-faces') and rewrite each dirty row via
     `kuro--update-line-full', batched under `inhibit-redisplay' so Emacs
     performs exactly one display flush per frame.
  3. Move point to the current cursor position (`kuro--update-cursor').
  4. Evict stale entries from `kuro--col-to-buf-map' when the table grows
     beyond 2× the current row count (hysteresis prevents churn).
  5. Detect full-screen TUI apps (≥80% dirty rows for
     `kuro--tui-mode-threshold' consecutive frames) and suppress the
     streaming idle timer while in TUI mode, restoring it when the app exits."
  ;; --- Scroll events + dirty line updates + cursor + title ---
  ;; ALL buffer/frame modifications are wrapped in a single `inhibit-redisplay'
  ;; block so Emacs performs exactly one display flush per frame.  This includes
  ;; the title update (OSC 2): `rename-buffer' and `set-frame-parameter' both
  ;; trigger redisplay, so they must be inside the block to prevent mid-frame
  ;; flashes.  Previously, scroll events (delete-region + insert) ran outside
  ;; this block, causing flickering on full-screen TUI apps like btop.
  ;;
  ;; FFI data structure (per line):
  ;;   (((row . text) . face-list) . col-to-buf-vector)
  ;; col-to-buf-vector maps grid column index → buffer char offset.
  ;; Face ranges use buffer offsets (not grid column indices).
  (let ((updates nil))
    (let ((inhibit-redisplay t))
      ;; Window title (OSC 2): inside inhibit-redisplay to prevent
      ;; rename-buffer / set-frame-parameter from triggering a mid-frame flush.
      (kuro--apply-title-update)
      ;; Consume pending scroll counts BEFORE polling dirty lines so that
      ;; buffer-level delete+insert happens before per-row text rewrites.
      (kuro--process-scroll-events)
      (setq updates (kuro--poll-updates-with-faces))
      (when updates
        (dolist (line-update updates)
          ;; line-update = (((row . text) . face-list) . col-to-buf-vector)
          (let* ((line-and-faces (car line-update))
                 (col-to-buf    (cdr line-update))
                 (line-data     (car line-and-faces))
                 (face-ranges   (cdr line-and-faces))
                 (row           (car line-data))
                 (text          (cdr line-data)))
            ;; Per-row condition-case: an error on row K is swallowed but
            ;; subsequent rows still render.  Wrapping the entire dolist would
            ;; silently discard all remaining rows after the first error.
            (condition-case nil
                (kuro--update-line-full row text face-ranges col-to-buf)
              (error nil)))))
      (kuro--update-cursor))
    ;; Outside inhibit-redisplay: lightweight bookkeeping that doesn't
    ;; modify buffer content and doesn't need display suppression.
    (kuro--evict-stale-col-to-buf-entries updates)
    (kuro--update-tui-streaming-timer updates)))

;;; Render cycle

(defun kuro--render-cycle ()
  "Single render cycle: poll updates and update buffer.
Frame coalescing: when multiple timer sources fire within the same frame
period, only the first actually renders.  This prevents the streaming idle
timer, input echo timer, and periodic 60fps timer from each producing a
separate partial-screen update within 16ms, which causes visible flickering
on complex TUI apps like Claude Code."
  ;; Frame coalescing: skip if we rendered within half a frame period.
  ;; At 60fps, half-frame = 8.3ms — enough to coalesce the input echo
  ;; timer (10ms) and streaming idle timer into the next periodic tick.
  (let ((now (float-time)))
    (when (>= (- now kuro--last-render-time) (/ 0.5 kuro-frame-rate))
      (setq kuro--last-render-time now)
      (kuro--handle-pending-resize)
      ;; Advance the frame counter before polling so that cadence checks inside
      ;; `kuro--poll-terminal-modes' see the incremented value.
      (setq kuro--mode-poll-frame-count (1+ kuro--mode-poll-frame-count))
      (kuro--poll-terminal-modes)
      ;; Guard: kuro-kill may have been called from within kuro--poll-terminal-modes
      ;; (process-exit path).  If the buffer was killed, abort the render cycle so
      ;; the bell, dirty-update, and blink-overlay operations do not run against
      ;; whatever buffer Emacs switched to after kill-buffer.
      (when (buffer-live-p (current-buffer))
        ;; --- Bell ---
        (when (kuro-core-take-bell-pending)
          (ding))
        ;; --- Dirty updates (buffer modifications + cursor) ---
        (kuro--apply-dirty-updates)
        ;; --- Blink overlays ---
        ;; Tick AFTER dirty updates so that newly created blink overlays from
        ;; `kuro--update-line-full' and pre-existing overlays on non-dirty rows
        ;; see the same blink phase.  Previously this ran before dirty updates,
        ;; causing a one-frame phase mismatch between dirty and non-dirty rows.
        (kuro--tick-blink-overlays)))))

(provide 'kuro-renderer)

;;; kuro-renderer.el ends here
