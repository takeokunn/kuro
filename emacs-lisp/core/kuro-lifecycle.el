;;; kuro-lifecycle.el --- Terminal lifecycle management for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; This file provides terminal lifecycle management for Kuro.
;;
;; # Responsibilities
;;
;; - Terminal creation: `kuro-create'
;; - Terminal teardown: `kuro-kill' (destroy or detach)
;; - Session re-attachment: `kuro-attach'
;; - Interactive send commands: `kuro-send-string', `kuro-send-interrupt',
;;   `kuro-send-sigstop', `kuro-send-sigquit'

;;; Code:

(require 'seq)
(require 'kuro-ffi)
(require 'kuro-renderer)
(require 'kuro-faces)
(require 'kuro-render-buffer)
(require 'kuro-dnd)
(require 'kuro-compilation)
(require 'kuro-bookmark)
(require 'kuro-color-scheme)

;; Forward-declare functions defined in kuro.el to avoid circular require
(declare-function kuro-mode "kuro" ())

;; Forward-declare render loop functions defined in kuro-renderer.el
(declare-function kuro--render-cycle      "kuro-renderer" ())
(declare-function kuro--start-render-loop "kuro-renderer" ())
(declare-function kuro--stop-render-loop  "kuro-renderer" ())

;; kuro--ensure-module-loaded, kuro-module-load, kuro-module-download, and
;; kuro-module-build are defined in kuro-module.el; kuro-module-installation-method
;; is defined as a defcustom there.
(declare-function kuro--ensure-module-loaded "kuro-module" ())
(declare-function kuro-module-load           "kuro-module" ())
(declare-function kuro-module-download       "kuro-module" (&optional version))
(declare-function kuro-module-build          "kuro-module" ())
(defvar kuro-module-installation-method)

;; face-remap-remove-relative is provided by the C core (face-remap.el)
(declare-function face-remap-remove-relative "face-remap" (cookie))

(defconst kuro--startup-render-delay 0.05
  "Delay in seconds before the first render after terminal startup.")

;; kuro-config.el
(defvar kuro-shell-integration)

(defun kuro--shell-integration-dir ()
  "Return the directory containing kuro shell integration scripts, or nil.
Resolves the `shell/' directory relative to the Elisp source location."
  (when kuro-shell-integration
    (let* ((lib (or (locate-library "kuro-lifecycle")
                    (locate-library "kuro")))
           (dir (and lib (expand-file-name
                          "shell"
                          (file-name-directory
                           (directory-file-name
                            (file-name-directory lib)))))))
      (when (and dir (file-directory-p dir))
        dir))))

(defun kuro--setup-shell-integration-env ()
  "Set KURO_SHELL_INTEGRATION_DIR for the next PTY spawn.
The Rust child process reads this variable and configures shell-specific
integration.  The variable is removed by Rust after reading."
  (let ((dir (kuro--shell-integration-dir)))
    (if dir
        (setenv "KURO_SHELL_INTEGRATION_DIR" dir)
      (setenv "KURO_SHELL_INTEGRATION_DIR" nil))))

(defconst kuro--buffer-name-default "*kuro*"
  "Default buffer name for new Kuro terminal instances.")

(defun kuro--terminal-dimensions ()
  "Return the current terminal size as a (ROWS . COLS) cons cell."
  (cons (if noninteractive kuro--default-rows (window-body-height))
        (if noninteractive kuro--default-cols (window-body-width))))

(defun kuro--session-buffer-name (session-id)
  "Return the buffer name used when attaching to SESSION-ID."
  (format "*kuro<%d>*" session-id))

(defun kuro--show-buffer-if-interactive (buffer)
  "Display BUFFER in the selected window when running interactively."
  (unless noninteractive
    (switch-to-buffer buffer))
  buffer)

(defun kuro--create-session-buffer (&optional buffer-name)
  "Create and display a new session buffer named BUFFER-NAME.
When BUFFER-NAME is nil, generate a fresh name from `kuro--buffer-name-default'."
  (kuro--show-buffer-if-interactive
   (get-buffer-create (or buffer-name
                          (generate-new-buffer-name kuro--buffer-name-default)))))

(defvar-local kuro--shell-command nil
  "The shell command used to create this terminal session.")

(defun kuro--start-session-in-buffer (buffer command)
  "Start COMMAND in BUFFER and initialize the terminal display.
Returns BUFFER after attempting startup."
  (with-current-buffer buffer
    (kuro-mode)
    (setq kuro--shell-command command)
    ;; Measure AFTER kuro-mode: kuro--assign-mono-fonts changes the fontset
    ;; via set-fontset-font, which can change effective line height (replacing
    ;; taller fallback fonts with the ASCII monospace font).  This changes
    ;; window-body-height without triggering window-size-change-functions
    ;; (pixel size is unchanged).  Measuring before kuro-mode gives a stale
    ;; row count, causing TUI apps to draw for the wrong terminal size.
    (pcase-let ((`(,rows . ,cols) (kuro--terminal-dimensions)))
      (let ((inhibit-read-only t))
        (kuro--prefill-buffer rows))
      (kuro--setup-shell-integration-env)
      (when (kuro--init command nil rows cols)
        (kuro--init-session-buffer buffer rows cols)
        (kuro--start-render-loop)
        (kuro--schedule-initial-render buffer)
        (message "Kuro: Started terminal with command: %s" command))))
  buffer)

(defmacro kuro--clear-session-state ()
  "Reset buffer-local session identity after detach or error.
Sets `kuro--initialized' to nil and `kuro--session-id' to 0."
  `(setq kuro--initialized nil
         kuro--session-id  0))

(defun kuro--do-attach (session-id rows cols)
  "Perform the core attach steps for SESSION-ID at terminal size ROWS x COLS.
Assumes the calling buffer is already in `kuro-mode'.
Signals on any failure; the caller is responsible for rollback."
  (let ((inhibit-read-only t))
    (kuro-core-attach session-id)
    (setq kuro--session-id session-id
          kuro--initialized t)
    (kuro--prefill-buffer rows)
    (kuro--init-session-buffer (current-buffer) rows cols)
    (kuro--resize rows cols)
    (kuro--start-render-loop)))

(defun kuro--rollback-attach (session-id buffer err)
  "Roll back a failed attach for SESSION-ID.
Log ERR, clear state, detach, and kill BUFFER."
  (message "Kuro: Failed to attach to session %d: %s" session-id err)
  (kuro--clear-session-state)
  (condition-case nil
      (kuro-core-detach session-id)
    (error nil))
  (kill-buffer buffer)
  nil)

(defun kuro--teardown-session ()
  "Detach or destroy the current session, prompting if the process is alive.
Detached sessions remain reattachable via `kuro-attach'.
Assumes `kuro--stop-render-loop' and `kuro--cleanup-render-state' already ran."
  (if (and kuro--initialized
           (kuro--is-process-alive)
           (not (yes-or-no-p "Kill the terminal process? (\"no\" detaches it) ")))
      ;; Detach: PTY keeps running; another buffer can attach later.
      (condition-case nil
          (progn
            (kuro-core-detach kuro--session-id)
            (kuro--clear-session-state))
        (error
         (kuro--clear-session-state)))
    ;; Destroy: shutdown PTY and remove session from the HashMap.
    (kuro--shutdown)))

(defun kuro--prefill-buffer (rows)
  "Erase the current buffer and insert ROWS blank lines.
Leaves point at `point-min'.  Must be called with `inhibit-read-only' bound
to t by the caller.  Used by both `kuro-create' and `kuro-attach' so that
`kuro--update-line-full' can navigate to any row without hitting
end-of-buffer."
  (erase-buffer)
  (dotimes (_ rows)
    (insert "\n"))
  (goto-char (point-min)))

(defun kuro--schedule-initial-render (buf)
  "Schedule an immediate render for BUF after the PTY session is started.
Posts an idle timer so the shell prompt appears at once rather than
waiting for the first periodic tick of the render loop (~8 ms at 120 fps).
The timer is a one-shot: it fires once and is not rescheduled."
  (run-with-idle-timer kuro--startup-render-delay nil
                       (lambda (b)
                         (when (buffer-live-p b)
                           (with-current-buffer b
                             (kuro--render-cycle))))
                       buf))

(defun kuro--init-session-buffer (buffer rows cols)
  "Initialize BUFFER as a kuro session display with dimensions ROWS×COLS.
Called from both `kuro-create' (new session) and `kuro-attach' (re-attach).
Sets up scrollback, font remapping, char-width table, fontset, default
colors, and resets all cursor cache state so the first render frame
always computes fresh cursor position from Rust."
  (with-current-buffer buffer
    (setq kuro--cursor-marker (point-marker)
          kuro--last-rows     rows
          kuro--last-cols     cols
          kuro--scroll-offset 0)
    (kuro--set-scrollback-max-lines kuro-scrollback-size)
    (kuro--apply-font-to-buffer buffer)
    (kuro--setup-char-width-table)
    (kuro--setup-fontset)
    (kuro--remap-default-face kuro-color-white kuro-color-black)
    (kuro--reset-cursor-cache)
    (kuro--ensure-left-margin)
    (kuro--setup-dnd)
    (kuro--setup-compilation)
    (kuro--setup-bookmark)
    ;; Install the global theme-change hook (idempotent via add-hook) and
    ;; sync the current Emacs theme to this session immediately so DSR 996
    ;; is truthful before any future theme switch.
    (kuro--color-scheme-install-hook)
    (ignore-errors (kuro-color-scheme-refresh))))

;; kuro--set-scrollback-max-lines is defined in kuro-ffi-osc.el (loaded via kuro-renderer)
(declare-function kuro--set-scrollback-max-lines "kuro-ffi-osc" (max-lines))

;; Multi-session FFI functions provided by the Rust dynamic module at runtime.
(declare-function kuro-core-detach        "ext:kuro-core" (session-id))
(declare-function kuro-core-attach        "ext:kuro-core" (session-id))
(declare-function kuro-core-list-sessions "ext:kuro-core" ())

;; kuro--resize is defined in kuro-ffi.el (required above); declared here for
;; byte-compiler visibility when kuro-attach calls it before the first render.
(declare-function kuro--resize "kuro-ffi" (rows cols))

;; kuro--apply-font-to-buffer and kuro--remap-default-face are defined in kuro-faces.el
(declare-function kuro--apply-font-to-buffer "kuro-faces" (buf))
(declare-function kuro--remap-default-face   "kuro-faces" (fg-str bg-str))

;; kuro--setup-char-width-table and kuro--setup-fontset are defined in kuro-char-width.el
(declare-function kuro--setup-char-width-table "kuro-char-width" ())
(declare-function kuro--setup-fontset "kuro-char-width" ())

;; kuro--clear-all-image-overlays is defined in kuro-overlays.el
(declare-function kuro--clear-all-image-overlays "kuro-overlays" ())

;; kuro--clear-hyperlink-overlays is defined in kuro-hyperlinks.el
(declare-function kuro--clear-hyperlink-overlays "kuro-hyperlinks" ())

;; kuro-dnd.el
(declare-function kuro--setup-dnd    "kuro-dnd" ())
(declare-function kuro--teardown-dnd "kuro-dnd" ())

;; kuro-compilation.el
(declare-function kuro--setup-compilation    "kuro-compilation" ())
(declare-function kuro--teardown-compilation "kuro-compilation" ())

;; kuro-bookmark.el
(declare-function kuro--setup-bookmark "kuro-bookmark" ())

;; kuro-color-scheme.el
(declare-function kuro--color-scheme-install-hook   "kuro-color-scheme" ())
(declare-function kuro--color-scheme-uninstall-hook "kuro-color-scheme" ())
(declare-function kuro-color-scheme-refresh         "kuro-color-scheme" ())

;; kuro-config.el
(declare-function kuro--kuro-buffers "kuro-config" ())

;; kuro-prompt-status.el
(declare-function kuro--ensure-left-margin           "kuro-prompt-status" ())
(declare-function kuro--clear-prompt-status-overlays "kuro-prompt-status" ())

;; Forward reference: defvar-local in kuro-input-mouse.el
(defvar kuro--mouse-pixel-mode nil
  "Forward reference; defvar-local in kuro-input-mouse.el.")

;; Forward declarations for defvar-local symbols written or tested in
;; kuro-kill / kuro-create but defined in other modules.
;; kuro-renderer.el
(defvar kuro--cursor-marker nil
  "Forward reference; defvar-local in kuro-renderer.el.")
;; kuro.el
(defvar kuro--last-rows 0
  "Forward reference; defvar-local in kuro.el.")
(defvar kuro--last-cols 0
  "Forward reference; defvar-local in kuro.el.")
;; kuro-input.el
(defvar kuro--scroll-offset 0
  "Forward reference; defvar-local in kuro-input.el.")
;; kuro-overlays.el
(defvar kuro--blink-overlays nil
  "Forward reference; defvar-local in kuro-overlays.el.")
(defvar kuro--blink-overlays-slow nil
  "Forward reference; defvar-local in kuro-overlays.el.")
(defvar kuro--blink-overlays-fast nil
  "Forward reference; defvar-local in kuro-overlays.el.")
;; kuro-tui-mode.el (TUI mode state)
(defvar kuro--tui-mode-active nil
  "Forward reference; defvar-permanent-local in kuro-tui-mode.el.")
(defvar kuro--tui-mode-frame-count 0
  "Forward reference; defvar-permanent-local in kuro-tui-mode.el.")
(defvar kuro--last-dirty-count 0
  "Forward reference; defvar-permanent-local in kuro-tui-mode.el.")
;; kuro-render-buffer.el
(defvar kuro--last-cursor-row nil
  "Forward reference; defvar-local in kuro-render-buffer.el.")
(defvar kuro--last-cursor-col nil
  "Forward reference; defvar-local in kuro-render-buffer.el.")
(defvar kuro--last-cursor-visible nil
  "Forward reference; defvar-local in kuro-render-buffer.el.")
(defvar kuro--last-cursor-shape nil
  "Forward reference; defvar-local in kuro-render-buffer.el.")
;; kuro-input-mouse.el
(defvar kuro--mouse-mode 0
  "Forward reference; defvar-local in kuro-input-mouse.el.")
(defvar kuro--mouse-sgr nil
  "Forward reference; defvar-local in kuro-input-mouse.el.")
;; kuro-faces.el
(defvar kuro--font-remap-cookie nil
  "Forward reference; defvar-local in kuro-faces.el.")

(defun kuro--module-loadable-p ()
  "Return non-nil when the Rust dynamic module is loaded into Emacs.
Detects this by probing for `kuro-core-init', the canonical FFI entry
point provided by the native module."
  (fboundp 'kuro-core-init))

(defun kuro--try-load-module ()
  "Attempt to load the Rust native module, swallowing any errors.
Returns non-nil iff the module is loaded after the attempt."
  (ignore-errors (kuro-module-load))
  (kuro--module-loadable-p))

(defun kuro--prompt-and-install-module ()
  "Prompt the user to install the native module, then load it.
Offers three choices via `read-char-choice':
  d — download a prebuilt binary via `kuro-module-download'.
  b — build from source via `kuro-module-build'.
  q — abort with `user-error'.
Signals a `user-error' on quit; otherwise returns non-nil after a
successful install and load."
  (pcase (read-char-choice
          (concat "Kuro native module not found. "
                  "Install: [d]ownload prebuilt, [b]uild from source, [q]uit? ")
          '(?d ?b ?q))
    (?d (kuro-module-download) (kuro-module-load)
        (or (kuro--module-loadable-p)
            (error "Kuro: download succeeded but native init is not bound")))
    (?b (kuro-module-build)    (kuro-module-load)
        (or (kuro--module-loadable-p)
            (error "Kuro: cargo build succeeded but native init is not bound")))
    (?q (user-error "Aborted: kuro native module is required"))))

(defun kuro--ensure-module-installed ()
  "Ensure the native module is installed, prompting the user if not.
Honours `kuro-module-installation-method' to skip the interactive
prompt: the symbols `prebuilt', `cargo', and `manual' map to download,
build, and abort-with-error respectively; nil falls through to the
interactive prompt.  Returns non-nil on success; signals an error
otherwise."
  (or (kuro--try-load-module)
      (pcase kuro-module-installation-method
        ('prebuilt (kuro-module-download) (kuro-module-load)
                   (or (kuro--module-loadable-p)
                       (error "Kuro: download succeeded but native init is not bound")))
        ('cargo    (kuro-module-build)    (kuro-module-load)
                   (or (kuro--module-loadable-p)
                       (error "Kuro: cargo build succeeded but native init is not bound")))
        ('manual   (user-error "Native module missing; install manually then retry"))
        (_         (kuro--prompt-and-install-module)))))

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

(defmacro kuro--def-control-key (name sequence doc)
  "Define an interactive command NAME that sends SEQUENCE to the terminal."
  `(defun ,name () ,doc (interactive) (kuro--send-key ,sequence)))

(kuro--def-control-key kuro-send-interrupt [?\C-c]  "Send interrupt signal (C-c) to the terminal.")
;;;###autoload (autoload 'kuro-send-interrupt "kuro-lifecycle" nil t)
(kuro--def-control-key kuro-send-sigstop  [?\C-z]  "Send SIGSTOP (C-z) to the terminal process.")
;;;###autoload (autoload 'kuro-send-sigstop "kuro-lifecycle" nil t)
(kuro--def-control-key kuro-send-sigquit  [?\C-\\] "Send quit signal (C-\\) to the terminal process.")
;;;###autoload (autoload 'kuro-send-sigquit "kuro-lifecycle" nil t)

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
  "Convert detached session SESSIONS into completing-read candidates."
  (mapcar (lambda (entry)
            (pcase-let ((`(,id ,cmd ,_detached-p ,_alive-p) entry))
              (cons (format "Session %d: %s" id cmd) id)))
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

(require 'kuro-sessions)

(provide 'kuro-lifecycle)

;;; kuro-lifecycle.el ends here
