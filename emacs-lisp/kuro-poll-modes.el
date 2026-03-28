;;; kuro-poll-modes.el --- Tiered terminal mode polling for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

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
;; Adding a new shell-interaction-timescale poll: push its function
;; symbol onto `kuro--tier1-poll-fns'.

;;; Code:

(require 'kuro-config)
(require 'kuro-ffi)
(require 'kuro-ffi-modes)
(require 'kuro-ffi-osc)
(require 'kuro-navigation)

(declare-function kuro--apply-palette-updates     "kuro-faces"      ())
(declare-function kuro--apply-default-colors      "kuro-faces"      ())
(declare-function kuro--render-image-notification "kuro-overlays"   (notif))
(declare-function kuro--update-prompt-positions   "kuro-navigation" (marks positions max-count))
(declare-function kuro-kill                       "kuro-lifecycle"  ())

;; Forward references: these defvar-locals live in their respective modules.
;; kuro-input.el
(defvar kuro--application-cursor-keys-mode nil
  "Forward reference; defvar-local in kuro-input.el.")
(defvar kuro--app-keypad-mode nil
  "Forward reference; defvar-local in kuro-input.el.")
(defvar kuro--mouse-mode)
(defvar kuro--mouse-sgr)
(defvar kuro--mouse-pixel-mode)
(defvar kuro--bracketed-paste-mode)
(defvar kuro--keyboard-flags)
;; kuro-navigation.el
(defvar kuro--prompt-positions nil
  "Forward reference; defvar-local in kuro-navigation.el.")

;;; Cadence constants

(defconst kuro--mode-poll-cadence 10
  "Poll terminal modes (DECCKM, cursor shape, OSC 10/11) every N render frames.
At 30 fps this yields approximately 333 ms between polls.")

(defconst kuro--osc-rare-poll-cadence 30
  "Poll rare OSC events (color palette, default colors) every N render frames.
At 30 fps this yields approximately 1 second between polls.")

;;; Cadence-gating macro (CPS continuation dispatch)

(defmacro kuro--gated-poll (cadence fn)
  "Invoke FN when `kuro--mode-poll-frame-count' is an exact multiple of CADENCE.
Built on `kuro--when-divisible': the function FN is only called at intervals
of CADENCE frames, reducing per-frame Mutex acquisitions."
  `(kuro--when-divisible kuro--mode-poll-frame-count ,cadence (funcall ,fn)))

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
  "Poll rare OSC events: color palette (OSC 4) and default colors (OSC 10/11/12).
Called every `kuro--osc-rare-poll-cadence' frames.  At 30 fps this fires
approximately once per second.  Changes occur at user-action timescale
(theme switch, startup), so a ~1 second lag is invisible."
  (kuro--apply-palette-updates)
  (kuro--apply-default-colors))

;;; Tier-1: mode application and per-item pollers

(defun kuro--apply-terminal-modes (modes)
  "Apply MODES vector to buffer-local terminal mode variables.
MODES is the 7-element list from `kuro--get-terminal-modes':
  (acm akm mm msgr mpm bpm kbf)
  0: application-cursor-keys  1: app-keypad  2: mouse-mode
  3: mouse-sgr                4: mouse-pixel 5: bracketed-paste
  6: keyboard-flags (nil → 0 when pre-Kitty-KB)."
  (pcase-let* ((`(,acm ,akm ,mm ,msgr ,mpm ,bpm ,kbf) modes))
    (setq kuro--application-cursor-keys-mode acm
          kuro--app-keypad-mode              akm
          kuro--mouse-mode                   mm
          kuro--mouse-sgr                    msgr
          kuro--mouse-pixel-mode             mpm
          kuro--bracketed-paste-mode         bpm
          kuro--keyboard-flags               (or kbf 0))))

(defun kuro--poll-cwd ()
  "Apply a pending working-directory change from OSC 7 (if any)."
  (when-let ((cwd (kuro--get-cwd)))
    (when (and (stringp cwd) (not (string-empty-p cwd)))
      (setq default-directory (file-name-as-directory cwd)))))

(defun kuro--poll-prompt-mark-updates ()
  "Merge pending OSC 133 prompt marks into `kuro--prompt-positions'."
  (when-let ((marks (kuro--poll-prompt-marks)))
    (setq kuro--prompt-positions
          (kuro--update-prompt-positions
           marks kuro--prompt-positions kuro--max-prompt-positions))))

(defun kuro--poll-image-events ()
  "Render pending Kitty Graphics image notifications."
  (dolist (notif (kuro--poll-image-notifications))
    (kuro--render-image-notification notif)))

(defun kuro--check-process-exit ()
  "Kill the buffer when `kuro-kill-buffer-on-exit' is set and process has exited."
  (when (and kuro-kill-buffer-on-exit (not (kuro--is-process-alive)))
    (kuro-kill)))

(defsubst kuro--send-osc52-clipboard-response ()
  "Send OSC 52 clipboard response with the current kill-ring head to the PTY."
  (let ((text (condition-case nil (current-kill 0 t) (error ""))))
    (kuro--send-key
     (format "\e]52;c;%s\a"
             (base64-encode-string (or text "") t)))))

(defun kuro--handle-clipboard-actions ()
  "Process pending OSC 52 clipboard actions per `kuro-clipboard-policy'.
Drains the action queue returned by `kuro--poll-clipboard-actions' and
dispatches each entry:
  `write' -- place terminal-supplied text on the kill ring (optional prompt).
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
            (kuro--send-osc52-clipboard-response))
           ('prompt
            (when (yes-or-no-p "kuro: terminal wants to read clipboard. Allow? ")
              (kuro--send-osc52-clipboard-response)))))))))

(defconst kuro--tier1-poll-fns
  '(kuro--poll-cwd
    kuro--handle-clipboard-actions
    kuro--poll-prompt-mark-updates
    kuro--poll-image-events
    kuro--check-process-exit)
  "Tier-1 poll functions called in order every `kuro--mode-poll-cadence' frames.
Add new shell-interaction-timescale polls here; no code changes to the dispatch loop.")

;;; Tier-1 consolidated dispatcher

(defun kuro--poll-tier1-modes ()
  "Poll tier-1 terminal state: modes, CWD, clipboard, prompts, images, exit.
A single consolidated FFI call (`kuro--get-terminal-modes', PERF-005)
replaces 7 individual Mutex acquisitions.  All other tier-1 items
(CWD, clipboard, prompt marks, image notifications, process exit) are
at shell-interaction timescale so 167 ms lag is imperceptible."
  (when-let ((modes (kuro--get-terminal-modes)))
    (kuro--apply-terminal-modes modes))
  (mapc #'funcall kuro--tier1-poll-fns))

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
