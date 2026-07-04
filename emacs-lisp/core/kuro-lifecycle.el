;;; kuro-lifecycle.el --- Terminal lifecycle management for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; This file provides terminal lifecycle management for Kuro.
;;
;; # Responsibilities
;;
;; - Terminal creation: `kuro-create'
;; - Terminal teardown: `kuro-kill' (destroy or detach)
;; - Session re-attachment: `kuro-attach'
;; - Interactive send commands: `kuro-send-string', `kuro-send-region',
;;   `kuro-send-interrupt', `kuro-send-sigstop', `kuro-send-sigquit'

;;; Code:

(require 'kuro-ffi)
(require 'kuro-renderer)
(require 'kuro-faces)
(require 'kuro-render-buffer)
(require 'kuro-dnd)
(require 'kuro-compilation)
(require 'kuro-bookmark)
(require 'kuro-color-scheme)
(require 'kuro-sessions)
(require 'kuro-lifecycle-module)
(require 'kuro-lifecycle-macros)

;; Forward-declare functions defined in kuro.el to avoid circular require
(declare-function kuro-mode "kuro" ())

;; Forward-declare render loop functions defined in kuro-renderer.el
(declare-function kuro--render-cycle      "kuro-renderer" ())
(declare-function kuro--start-render-loop "kuro-renderer" ())
(declare-function kuro--stop-render-loop  "kuro-renderer" ())

;; face-remap-remove-relative is provided by the C core (face-remap.el)
(declare-function face-remap-remove-relative "face-remap" (cookie))

;; kuro-bookmark.el
(declare-function kuro--setup-bookmark "kuro-bookmark" ())

;; kuro-char-width.el
(declare-function kuro--setup-char-width-table "kuro-char-width" ())
(declare-function kuro--setup-fontset          "kuro-char-width" ())

;; kuro-color-scheme.el
(declare-function kuro--color-scheme-install-hook   "kuro-color-scheme" ())
(declare-function kuro--color-scheme-uninstall-hook "kuro-color-scheme" ())
(declare-function kuro-color-scheme-refresh         "kuro-color-scheme" ())

;; kuro-compilation.el
(declare-function kuro--setup-compilation    "kuro-compilation" ())
(declare-function kuro--teardown-compilation "kuro-compilation" ())

;; kuro-config.el
(declare-function kuro--kuro-buffers "kuro-config" ())

;; kuro-dnd.el
(declare-function kuro--setup-dnd    "kuro-dnd" ())
(declare-function kuro--teardown-dnd "kuro-dnd" ())

;; kuro-input-paste.el — used by kuro-send-region
(declare-function kuro--send-paste-or-raw        "kuro-input-paste" (text))
(declare-function kuro--schedule-immediate-render "kuro-input-render" ())

;; kuro-faces.el
(declare-function kuro--apply-font-to-buffer "kuro-faces" (buf))
(declare-function kuro--remap-default-face   "kuro-faces" (fg-str bg-str))

;; kuro-ffi.el
(declare-function kuro--resize "kuro-ffi" (rows cols))

;; kuro-ffi-osc.el
(declare-function kuro--set-scrollback-max-lines "kuro-ffi-osc" (max-lines))

;; kuro-hyperlinks.el
(declare-function kuro--clear-hyperlink-overlays "kuro-hyperlinks" ())

;; kuro-overlays.el
(declare-function kuro--clear-all-image-overlays "kuro-overlays" ())

;; kuro-prompt-status.el
(declare-function kuro--ensure-left-margin           "kuro-prompt-status" ())
(declare-function kuro--clear-prompt-status-overlays "kuro-prompt-status" ())

;; kuro-core Rust FFI functions (loaded at runtime by the dynamic module)
(declare-function kuro-core-detach        "ext:kuro-core" (session-id))
(declare-function kuro-core-attach        "ext:kuro-core" (session-id))
(declare-function kuro-core-list-sessions "ext:kuro-core" ())

;;; Forward defvar references — defvar-local symbols used here but defined elsewhere

;; kuro-config.el
(defvar kuro-shell-integration)

;; kuro-faces.el
(defvar kuro--font-remap-cookie nil
  "Forward reference; `defvar-local' in kuro-faces.el.")

;; kuro-input.el
(defvar kuro--scroll-offset 0
  "Forward reference; `defvar-local' in kuro-input.el.")

;; kuro-input-mouse.el
(defvar kuro--mouse-pixel-mode nil
  "Forward reference; `defvar-local' in kuro-input-mouse.el.")
(defvar kuro--mouse-mode 0
  "Forward reference; `defvar-local' in kuro-input-mouse.el.")
(defvar kuro--mouse-sgr nil
  "Forward reference; `defvar-local' in kuro-input-mouse.el.")

;; kuro-overlays.el
(defvar kuro--blink-overlays nil
  "Forward reference; `defvar-local' in kuro-overlays.el.")
(defvar kuro--blink-overlays-slow nil
  "Forward reference; `defvar-local' in kuro-overlays.el.")
(defvar kuro--blink-overlays-fast nil
  "Forward reference; `defvar-local' in kuro-overlays.el.")

;; kuro-render-buffer.el
(defvar kuro--last-cursor-row nil
  "Forward reference; `defvar-local' in kuro-render-buffer.el.")
(defvar kuro--last-cursor-col nil
  "Forward reference; `defvar-local' in kuro-render-buffer.el.")
(defvar kuro--last-cursor-visible nil
  "Forward reference; `defvar-local' in kuro-render-buffer.el.")
(defvar kuro--last-cursor-shape nil
  "Forward reference; `defvar-local' in kuro-render-buffer.el.")

;; kuro-renderer.el
(defvar kuro--cursor-marker nil
  "Forward reference; `defvar-local' in kuro-renderer.el.")

;; kuro-tui-mode.el
(defvar kuro--tui-mode-active nil
  "Forward reference; defvar-permanent-local in kuro-tui-mode.el.")
(defvar kuro--tui-mode-frame-count 0
  "Forward reference; defvar-permanent-local in kuro-tui-mode.el.")
(defvar kuro--last-dirty-count 0
  "Forward reference; defvar-permanent-local in kuro-tui-mode.el.")

;; kuro.el
(defvar kuro--last-rows 0
  "Forward reference; `defvar-local' in kuro.el.")
(defvar kuro--last-cols 0
  "Forward reference; `defvar-local' in kuro.el.")

(defconst kuro--startup-render-delay 0.05
  "Delay in seconds before the first render after terminal startup.")

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

(defun kuro--initialize-session-buffer (buffer rows cols)
  "Prepare BUFFER for a session display with ROWS x COLS dimensions."
  (with-current-buffer buffer
    (let ((inhibit-read-only t))
      (kuro--prefill-buffer rows))
    (kuro--init-session-buffer buffer rows cols)))

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
      (kuro--initialize-session-buffer buffer rows cols)
      (kuro--setup-shell-integration-env)
      (when (kuro--init command nil rows cols)
        (kuro--start-render-loop)
        (kuro--schedule-initial-render buffer)
        (message "Kuro: Started terminal with command: %s" command))))
  buffer)

(defun kuro--do-attach (session-id rows cols)
  "Perform the core attach step for SESSION-ID at terminal size ROWS x COLS.
Assume the calling buffer is already in `kuro-mode'.
Signals on any failure; the caller is responsible for rollback."
  (let ((inhibit-read-only t))
    (kuro-core-attach session-id)
    (setq kuro--session-id session-id
          kuro--initialized t)
    (kuro--initialize-session-buffer (current-buffer) rows cols)
    (kuro--resize rows cols)
    (kuro--start-render-loop)))

(defun kuro--rollback-attach (session-id buffer err)
  "Roll back a failed attach for SESSION-ID.
Log ERR, clear state, detach, and kill BUFFER."
  (message "Kuro: Failed to attach to session %d: %s" session-id err)
  (kuro--detach-and-clear-session-state session-id)
  (kill-buffer buffer)
  nil)

(defun kuro--teardown-session ()
  "Detach or destroy the current session, prompting if the process is alive.
Detached sessions remain reattachable via `kuro-attach'.
Assumes `kuro--stop-render-loop' and `kuro--cleanup-render-state' already ran."
  (if (and kuro--initialized
           (kuro--is-process-alive)
           (not (yes-or-no-p "Kill the terminal process? (\"no\" detaches it)? ")))
      ;; Detach: PTY keeps running; another buffer can attach later.
      (kuro--detach-and-clear-session-state kuro--session-id)
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

(defconst kuro--session-setup-fns
  '(kuro--setup-char-width-table
    kuro--setup-fontset
    kuro--ensure-left-margin
    kuro--setup-dnd
    kuro--setup-compilation
    kuro--setup-bookmark
    kuro--color-scheme-install-hook)
  "Zero-argument setup functions called in each new session buffer.
Run by `kuro--init-session-buffer' after the arg-based initializations.
Does not include `kuro--reset-cursor-cache' because it is a macro.")

(defun kuro--init-session-buffer (buffer rows cols)
  "Initialize BUFFER as a kuro session display with dimensions ROWS×COLS."
  (with-current-buffer buffer
    (setq kuro--cursor-marker (point-marker)
          kuro--last-rows     rows
          kuro--last-cols     cols
          kuro--scroll-offset 0)
    (kuro--set-scrollback-max-lines kuro-scrollback-size)
    (kuro--apply-font-to-buffer buffer)
    (kuro--remap-default-face kuro-color-white kuro-color-black)
    (kuro--reset-cursor-cache)
    (kuro--run-session-setup-fns)
    (ignore-errors (kuro-color-scheme-refresh))))

(require 'kuro-lifecycle-commands)

(provide 'kuro-lifecycle)
;;; kuro-lifecycle.el ends here
