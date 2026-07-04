;;; kuro-input-mode-edit.el --- Line-edit buffer commands for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Line-buffer editor for `kuro-input-mode'.  This file owns the dedicated
;; edit buffer, its state, and the send/discard commands.
;;
;; Loaded automatically via `kuro-input-mode-ext2'.  Do not require directly.

;;; Code:

(require 'kuro-config)
(require 'kuro-keymap)
(require 'kuro-input-mode-macros)

;; Functions defined in kuro-input-mode.el.
(declare-function kuro--line-set-buffer           "kuro-input-mode-line-state" (text))
(declare-function kuro--line-reset-state          "kuro-input-mode-line-state" ())
(declare-function kuro--line-suspend-state        "kuro-input-mode-line-display" ())
(declare-function kuro--schedule-immediate-render "kuro-input-render" ())
(declare-function kuro--send-key                  "kuro-ffi" (key))

;; Buffer-local variables forward-declared in kuro-input-mode.el.
(defvar kuro--line-buffer)
(defvar kuro--line-point)


;;;; Line buffer editor

(defvar-local kuro--line-edit-source-buffer nil
  "The `kuro-mode' buffer this line-edit buffer was spawned from.
Set by `kuro--line-edit-in-buffer' in the edit buffer.")

(defvar-local kuro--line-edit-original nil
  "The value of `kuro--line-buffer' at the time the edit buffer was opened.
Used by `kuro-line-edit-discard' to restore the terminal buffer's line state.")

(defvar kuro--line-edit-keymap
  (kuro--define-keymap
    ((kbd "C-c C-c") . kuro-line-edit-send)
    ((kbd "C-c C-k") . kuro-line-edit-discard))
  "Keymap installed in buffers created by `kuro--line-edit-in-buffer'.")

;;;###autoload
(define-derived-mode kuro-line-edit-mode text-mode "Kuro-Line-Edit"
  "Major mode for editing the current line-mode command in a full Emacs buffer.
Created by `kuro--line-edit-in-buffer' (\\[kuro--line-edit-in-buffer] in line mode).

The buffer holds the current line-mode accumulator.  Use any Emacs editing
commands such as `query-replace', abbrev expansion, or company-mode, then:

\\[kuro-line-edit-send]    — send the buffer contents as a command to the PTY
\\[kuro-line-edit-discard] — discard and restore the original line buffer"
  (setq buffer-read-only nil)
  (use-local-map (make-composed-keymap kuro--line-edit-keymap
                                       (current-local-map))))

;;;###autoload
(defun kuro--line-edit-in-buffer ()
  "Open the current line-mode accumulator in a full Emacs text buffer.
Creates a dedicated buffer named `*kuro-line-edit: <name>*' pre-filled with
the current `kuro--line-buffer'.  Full Emacs editing is available.

When done:
  \\[kuro-line-edit-send]    — send result as a command to the PTY
  \\[kuro-line-edit-discard] — restore original line buffer and close

Analogous to bash \\='s `edit-and-execute-command'."
  (interactive)
  (kuro--with-kuro-mode
   (let* ((source (current-buffer))
          (initial kuro--line-buffer)
          (edit-name (format "*kuro-line-edit: %s*" (buffer-name source)))
          (edit-buf (get-buffer-create edit-name)))
     (with-current-buffer edit-buf
       (kuro-line-edit-mode)
       (let ((inhibit-read-only t))
         (erase-buffer)
         (insert initial)
         (goto-char (point-max)))
       (setq kuro--line-edit-source-buffer source)
       (setq kuro--line-edit-original initial))
     (kuro--line-suspend-state)
     (switch-to-buffer edit-buf)
     (message "Kuro line edit — C-c C-c: send to PTY, C-c C-k: discard"))))

;;;###autoload
(defun kuro-line-edit-send ()
  "Send the line-edit buffer contents as a command to the source Kuro PTY.
The buffer text is sent with a trailing RET (as `kuro--line-commit' does)
and the edit buffer is killed.  Signals `user-error' when the source
Kuro buffer is no longer live."
  (interactive)
  (kuro--with-mode kuro-line-edit-mode "Not in a Kuro line-edit buffer"
    (let ((text   (buffer-string))
          (source kuro--line-edit-source-buffer))
      (unless (buffer-live-p source)
        (user-error "Source Kuro buffer no longer exists"))
      (kill-buffer (current-buffer))
      (with-current-buffer source
        (kuro--send-key (concat text "\r"))
        (kuro--schedule-immediate-render)
        (message "Kuro: line-edit command sent to PTY")))))

;;;###autoload
(defun kuro-line-edit-discard ()
  "Discard the line-edit buffer and restore the original line accumulator."
  (interactive)
  (let ((original kuro--line-edit-original)
        (source   kuro--line-edit-source-buffer))
    (kill-buffer (current-buffer))
    (when (buffer-live-p source)
      (with-current-buffer source
        (kuro--line-reset-state)
        (kuro--line-set-buffer (or original ""))))
    (message "Kuro: line-edit discarded")))

(provide 'kuro-input-mode-edit)
;;; kuro-input-mode-edit.el ends here
