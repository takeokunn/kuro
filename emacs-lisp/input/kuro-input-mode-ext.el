;;; kuro-input-mode-ext.el --- Word-case transforms and input-mode glue  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Continuation of `kuro-input-mode'.  Loaded automatically at the end of
;; that file.  Contains word-case transforms and input-mode glue.
;; Minibuffer send lives in `kuro-input-mode-ext2-send'; the line-buffer
;; editor lives in `kuro-input-mode-edit'; line-mode editing commands live
;; in `kuro-input-mode-line-ops'; line-mode keymap builder and public
;; mode-switch commands live in `kuro-input-mode-ext2-mode'.
;;
;; Do not `(require \\='kuro-input-mode-ext)' directly; load
;; `kuro-input-mode' instead.

;;; Code:

(require 'kuro-config)
(require 'kuro-input-mode-macros)
(require 'kuro-input-mode-line-ops)
(require 'kuro-input-mode-transform)

;; Functions defined in kuro-input-mode-line-display.el,
;; kuro-input-mode-line.el, and kuro-input-mode-transform.el
;; (loaded before this file at runtime).
(declare-function kuro--line-mode-update-display "kuro-input-mode-line-display" ())
(declare-function kuro--line-clear-overlay        "kuro-input-mode-line-display" ())
(declare-function kuro--line-word-bounds-forward  "kuro-input-mode-line" ())
(declare-function kuro--schedule-immediate-render "kuro-input-render" ())
(declare-function kuro--send-key                  "kuro-ffi"        (key))
(declare-function kuro--build-keymap              "kuro-input-keymap" ())

;; Buffer-local variables defined in kuro-input-mode.el.
(defvar kuro--line-buffer)
(defvar kuro--line-point)
(defvar kuro--line-history)
(defvar kuro--line-history-idx)
(defvar kuro--line-history-stash)
(defvar kuro--input-mode)
;; Keymap variables forward-declared in kuro-input-mode.el.
(defvar kuro--keymap)
(defvar kuro--char-keymap)
(defvar kuro-mode-map)
;; Defcustom variables defined in kuro-input-mode.el.
(defvar kuro-line-completion-function)
(defvar kuro-line-abbrev-alist)


(require 'kuro-input-mode-yank)
(require 'kuro-input-mode-ext2)

(provide 'kuro-input-mode-ext)
;;; kuro-input-mode-ext.el ends here
