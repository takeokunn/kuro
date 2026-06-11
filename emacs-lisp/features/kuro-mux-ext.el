;;; kuro-mux-ext.el --- kuro-mux: pane management, tab-bar, persistence, keymap  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;;; Commentary:

;; Extension module for kuro-mux.el.  Loaded automatically by kuro-mux.el.
;; Provides: pane movement between frames, session naming, tab-bar integration,
;; layout persistence, session monitoring, pipe-pane, prefix keymap, and setup.
;; All functions here depend on kuro-mux.el having been loaded first.

;;; Code:

(declare-function kuro-mux--live-sessions      "kuro-mux" ())
(declare-function kuro-mux--session-display-name "kuro-mux" (buf))
(declare-function kuro-mux--register           "kuro-mux" ())
(declare-function kuro-mux--unregister         "kuro-mux" ())
(declare-function kuro-mux-next-layout         "kuro-mux-layout" ())
(declare-function kuro-mux-previous-layout     "kuro-mux-layout" ())
(declare-function kuro-mux-select-layout       "kuro-mux-layout" (layout))
(declare-function kuro-mux-next                "kuro-mux" ())
(declare-function kuro-mux-prev                "kuro-mux" ())
(declare-function kuro-mux-switch-by-name      "kuro-mux" (name))
(declare-function kuro-mux-other-window        "kuro-mux" ())
(declare-function kuro-mux-rotate-panes        "kuro-mux" (&optional backward))
(declare-function kuro-mux-rotate-panes-backward "kuro-mux" ())
(declare-function kuro-mux-last                "kuro-mux" ())
(declare-function kuro-mux-find-window         "kuro-mux" (name))
(declare-function kuro-mux-select-by-index     "kuro-mux" (n))
(declare-function kuro-mux-split-right         "kuro-mux" (&optional command))
(declare-function kuro-mux-split-below         "kuro-mux" (&optional command))
(declare-function kuro-mux-detach              "kuro-mux" ())
(declare-function kuro-mux-zoom                "kuro-mux" ())
(declare-function kuro-mux-kill                "kuro-mux" ())
(declare-function kuro-mux-swap-pane-forward   "kuro-mux" ())
(declare-function kuro-mux-swap-pane-backward  "kuro-mux" ())
(declare-function kuro-mux-resize-pane         "kuro-mux" (direction &optional delta))
(declare-function kuro-mux-install-mode-line       "kuro-mux"      ())
(declare-function kuro-mux--track-window-change    "kuro-mux"      (_frame))
(declare-function kuro--activity-notify            "kuro-activity" (title body))

;; Forward declarations for buffer-local variables defined in kuro-mux.el.
;; kuro-mux-tab-bar-mode is defined later in this file (define-minor-mode at line ~187).
(defvar kuro-mux-tab-bar-mode)
(defvar kuro-mux-monitor-activity-debounce)
(defvar kuro-mux-mode-line-segment)
(defvar kuro-mux--name)
(defvar kuro-mux--command)
(defvar kuro-mux--directory)
(defvar kuro-mux--monitor-activity)
(defvar kuro-mux--monitor-activity-last-notified)
(defvar kuro-mux--monitor-silence-seconds)
(defvar kuro-mux--monitor-silence-timer)
(defvar kuro-mux--pipe-pane-file)
(defvar kuro-shell)


;;;; Pane movement between frames

;;;###autoload
(defun kuro-mux-break-pane ()
  "Move the current kuro buffer to its own dedicated frame (tmux: break-pane).
The buffer remains live.  When the current window is one of several visible
windows, it is removed from the frame after the new frame is created.
When it is the sole window, the buffer is shown in both frames momentarily;
the caller may close the old frame manually."
  (interactive)
  (unless (derived-mode-p 'kuro-mode)
    (user-error "Not in a Kuro buffer"))
  (let* ((buf        (current-buffer))
         (can-delete (> (length (window-list nil 0)) 1))
         (new-frame  (make-frame)))
    (with-selected-frame new-frame
      (switch-to-buffer buf))
    (when can-delete
      (delete-window))))

;;;###autoload
(defun kuro-mux-join-pane (name)
  "Pull the named kuro session into the current frame as a vertical split.
NAME is the buffer name of a live kuro session.  The session is pulled
into a new window on the right side of the current window (tmux: join-pane).
Use `kuro-mux-break-pane' to perform the reverse operation."
  (interactive
   (list (completing-read "Join session: "
                          (mapcar #'buffer-name (kuro-mux--live-sessions))
                          nil t)))
  (let ((buf (get-buffer name)))
    (unless (buffer-live-p buf)
      (user-error "Session buffer no longer exists: %s" name))
    (let ((new-win (split-window-right)))
      (set-window-buffer new-win buf)
      (select-window new-win))))


;;;; Session naming

;;;###autoload
(defun kuro-mux-rename (name)
  "Rename the current kuro session to NAME.
Updates the mode-line and the tab-bar tab (when `kuro-mux-tab-bar-mode'
is active).  NAME is shown by `kuro-mux-switch-by-name'."
  (interactive "sSession name: ")
  (unless (derived-mode-p 'kuro-mode)
    (user-error "Not in a kuro buffer"))
  (setq kuro-mux--name (if (string-empty-p name) nil name))
  (when kuro-mux-tab-bar-mode
    (kuro-mux--tab-bar-update))
  (force-mode-line-update)
  (message "kuro-mux: session renamed to %s"
           (or kuro-mux--name (buffer-name))))

(defun kuro-mux--name-lighter ()
  "Return a mode-line string for the current session name.
Returns empty string when no name is set."
  (if kuro-mux--name
      (format " {%s}" kuro-mux--name)
    ""))

;;;###autoload
(defun kuro-mux-send-to-session (name text)
  "Send TEXT to the kuro session named NAME.
Interactively, prompts for a session name (with completion) and for
the text to send.  TEXT is delivered via `kuro--send-paste-or-raw'
in the target buffer, which applies bracketed-paste wrapping when
the session has that terminal mode active.
Signals `user-error' when no session matching NAME is found."
  (interactive
   (list (completing-read "Kuro session: "
                          (mapcar #'kuro-mux--session-display-name
                                  (kuro-mux--live-sessions))
                          nil t)
         (read-string "Send text: ")))
  (let ((target (seq-find (lambda (buf)
                            (string= (kuro-mux--session-display-name buf) name))
                          (kuro-mux--live-sessions))))
    (if target
        (with-current-buffer target
          (kuro--send-paste-or-raw text))
      (user-error "kuro-mux: no session named %s" name))))


;;;; Tab-bar integration

(defun kuro-mux--tab-bar-update ()
  "Rebuild the tab-bar tab list to reflect the current session registry.
Each live kuro session gets one tab named by `kuro-mux--session-display-name'.
Existing non-kuro tabs are preserved at their current positions."
  (when (and (fboundp 'tab-bar-tabs) (fboundp 'tab-bar-select-tab-by-name))
    ;; Ensure tab-bar-mode is on
    (tab-bar-mode 1)
    ;; For each session without a corresponding tab, create one
    (dolist (buf (kuro-mux--live-sessions))
      (let* ((name (kuro-mux--session-display-name buf))
             (existing (seq-find (lambda (tab)
                                   (string= (alist-get 'name tab) name))
                                 (tab-bar-tabs))))
        (unless existing
          (tab-bar-new-tab)
          (with-current-buffer buf
            (switch-to-buffer buf))
          ;; Rename the new tab
          (when (fboundp 'tab-bar-rename-tab)
            (tab-bar-rename-tab name)))))))

(defun kuro-mux--on-session-created ()
  "Hook function: register new session and update tab-bar if enabled."
  (kuro-mux--register)
  (when kuro-mux-tab-bar-mode
    (kuro-mux--tab-bar-update)))

(defun kuro-mux--on-session-killed ()
  "Hook function: unregister session and update tab-bar if enabled."
  (kuro-mux--unregister))

(defun kuro-mux--install-hooks ()
  "Install kuro-mux lifecycle hooks."
  (add-hook 'kuro-mode-hook #'kuro-mux--on-session-created)
  (add-hook 'kill-buffer-hook #'kuro-mux--on-session-killed)
  (add-hook 'window-selection-change-functions #'kuro-mux--track-window-change)
  (add-hook 'kill-emacs-hook #'kuro-mux--auto-save-on-exit))

(defun kuro-mux--uninstall-hooks ()
  "Remove kuro-mux lifecycle hooks."
  (remove-hook 'kuro-mode-hook #'kuro-mux--on-session-created)
  (remove-hook 'kill-buffer-hook #'kuro-mux--on-session-killed)
  (remove-hook 'window-selection-change-functions #'kuro-mux--track-window-change)
  (remove-hook 'kill-emacs-hook #'kuro-mux--auto-save-on-exit))

;;;###autoload
(define-minor-mode kuro-mux-tab-bar-mode
  "Global minor mode that syncs kuro sessions with tab-bar tabs.
When enabled, each new kuro session automatically gets a tab-bar tab,
and closing a session removes its tab.  `tab-bar-mode' is activated
automatically when the first kuro tab is created."
  :global t
  :group 'kuro
  (if kuro-mux-tab-bar-mode
      (progn
        (kuro-mux--install-hooks)
        ;; Reflect already-open sessions in tab-bar
        (when (kuro-mux--live-sessions)
          (kuro-mux--tab-bar-update)))
    (kuro-mux--uninstall-hooks)))


;;;; Layout persistence

(defcustom kuro-mux-layout-file
  (expand-file-name "kuro-mux-layout.el" user-emacs-directory)
  "File path for saving and restoring the kuro-mux session layout.
The file is an Emacs Lisp sexp — do not edit by hand."
  :type 'file
  :group 'kuro)

(defcustom kuro-mux-auto-save-layout nil
  "When non-nil, automatically save the kuro session layout when Emacs exits.
`kuro-mux-save-layout' is called from `kill-emacs-hook' when this is set.
The layout is written to `kuro-mux-layout-file' and can be restored with
`kuro-mux-restore-layout' on the next Emacs startup."
  :type 'boolean
  :group 'kuro)

(defun kuro-mux--auto-save-on-exit ()
  "Save the kuro session layout on Emacs exit if auto-save is enabled.
Called from `kill-emacs-hook'.  No-op when `kuro-mux-auto-save-layout' is nil
or when there are no live sessions to persist."
  (when (and kuro-mux-auto-save-layout (kuro-mux--live-sessions))
    (kuro-mux-save-layout)))

;;;; Session monitoring (activity + silence)

(defun kuro-mux--activity-watcher (_beg _end _old-len)
  "Called from `after-change-functions' to detect output in monitored sessions.
Fires a notification when the buffer is not currently visible and at least
`kuro-mux-monitor-activity-debounce' seconds have elapsed since the last one."
  (when (and kuro-mux--monitor-activity
             (not (get-buffer-window (current-buffer) 'visible))
             (> (float-time)
                (+ kuro-mux--monitor-activity-last-notified
                   kuro-mux-monitor-activity-debounce)))
    (setq kuro-mux--monitor-activity-last-notified (float-time))
    (kuro--activity-notify
     (format "Activity: %s" (buffer-name))
     "Session produced output while hidden")))

(defun kuro-mux--silence-watcher (_beg _end _old-len)
  "Called from `after-change-functions' to reset the silence countdown.
Cancels any pending silence timer and schedules a new one for
`kuro-mux--monitor-silence-seconds' seconds in the future."
  (when kuro-mux--monitor-silence-seconds
    (when (timerp kuro-mux--monitor-silence-timer)
      (cancel-timer kuro-mux--monitor-silence-timer))
    (let ((buf (current-buffer))
          (sec kuro-mux--monitor-silence-seconds))
      (setq kuro-mux--monitor-silence-timer
            (run-with-timer sec nil
              (lambda ()
                (when (buffer-live-p buf)
                  (with-current-buffer buf
                    (kuro--activity-notify
                     (format "Silence: %s" (buffer-name))
                     (format "No output for %gs" sec))))))))))

;;;###autoload
(defun kuro-mux-monitor-activity-toggle ()
  "Toggle activity monitoring for the current kuro session.
When enabled, a notification fires via `kuro--activity-notify' the first
time new output arrives while the buffer is not displayed in any visible
frame.  Subsequent notifications are throttled by
`kuro-mux-monitor-activity-debounce'.
Analogous to tmux `:monitor-activity on/off'."
  (interactive)
  (unless (derived-mode-p 'kuro-mode)
    (user-error "Not in a Kuro buffer"))
  (setq kuro-mux--monitor-activity (not kuro-mux--monitor-activity))
  (if kuro-mux--monitor-activity
      (progn
        (add-hook 'after-change-functions #'kuro-mux--activity-watcher nil t)
        (message "kuro-mux: activity monitoring ON for %s" (buffer-name)))
    (remove-hook 'after-change-functions #'kuro-mux--activity-watcher t)
    (message "kuro-mux: activity monitoring OFF for %s" (buffer-name))))

;;;###autoload
(defun kuro-mux-monitor-silence (seconds)
  "Monitor the current kuro session for silence longer than SECONDS.
A notification fires via `kuro--activity-notify' when the session produces
no output for SECONDS consecutive seconds.  The timer is reset on every
new output event.  Pass 0 to disable silence monitoring for this session.
Analogous to tmux `:monitor-silence N'."
  (interactive "nMonitor silence after (seconds, 0=off): ")
  (unless (derived-mode-p 'kuro-mode)
    (user-error "Not in a Kuro buffer"))
  (setq kuro-mux--monitor-silence-seconds (and (> seconds 0) seconds))
  (if kuro-mux--monitor-silence-seconds
      (progn
        (add-hook 'after-change-functions #'kuro-mux--silence-watcher nil t)
        (message "kuro-mux: silence monitoring ON (%gs) for %s"
                 seconds (buffer-name)))
    (when (timerp kuro-mux--monitor-silence-timer)
      (cancel-timer kuro-mux--monitor-silence-timer)
      (setq kuro-mux--monitor-silence-timer nil))
    (remove-hook 'after-change-functions #'kuro-mux--silence-watcher t)
    (message "kuro-mux: silence monitoring OFF for %s" (buffer-name))))


;;;; Pipe pane — capture rendered session output to a file

(defun kuro-mux--pipe-pane-watcher (beg end _old-len)
  "Append newly inserted buffer text to `kuro-mux--pipe-pane-file'.
Called from `after-change-functions' when output piping is active."
  (when (and kuro-mux--pipe-pane-file (< beg end))
    (let ((text (buffer-substring-no-properties beg end)))
      (condition-case err
          (write-region text nil kuro-mux--pipe-pane-file t 'silent)
        (error
         (message "kuro-mux pipe-pane error: %s" (error-message-string err))
         (setq kuro-mux--pipe-pane-file nil)
         (remove-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher t))))))

(defun kuro-mux-pipe-pane (file)
  "Toggle piping of this session's rendered output to FILE (tmux: pipe-pane).
When output is already being piped, stop it (pass nil interactively).
Otherwise prompt for FILE and start appending rendered text to it.
Bound to `P' in the mux prefix map."
  (interactive
   (if kuro-mux--pipe-pane-file
       (list nil)
     (list (read-file-name "Pipe output to file: "))))
  (unless (derived-mode-p 'kuro-mode)
    (user-error "Not in a Kuro buffer"))
  (if (null file)
      (progn
        (setq kuro-mux--pipe-pane-file nil)
        (remove-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher t)
        (message "kuro-mux: pipe-pane stopped for %s" (buffer-name)))
    (setq kuro-mux--pipe-pane-file (expand-file-name file))
    (add-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher nil t)
    (message "kuro-mux: piping %s → %s" (buffer-name) kuro-mux--pipe-pane-file)))


(defun kuro-mux--session-spec (buf)
  "Return a layout spec plist for kuro buffer BUF.
Returns nil if BUF is not a live kuro buffer."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (list :name      (or kuro-mux--name (buffer-name))
            :command   (or kuro-mux--command kuro-shell)
            :directory (or kuro-mux--directory default-directory)))))

;;;###autoload
(defun kuro-mux-save-layout ()
  "Save the current kuro session layout to `kuro-mux-layout-file'.
The layout records the name, command, and working directory of each
live session.  The PTY state (scrollback, terminal modes) is NOT saved.
Use `kuro-mux-restore-layout' to recreate the sessions after an Emacs
restart."
  (interactive)
  (let* ((sessions (kuro-mux--live-sessions))
         (specs    (delq nil (mapcar #'kuro-mux--session-spec sessions))))
    (with-temp-file kuro-mux-layout-file
      (insert ";; kuro-mux layout — auto-generated by kuro-mux-save-layout\n")
      (insert ";; Restore with M-x kuro-mux-restore-layout\n")
      (pp `(kuro-mux-layout ,@specs) (current-buffer)))
    (message "kuro-mux: layout saved (%d session%s) → %s"
             (length specs)
             (if (= (length specs) 1) "" "s")
             kuro-mux-layout-file)))

(defun kuro-mux--read-layout-file ()
  "Read and return the layout sexp from `kuro-mux-layout-file'.
Returns nil if the file does not exist or cannot be parsed."
  (when (file-readable-p kuro-mux-layout-file)
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents kuro-mux-layout-file)
          (goto-char (point-min))
          (read (current-buffer)))
      (error nil))))

(defun kuro-mux--restore-session (spec)
  "Recreate a single kuro session from layout SPEC plist.
SPEC must have :command and optionally :name and :directory.
Calls `kuro-mux--register' explicitly after creation so the session
appears in the registry even when lifecycle hooks are not installed."
  (let* ((cmd  (plist-get spec :command))
         (name (plist-get spec :name))
         (dir  (plist-get spec :directory))
         (default-directory (or (and dir (file-directory-p dir) dir)
                                default-directory)))
    (kuro-create cmd)
    ;; kuro-create switches to the new buffer; annotate and register now
    (when (derived-mode-p 'kuro-mode)
      (setq kuro-mux--command cmd)
      (setq kuro-mux--directory (or dir default-directory))
      (when name
        (setq kuro-mux--name name))
      ;; Ensure registration regardless of whether kuro-mode-hook fired
      (kuro-mux--register))))

;;;###autoload
(defun kuro-mux-restore-layout ()
  "Recreate kuro sessions from the saved layout in `kuro-mux-layout-file'.
Each session is restarted with its saved command and working directory.
Terminal content (scrollback, history) is not restored — only the
session structure is recreated.
Signals `user-error' if the layout file does not exist."
  (interactive)
  (let ((layout (kuro-mux--read-layout-file)))
    (unless layout
      (user-error "kuro-mux: no layout file found at %s"
                  kuro-mux-layout-file))
    ;; layout = (kuro-mux-layout :name N :command C :directory D ...)
    (unless (eq (car layout) 'kuro-mux-layout)
      (user-error "kuro-mux: invalid layout file format"))
    (let* ((raw   (cdr layout))
           (specs (kuro-mux--parse-layout-plists raw)))
      (dolist (spec specs)
        (kuro-mux--restore-session spec))
      (message "kuro-mux: restored %d session%s from %s"
               (length specs)
               (if (= (length specs) 1) "" "s")
               kuro-mux-layout-file))))

(defun kuro-mux--parse-layout-plists (raw)
  "Parse RAW (the cdr of a kuro-mux-layout sexp) into a list of session plists.
RAW is a list of plists, each with :name, :command, and :directory keys,
as written by `kuro-mux-save-layout' via `pp'.  Invalid entries (non-list
or missing :command) are silently dropped."
  (seq-filter (lambda (spec)
                (and (listp spec) (plist-member spec :command)))
              raw))

;;;; Prefix keymap (tmux-style)

(defconst kuro-mux--prefix-bindings
  '(("n"     . kuro-mux-next)                  ("p"     . kuro-mux-prev)
    ("s"     . kuro-mux-switch-by-name)         ("L"     . kuro-mux-last)
    ("o"     . kuro-mux-other-window)           ("C-o"   . kuro-mux-rotate-panes)
    ("M-o"   . kuro-mux-rotate-panes-backward)  ("f"     . kuro-mux-find-window)
    ("%"     . kuro-mux-split-right)            ("\""    . kuro-mux-split-below)
    ("c"     . kuro-mux-create)                 (","     . kuro-mux-rename)
    ("$"     . kuro-mux-rename)                 ("d"     . kuro-mux-detach)
    ("z"     . kuro-mux-zoom)                   ("&"     . kuro-mux-kill)
    ("S"     . kuro-mux-save-layout)            ("R"     . kuro-mux-restore-layout)
    ("SPC"   . kuro-mux-next-layout)            ("M-SPC" . kuro-mux-select-layout)
    ("M-{"   . kuro-mux-previous-layout)        ("M-}"   . kuro-mux-next-layout)
    ("{"     . kuro-mux-swap-pane-backward)     ("}"     . kuro-mux-swap-pane-forward)
    ("!"     . kuro-mux-break-pane)             ("@"     . kuro-mux-join-pane)
    ("["     . kuro-copy-mode)                  ("/"     . kuro-search-forward)
    ("t"     . kuro-mux-clock)                  ("x"     . kuro-mux-send-to-session)
    ("B"     . kuro-mux-broadcast-toggle)       ("P"     . kuro-mux-pipe-pane)
    ("m"     . kuro-mux-monitor-activity-toggle) ("M"    . kuro-mux-monitor-silence)
    ("w"     . kuro-list-sessions)              ("?"     . kuro-mux-help))
  "Simple key→command binding table for `kuro-mux-prefix-map'.")

(defconst kuro-mux--prefix-resize-bindings
  '(("<up>" up 2) ("<down>" down 2) ("<left>" left 5) ("<right>" right 5))
  "Arrow resize entries (key direction delta) for `kuro-mux-prefix-map'.")

(defvar kuro-mux-prefix-map
  (let ((map (make-sparse-keymap)))
    (dolist (b kuro-mux--prefix-bindings)
      (define-key map (kbd (car b)) (cdr b)))
    (dotimes (i 9)
      (let ((n (1+ i)))
        (define-key map (kbd (number-to-string n))
          (lambda () (interactive) (kuro-mux-select-by-index n)))))
    (dolist (b kuro-mux--prefix-resize-bindings)
      (let ((key (car b)) (dir (cadr b)) (delta (caddr b)))
        (define-key map (kbd key)
          (lambda () (interactive) (kuro-mux-resize-pane dir delta)))))
    map)
  "Prefix keymap for kuro-mux multiplexer commands.
Bound under `kuro-mux-prefix-key' by `kuro-mux-install-keys'.
See `kuro-mux--prefix-bindings' for the full command table.")

(defcustom kuro-mux-prefix-key "C-c m"
  "Key sequence (a `kbd' string) under which `kuro-mux-prefix-map' is bound.
Used by `kuro-mux-install-keys'.  The default \"C-c m\" coexists with the
existing kuro-mode `C-c C-x' terminal bindings because the prefix uses a
plain letter, not a control character, after C-c.
Changing this after `kuro-mux-install-keys' has run requires re-running it."
  :type 'string
  :group 'kuro)

;;;###autoload
(defun kuro-mux-create (&optional command)
  "Create a new kuro session in the current window.
COMMAND defaults to `kuro-shell'.  Provided as a mux-prefix-friendly
wrapper around `kuro-create' so the prefix map has a `c' (create)
binding analogous to tmux."
  (interactive)
  (kuro-create (or command kuro-shell)))

;;;###autoload
(defun kuro-mux-install-keys (&optional keymap)
  "Bind `kuro-mux-prefix-map' under `kuro-mux-prefix-key' in KEYMAP.
KEYMAP defaults to `kuro-mode-map' so the multiplexer prefix is available
in every kuro terminal buffer.  Call this once after loading kuro, e.g.
from `kuro-mux-setup' or your init file.  Returns the keymap modified."
  (let ((map (or keymap (and (boundp 'kuro-mode-map) kuro-mode-map))))
    (unless (keymapp map)
      (user-error "kuro-mux-install-keys: no valid keymap to bind into"))
    (define-key map (kbd kuro-mux-prefix-key) kuro-mux-prefix-map)
    map))


;;;; Help

;;;###autoload
(defun kuro-mux-help ()
  "Show a help buffer listing all kuro-mux prefix keymap bindings.
Displays the formatted contents of `kuro-mux-prefix-map' and the
configured `kuro-mux-prefix-key' via `with-help-window'."
  (interactive)
  (with-help-window "*kuro-mux help*"
    (princ (format "kuro-mux prefix key: %s\n\n" kuro-mux-prefix-key))
    (princ "Available commands:\n\n")
    (princ (substitute-command-keys "\\{kuro-mux-prefix-map}"))))

;;;###autoload
(defun kuro-mux-clock ()
  "Display the current time in the echo area.
Analogous to tmux's clock mode (prefix + t)."
  (interactive)
  (message "kuro-mux: %s" (format-time-string "%H:%M:%S")))


;;;; Broadcast (synchronized panes)

(defvar kuro-mux--broadcast-mode nil
  "When non-nil, PTY input is replicated to all live kuro sessions.
Toggle interactively with `kuro-mux-broadcast-toggle' (prefix key + B).
Analogous to tmux's `:setw synchronize-panes on'.")

(defvar kuro-mux--broadcasting nil
  "Non-nil while `kuro-mux--broadcast-send' is iterating sessions.
Prevents re-entrant advice calls from causing infinite recursion when
broadcasting triggers another `kuro--send-paste-or-raw' in a target buffer.")

(defun kuro-mux--broadcast-send (text)
  "Replicate TEXT to all live kuro sessions except the current buffer.
Installed as :after advice on `kuro--send-paste-or-raw'.  Has no effect
when `kuro-mux--broadcast-mode' is nil or a broadcast is already in
progress (`kuro-mux--broadcasting' non-nil)."
  (when (and kuro-mux--broadcast-mode (not kuro-mux--broadcasting))
    (let ((kuro-mux--broadcasting t)
          (origin (current-buffer)))
      (dolist (buf (kuro-mux--live-sessions))
        (unless (eq buf origin)
          (with-current-buffer buf
            (kuro--send-paste-or-raw text)))))))

;;;###autoload
(defun kuro-mux-broadcast-toggle ()
  "Toggle broadcast mode: replicate PTY input to all live kuro sessions.
When enabled, every keystroke sent to any kuro buffer is mirrored to all
other live kuro sessions — useful for running the same command on multiple
servers simultaneously.  Analogous to tmux `:setw synchronize-panes'."
  (interactive)
  (setq kuro-mux--broadcast-mode (not kuro-mux--broadcast-mode))
  (message "kuro-mux broadcast: %s"
           (if kuro-mux--broadcast-mode "ON — input shared across all sessions"
             "OFF")))

;; Install relay at load time; the guard inside kuro-mux--broadcast-send
;; ensures it is a no-op (two variable reads) unless broadcast mode is on.
(advice-add 'kuro--send-paste-or-raw :after #'kuro-mux--broadcast-send)


;;;; Setup

(defcustom kuro-mux-install-prefix-keys t
  "When non-nil, `kuro-mux-setup' installs the mux prefix keymap.
Binds `kuro-mux-prefix-map' under `kuro-mux-prefix-key' in `kuro-mode-map'.
Set to nil if you prefer to bind multiplexer commands manually."
  :type 'boolean
  :group 'kuro)

(defun kuro-mux-setup ()
  "Activate kuro-mux: install lifecycle hooks and (optionally) prefix keys.
Call this once in your init file after loading kuro.
Installs the tmux-style prefix keymap when `kuro-mux-install-prefix-keys'
is non-nil.  With `kuro-mux-tab-bar-mode' enabled, also syncs sessions to
tab-bar tabs."
  (kuro-mux--install-hooks)
  (when (and kuro-mux-install-prefix-keys
             (boundp 'kuro-mode-map)
             (keymapp kuro-mode-map))
    (kuro-mux-install-keys))
  (when kuro-mux-mode-line-segment
    (kuro-mux-install-mode-line)))


(provide 'kuro-mux-ext)
;;; kuro-mux-ext.el ends here
