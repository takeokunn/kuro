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
  (let ((props (kuro--attrs-to-face-props
                '(:foreground :default :background :default :flags 0))))
    (should-not (plist-get props :weight))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-bold ()
  "Bold flag (0x01) → :weight bold."
  (let ((props (kuro--attrs-to-face-props
                '(:foreground :default :background :default :flags 1))))
    (should (eq (plist-get props :weight) 'bold))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-dim ()
  "Dim flag (0x02) → :weight light."
  (let ((props (kuro--attrs-to-face-props
                '(:foreground :default :background :default :flags 2))))
    (should (eq (plist-get props :weight) 'light))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-italic ()
  "Italic flag (0x04) → :slant italic."
  (let ((props (kuro--attrs-to-face-props
                '(:foreground :default :background :default :flags 4))))
    (should (eq (plist-get props :slant) 'italic))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-no-italic-omits-slant ()
  "No italic → :slant absent (nil), to inherit from default face."
  (let ((props (kuro--attrs-to-face-props
                '(:foreground :default :background :default :flags 0))))
    (should-not (plist-get props :slant))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-strikethrough ()
  "Strikethrough flag (0x100) → :strike-through t."
  (let ((props (kuro--attrs-to-face-props
                '(:foreground :default :background :default :flags #x100))))
    (should (plist-get props :strike-through))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-inverse ()
  "Inverse flag (0x40) → :inverse-video t."
  (let ((props (kuro--attrs-to-face-props
                '(:foreground :default :background :default :flags #x40))))
    (should (plist-get props :inverse-video))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-rgb-foreground ()
  "RGB foreground → :foreground #rrggbb hex string."
  (let ((props (kuro--attrs-to-face-props
                '(:foreground (rgb . #xFF8000) :background :default :flags 0))))
    (should (equal (plist-get props :foreground) "#ff8000"))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-default-fg-bg-omitted ()
  ":default fg and bg → no :foreground or :background in output."
  (let ((props (kuro--attrs-to-face-props
                '(:foreground :default :background :default :flags 0))))
    (should-not (plist-get props :foreground))
    (should-not (plist-get props :background))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-underline-with-style ()
  "Underline bit + style 3 → :underline (:style wave)."
  ;; bits: underline=0x08, style=3 (0x600)
  (let* ((flags (logior #x08 #x600))
         (props (kuro--attrs-to-face-props
                 (list :foreground :default :background :default :flags flags))))
    (let ((ul (plist-get props :underline)))
      (should ul)
      (should (eq (plist-get ul :style) 'wave)))))

(provide 'kuro-faces-attrs-test)

;;; kuro-faces-attrs-test.el ends here
