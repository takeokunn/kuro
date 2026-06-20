;;; kuro-lifecycle-commands.el --- Interactive Kuro terminal commands  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Interactive user-facing commands for Kuro: terminal creation, send
;; commands, kill, and session re-attachment.  Loaded automatically at the
;; end of `kuro-lifecycle'.

;;; Code:

(require 'seq)
(require 'kuro-faces-macros)
(require 'kuro-lifecycle-commands-macros)
(require 'kuro-lifecycle-module)

;; Functions defined in kuro-lifecycle.el or kuro-lifecycle-module.el
;; (loaded before this file at runtime).
(declare-function kuro--ensure-module-installed    "kuro-lifecycle-module" ())
(declare-function kuro--start-session-in-buffer    "kuro-lifecycle" (buffer command))
(declare-function kuro--create-session-buffer      "kuro-lifecycle" (&optional buffer-name))
(declare-function kuro--show-buffer-if-interactive "kuro-lifecycle" (buffer))
(declare-function kuro--session-buffer-name        "kuro-lifecycle" (session-id))
(declare-function kuro--terminal-dimensions        "kuro-lifecycle" ())
(declare-function kuro--do-attach                  "kuro-lifecycle" (session-id rows cols))
(declare-function kuro--rollback-attach            "kuro-lifecycle" (session-id buffer err))
(declare-function kuro--teardown-session           "kuro-lifecycle" ())

;; Functions from other modules (all required by kuro-lifecycle.el transitively).
(declare-function kuro--send-key                    "kuro-ffi"           (key))
(declare-function kuro--send-paste-or-raw           "kuro-input-paste"   (text))
(declare-function kuro--schedule-immediate-render   "kuro-input"         ())
(declare-function kuro--stop-render-loop            "kuro-renderer"      ())
(declare-function kuro--clear-all-image-overlays    "kuro-overlays"      ())
(declare-function kuro--clear-hyperlink-overlays    "kuro-hyperlinks"    ())
(declare-function kuro--clear-prompt-status-overlays "kuro-prompt-status" ())
(declare-function kuro--teardown-compilation        "kuro-compilation"   ())
(declare-function kuro--teardown-dnd                "kuro-dnd"           ())
(declare-function kuro--kuro-buffers               "kuro-config"        ())
(declare-function kuro--color-scheme-uninstall-hook "kuro-color-scheme"  ())
(declare-function kuro-core-list-sessions           "ext:kuro-core"      ())
(declare-function kuro-mode                         "kuro"               ())
(declare-function face-remap-remove-relative        "face-remap"         (cookie))

;; Variables defined in kuro-lifecycle.el or loaded modules.
(defvar kuro-shell)
(defvar kuro--buffer-name-default)
(defvar kuro--tui-mode-active)
(defvar kuro--tui-mode-frame-count)
(defvar kuro--last-dirty-count)
(defvar kuro--blink-overlays)
(defvar kuro--blink-overlays-slow)
(defvar kuro--blink-overlays-fast)
(defvar kuro--mouse-mode)
(defvar kuro--mouse-sgr)
(defvar kuro--mouse-pixel-mode)
(defvar kuro--scroll-offset)
(defvar kuro--font-remap-cookie)

;;;###autoload
(defun kuro-create (&optional command buffer-name)
  "Create a new Kuro terminal instance running COMMAND.
If COMMAND is nil, use `kuro-shell'.
BUFFER-NAME is the name for the new buffer.
Switches to the terminal buffer after creation.
On first run, when the Rust native module is missing, the user is
prompted to download a prebuilt binary or build it from source; the
prompt is skipped when `kuro-module-installation-method' is set."
  (interactive
   (list
    (read-string "Shell command: " kuro-shell)
    (generate-new-buffer-name kuro--buffer-name-default)))
  (kuro--ensure-module-installed)
  (kuro--start-session-in-buffer
   (kuro--create-session-buffer buffer-name)
   (or command kuro-shell)))

;;;###autoload
(defalias 'kuro #'kuro-create
  "Alias for `kuro-create'. Launch a new Kuro terminal.")

;;;###autoload
(defun kuro-send-string (string)
  "Send STRING to the terminal."
  (interactive "sSend string: ")
  (kuro--send-key string))

(defun kuro--most-recent-buffer ()
  "Return the most recently active live Kuro terminal buffer, or nil.
Searches `buffer-list' which is ordered by most-recently-selected buffer,
so this returns the Kuro buffer the user was last in across all windows."
  (seq-find (lambda (b)
              (with-current-buffer b (derived-mode-p 'kuro-mode)))
            (buffer-list)))

;;;###autoload
(defun kuro-send-region (start end)
  "Send the text between START and END to a Kuro terminal buffer.
When called inside a Kuro buffer, sends to the current buffer's PTY.
When called from any other buffer, sends to the most recently active
Kuro session.  When the target terminal has mode 2004 active, the text is
wrapped with ESC[200~ and ESC[201~ bracketed-paste sequences, preventing
injection attacks through multi-line content.

Typical use: select a code block in a source buffer, call this command
to send it to a running shell or REPL without using the kill ring."
  (interactive "r")
  (let ((text (buffer-substring-no-properties start end)))
    (let ((target (if (derived-mode-p 'kuro-mode)
                      (current-buffer)
                    (or (kuro--most-recent-buffer)
                        (user-error "No live Kuro session found")))))
      (with-current-buffer target
        (kuro--send-paste-or-raw text)
        (kuro--schedule-immediate-render)))))

(kuro--def-control-key kuro-send-interrupt [?\C-c]  "Send interrupt signal (C-c) to the terminal.")
;;;###autoload (autoload 'kuro-send-interrupt "kuro-lifecycle-commands" nil t)
(kuro--def-control-key kuro-send-sigstop   [?\C-z]  "Send SIGSTOP (C-z) to the terminal process.")
;;;###autoload (autoload 'kuro-send-sigstop "kuro-lifecycle-commands" nil t)
(kuro--def-control-key kuro-send-sigquit   [?\C-\\] "Send quit signal (C-\\) to the terminal process.")
;;;###autoload (autoload 'kuro-send-sigquit "kuro-lifecycle-commands" nil t)

(defun kuro--cleanup-render-state ()
  "Reset all render-related buffer state for teardown.
Called by `kuro-kill' immediately after stopping the render loop.
Resets TUI mode counters, overlay lists, mouse state, scroll offset,
and font remap cookie.  Idempotent: safe to call more than once.
When the buffer being killed is the LAST live Kuro buffer, also
uninstalls the global `enable-theme-functions' hook so it does not
iterate over zero buffers on every future theme switch."
  (setq kuro--tui-mode-active     nil
        kuro--tui-mode-frame-count 0
        kuro--last-dirty-count    0)
  (remove-overlays (point-min) (point-max) 'kuro-blink t)
  (setq kuro--blink-overlays      nil
        kuro--blink-overlays-slow nil
        kuro--blink-overlays-fast nil)
  (kuro--clear-all-image-overlays)
  (kuro--clear-hyperlink-overlays)
  (kuro--clear-prompt-status-overlays)
  (setq kuro--mouse-mode       0
        kuro--mouse-sgr        nil
        kuro--mouse-pixel-mode nil
        kuro--scroll-offset    0)
  (kuro--with-face-remap kuro--font-remap-cookie)
  (kuro--teardown-compilation)
  (kuro--teardown-dnd)
  ;; Uninstall the global theme-change hook when this is the last live
  ;; Kuro buffer.  The current buffer still appears in `kuro--kuro-buffers'
  ;; (kill-buffer runs after this), so the "last buffer" condition is
  ;; "remaining Kuro buffers excluding self is empty".
  (let ((others (remq (current-buffer) (kuro--kuro-buffers))))
    (unless others
      (kuro--color-scheme-uninstall-hook))))

;;;###autoload
(defun kuro-kill ()
  "Kill the current Kuro terminal.
When the child process is still alive, prompts the user:
  yes — destroy the process and remove the session.
  no  — detach the session (PTY continues running, buffer is closed).
Detached sessions can be re-attached with `kuro-attach'."
  (interactive)
  (when (derived-mode-p 'kuro-mode)
    (kuro--stop-render-loop)
    (kuro--cleanup-render-state)
    (kuro--teardown-session)
    (kill-buffer (current-buffer))))

(defun kuro--list-sessions-safe ()
  "Return active sessions from Rust, or nil if the query fails."
  (condition-case nil
      (kuro-core-list-sessions)
    (error nil)))

(defun kuro--detached-sessions (sessions)
  "Return detached entries from SESSIONS.
Each entry is expected to be (ID COMMAND DETACHED-P ALIVE-P)."
  (seq-filter (lambda (entry) (nth 2 entry)) sessions))

(defun kuro--session-candidates (sessions)
  "Convert detached session SESSIONS into `completing-read' candidates.
Each entry is (ID COMMAND DETACHED-P ALIVE-P); only ID and COMMAND are used."
  (mapcar (lambda (entry)
            (cons (format "Session %d: %s" (car entry) (cadr entry))
                  (car entry)))
          sessions))

(defun kuro--read-attach-session-id ()
  "Prompt for a detached session ID and return it.
Signals a user error if no sessions are available for attach."
  (let* ((sessions (kuro--list-sessions-safe))
         (detached (kuro--detached-sessions sessions)))
    (cond
     ((null sessions)
      (user-error "No active Kuro sessions"))
     ((null detached)
      (user-error "No detached Kuro sessions available for attach"))
     (t
      (let* ((candidates (kuro--session-candidates detached))
             (choice (completing-read "Attach to session: " candidates nil t)))
        (cdr (assoc choice candidates)))))))

(defun kuro--attach-buffer (session-id)
  "Create and display a fresh attach buffer for SESSION-ID."
  (kuro--show-buffer-if-interactive
   (generate-new-buffer (kuro--session-buffer-name session-id))))

;;;###autoload
(defun kuro-attach (session-id)
  "Attach to a detached Kuro session identified by SESSION-ID.
Creates a new buffer in `kuro-mode', associates it with the existing
PTY session, and starts the render loop.  The session must be in the
detached state (see `kuro-list-sessions' and `kuro-kill')."
  (interactive (list (kuro--read-attach-session-id)))
  (kuro--ensure-module-installed)
  (let ((buffer (kuro--attach-buffer session-id)))
    (with-current-buffer buffer
      (kuro-mode)
      (pcase-let ((`(,rows . ,cols) (kuro--terminal-dimensions)))
        (condition-case err
            (progn
              (kuro--do-attach session-id rows cols)
              (message "Kuro: Attached to session %d" session-id))
          (error
           (kuro--rollback-attach session-id buffer err)))))
    buffer))

(provide 'kuro-lifecycle-commands)
;;; kuro-lifecycle-commands.el ends here
