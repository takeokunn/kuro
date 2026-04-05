;;; kuro-colors.el --- ANSI color palette defcustoms for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

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

;;; Color validation constant

(defconst kuro--hex-color-regexp "^#[0-9a-fA-F]\\{6\\}$"
  "Regular expression that matches a valid 6-digit hex color string (#rrggbb).")

;;; ANSI color name → defcustom symbol mapping

(defconst kuro--color-name-alist
  '(("black"          . kuro-color-black)
    ("red"            . kuro-color-red)
    ("green"          . kuro-color-green)
    ("yellow"         . kuro-color-yellow)
    ("blue"           . kuro-color-blue)
    ("magenta"        . kuro-color-magenta)
    ("cyan"           . kuro-color-cyan)
    ("white"          . kuro-color-white)
    ("bright-black"   . kuro-color-bright-black)
    ("bright-red"     . kuro-color-bright-red)
    ("bright-green"   . kuro-color-bright-green)
    ("bright-yellow"  . kuro-color-bright-yellow)
    ("bright-blue"    . kuro-color-bright-blue)
    ("bright-magenta" . kuro-color-bright-magenta)
    ("bright-cyan"    . kuro-color-bright-cyan)
    ("bright-white"   . kuro-color-bright-white))
  "Alist mapping ANSI color name strings to `kuro-color-*' defcustom symbols.
Used by `kuro--rebuild-named-colors' to populate `kuro--named-colors'.")

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
    (dolist (entry kuro--color-name-alist)
      (puthash (car entry) (symbol-value (cdr entry)) kuro--named-colors))))

;;; :set handler for color defcustoms

(defun kuro--set-color (symbol value)
  "Set SYMBOL to VALUE, rebuild color table, and clear face cache."
  (unless (and (stringp value)
               (string-match-p kuro--hex-color-regexp value))
    (user-error "kuro: color must be a 6-digit hex string like #rrggbb, got: %s" value))
  (set-default symbol value)
  (kuro--rebuild-named-colors)
  (when (fboundp 'kuro--clear-face-cache)
    (kuro--clear-face-cache)))

;;; ANSI Color Palette

(defmacro kuro--defcolor (suffix default label index)
  "Define a `defcustom' for ANSI palette entry SUFFIX with DEFAULT hex value.
LABEL is the color name string; INDEX is the palette index integer."
  `(defcustom ,(intern (concat "kuro-color-" suffix)) ,default
     ,(concat "Color for ANSI " label " (palette index " (number-to-string index)
              ").\nValue must be a 6-digit hex string, e.g. #rrggbb.")
     :type '(string :tag "Hex color (#rrggbb)")
     :group 'kuro-colors
     :set #'kuro--set-color))

(kuro--defcolor "black"          "#000000" "black"                    0)
(kuro--defcolor "red"            "#c23621" "red"                      1)
(kuro--defcolor "green"          "#25bc24" "green"                    2)
(kuro--defcolor "yellow"         "#adad27" "yellow"                   3)
(kuro--defcolor "blue"           "#492ee1" "blue"                     4)
(kuro--defcolor "magenta"        "#d338d3" "magenta"                  5)
(kuro--defcolor "cyan"           "#33bbc8" "cyan"                     6)
(kuro--defcolor "white"          "#cbcccd" "white"                    7)
(kuro--defcolor "bright-black"   "#808080" "bright black / dark gray" 8)
(kuro--defcolor "bright-red"     "#ff0000" "bright red"               9)
(kuro--defcolor "bright-green"   "#00ff00" "bright green"            10)
(kuro--defcolor "bright-yellow"  "#ffff00" "bright yellow"           11)
(kuro--defcolor "bright-blue"    "#0000ff" "bright blue"             12)
(kuro--defcolor "bright-magenta" "#ff00ff" "bright magenta"          13)
(kuro--defcolor "bright-cyan"    "#00ffff" "bright cyan"             14)
(kuro--defcolor "bright-white"   "#ffffff" "bright white"            15)

(provide 'kuro-colors)

;;; kuro-colors.el ends here
