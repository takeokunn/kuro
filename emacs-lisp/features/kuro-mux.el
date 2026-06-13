;;; kuro-mux.el --- Lightweight terminal multiplexer for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Provides a lightweight Emacs-native terminal multiplexer built on top
;; of kuro's session model.  It syncs with Emacs' window-configuration
;; and tab-bar-mode so multiple terminal sessions feel like first-class
;; Emacs citizens.
;;
;; # Features
;;
;; Buffer registry and navigation:
;;   `kuro-mux-next'            — cycle to the next live kuro buffer
;;   `kuro-mux-prev'            — cycle to the previous live kuro buffer
;;   `kuro-mux-switch-by-name'  — switch to a session by name (completing-read)
;;
;; Pane splitting:
;;   `kuro-mux-split-right'  — split right, open a new kuro terminal
;;   `kuro-mux-split-below'  — split below, open a new kuro terminal
;;
;; Window management:
;;   `kuro-mux-detach'  — close current window, buffer and PTY remain alive
;;   `kuro-mux-zoom'    — toggle maximizing the current kuro window
;;   `kuro-mux-kill'    — kill the current kuro session (buffer + PTY)
;;
;; Session naming:
;;   `kuro-mux-rename'  — assign a human-readable name shown in the mode-line
;;
;; Tab-bar sync (requires tab-bar-mode):
;;   `kuro-mux-tab-bar-mode'  — global minor mode that auto-creates/removes
;;                               tab-bar tabs to mirror the session registry
;;
;; Layout persistence:
;;   `kuro-mux-save-layout'    — save session names + commands to disk
;;   `kuro-mux-restore-layout' — recreate sessions from a saved layout file
;;
;; # Architecture
;;
;; `kuro-mux--sessions' is a buffer-ordered list of live kuro buffers.
;; It is maintained by hooks installed on `kuro-mode-hook' and
;; `kill-buffer-hook'.  Session order is creation order (newest last).
;;
;; Layout files are plain Emacs Lisp sexp files.  They store the session
;; name, command, and working directory for each session so the layout can
;; be recreated after an Emacs restart (PTY state is not serialized).

;;; Code:

(require 'kuro-config)

(declare-function kuro-create             "kuro-lifecycle"  (&optional command buffer-name))
(declare-function derived-mode-p          "subr"            (&rest modes))
(declare-function kuro-copy-mode          "kuro"            ())
(declare-function kuro-search-forward     "kuro"            ())
(declare-function kuro--send-paste-or-raw "kuro-input-paste" (text))
(declare-function kuro-list-sessions      "kuro-sessions"    ())

(defvar kuro-shell nil "Forward ref; defcustom in kuro-config.el.")


;;;; Registry

(defvar kuro-mux--sessions nil
  "Ordered list of live `kuro-mode' buffers managed by kuro-mux.
Maintained by `kuro-mux--register' and `kuro-mux--unregister'.
Order is creation order (oldest first, newest last).")

(defvar kuro-mux--zoom-config nil
  "Saved window configuration for `kuro-mux-zoom' toggle.
Non-nil when a zoom is in effect; `kuro-mux-zoom' restores this
configuration and clears it.  Stored as a frame-level global because
only one zoomed window configuration exists per frame at a time.")

(kuro--defvar-permanent-local kuro-mux--name nil
  "Human-readable name for this kuro session.
Used in the mode-line lighter and by `kuro-mux-switch-by-name'.
Set via `kuro-mux-rename'.")

(kuro--defvar-permanent-local kuro-mux--command nil
  "Shell command that launched this kuro session.
Stored for layout persistence so the session can be recreated.")

(kuro--defvar-permanent-local kuro-mux--directory nil
  "Working directory at session creation time.
Stored for layout persistence.")

(defvar-local kuro-mux--monitor-activity nil
  "When non-nil, fire notifications when this session produces output off-screen.")

(defvar-local kuro-mux--monitor-activity-last-notified 0
  "Float-time of the last activity notification dispatched for this buffer.")

(defvar-local kuro-mux--monitor-silence-seconds nil
  "Seconds of silence before a silence notification fires, or nil when disabled.")

(defvar-local kuro-mux--monitor-silence-timer nil
  "Active countdown timer for silence monitoring in this buffer, or nil.")

(defvar-local kuro-mux--pipe-pane-file nil
  "Absolute path of the file currently receiving piped output.
Nil when no pipe-pane capture is active for this buffer.")

(defcustom kuro-mux-monitor-activity-debounce 2.0
  "Minimum seconds between activity notifications for a monitored session.
Prevents notification floods when a session produces continuous rapid output."
  :type 'number
  :group 'kuro)

(defun kuro-mux--register ()
  "Add the current buffer to `kuro-mux--sessions' if it is a kuro buffer.
Called from `kuro-mode-hook'."
  (when (derived-mode-p 'kuro-mode)
    (unless (memq (current-buffer) kuro-mux--sessions)
      (setq kuro-mux--sessions
            (append kuro-mux--sessions (list (current-buffer)))))
    (setq kuro-mux--directory default-directory)))

(defun kuro-mux--unregister ()
  "Remove the current buffer from `kuro-mux--sessions'.
Called from `kill-buffer-hook'."
  (setq kuro-mux--sessions
        (delq (current-buffer) kuro-mux--sessions)))

(defun kuro-mux--live-sessions ()
  "Return the list of live kuro-mode buffers, pruning any dead ones."
  (setq kuro-mux--sessions
        (seq-filter #'buffer-live-p kuro-mux--sessions))
  kuro-mux--sessions)

(defun kuro-mux--session-display-name (buf)
  "Return a display name for kuro buffer BUF.
Prefers `kuro-mux--name' when set, falls back to the buffer name."
  (with-current-buffer buf
    (or kuro-mux--name (buffer-name))))


;;;; Navigation

(defun kuro-mux--next-buffer (buf sessions)
  "Return the buffer after BUF in SESSIONS, wrapping around."
  (let ((rest (cdr (memq buf sessions))))
    (or (car rest) (car sessions))))

(defun kuro-mux--prev-buffer (buf sessions)
  "Return the buffer before BUF in SESSIONS, wrapping around."
  (kuro-mux--next-buffer buf (reverse sessions)))

(defmacro kuro--def-mux-nav (name nav-fn docstring)
  "Define a kuro-mux session cycle command.
NAV-FN is called with (current-buffer sessions) to pick the target buffer."
  `(defun ,name ()
     ,docstring
     (interactive)
     (let ((sessions (kuro-mux--live-sessions)))
       (cond
        ((null sessions)       (message "kuro-mux: no active sessions"))
        ((null (cdr sessions)) (switch-to-buffer (car sessions)))
        (t                     (switch-to-buffer
                                (,nav-fn (current-buffer) sessions)))))))

;;;###autoload
(kuro--def-mux-nav kuro-mux-next kuro-mux--next-buffer
  "Switch to the next live kuro buffer in creation order, wrapping around.")

;;;###autoload
(kuro--def-mux-nav kuro-mux-prev kuro-mux--prev-buffer
  "Switch to the previous live kuro buffer in creation order, wrapping around.")

;;;###autoload
(defun kuro-mux-switch-by-name (name)
  "Switch to the kuro session named NAME.
With prefix argument or when called interactively, use `completing-read'."
  (interactive
   (list (completing-read
          "Kuro session: "
          (mapcar #'kuro-mux--session-display-name
                  (kuro-mux--live-sessions))
          nil t)))
  (let ((target (seq-find
                 (lambda (buf)
                   (string= (kuro-mux--session-display-name buf) name))
                 (kuro-mux--live-sessions))))
    (if target
        (switch-to-buffer target)
      (message "kuro-mux: no session named %s" name))))

(defun kuro-mux--session-index ()
  "Return the 1-indexed position of the current buffer in the session registry.
Returns nil when the current buffer is not registered with kuro-mux."
  (when-let ((pos (seq-position (kuro-mux--live-sessions) (current-buffer))))
    (1+ pos)))

(defun kuro-mux--mode-line-segment ()
  "Return a mode-line string showing the current session's index as [N/M].
Returns an empty string when the buffer is not in the kuro-mux registry."
  (if-let ((idx   (kuro-mux--session-index))
           (total (length (kuro-mux--live-sessions))))
      (format " [%d/%d]" idx total)
    ""))

(defcustom kuro-mux-mode-line-segment t
  "When non-nil, `kuro-mux-setup' appends a session-index segment to the mode-line.
The segment shows \" [N/M]\" in each kuro buffer where N is the 1-indexed
session slot and M is the total number of live sessions."
  :type 'boolean
  :group 'kuro)

(defun kuro-mux--buffer-mode-line-setup ()
  "Append the kuro-mux session-index segment to this buffer's mode-line-format.
Idempotent: repeated calls do not add duplicate segments."
  (make-local-variable 'mode-line-format)
  (let ((seg '(:eval (kuro-mux--mode-line-segment))))
    (unless (member seg mode-line-format)
      (setq mode-line-format (append mode-line-format (list seg))))))

(defun kuro-mux-install-mode-line ()
  "Install the kuro-mux mode-line segment into all current and future kuro buffers.
Adds `kuro-mux--buffer-mode-line-setup' to `kuro-mode-hook' and calls it
immediately on every already-live kuro session."
  (add-hook 'kuro-mode-hook #'kuro-mux--buffer-mode-line-setup)
  (dolist (buf (kuro-mux--live-sessions))
    (with-current-buffer buf
      (kuro-mux--buffer-mode-line-setup))))

;;;###autoload
(defun kuro-mux-other-window ()
  "Switch focus to the next visible window displaying a kuro buffer.
Cycles through windows on the selected frame that show a kuro-mode buffer,
in `next-window' order.  Analogous to tmux prefix + o (next pane)."
  (interactive)
  (let* ((kuro-wins (kuro-mux--visible-windows))
         (next (cadr (memq (selected-window) kuro-wins))))
    (cond
     ((length< kuro-wins 1)
      (user-error "kuro-mux: no visible kuro panes"))
     ((length< kuro-wins 2)
      (user-error "kuro-mux: only one visible kuro pane"))
     (t
      (select-window (or next (car kuro-wins)))))))

(defun kuro-mux--visible-windows ()
  "Return the live windows on the selected frame that show a kuro buffer.
Order follows `window-list' (top-to-bottom, then left-to-right)."
  (seq-filter
   (lambda (w)
     (with-current-buffer (window-buffer w)
       (derived-mode-p 'kuro-mode)))
   (window-list nil 'no-minibuf)))

;;;###autoload
(defun kuro-mux-rotate-panes (&optional backward)
  "Rotate kuro buffers through the visible window positions (tmux: C-o).
Window geometry stays fixed; each window adopts a neighbour's buffer,
cycling around so no buffer is lost.  Forward rotation shifts every buffer
to the next window (the last wraps to the first); with BACKWARD non-nil —
or any prefix argument — it rotates the other way.  Signals `user-error'
when fewer than two kuro panes are visible."
  (interactive "P")
  (let* ((wins (kuro-mux--visible-windows))
         (n    (length wins)))
    (when (< n 2)
      (user-error "kuro-mux: need at least two visible kuro panes to rotate"))
    (let* ((bufs (mapcar #'window-buffer wins))
           ;; Forward = right-shift the buffer list onto the windows:
           ;; window[i] shows what window[i-1] showed, window[0] takes the last.
           (rot  (if backward
                     (append (cdr bufs) (list (car bufs)))
                   (cons (car (last bufs)) (butlast bufs))))
           (ws wins)
           (bs rot))
      (while ws
        (set-window-buffer (car ws) (car bs))
        (setq ws (cdr ws) bs (cdr bs)))
      (select-window (car wins)))))

;;;###autoload
(defun kuro-mux-rotate-panes-backward ()
  "Rotate kuro buffers through window positions in reverse (tmux: M-o).
Equivalent to `kuro-mux-rotate-panes' with a prefix argument."
  (interactive)
  (kuro-mux-rotate-panes t))

;;;###autoload
(defun kuro-mux-select-by-index (n)
  "Switch to the Nth kuro session (1-indexed).
Sessions are ordered by `kuro-mux--live-sessions' (creation order, oldest
first).  Index 1 is the oldest session; 0 selects the tenth.  Signals
`user-error' when N is out of range."
  (interactive "nKuro session index: ")
  (let* ((idx      (if (= n 0) 9 (1- n)))
         (sessions (kuro-mux--live-sessions))
         (target   (nth idx sessions)))
    (if target
        (switch-to-buffer target)
      (user-error "kuro-mux: no session at index %d (have %d)"
                  (if (= n 0) 10 n)
                  (length sessions)))))


;;;; Last session

(defvar kuro-mux--last-session nil
  "The most recently deselected kuro buffer, for `kuro-mux-last'.
Set by `kuro-mux--track-window-change' via `window-selection-change-functions'.")

(defun kuro-mux--track-window-change (_frame)
  "Record the previously focused kuro buffer when window selection changes.
Added to `window-selection-change-functions' by `kuro-mux--install-hooks'.
Uses `old-selected-window', which is only valid inside this hook."
  (let ((old (old-selected-window)))
    (when (window-live-p old)
      (let ((buf (window-buffer old)))
        (when (and (with-current-buffer buf (derived-mode-p 'kuro-mode))
                   (not (eq buf (current-buffer))))
          (setq kuro-mux--last-session buf))))))

;;;###autoload
(defun kuro-mux-last ()
  "Switch to the most recently focused kuro session.
Analogous to tmux prefix + L (last window).
Signals `user-error' when there is no recorded previous session or it is dead."
  (interactive)
  (cond
   ((null kuro-mux--last-session)
    (user-error "kuro-mux: no previous kuro session recorded"))
   ((not (buffer-live-p kuro-mux--last-session))
    (setq kuro-mux--last-session nil)
    (user-error "kuro-mux: previous session no longer alive"))
   (t
    (switch-to-buffer kuro-mux--last-session))))

;;;###autoload
(defun kuro-mux-find-window (name)
  "Switch to the kuro session named NAME.
Prompts with completion over all live kuro session buffer names.
If the session is visible in a window, selects that window;
otherwise calls `switch-to-buffer'."
  (interactive
   (list (completing-read "Find session: "
                          (mapcar #'buffer-name (kuro-mux--live-sessions))
                          nil t)))
  (let* ((buf (get-buffer name))
         (win (and buf (get-buffer-window buf 'visible))))
    (cond
     ((null buf)
      (user-error "kuro-mux: no session named %S" name))
     (win
      (select-window win))
     (t
      (switch-to-buffer buf)))))


;;;; Splitting

(defmacro kuro--def-mux-split (name split-fn docstring)
  "Define a kuro-mux split command.
SPLIT-FN is called with no arguments to create the new window."
  `(defun ,name (&optional command)
     ,docstring
     (interactive)
     (let ((win (,split-fn)))
       (select-window win)
       (kuro-create (or command kuro-shell)))))

;;;###autoload
(kuro--def-mux-split kuro-mux-split-right split-window-right
  "Split the current window to the right and open a new kuro terminal.
COMMAND defaults to `kuro-shell'.")

;;;###autoload
(kuro--def-mux-split kuro-mux-split-below split-window-below
  "Split the current window below and open a new kuro terminal.
COMMAND defaults to `kuro-shell'.")


;;;; Window management

;;;###autoload
(defun kuro-mux-detach ()
  "Hide the current kuro session without killing it.
If there are multiple windows visible, the current window is deleted and
the kuro buffer continues running in the background.  If there is only
one window, switches to the next registered session instead (wrapping
around).  The kuro buffer and its PTY process are preserved in both
cases."
  (interactive)
  (unless (derived-mode-p 'kuro-mode)
    (user-error "Not in a kuro buffer"))
  (if (> (count-windows) 1)
      (delete-window)
    (let ((sessions (kuro-mux--live-sessions)))
      (if (> (length sessions) 1)
          (kuro-mux-next)
        (message "kuro-mux: no other sessions to switch to")))))

;;;###autoload
(defun kuro-mux-zoom ()
  "Toggle maximizing the current window in the frame.
On the first call, saves the current window configuration to
`kuro-mux--zoom-config' and calls `delete-other-windows' so the kuro
buffer fills the frame.  On the second call, restores the saved
configuration (\"zoom off\")."
  (interactive)
  (if kuro-mux--zoom-config
      (progn
        (set-window-configuration kuro-mux--zoom-config)
        (setq kuro-mux--zoom-config nil)
        (message "kuro-mux: zoom off"))
    (setq kuro-mux--zoom-config (current-window-configuration))
    (delete-other-windows)
    (message "kuro-mux: zoomed")))

(defcustom kuro-mux-kill-confirm t
  "When non-nil, `kuro-mux-kill' prompts before killing the buffer."
  :type 'boolean
  :group 'kuro)

;;;###autoload
(defun kuro-mux-kill ()
  "Kill the current kuro session buffer and its PTY process.
When `kuro-mux-kill-confirm' is non-nil, prompts for confirmation first."
  (interactive)
  (unless (derived-mode-p 'kuro-mode)
    (user-error "Not in a kuro buffer"))
  (when (or (not kuro-mux-kill-confirm)
            (y-or-n-p (format "Kill kuro session %s? " (buffer-name))))
    (kill-buffer (current-buffer))))

(defmacro kuro--def-mux-swap (name window-nav-fn docstring)
  "Define a kuro-mux pane-swap command.
WINDOW-NAV-FN is called with (selected-window nil \\='visible) to pick the peer."
  `(defun ,name ()
     ,docstring
     (interactive)
     (let ((peer (,window-nav-fn (selected-window) nil 'visible)))
       (if (eq peer (selected-window))
           (user-error "kuro-mux: only one window visible")
         (window-swap-states (selected-window) peer)))))

;;;###autoload
(kuro--def-mux-swap kuro-mux-swap-pane-forward next-window
  "Swap the current window's buffer with the next visible window (tmux: `}').")

;;;###autoload
(kuro--def-mux-swap kuro-mux-swap-pane-backward previous-window
  "Swap the current window's buffer with the previous visible window (tmux: `{').")

(defconst kuro--mux-resize-directions
  '((up    . enlarge-window)
    (down  . shrink-window)
    (left  . shrink-window-horizontally)
    (right . enlarge-window-horizontally))
  "Alist mapping resize direction symbols to their window-resize functions.")

;;;###autoload
(defun kuro-mux-resize-pane (direction &optional delta)
  "Resize the current window pane in DIRECTION by DELTA lines or columns.
DIRECTION is one of the symbols: up, down, left, right.
`up' / `down' adjust vertical size (rows); `left' / `right' adjust
horizontal size (columns).  DELTA defaults to 1 when nil or omitted.
Analogous to tmux's resize-pane command."
  (interactive
   (list (intern (completing-read
                  "Direction (up/down/left/right): "
                  (mapcar (lambda (e) (symbol-name (car e)))
                          kuro--mux-resize-directions)
                  nil t))
         (if current-prefix-arg
             (prefix-numeric-value current-prefix-arg)
           1)))
  (let ((n    (max 1 (or delta 1)))
        (cell (assq direction kuro--mux-resize-directions)))
    (if cell
        (funcall (cdr cell) n)
      (user-error "kuro-mux: invalid direction: %s" direction))))



(require 'kuro-mux-layout)
(require 'kuro-mux-ext)
(require 'kuro-mux-ext2)

(provide 'kuro-mux)
;;; kuro-mux.el ends here
