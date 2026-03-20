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

;; kuro--set-scrollback-max-lines is defined in kuro-ffi-osc.el (loaded via kuro-renderer)
(declare-function kuro--set-scrollback-max-lines "kuro-ffi-osc" (max-lines))

;; Multi-session FFI functions provided by the Rust dynamic module at runtime.
(declare-function kuro-core-detach        "ext:kuro-core" (session-id))
(declare-function kuro-core-attach        "ext:kuro-core" (session-id))
(declare-function kuro-core-list-sessions "ext:kuro-core" ())

;; kuro--resize is defined in kuro-ffi.el (required above); declared here for
;; byte-compiler visibility when kuro-attach calls it before the first render.
(declare-function kuro--resize "kuro-ffi" (rows cols))

;; kuro--apply-font-to-buffer is defined in kuro-faces.el
(declare-function kuro--apply-font-to-buffer "kuro-faces" (buf))

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
    (generate-new-buffer-name "*kuro*")))
  (kuro--ensure-module-loaded)
  (let* ((cmd (or command kuro-shell))
         (buffer (get-buffer-create (or buffer-name (generate-new-buffer-name "*kuro*")))))
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
        ;; Pre-fill with blank lines so `kuro--update-line-full' can navigate
        ;; via forward-line to any row without hitting end-of-buffer.
        (let ((inhibit-read-only t))
          (erase-buffer)
          (dotimes (_ rows)
            (insert "\n"))
          (goto-char (point-min)))
        ;; Spawn PTY with the correct dimensions from the start — no resize needed.
        (when (kuro--init cmd rows cols)
          (setq kuro--cursor-marker (point-marker))
          (setq kuro--last-rows rows)
          (setq kuro--last-cols cols)
          (kuro--set-scrollback-max-lines kuro-scrollback-size)
          (setq kuro--scroll-offset 0)
          (kuro--apply-font-to-buffer buffer)
          (kuro--start-render-loop)
          ;; Schedule an immediate render so the shell prompt appears at once
          ;; instead of waiting for the first periodic timer tick (~16ms at 60fps).
          ;; This is what makes kuro feel as instant as kitty on startup.
          (run-with-idle-timer kuro--startup-render-delay nil
                               (lambda (buf)
                                 (when (buffer-live-p buf)
                                   (with-current-buffer buf
                                     (kuro--render-cycle))))
                               buffer)
          (message "Kuro: Started terminal with command: %s" cmd))))
    buffer))

;;;###autoload
(defun kuro-send-string (string)
  "Send STRING to the terminal."
  (interactive "sSend string: ")
  (kuro--send-key string))

;;;###autoload
(defun kuro-send-interrupt ()
  "Send SIGINT (C-c) to the terminal."
  (interactive)
  (kuro--send-key [?\C-c]))

;;;###autoload
(defun kuro-send-sigstop ()
  "Send SIGSTOP (C-z) to the terminal."
  (interactive)
  (kuro--send-key [?\C-z]))

;;;###autoload
(defun kuro-send-sigquit ()
  "Send SIGQUIT (C-\\) to the terminal."
  (interactive)
  (kuro--send-key [?\C-\\]))

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
    ;; Clean up blink overlays
    (remove-overlays (point-min) (point-max) 'kuro-blink t)
    (setq kuro--blink-overlays nil)
    ;; Clean up image overlays
    (kuro--clear-all-image-overlays)
    ;; Reset mouse state
    (setq kuro--mouse-mode 0)
    (setq kuro--mouse-sgr nil)
    (setq kuro--mouse-pixel-mode nil)
    ;; Reset scroll offset
    (setq kuro--scroll-offset 0)
    ;; Clean up font remap
    (when (and (boundp 'kuro--font-remap-cookie) kuro--font-remap-cookie)
      (face-remap-remove-relative kuro--font-remap-cookie)
      (setq kuro--font-remap-cookie nil))
    ;; Shutdown or detach the PTY session.
    ;; When the process is still alive, ask the user whether to destroy it or
    ;; leave it running in a detached state (re-attachable via `kuro-attach').
    ;; When the process has already exited (auto-kill path from the renderer),
    ;; skip the prompt and shut down immediately.
    (if (and kuro--initialized
             (kuro--is-process-alive)
             (not (yes-or-no-p "Kill the terminal process? (\"no\" detaches it) ")))
        ;; Detach: PTY keeps running; another buffer can attach later.
        (condition-case nil
            (progn
              (kuro-core-detach kuro--session-id)
              (setq kuro--initialized nil)
              (setq kuro--session-id 0))
          (error
           (setq kuro--initialized nil)
           (setq kuro--session-id 0)))
      ;; Destroy: shutdown PTY and remove session from the HashMap.
      (kuro--shutdown))
    (let ((buffer (current-buffer)))
      (kill-buffer buffer))))

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
      (with-current-buffer (get-buffer-create "*kuro-sessions*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert "Kuro Terminal Sessions\n")
          (insert "======================\n\n")
          (dolist (entry sessions)
            (let* ((id         (nth 0 entry))
                   (cmd        (nth 1 entry))
                   (detached-p (nth 2 entry))
                   (alive-p    (nth 3 entry))
                   (status     (cond (detached-p "detached")
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
      (condition-case err
          (let* ((rows (if noninteractive kuro--default-rows (window-body-height)))
                 (cols (if noninteractive kuro--default-cols (window-body-width)))
                 (inhibit-read-only t))
            (kuro-core-attach session-id)
            (setq kuro--session-id session-id)
            (setq kuro--initialized t)
            ;; Pre-fill with blank lines so `kuro--update-line-full' can reach any row.
            (erase-buffer)
            (dotimes (_ rows) (insert "\n"))
            (goto-char (point-min))
            (setq kuro--cursor-marker (point-marker))
            (setq kuro--last-rows rows)
            (setq kuro--last-cols cols)
            (setq kuro--scroll-offset 0)
            (kuro--set-scrollback-max-lines kuro-scrollback-size)
            (kuro--apply-font-to-buffer buffer)
            ;; Resize to match the new window — the detached PTY may have a
            ;; different geometry from when it was last attached.
            (kuro--resize rows cols)
            (kuro--start-render-loop)
            (message "Kuro: Attached to session %d" session-id))
        (error
         (message "Kuro: Failed to attach to session %d: %s" session-id err)
         ;; Clear buffer-local state immediately so that any hook or timer firing
         ;; before kill-buffer completes cannot observe kuro--initialized=t against
         ;; a Detached or never-attached session.
         (setq kuro--initialized nil)
         (setq kuro--session-id 0)
         ;; Roll back the Bound state so the session remains re-attachable.
         ;; If kuro-core-attach succeeded before the error (e.g. kuro--resize failed),
         ;; we must detach to prevent the session from being stranded as Bound with no buffer.
         ;; If kuro-core-attach itself failed, this detach call will error and be swallowed.
         (condition-case nil
             (kuro-core-detach session-id)
           (error nil))
         (kill-buffer buffer)
         nil)))
    buffer))

(provide 'kuro-lifecycle)

;;; kuro-lifecycle.el ends here
