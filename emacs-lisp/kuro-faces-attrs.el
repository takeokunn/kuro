;;; kuro-faces-attrs.el --- SGR attribute decoding for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; This file decodes SGR attribute bit-flags from the Rust FFI into
;; Emacs face property lists.
;;
;; # Responsibilities
;;
;; - `kuro--decode-attrs': unpack raw attribute integer into an attrs plist
;; - `kuro--underline-style-to-face-prop': map underline style enum to face prop
;; - `kuro--attrs-to-face-props': convert full attrs plist to Emacs face props

;;; Code:

(require 'kuro-faces-color)

;;; SGR attribute bitmask constants
;; These must match the encoding in rust-core/src/ffi/codec.rs `encode_attrs`.
(defconst kuro--sgr-flag-bold          #x001
  "SGR bold attribute flag (bit 0). Must match encode_attrs in rust-core/src/ffi/codec.rs.")
(defconst kuro--sgr-flag-dim           #x002
  "SGR dim/faint attribute flag (bit 1). Must match encode_attrs in rust-core/src/ffi/codec.rs.")
(defconst kuro--sgr-flag-italic        #x004
  "SGR italic attribute flag (bit 2). Must match encode_attrs in rust-core/src/ffi/codec.rs.")
(defconst kuro--sgr-flag-underline     #x008
  "SGR underline attribute flag (bit 3). Must match encode_attrs in rust-core/src/ffi/codec.rs.")
(defconst kuro--sgr-flag-blink-slow    #x010
  "SGR slow blink attribute flag (bit 4). Must match encode_attrs in rust-core/src/ffi/codec.rs.")
(defconst kuro--sgr-flag-blink-fast    #x020
  "SGR fast blink attribute flag (bit 5). Must match encode_attrs in rust-core/src/ffi/codec.rs.")
(defconst kuro--sgr-flag-inverse       #x040
  "SGR inverse/reverse video attribute flag (bit 6). Must match encode_attrs in rust-core/src/ffi/codec.rs.")
(defconst kuro--sgr-flag-hidden        #x080
  "SGR hidden/invisible attribute flag (bit 7). Must match encode_attrs in rust-core/src/ffi/codec.rs.")
(defconst kuro--sgr-flag-strikethrough #x100
  "SGR strikethrough attribute flag (bit 8). Must match encode_attrs in rust-core/src/ffi/codec.rs.")
(defconst kuro--sgr-underline-style-mask  #xE00
  "Bitmask for underline style field (bits 9-11). Must match encode_attrs in rust-core/src/ffi/codec.rs.")
(defconst kuro--sgr-underline-style-shift 9
  "Bit shift for underline style field. Must match encode_attrs in rust-core/src/ffi/codec.rs.")

(defsubst kuro--sgr-flag-set-p (attr-flags flag)
  "Return t if FLAG bit is set in ATTR-FLAGS bitmask, nil otherwise.
Uses (/= 0 ...) since 0 is truthy in Elisp — only nil is falsy."
  (/= 0 (logand attr-flags flag)))

;;; SGR attribute decoding

(defun kuro--decode-attrs (attr-flags)
  "Decode attribute bit flags ATTR-FLAGS from Rust core into a plist.
ATTR-FLAGS is a bitmask matching Rust encode_attrs:
  bit 0  (0x001) = bold
  bit 1  (0x002) = dim
  bit 2  (0x004) = italic
  bit 3  (0x008) = underline (any style)
  bit 4  (0x010) = blink-slow
  bit 5  (0x020) = blink-fast
  bit 6  (0x040) = inverse
  bit 7  (0x080) = hidden
  bit 8  (0x100) = strikethrough
  bits 9-11 (0xE00, shift 9) = underline style:
    0 = None, 1 = Straight, 2 = Double, 3 = Curly, 4 = Dotted, 5 = Dashed
Use (/= 0 ...) to produce t/nil booleans — in Elisp, 0 is truthy, only nil is falsy."
  (let ((bold           (kuro--sgr-flag-set-p attr-flags kuro--sgr-flag-bold))
        (dim            (kuro--sgr-flag-set-p attr-flags kuro--sgr-flag-dim))
        (italic         (kuro--sgr-flag-set-p attr-flags kuro--sgr-flag-italic))
        (underline      (kuro--sgr-flag-set-p attr-flags kuro--sgr-flag-underline))
        (blink-slow     (kuro--sgr-flag-set-p attr-flags kuro--sgr-flag-blink-slow))
        (blink-fast     (kuro--sgr-flag-set-p attr-flags kuro--sgr-flag-blink-fast))
        (inverse        (kuro--sgr-flag-set-p attr-flags kuro--sgr-flag-inverse))
        (hidden         (kuro--sgr-flag-set-p attr-flags kuro--sgr-flag-hidden))
        (strikethrough  (kuro--sgr-flag-set-p attr-flags kuro--sgr-flag-strikethrough))
        ;; Underline style: bits 9-11 (mask 0xE00, shift right 9)
        (underline-style (ash (logand attr-flags kuro--sgr-underline-style-mask) (- kuro--sgr-underline-style-shift))))
    (list :bold bold
          :italic italic
          :underline underline
          :underline-style underline-style
          :strike-through strikethrough
          :inverse inverse
          :dim dim
          :blink-slow blink-slow
          :blink-fast blink-fast
          :hidden hidden)))

(defun kuro--underline-style-to-face-prop (style underline-color)
  "Convert underline STYLE integer and UNDERLINE-COLOR to an Emacs :underline value.
STYLE is the decoded underline style integer (0-5):
  0 = None (no underline)
  1 = Straight
  2 = Double
  3 = Curly (undercurl / wave)
  4 = Dotted
  5 = Dashed
UNDERLINE-COLOR is an Emacs color string or nil.
Returns the value for the :underline face attribute, or nil for no underline."
  (pcase style
    (0 nil)   ; None
    (1 (if underline-color
           (list :color underline-color :style 'line)
         t))
    (2 (if underline-color
           (list :color underline-color :style 'line)
         (list :style 'double-line)))
    (3 (if underline-color
           (list :color underline-color :style 'wave)
         (list :style 'wave)))
    (4 (if underline-color
           (list :color underline-color :style 'dots)
         (list :style 'dots)))
    (5 (if underline-color
           (list :color underline-color :style 'dashes)
         (list :style 'dashes)))
    (_ t)))  ; Unknown style: plain underline

(defun kuro--attrs-to-face-props (fg bg attr-flags underline-color)
  "Convert SGR attributes to Emacs face property list.
FG and BG are decoded color specs (from `kuro--decode-ffi-color').
ATTR-FLAGS is the SGR bitmask integer.  UNDERLINE-COLOR is an Emacs
color string or nil.

Only non-default attributes are included in the returned plist.  Omitting
:weight 'normal and :slant 'normal lets text inherit those properties from the
buffer's default face, which is both more correct and faster to render —
Emacs does not need to recompute font metrics for every cell.

Bit-flag tests are inlined to avoid the intermediate 20-element plist
that `kuro--decode-attrs' would allocate on every call."
  (let* ((fg-color (kuro--color-to-emacs fg))
         (bg-color (kuro--color-to-emacs bg))
         ;; Inline bit-flag tests (same logic as kuro--decode-attrs)
         (bold          (kuro--sgr-flag-set-p attr-flags kuro--sgr-flag-bold))
         (dim           (kuro--sgr-flag-set-p attr-flags kuro--sgr-flag-dim))
         (italic        (kuro--sgr-flag-set-p attr-flags kuro--sgr-flag-italic))
         (underline     (kuro--sgr-flag-set-p attr-flags kuro--sgr-flag-underline))
         (strikethrough (kuro--sgr-flag-set-p attr-flags kuro--sgr-flag-strikethrough))
         (inverse       (kuro--sgr-flag-set-p attr-flags kuro--sgr-flag-inverse))
         (underline-style (ash (logand attr-flags kuro--sgr-underline-style-mask)
                               (- kuro--sgr-underline-style-shift)))
         ;; Build :underline value: prefer explicit style if underline bit is set
         (underline-val
          (when underline
            (if (and underline-style (> underline-style 0))
                (kuro--underline-style-to-face-prop underline-style underline-color)
              ;; Straight underline (style 0 or no style bits set)
              (if underline-color
                  (list :color underline-color :style 'line)
                t)))))
    (let (result)
      (when inverse (setq result (nconc (list :inverse-video t) result)))
      (when strikethrough (setq result (nconc (list :strike-through t) result)))
      (when underline-val (setq result (nconc (list :underline underline-val) result)))
      (when italic (setq result (nconc (list :slant 'italic) result)))
      (cond (bold (setq result (nconc (list :weight 'bold) result)))
            (dim  (setq result (nconc (list :weight 'light) result))))
      (when bg-color (setq result (nconc (list :background bg-color) result)))
      (when fg-color (setq result (nconc (list :foreground fg-color) result)))
      result)))

(provide 'kuro-faces-attrs)

;;; kuro-faces-attrs.el ends here
