;;; kuro-input-mode.el --- Three-mode input system for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Provides three named input modes for `kuro-mode' buffers:
;;
;;   `char'      — ALL keys forwarded to PTY (no Emacs interception).
;;                 Raw terminal mode: binary apps, screen editors, etc.
;;
;;   `semi-char' — Keys in `kuro-keymap-exceptions' fall through to Emacs
;;                 (C-x, M-x, C-g, etc.); everything else → PTY.
;;                 This is the DEFAULT mode.
;;
;;   `line'      — Characters accumulate in Emacs.  RET sends the full
;;                 line to the PTY.  Full Emacs editing is available:
;;                 isearch, company-mode, hippie-expand.  Typed input is
;;                 shown via an overlay at the terminal cursor position.
;;                 C-g cancels without sending.
;;
;;                 For full IME support (DDSKK, mozc, skk), set
;;                 `kuro-line-use-minibuffer' to t.  In that mode every
;;                 keypress opens a minibuffer prompt where `input-method-
;;                 function' fires normally.  Alternatively, call
;;                 `kuro-line-minibuffer-send' (C-c C-r in line mode)
;;                 at any time to explicitly switch to the minibuffer path.
;;
;; API:
;;   `kuro-char-mode'            — switch to char mode
;;   `kuro-semi-char-mode'       — switch to semi-char mode (default)
;;   `kuro-line-mode'            — switch to line mode
;;   `kuro-cycle-input-mode'     — cycle: semi-char → char → line → semi-char
;;   `kuro-line-minibuffer-send' — read via minibuffer (IME-compatible)
;;
;; Mode-line: each kuro buffer shows the current mode as "[C]", "[S]", or "[L]"
;; appended after the mode name.

;;; Code:

(require 'kuro-input-mode-data)
(require 'kuro-input-mode-line)
(require 'kuro-input-mode-line-state)
(require 'kuro-input-mode-macros)
(require 'kuro-ffi)

(require 'kuro-input-mode-history)
(require 'kuro-input-mode-ext)

(provide 'kuro-input-mode)
;;; kuro-input-mode.el ends here
