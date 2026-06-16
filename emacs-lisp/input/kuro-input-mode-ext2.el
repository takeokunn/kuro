;;; kuro-input-mode-ext2.el --- Minibuffer send, line-edit, keymap, public commands  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Second extension of `kuro-input-mode'.  Split from `kuro-input-mode-ext'
;; to keep files under the 500-line policy.  Contains: minibuffer-send,
;; line-buffer editor, line-mode keymap builder, and public mode-switch
;; commands.
;;
;; Loaded automatically via `kuro-input-mode-ext'.  Do not require directly.

;;; Code:

(require 'kuro-config)
(require 'kuro-keymap)
(require 'kuro-input-mode-macros)

;; Functions defined in kuro-input-mode.el.
(declare-function kuro--line-mode-update-display "kuro-input-mode" ())
(declare-function kuro--line-clear-overlay        "kuro-input-mode" ())
(declare-function kuro--line-set-buffer           "kuro-input-mode" (s))
(declare-function kuro--schedule-immediate-render "kuro-input"      ())
(declare-function kuro--send-key                  "kuro-ffi"        (key))
(declare-function kuro--build-keymap              "kuro-input-keymap" ())

;; Buffer-local variables forward-declared in kuro-input-mode.el.
(defvar kuro--line-buffer)
(defvar kuro--line-point)
(defvar kuro--input-mode)
;; Keymap variables forward-declared in kuro-input-mode.el.
(defvar kuro--keymap)
(defvar kuro--char-keymap)
(defvar kuro-mode-map)


;;;; Line mode: minibuffer send

;;;###autoload
(defun kuro-line-minibuffer-send ()
  "Read a line via minibuffer and send it to the PTY.
Unlike the overlay accumulator, `read-from-minibuffer' fully supports
input methods (DDSKK, mozc, skk) because `input-method-function' fires
inside the minibuffer input loop before any keymap dispatch.  Command
history is accessible via \\[previous-history-element] /
\\[next-history-element].

The current `kuro--line-buffer' is used as the initial contents.
Canceling quits without sending; the line buffer is cleared in all cases
so no stale state accumulates.

Bound to \\[kuro-line-minibuffer-send] in line mode.  When
`kuro-line-use-minibuffer' is non-nil, every keypress auto-invokes this
function with the typed character pre-filled."
  (interactive)
  (kuro--with-kuro-mode
   (let ((initial kuro--line-buffer))
     (setq kuro--line-buffer "")
     (kuro--line-clear-overlay)
     (condition-case nil
         (let ((text (read-from-minibuffer "» " initial nil nil
                                           'kuro--line-history)))
           (kuro--send-key (concat text "\r"))
           (kuro--schedule-immediate-render))
       (quit nil)))))


;;;; Line buffer editor — C-x C-e opens line buffer in a full Emacs text buffer

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
     (setq kuro--line-buffer "")
     (setq kuro--line-point 0)
     (kuro--line-clear-overlay)
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
        (kuro--line-set-buffer (or original ""))))
    (message "Kuro: line-edit discarded")))


;;;; Line mode keymap

(defvar kuro--line-mode-keymap nil
  "Keymap active in Kuro line mode.
Inherits from `kuro--keymap' (semi-char) but overrides self-insert, RET,
delete/backspace, line kill, and cancel to operate on the local line
buffer instead of forwarding to the PTY.")

(defconst kuro--line-mode-bindings
  '(;; commit / abort / newline
    ("C-m"     . kuro--line-commit)         ("C-j"     . kuro--line-commit)
    ("C-o"     . kuro--line-newline)        ("C-g"     . kuro--line-abort)
    ;; delete
    ("DEL"     . kuro--line-delete)         ("C-h"     . kuro--line-delete)
    ("C-k"     . kuro--line-kill-line)      ("C-d"     . kuro--line-delete-char)
    ("C-u"     . kuro--line-kill-to-bol)    ("C-w"     . kuro--line-unix-word-rubout)
    ;; movement
    ("C-a"     . kuro--line-beginning-of-line) ("C-e"  . kuro--line-end-of-line)
    ("C-f"     . kuro--line-forward-char)   ("C-b"     . kuro--line-backward-char)
    ("M-f"     . kuro--line-forward-word)   ("M-b"     . kuro--line-backward-word)
    ;; word operations
    ("M-d"     . kuro--line-kill-word)      ("M-DEL"   . kuro--line-backward-kill-word)
    ("M-u"     . kuro--line-upcase-word)    ("M-l"     . kuro--line-downcase-word)
    ("M-c"     . kuro--line-capitalize-word) ("M-t"    . kuro--line-transpose-words)
    ;; misc editing
    ("C-t"     . kuro--line-transpose-chars) ("C-q"   . kuro--line-quoted-insert)
    ("C-/"     . kuro--line-undo)           ("C-_"     . kuro--line-undo)
    ("C-y"     . kuro--line-yank)           ("M-y"     . kuro--line-yank-pop)
    ("M-."     . kuro--line-yank-last-arg)  ("M-_"     . kuro--line-yank-last-arg)
    ;; history navigation
    ("M-p"     . kuro--line-history-prev)   ("M-n"     . kuro--line-history-next)
    ("C-p"     . kuro--line-history-prev)   ("C-n"     . kuro--line-history-next)
    ("M-<"     . kuro--line-goto-history-oldest) ("M->" . kuro--line-goto-history-newest)
    ;; completion / search / abbrev
    ("TAB"     . kuro--line-complete)       ("M-/"     . kuro--line-complete-history)
    ("C-r"     . kuro--line-history-search) ("C-c C-r" . kuro-line-minibuffer-send)
    ("M-SPC"   . kuro--line-expand-abbrev)  ("C-x C-e" . kuro--line-edit-in-buffer))
  "Key→command binding table for `kuro--line-mode-keymap'.
Vector-keyed special bindings ([remap self-insert-command], [return],
[backspace]) are installed directly in `kuro--build-line-mode-keymap'.")

(defun kuro--build-line-mode-keymap ()
  "Build `kuro--line-mode-keymap' from `kuro--keymap'.
Must be called after `kuro--build-keymap' so the parent is up to date."
  (let ((map (kuro--build-keymap-from-alist kuro--line-mode-bindings
                                            (lambda (binding)
                                              (kbd (car binding)))
                                            #'cdr
                                            kuro--keymap)))
    (define-key map [remap self-insert-command] #'kuro--line-self-insert)
    (define-key map [return]    #'kuro--line-commit)
    (define-key map [backspace] #'kuro--line-delete)
    (setq kuro--line-mode-keymap map)
    map))


;;;; Keymap application

(defconst kuro--input-mode-keymaps
  '((char      . kuro--char-keymap)
    (semi-char . kuro--keymap))
  "Alist mapping non-line input modes to their parent keymap variables.
Used by `kuro--apply-input-mode' to install the correct keymap for each
mode.
Line mode is absent: it uses a composed keymap via
`kuro--build-line-mode-keymap'.")

(defun kuro--apply-input-mode ()
  "Update the current buffer's effective keymap for `kuro--input-mode'.
Sets `kuro-mode-map' parent to:
  `char'      → `kuro--char-keymap'  (all keys bound)
  `semi-char' → `kuro--keymap'       (exceptions removed)
  `line'      → `kuro--line-mode-keymap' as a composed local map
The mode-line is updated after every switch."
  (if-let* ((entry (assq kuro--input-mode kuro--input-mode-keymaps)))
      (progn
        (set-keymap-parent kuro-mode-map (symbol-value (cdr entry)))
        (use-local-map kuro-mode-map))
    ;; Line mode: compose line-mode overrides on top of kuro-mode-map's C-c bindings
    (kuro--build-line-mode-keymap)
    (use-local-map (make-composed-keymap kuro--line-mode-keymap kuro-mode-map)))
  (force-mode-line-update))


;;;; Public commands

(defmacro kuro--def-input-mode (name mode message &rest pre-apply)
  "Define NAME as a Kuro input-mode switch command.
MODE is the mode symbol to set.  MESSAGE is shown after switching.
PRE-APPLY forms run between the buffer reset and `kuro--apply-input-mode'."
  `(defun ,name ()
     ,(format "Switch the current Kuro buffer to %s mode." mode)
     (interactive)
     (kuro--with-kuro-mode
      (setq kuro--input-mode ',mode
            kuro--line-buffer "")
      ,@pre-apply
      (kuro--apply-input-mode)
      (message ,message))))

;;;###autoload
(kuro--def-input-mode kuro-char-mode char
  "Kuro: char mode — all keys forwarded to PTY"
  (kuro--line-clear-overlay))

;;;###autoload
(kuro--def-input-mode kuro-semi-char-mode semi-char
  "Kuro: semi-char mode — exception keys pass through to Emacs"
  (kuro--line-clear-overlay))

;;;###autoload
(kuro--def-input-mode kuro-line-mode line
  "Kuro: line mode — type locally, RET sends, C-g cancels"
  (kuro--line-mode-update-display))

(defconst kuro--input-mode-cycle-table
  '((semi-char . kuro-char-mode)
    (char      . kuro-line-mode)
    (line      . kuro-semi-char-mode))
  "Alist mapping the current input mode to the command that activates the next one.
The cycle is: semi-char → char → line → semi-char.
Used by `kuro-cycle-input-mode'.")

;;;###autoload
(defun kuro-cycle-input-mode ()
  "Cycle through Kuro input modes: semi-char → char → line → semi-char.
Provides a quick one-key way to switch without remembering three commands."
  (interactive)
  (kuro--with-kuro-mode
   (funcall (or (cdr (assq kuro--input-mode kuro--input-mode-cycle-table))
                #'kuro-semi-char-mode))))

(provide 'kuro-input-mode-ext2)
;;; kuro-input-mode-ext2.el ends here
