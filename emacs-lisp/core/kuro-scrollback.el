;;; kuro-scrollback.el --- Scrollback editing for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Writable scrollback snapshots for editing terminal output with normal
;; Emacs commands, then sending the edited text back to the PTY.

;;; Code:

(require 'kuro-config)
(require 'kuro-keymap)

;; Used by `kuro-scrollback-send'.
(declare-function kuro--send-paste-or-raw "kuro-input-paste" (text))
(declare-function kuro--schedule-immediate-render "kuro-input-render" ())

(defvar-local kuro-edit-scrollback--source-buffer nil
  "The `kuro-mode' buffer this scrollback snapshot was created from.
Set by `kuro-edit-scrollback' in the snapshot buffer.")

(defvar kuro--scrollback-edit-keymap
  (kuro--define-keymap
    ("C-c C-c" . kuro-scrollback-send)
    ("C-c C-k" . kuro-scrollback-discard))
  "Keymap installed in buffers created by `kuro-edit-scrollback'.")

;;;###autoload
(define-derived-mode kuro-scrollback-edit-mode text-mode "Kuro-Edit"
  "Major mode for editing a writable snapshot of Kuro terminal output.
Created by `kuro-edit-scrollback'.

The buffer holds a verbatim copy of the terminal content at the time
the snapshot was taken.  All Emacs editing commands apply: `isearch',
`query-replace', `string-rectangle', `delete-rectangle', `swiper',
and similar extended commands.

\\[kuro-scrollback-send]    - send entire buffer to the PTY and close
\\[kuro-scrollback-discard] - discard edits and close this buffer"
  (setq buffer-read-only nil)
  (use-local-map (make-composed-keymap kuro--scrollback-edit-keymap
                                       (current-local-map))))

;;;###autoload
(defun kuro-edit-scrollback ()
  "Open a writable snapshot of the terminal scrollback buffer for editing.
Creates a dedicated buffer named `*kuro-scrollback: <name>*' containing
the current terminal content.  The snapshot is fully editable: apply
`query-replace', `string-rectangle', `occur', `isearch', or any other
Emacs command freely.

When done:
  \\[kuro-scrollback-send]    - send the result to the PTY (C-c C-c)
  \\[kuro-scrollback-discard] - discard without sending   (C-c C-k)

The original terminal buffer is not modified; the PTY continues to run."
  (interactive)
  (kuro--with-kuro-mode
   (let* ((source (current-buffer))
          (snap-name (format "*kuro-scrollback: %s*" (buffer-name source)))
          (snap (get-buffer-create snap-name)))
     (with-current-buffer snap
       (kuro-scrollback-edit-mode)
       (let ((inhibit-read-only t))
         (erase-buffer)
         (insert-buffer-substring source))
       (setq kuro-edit-scrollback--source-buffer source)
       (goto-char (point-min)))
     (switch-to-buffer snap)
     (message "Kuro scrollback edit - C-c C-c: send to PTY, C-c C-k: discard"))))

;;;###autoload
(defun kuro-scrollback-send ()
  "Send the snapshot buffer contents to the source Kuro PTY and close.
The entire buffer is sent via the Rust paste API, which reads the
target terminal's current mode 2004 state at send time.
Signals `user-error' when the source buffer no longer exists."
  (interactive)
  (kuro--with-mode kuro-scrollback-edit-mode "Not in a Kuro scrollback edit buffer"
    (let ((text (buffer-string))
          (source kuro-edit-scrollback--source-buffer))
      (unless (buffer-live-p source)
        (user-error "Source Kuro buffer no longer exists"))
      (kill-buffer (current-buffer))
      (with-current-buffer source
        (kuro--send-paste-or-raw text)
        (kuro--schedule-immediate-render)
        (message "kuro: scrollback content sent to PTY")))))

;;;###autoload
(defun kuro-scrollback-discard ()
  "Discard the scrollback snapshot without sending to the PTY."
  (interactive)
  (kill-buffer (current-buffer))
  (message "kuro: scrollback snapshot discarded"))

(provide 'kuro-scrollback)
;;; kuro-scrollback.el ends here
