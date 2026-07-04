;;; kuro-prompt-status.el --- Prompt exit-status indicators for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Displays left-margin indicators showing command exit status next to
;; shell prompts.  Uses OSC 133 prompt marks with exit codes from the
;; Rust backend.
;;
;; When enabled, a green checkmark (✓) appears next to successful
;; commands (exit code 0) and a red cross (✗) next to failed commands.

;;; Code:

(require 'kuro-config)
(require 'kuro-ffi)

;;; Customization

(defcustom kuro-prompt-status-annotations t
  "When non-nil, show exit-status indicators in the left margin."
  :type 'boolean
  :group 'kuro)

(defcustom kuro-prompt-status-success-indicator "✓"
  "String displayed in the left margin for successful commands (exit 0)."
  :type 'string
  :group 'kuro)

(defcustom kuro-prompt-status-failure-indicator "✗"
  "String displayed in the left margin for failed commands (non-zero exit)."
  :type 'string
  :group 'kuro)

(defcustom kuro-prompt-status-show-extras t
  "When non-nil, render aid/duration/error-path metadata after prompt rows.
Applies to rows that have command-end marks carrying any of those fields.

The data is sourced from OSC 133 \"D\" parameters emitted by shells that
support extended prompt marking (semantic prompt extensions).  When the
shell does not provide the metadata, no extras overlay is created."
  :type 'boolean
  :group 'kuro)

(defcustom kuro-prompt-status-min-duration-ms 0
  "Minimum command duration in milliseconds for the duration annotation to appear.
When a command finishes in less than this many milliseconds, the duration field
is suppressed from the extras overlay, reducing noise for fast commands.
Set to 0 (the default) to always show duration.  For example, setting this
to 2000 suppresses duration annotations for commands that complete in under
two seconds."
  :type 'integer
  :group 'kuro)

;;; Faces

(defface kuro-prompt-success
  '((t :foreground "#00cc00" :weight bold))
  "Face for successful command indicators."
  :group 'kuro)

(defface kuro-prompt-failure
  '((t :foreground "#cc0000" :weight bold))
  "Face for failed command indicators."
  :group 'kuro)

(defface kuro-prompt-extras
  '((t :inherit shadow :slant italic))
  "Face for the OSC 133 D-mark extras annotation appended to the prompt line.
Fields include aid, duration, and error path.
Controlled by `kuro-prompt-status-show-extras'.  Inherits from `shadow'
for subtle styling; rendered via an overlay `after-string'."
  :group 'kuro)

;;; Internal state

(kuro--defvar-permanent-local kuro--prompt-status-overlays nil
  "List of prompt status indicator overlays in this buffer.")

(kuro--defvar-permanent-local kuro--last-exit-code nil
  "Exit code of the most recently completed command (OSC 133), or nil.
Tracked from `command-end' marks regardless of
`kuro-prompt-status-annotations', and rendered by
`kuro-prompt-status-mode-line-segment'.")

;;; Core logic

(defun kuro--prompt-status-indicator (exit-code)
  "Return propertized indicator string for EXIT-CODE, or nil."
  (cond
   ((null exit-code) nil)
   ((= exit-code 0)
    (propertize kuro-prompt-status-success-indicator
                'face 'kuro-prompt-success))
   (t
    (propertize kuro-prompt-status-failure-indicator
                'face 'kuro-prompt-failure))))

(defun kuro--apply-prompt-status-overlay (row indicator)
  "Place INDICATOR string in the left margin at ROW."
  (save-excursion
    (goto-char (point-min))
    (when (zerop (forward-line row))
      (let ((ov (make-overlay (point) (point) nil t nil)))
        (overlay-put ov 'before-string
                     (propertize " " 'display
                                 `((margin left-margin) ,indicator)))
        (overlay-put ov 'kuro-prompt-status t)
        (push ov kuro--prompt-status-overlays)))))

(defun kuro--clear-prompt-status-overlays ()
  "Remove all prompt status overlays from the current buffer."
  (dolist (ov kuro--prompt-status-overlays)
    (when (overlay-buffer ov)
      (delete-overlay ov)))
  (setq kuro--prompt-status-overlays nil))

(defun kuro--format-prompt-duration (duration-ms)
  "Render DURATION-MS (an integer count of milliseconds) as a short string.
<1000 ms -> \"Nms\"; <60000 ms -> \"N.Ns\"; otherwise \"MmSSs\"."
  (cond
   ((null duration-ms) nil)
   ((< duration-ms 1000)
    (format "%dms" duration-ms))
   ((< duration-ms 60000)
    (format "%.1fs" (/ duration-ms 1000.0)))
   (t
    (let* ((total-seconds (/ duration-ms 1000))
           (minutes       (/ total-seconds 60))
           (seconds       (% total-seconds 60)))
      (format "%dm%02ds" minutes seconds)))))

(defconst kuro--prompt-extras-sanitize-regexp
  "[\x00-\x1f\x7f\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069]"
  "Control and bidi-control characters stripped from OSC 133 extras.
The `aid' and `err-path' fields come from untrusted OSC 133 \"D\" marks and
are rendered in an overlay `after-string'.  Stripping ASCII control chars
\(U+0000-U+001F, U+007F) and Unicode bidirectional control characters
\(U+061C, U+200E, U+200F, U+202A-U+202E, U+2066-U+2069) prevents
prompt-line reordering and spoofing, mirroring
`kuro--sanitize-notification-text'.")

(defun kuro--sanitize-prompt-extra (text)
  "Return TEXT with control and bidi-override characters removed, or nil.
TEXT may be nil, in which case nil is returned unchanged."
  (and text
       (replace-regexp-in-string kuro--prompt-extras-sanitize-regexp "" text)))

(defun kuro--format-prompt-extras (aid duration-ms err-path)
  "Build a propertized extras string from AID, DURATION-MS, ERR-PATH.
AID and ERR-PATH are sanitized of control/bidi characters before display,
since they originate from untrusted OSC 133 marks.
Returns nil if all three fields are nil/empty."
  (let ((aid (kuro--sanitize-prompt-extra aid))
        (err-path (kuro--sanitize-prompt-extra err-path))
        parts)
    (when (and aid (not (string-empty-p aid)))
      (push (concat "aid=" aid) parts))
    (when-let* ((dur (kuro--format-prompt-duration duration-ms)))
      (when (>= (or duration-ms 0) kuro-prompt-status-min-duration-ms)
        (push dur parts)))
    (when (and err-path (not (string-empty-p err-path)))
      (push (concat "err=" err-path) parts))
    (when parts
      (propertize (concat " [" (mapconcat #'identity (nreverse parts) " · ") "]")
                  'face 'kuro-prompt-extras))))

(defun kuro--apply-prompt-extras-overlay (row aid duration-ms err-path)
  "Place an end-of-line extras annotation overlay for ROW.
AID, DURATION-MS, and ERR-PATH are forwarded to `kuro--format-prompt-extras'.
The overlay carries `kuro-prompt-status' so it is removed by
`kuro--clear-prompt-status-overlays'."
  (when-let* ((label (kuro--format-prompt-extras aid duration-ms err-path)))
    (save-excursion
      (goto-char (point-min))
      (when (zerop (forward-line row))
        (let* ((eol (line-end-position))
               (ov  (make-overlay eol eol nil t nil)))
          (overlay-put ov 'after-string label)
          (overlay-put ov 'kuro-prompt-status t)
          (overlay-put ov 'kuro-prompt-extras t)
          (push ov kuro--prompt-status-overlays))))))

(defun kuro--update-prompt-status (marks)
  "Update prompt status annotations for the current terminal buffer.
MARKS is a list of (MARK-TYPE ROW COL EXIT-CODE AID DURATION-MS ERR-PATH)
as returned by `kuro--poll-prompt-marks'.  AID, DURATION-MS, and ERR-PATH
are nil when not provided by the shell.  Only processes \"command-end\"
marks.  A trailing rest-pattern preserves backward compatibility with
legacy 4-tuples emitted by older Rust builds."
  (dolist (mark marks)
    (pcase-let ((`(,type ,row ,_col ,exit-code . ,rest) mark))
      (when (equal type "command-end")
        ;; Track the most recent exit code for the mode-line segment,
        ;; independent of whether margin annotations are enabled.
        (when (integerp exit-code)
          (setq kuro--last-exit-code exit-code))
        (when kuro-prompt-status-annotations
          (let ((aid         (nth 0 rest))
                (duration-ms (nth 1 rest))
                (err-path    (nth 2 rest)))
            (when-let* ((indicator (kuro--prompt-status-indicator exit-code)))
              (kuro--apply-prompt-status-overlay row indicator))
            (when (and kuro-prompt-status-show-extras
                       (or aid duration-ms err-path))
              (kuro--apply-prompt-extras-overlay row aid duration-ms err-path))))))))

(defun kuro--ensure-left-margin ()
  "Ensure the left margin is wide enough for status indicators."
  (when (and kuro-prompt-status-annotations
             (or (null left-margin-width) (< left-margin-width 2)))
    (setq left-margin-width 2)
    (when-let* ((win (get-buffer-window)))
      (set-window-margins win 2 (cdr (window-margins win))))))

;;; Mode-line exit-status segment

(defun kuro-prompt-status-mode-line-segment ()
  "Return a mode-line string for the last command's exit status.
Shows the success indicator for exit 0 and the failure indicator plus the
numeric code for a non-zero exit, using the same faces as the margin
annotations.  Returns an empty string when no command has completed yet, so
it is safe to splice unconditionally into `mode-line-format'."
  (cond
   ((not (integerp kuro--last-exit-code)) "")
   ((= kuro--last-exit-code 0)
    (propertize (concat " " kuro-prompt-status-success-indicator)
                'face 'kuro-prompt-success
                'help-echo "Last command succeeded (exit 0)"))
   (t
    (propertize (format " %s%d" kuro-prompt-status-failure-indicator
                        kuro--last-exit-code)
                'face 'kuro-prompt-failure
                'help-echo (format "Last command failed (exit %d)"
                                   kuro--last-exit-code)))))

(defun kuro-prompt-status-install-mode-line ()
  "Splice the exit-status segment into the current buffer's `mode-line-format'.
Idempotent: the `:eval' form is appended only once.  Call this in a kuro
buffer (e.g. from `kuro-mode-hook') to show a shell-prompt-style status
indicator in the mode line."
  (let ((seg '(:eval (kuro-prompt-status-mode-line-segment))))
    (unless (and (listp mode-line-format) (member seg mode-line-format))
      (setq-local mode-line-format
                  (append (if (listp mode-line-format)
                              mode-line-format
                            (list mode-line-format))
                          (list seg))))))

(provide 'kuro-prompt-status)

;;; kuro-prompt-status.el ends here
