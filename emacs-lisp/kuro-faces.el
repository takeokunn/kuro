;;; kuro-faces.el --- Color conversion and face management for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; This file provides color conversion, SGR attribute decoding, and face
;; caching for the Kuro terminal emulator.
;;
;; # Responsibilities
;;
;; - ANSI/256-color/TrueColor → Emacs color string conversion
;; - FFI color encoding → Emacs color spec decoding
;; - SGR attribute bitmask → face property list conversion
;; - Per-session face cache (avoids recreating identical faces)
;; - Font remapping for per-buffer font family/size overrides
;;
;; # Dependencies
;;
;; Depends on `kuro-config' for `kuro--named-colors', `kuro-font-family',
;; and `kuro-font-size'.  Has no dependency on `kuro-ffi'.

;;; Code:

(require 'kuro-config)

;; Core Emacs face remapping functions (provided by C core; suppress warnings)
(declare-function face-remap-remove-relative "face-remap" (cookie))

;;; Face cache

(defvar kuro--face-cache (make-hash-table :test 'equal)
  "Cache computed faces to avoid recreating them for same attribute combinations.")

(defvar-local kuro--font-remap-cookie nil
  "Cookie returned by `face-remap-add-relative' for font customization.
Stored per-buffer so the remap can be cleanly removed when settings change
or when the buffer is killed.  Internal state; do not set directly.")
(put 'kuro--font-remap-cookie 'permanent-local t)

(defvar kuro--truecolor-available-p nil
  "Cached result of checking TrueColor support.")

;;; TrueColor detection

;;;###autoload
(defun kuro--check-truecolor ()
  "Check if Emacs supports TrueColor (24-bit colors)."
  (or (display-graphic-p)
      (and (>= (display-color-cells) 16777216)
           (setq kuro--truecolor-available-p t))))

;;; Font remapping

;;;###autoload
(defun kuro--apply-font-to-buffer (buf)
  "Apply `kuro-font-family' and `kuro-font-size' settings to BUF.
Uses `face-remap-add-relative' to override the default face in the buffer.
Removes any previously installed remap cookie before applying a new one.
This function is a no-op in non-graphical (terminal) Emacs frames."
  (when (display-graphic-p)
    (with-current-buffer buf
      (when kuro--font-remap-cookie
        (face-remap-remove-relative kuro--font-remap-cookie)
        (setq kuro--font-remap-cookie nil))
      (when (or kuro-font-family kuro-font-size)
        (setq kuro--font-remap-cookie
              (apply #'face-remap-add-relative
                     'default
                     (append
                      (when kuro-font-family (list :family kuro-font-family))
                      (when kuro-font-size   (list :height (* 10 kuro-font-size))))))))))

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
       ('named (cdr (assoc (cdr color) kuro--named-colors)))
       ('indexed (kuro--indexed-to-emacs (cdr color)))
       ('rgb (kuro--rgb-to-emacs (cdr color)))))
    (_ nil)))

(defun kuro--indexed-to-emacs (idx)
  "Convert 256-color palette index IDX to Emacs color string."
  (cond
   ((<= idx 15)
    (let* ((names ["black" "red" "green" "yellow"
                   "blue" "magenta" "cyan" "white"
                   "bright-black" "bright-red" "bright-green" "bright-yellow"
                   "bright-blue" "bright-magenta" "bright-cyan" "bright-white"])
           (name (aref names idx)))
      (cdr (assoc name kuro--named-colors))))
   ((<= idx 231)
    (let* ((n (- idx 16))
           (r (* (floor (/ n 36)) 51))
           (g (* (mod (floor (/ n 6)) 6) 51))
           (b (* (mod n 6) 51)))
      (format "#%02x%02x%02x" r g b)))
   ((<= idx 255)
    (let* ((n (- idx 232))
           (v (+ (* n 10) 8)))
      (format "#%02x%02x%02x" v v v)))
   (t nil)))

(defun kuro--rgb-to-emacs (rgb-value)
  "Convert 24-bit RGB-VALUE to Emacs color string."
  (let ((r (logand (ash rgb-value -16) #xFF))
        (g (logand (ash rgb-value -8)  #xFF))
        (b (logand rgb-value            #xFF)))
    (format "#%02x%02x%02x" r g b)))

;;; FFI color decoding

(defun kuro--decode-ffi-color (color-enc)
  "Decode FFI color encoding COLOR-ENC to Emacs color spec.
COLOR-ENC is a u32 value:
  - #xFF000000: default color (sentinel, distinct from true black)
  - Bit 31 set: named color (lower 8 bits = index into standard 16 names)
  - Bit 30 set: indexed color (lower 8 bits = palette index 0-255)
  - Otherwise: RGB packed into 24 bits (RRGGBB); 0 = true black Rgb(0,0,0)"
  (cond
   ((= color-enc #xFF000000)
    :default)
   ((/= 0 (logand color-enc #x80000000))
    (let* ((idx (logand color-enc #xFF))
           (names ["black" "red" "green" "yellow"
                   "blue" "magenta" "cyan" "white"
                   "bright-black" "bright-red" "bright-green" "bright-yellow"
                   "bright-blue" "bright-magenta" "bright-cyan" "bright-white"])
           (name (aref names idx)))
      (cons 'named name)))
   ((/= 0 (logand color-enc #x40000000))
    (cons 'indexed (logand color-enc #xFF)))
   (t
    (let ((r (logand (ash color-enc -16) #xFF))
          (g (logand (ash color-enc -8)  #xFF))
          (b (logand color-enc            #xFF)))
      (cons 'rgb (logior (ash r 16) (ash g 8) b))))))

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
  (let ((bold           (/= 0 (logand attr-flags #x01)))
        (dim            (/= 0 (logand attr-flags #x02)))
        (italic         (/= 0 (logand attr-flags #x04)))
        (underline      (/= 0 (logand attr-flags #x08)))
        (blink-slow     (/= 0 (logand attr-flags #x10)))
        (blink-fast     (/= 0 (logand attr-flags #x20)))
        (inverse        (/= 0 (logand attr-flags #x40)))
        (hidden         (/= 0 (logand attr-flags #x80)))
        (strikethrough  (/= 0 (logand attr-flags #x100)))
        ;; Underline style: bits 9-11 (mask 0xE00, shift right 9)
        (underline-style (ash (logand attr-flags #xE00) -9)))
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
         ;; Emacs 29+ supports double underline via :style 'double-line
         (if (boundp 'face-underline-style)
             (list :style 'double-line)
           t)))
    (3 (if underline-color
           (list :color underline-color :style 'wave)
         (list :style 'wave)))
    (4 (if underline-color
           (list :color underline-color :style 'dots)
         ;; :style 'dots is Emacs 29+; fall back to plain underline
         (if (boundp 'face-underline-style)
             (list :style 'dots)
           t)))
    (5 (if underline-color
           (list :color underline-color :style 'dashes)
         ;; :style 'dashes is Emacs 29+; fall back to plain underline
         (if (boundp 'face-underline-style)
             (list :style 'dashes)
           t)))
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

;;; Face caching

(defun kuro--make-face (attrs)
  "Create an Emacs face spec from attribute plist ATTRS."
  (let ((props (kuro--attrs-to-face-props attrs)))
    (list props)))

(defun kuro--get-cached-face (attrs)
  "Get or create a cached face for given attributes ATTRS.
ATTRS is a plist containing :foreground, :background, :flags, and
optionally :underline-color."
  (let ((key (list (plist-get attrs :foreground)
                   (plist-get attrs :background)
                   (plist-get attrs :flags)
                   (plist-get attrs :underline-color))))
    (or (gethash key kuro--face-cache)
        (puthash key (kuro--make-face attrs) kuro--face-cache))))

(defun kuro--clear-face-cache ()
  "Clear the face cache to free memory."
  (clrhash kuro--face-cache))

;;; Face application

(defun kuro--apply-face-range (start end attrs)
  "Apply a face to buffer positions START to END with SGR attributes ATTRS.
ATTRS is a plist with :foreground, :background, and :flags keys."
  (let ((face (kuro--get-cached-face attrs)))
    (add-text-properties start end `(face ,face))))

(defun kuro--apply-faces (line-num face-ranges)
  "Apply SGR faces to LINE-NUM based on FACE-RANGES from the old plist API.
LINE-NUM is the 0-indexed line number.
FACE-RANGES is a list of (START . (END . ATTRS)) where START and END
are column positions (0-indexed) and ATTRS is a plist with SGR attributes."
  (save-excursion
    (goto-char (point-min))
    (forward-line line-num)
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t)
          (line-start (point))
          (line-end (line-end-position)))
      (dolist (face-range face-ranges)
        (let* ((start-col (car face-range))
               (end-col (car (cdr face-range)))
               (attrs (cdr (cdr face-range)))
               (start-pos (min (+ line-start start-col) line-end))
               (end-pos (min (+ line-start end-col) line-end)))
          (when (> end-pos start-pos)
            (kuro--apply-face-range start-pos end-pos attrs)))))))

(provide 'kuro-faces)

;;; kuro-faces.el ends here
