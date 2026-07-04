;;; kuro-poll-modes.el --- Tiered terminal mode polling for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

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
(require 'kuro-text-size)
(require 'kuro-tramp)
(require 'kuro-poll-modes-macros)

(declare-function kuro--apply-palette-updates     "kuro-faces"      ())
(declare-function kuro--apply-default-colors      "kuro-faces"      ())
(declare-function kuro--render-image-notification "kuro-overlays"   (notif))
(declare-function kuro--render-placeholder-regions "kuro-overlays"  (regions))
(declare-function kuro--update-prompt-positions   "kuro-navigation" (marks positions max-count))
(declare-function notifications-notify            "notifications"   (&rest params))
(declare-function kuro--poll-notifications        "kuro-ffi-osc"    ())
(declare-function kuro--notify-action-response    "kuro-ffi-osc"    (session-id id button close))
(declare-function kuro--update-prompt-status      "kuro-prompt-status" (marks))
(declare-function kuro-kill                       "kuro-lifecycle"  ())
(declare-function kuro--poll-eval-command-updates "kuro-eval"       ())
(declare-function kuro--apply-hyperlink-ranges    "kuro-hyperlinks" ())
(declare-function kuro--apply-text-size-ranges    "kuro-text-size"  ())
(declare-function kuro--apply-cwd-with-tramp     "kuro-tramp"      ())
(declare-function kuro--get-progress             "kuro-ffi-osc"    ())
(declare-function kuro--poll-user-vars-raw       "kuro-ffi-osc"    ())

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
      kuro--poll-progress
      kuro--poll-user-vars
      kuro--handle-clipboard-actions
      kuro--poll-prompt-mark-updates
      kuro--poll-eval-command-updates
      kuro--poll-image-events
      kuro--poll-placeholder-events
      kuro--apply-hyperlink-ranges
      kuro--apply-text-size-ranges
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

(defun kuro--notify-build-action-handler (session-id id)
  "Return an `:on-action' handler closure for OSC 99 notification ID.
SESSION-ID is captured so the response is routed to the originating session
even if the buffer's `kuro--session-id' has since changed.  The returned
closure is called by `notifications-notify' with the activated action key
\(a string).  \"default\" (whole-notification activation) sends a plain
activation report; a numeric key sends a button-index report; any other
key is ignored."
  (lambda (action-key)
    (let ((button (cond ((equal action-key "default") -1)
                        ((and (stringp action-key)
                              (string-match-p "\\`[0-9]+\\'" action-key))
                         (string-to-number action-key))
                        (t nil))))
      (when button
        (kuro--notify-action-response session-id id button nil)))))

(defconst kuro--notification-sanitize-regexp
  "[\x00-\x1f\x7f\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069]"
  "Control and bidi-control characters stripped from OSC notifications.
Terminal output is untrusted; stripping ASCII control characters
\(U+0000-U+001F, U+007F) and Unicode bidirectional control characters
\(U+061C, U+200E, U+200F, U+202A-U+202E, U+2066-U+2069) prevents
notification and echo-area spoofing via crafted OSC 9/777/99 titles and
bodies.")

(defun kuro--sanitize-notification-text (text)
  "Return TEXT with control and bidi-override characters removed, or nil.
TEXT may be nil, in which case nil is returned unchanged."
  (and text
       (replace-regexp-in-string kuro--notification-sanitize-regexp "" text)))

(defun kuro--default-notify (title body &optional id report)
  "Show a terminal desktop notification with TITLE and BODY.
Prefers `notifications-notify' (D-Bus) when available; otherwise falls back
to the echo area.  TITLE may be nil.

When REPORT is non-nil and ID (an OSC 99 `i=<id>' string) is provided, the
D-Bus notification is given an activation action whose `:on-action' callback
sends an OSC 99 report back to the terminal application via the Rust core, so
the application learns the notification was activated.  When D-Bus is
unavailable this gracefully degrades to a plain echo-area message (no action
round-trip is possible without a clickable notification).  TITLE and BODY are
sanitized by the caller, `kuro--handle-notifications', before reaching any
`kuro-notification-function'."
  (or (and (require 'notifications nil t)
           (fboundp 'notifications-notify)
           (ignore-errors
             (apply #'notifications-notify
                    (append
                     (list :title (or title "kuro")
                           :body body
                           :app-name "kuro")
                     (when (and report id)
                       (list :actions '("default" "Activate")
                             :on-action
                             (kuro--notify-build-action-handler
                              kuro--session-id id)))))
             t))
      (message "%s%s"
               (if (and title (not (string-empty-p title)))
                   (concat title ": ")
                 "")
               body)))

(defun kuro--notification-fields (notif)
  "Extract (TITLE BODY ID REPORT) from a polled NOTIF entry.
Accepts the current 4-element list form `(TITLE BODY ID REPORT)' produced by
the Rust FFI, as well as the legacy cons form `(TITLE . BODY)' (ID and REPORT
default to nil) for backward compatibility."
  (if (and (consp notif) (listp (cdr notif)))
      (list (nth 0 notif) (nth 1 notif) (nth 2 notif) (nth 3 notif))
    (list (car notif) (cdr notif) nil nil)))

(defun kuro--handle-notifications ()
  "Drain and display pending OSC 9 / OSC 777 / OSC 99 desktop notifications.
Always drains the queue (so it cannot grow unbounded); displays each
notification via `kuro-notification-function' only when
`kuro-notifications-enabled' is non-nil.  When the notification carries an
OSC 99 id and requested an `a=report' action, the id and report flag are
forwarded so the notify function can wire an action round-trip.

TITLE and BODY are sanitized here, at the dispatch chokepoint, rather than
inside the default notify function: `kuro-notification-function' is a
public customization point, and any replacement the user installs must
receive already-sanitized text, not just the built-in default."
  (let ((notifs (kuro--poll-notifications)))
    (when kuro-notifications-enabled
      (dolist (notif notifs)
        (pcase-let ((`(,title ,body ,id ,report)
                     (kuro--notification-fields notif)))
          (funcall kuro-notification-function
                   (kuro--sanitize-notification-text title)
                   (kuro--sanitize-notification-text body)
                   id report))))))

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
Uses Tramp path construction when a remote hostname is detected.
The Rust core feeds both OSC 7 and the iTerm2 OSC 1337 `CurrentDirectory='
notification into the same cwd slot, so this single poll handles both."
  (kuro--apply-cwd-with-tramp))

;;; Tier-1: OSC 9;4 progress (ConEmu) mode-line indicator

(kuro--defvar-permanent-local kuro--progress-state nil
  "Current ConEmu OSC 9;4 progress as a cons cell (STATE . PERCENT), or nil.
STATE is the ConEmu state code (1=set, 2=error, 3=indeterminate, 4=warning);
PERCENT is 0-100.  nil means no progress is active (state 0 / done).
Updated by `kuro--poll-progress'; rendered into `mode-line-process'.")

(defun kuro--progress-state-glyph (state)
  "Return the mode-line glyph string for OSC 9;4 progress STATE.
Looks up STATE in `kuro-progress-state-glyphs'; unknown states yield \"\"."
  (or (cdr (assq state kuro-progress-state-glyphs)) ""))

(defun kuro--progress-mode-line-string (state percent)
  "Build the mode-line indicator string for progress STATE and PERCENT.
Returns nil when `kuro-progress-format' is nil (textual indicator disabled)."
  (when kuro-progress-format
    (format kuro-progress-format (kuro--progress-state-glyph state) percent)))

(defun kuro--apply-progress (progress)
  "Apply a polled PROGRESS cons cell (STATE . PERCENT) to mode-line state.
A nil or state-0 PROGRESS clears the indicator; any other state stores the
cons in `kuro--progress-state' and refreshes the mode line.  Honors
`kuro-progress-enabled': when nil the indicator is cleared even on a
non-zero state."
  (let ((state (and (consp progress) (car progress))))
    (setq kuro--progress-state
          (and kuro-progress-enabled
               state
               (/= state 0)
               progress))
    (force-mode-line-update)))

(defun kuro--progress-mode-line ()
  "Return the mode-line indicator string for the current progress, or nil.
Designed for use as a `mode-line-process' `:eval' form: returns nil when no
progress is active so nothing is shown."
  (when (consp kuro--progress-state)
    (kuro--progress-mode-line-string (car kuro--progress-state)
                                     (cdr kuro--progress-state))))

(defun kuro--poll-progress ()
  "Poll the ConEmu OSC 9;4 progress state and update the mode-line indicator.
Drains the dirty progress slot from the Rust core (so it cannot get stuck)
and routes it through `kuro--apply-progress'.  A nil result means unchanged
since the last poll, so the existing indicator is left untouched."
  (when-let* ((progress (kuro--get-progress)))
    (kuro--apply-progress progress)))

;;; Tier-1: OSC 1337 SetUserVar user variables

(kuro--defvar-permanent-local kuro--user-vars nil
  "Alist of iTerm2 OSC 1337 `SetUserVar' user variables for this buffer.
Each entry is (NAME . VALUE), both strings; VALUE is base64-decoded by the
Rust core.  Replaced wholesale (the Rust core sends the full current set)
whenever the user-vars change.  Other Lisp can read this to react to shell-
exported variables.")

(defun kuro--poll-user-vars ()
  "Poll iTerm2 OSC 1337 `SetUserVar' user variables into `kuro--user-vars'.
The Rust core returns the full current set as a list of (NAME . VALUE) cons
cells when changed, or nil when unchanged (leaving the cache intact)."
  (when-let* ((vars (kuro--poll-user-vars-raw)))
    (setq kuro--user-vars vars)))

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

(defun kuro--poll-placeholder-events ()
  "Render Kitty Unicode-placeholder (U+10EEEE) image regions on the grid.
Polls `kuro--poll-placeholder-placements' (a non-draining query re-derived
from the grid each frame) and hands the region descriptors to
`kuro--render-placeholder-regions', which clears and re-attaches per-cell
image tiles.  Skips the work entirely when no placeholders are present."
  (let ((regions (kuro--poll-placeholder-placements)))
    (kuro--render-placeholder-regions regions)))

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

(defsubst kuro--clipboard-action-strict-p (action)
  "Return non-nil when ACTION is exactly (TAG PAYLOAD TARGET)."
  (and (consp action)
       (consp (cdr action))
       (consp (cddr action))
       (null (cdddr action))))

(defsubst kuro--clipboard-action-payload (action)
  "Return the payload slot of strict clipboard ACTION."
  (cadr action))

(defsubst kuro--clipboard-action-target (action)
  "Return the target slot of strict clipboard ACTION."
  (caddr action))

(defsubst kuro--clipboard-target-kind (target)
  "Return normalized selection kind for strict OSC 52 TARGET, or nil."
  (cond
   ((equal target "clipboard") 'clipboard)
   ((or (equal target "primary") (equal target "select")) 'primary)
   (t nil)))

(defconst kuro--clipboard-sanitize-regexp
  "[\x00-\x08\x0b-\x1f\x7f]"
  "Control characters stripped from OSC 52 clipboard payloads.
Keeps TAB and LF so multi-line and tabbed clipboard text survives, but
removes ESC, CR, BEL, and other C0/DEL bytes.  Terminal output is
untrusted; those bytes enable escape-sequence injection or CR-based
line-overwrite spoofing when the clipboard is later yanked into another
terminal.  This does not by itself make pasted text safe to execute —
LF is intentionally kept, so a multi-line payload can still run multiple
shell commands if blindly pasted into a prompt.  Guarding against that
is `kuro-clipboard-policy''s job (use `prompt' to confirm each write),
not this sanitizer's.")

(defun kuro--clipboard-sanitize (text)
  "Return TEXT with paste-injection-prone control characters removed."
  (replace-regexp-in-string kuro--clipboard-sanitize-regexp "" text))

(defun kuro--clipboard-set-selection (text target)
  "Place TEXT on the Emacs selection chosen by TARGET.
TARGET must be \"clipboard\", \"primary\", or \"select\".
TEXT is sanitized of dangerous control characters before being stored."
  (let ((text (kuro--clipboard-sanitize text)))
    (pcase (kuro--clipboard-target-kind target)
      ('clipboard
       (kill-new text))
      ('primary
       (gui-set-selection 'PRIMARY text))
      (_ nil))))

(defun kuro--clipboard-write (text target)
  "Place TEXT on the Emacs selection chosen by TARGET per `kuro-clipboard-policy'.
TARGET must be \"clipboard\", \"primary\", or \"select\".
Under `write-only' or `allow': accepts silently.  Under `prompt': asks first.
Under `deny' or any other value: does nothing."
  (when (and (stringp text) (kuro--clipboard-target-kind target))
    (pcase kuro-clipboard-policy
      ((or 'write-only 'allow)
       (kuro--clipboard-set-selection text target)
       (message "Kuro: clipboard updated from terminal"))
      ('prompt
       ;; Report the sanitized length so the prompt reflects what is actually
       ;; stored (`kuro--clipboard-set-selection' re-sanitizes idempotently).
       (when (yes-or-no-p
              (format "Kuro: terminal wants to set clipboard (%d chars).  Allow? "
                      (length (kuro--clipboard-sanitize text))))
         (kuro--clipboard-set-selection text target))))))

(defun kuro--clipboard-query (target)
  "Respond to a clipboard read request per `kuro-clipboard-policy'.
TARGET must be \"clipboard\", \"primary\", or \"select\".
Under `allow': responds immediately.  Under `prompt': asks first.
Under `deny', `write-only', or any other value: does nothing."
  (when (kuro--clipboard-target-kind target)
    (pcase kuro-clipboard-policy
      ('allow (kuro--send-osc52-clipboard-response))
      ('prompt
       (when (yes-or-no-p "Kuro: terminal wants to read clipboard.  Allow? ")
         (kuro--send-osc52-clipboard-response))))))

(defun kuro--handle-clipboard-actions ()
  "Process pending OSC 52 clipboard actions per `kuro-clipboard-policy'.
Drains strict (TAG PAYLOAD TARGET) actions from `kuro--poll-clipboard-actions'
and dispatches:
  `write' -> `kuro--clipboard-write'
  `query' -> `kuro--clipboard-query'"
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
