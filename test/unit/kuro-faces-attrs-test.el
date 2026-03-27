;;; kuro-faces-attrs-test.el --- Unit tests for kuro-faces-attrs.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-faces-attrs.el (SGR attribute bit-flag decoding and
;; conversion to Emacs face property lists).
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;;
;; Note: kuro-faces-test.el already tests kuro--decode-attrs and
;; kuro--underline-style-to-face-prop via (require 'kuro-faces).  This file
;; targets kuro-faces-attrs.el directly and adds coverage for cases not
;; present in kuro-faces-test.el.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-faces-attrs)

;;; Group 1: kuro--decode-attrs — individual flag bits

(ert-deftest kuro-faces-attrs--bold-flag ()
  "Bit 0 (0x01) decodes as :bold t."
  (let ((decoded (kuro--decode-attrs #x01)))
    (should (plist-get decoded :bold))
    (should-not (plist-get decoded :italic))
    (should-not (plist-get decoded :dim))))

(ert-deftest kuro-faces-attrs--dim-flag ()
  "Bit 1 (0x02) decodes as :dim t."
  (let ((decoded (kuro--decode-attrs #x02)))
    (should (plist-get decoded :dim))
    (should-not (plist-get decoded :bold))))

(ert-deftest kuro-faces-attrs--italic-flag ()
  "Bit 2 (0x04) decodes as :italic t."
  (let ((decoded (kuro--decode-attrs #x04)))
    (should (plist-get decoded :italic))
    (should-not (plist-get decoded :bold))
    (should-not (plist-get decoded :underline))))

(ert-deftest kuro-faces-attrs--underline-flag ()
  "Bit 3 (0x08) decodes as :underline t."
  (let ((decoded (kuro--decode-attrs #x08)))
    (should (plist-get decoded :underline))))

(ert-deftest kuro-faces-attrs--blink-slow-flag ()
  "Bit 4 (0x10) decodes as :blink-slow t, not :blink-fast."
  (let ((decoded (kuro--decode-attrs #x10)))
    (should (plist-get decoded :blink-slow))
    (should-not (plist-get decoded :blink-fast))))

(ert-deftest kuro-faces-attrs--blink-fast-flag ()
  "Bit 5 (0x20) decodes as :blink-fast t, not :blink-slow."
  (let ((decoded (kuro--decode-attrs #x20)))
    (should (plist-get decoded :blink-fast))
    (should-not (plist-get decoded :blink-slow))))

(ert-deftest kuro-faces-attrs--inverse-flag ()
  "Bit 6 (0x40) decodes as :inverse t."
  (let ((decoded (kuro--decode-attrs #x40)))
    (should (plist-get decoded :inverse))))

(ert-deftest kuro-faces-attrs--hidden-flag ()
  "Bit 7 (0x80) decodes as :hidden t."
  (let ((decoded (kuro--decode-attrs #x80)))
    (should (plist-get decoded :hidden))))

(ert-deftest kuro-faces-attrs--strikethrough-flag ()
  "Bit 8 (0x100) decodes as :strike-through t."
  (let ((decoded (kuro--decode-attrs #x100)))
    (should (plist-get decoded :strike-through))))

;;; Group 2: kuro--decode-attrs — underline style field (bits 9-11)

(ert-deftest kuro-faces-attrs--underline-style-zero-when-no-bits ()
  "No style bits set → :underline-style 0."
  (let ((decoded (kuro--decode-attrs 0)))
    (should (= (plist-get decoded :underline-style) 0))))

(ert-deftest kuro-faces-attrs--underline-style-straight ()
  "Style 1 (straight): bits 9-11 = 001 → shift 9 = 0x200."
  (let ((decoded (kuro--decode-attrs (logior #x08 #x200))))
    (should (plist-get decoded :underline))
    (should (= (plist-get decoded :underline-style) 1))))

(ert-deftest kuro-faces-attrs--underline-style-double ()
  "Style 2 (double): bits 9-11 = 010 → shift 9 = 0x400."
  (let ((decoded (kuro--decode-attrs (logior #x08 #x400))))
    (should (plist-get decoded :underline))
    (should (= (plist-get decoded :underline-style) 2))))

(ert-deftest kuro-faces-attrs--underline-style-curly ()
  "Style 3 (curly/wave): bits 9-11 = 011 → 0x600."
  (let ((decoded (kuro--decode-attrs (logior #x08 #x600))))
    (should (= (plist-get decoded :underline-style) 3))))

(ert-deftest kuro-faces-attrs--underline-style-dotted ()
  "Style 4 (dotted): bits 9-11 = 100 → 0x800."
  (let ((decoded (kuro--decode-attrs (logior #x08 #x800))))
    (should (= (plist-get decoded :underline-style) 4))))

(ert-deftest kuro-faces-attrs--underline-style-dashed ()
  "Style 5 (dashed): bits 9-11 = 101 → 0xA00."
  (let ((decoded (kuro--decode-attrs (logior #x08 #xA00))))
    (should (= (plist-get decoded :underline-style) 5))))

;;; Group 3: kuro--decode-attrs — combined flags

(ert-deftest kuro-faces-attrs--bold-and-italic-combined ()
  "Flags 0x05 → :bold t AND :italic t, nothing else."
  (let ((decoded (kuro--decode-attrs #x05)))
    (should (plist-get decoded :bold))
    (should (plist-get decoded :italic))
    (should-not (plist-get decoded :underline))
    (should-not (plist-get decoded :dim))))

(ert-deftest kuro-faces-attrs--bold-and-dim-combined ()
  "Flags 0x03 → :bold t AND :dim t (both set simultaneously)."
  (let ((decoded (kuro--decode-attrs #x03)))
    (should (plist-get decoded :bold))
    (should (plist-get decoded :dim))))

(ert-deftest kuro-faces-attrs--all-base-flags ()
  "Flags 0x1FF sets all 9 base attribute bits."
  (let ((decoded (kuro--decode-attrs #x1FF)))
    (should (plist-get decoded :bold))
    (should (plist-get decoded :dim))
    (should (plist-get decoded :italic))
    (should (plist-get decoded :underline))
    (should (plist-get decoded :blink-slow))
    (should (plist-get decoded :blink-fast))
    (should (plist-get decoded :inverse))
    (should (plist-get decoded :hidden))
    (should (plist-get decoded :strike-through))))

;;; Group 4: kuro--underline-style-to-face-prop

(ert-deftest kuro-faces-attrs--underline-style-none-returns-nil ()
  "Style 0 → nil regardless of color argument."
  (should-not (kuro--underline-style-to-face-prop 0 nil))
  (should-not (kuro--underline-style-to-face-prop 0 "#ff0000")))

(ert-deftest kuro-faces-attrs--underline-style-straight-no-color ()
  "Style 1 without color → t (plain Emacs underline)."
  (should (eq t (kuro--underline-style-to-face-prop 1 nil))))

(ert-deftest kuro-faces-attrs--underline-style-straight-with-color ()
  "Style 1 with color → plist :color ... :style line."
  (let ((result (kuro--underline-style-to-face-prop 1 "#ff0000")))
    (should (equal (plist-get result :color) "#ff0000"))
    (should (eq (plist-get result :style) 'line))))

(ert-deftest kuro-faces-attrs--underline-style-wave-no-color ()
  "Style 3 (curly/wave) without color → (:style wave)."
  (let ((result (kuro--underline-style-to-face-prop 3 nil)))
    (should (eq (plist-get result :style) 'wave))
    (should-not (plist-get result :color))))

(ert-deftest kuro-faces-attrs--underline-style-wave-with-color ()
  "Style 3 with color → (:color ... :style wave)."
  (let ((result (kuro--underline-style-to-face-prop 3 "#00ff00")))
    (should (equal (plist-get result :color) "#00ff00"))
    (should (eq (plist-get result :style) 'wave))))

(ert-deftest kuro-faces-attrs--underline-style-unknown-fallback ()
  "Unknown style value (>5) → t (plain underline fallback)."
  (should (eq t (kuro--underline-style-to-face-prop 99 nil)))
  (should (eq t (kuro--underline-style-to-face-prop 6 nil))))

;;; Group 5: kuro--attrs-to-face-props — integration of decode + conversion

(ert-deftest kuro-faces-attrs--attrs-to-face-props-empty-returns-no-weight ()
  "Default attrs (flags=0) → no :weight in the face props (inherit from default)."
  (let ((props (kuro--attrs-to-face-props :default :default 0 nil)))
    (should-not (plist-get props :weight))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-bold ()
  "Bold flag (0x01) → :weight bold."
  (let ((props (kuro--attrs-to-face-props :default :default 1 nil)))
    (should (eq (plist-get props :weight) 'bold))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-dim ()
  "Dim flag (0x02) → :weight light."
  (let ((props (kuro--attrs-to-face-props :default :default 2 nil)))
    (should (eq (plist-get props :weight) 'light))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-italic ()
  "Italic flag (0x04) → :slant italic."
  (let ((props (kuro--attrs-to-face-props :default :default 4 nil)))
    (should (eq (plist-get props :slant) 'italic))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-no-italic-omits-slant ()
  "No italic → :slant absent (nil), to inherit from default face."
  (let ((props (kuro--attrs-to-face-props :default :default 0 nil)))
    (should-not (plist-get props :slant))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-strikethrough ()
  "Strikethrough flag (0x100) → :strike-through t."
  (let ((props (kuro--attrs-to-face-props :default :default #x100 nil)))
    (should (plist-get props :strike-through))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-inverse ()
  "Inverse flag (0x40) → :inverse-video t."
  (let ((props (kuro--attrs-to-face-props :default :default #x40 nil)))
    (should (plist-get props :inverse-video))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-rgb-foreground ()
  "RGB foreground → :foreground #rrggbb hex string."
  (let ((props (kuro--attrs-to-face-props '(rgb . #xFF8000) :default 0 nil)))
    (should (equal (plist-get props :foreground) "#ff8000"))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-default-fg-bg-omitted ()
  ":default fg and bg → no :foreground or :background in output."
  (let ((props (kuro--attrs-to-face-props :default :default 0 nil)))
    (should-not (plist-get props :foreground))
    (should-not (plist-get props :background))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-underline-with-style ()
  "Underline bit + style 3 → :underline (:style wave)."
  ;; bits: underline=0x08, style=3 (0x600)
  (let* ((flags (logior #x08 #x600))
         (props (kuro--attrs-to-face-props :default :default flags nil)))
    (let ((ul (plist-get props :underline)))
      (should ul)
      (should (eq (plist-get ul :style) 'wave)))))

;;; Group 6: kuro--sgr-flag-set-p

(ert-deftest kuro-faces-attrs--sgr-flag-set-p-returns-t-when-set ()
  "Returns t when the flag bit is set in the bitmask."
  (should (kuro--sgr-flag-set-p #xFF kuro--sgr-flag-bold))
  (should (kuro--sgr-flag-set-p #x01 kuro--sgr-flag-bold))
  (should (kuro--sgr-flag-set-p #x10 kuro--sgr-flag-blink-slow)))

(ert-deftest kuro-faces-attrs--sgr-flag-set-p-returns-nil-when-not-set ()
  "Returns nil when the flag bit is absent from the bitmask."
  (should-not (kuro--sgr-flag-set-p 0 kuro--sgr-flag-bold))
  (should-not (kuro--sgr-flag-set-p #x02 kuro--sgr-flag-bold))
  (should-not (kuro--sgr-flag-set-p #x01 kuro--sgr-flag-blink-slow)))

(ert-deftest kuro-faces-attrs--sgr-flag-set-p-returns-t-not-integer ()
  "Returns a boolean t/nil, not a raw integer (important: 0 is truthy in Elisp)."
  (should (eq t (kuro--sgr-flag-set-p #x01 kuro--sgr-flag-bold)))
  (should (eq nil (kuro--sgr-flag-set-p 0 kuro--sgr-flag-bold))))

;;; Group 7: kuro--decode-attrs — additional flag combinations

(ert-deftest kuro-faces-attrs--underline-and-blink-slow-combined ()
  "Flags underline (0x08) + blink-slow (0x10) both decode correctly."
  (let ((decoded (kuro--decode-attrs (logior #x08 #x10))))
    (should (plist-get decoded :underline))
    (should (plist-get decoded :blink-slow))
    (should-not (plist-get decoded :blink-fast))
    (should-not (plist-get decoded :bold))))

(ert-deftest kuro-faces-attrs--inverse-and-strikethrough-combined ()
  "Flags inverse (0x40) + strikethrough (0x100) both decode correctly."
  (let ((decoded (kuro--decode-attrs (logior #x40 #x100))))
    (should (plist-get decoded :inverse))
    (should (plist-get decoded :strike-through))
    (should-not (plist-get decoded :bold))
    (should-not (plist-get decoded :underline))))

(ert-deftest kuro-faces-attrs--bold-italic-underline-combined ()
  "Bold (0x01) + italic (0x04) + underline (0x08) all set simultaneously."
  (let ((decoded (kuro--decode-attrs (logior #x01 #x04 #x08))))
    (should (plist-get decoded :bold))
    (should (plist-get decoded :italic))
    (should (plist-get decoded :underline))
    (should-not (plist-get decoded :dim))
    (should-not (plist-get decoded :strike-through))))

(ert-deftest kuro-faces-attrs--all-flags-zero-clears-everything ()
  "flags=0 → every boolean attribute decodes as nil."
  (let ((decoded (kuro--decode-attrs 0)))
    (should-not (plist-get decoded :bold))
    (should-not (plist-get decoded :dim))
    (should-not (plist-get decoded :italic))
    (should-not (plist-get decoded :underline))
    (should-not (plist-get decoded :blink-slow))
    (should-not (plist-get decoded :blink-fast))
    (should-not (plist-get decoded :inverse))
    (should-not (plist-get decoded :hidden))
    (should-not (plist-get decoded :strike-through))))

;;; Group 8: kuro--underline-style-to-face-prop — remaining styles

(ert-deftest kuro-faces-attrs--underline-style-double-no-color ()
  "Style 2 (double-line) without color → (:style double-line)."
  (let ((result (kuro--underline-style-to-face-prop 2 nil)))
    (should (eq (plist-get result :style) 'double-line))
    (should-not (plist-get result :color))))

(ert-deftest kuro-faces-attrs--underline-style-double-with-color ()
  "Style 2 with color → (:color ... :style line) — same as straight with color."
  (let ((result (kuro--underline-style-to-face-prop 2 "#0000ff")))
    (should (equal (plist-get result :color) "#0000ff"))
    (should (eq (plist-get result :style) 'line))))

(ert-deftest kuro-faces-attrs--underline-style-dotted-no-color ()
  "Style 4 (dotted) without color → (:style dots)."
  (let ((result (kuro--underline-style-to-face-prop 4 nil)))
    (should (eq (plist-get result :style) 'dots))
    (should-not (plist-get result :color))))

(ert-deftest kuro-faces-attrs--underline-style-dotted-with-color ()
  "Style 4 (dotted) with color → (:color ... :style dots)."
  (let ((result (kuro--underline-style-to-face-prop 4 "#aabbcc")))
    (should (equal (plist-get result :color) "#aabbcc"))
    (should (eq (plist-get result :style) 'dots))))

(ert-deftest kuro-faces-attrs--underline-style-dashed-no-color ()
  "Style 5 (dashed) without color → (:style dashes)."
  (let ((result (kuro--underline-style-to-face-prop 5 nil)))
    (should (eq (plist-get result :style) 'dashes))
    (should-not (plist-get result :color))))

(ert-deftest kuro-faces-attrs--underline-style-dashed-with-color ()
  "Style 5 (dashed) with color → (:color ... :style dashes)."
  (let ((result (kuro--underline-style-to-face-prop 5 "#112233")))
    (should (equal (plist-get result :color) "#112233"))
    (should (eq (plist-get result :style) 'dashes))))

;;; Group 10: kuro--attrs-to-face-props — untested paths

(ert-deftest kuro-faces-attrs--attrs-to-face-props-underline-plain-t ()
  "Underline bit set with style 0 and no underline-color → :underline t."
  ;; Only the underline flag bit is set (0x08); no style bits; no underline-color.
  ;; Expected: (if underline-color (list ...) t) → t
  (let ((props (kuro--attrs-to-face-props :default :default #x08 nil)))
    (should (eq t (plist-get props :underline)))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-underline-plain-t-with-color ()
  "Underline bit set, style=0, underline-color present → :underline (:color ... :style line)."
  ;; style bits absent → style field = 0; underline-color provided.
  ;; Code path: (if underline-color (list :color ... :style 'line) t)
  (let* ((props (kuro--attrs-to-face-props :default :default #x08 "#123456")))
    (let ((ul (plist-get props :underline)))
      (should ul)
      (should (equal (plist-get ul :color) "#123456"))
      (should (eq (plist-get ul :style) 'line)))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-underline-style1-with-color ()
  "Underline bit + style 1 (straight) + underline-color → (:color ... :style line)."
  ;; style=1 → kuro--underline-style-to-face-prop returns (list :color c :style 'line)
  (let* ((flags (logior #x08 #x200))  ; style 1 = 0x200
         (props (kuro--attrs-to-face-props :default :default flags "#aabbcc")))
    (let ((ul (plist-get props :underline)))
      (should (equal (plist-get ul :color) "#aabbcc"))
      (should (eq (plist-get ul :style) 'line)))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-blink-and-hidden-absent-from-face-props ()
  "blink-slow, blink-fast, hidden flags are decoded but not mapped to face properties.
kuro--attrs-to-face-props silently ignores them — they have no Emacs face equivalent."
  (let* ((flags (logior kuro--sgr-flag-blink-slow
                        kuro--sgr-flag-blink-fast
                        kuro--sgr-flag-hidden))
         (props (kuro--attrs-to-face-props :default :default flags nil)))
    ;; No :weight, :slant, :underline, :strike-through, :inverse-video, :foreground, :background
    (should-not (plist-get props :weight))
    (should-not (plist-get props :slant))
    (should-not (plist-get props :underline))
    (should-not (plist-get props :strike-through))
    (should-not (plist-get props :inverse-video))
    (should-not (plist-get props :foreground))
    (should-not (plist-get props :background))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-dim-and-italic ()
  "Dim (0x02) + italic (0x04) → :weight light AND :slant italic."
  (let ((props (kuro--attrs-to-face-props :default :default #x06 nil)))
    (should (eq (plist-get props :weight) 'light))
    (should (eq (plist-get props :slant) 'italic))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-bold-wins-over-nothing ()
  "Bold alone → :weight bold only; no :slant, :underline, or other props."
  (let ((props (kuro--attrs-to-face-props :default :default #x01 nil)))
    (should (eq (plist-get props :weight) 'bold))
    (should-not (plist-get props :slant))
    (should-not (plist-get props :underline))
    (should-not (plist-get props :strike-through))
    (should-not (plist-get props :inverse-video))))

;;; Group 9: kuro--attrs-to-face-props — complete SGR state and color paths

(ert-deftest kuro-faces-attrs--attrs-to-face-props-rgb-background ()
  "RGB background → :background #rrggbb hex string."
  (let ((props (kuro--attrs-to-face-props :default '(rgb . #x003FFF) 0 nil)))
    (should (equal (plist-get props :background) "#003fff"))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-both-rgb-fg-and-bg ()
  "RGB fg and bg both present → :foreground and :background in output plist."
  (let ((props (kuro--attrs-to-face-props
                '(rgb . #xFF0000)
                '(rgb . #x0000FF)
                0 nil)))
    (should (equal (plist-get props :foreground) "#ff0000"))
    (should (equal (plist-get props :background) "#0000ff"))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-underline-with-color ()
  "Underline bit set + underline-color → :underline (:color ... :style line)."
  (let* ((flags #x08)
         (props (kuro--attrs-to-face-props :default :default flags "#ff00ff")))
    (let ((ul (plist-get props :underline)))
      (should ul)
      (should (equal (plist-get ul :color) "#ff00ff"))
      (should (eq (plist-get ul :style) 'line)))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-bold-and-italic ()
  "Bold (0x01) + italic (0x04) → :weight bold AND :slant italic."
  (let ((props (kuro--attrs-to-face-props :default :default #x05 nil)))
    (should (eq (plist-get props :weight) 'bold))
    (should (eq (plist-get props :slant) 'italic))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-full-sgr-state ()
  "A fully-specified SGR state produces all expected face properties."
  ;; bold(0x01) + italic(0x04) + underline(0x08) + strikethrough(0x100)
  ;; + inverse(0x40) = 0x14D
  (let* ((flags (logior #x01 #x04 #x08 #x40 #x100))
         (props (kuro--attrs-to-face-props
                 '(rgb . #xFFFFFF)
                 '(rgb . #x000000)
                 flags nil)))
    (should (eq (plist-get props :weight) 'bold))
    (should (eq (plist-get props :slant) 'italic))
    (should (plist-get props :underline))
    (should (plist-get props :strike-through))
    (should (plist-get props :inverse-video))
    (should (stringp (plist-get props :foreground)))
    (should (stringp (plist-get props :background)))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-underline-dashed-style ()
  "Underline bit + style 5 (dashed) → :underline (:style dashes)."
  (let* ((flags (logior #x08 #xA00))  ; style 5 = 0xA00
         (props (kuro--attrs-to-face-props :default :default flags nil)))
    (let ((ul (plist-get props :underline)))
      (should ul)
      (should (eq (plist-get ul :style) 'dashes)))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-underline-dotted-style ()
  "Underline bit + style 4 (dotted) → :underline (:style dots)."
  (let* ((flags (logior #x08 #x800))  ; style 4 = 0x800
         (props (kuro--attrs-to-face-props :default :default flags nil)))
    (let ((ul (plist-get props :underline)))
      (should ul)
      (should (eq (plist-get ul :style) 'dots)))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-dim-excludes-bold ()
  "Dim flag (0x02) alone → :weight light, NOT :weight bold."
  (let ((props (kuro--attrs-to-face-props :default :default 2 nil)))
    (should (eq (plist-get props :weight) 'light))
    (should-not (eq (plist-get props :weight) 'bold))))

;;; Group 11: kuro--underline-style-to-face-prop — style-0 ignores color arg

(ert-deftest kuro-faces-attrs--underline-style0-with-color-still-nil ()
  "Style 0 returns nil even when underline-color is non-nil."
  (should-not (kuro--underline-style-to-face-prop 0 "#ff0000"))
  (should-not (kuro--underline-style-to-face-prop 0 "#ffffff")))

(ert-deftest kuro-faces-attrs--underline-style-unknown-with-color-is-t ()
  "Unknown style value with color still returns t (plain fallback; color ignored)."
  (should (eq t (kuro--underline-style-to-face-prop 42 "#aabbcc")))
  (should (eq t (kuro--underline-style-to-face-prop 6 "#123456"))))

(ert-deftest kuro-faces-attrs--underline-style-dashed-color-preserves-style ()
  "Style 5 with color has :style dashes (not line or wave)."
  (let ((result (kuro--underline-style-to-face-prop 5 "#001122")))
    (should (eq (plist-get result :style) 'dashes))
    (should (equal (plist-get result :color) "#001122"))))

(ert-deftest kuro-faces-attrs--underline-style-dotted-color-preserves-style ()
  "Style 4 with color has :style dots (not line)."
  (let ((result (kuro--underline-style-to-face-prop 4 "#334455")))
    (should (eq (plist-get result :style) 'dots))
    (should (equal (plist-get result :color) "#334455"))))

;;; Group 12: kuro--attrs-to-face-props — bold+dim cond priority and named colors

(ert-deftest kuro-faces-attrs--attrs-to-face-props-bold-takes-priority-over-dim ()
  "When both bold (0x01) and dim (0x02) flags are set, bold wins (:weight bold)."
  ;; The cond in kuro--attrs-to-face-props: (cond (bold ...) (dim ...)) — bold tested first.
  (let ((props (kuro--attrs-to-face-props :default :default #x03 nil)))
    (should (eq (plist-get props :weight) 'bold))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-named-fg-resolves ()
  "Named foreground color is resolved to a hex string via kuro--named-colors."
  ;; 'red' should be in kuro--named-colors as a hex string.
  (let ((props (kuro--attrs-to-face-props '(named . "red") :default 0 nil)))
    (let ((fg (plist-get props :foreground)))
      (should (stringp fg))
      (should (string-match-p "^#[0-9a-fA-F]\\{6\\}$" fg)))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-named-bg-resolves ()
  "Named background color is resolved to a hex string via kuro--named-colors."
  (let ((props (kuro--attrs-to-face-props :default '(named . "blue") 0 nil)))
    (let ((bg (plist-get props :background)))
      (should (stringp bg))
      (should (string-match-p "^#[0-9a-fA-F]\\{6\\}$" bg)))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-indexed-fg-resolves ()
  "Indexed foreground color (cube range) resolves to a hex string."
  (let ((props (kuro--attrs-to-face-props '(indexed . 196) :default 0 nil)))
    (let ((fg (plist-get props :foreground)))
      (should (stringp fg))
      (should (string-match-p "^#[0-9a-fA-F]\\{6\\}$" fg)))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-all-visual-attrs ()
  "All visual attrs combined: bold+italic+underline+strikethrough+inverse+RGB fg+bg."
  ;; bold=0x01, italic=0x04, underline=0x08, strikethrough=0x100, inverse=0x40
  (let* ((flags (logior #x01 #x04 #x08 #x100 #x40))
         (props (kuro--attrs-to-face-props '(rgb . #xFFFFFF) '(rgb . #x000000) flags nil)))
    (should (eq (plist-get props :weight) 'bold))
    (should (eq (plist-get props :slant) 'italic))
    (should (plist-get props :underline))
    (should (plist-get props :strike-through))
    (should (plist-get props :inverse-video))
    (should (equal (plist-get props :foreground) "#ffffff"))
    (should (equal (plist-get props :background) "#000000"))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-no-underline-no-underline-prop ()
  "Without underline flag, :underline key is absent (nil) from result."
  (let ((props (kuro--attrs-to-face-props :default :default 0 "#ff0000")))
    ;; underline-color is provided but the underline flag bit is off.
    (should-not (plist-get props :underline))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-underline-style2-with-color ()
  "Underline bit + style 2 (double) + color → (:color ... :style line)."
  ;; From source: style 2 with color uses 'line (same code path as style 1+color).
  (let* ((flags (logior #x08 #x400))  ; style 2 = 0x400
         (props (kuro--attrs-to-face-props :default :default flags "#667788")))
    (let ((ul (plist-get props :underline)))
      (should ul)
      (should (equal (plist-get ul :color) "#667788"))
      (should (eq (plist-get ul :style) 'line)))))

(provide 'kuro-faces-attrs-test)

;;; kuro-faces-attrs-test.el ends here
