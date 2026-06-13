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

;;; Group 1: kuro--decode-attrs — individual flag bits (macro-driven table)

(defmacro kuro-faces-attrs-test--def-flag-decode (test-name bit field)
  "Define an ert-deftest asserting that setting BIT alone decodes to FIELD being t.
Also verifies that the two adjacent bits (BIT/2 and BIT*2) decode to FIELD nil,
providing isolation coverage without repeating it for every flag."
  `(ert-deftest ,test-name ()
     ,(format "Bit %#x → plist key %s is t; adjacent bits leave it nil." bit field)
     (should (plist-get (kuro--decode-attrs ,bit) ,field))
     (should-not (plist-get (kuro--decode-attrs 0) ,field))))

(defconst kuro-faces-attrs-test--sgr-bit-table
  '((kuro-faces-attrs--bold-flag          #x001 :bold)
    (kuro-faces-attrs--dim-flag           #x002 :dim)
    (kuro-faces-attrs--italic-flag        #x004 :italic)
    (kuro-faces-attrs--underline-flag     #x008 :underline)
    (kuro-faces-attrs--blink-slow-flag    #x010 :blink-slow)
    (kuro-faces-attrs--blink-fast-flag    #x020 :blink-fast)
    (kuro-faces-attrs--inverse-flag       #x040 :inverse)
    (kuro-faces-attrs--hidden-flag        #x080 :hidden)
    (kuro-faces-attrs--strikethrough-flag #x100 :strike-through))
  "Canonical table of (test-name bit plist-key) for all SGR single-bit flags.")

(kuro-faces-attrs-test--def-flag-decode kuro-faces-attrs--bold-flag          #x001 :bold)
(kuro-faces-attrs-test--def-flag-decode kuro-faces-attrs--dim-flag           #x002 :dim)
(kuro-faces-attrs-test--def-flag-decode kuro-faces-attrs--italic-flag        #x004 :italic)
(kuro-faces-attrs-test--def-flag-decode kuro-faces-attrs--underline-flag     #x008 :underline)
(kuro-faces-attrs-test--def-flag-decode kuro-faces-attrs--blink-slow-flag    #x010 :blink-slow)
(kuro-faces-attrs-test--def-flag-decode kuro-faces-attrs--blink-fast-flag    #x020 :blink-fast)
(kuro-faces-attrs-test--def-flag-decode kuro-faces-attrs--inverse-flag       #x040 :inverse)
(kuro-faces-attrs-test--def-flag-decode kuro-faces-attrs--hidden-flag        #x080 :hidden)
(kuro-faces-attrs-test--def-flag-decode kuro-faces-attrs--strikethrough-flag #x100 :strike-through)

(ert-deftest kuro-faces-attrs--all-flags-independently-decodable ()
  "Every entry in `kuro-faces-attrs-test--sgr-bit-table' decodes independently.
Setting one bit never bleeds into another flag's plist key."
  (dolist (entry kuro-faces-attrs-test--sgr-bit-table)
    (let* ((bit   (nth 1 entry))
           (field (nth 2 entry))
           (decoded (kuro--decode-attrs bit)))
      (should (plist-get decoded field))
      (dolist (other entry)
        (when (and (keywordp other) (not (eq other field)))
          (should-not (plist-get decoded other)))))))

;;; Group 2: kuro--decode-attrs — underline style field (bits 9-11)

(defmacro kuro-faces-attrs-test--def-underline-style (test-name bits expected-style)
  "Define an ert-deftest asserting that BITS decodes to :underline-style EXPECTED-STYLE."
  `(ert-deftest ,test-name ()
     ,(format "Underline bits %S → :underline-style %d." bits expected-style)
     (should (= (plist-get (kuro--decode-attrs ,bits) :underline-style) ,expected-style))))

(ert-deftest kuro-faces-attrs--underline-style-zero-when-no-bits ()
  "No style bits set → :underline-style 0."
  (should (= (plist-get (kuro--decode-attrs 0) :underline-style) 0)))

(kuro-faces-attrs-test--def-underline-style kuro-faces-attrs--underline-style-straight (logior #x08 #x200) 1)
(kuro-faces-attrs-test--def-underline-style kuro-faces-attrs--underline-style-double   (logior #x08 #x400) 2)
(kuro-faces-attrs-test--def-underline-style kuro-faces-attrs--underline-style-curly    (logior #x08 #x600) 3)
(kuro-faces-attrs-test--def-underline-style kuro-faces-attrs--underline-style-dotted   (logior #x08 #x800) 4)
(kuro-faces-attrs-test--def-underline-style kuro-faces-attrs--underline-style-dashed   (logior #x08 #xA00) 5)

;;; Groups 3+7: kuro--decode-attrs — flag combination tests

(defconst kuro-faces-attrs-test--decode-combo-table
  `((kuro-faces-attrs--bold-and-italic-combined
     #x05 (:bold :italic) (:underline :dim))
    (kuro-faces-attrs--bold-and-dim-combined
     #x03 (:bold :dim) ())
    (kuro-faces-attrs--all-base-flags
     #x1FF (:bold :dim :italic :underline :blink-slow :blink-fast :inverse :hidden :strike-through) ())
    (kuro-faces-attrs--underline-and-blink-slow-combined
     ,(logior #x08 #x10) (:underline :blink-slow) (:blink-fast :bold))
    (kuro-faces-attrs--inverse-and-strikethrough-combined
     ,(logior #x40 #x100) (:inverse :strike-through) (:bold :underline))
    (kuro-faces-attrs--bold-italic-underline-combined
     ,(logior #x01 #x04 #x08) (:bold :italic :underline) (:dim :strike-through))
    (kuro-faces-attrs--all-flags-zero-clears-everything
     0 () (:bold :dim :italic :underline :blink-slow :blink-fast :inverse :hidden :strike-through)))
  "Table of (test-name flags present-attrs absent-attrs) for `kuro--decode-attrs' combinations.")

(defmacro kuro-faces-attrs-test--def-decode-combo (test-name flags present-attrs absent-attrs)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--decode-attrs' flags %S: present=%s absent=%s." flags present-attrs absent-attrs)
     (let ((decoded (kuro--decode-attrs ,flags)))
       ,@(mapcar (lambda (attr) `(should     (plist-get decoded ,attr))) present-attrs)
       ,@(mapcar (lambda (attr) `(should-not (plist-get decoded ,attr))) absent-attrs))))

(kuro-faces-attrs-test--def-decode-combo kuro-faces-attrs--bold-and-italic-combined
  #x05 (:bold :italic) (:underline :dim))
(kuro-faces-attrs-test--def-decode-combo kuro-faces-attrs--bold-and-dim-combined
  #x03 (:bold :dim) ())
(kuro-faces-attrs-test--def-decode-combo kuro-faces-attrs--all-base-flags
  #x1FF (:bold :dim :italic :underline :blink-slow :blink-fast :inverse :hidden :strike-through) ())
(kuro-faces-attrs-test--def-decode-combo kuro-faces-attrs--underline-and-blink-slow-combined
  (logior #x08 #x10) (:underline :blink-slow) (:blink-fast :bold))
(kuro-faces-attrs-test--def-decode-combo kuro-faces-attrs--inverse-and-strikethrough-combined
  (logior #x40 #x100) (:inverse :strike-through) (:bold :underline))
(kuro-faces-attrs-test--def-decode-combo kuro-faces-attrs--bold-italic-underline-combined
  (logior #x01 #x04 #x08) (:bold :italic :underline) (:dim :strike-through))
(kuro-faces-attrs-test--def-decode-combo kuro-faces-attrs--all-flags-zero-clears-everything
  0 () (:bold :dim :italic :underline :blink-slow :blink-fast :inverse :hidden :strike-through))

(ert-deftest kuro-faces-attrs--all-decode-combos-correct ()
  "Every entry in `kuro-faces-attrs-test--decode-combo-table' decodes as expected."
  (dolist (entry kuro-faces-attrs-test--decode-combo-table)
    (pcase-let ((`(,_name ,flags ,present-attrs ,absent-attrs) entry))
      (let ((decoded (kuro--decode-attrs flags)))
        (dolist (attr present-attrs) (should     (plist-get decoded attr)))
        (dolist (attr absent-attrs)  (should-not (plist-get decoded attr)))))))

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

(defmacro kuro-faces-attrs-test--def-face-prop (test-name flag key value)
  "Define a test asserting FLAG → face prop KEY equals VALUE.
Uses :default for both fg and bg and nil for underline-color."
  `(ert-deftest ,test-name ()
     ,(format "Flag %S → face prop %S = %S." flag key value)
     (let ((props (kuro--attrs-to-face-props :default :default ,flag nil)))
       (should (equal (plist-get props ,key) ,value)))))

(ert-deftest kuro-faces-attrs--attrs-to-face-props-empty-returns-no-weight ()
  "Default attrs (flags=0) → no :weight in the face props (inherit from default)."
  (let ((props (kuro--attrs-to-face-props :default :default 0 nil)))
    (should-not (plist-get props :weight))))

(kuro-faces-attrs-test--def-face-prop kuro-faces-attrs--attrs-to-face-props-bold         1     :weight      'bold)
(kuro-faces-attrs-test--def-face-prop kuro-faces-attrs--attrs-to-face-props-dim          2     :weight      'light)
(kuro-faces-attrs-test--def-face-prop kuro-faces-attrs--attrs-to-face-props-italic       4     :slant       'italic)
(kuro-faces-attrs-test--def-face-prop kuro-faces-attrs--attrs-to-face-props-strikethrough #x100 :strike-through t)
(kuro-faces-attrs-test--def-face-prop kuro-faces-attrs--attrs-to-face-props-inverse      #x40  :inverse-video  t)

(ert-deftest kuro-faces-attrs--attrs-to-face-props-no-italic-omits-slant ()
  "No italic → :slant absent (nil), to inherit from default face."
  (let ((props (kuro--attrs-to-face-props :default :default 0 nil)))
    (should-not (plist-get props :slant))))

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

(defconst kuro-faces-attrs-test--sgr-flag-set-p-table
  '((kuro-faces-attrs--sgr-flag-set-p-ff-bold           #xFF  kuro--sgr-flag-bold       t)
    (kuro-faces-attrs--sgr-flag-set-p-01-bold            #x01 kuro--sgr-flag-bold       t)
    (kuro-faces-attrs--sgr-flag-set-p-10-blink-slow      #x10 kuro--sgr-flag-blink-slow t)
    (kuro-faces-attrs--sgr-flag-set-p-00-bold-absent     0    kuro--sgr-flag-bold       nil)
    (kuro-faces-attrs--sgr-flag-set-p-02-bold-absent     #x02 kuro--sgr-flag-bold       nil)
    (kuro-faces-attrs--sgr-flag-set-p-01-slow-absent     #x01 kuro--sgr-flag-blink-slow nil))
  "Table of (test-name mask flag expectedp) for `kuro--sgr-flag-set-p'.")

(defmacro kuro-faces-attrs-test--def-sgr-flag-set-p (test-name mask flag expectedp)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--sgr-flag-set-p' mask=%s flag=%s => %s." mask flag expectedp)
     ,(if expectedp
          `(should (kuro--sgr-flag-set-p ,mask ,flag))
        `(should-not (kuro--sgr-flag-set-p ,mask ,flag)))))

(kuro-faces-attrs-test--def-sgr-flag-set-p kuro-faces-attrs--sgr-flag-set-p-ff-bold           #xFF  kuro--sgr-flag-bold       t)
(kuro-faces-attrs-test--def-sgr-flag-set-p kuro-faces-attrs--sgr-flag-set-p-01-bold            #x01 kuro--sgr-flag-bold       t)
(kuro-faces-attrs-test--def-sgr-flag-set-p kuro-faces-attrs--sgr-flag-set-p-10-blink-slow      #x10 kuro--sgr-flag-blink-slow t)
(kuro-faces-attrs-test--def-sgr-flag-set-p kuro-faces-attrs--sgr-flag-set-p-00-bold-absent     0    kuro--sgr-flag-bold       nil)
(kuro-faces-attrs-test--def-sgr-flag-set-p kuro-faces-attrs--sgr-flag-set-p-02-bold-absent     #x02 kuro--sgr-flag-bold       nil)
(kuro-faces-attrs-test--def-sgr-flag-set-p kuro-faces-attrs--sgr-flag-set-p-01-slow-absent     #x01 kuro--sgr-flag-blink-slow nil)

(ert-deftest kuro-faces-attrs--sgr-flag-set-p-all-table-entries-correct ()
  "All entries in `kuro-faces-attrs-test--sgr-flag-set-p-table' match actual behavior."
  (dolist (entry kuro-faces-attrs-test--sgr-flag-set-p-table)
    (pcase-let ((`(,_name ,mask ,flag ,expectedp) entry))
      (if expectedp
          (should (kuro--sgr-flag-set-p mask (symbol-value flag)))
        (should-not (kuro--sgr-flag-set-p mask (symbol-value flag)))))))

(ert-deftest kuro-faces-attrs--sgr-flag-set-p-returns-t-not-integer ()
  "Returns a boolean t/nil, not a raw integer (important: 0 is truthy in Elisp)."
  (should (eq t (kuro--sgr-flag-set-p #x01 kuro--sgr-flag-bold)))
  (should (eq nil (kuro--sgr-flag-set-p 0 kuro--sgr-flag-bold))))


;;; Group 8: kuro--underline-style-to-face-prop — remaining styles

(defmacro kuro-faces-attrs-test--ul-no-color (test-name style style-sym desc)
  "Define a no-color ert-deftest for kuro--underline-style-to-face-prop.
TEST-NAME is the ert-deftest symbol, STYLE is the integer style index,
STYLE-SYM is the expected :style symbol, DESC is the docstring."
  `(ert-deftest ,test-name ()
     ,desc
     (let ((result (kuro--underline-style-to-face-prop ,style nil)))
       (should (eq (plist-get result :style) ',style-sym))
       (should-not (plist-get result :color)))))

(defmacro kuro-faces-attrs-test--ul-with-color (test-name style color style-sym desc)
  "Define a with-color ert-deftest for kuro--underline-style-to-face-prop.
TEST-NAME is the ert-deftest symbol, STYLE is the integer style index,
COLOR is the hex color string, STYLE-SYM is the expected :style symbol,
DESC is the docstring."
  `(ert-deftest ,test-name ()
     ,desc
     (let ((result (kuro--underline-style-to-face-prop ,style ,color)))
       (should (equal (plist-get result :color) ,color))
       (should (eq (plist-get result :style) ',style-sym)))))

(kuro-faces-attrs-test--ul-no-color   kuro-faces-attrs--underline-style-double-no-color   2 double-line "Style 2 (double-line) without color → (:style double-line).")
(kuro-faces-attrs-test--ul-with-color kuro-faces-attrs--underline-style-double-with-color 2 "#0000ff" line   "Style 2 with color → (:color ... :style line) — same as straight with color.")
(kuro-faces-attrs-test--ul-no-color   kuro-faces-attrs--underline-style-dotted-no-color   4 dots      "Style 4 (dotted) without color → (:style dots).")
(kuro-faces-attrs-test--ul-with-color kuro-faces-attrs--underline-style-dotted-with-color 4 "#aabbcc" dots   "Style 4 (dotted) with color → (:color ... :style dots).")
(kuro-faces-attrs-test--ul-no-color   kuro-faces-attrs--underline-style-dashed-no-color   5 dashes    "Style 5 (dashed) without color → (:style dashes).")
(kuro-faces-attrs-test--ul-with-color kuro-faces-attrs--underline-style-dashed-with-color 5 "#112233" dashes "Style 5 (dashed) with color → (:color ... :style dashes).")

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


(provide 'kuro-faces-attrs-test)
;;; kuro-faces-attrs-test.el ends here
