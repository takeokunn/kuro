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
  (dolist (name '("black" "red" "green" "yellow"
                  "blue" "magenta" "cyan" "white"
                  "bright-black" "bright-red" "bright-green" "bright-yellow"
                  "bright-blue" "bright-magenta" "bright-cyan" "bright-white"))
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

(ert-deftest kuro-faces-rgb-to-emacs-red ()
  "0xFF0000 → #ff0000."
  (should (equal (kuro--rgb-to-emacs #xFF0000) "#ff0000")))

(ert-deftest kuro-faces-rgb-to-emacs-green ()
  "0x00FF00 → #00ff00."
  (should (equal (kuro--rgb-to-emacs #x00FF00) "#00ff00")))

(ert-deftest kuro-faces-rgb-to-emacs-blue ()
  "0x0000FF → #0000ff."
  (should (equal (kuro--rgb-to-emacs #x0000FF) "#0000ff")))

(ert-deftest kuro-faces-rgb-to-emacs-white ()
  "0xFFFFFF → #ffffff."
  (should (equal (kuro--rgb-to-emacs #xFFFFFF) "#ffffff")))

(ert-deftest kuro-faces-rgb-to-emacs-black ()
  "0x000000 → #000000."
  (should (equal (kuro--rgb-to-emacs 0) "#000000")))

;;; Group 4: kuro--decode-ffi-color

(ert-deftest kuro-faces-decode-ffi-color-default-sentinel ()
  "#xFF000000 (sentinel) → :default."
  (should (eq (kuro--decode-ffi-color #xFF000000) :default)))

(ert-deftest kuro-faces-decode-ffi-color-named-black ()
  "Bit 31 set + index 0 → (named . \"black\")."
  (let ((result (kuro--decode-ffi-color #x80000000)))
    (should (consp result))
    (should (eq (car result) 'named))
    (should (equal (cdr result) "black"))))

(ert-deftest kuro-faces-decode-ffi-color-named-all-16 ()
  "Named color encoding for all 16 base colors (bit 31 + low byte)."
  (let ((names ["black" "red" "green" "yellow"
                "blue" "magenta" "cyan" "white"
                "bright-black" "bright-red" "bright-green" "bright-yellow"
                "bright-blue" "bright-magenta" "bright-cyan" "bright-white"]))
    (dotimes (i 16)
      (let* ((enc (logior #x80000000 i))
             (result (kuro--decode-ffi-color enc)))
        (should (consp result))
        (should (eq (car result) 'named))
        (should (equal (cdr result) (aref names i)))))))

(ert-deftest kuro-faces-decode-ffi-color-indexed ()
  "Bit 30 set + low byte → (indexed . N)."
  (let ((result (kuro--decode-ffi-color #x40000042)))
    (should (consp result))
    (should (eq (car result) 'indexed))
    (should (= (cdr result) #x42))))

(ert-deftest kuro-faces-decode-ffi-color-rgb-true-black ()
  "0x00000000 (true black) → (rgb . 0)."
  (let ((result (kuro--decode-ffi-color 0)))
    (should (consp result))
    (should (eq (car result) 'rgb))
    (should (= (cdr result) 0))))

(ert-deftest kuro-faces-decode-ffi-color-rgb-red ()
  "0x00FF0000 → (rgb . #xFF0000)."
  (let ((result (kuro--decode-ffi-color #x00FF0000)))
    (should (consp result))
    (should (eq (car result) 'rgb))
    (should (= (cdr result) #xFF0000))))

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

(ert-deftest kuro-faces-decode-attrs-bold ()
  "Bit 0 (0x01) → :bold t."
  (let ((decoded (kuro--decode-attrs #x01)))
    (should (plist-get decoded :bold))
    (should-not (plist-get decoded :italic))))

(ert-deftest kuro-faces-decode-attrs-dim ()
  "Bit 1 (0x02) → :dim t."
  (let ((decoded (kuro--decode-attrs #x02)))
    (should (plist-get decoded :dim))
    (should-not (plist-get decoded :bold))))

(ert-deftest kuro-faces-decode-attrs-italic ()
  "Bit 2 (0x04) → :italic t."
  (let ((decoded (kuro--decode-attrs #x04)))
    (should (plist-get decoded :italic))))

(ert-deftest kuro-faces-decode-attrs-underline ()
  "Bit 3 (0x08) → :underline t."
  (let ((decoded (kuro--decode-attrs #x08)))
    (should (plist-get decoded :underline))))

(ert-deftest kuro-faces-decode-attrs-blink-slow ()
  "Bit 4 (0x10) → :blink-slow t."
  (let ((decoded (kuro--decode-attrs #x10)))
    (should (plist-get decoded :blink-slow))
    (should-not (plist-get decoded :blink-fast))))

(ert-deftest kuro-faces-decode-attrs-blink-fast ()
  "Bit 5 (0x20) → :blink-fast t."
  (let ((decoded (kuro--decode-attrs #x20)))
    (should (plist-get decoded :blink-fast))
    (should-not (plist-get decoded :blink-slow))))

(ert-deftest kuro-faces-decode-attrs-inverse ()
  "Bit 6 (0x40) → :inverse t."
  (let ((decoded (kuro--decode-attrs #x40)))
    (should (plist-get decoded :inverse))))

(ert-deftest kuro-faces-decode-attrs-hidden ()
  "Bit 7 (0x80) → :hidden t."
  (let ((decoded (kuro--decode-attrs #x80)))
    (should (plist-get decoded :hidden))))

(ert-deftest kuro-faces-decode-attrs-strikethrough ()
  "Bit 8 (0x100) → :strike-through t."
  (let ((decoded (kuro--decode-attrs #x100)))
    (should (plist-get decoded :strike-through))))

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
      (kuro--apply-ffi-face-at 1 6 0 0 0)
      (let ((prop (get-text-property 1 'face)))
        (should prop)))))

;;; Group 10: Character width table and font detection

(ert-deftest kuro-test-char-width-table-emoji ()
  "After setup, fire emoji (U+1F525) has char-width 2."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= (char-width ?\U0001F525) 2))))

(ert-deftest kuro-test-char-width-table-cjk ()
  "After setup, CJK ideograph U+65E5 has char-width 2."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= (char-width ?\u65E5) 2))))

(ert-deftest kuro-test-char-width-table-pua ()
  "After setup, PUA codepoint U+E0B0 (Nerd Font) has char-width 1."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= (char-width ?\xE0B0) 1))))

(ert-deftest kuro-test-detect-nerd-font-nil ()
  "kuro--detect-nerd-font returns nil or a string without error."
  (let ((result (kuro--detect-nerd-font)))
    (should (or (null result) (stringp result)))))

;;; Group 11: kuro--apply-palette-updates

(ert-deftest kuro-test-apply-palette-updates-updates-named-color ()
  "kuro--apply-palette-updates replaces the named color for the given index."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro--get-palette-updates)
               (lambda () '((1 255 0 0)))))  ; index 1 = red, RGB=(255,0,0)
      (kuro--rebuild-named-colors)
      (kuro--apply-palette-updates)
      (should (equal (gethash "red" kuro--named-colors) "#ff0000")))))

(ert-deftest kuro-test-apply-palette-updates-clears-face-cache ()
  "kuro--apply-palette-updates clears the face cache when a color changes."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro--get-palette-updates)
               (lambda () '((0 0 0 0)))))
      (kuro--get-cached-face-raw 0 0 0 0)  ; populate cache
      (kuro--apply-palette-updates)
      (should (= (hash-table-count kuro--face-cache) 0)))))

(ert-deftest kuro-test-apply-palette-updates-ignores-index-gte-16 ()
  "kuro--apply-palette-updates ignores entries with index >= 16."
  (let ((kuro--initialized t))
    (cl-letf (((symbol-function 'kuro--get-palette-updates)
               (lambda () '((16 255 0 0)))))
      (kuro--rebuild-named-colors)
      (let ((red-before (gethash "red" kuro--named-colors)))
        (kuro--apply-palette-updates)
        (should (equal (gethash "red" kuro--named-colors) red-before))))))

(ert-deftest kuro-test-apply-palette-updates-noop-when-uninitialized ()
  "kuro--apply-palette-updates is a no-op when kuro--initialized is nil."
  (let ((kuro--initialized nil)
        (called nil))
    (cl-letf (((symbol-function 'kuro--get-palette-updates)
               (lambda () (setq called t) '())))
      (kuro--apply-palette-updates)
      (should-not called))))

(ert-deftest kuro-test-apply-palette-updates-clears-face-cache-exactly-once ()
  "kuro--clear-face-cache is called exactly once regardless of entry count.
With three palette entries the cache must be flushed once, not three times."
  (let ((kuro--initialized t)
        (flush-count 0))
    (cl-letf (((symbol-function 'kuro--get-palette-updates)
               (lambda () '((0 10 20 30) (1 40 50 60) (2 70 80 90))))
              ((symbol-function 'kuro--clear-face-cache)
               (lambda () (cl-incf flush-count))))
      (kuro--apply-palette-updates)
      (should (= flush-count 1)))))

(ert-deftest kuro-test-apply-palette-updates-noop-when-no-updates ()
  "kuro--apply-palette-updates does not flush the cache when the update list is empty.
`when-let' guards the body, so an empty list must not trigger a flush."
  (let ((kuro--initialized t)
        (flush-count 0))
    (cl-letf (((symbol-function 'kuro--get-palette-updates)
               (lambda () nil))
              ((symbol-function 'kuro--clear-face-cache)
               (lambda () (cl-incf flush-count))))
      (kuro--apply-palette-updates)
      (should (= flush-count 0)))))

;;; Group 12: kuro--merge-palette-entry

(ert-deftest kuro-test-merge-palette-entry-valid-index ()
  "kuro--merge-palette-entry writes the correct hex color for a valid index."
  (kuro--rebuild-named-colors)
  ;; Index 4 = \"blue\" in kuro--ansi-color-names
  (kuro--merge-palette-entry '(4 0 0 255))
  (should (equal (gethash "blue" kuro--named-colors) "#0000ff")))

(ert-deftest kuro-test-merge-palette-entry-index-15 ()
  "kuro--merge-palette-entry handles the last valid index (15 = bright-white)."
  (kuro--rebuild-named-colors)
  (kuro--merge-palette-entry '(15 200 210 220))
  (should (equal (gethash "bright-white" kuro--named-colors) "#c8d2dc")))

(ert-deftest kuro-test-merge-palette-entry-index-16-ignored ()
  "kuro--merge-palette-entry silently ignores index 16 (out of ANSI range)."
  (kuro--rebuild-named-colors)
  (let ((before (gethash "black" kuro--named-colors)))
    (kuro--merge-palette-entry '(16 1 2 3))
    ;; The named-colors table should be unchanged for all 16 ANSI names.
    (should (equal (gethash "black" kuro--named-colors) before))))

(ert-deftest kuro-test-merge-palette-entry-no-face-cache-side-effect ()
  "kuro--merge-palette-entry never touches the face cache."
  (kuro--clear-face-cache)
  (kuro--get-cached-face-raw 0 0 0 0)  ; seed one entry
  (let ((count-before (hash-table-count kuro--face-cache)))
    (kuro--merge-palette-entry '(0 255 0 0))
    (should (= (hash-table-count kuro--face-cache) count-before))))

;;; Group 13: kuro--make-face

(ert-deftest kuro-faces-make-face-returns-list ()
  "kuro--make-face returns a plist (list) for default color args."
  (let ((result (kuro--make-face :default :default 0 nil)))
    (should (listp result))))

(ert-deftest kuro-faces-make-face-bold-weight ()
  "kuro--make-face with bold flag produces :weight bold."
  (let ((result (kuro--make-face :default :default 1 nil)))
    (should (eq (plist-get result :weight) 'bold))))

(ert-deftest kuro-faces-make-face-italic-slant ()
  "kuro--make-face with italic flag produces :slant italic."
  (let ((result (kuro--make-face :default :default 4 nil)))
    (should (eq (plist-get result :slant) 'italic))))

(ert-deftest kuro-faces-make-face-rgb-fg-and-bg ()
  "kuro--make-face with RGB fg and bg produces :foreground and :background."
  (let ((result (kuro--make-face '(rgb . #xFF0000) '(rgb . #x0000FF) 0 nil)))
    (should (equal (plist-get result :foreground) "#ff0000"))
    (should (equal (plist-get result :background) "#0000ff"))))

(ert-deftest kuro-faces-make-face-underline-color-passed-through ()
  "kuro--make-face passes underline-color to :underline prop."
  (let ((result (kuro--make-face :default :default #x08 "#aabbcc")))
    (let ((ul (plist-get result :underline)))
      (should ul)
      (should (equal (plist-get ul :color) "#aabbcc")))))

;;; Group 14: kuro--get-cached-face-raw — ul-enc normalization edge cases

(ert-deftest kuro-faces-cached-face-raw-sentinel-ul-same-as-zero ()
  "ul-enc=#xFF000000 (sentinel) and ul-enc=0 map to the same cache key."
  (kuro--clear-face-cache)
  (let ((face-zero     (kuro--get-cached-face-raw 0 0 0 0))
        (face-sentinel (kuro--get-cached-face-raw 0 0 0 #xFF000000)))
    (should (eq face-zero face-sentinel))))

(ert-deftest kuro-faces-cached-face-raw-nil-ul-same-as-zero ()
  "ul-enc=nil is normalized to 0 and hits the same cache entry as ul-enc=0."
  (kuro--clear-face-cache)
  (let ((face-zero (kuro--get-cached-face-raw 0 0 0 0))
        (face-nil  (kuro--get-cached-face-raw 0 0 0 nil)))
    (should (eq face-zero face-nil))))

(ert-deftest kuro-faces-cached-face-raw-nonzero-ul-distinct ()
  "A non-zero, non-sentinel ul-enc stays distinct from the ul=0 cache slot."
  (kuro--clear-face-cache)
  (let ((face-no-ul   (kuro--get-cached-face-raw 0 0 0 0))
        (face-with-ul (kuro--get-cached-face-raw 0 0 0 #x0000FF)))
    (should-not (eq face-no-ul face-with-ul))))

(ert-deftest kuro-faces-cached-face-raw-evicts-when-over-max ()
  "Cache is cleared when entry count exceeds kuro--face-cache-max-size."
  (kuro--clear-face-cache)
  ;; Insert max-size+2 distinct fg values to cross the eviction threshold.
  (dotimes (i (+ kuro--face-cache-max-size 2))
    (kuro--get-cached-face-raw i 0 0 0))
  (should (< (hash-table-count kuro--face-cache) kuro--face-cache-max-size)))

(ert-deftest kuro-faces-cached-face-raw-lookup-vector-length-4 ()
  "kuro--face-cache-lookup-key is a 4-element pre-allocated vector."
  (kuro--clear-face-cache)
  (kuro--get-cached-face-raw 0 0 0 0)
  (should (vectorp kuro--face-cache-lookup-key))
  (should (= (length kuro--face-cache-lookup-key) 4)))

(ert-deftest kuro-faces-cached-face-raw-flags-distinguish-keys ()
  "Different flags values produce different cache entries."
  (kuro--clear-face-cache)
  (let ((face-no-bold   (kuro--get-cached-face-raw 0 0 0 0))
        (face-with-bold (kuro--get-cached-face-raw 0 0 1 0)))
    (should-not (eq face-no-bold face-with-bold))))

(provide 'kuro-faces-test)

;;; kuro-faces-test.el ends here
