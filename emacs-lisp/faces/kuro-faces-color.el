;;; kuro-faces-color.el --- Color conversion utilities for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; This file provides TrueColor detection, ANSI/256-color/TrueColor →
;; Emacs color string conversion, and FFI color encoding decoding for
;; the Kuro terminal emulator.
;;
;; # Responsibilities
;;
;; - TrueColor (24-bit) display support detection
;; - Named / indexed / RGB color → Emacs color string conversion
;; - FFI u32 color encoding → Emacs color spec decoding
;;
;; # Dependencies
;;
;; Depends on `kuro-config' (via kuro-faces.el) for `kuro--named-colors'.
;; Has no direct dependency on `kuro-ffi'.

;;; Code:

(defconst kuro--ffi-color-default #xFF000000
  "FFI color encoding sentinel meaning Color::Default from the Rust side.
Distinct from true black (#x000000) by the upper byte being 0xFF.
See `encode_color' in rust-core/src/ffi/codec.rs for the encoding contract.")

(defconst kuro--ansi-color-names
  ["black" "red" "green" "yellow" "blue" "magenta" "cyan" "white"
   "bright-black" "bright-red" "bright-green" "bright-yellow"
   "bright-blue" "bright-magenta" "bright-cyan" "bright-white"]
  "Standard ANSI terminal color names for indices 0-15.
Used to look up named-color faces in `kuro--decode-ffi-color' and
`kuro--indexed-to-emacs'. Indices match the order of NamedColor in
rust-core/src/types/color.rs.  Names match the keys in `kuro--named-colors'.")

(defconst kuro--named-color-conses
  (let ((v (make-vector 16 nil)))
    (dotimes (i 16)
      (aset v i (cons 'named (aref kuro--ansi-color-names i))))
    v)
  "Pre-allocated `(named . name)' cons cells for the 16 ANSI color indices.
`kuro--decode-ffi-color' reads these directly on named-color hits, avoiding
one cons allocation per unique named-color cache miss.")

;;; 256-color palette constants

(defconst kuro--color-cube-start 16
  "Start index of the 6×6×6 RGB color cube in the 256-color palette.
Indices 0-15 are the standard ANSI named colors; the cube begins at 16.")

(defconst kuro--color-cube-end 231
  "Last index of the 6×6×6 RGB color cube in the 256-color palette.
Indices 16-231 encode 216 colors (6 steps × 6 steps × 6 steps).")

(defconst kuro--color-cube-size 6
  "Number of intensity steps per channel in the 6×6×6 RGB color cube.")

(defconst kuro--color-cube-step 51
  "Intensity increment per cube step: 255 / 5 = 51 (evenly spaced).")

(defconst kuro--color-gray-start 232
  "Start index of the grayscale ramp in the 256-color palette.
Indices 232-255 encode 24 shades from near-black to near-white.")

(defconst kuro--color-gray-step 10
  "Intensity increment per grayscale ramp step.")

(defconst kuro--color-gray-offset 8
  "Base intensity offset for the first grayscale ramp entry (index 232).
Formula: index_offset * kuro--color-gray-step + kuro--color-gray-offset.")

;;; Pre-computed 256-color lookup tables

(defconst kuro--color-cube-table
  (let ((v (make-vector 216 nil)))
    (dotimes (i 216)
      (let* ((r (* (/ i (* kuro--color-cube-size kuro--color-cube-size))
                   kuro--color-cube-step))
             (g (* (mod (/ i kuro--color-cube-size) kuro--color-cube-size)
                   kuro--color-cube-step))
             (b (* (mod i kuro--color-cube-size)
                   kuro--color-cube-step)))
        (aset v i (format "#%02x%02x%02x" r g b))))
    v)
  "Pre-computed RGB strings for 256-color cube (indices 16-231).")

(defconst kuro--grayscale-table
  (let ((v (make-vector 24 nil)))
    (dotimes (i 24)
      (let ((val (+ (* i kuro--color-gray-step) kuro--color-gray-offset)))
        (aset v i (format "#%02x%02x%02x" val val val))))
    v)
  "Pre-computed RGB strings for grayscale ramp (indices 232-255).")

;;; FFI color tag bit constants

(defconst kuro--color-tag-named #x80000000
  "FFI color tag bit: named color (palette index) encoding.")
(defconst kuro--color-tag-indexed #x40000000
  "FFI color tag bit: indexed (256-color) encoding.")
(defconst kuro--color-rgb-mask #xFFFFFF
  "FFI color mask: low 24 bits extract the index from a tagged color word.")

;;; ANSI color conversion

(defun kuro--color-to-emacs (color)
  "Convert Rust Color enum value to Emacs color string or nil.
COLOR can be:
  - :default for default color (returns nil)
  - A cons cell (named . color-name) for named colors
  - A cons cell (indexed . index) for 256-color palette
  - A cons cell (rgb . rgb-value) for truecolor (24-bit RGB)"
  (pcase color
    (:default nil)
    ((pred consp)
     (pcase (car color)
       ('named (or (gethash (cdr color) kuro--named-colors)
                   (cdr color)))
       ('indexed (kuro--indexed-to-emacs (cdr color)))
       ('rgb (kuro--rgb-to-emacs (cdr color)))))
    (_ nil)))

(defun kuro--indexed-to-emacs (idx)
  "Convert 256-color palette index IDX to Emacs color string."
  (cond
   ((<= idx 15)
    (let* ((name (aref kuro--ansi-color-names idx)))
      (gethash name kuro--named-colors)))
   ((<= idx kuro--color-cube-end)
    (aref kuro--color-cube-table (- idx kuro--color-cube-start)))
   ((<= idx 255)
    (aref kuro--grayscale-table (- idx kuro--color-gray-start)))
   (t nil)))

(defvar kuro--rgb-string-cache (make-hash-table :test 'eql :size 256)
  "Cache mapping 24-bit RGB integers to Emacs \"#rrggbb\" color strings.
Avoids repeated `format' calls for TrueColor values that recur across
frames (e.g. btop, neovim palette).  Keyed on the raw integer so lookups
are O(1) with no string comparison.")

(defsubst kuro--rgb-to-emacs (rgb-value)
  "Convert 24-bit RGB-VALUE to Emacs color string, using a session cache."
  (or (gethash rgb-value kuro--rgb-string-cache)
      (let ((s (format "#%02x%02x%02x"
                       (logand (ash rgb-value -16) #xFF)
                       (logand (ash rgb-value -8)  #xFF)
                       (logand rgb-value            #xFF))))
        (puthash rgb-value s kuro--rgb-string-cache)
        s)))

;;; FFI color decoding

(defconst kuro--indexed-color-conses
  (let ((v (make-vector 256 nil)))
    (dotimes (i 256)
      (aset v i (cons 'indexed i)))
    v)
  "Pre-allocated `(indexed . idx)' cons cells for all 256 indexed color indices.
`kuro--decode-ffi-color' reads these directly on indexed-color hits, avoiding
one cons allocation per unique indexed-color cache miss (analogous to
`kuro--named-color-conses' for the 16 ANSI named colors).")

(defsubst kuro--decode-ffi-color (color-enc)
  "Decode FFI color encoding COLOR-ENC to Emacs color spec.
COLOR-ENC is a u32 value:
  - kuro--ffi-color-default: default color (sentinel, distinct from true black)
  - Bit 31 set: named color (lower 8 bits = index into standard 16 names)
  - Bit 30 set: indexed color (lower 8 bits = palette index 0-255)
  - Otherwise: RGB packed into 24 bits (RRGGBB); 0 = true black Rgb(0,0,0)"
  (cond
   ((= color-enc kuro--ffi-color-default)
    :default)
   ((/= 0 (logand color-enc kuro--color-tag-named))
    ;; Use pre-allocated cons cell to avoid heap allocation on every cache miss.
    (let ((idx (logand color-enc #xFF)))
      (when (< idx 16)
        (aref kuro--named-color-conses idx))))
   ((/= 0 (logand color-enc kuro--color-tag-indexed))
    ;; Use pre-allocated cons cell to avoid heap allocation on every cache miss.
    (aref kuro--indexed-color-conses (logand color-enc #xFF)))
   (t
    (cons 'rgb (logand color-enc kuro--color-rgb-mask)))))

(provide 'kuro-faces-color)

;;; kuro-faces-color.el ends here
