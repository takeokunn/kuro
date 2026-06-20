;;; kuro-input-keymap-meta.el --- Meta key bindings for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Meta/Alt bindings and keymap exception handling for
;; `kuro-input-keymap.el'.  This module keeps the ESC-prefix fallback logic
;; separate from the core keymap builder.

;;; Code:

(require 'kuro-ffi)
(require 'kuro-input-keymap-data)
(require 'kuro-input-keymap-meta-macros)
(require 'kuro-keymap)
(require 'kuro-keymap-macros)

(eval-when-compile
  (require 'cl-lib))

;; Forward references from kuro-input.el and kuro-ffi.
(declare-function kuro--send-key "kuro-ffi" (key))
(declare-function kuro--schedule-immediate-render "kuro-input-render" ())
(declare-function kuro--send-meta "kuro-input-send" (char))
(declare-function kuro--scroll-aware-meta-v "kuro-input-send-scroll" ())

(defvar kuro--keyboard-flags 0
  "Forward reference; defvar-permanent-local in kuro-input-paste.el.")

(defun kuro--send-meta-backspace ()
  "Send ESC+DEL (Meta-Backspace) to the PTY.
This is the standard control sequence for `backward-kill-word' in readline/bash."
  (interactive)
  (kuro--send-key (string ?\e ?\x7f))
  (kuro--schedule-immediate-render))

(defun kuro--meta-exception-char (exc)
  "Return the single-character Meta suffix from EXC, or nil."
  (when (and (string-prefix-p "M-" exc)
             (= (length exc) 3))
    (aref exc 2)))

(defun kuro--keymap-clear-exception (map exc)
  "Unbind EXC in MAP and clear its ESC-prefix fallback when applicable."
  (ignore-errors
    (define-key map (kbd exc) nil)
    (let ((char (kuro--meta-exception-char exc)))
      (when char
        (define-key map (vector ?\e char) nil)))))

(defun kuro--keymap-setup-meta (map)
  "Install Meta/Alt bindings for all letters and related keys into MAP.

In readline, Alt+key is sent as ESC then the key character.  These are
the bash readline Alt bindings most frequently used (each is forwarded as
ESC + the corresponding character byte to the PTY):
  Meta-b  — move word left          Meta-f  — move word right
  Meta-d  — delete word forward     Meta-DEL — delete word backward
  Meta-.  — insert last argument    Meta-r  — revert-line
  Meta-u  — uppercase word          Meta-l  — lowercase word
  Meta-c  — capitalize word         Meta-t  — transpose words
  Meta-y  — `yank-pop'              Meta-<  — beginning of history
  Meta->  — end of history          Meta-?  — possible completions
  Meta-/  — complete filename

The loop runs FIRST so that explicit overrides below take precedence.
Use (kbd (format \"M-%c\" char)) — this produces the correct event descriptor
in both terminal and GUI Emacs.  (vector (list \='meta char)) is NOT equivalent
and would be silently ignored in GUI frames."
  ;; Bind ALL M-a … M-z, M-A … M-Z, M-0 … M-9.
  (kuro--define-meta-letter-bindings map kuro--meta-letter-chars)

  ;; Keys outside the a-z/A-Z/0-9 ranges.
  (kuro--define-key-bindings map kuro--meta-punct-bindings
    (lambda (binding) (kbd (car binding)))
    (lambda (binding)
      `(lambda ()
         (interactive)
         (kuro--send-meta ,(cdr binding)))))
  ;; M-v: scroll-aware — scrolls when in scrollback, sends ESC+v when at live view.
  (kuro--bind-keys map #'kuro--scroll-aware-meta-v (kbd "M-v") (vector ?\e ?v))
  ;; M-DEL — delete word backward (sends ESC + DEL = ESC + 127)
  (kuro--bind-keys map #'kuro--send-meta-backspace
                   (kbd "M-DEL")
                   (kbd "M-<backspace>")))

(defun kuro--keymap-apply-exceptions (map)
  "Remove exception keys from MAP per `kuro-keymap-exceptions'.
Keys in `kuro-keymap-exceptions' fall through to the standard Emacs
global keymap.
Called on the semi-char keymap; NOT called when building the char keymap."
  (dolist (exc (bound-and-true-p kuro-keymap-exceptions))
    (kuro--keymap-clear-exception map exc)))

(provide 'kuro-input-keymap-meta)

;;; kuro-input-keymap-meta.el ends here
