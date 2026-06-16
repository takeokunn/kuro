;;; kuro-faces-test.el --- Unit tests for kuro-faces.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-faces.el (color conversion, attribute decoding, face caching).
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-faces)
(require 'kuro-char-width)
(require 'kuro-overlays)
(require 'kuro-colors-test-support)

;;; Group 1: kuro--color-to-emacs

(ert-deftest kuro-faces-color-to-emacs-default ()
  ":default color returns nil."
  (should-not (kuro--color-to-emacs :default)))

(ert-deftest kuro-faces-color-to-emacs-named-red ()
  "Named 'red' maps to kuro-color-red hex string."
  (let ((result (kuro--color-to-emacs '(named . "red"))))
    (should (stringp result))
    (should (string-match-p "^#[0-9a-fA-F]\\{6\\}$" result))))

(ert-deftest kuro-faces-color-to-emacs-named-all-16 ()
  "All 16 ANSI named colors resolve to hex strings."
  (dolist (name (kuro-colors-test--color-names))
    (let ((result (kuro--color-to-emacs (cons 'named name))))
      (should (stringp result))
      (should (string-match-p "^#[0-9a-fA-F]\\{6\\}$" result)))))

(ert-deftest kuro-faces-color-to-emacs-rgb ()
  "RGB cons cell produces #RRGGBB string."
  ;; 0xFF0000 = red
  (let ((result (kuro--color-to-emacs '(rgb . #xFF0000))))
    (should (equal result "#ff0000"))))

(ert-deftest kuro-faces-color-to-emacs-rgb-black ()
  "RGB value 0 (true black) produces #000000."
  (let ((result (kuro--color-to-emacs '(rgb . 0))))
    (should (equal result "#000000"))))

(ert-deftest kuro-faces-color-to-emacs-unknown-returns-nil ()
  "Unknown color type returns nil gracefully."
  (should-not (kuro--color-to-emacs 'bogus))
  (should-not (kuro--color-to-emacs 42)))

;;; Group 2: kuro--indexed-to-emacs

(ert-deftest kuro-faces-indexed-to-emacs-basic-16 ()
  "Indexed colors 0-15 map to ANSI named colors (non-nil strings)."
  (dotimes (i 16)
    (let ((result (kuro--indexed-to-emacs i)))
      (should (stringp result))
      (should (string-match-p "^#[0-9a-fA-F]\\{6\\}$" result)))))

(ert-deftest kuro-faces-indexed-to-emacs-256-color-range ()
  "Indexed colors 16-231 (6x6x6 cube) return hex strings."
  (let ((result (kuro--indexed-to-emacs 16)))
    (should (equal result "#000000")))
  (let ((result (kuro--indexed-to-emacs 231)))
    (should (equal result "#ffffff")))
  ;; Spot check middle of cube
  (let ((result (kuro--indexed-to-emacs 123)))
    (should (stringp result))
    (should (string-match-p "^#[0-9a-fA-F]\\{6\\}$" result))))

(ert-deftest kuro-faces-indexed-to-emacs-grayscale-range ()
  "Indexed colors 232-255 (grayscale ramp) return gray hex strings."
  (let ((result (kuro--indexed-to-emacs 232)))
    (should (equal result "#080808")))
  (let ((result (kuro--indexed-to-emacs 255)))
    (should (equal result "#eeeeee")))
  ;; All grayscale should have equal R=G=B components
  (dotimes (i 24)
    (let* ((idx (+ 232 i))
           (result (kuro--indexed-to-emacs idx)))
      (should (stringp result))
      (should (string-match "^#\\([0-9a-f][0-9a-f]\\)\\1\\1$" result)))))

(ert-deftest kuro-faces-indexed-to-emacs-out-of-range ()
  "Index > 255 returns nil without error."
  (should-not (kuro--indexed-to-emacs 256))
  (should-not (kuro--indexed-to-emacs 999)))

;;; Group 3: kuro--rgb-to-emacs

(defconst kuro-faces-test--rgb-to-emacs-table
  '((kuro-faces-rgb-to-emacs-red   #xFF0000 "#ff0000")
    (kuro-faces-rgb-to-emacs-green #x00FF00 "#00ff00")
    (kuro-faces-rgb-to-emacs-blue  #x0000FF "#0000ff")
    (kuro-faces-rgb-to-emacs-white #xFFFFFF "#ffffff")
    (kuro-faces-rgb-to-emacs-black 0        "#000000"))
  "Table of (test-name rgb-int expected-hex) for `kuro--rgb-to-emacs'.")

(defmacro kuro-faces-test--def-rgb-to-emacs (test-name input expected)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--rgb-to-emacs' #x%X → %S." input expected)
     (should (equal (kuro--rgb-to-emacs ,input) ,expected))))

(kuro-faces-test--def-rgb-to-emacs kuro-faces-rgb-to-emacs-red   #xFF0000 "#ff0000")
(kuro-faces-test--def-rgb-to-emacs kuro-faces-rgb-to-emacs-green #x00FF00 "#00ff00")
(kuro-faces-test--def-rgb-to-emacs kuro-faces-rgb-to-emacs-blue  #x0000FF "#0000ff")
(kuro-faces-test--def-rgb-to-emacs kuro-faces-rgb-to-emacs-white #xFFFFFF "#ffffff")
(kuro-faces-test--def-rgb-to-emacs kuro-faces-rgb-to-emacs-black 0        "#000000")

(ert-deftest kuro-faces-test--all-rgb-to-emacs-produce-hex ()
  "All kuro-faces-test--rgb-to-emacs-table entries produce the expected hex string."
  (dolist (entry kuro-faces-test--rgb-to-emacs-table)
    (pcase-let ((`(,_name ,input ,expected) entry))
      (should (equal (kuro--rgb-to-emacs input) expected)))))

;;; Group 4: kuro--decode-ffi-color

(ert-deftest kuro-faces-decode-ffi-color-default-sentinel ()
  "#xFF000000 (sentinel) → :default."
  (should (eq (kuro--decode-ffi-color #xFF000000) :default)))

(defconst kuro-faces-test--decode-ffi-color-cons-table
  '((kuro-faces-decode-ffi-color-named-black    #x80000000 named   "black")
    (kuro-faces-decode-ffi-color-indexed         #x40000042 indexed #x42)
    (kuro-faces-decode-ffi-color-rgb-true-black  0          rgb     0)
    (kuro-faces-decode-ffi-color-rgb-red         #x00FF0000 rgb     #xFF0000))
  "Table of (test-name enc type value) for `kuro--decode-ffi-color' cons results.")

(defmacro kuro-faces-test--def-decode-ffi-color-cons (test-name enc type value)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--decode-ffi-color' → (%s . %S)." type value)
     (let ((result (kuro--decode-ffi-color ,enc)))
       (should (consp result))
       (should (eq  (car result) ',type))
       (should (equal (cdr result) ,value)))))

(kuro-faces-test--def-decode-ffi-color-cons kuro-faces-decode-ffi-color-named-black    #x80000000 named   "black")
(kuro-faces-test--def-decode-ffi-color-cons kuro-faces-decode-ffi-color-indexed         #x40000042 indexed #x42)
(kuro-faces-test--def-decode-ffi-color-cons kuro-faces-decode-ffi-color-rgb-true-black  0          rgb     0)
(kuro-faces-test--def-decode-ffi-color-cons kuro-faces-decode-ffi-color-rgb-red         #x00FF0000 rgb     #xFF0000)

(ert-deftest kuro-faces-decode-ffi-color-named-all-16 ()
  "Named color encoding for all 16 base colors (bit 31 + low byte)."
  (let ((names (kuro-colors-test--color-name-vector)))
    (dotimes (i 16)
      (let* ((enc (logior #x80000000 i))
             (result (kuro--decode-ffi-color enc)))
        (should (consp result))
        (should (eq (car result) 'named))
        (should (equal (cdr result) (aref names i)))))))

(ert-deftest kuro-faces-decode-ffi-color-cons-table-all-correct ()
  "Every entry in `kuro-faces-test--decode-ffi-color-cons-table' returns the expected cons."
  (dolist (entry kuro-faces-test--decode-ffi-color-cons-table)
    (pcase-let ((`(,_name ,enc ,type ,value) entry))
      (let ((result (kuro--decode-ffi-color enc)))
        (should (consp result))
        (should (eq  (car result) type))
        (should (equal (cdr result) value))))))

;;; Group 5: kuro--decode-attrs

(ert-deftest kuro-faces-decode-attrs-zero-flags ()
  "Flags 0: all attributes are nil/false."
  (let ((decoded (kuro--decode-attrs 0)))
    (should-not (plist-get decoded :bold))
    (should-not (plist-get decoded :italic))
    (should-not (plist-get decoded :underline))
    (should-not (plist-get decoded :blink-slow))
    (should-not (plist-get decoded :blink-fast))
    (should-not (plist-get decoded :inverse))
    (should-not (plist-get decoded :dim))
    (should-not (plist-get decoded :hidden))
    (should-not (plist-get decoded :strike-through))
    (should (= (plist-get decoded :underline-style) 0))))

(defconst kuro-faces-test--decode-attrs-flag-table
  ;;  test-name                             flags  key             not-key
  '((kuro-faces-decode-attrs-bold           #x001  :bold           :italic)
    (kuro-faces-decode-attrs-dim            #x002  :dim            :bold)
    (kuro-faces-decode-attrs-italic         #x004  :italic         nil)
    (kuro-faces-decode-attrs-underline      #x008  :underline      nil)
    (kuro-faces-decode-attrs-blink-slow     #x010  :blink-slow     :blink-fast)
    (kuro-faces-decode-attrs-blink-fast     #x020  :blink-fast     :blink-slow)
    (kuro-faces-decode-attrs-inverse        #x040  :inverse        nil)
    (kuro-faces-decode-attrs-hidden         #x080  :hidden         nil)
    (kuro-faces-decode-attrs-strikethrough  #x100  :strike-through nil))
  "Table of (test-name flags key not-key) for single-bit `kuro--decode-attrs' checks.")

(defmacro kuro-faces-test--def-decode-attrs-flag (test-name flags key not-key)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--decode-attrs' #x%X → %s truthy%s."
              flags key (if not-key (format ", %s nil" not-key) ""))
     (let ((decoded (kuro--decode-attrs ,flags)))
       (should (plist-get decoded ,key))
       ,@(when not-key `((should-not (plist-get decoded ,not-key)))))))

(kuro-faces-test--def-decode-attrs-flag kuro-faces-decode-attrs-bold          #x001  :bold           :italic)
(kuro-faces-test--def-decode-attrs-flag kuro-faces-decode-attrs-dim           #x002  :dim            :bold)
(kuro-faces-test--def-decode-attrs-flag kuro-faces-decode-attrs-italic        #x004  :italic         nil)
(kuro-faces-test--def-decode-attrs-flag kuro-faces-decode-attrs-underline     #x008  :underline      nil)
(kuro-faces-test--def-decode-attrs-flag kuro-faces-decode-attrs-blink-slow    #x010  :blink-slow     :blink-fast)
(kuro-faces-test--def-decode-attrs-flag kuro-faces-decode-attrs-blink-fast    #x020  :blink-fast     :blink-slow)
(kuro-faces-test--def-decode-attrs-flag kuro-faces-decode-attrs-inverse       #x040  :inverse        nil)
(kuro-faces-test--def-decode-attrs-flag kuro-faces-decode-attrs-hidden        #x080  :hidden         nil)
(kuro-faces-test--def-decode-attrs-flag kuro-faces-decode-attrs-strikethrough #x100  :strike-through nil)

(ert-deftest kuro-faces-test--all-single-bit-attrs-set-key ()
  "Each single-bit flag in decode-attrs-flag-table sets its key and clears not-key."
  (dolist (entry kuro-faces-test--decode-attrs-flag-table)
    (pcase-let ((`(,_name ,flags ,key ,not-key) entry))
      (let ((decoded (kuro--decode-attrs flags)))
        (should (plist-get decoded key))
        (when not-key
          (should-not (plist-get decoded not-key)))))))

(ert-deftest kuro-faces-decode-attrs-underline-style-curly ()
  "Bits 9-11 encoding 3 → :underline-style 3 (curly/wave)."
  ;; style=3 → bits 9-11 = 011 → 3 << 9 = 0x600
  (let ((decoded (kuro--decode-attrs (logior #x08 #x600))))
    (should (plist-get decoded :underline))
    (should (= (plist-get decoded :underline-style) 3))))

(ert-deftest kuro-faces-decode-attrs-bold-italic-combined ()
  "0x05 → bold AND italic."
  (let ((decoded (kuro--decode-attrs #x05)))
    (should (plist-get decoded :bold))
    (should (plist-get decoded :italic))
    (should-not (plist-get decoded :underline))))

(ert-deftest kuro-faces-decode-attrs-all-flags ()
  "All low bits set → all base attributes true."
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

;;; Group 6: kuro--underline-style-to-face-prop

(ert-deftest kuro-faces-underline-style-none ()
  "Style 0 → nil (no underline)."
  (should-not (kuro--underline-style-to-face-prop 0 nil)))

(ert-deftest kuro-faces-underline-style-straight-no-color ()
  "Style 1 without color → t (plain underline)."
  (should (eq t (kuro--underline-style-to-face-prop 1 nil))))

(ert-deftest kuro-faces-underline-style-straight-with-color ()
  "Style 1 with color → plist with :style line."
  (let ((result (kuro--underline-style-to-face-prop 1 "#ff0000")))
    (should (plist-get result :color))
    (should (eq (plist-get result :style) 'line))))

(ert-deftest kuro-faces-underline-style-wave-no-color ()
  "Style 3 (curly/wave) without color → (:style wave)."
  (let ((result (kuro--underline-style-to-face-prop 3 nil)))
    (should (eq (plist-get result :style) 'wave))))

(ert-deftest kuro-faces-underline-style-wave-with-color ()
  "Style 3 with color → (:color ... :style wave)."
  (let ((result (kuro--underline-style-to-face-prop 3 "#00ff00")))
    (should (equal (plist-get result :color) "#00ff00"))
    (should (eq (plist-get result :style) 'wave))))

(ert-deftest kuro-faces-underline-style-unknown ()
  "Unknown style → t (plain underline fallback)."
  (should (eq t (kuro--underline-style-to-face-prop 99 nil))))

;;; Group 7: Face cache

(ert-deftest kuro-faces-get-cached-face-returns-cons ()
  "kuro--get-cached-face-raw returns a list for default (all-zero) args."
  (kuro--clear-face-cache)
  (let ((face (kuro--get-cached-face-raw 0 0 0 0)))
    (should (consp face))))

(ert-deftest kuro-faces-get-cached-face-same-key-returns-eq ()
  "Same integer key args return the identical (eq) cached object."
  (kuro--clear-face-cache)
  ;; named red = bit31 + index 1 = #x80000001
  (let ((face1 (kuro--get-cached-face-raw #x80000001 0 0 0))
        (face2 (kuro--get-cached-face-raw #x80000001 0 0 0)))
    (should (eq face1 face2))))

(ert-deftest kuro-faces-get-cached-face-different-fg-different-object ()
  "Different fg-enc values produce different cached faces."
  (kuro--clear-face-cache)
  ;; red (#x80000001) vs blue (#x80000004)
  (let ((face1 (kuro--get-cached-face-raw #x80000001 0 0 0))
        (face2 (kuro--get-cached-face-raw #x80000004 0 0 0)))
    (should-not (eq face1 face2))))

(ert-deftest kuro-faces-clear-face-cache ()
  "kuro--clear-face-cache empties the hash table so next call creates new object."
  (kuro--clear-face-cache)
  (let ((face1 (kuro--get-cached-face-raw 0 0 0 0)))
    (kuro--clear-face-cache)
    (let ((face2 (kuro--get-cached-face-raw 0 0 0 0)))
      (should-not (eq face1 face2)))))

;;; Group 8: kuro--attrs-to-face-props

(ert-deftest kuro-faces-attrs-to-face-props-default-colors ()
  ":default fg and bg → no :foreground/:background in face props."
  (let ((props (kuro--attrs-to-face-props :default :default 0 nil)))
    (should-not (plist-get props :foreground))
    (should-not (plist-get props :background))))

(ert-deftest kuro-faces-attrs-to-face-props-bold-weight ()
  "Bold flag → :weight bold."
  (let ((props (kuro--attrs-to-face-props :default :default 1 nil)))
    (should (eq (plist-get props :weight) 'bold))))

(ert-deftest kuro-faces-attrs-to-face-props-dim-weight ()
  "Dim flag → :weight light."
  (let ((props (kuro--attrs-to-face-props :default :default 2 nil)))
    (should (eq (plist-get props :weight) 'light))))

(ert-deftest kuro-faces-attrs-to-face-props-normal-weight ()
  "No bold/dim → :weight is omitted (nil) to inherit from default face.
This is intentional: omitting :weight 'normal is more efficient than
setting it explicitly, because Emacs inherits the default face weight
without an extra font-metric recomputation pass."
  (let ((props (kuro--attrs-to-face-props :default :default 0 nil)))
    ;; :weight should be absent (nil) — normal weight is inherited from default face
    (should-not (plist-get props :weight))))

(ert-deftest kuro-faces-attrs-to-face-props-italic ()
  "Italic flag → :slant italic."
  (let ((props (kuro--attrs-to-face-props :default :default 4 nil)))
    (should (eq (plist-get props :slant) 'italic))))

(ert-deftest kuro-faces-attrs-to-face-props-inverse ()
  "Inverse flag → :inverse-video t."
  (let ((props (kuro--attrs-to-face-props :default :default #x40 nil)))
    (should (plist-get props :inverse-video))))

(ert-deftest kuro-faces-attrs-to-face-props-strikethrough ()
  "Strikethrough flag → :strike-through t."
  (let ((props (kuro--attrs-to-face-props :default :default #x100 nil)))
    (should (plist-get props :strike-through))))

;;; Group 9: kuro--apply-ffi-face-at

(ert-deftest kuro-faces-apply-ffi-face-at-sets-text-property ()
  "kuro--apply-ffi-face-at sets the `face' text property on the specified range."
  (with-temp-buffer
    (let ((inhibit-read-only t))
      (insert "Hello World")
      (kuro--clear-face-cache)
      ;; all-zero args = default colors, no attributes
      (kuro--apply-ffi-face-at 1 6 0 0 0 0)
      (let ((prop (get-text-property 1 'face)))
        (should prop)))))

(provide 'kuro-faces-test)
;;; kuro-faces-test.el ends here
