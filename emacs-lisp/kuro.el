;;; kuro.el --- Main entry point for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: terminal, tools

;;; Commentary:

;; Kuro is a modern terminal emulator for Emacs using a Rust core and
;; Emacs Lisp UI. It implements the Remote Display Model where all
;; terminal state is managed in Rust and Emacs is purely a display layer.

;; Usage:
;; (require 'kuro)
;; (kuro-create "bash")

;;; Code:

(require 'kuro-module)
(require 'kuro-ffi)
(require 'kuro-renderer)
(require 'kuro-input)

(defgroup kuro nil
  "Kuro terminal emulator."
  :group 'terminal
  :prefix 'kuro-)

(defcustom kuro-default-shell "/bin/zsh"
  "Default shell command to run."
  :type 'string
  :group 'kuro)

(defcustom kuro-scrollback-size 10000
  "Maximum scrollback buffer size (lines)."
  :type 'integer
  :group 'kuro)

(defvar kuro-mode-map
  (let ((map (make-sparse-keymap)))
    ;; Terminal keybindings should pass through
    (define-key map [?\C-c ?\C-c] 'kuro-send-interrupt)
    (define-key map [?\C-c ?\C-z] 'kuro-send-sigstop)
    (define-key map [?\C-c ?\C-\\] 'kuro-send-sigquit)
    map)
  "Keymap for Kuro major mode.")

(define-derived-mode kuro-mode fundamental-mode "Kuro"
  "Major mode for Kuro terminal buffers."
  (setq buffer-read-only t)
  (setq-local bidi-display-reordering nil)
  (setq-local truncate-lines t)
  (unless noninteractive
    (cursor-intangible-mode 1))
  (setq-local show-trailing-whitespace nil)
  ;; Install terminal input keymap as parent so all key presses reach the PTY
  (set-keymap-parent kuro-mode-map kuro--keymap))

;;;###autoload
(defun kuro-create (&optional command buffer-name)
  "Create a new Kuro terminal instance running COMMAND.
If COMMAND is nil, use `kuro-default-shell'.
BUFFER-NAME is the name for the new buffer.
Switches to the terminal buffer after creation."
  (interactive
   (list
    (read-string "Shell command: " kuro-default-shell)
    (generate-new-buffer-name "*kuro*")))
  (let* ((cmd (or command kuro-default-shell))
         (buffer (get-buffer-create (or buffer-name (generate-new-buffer-name "*kuro*")))))
    (with-current-buffer buffer
      (kuro-mode)
      (when (kuro--init cmd)
        (setq kuro--cursor-marker (point-marker))
        (kuro--start-render-loop)
        (message "Kuro: Started terminal with command: %s" cmd)))
    (unless noninteractive
      (switch-to-buffer buffer))
    ;; Sync actual window dimensions to the terminal after buffer is displayed
    (let ((rows (if noninteractive 24 (window-body-height)))
          (cols (if noninteractive 80 (window-body-width))))
      (kuro--resize rows cols))
    buffer))

;;;###autoload
(defun kuro-send-string (string)
  "Send STRING to the terminal."
  (interactive "sSend string: ")
  (let ((bytes (vconcat (mapcar #'identity string))))
    (kuro--send-key bytes)))

(defun kuro-send-interrupt ()
  "Send SIGINT (C-c) to the terminal."
  (interactive)
  (kuro--send-key [?\C-c]))

(defun kuro-send-sigstop ()
  "Send SIGSTOP (C-z) to the terminal."
  (interactive)
  (kuro--send-key [?\C-z]))

(defun kuro-send-sigquit ()
  "Send SIGQUIT (C-\\) to the terminal."
  (interactive)
  (kuro--send-key [?\C-\\]))

(defun kuro-kill ()
  "Kill the current Kuro terminal."
  (interactive)
  (when (derived-mode-p 'kuro-mode)
    (kuro--stop-render-loop)
    (kuro--shutdown)
    (let ((buffer (current-buffer)))
      (kill-buffer buffer))))

(provide 'kuro)

;;; kuro.el ends here
