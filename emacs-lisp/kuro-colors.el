;;; kuro-colors.el --- ANSI color palette defcustoms for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; This file defines the 16 ANSI color palette `defcustom' variables,
;; the `kuro--named-colors' alist, and the `kuro--rebuild-named-colors'
;; function for the Kuro terminal emulator.
;;
;; # Responsibilities
;;
;; - 16 user-facing ANSI color defcustom variables (kuro-color-*)
;; - kuro--named-colors internal alist (name → hex)
;; - kuro--rebuild-named-colors: rebuilds the alist from current defcustom values
;;
;; # Dependencies
;;
;; None.  Color defcustoms are self-contained.
;; kuro-config.el loads this file and provides kuro--set-color and
;; kuro--kuro-buffers which the :set handlers reference at runtime.

;;; Code:

(declare-function kuro--clear-face-cache "kuro-faces" ())

;;; Customization Group

(defgroup kuro-colors nil
  "ANSI color palette for Kuro terminal emulator."
  :group 'kuro
  :prefix "kuro-color-")

;;; Internal Color Table

(defvar kuro--named-colors (make-hash-table :test 'equal :size 16)
  "Internal hash table mapping ANSI color names to hex color strings.
Rebuilt automatically from `kuro-color-*' defcustom values by
`kuro--rebuild-named-colors'.  Do not set this variable directly.")

(defun kuro--rebuild-named-colors ()
  "Rebuild `kuro--named-colors' from `kuro-color-*' defcustom values.
Called at file load and by each color `defcustom' `:set' handler.
Skips rebuild silently if any color variable is not yet bound (e.g.
during `defcustom' initialization before all 16 colors are defined)."
  (when (boundp 'kuro-color-bright-white)
    (clrhash kuro--named-colors)
    (puthash "black"          kuro-color-black          kuro--named-colors)
    (puthash "red"            kuro-color-red            kuro--named-colors)
    (puthash "green"          kuro-color-green          kuro--named-colors)
    (puthash "yellow"         kuro-color-yellow         kuro--named-colors)
    (puthash "blue"           kuro-color-blue           kuro--named-colors)
    (puthash "magenta"        kuro-color-magenta        kuro--named-colors)
    (puthash "cyan"           kuro-color-cyan           kuro--named-colors)
    (puthash "white"          kuro-color-white          kuro--named-colors)
    (puthash "bright-black"   kuro-color-bright-black   kuro--named-colors)
    (puthash "bright-red"     kuro-color-bright-red     kuro--named-colors)
    (puthash "bright-green"   kuro-color-bright-green   kuro--named-colors)
    (puthash "bright-yellow"  kuro-color-bright-yellow  kuro--named-colors)
    (puthash "bright-blue"    kuro-color-bright-blue    kuro--named-colors)
    (puthash "bright-magenta" kuro-color-bright-magenta kuro--named-colors)
    (puthash "bright-cyan"    kuro-color-bright-cyan    kuro--named-colors)
    (puthash "bright-white"   kuro-color-bright-white   kuro--named-colors)))

;;; :set handler for color defcustoms

(defun kuro--set-color (symbol value)
  "Set SYMBOL to VALUE, rebuild color table, and clear face cache."
  (unless (and (stringp value)
               (string-match-p "^#[0-9a-fA-F]\\{6\\}$" value))
    (user-error "kuro: color must be a 6-digit hex string like #rrggbb, got: %s" value))
  (set-default symbol value)
  (kuro--rebuild-named-colors)
  (when (fboundp 'kuro--clear-face-cache)
    (kuro--clear-face-cache)))

;;; ANSI Color Palette

(defcustom kuro-color-black "#000000"
  "Color for ANSI black (palette index 0).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type '(string :tag "Hex color (#rrggbb)")
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-red "#c23621"
  "Color for ANSI red (palette index 1).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type '(string :tag "Hex color (#rrggbb)")
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-green "#25bc24"
  "Color for ANSI green (palette index 2).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type '(string :tag "Hex color (#rrggbb)")
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-yellow "#adad27"
  "Color for ANSI yellow (palette index 3).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type '(string :tag "Hex color (#rrggbb)")
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-blue "#492ee1"
  "Color for ANSI blue (palette index 4).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type '(string :tag "Hex color (#rrggbb)")
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-magenta "#d338d3"
  "Color for ANSI magenta (palette index 5).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type '(string :tag "Hex color (#rrggbb)")
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-cyan "#33bbc8"
  "Color for ANSI cyan (palette index 6).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type '(string :tag "Hex color (#rrggbb)")
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-white "#cbcccd"
  "Color for ANSI white (palette index 7).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type '(string :tag "Hex color (#rrggbb)")
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-bright-black "#808080"
  "Color for ANSI bright black / dark gray (palette index 8).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type '(string :tag "Hex color (#rrggbb)")
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-bright-red "#ff0000"
  "Color for ANSI bright red (palette index 9).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type '(string :tag "Hex color (#rrggbb)")
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-bright-green "#00ff00"
  "Color for ANSI bright green (palette index 10).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type '(string :tag "Hex color (#rrggbb)")
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-bright-yellow "#ffff00"
  "Color for ANSI bright yellow (palette index 11).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type '(string :tag "Hex color (#rrggbb)")
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-bright-blue "#0000ff"
  "Color for ANSI bright blue (palette index 12).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type '(string :tag "Hex color (#rrggbb)")
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-bright-magenta "#ff00ff"
  "Color for ANSI bright magenta (palette index 13).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type '(string :tag "Hex color (#rrggbb)")
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-bright-cyan "#00ffff"
  "Color for ANSI bright cyan (palette index 14).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type '(string :tag "Hex color (#rrggbb)")
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-bright-white "#ffffff"
  "Color for ANSI bright white (palette index 15).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type '(string :tag "Hex color (#rrggbb)")
  :group 'kuro-colors
  :set #'kuro--set-color)

(provide 'kuro-colors)

;;; kuro-colors.el ends here
