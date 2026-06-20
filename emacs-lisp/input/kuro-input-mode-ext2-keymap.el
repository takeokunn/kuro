;;; kuro-input-mode-ext2-keymap.el --- Keymap helpers for kuro-input-mode-ext2  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Internal keymap resolution, construction, and installation helpers for
;; `kuro-input-mode-ext2'.  Keep the public mode-switch commands in
;; `kuro-input-mode-ext2-mode.el' so this file owns the implementation detail
;; boundary.

;;; Code:

(require 'kuro-keymap)
(require 'kuro-keymap-macros)
(require 'kuro-input-mode-ext2-data)

;; Functions used as keymap targets.  They are defined across the line-mode
;; helper modules that load alongside this file.
(declare-function kuro--line-self-insert "kuro-input-mode-line" ())
(declare-function kuro--line-commit "kuro-input-mode-line" ())
(declare-function kuro--line-delete "kuro-input-mode-line" ())
(declare-function kuro--line-newline "kuro-input-mode-line" ())
(declare-function kuro--line-abort "kuro-input-mode-line" ())
(declare-function kuro--line-kill-line "kuro-input-mode-line" ())
(declare-function kuro--line-delete-char "kuro-input-mode-line-ops" ())
(declare-function kuro--line-kill-to-bol "kuro-input-mode-line-ops" ())
(declare-function kuro--line-unix-word-rubout "kuro-input-mode-line-ops" ())
(declare-function kuro--line-beginning-of-line "kuro-input-mode-line-nav" ())
(declare-function kuro--line-end-of-line "kuro-input-mode-line-nav" ())
(declare-function kuro--line-forward-char "kuro-input-mode-line-nav" ())
(declare-function kuro--line-backward-char "kuro-input-mode-line-nav" ())
(declare-function kuro--line-forward-word "kuro-input-mode-line-nav" ())
(declare-function kuro--line-backward-word "kuro-input-mode-line-nav" ())
(declare-function kuro--line-kill-word "kuro-input-mode-line-ops" ())
(declare-function kuro--line-backward-kill-word "kuro-input-mode-line-ops" ())
(declare-function kuro--line-upcase-word "kuro-input-mode-transform" ())
(declare-function kuro--line-downcase-word "kuro-input-mode-transform" ())
(declare-function kuro--line-capitalize-word "kuro-input-mode-transform" ())
(declare-function kuro--line-transpose-words "kuro-input-mode-transform" ())
(declare-function kuro--line-transpose-chars "kuro-input-mode-line-ops" ())
(declare-function kuro--line-quoted-insert "kuro-input-mode-line" ())
(declare-function kuro--line-undo "kuro-input-mode-line" ())
(declare-function kuro--line-yank "kuro-input-mode-yank" ())
(declare-function kuro--line-yank-pop "kuro-input-mode-yank" ())
(declare-function kuro--line-yank-last-arg "kuro-input-mode-yank" ())
(declare-function kuro--line-history-prev "kuro-input-mode-history-nav" ())
(declare-function kuro--line-history-next "kuro-input-mode-history-nav" ())
(declare-function kuro--line-goto-history-oldest "kuro-input-mode-history-nav" ())
(declare-function kuro--line-goto-history-newest "kuro-input-mode-history-nav" ())
(declare-function kuro--line-complete "kuro-input-mode-completion" ())
(declare-function kuro--line-complete-history "kuro-input-mode-completion" ())
(declare-function kuro--line-history-search "kuro-input-mode-completion" ())
(declare-function kuro--line-expand-abbrev "kuro-input-mode-completion" ())
(declare-function kuro-line-minibuffer-send "kuro-input-mode-ext2-send" ())
(declare-function kuro--line-edit-in-buffer "kuro-input-mode-edit" ())

;; Buffer-local variables forward-declared in kuro-input-mode.el.
(defvar kuro--line-buffer)
(defvar kuro--line-point)
(defvar kuro--input-mode)
;; Keymap variables forward-declared in kuro-input-mode.el.
(defvar kuro--keymap)
(defvar kuro--char-keymap)
(defvar kuro-mode-map)

(defvar kuro--line-mode-keymap nil
  "Keymap active in Kuro line mode.
Inherits from `kuro--keymap' (semi-char) but overrides self-insert, RET,
delete/backspace, line kill, and cancel to operate on the local line
buffer instead of forwarding to the PTY.")

(defun kuro--resolve-keymap (keymap)
  "Return KEYMAP as a keymap value, resolving symbols when needed."
  (cond
   ((keymapp keymap) keymap)
   ((and (symbolp keymap) (boundp keymap))
    (let ((value (symbol-value keymap)))
      (if (keymapp value)
          value
        (error "Kuro: `%s' does not name a keymap" keymap))))
   (t (error "Kuro: `%s' does not name a keymap" keymap))))

(defun kuro--build-line-mode-keymap ()
  "Build `kuro--line-mode-keymap' from `kuro--keymap'.
Must be called after `kuro--build-keymap' so the parent is up to date."
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map (kuro--resolve-keymap kuro--keymap))
    (define-key map [remap self-insert-command] #'kuro--line-self-insert)
    (define-key map [return] #'kuro--line-commit)
    (define-key map [backspace] #'kuro--line-delete)
    (kuro--define-key-bindings map kuro--line-mode-bindings
      (lambda (binding) (kbd (car binding)))
      #'cdr)
    (setq kuro--line-mode-keymap map)
    map))

(defun kuro--install-input-mode-keymap ()
  "Install the effective keymap for `kuro--input-mode'."
  (let ((parent (cdr (assq kuro--input-mode kuro--input-mode-keymaps))))
    (if parent
        (progn
          (set-keymap-parent kuro-mode-map (kuro--resolve-keymap parent))
          (use-local-map kuro-mode-map))
      (kuro--build-line-mode-keymap)
      (use-local-map (make-composed-keymap kuro--line-mode-keymap kuro-mode-map)))))

(defun kuro--apply-input-mode ()
  "Update the current buffer's effective keymap for `kuro--input-mode'.
Sets `kuro-mode-map' parent to:
  `char'      → `kuro--char-keymap'  (all keys bound)
  `semi-char' → `kuro--keymap'       (exceptions removed)
  `line'      → `kuro--line-mode-keymap' as a composed local map
The mode-line is updated after every switch."
  (kuro--install-input-mode-keymap)
  (force-mode-line-update))

(provide 'kuro-input-mode-ext2-keymap)
;;; kuro-input-mode-ext2-keymap.el ends here
