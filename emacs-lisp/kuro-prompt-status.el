;;; kuro-prompt-status.el --- Prompt exit-status indicators for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

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

;;; Faces

(defface kuro-prompt-success
  '((t :foreground "#00cc00" :weight bold))
  "Face for successful command indicators."
  :group 'kuro)

(defface kuro-prompt-failure
  '((t :foreground "#cc0000" :weight bold))
  "Face for failed command indicators."
  :group 'kuro)

;;; Internal state

(kuro--defvar-permanent-local kuro--prompt-status-overlays nil
  "List of prompt status indicator overlays in this buffer.")

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

(defun kuro--update-prompt-status (marks)
  "Update prompt status annotations from MARKS.
MARKS is a list of (MARK-TYPE ROW COL EXIT-CODE) as from `kuro--poll-prompt-marks'.
Only processes \"command-end\" marks that have an exit code."
  (when kuro-prompt-status-annotations
    (dolist (mark marks)
      (pcase-let ((`(,type ,row ,_col ,exit-code) mark))
        (when (and (equal type "command-end") exit-code)
          (when-let ((indicator (kuro--prompt-status-indicator exit-code)))
            (kuro--apply-prompt-status-overlay row indicator)))))))

(defun kuro--ensure-left-margin ()
  "Ensure the left margin is wide enough for status indicators."
  (when (and kuro-prompt-status-annotations
             (or (null left-margin-width) (< left-margin-width 2)))
    (setq left-margin-width 2)
    (when-let ((win (get-buffer-window)))
      (set-window-margins win 2 (cdr (window-margins win))))))

(provide 'kuro-prompt-status)

;;; kuro-prompt-status.el ends here
