;;; kuro-activity.el --- Background activity and command-completion notifications -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Watches for activity and command completion events in background Kuro
;; sessions, then surfaces them as desktop or echo-area notifications.
;;
;; # Responsibilities
;;
;; - Command-completion notifications: when an OSC 133 D (command-end) mark
;;   arrives while the kuro buffer is NOT visible and the command took
;;   >= `kuro-activity-notify-threshold' seconds, fire a notification.
;; - Bell escalation: when a BEL arrives in a non-visible buffer, escalate
;;   the visual bell to a desktop notification so the user can react.
;; - Process-exit notification: when the shell exits in a background session
;;   and `kuro-activity-notify-on-exit' is non-nil, notify the user.
;;
;; # Architecture
;;
;; This module hooks into two points in the existing render cycle:
;;   1. `kuro-on-command-complete-functions' (kuro-poll-modes.el): called by
;;      `kuro--poll-prompt-mark-updates' for each OSC 133 command-end mark.
;;   2. `kuro--ring-pending-bell' (kuro-renderer.el): advised to escalate
;;      BEL to desktop notifications when the buffer is invisible.
;;
;; `kuro-activity-mode' is a global minor mode that installs and removes
;; both hooks on enable/disable.

;;; Code:

(require 'kuro-config)
(require 'kuro-poll-modes)
(require 'kuro-prompt-status)
(require 'tabulated-list)

(declare-function kuro--ring-pending-bell "kuro-renderer" ())
(declare-function kuro--default-notify    "kuro-poll-modes" (title body))

;;; Customization

(defgroup kuro-activity nil
  "Background activity monitoring and notifications for Kuro."
  :group 'kuro)

(defcustom kuro-activity-notify-threshold 10.0
  "Minimum command duration in seconds to trigger a background notification.
When an OSC 133 command-end mark arrives with a duration shorter than this
value, no notification is fired even if the kuro buffer is not visible.
Set to nil to disable command-completion notifications entirely."
  :type '(choice (number :tag "Threshold in seconds")
                 (const  :tag "Disabled" nil))
  :group 'kuro-activity)

(defcustom kuro-activity-notify-on-exit t
  "When non-nil, notify when a background kuro session's shell process exits.
The notification is fired only when the kuro buffer is not visible and
`kuro-kill-buffer-on-exit' is nil (otherwise the buffer is already killed)."
  :type 'boolean
  :group 'kuro-activity)

(defcustom kuro-activity-notify-on-bell t
  "When non-nil, escalate BEL from a non-visible kuro buffer to a desktop
notification.  Supplements the standard `ring-bell-function' so the user
sees the alert even when the kuro buffer is in a background window."
  :type 'boolean
  :group 'kuro-activity)

(defcustom kuro-activity-bell-message "Bell"
  "Notification body text used for BEL escalation."
  :type 'string
  :group 'kuro-activity)

(defcustom kuro-activity-log-max-length 200
  "Maximum number of entries in `kuro-activity--log'.
When a new notification is appended and the list grows beyond this
limit, the oldest entries (tail) are discarded.  Set to nil for
unlimited."
  :type '(choice (integer :tag "Maximum entries")
                 (const   :tag "Unlimited" nil))
  :group 'kuro-activity)


;;; Activity log

(defvar kuro-activity--log nil
  "List of logged notification events, newest first.
Each entry is a list (TIME TITLE BODY) where TIME is the result of
`current-time'.  Capped at `kuro-activity-log-max-length' entries.")


;;; Internal: visibility helper

(defsubst kuro--activity-visible-p ()
  "Return non-nil when the current buffer is displayed on any visible frame.
Uses `get-buffer-window' with t (= any frame) to catch multi-frame setups."
  (and (get-buffer-window (current-buffer) t) t))

;;; Internal: notification dispatch

(defun kuro--activity-notify (title body)
  "Log a notification and dispatch it via `kuro-notification-function'.
Always appends (TIME TITLE BODY) to `kuro-activity--log', truncating
to `kuro-activity-log-max-length' when non-nil.  Only dispatches when
`kuro-notifications-enabled' is non-nil.
Defined as `defun' (not `defsubst') so that `let' rebinding of
`kuro-notification-function' in tests reaches this call site."
  (push (list (current-time) title body) kuro-activity--log)
  (when (and kuro-activity-log-max-length
             (> (length kuro-activity--log) kuro-activity-log-max-length))
    (setq kuro-activity--log
          (seq-take kuro-activity--log kuro-activity-log-max-length)))
  (when kuro-notifications-enabled
    (funcall kuro-notification-function title body)))

;;; Core: command-completion handler

(defun kuro--activity-on-command-complete (exit-code duration-ms
                                            _aid _err-path
                                            buffer-visible-p)
  "Notify when a long command finishes in a background kuro session.
Called by `kuro-on-command-complete-functions'.

Fires when ALL conditions hold:
  - BUFFER-VISIBLE-P is nil (buffer is invisible)
  - `kuro-activity-notify-threshold' is non-nil
  - DURATION-MS is non-nil and >= threshold × 1000"
  (when (and (not buffer-visible-p)
             kuro-activity-notify-threshold
             duration-ms
             (>= duration-ms (* kuro-activity-notify-threshold 1000)))
    (let* ((dur    (kuro--format-prompt-duration duration-ms))
           (status (cond ((null exit-code)  "")
                         ((= exit-code 0)   " ✓")
                         (t                 (format " ✗ (exit %d)" exit-code))))
           (body   (format "Finished in %s%s" dur status)))
      (kuro--activity-notify (buffer-name) body))))

;;; Core: bell escalation

(defun kuro--activity-bell-advice (&rest _args)
  "Escalate BEL to a desktop notification when the kuro buffer is invisible.
Installed as `:after' advice on `kuro--ring-pending-bell'."
  (when (and kuro-activity-notify-on-bell
             (not (kuro--activity-visible-p)))
    (kuro--activity-notify (buffer-name) kuro-activity-bell-message)))

;;; Core: process-exit notification

(defun kuro--activity-check-exit ()
  "Notify when the shell exits in a background kuro session.
Installed as `:after' advice on `kuro--check-process-exit'.
Fires only when the buffer is invisible and `kuro-activity-notify-on-exit'
is non-nil.  When `kuro-kill-buffer-on-exit' is set the buffer would
already be killed by `kuro--check-process-exit', so we only fire when
the buffer is still alive."
  (when (and kuro-activity-notify-on-exit
             (not (kuro--activity-visible-p))
             (buffer-live-p (current-buffer)))
    (kuro--activity-notify (buffer-name) "Session ended")))

;;; Minor mode

(define-minor-mode kuro-activity-mode
  "Global minor mode for background activity notifications in Kuro sessions.
When enabled, command completions, BEL events, and process exits that
occur in non-visible kuro buffers produce desktop or echo-area notifications."
  :global t
  :group 'kuro-activity
  (if kuro-activity-mode
      (progn
        (add-hook 'kuro-on-command-complete-functions
                  #'kuro--activity-on-command-complete)
        (advice-add 'kuro--ring-pending-bell :after
                    #'kuro--activity-bell-advice)
        (advice-add 'kuro--check-process-exit :after
                    #'kuro--activity-check-exit))
    (remove-hook 'kuro-on-command-complete-functions
                 #'kuro--activity-on-command-complete)
    (advice-remove 'kuro--ring-pending-bell
                   #'kuro--activity-bell-advice)
    (advice-remove 'kuro--check-process-exit
                   #'kuro--activity-check-exit)))

;;; Activity list buffer

;;;###autoload
(defun kuro-activity-list-delete-entry ()
  "Remove the notification entry at point from `kuro-activity--log'.
Has no effect when point is not on a list entry."
  (interactive)
  (let ((entry (tabulated-list-get-id)))
    (when entry
      (setq kuro-activity--log (delq entry kuro-activity--log))
      (tabulated-list-delete-entry))))

(defvar kuro-activity-list-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "g") #'tabulated-list-revert)
    (define-key map (kbd "d") #'kuro-activity-list-delete-entry)
    (define-key map (kbd "c") #'kuro-activity-clear)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Keymap for `kuro-activity-list-mode'.")

(defconst kuro-activity--list-columns
  [("Time" 10 t) ("Session" 24 t) ("Event" 0 t)]
  "Column definitions for `kuro-activity-list-mode'.")

(defun kuro-activity-list--entries ()
  "Return `tabulated-list-entries' built from `kuro-activity--log'."
  (mapcar (lambda (entry)
            (list entry
                  (vector (format-time-string "%H:%M:%S" (car entry))
                          (or (cadr entry) "")
                          (or (caddr entry) ""))))
          kuro-activity--log))

(defun kuro-activity-list--refresh ()
  "Rebuild the display in a `kuro-activity-list-mode' buffer."
  (setq tabulated-list-entries (kuro-activity-list--entries))
  (tabulated-list-print t))

(define-derived-mode kuro-activity-list-mode tabulated-list-mode
  "Kuro Activity"
  "Major mode for viewing kuro activity notification history.
Entries are drawn from `kuro-activity--log' (newest first).
Use `kuro-activity-clear' to clear the log."
  (setq tabulated-list-format   kuro-activity--list-columns
        tabulated-list-entries  #'kuro-activity-list--entries
        tabulated-list-padding  1)
  (tabulated-list-init-header))

;;;###autoload
(defun kuro-activity-list ()
  "Display a buffer listing all logged kuro activity notifications.
Creates or refreshes the `*kuro-activity*' buffer using
`kuro-activity-list-mode'."
  (interactive)
  (let ((buf (get-buffer-create "*kuro-activity*")))
    (with-current-buffer buf
      (unless (derived-mode-p 'kuro-activity-list-mode)
        (kuro-activity-list-mode))
      (kuro-activity-list--refresh))
    (display-buffer buf)))

;;;###autoload
(defun kuro-activity-clear ()
  "Clear all entries from `kuro-activity--log'.
Also refreshes the `*kuro-activity*' list buffer when it is live."
  (interactive)
  (setq kuro-activity--log nil)
  (let ((buf (get-buffer "*kuro-activity*")))
    (when buf
      (with-current-buffer buf
        (kuro-activity-list--refresh))))
  (message "kuro-activity: log cleared"))


(provide 'kuro-activity)

;;; kuro-activity.el ends here
