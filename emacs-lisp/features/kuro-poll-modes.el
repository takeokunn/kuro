;;; kuro-poll-modes.el --- Tiered terminal mode polling for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; This file provides the tiered polling mechanism that reads terminal mode
;; state from the Rust backend on a cadence-gated schedule.
;;
;; # Responsibilities
;;
;; - Tier-1 polling (every `kuro--mode-poll-cadence' frames):
;;   consolidated FFI call for DECCKM/mouse/paste/keyboard modes, CWD
;;   (OSC 7), clipboard actions (OSC 52), OSC 133 prompt marks, Kitty
;;   Graphics image notifications, and process-exit detection.
;; - Tier-2 polling (every `kuro--osc-rare-poll-cadence' frames):
;;   color palette (OSC 4) and default colors (OSC 10/11/12).
;; - Frame counter management: `kuro--mode-poll-frame-count' is
;;   incremented and used to gate both tiers.
;;
;; # Architecture
;;
;; `kuro-renderer.el' calls `kuro--poll-terminal-modes' once per
;; coalesced render frame (budget-gated via `kuro--poll-within-budget').
;; Adding a new shell-interaction-timescale poll: update
;; `kuro--tier1-poll-fns' for tests/docs and
;; `kuro--run-tier1-poll-fns' for runtime dispatch.

;;; Code:

(require 'kuro-config)
(require 'kuro-eval)
(require 'kuro-ffi)
(require 'kuro-ffi-modes)
(require 'kuro-ffi-osc)
(require 'kuro-navigation)
(require 'kuro-prompt-status)
(require 'kuro-hyperlinks)
(require 'kuro-tramp)
(require 'kuro-poll-modes-macros)

(declare-function kuro--apply-palette-updates     "kuro-faces"      ())
(declare-function kuro--apply-default-colors      "kuro-faces"      ())
(declare-function kuro--render-image-notification "kuro-overlays"   (notif))
(declare-function kuro--update-prompt-positions   "kuro-navigation" (marks positions max-count))
(declare-function notifications-notify            "notifications"   (&rest params))
(declare-function kuro--poll-notifications        "kuro-ffi-osc"    ())
(declare-function kuro--update-prompt-status      "kuro-prompt-status" (marks))
(declare-function kuro-kill                       "kuro-lifecycle"  ())
(declare-function kuro--poll-eval-command-updates "kuro-eval"       ())
(declare-function kuro--apply-hyperlink-ranges    "kuro-hyperlinks" ())
(declare-function kuro--apply-cwd-with-tramp     "kuro-tramp"      ())

;; Forward references: these defvar-locals live in their respective modules.
;; kuro-input.el
(defvar kuro--application-cursor-keys-mode nil
  "Forward reference; `defvar-local' in kuro-input.el.")
(defvar kuro--app-keypad-mode nil
  "Forward reference; `defvar-local' in kuro-input.el.")
(defvar kuro--mouse-mode)
(defvar kuro--mouse-sgr)
(defvar kuro--mouse-pixel-mode)
(defvar kuro--bracketed-paste-mode)
(defvar kuro--keyboard-flags)
;; kuro-navigation.el
(defvar kuro--prompt-positions nil
  "Forward reference; `defvar-local' in kuro-navigation.el.")

(eval-and-compile
  (defconst kuro--tier1-poll-fns
    '(kuro--poll-terminal-mode-state  ; consolidated FFI - must stay first
      kuro--poll-cwd
      kuro--handle-clipboard-actions
      kuro--poll-prompt-mark-updates
      kuro--poll-eval-command-updates
      kuro--poll-image-events
      kuro--apply-hyperlink-ranges
      kuro--check-process-exit)
    "Tier-1 poll functions called at the configured poll cadence.
Add new shell-interaction-timescale polls here; the dispatch loop needs
no changes."))

;;; Cadence constants

(defconst kuro--mode-poll-cadence 10
  "Poll terminal modes (DECCKM, cursor shape, OSC 10/11) every N render frames.
At 30 fps this yields approximately 333 ms between polls.")

(defconst kuro--osc-rare-poll-cadence 30
  "Poll rare OSC events (color palette, default colors) every N render frames.
At 30 fps this yields approximately 1 second between polls.")

(defconst kuro--max-prompt-positions 1000
  "Maximum number of prompt positions to track.")

;;; Buffer-local frame counter

(kuro--defvar-permanent-local kuro--mode-poll-frame-count (1- kuro--mode-poll-cadence)
  "Frame counter for all terminal mode polling (DECCKM, mouse, OSC, etc.).
Incremented each render frame and used to gate tiered polling cadences.
Initialized to (1- kuro--mode-poll-cadence) so the first poll fires
at the end of frame N rather than immediately at frame 0.
See `kuro--mode-poll-cadence' and `kuro--osc-rare-poll-cadence'.")

;;; Tier-2: rare OSC events

(defun kuro--poll-osc-events ()
  "Poll rare OSC events.
This includes palette, default-color, and desktop-notification events.
Called every `kuro--osc-rare-poll-cadence' frames.  At 30 fps this fires
approximately once per second.  Changes occur at user-action timescale
\(theme switch, startup), so a ~1 second lag is invisible."
  (kuro--apply-palette-updates)
  (kuro--apply-default-colors)
  (kuro--handle-notifications))

(defun kuro--default-notify (title body)
  "Show a terminal desktop notification with TITLE and BODY.
Prefers `notifications-notify' (D-Bus) when available; otherwise falls back
to the echo area.  TITLE may be nil."
  (or (and (require 'notifications nil t)
           (fboundp 'notifications-notify)
           (ignore-errors
             (notifications-notify :title (or title "kuro")
                                   :body body
                                   :app-name "kuro")
             t))
      (message "%s%s"
               (if (and title (not (string-empty-p title)))
                   (concat title ": ")
                 "")
               body)))

(defun kuro--handle-notifications ()
  "Drain and display pending OSC 9 / OSC 777 desktop notifications.
Always drains the queue (so it cannot grow unbounded); displays each
notification via `kuro-notification-function' only when
`kuro-notifications-enabled' is non-nil."
  (let ((notifs (kuro--poll-notifications)))
    (when kuro-notifications-enabled
      (dolist (notif notifs)
        (funcall kuro-notification-function (car notif) (cdr notif))))))

;;; Tier-1: mode application and per-item pollers

(defun kuro--apply-terminal-modes (modes)
  "Apply MODES vector to buffer-local terminal mode variables.
MODES is the 7-element list from `kuro--get-terminal-modes':
  (acm akm mm msgr mpm bpm kbf)
  0: application-cursor-keys  1: app-keypad  2: mouse-mode
  3: mouse-sgr                4: mouse-pixel 5: bracketed-paste
  6: keyboard-flags (nil → 0 when pre-Kitty-KB)."
  ;; Direct nth avoids pcase-let* pattern-dispatch overhead (12 calls/sec).
  (setq kuro--application-cursor-keys-mode (nth 0 modes)
        kuro--app-keypad-mode              (nth 1 modes)
        kuro--mouse-mode                   (nth 2 modes)
        kuro--mouse-sgr                    (nth 3 modes)
        kuro--mouse-pixel-mode             (nth 4 modes)
        kuro--bracketed-paste-mode         (nth 5 modes)
        kuro--keyboard-flags               (or (nth 6 modes) 0)))

(defun kuro--poll-cwd ()
  "Apply a pending working-directory change from OSC 7 (if any).
Uses Tramp path construction when a remote hostname is detected."
  (kuro--apply-cwd-with-tramp))

(defvar kuro-on-command-complete-functions nil
  "Abnormal hook run for each OSC 133 command-end mark received.
Each function is called with arguments:
  (EXIT-CODE DURATION-MS AID ERR-PATH BUFFER-VISIBLE-P)
EXIT-CODE is the integer exit status (or nil if not provided by the shell).
DURATION-MS is the command duration in milliseconds (or nil if not provided).
AID is the shell-assigned command ID string (or nil).
ERR-PATH is an error path string for the failed command (or nil).
BUFFER-VISIBLE-P is non-nil when the kuro buffer is currently displayed.

Functions on this hook are called from the render-cycle timer context.
Avoid blocking operations; use `run-with-timer 0' for deferred work.")

(defun kuro--run-command-complete-hook (marks)
  "Run `kuro-on-command-complete-functions' for command-end entries.
MARKS is the OSC 133 marker list to inspect."
  (when kuro-on-command-complete-functions
    (let ((visible (and (get-buffer-window (current-buffer) t) t)))
      (dolist (mark marks)
        (pcase-let ((`(,type ,_row ,_col ,exit-code . ,rest) mark))
          (when (equal type "command-end")
            (let ((aid         (nth 0 rest))
                  (duration-ms (nth 1 rest))
                  (err-path    (nth 2 rest)))
              (run-hook-with-args 'kuro-on-command-complete-functions
                                  exit-code duration-ms aid err-path
                                  visible))))))))

(defun kuro--poll-prompt-mark-updates ()
  "Merge pending OSC 133 prompt mark into `kuro--prompt-positions'."
  (when-let* ((marks (kuro--poll-prompt-marks)))
    (kuro--update-prompt-status marks)
    (kuro--run-command-complete-hook marks)
    (setq kuro--prompt-positions
          (kuro--update-prompt-positions
           marks kuro--prompt-positions kuro--max-prompt-positions))))

(defun kuro--poll-image-events ()
  "Render pending Kitty Graphics image notifications."
  (dolist (notif (kuro--poll-image-notifications))
    (kuro--render-image-notification notif)))

(defun kuro--check-process-exit ()
  "Kill the buffer when `kuro-kill-buffer-on-exit' is set and process exited."
  (when (and kuro-kill-buffer-on-exit (not (kuro--is-process-alive)))
    (kuro-kill)))

(defun kuro--send-osc52-clipboard-response ()
  "Send OSC 52 clipboard response with the current `kill-ring' head to the PTY."
  (let ((text (condition-case nil (current-kill 0 t) (error ""))))
    (kuro--send-key
     (format "\e]52;c;%s\a"
             (base64-encode-string (or text "") t)))))

(defsubst kuro--clipboard-action-payload (action)
  "Return the payload string of clipboard ACTION.
ACTION is the new 3-element list (TAG PAYLOAD TARGET) or a legacy
2-element form — the list (TAG PAYLOAD) or the cons (TAG . PAYLOAD).
The cons form is detected by a non-list cdr."
  (let ((rest (cdr action)))
    (if (listp rest) (car rest) rest)))

(defsubst kuro--clipboard-action-target (action)
  "Return the selection-target string of clipboard ACTION, or nil.
Only the new 3-element list (TAG PAYLOAD TARGET) carries a target; legacy
2-element actions yield nil, defaulting writes to the clipboard."
  (let ((rest (cdr action)))
    (and (consp rest) (nth 1 rest))))

(defun kuro--clipboard-set-selection (text target)
  "Place TEXT on the Emacs selection chosen by TARGET.
TARGET is a string from the OSC 52 selection field:
  \"primary\" / \"select\" → the X PRIMARY selection;
  \"clipboard\", \"cut-buffer-N\", nil, or any unknown value →
  the kill ring and the CLIPBOARD selection (the default path)."
  (pcase target
    ((or "primary" "select")
     (gui-set-selection 'PRIMARY text))
    (_
     (kill-new text))))

(defun kuro--clipboard-write (text &optional target)
  "Place TEXT on the Emacs selection chosen by TARGET per `kuro-clipboard-policy'.
TARGET routes the write (see `kuro--clipboard-set-selection'); when nil the
write goes to the clipboard for backward compatibility.
Under `write-only' or `allow': accepts silently.  Under `prompt': asks first.
Under `deny' or any other value: does nothing."
  (pcase kuro-clipboard-policy
    ((or 'write-only 'allow)
     (kuro--clipboard-set-selection text target)
     (message "Kuro: clipboard updated from terminal"))
    ('prompt
     (when (yes-or-no-p
            (format "Kuro: terminal wants to set clipboard (%d chars).  Allow? "
                    (length text)))
       (kuro--clipboard-set-selection text target)))))

(defun kuro--clipboard-query ()
  "Respond to a clipboard read request per `kuro-clipboard-policy'.
Under `allow': responds immediately.  Under `prompt': asks first.
Under `deny', `write-only', or any other value: does nothing."
  (pcase kuro-clipboard-policy
    ('allow (kuro--send-osc52-clipboard-response))
    ('prompt
     (when (yes-or-no-p "Kuro: terminal wants to read clipboard.  Allow? ")
       (kuro--send-osc52-clipboard-response)))))

(defun kuro--handle-clipboard-actions ()
  "Process pending OSC 52 clipboard actions per `kuro-clipboard-policy'.
Drains the action queue from `kuro--poll-clipboard-actions' and dispatches:
  `write' → `kuro--clipboard-write'
  `query' → `kuro--clipboard-query'"
  (dolist (action (kuro--poll-clipboard-actions))
    (kuro--dispatch-clipboard-action action)))

(defun kuro--poll-terminal-mode-state ()
  "Fetch all terminal mode state in a single consolidated FFI call (PERF-005).
`kuro--get-terminal-modes' acquires one Mutex instead of seven separate
acquisitions.  Must remain first in `kuro--tier1-poll-fns' so it runs before
any poll that reads mode variables populated by `kuro--apply-terminal-modes'."
  (when-let* ((modes (kuro--get-terminal-modes)))
    (kuro--apply-terminal-modes modes)))

;;; Tier-1 consolidated dispatcher

(defun kuro--poll-tier1-modes ()
  "Run the fixed tier-1 poll sequence in order."
  (kuro--run-tier1-poll-fns))

;;; Top-level gated dispatcher

(defun kuro--poll-terminal-modes ()
  "Gate tier-1 and tier-2 polling at their respective cadences.
Tier-1 (`kuro--poll-tier1-modes') fires every `kuro--mode-poll-cadence'
frames; tier-2 (`kuro--poll-osc-events') fires every
`kuro--osc-rare-poll-cadence' frames.  Tiering reduces per-frame Mutex
acquisitions from ~11 to ~5, cutting lock contention with the PTY reader."
  (kuro--gated-poll kuro--mode-poll-cadence     #'kuro--poll-tier1-modes)
  (kuro--gated-poll kuro--osc-rare-poll-cadence #'kuro--poll-osc-events))

(provide 'kuro-poll-modes)

;;; kuro-poll-modes.el ends here
