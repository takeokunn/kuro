;;; kuro-lifecycle.el --- Terminal lifecycle management for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; This file provides terminal lifecycle management for Kuro.
;;
;; # Responsibilities
;;
;; - Terminal creation: `kuro-create'
;; - Terminal teardown: `kuro-kill' (destroy or detach)
;; - Session listing: `kuro-list-sessions'
;; - Session re-attachment: `kuro-attach'
;; - Interactive send commands: `kuro-send-string', `kuro-send-interrupt',
;;   `kuro-send-sigstop', `kuro-send-sigquit'

;;; Code:

(require 'kuro-ffi)
(require 'kuro-renderer)
(require 'kuro-faces)
(require 'kuro-render-buffer)

;; Forward-declare functions defined in kuro.el to avoid circular require
(declare-function kuro-mode "kuro" ())
(declare-function kuro--window-size-change "kuro" (frame))

;; Forward-declare render loop functions defined in kuro-renderer.el
(declare-function kuro--render-cycle      "kuro-renderer" ())
(declare-function kuro--start-render-loop "kuro-renderer" ())
(declare-function kuro--stop-render-loop  "kuro-renderer" ())

;; kuro--ensure-module-loaded is defined in kuro-module.el
(declare-function kuro--ensure-module-loaded "kuro-module" ())

;; face-remap-remove-relative is provided by the C core (face-remap.el)
(declare-function face-remap-remove-relative "face-remap" (cookie))

(defconst kuro--startup-render-delay 0.05
  "Delay in seconds before the first render after terminal startup.")

(defconst kuro--buffer-name-default "*kuro*"
  "Default buffer name for new Kuro terminal instances.")

(defconst kuro--buffer-name-sessions "*kuro-sessions*"
  "Buffer name used by `kuro-list-sessions' to display session list.")

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
  "Roll back a failed attach for SESSION-ID: log ERR, clear state, detach, kill BUFFER."
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
Assumes `kuro--stop-render-loop' and `kuro--cleanup-render-state' have already run."
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
    (kuro--reset-cursor-cache)))

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

;;;###autoload
(defun kuro-create (&optional command buffer-name)
  "Create a new Kuro terminal instance running COMMAND.
If COMMAND is nil, use `kuro-shell'.
BUFFER-NAME is the name for the new buffer.
Switches to the terminal buffer after creation."
  (interactive
   (list
    (read-string "Shell command: " kuro-shell)
    (generate-new-buffer-name kuro--buffer-name-default)))
  (kuro--ensure-module-loaded)
  (let* ((cmd (or command kuro-shell))
         (buffer (get-buffer-create (or buffer-name (generate-new-buffer-name kuro--buffer-name-default)))))
    ;; Display the buffer FIRST so window-body-height/width reflect the real window.
    ;; We need exact dimensions before spawning the PTY; otherwise the shell starts
    ;; with hardcoded 24×80 and full-screen programs (vim, htop, …) that run before
    ;; the resize SIGWINCH arrives will lay out their UI with the wrong geometry.
    (unless noninteractive
      (switch-to-buffer buffer))
    (let ((rows (if noninteractive kuro--default-rows (window-body-height)))
          (cols (if noninteractive kuro--default-cols (window-body-width))))
      (with-current-buffer buffer
        (kuro-mode)
        (let ((inhibit-read-only t))
          (kuro--prefill-buffer rows))
        ;; Spawn PTY with the correct dimensions from the start — no resize needed.
        (when (kuro--init cmd rows cols)
          (kuro--init-session-buffer buffer rows cols)
          (kuro--start-render-loop)
          (kuro--schedule-initial-render buffer)
          (message "Kuro: Started terminal with command: %s" cmd))))
    buffer))

;;;###autoload
(defun kuro-send-string (string)
  "Send STRING to the terminal."
  (interactive "sSend string: ")
  (kuro--send-key string))

(defmacro kuro--def-control-key (name sequence doc)
  "Define an interactive command NAME that sends SEQUENCE to the terminal."
  `(defun ,name () ,doc (interactive) (kuro--send-key ,sequence)))

;;;###autoload
(kuro--def-control-key kuro-send-interrupt [?\C-c]  "Send interrupt signal (C-c) to the terminal process.")
;;;###autoload
(kuro--def-control-key kuro-send-sigstop  [?\C-z]  "Send SIGSTOP (C-z) to the terminal process.")
;;;###autoload
(kuro--def-control-key kuro-send-sigquit  [?\C-\\] "Send quit signal (C-\\) to the terminal process.")

(defun kuro--cleanup-render-state ()
  "Reset all render-related buffer state for teardown.
Called by `kuro-kill' immediately after stopping the render loop.
Resets TUI mode counters, overlay lists, mouse state, scroll offset,
and font remap cookie.  Idempotent: safe to call more than once."
  (setq kuro--tui-mode-active     nil
        kuro--tui-mode-frame-count 0
        kuro--last-dirty-count    0)
  (remove-overlays (point-min) (point-max) 'kuro-blink t)
  (setq kuro--blink-overlays nil)
  (kuro--clear-all-image-overlays)
  (setq kuro--mouse-mode       0
        kuro--mouse-sgr        nil
        kuro--mouse-pixel-mode nil
        kuro--scroll-offset    0)
  (when (and (boundp 'kuro--font-remap-cookie) kuro--font-remap-cookie)
    (face-remap-remove-relative kuro--font-remap-cookie)
    (setq kuro--font-remap-cookie nil)))

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

;;;###autoload
(defun kuro-list-sessions ()
  "Display all active Kuro terminal sessions in a dedicated buffer.
Each entry shows the session ID, shell command, and current status
(running, detached, or dead).  Use `kuro-attach' to reconnect to a
detached session."
  (interactive)
  (let ((sessions (condition-case nil
                      (kuro-core-list-sessions)
                    (error nil))))
    (if (null sessions)
        (message "No active Kuro sessions.")
      (with-current-buffer (get-buffer-create kuro--buffer-name-sessions)
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert "Kuro Terminal Sessions\n")
          (insert "----------------------\n\n")
          (dolist (entry sessions)
            (pcase-let* ((`(,id ,cmd ,detached-p ,alive-p) entry)
                         (status (cond (detached-p "detached")
                                       (alive-p    "running")
                                       (t          "dead"))))
              (insert (format "  ID %-4d  %-12s  %s\n" id status cmd))))
          (insert "\nUse M-x kuro-attach to reconnect to a detached session.\n")
          (goto-char (point-min)))
        (display-buffer (current-buffer))))))

;;;###autoload
(defun kuro-attach (session-id)
  "Attach to a detached Kuro session identified by SESSION-ID.
Creates a new buffer in `kuro-mode', associates it with the existing
PTY session, and starts the render loop.  The session must be in the
detached state (see `kuro-list-sessions' and `kuro-kill')."
  (interactive "nSession ID to attach: ")
  (kuro--ensure-module-loaded)
  (let ((buffer (generate-new-buffer (format "*kuro<%d>*" session-id))))
    (unless noninteractive
      (switch-to-buffer buffer))
    (with-current-buffer buffer
      (kuro-mode)
      (let ((rows (if noninteractive kuro--default-rows (window-body-height)))
            (cols (if noninteractive kuro--default-cols (window-body-width))))
        (condition-case err
            (progn
              (kuro--do-attach session-id rows cols)
              (message "Kuro: Attached to session %d" session-id))
          (error
           (kuro--rollback-attach session-id buffer err)))))
    buffer))

(provide 'kuro-lifecycle)

;;; kuro-lifecycle.el ends here
