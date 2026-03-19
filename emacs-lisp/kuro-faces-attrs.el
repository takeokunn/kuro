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
  (let ((bold           (/= 0 (logand attr-flags kuro--sgr-flag-bold)))
        (dim            (/= 0 (logand attr-flags kuro--sgr-flag-dim)))
        (italic         (/= 0 (logand attr-flags kuro--sgr-flag-italic)))
        (underline      (/= 0 (logand attr-flags kuro--sgr-flag-underline)))
        (blink-slow     (/= 0 (logand attr-flags kuro--sgr-flag-blink-slow)))
        (blink-fast     (/= 0 (logand attr-flags kuro--sgr-flag-blink-fast)))
        (inverse        (/= 0 (logand attr-flags kuro--sgr-flag-inverse)))
        (hidden         (/= 0 (logand attr-flags kuro--sgr-flag-hidden)))
        (strikethrough  (/= 0 (logand attr-flags kuro--sgr-flag-strikethrough)))
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

(defun kuro--attrs-to-face-props (attrs)
  "Convert SGR attributes plist ATTRS to Emacs face property list.
ATTRS is a plist with keys :foreground, :background, :flags, and
optionally :underline-color (an Emacs color string for the underline).

Only non-default attributes are included in the returned plist.  Omitting
:weight 'normal and :slant 'normal lets text inherit those properties from the
buffer's default face, which is both more correct and faster to render —
Emacs does not need to recompute font metrics for every cell."
  (let* ((fg (plist-get attrs :foreground))
         (bg (plist-get attrs :background))
         (fg-color (kuro--color-to-emacs fg))
         (bg-color (kuro--color-to-emacs bg))
         (flags (plist-get attrs :flags))
         (decoded (kuro--decode-attrs (or flags 0)))
         (bold (plist-get decoded :bold))
         (italic (plist-get decoded :italic))
         (underline (plist-get decoded :underline))
         (underline-style (plist-get decoded :underline-style))
         (strikethrough (plist-get decoded :strike-through))
         (inverse (plist-get decoded :inverse))
         (dim (plist-get decoded :dim))
         (underline-color (plist-get attrs :underline-color))
         ;; Build :underline value: prefer explicit style if underline bit is set
         (underline-val
          (when underline
            (if (and underline-style (> underline-style 0))
                (kuro--underline-style-to-face-prop underline-style underline-color)
              ;; Straight underline (style 0 or no style bits set)
              (if underline-color
                  (list :color underline-color :style 'line)
                t)))))
    (nconc
     (when fg-color (list :foreground fg-color))
     (when bg-color (list :background bg-color))
     ;; Only emit :weight when non-normal so the default face is inherited.
     (cond (bold  (list :weight 'bold))
           (dim   (list :weight 'light)))
     ;; Only emit :slant when italic; omitting it inherits 'normal from default.
     (when italic (list :slant 'italic))
     (when underline-val (list :underline underline-val))
     (when strikethrough (list :strike-through t))
     (when inverse (list :inverse-video t)))))

(provide 'kuro-faces-attrs)

;;; kuro-faces-attrs.el ends here
