;;; kuro-input-mode-ext2-keymap.el --- Keymap helpers for kuro-input-mode-ext2  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Internal keymap resolution, construction, and installation helpers for
;; `kuro-input-mode-ext2'.  Keep the public mode-switch commands in
;; `kuro-input-mode-ext2-mode.el' so this file owns the implementation detail
;; boundary.

;;; Code:

(require 'kuro-keymap)
(require 'kuro-keymap-macros)
(require 'kuro-input-mode-ext2-data)
(require 'kuro-ffi-macros)

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
;; kuro--copy-mode is defined (permanent-local) in kuro-copy.el, which is
;; required AFTER kuro-input-mode in kuro.el's load order (see kuro.el's
;; `(require 'kuro-input-mode)' / `(require 'kuro-copy)' comment), so this
;; file cannot `require' it without introducing a backwards/circular load.
;; Forward-declare instead; `bound-and-true-p' at the call site degrades
;; safely to "not in copy mode" if it is ever unbound.
(defvar kuro--copy-mode)

(defvar kuro--line-mode-keymap nil
  "Keymap active in Kuro line mode.
Inherits from `kuro--keymap' (semi-char) but overrides self-insert, RET,
delete/backspace, line kill, and cancel to operate on the local line
buffer instead of forwarding to the PTY.")

(kuro--defvar-permanent-local kuro--emulation-mode-map-alist nil
  "Buffer-local alist registered into `emulation-mode-map-alists'.
When non-nil, holds a single ((t . EFFECTIVE-MAP)) entry where EFFECTIVE-MAP
is this buffer's current PTY-forwarding composed keymap (the same object
installed via `use-local-map' by `kuro--install-input-mode-keymap').
Because `emulation-mode-map-alists' keymaps take precedence over any
`minor-mode-map-alist' entry (evil-mode, god-mode, meow, ...) as well as
any ordinary major-mode local map, this guarantees PTY-forwarded keys
reach the PTY even when such a package is active.  Set to nil while
`kuro--copy-mode' is active, since copy-mode intentionally suspends PTY
forwarding.")

(add-to-list 'emulation-mode-map-alists 'kuro--emulation-mode-map-alist)

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
  "Install the effective keymap for `kuro--input-mode'.
Builds a buffer-local composed keymap — `kuro-mode-map' (the shared,
invariant C-c-prefixed command map) is never mutated in place, so
switching input mode or `kuro-keymap-exceptions' in one Kuro buffer never
affects any other simultaneously open Kuro buffer.  Also refreshes
`kuro--emulation-mode-map-alist' so PTY-forwarding keeps Emacs
key-lookup precedence over any higher-priority keymap (evil-mode,
god-mode, ...) via `emulation-mode-map-alists' — except while
`kuro--copy-mode' is active, in which case this function is a no-op so
copy-mode's own keymap and Emacs-native navigation are left undisturbed.

`kuro-mode-map' is listed BEFORE the PTY-forwarding map in the composed
keymap (not after): `make-composed-keymap' gives its first constituent
absolute priority for a given event, including when that constituent's
own answer is an explicit nil (e.g. from `kuro-keymap-exceptions' — see
`kuro--keymap-apply-exceptions'), which shadows rather than defers to a
later constituent.  Since `kuro-mode-map' only defines its own prefixed
command bindings and is silent on every other key, listing it first
costs nothing for ordinary PTY-forwarded keys (they still forward
correctly — verified: exception keys configured via
`kuro-keymap-exceptions' (e.g. `execute-extended-command', quitting, and
Emacs' own prefix keys) still fall through to the global map, and
ordinary non-exception keys still reach the PTY ahead of evil-mode,
god-mode, and similar packages via `emulation-mode-map-alists') while
guaranteeing `kuro-mode-map's own commands (interrupt, toggling copy
mode, ...) are never shadowed by the forwarding map's own exception
entry for the Kuro prefix key itself.

Also re-asserts `kuro--emulation-mode-map-alist' at the HEAD of the
global `emulation-mode-map-alists' list on every call, not just once at
package load time.  `add-to-list' (used once, at load time, below) only
prepends the first time it sees a given entry; if some other package
registers its own entry into `emulation-mode-map-alists' afterwards
\(e.g. evil-mode enabled in a buffer, or `evil' `require'd, later in the
session than Kuro), that package's entry ends up ahead of Kuro's within
the `emulation-mode-map-alists' precedence tier and can shadow
PTY-forwarded keys again — the same bug class issue #1 fixed.  Since this
function already runs on every mode switch, initial mode entry, and
`kuro-keymap-exceptions' change, it is the natural place to keep
reclaiming the head position each time."
  (unless (bound-and-true-p kuro--copy-mode)
    (let* ((parent (cdr (assq kuro--input-mode kuro--input-mode-keymaps)))
           (forward-map (if parent
                            (kuro--resolve-keymap parent)
                          (kuro--build-line-mode-keymap)))
           (effective-map (make-composed-keymap kuro-mode-map forward-map)))
      (use-local-map effective-map)
      (setq kuro--emulation-mode-map-alist (list (cons t effective-map)))
      (unless (eq (car emulation-mode-map-alists) 'kuro--emulation-mode-map-alist)
        (setq emulation-mode-map-alists
              (cons 'kuro--emulation-mode-map-alist
                    (delq 'kuro--emulation-mode-map-alist emulation-mode-map-alists)))))))

(defun kuro--apply-input-mode ()
  "Update the current buffer's effective keymap for `kuro--input-mode'.
Builds a buffer-local composed keymap (forwarding map over the shared
`kuro-mode-map', never mutating it) for:
  `char'      → `kuro--char-keymap'  (all keys bound)
  `semi-char' → `kuro--keymap'       (exceptions removed)
  `line'      → `kuro--line-mode-keymap'
and refreshes `kuro--emulation-mode-map-alist' so it keeps taking
precedence over any modal-editing package's keymap.  The mode-line is
updated after every switch."
  (kuro--install-input-mode-keymap)
  (force-mode-line-update))

(provide 'kuro-input-mode-ext2-keymap)
;;; kuro-input-mode-ext2-keymap.el ends here
