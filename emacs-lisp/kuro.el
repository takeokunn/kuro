;;; kuro.el --- Main entry point for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn <takeokunn@users.noreply.github.com>
;; URL: https://github.com/takeokunn/kuro
;; Version: 1.0.0
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
(kuro-module-load)
(require 'kuro-config)
(require 'kuro-ffi)
(require 'kuro-faces)
(require 'kuro-overlays)
(require 'kuro-input)
(require 'kuro-stream)
(require 'kuro-renderer)

;; face-remap-remove-relative is provided by the C core (face-remap.el);
;; declare it to suppress byte-compiler warnings in kuro-kill.
(declare-function face-remap-remove-relative "face-remap" (cookie))

(defvar kuro-mode-map
  (let ((map (make-sparse-keymap)))
    ;; Terminal keybindings should pass through
    (define-key map [?\C-c ?\C-c] 'kuro-send-interrupt)
    (define-key map [?\C-c ?\C-z] 'kuro-send-sigstop)
    (define-key map [?\C-c ?\C-\\] 'kuro-send-sigquit)
    ;; Prompt navigation (OSC 133)
    (define-key map [?\C-c ?\C-p] #'kuro-previous-prompt)
    (define-key map [?\C-c ?\C-n] #'kuro-next-prompt)
    map)
  "Keymap for Kuro major mode.")

(defun kuro--window-size-change (frame)
  "Handle window size changes for kuro buffers in FRAME.
Called from `window-size-change-functions'.  For every kuro buffer
whose window dimensions changed, resizes the PTY to match and
pre-fills/trims the buffer to the new row count so kuro--update-line
can always navigate to any row without hitting end-of-buffer."
  (dolist (win (window-list frame))
    (let ((buf (window-buffer win)))
      (when (and (buffer-live-p buf)
                 (with-current-buffer buf (derived-mode-p 'kuro-mode)))
        (with-current-buffer buf
          (let ((new-rows (window-body-height win))
                (new-cols (window-body-width win)))
            (when (and kuro--initialized
                       (or (/= new-rows kuro--last-rows)
                           (/= new-cols kuro--last-cols)))
              ;; Resize PTY first so SIGWINCH delivers the new size.
              (kuro--resize new-rows new-cols)
              (setq kuro--last-rows new-rows
                    kuro--last-cols new-cols)
              ;; Adjust the buffer line count to match.
              (let ((inhibit-read-only t)
                    (current-rows (count-lines (point-min) (point-max))))
                (cond
                 ((< current-rows new-rows)
                  ;; Add missing blank lines at the end.
                  (save-excursion
                    (goto-char (point-max))
                    (dotimes (_ (- new-rows current-rows))
                      (insert "\n"))))
                 ((> current-rows new-rows)
                  ;; Remove excess lines from the end (they will be blank).
                  (save-excursion
                    (goto-char (point-max))
                    (dotimes (_ (- current-rows new-rows))
                      (when (> (point) (point-min))
                        (forward-line -1)
                        (delete-region (line-end-position) (point-max))))))
                 )))))))))

(defvar-local kuro--last-rows 0
  "Last known terminal row count; used to detect window size changes.")
(put 'kuro--last-rows 'permanent-local t)

(defvar-local kuro--last-cols 0
  "Last known terminal column count; used to detect window size changes.")
(put 'kuro--last-cols 'permanent-local t)

(define-derived-mode kuro-mode fundamental-mode "Kuro"
  "Major mode for Kuro terminal buffers."
  (setq buffer-read-only t)
  (setq-local bidi-display-reordering nil)
  (setq-local truncate-lines t)
  ;; Do NOT enable cursor-intangible-mode: it interferes with set-window-point
  ;; (which we use to track the terminal cursor), causing the visual cursor to
  ;; jump unexpectedly.  vterm and eshell do not use cursor-intangible-mode either.
  (setq-local show-trailing-whitespace nil)
  ;; Disable undo in terminal buffers.  Every render cycle replaces line content
  ;; via delete-region + insert (up to N*2 operations/frame); without this, the
  ;; undo ring grows unboundedly and `undo-boundary' calls inside buffer operations
  ;; add measurable overhead to every redraw tick.
  (buffer-disable-undo)
  ;; Install terminal input keymap as parent so all key presses reach the PTY
  (set-keymap-parent kuro-mode-map kuro--keymap)
  ;; Focus event reporting (mode 1004): forward Emacs focus events to PTY.
  ;; Use after-focus-change-function (Emacs 27+) instead of the obsolete
  ;; focus-in-hook / focus-out-hook hooks.  after-focus-change-function
  ;; is a plain function (not a hook), so we wrap it to preserve any
  ;; existing handler.
  (when (boundp 'after-focus-change-function)
    (let ((prev after-focus-change-function))
      (setq-local after-focus-change-function
                  (lambda ()
                    (if (frame-focus-state)
                        (kuro--handle-focus-in)
                      (kuro--handle-focus-out))
                    (when (functionp prev) (funcall prev)))))
    ;; Remove the obsolete hooks so byte-compiler warnings don't appear.
    ;; This branch is taken on Emacs 27+.
    )
  ;; Resize the PTY whenever the Emacs window size changes.
  (add-hook 'window-size-change-functions #'kuro--window-size-change))

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
  (let* ((cmd (or command kuro-shell))
         (buffer (get-buffer-create (or buffer-name (generate-new-buffer-name "*kuro*")))))
    ;; Display the buffer FIRST so window-body-height/width reflect the real window.
    ;; We need exact dimensions before spawning the PTY; otherwise the shell starts
    ;; with hardcoded 24×80 and full-screen programs (vim, htop, …) that run before
    ;; the resize SIGWINCH arrives will lay out their UI with the wrong geometry.
    (unless noninteractive
      (switch-to-buffer buffer))
    (let ((rows (if noninteractive 24 (window-body-height)))
          (cols (if noninteractive 80 (window-body-width))))
      (with-current-buffer buffer
        (kuro-mode)
        ;; Pre-fill with blank lines so kuro--update-line can navigate via
        ;; forward-line to any row without hitting end-of-buffer.
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
          (run-with-idle-timer 0.05 nil
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
    ;; Clean up blink overlays
    (remove-overlays (point-min) (point-max) 'kuro-blink t)
    (setq kuro--blink-overlays nil)
    ;; Reset mouse state
    (setq kuro--mouse-mode 0)
    (setq kuro--mouse-sgr nil)
    ;; Reset scroll offset
    (setq kuro--scroll-offset 0)
    ;; Clean up font remap
    (when (and (boundp 'kuro--font-remap-cookie) kuro--font-remap-cookie)
      (face-remap-remove-relative kuro--font-remap-cookie)
      (setq kuro--font-remap-cookie nil))
    (kuro--shutdown)
    (let ((buffer (current-buffer)))
      (kill-buffer buffer))))

(provide 'kuro)

;;; kuro.el ends here
