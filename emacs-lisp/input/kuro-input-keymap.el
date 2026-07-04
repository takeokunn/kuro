;;; kuro-input-keymap.el --- Terminal input keymap for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Builds `kuro--keymap', the parent keymap of `kuro-mode-map'.
;;
;; Key categories are split into per-function setup helpers:
;; `kuro--keymap-setup-special' (RET/TAB/DEL/ESC),
;; `kuro--keymap-setup-ctrl' (C-a..C-z control bytes),
;; `kuro--keymap-setup-meta' (M-a..M-z and Meta-punctuation via ESC prefix),
;; `kuro--keymap-setup-navigation' (arrows, home/end, page, F1-F12,
;; modifier+arrow xterm sequences), `kuro--keymap-setup-mouse' (X10/SGR
;; mouse events), and `kuro--keymap-setup-yank' (bracketed paste yank).
;;
;; Keys listed in `kuro-keymap-exceptions' are removed at build time so
;; they fall through to the global keymap (e.g. M-x, C-g).

;;; Code:

(require 'kuro-input-keymap-data)
(require 'kuro-input-keymap-meta)
(require 'kuro-input-keymap-navigation)
(require 'kuro-input-macros)
(require 'kuro-input-mouse)
(require 'kuro-input-mouse-scroll)
(require 'kuro-input-paste)
(require 'kuro-keymap)
(require 'kuro-keymap-macros)

;; Forward references: these functions are defined in kuro-input-send.el,
;; kuro-input-send-scroll.el, kuro-input-keys.el, and
;; kuro-input-keymap-navigation.el.  declare-function
;; silences byte-compiler warnings without introducing a circular require.
(declare-function kuro--self-insert "kuro-input-send" ())
(declare-function kuro--RET "kuro-input-send" ())
(declare-function kuro--TAB "kuro-input-send" ())
(declare-function kuro--DEL "kuro-input-send" ())
(declare-function kuro--arrow-up "kuro-input-keys" ())
(declare-function kuro--arrow-down "kuro-input-keys" ())
(declare-function kuro--arrow-left "kuro-input-keys" ())
(declare-function kuro--arrow-right "kuro-input-keys" ())
(declare-function kuro--HOME "kuro-input-keys" ())
(declare-function kuro--END "kuro-input-keys" ())
(declare-function kuro--schedule-immediate-render "kuro-input-render" ())
(declare-function kuro--kkp-flag-p "kuro-input-keys" (flag))
(declare-function kuro--INSERT "kuro-input-keys" ())
(declare-function kuro--DELETE "kuro-input-keys" ())
(declare-function kuro--PAGE-UP "kuro-input-keys" ())
(declare-function kuro--PAGE-DOWN "kuro-input-keys" ())
(declare-function kuro-scroll-up "kuro-input-send-scroll" ())
(declare-function kuro-scroll-down "kuro-input-send-scroll" ())
(declare-function kuro-scroll-bottom "kuro-input-send-scroll" ())
(declare-function kuro--send-ctrl "kuro-input-send" (byte))
(declare-function kuro--scroll-aware-ctrl-v "kuro-input-send-scroll" ())
(declare-function kuro--super-modified "kuro-input-keys" (char))
(declare-function kuro--hyper-modified "kuro-input-keys" (char))

;;; Keymap Variable

(defvar kuro--keymap nil
  "Keymap for Kuro terminal emulator.  Built by `kuro--build-keymap'.")


;;; Keymap Helper Functions

(defun kuro--keymap-setup-special (map)
  "Install special key bindings into MAP (RET, TAB, DEL, escape, Ctrl variants)."
  ;; [return] and (kbd "C-m") are both ?\r (ASCII 13) in terminal semantics.
  ;; [tab] and (kbd "C-i") are both ?\t.
  ;; [backspace] is DEL (127); (kbd "C-h") is BS (8) — both must work.
  (kuro--bind-keys map #'kuro--RET [return] (kbd "C-m"))
  (kuro--bind-keys map #'kuro--TAB [tab] (kbd "C-i"))
  (kuro--bind-keys map #'kuro--DEL [backspace] (kbd "C-h") (kbd "DEL")))

(defun kuro--send-escape ()
  "Send Escape to the PTY, preserving KKP disambiguation when enabled."
  (interactive)
  (kuro--with-kkp-disambiguate "\e[27;1u" (kuro--send-ctrl 27))
  (kuro--schedule-immediate-render))

(defun kuro--keymap-setup-ctrl (map)
  "Install Ctrl+letter bindings into MAP as PTY control bytes.
Uses `kuro--ctrl-key-table' to map Emacs key strings to ASCII control codes."
  (kuro--define-key-bindings map kuro--ctrl-key-table
    (lambda (binding) (kbd (car binding)))
    (lambda (binding)
      `(lambda ()
         (interactive)
         (kuro--send-ctrl ,(cdr binding)))))
  ;; C-v: scroll-aware — scrolls when in scrollback, sends ctrl byte when at live view.
  (define-key map (kbd "C-v") #'kuro--scroll-aware-ctrl-v)
  ;; ESC must use [escape] (not kbd "ESC") to avoid shadowing all ESC-prefixed bindings.
  ;; With KKP DISAMBIGUATE (0x01): send CSI 27;1u so the app sees an unambiguous Escape
  ;; event, rather than a bare \e that could be mistaken as the start of an escape sequence.
  (define-key map [escape] #'kuro--send-escape))

(defun kuro--keymap-setup-super-hyper (map)
  "Install Super (s-) and Hyper (H-) modifier bindings into MAP.
Each printable letter/digit is bound so that, when a Kitty keyboard
protocol flag is active, s-CHAR sends CSI char;9u and H-CHAR sends
CSI char;17u via `kuro--super-modified' / `kuro--hyper-modified'.

These modifiers have no legacy (non-KKP) terminal encoding, so without a
KKP flag the handlers send nothing — matching how real terminals behave.

`kuro--kkp-report-events' (flag 0x02, key press/repeat/release reporting)
is intentionally NOT wired here: vanilla Emacs delivers only key-press
events and exposes no key-release events, so it cannot be supported."
  (dolist (char kuro--meta-letter-chars)
    (kuro--bind-keys map
                     `(lambda () (interactive) (kuro--super-modified ,char))
                     (kbd (format "s-%c" char)))
    (kuro--bind-keys map
                     `(lambda () (interactive) (kuro--hyper-modified ,char))
                     (kbd (format "H-%c" char)))))

(defun kuro--keymap-setup-mouse (map)
  "Install mouse event bindings into MAP using `kuro--mouse-bindings'."
  (kuro--define-key-bindings map kuro--mouse-bindings
    (lambda (binding) (car binding))
    #'cdr))

(defun kuro--keymap-setup-yank (map)
  "Install yank remapping into MAP using `kuro--yank-bindings'.
Remaps `yank', `yank-pop', and `clipboard-yank' (Cmd+V on macOS)
all to `kuro--yank' / `kuro--yank-pop' so paste always goes through the PTY
with optional bracketed-paste wrapping."
  (kuro--define-key-bindings map kuro--yank-bindings
    (lambda (binding) (vector 'remap (car binding)))
    #'cdr))

;;; Keymap Variables

(defvar kuro--char-keymap nil
  "Full Kuro keymap with ALL keys bound (char mode: no exceptions).
Built by `kuro--build-keymap' alongside `kuro--keymap'.")


;;; Keymap Builder

(defun kuro--build-full-keymap ()
  "Build and return a full Kuro keymap with all keys bound (no exceptions).
This is the char-mode base; used directly in char mode and as the basis
for `kuro--keymap' (semi-char) after exception removal."
  (let ((map (make-sparse-keymap)))
    (define-key map [remap self-insert-command] #'kuro--self-insert)
    (kuro--keymap-setup-special map)
    (kuro--keymap-setup-ctrl map)
    (kuro--keymap-setup-meta map)
    (kuro--keymap-setup-super-hyper map)
    (kuro--keymap-setup-navigation map)
    (kuro--keymap-setup-mouse map)
    (kuro--keymap-setup-yank map)
    map))

(defun kuro--build-keymap ()
  "Build `kuro--keymap' (semi-char) and `kuro--char-keymap' (char mode).
`kuro--char-keymap': all keys bound, no exceptions — used in char mode.
`kuro--keymap': exceptions from `kuro-keymap-exceptions' removed — default.
Returns `kuro--keymap' for backward compatibility."
  (setq kuro--char-keymap (kuro--build-full-keymap))
  ;; Semi-char: start from a copy of the full keymap, then punch holes
  (let ((map (copy-keymap kuro--char-keymap)))
    (kuro--keymap-apply-exceptions map)
    (setq kuro--keymap map)
    map))

(provide 'kuro-input-keymap)

;;; kuro-input-keymap.el ends here
