;;; kuro-faces-color-test.el --- Unit tests for kuro-faces-color.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-faces-color.el (FFI color sentinel, ANSI color name
;; vector, and color conversion helpers).
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.

;;; Code:

(require 'kuro-faces-color-test-support)

;;; Group 1: kuro--ffi-color-default sentinel

(ert-deftest kuro-faces-color--default-sentinel-value ()
  "kuro--ffi-color-default must equal #xFF000000."
  (should (= kuro--ffi-color-default #xFF000000)))

(ert-deftest kuro-faces-color--default-sentinel-is-integer ()
  "kuro--ffi-color-default must be an integer (not a symbol or string)."
  (should (integerp kuro--ffi-color-default)))

(ert-deftest kuro-faces-color--default-sentinel-distinct-from-true-black ()
  "kuro--ffi-color-default must differ from true black (0x000000)."
  (should-not (= kuro--ffi-color-default 0)))

;;; Group 2: kuro--ansi-color-names vector

(ert-deftest kuro-faces-color--ansi-color-names-is-vector ()
  "kuro--ansi-color-names must be a vector."
  (should (vectorp kuro--ansi-color-names)))

(ert-deftest kuro-faces-color--ansi-color-names-length ()
  "kuro--ansi-color-names must have exactly 16 entries."
  (should (= (length kuro--ansi-color-names) 16)))

(ert-deftest kuro-faces-color--ansi-color-names-all-strings ()
  "Every element of kuro--ansi-color-names must be a non-empty string."
  (dotimes (i 16)
    (let ((name (aref kuro--ansi-color-names i)))
      (should (stringp name))
      (should (> (length name) 0)))))

(ert-deftest kuro-faces-color--ansi-color-names-normal-colors ()
  "Indices 0-7 must be the standard ANSI names (no 'bright-' prefix)."
  (let ((expected ["black" "red" "green" "yellow"
                   "blue" "magenta" "cyan" "white"]))
    (dotimes (i 8)
      (should (string= (aref kuro--ansi-color-names i)
                       (aref expected i))))))

(ert-deftest kuro-faces-color--ansi-color-names-bright-black-hyphenated ()
  "Index 8 must be \"bright-black\" (hyphenated, not \"brightblack\" or \"dark-gray\")."
  (should (string= (aref kuro--ansi-color-names 8) "bright-black")))

(ert-deftest kuro-faces-color--ansi-color-names-bright-colors ()
  "Indices 8-15 must be the bright ANSI names with 'bright-' prefix."
  (let ((expected ["bright-black" "bright-red" "bright-green" "bright-yellow"
                   "bright-blue" "bright-magenta" "bright-cyan" "bright-white"]))
    (dotimes (i 8)
      (should (string= (aref kuro--ansi-color-names (+ 8 i))
                       (aref expected i))))))

;;; Group 3: kuro--decode-ffi-color — focused on sentinel and boundary cases
;;; (Broad coverage is already in kuro-faces-test.el; these tests add gaps.)

(kuro-faces-color-test--should-decode
 kuro-faces-color--decode-ffi-color-sentinel-returns-default
 kuro--ffi-color-default
 :default)

(ert-deftest kuro-faces-color--decode-ffi-color-named-index-15 ()
  "Named color at index 15 (bit 31 + 0x0F) decodes to (named . \"bright-white\")."
  (let ((result (kuro--decode-ffi-color (logior #x80000000 15))))
    (should (consp result))
    (should (eq (car result) 'named))
    (should (string= (cdr result) "bright-white"))))

(ert-deftest kuro-faces-color--decode-ffi-color-named-out-of-range-index ()
  "Named color with index >= 16 (bit 31 + 0x10) returns nil (no valid name)."
  ;; Index 16 is beyond the 16-entry kuro--ansi-color-names vector.
  (let ((result (kuro--decode-ffi-color (logior #x80000000 16))))
    (should (null result))))

(kuro-faces-color-test--should-decode
 kuro-faces-color--decode-ffi-color-indexed-boundary-zero
 #x40000000
 '(indexed . 0))

(kuro-faces-color-test--should-decode
 kuro-faces-color--decode-ffi-color-indexed-boundary-255
 (logior #x40000000 255)
 '(indexed . 255))

(kuro-faces-color-test--should-decode
 kuro-faces-color--decode-ffi-color-rgb-white
 #x00FFFFFF
 '(rgb . 16777215))

;;; Group 4: kuro--rgb-to-emacs — boundary values

(ert-deftest kuro-faces-color--rgb-to-emacs-black ()
  "0x000000 (true black) encodes to #000000."
  (should (equal (kuro--rgb-to-emacs #x000000) "#000000")))

(ert-deftest kuro-faces-color--rgb-to-emacs-white ()
  "0xFFFFFF (white) encodes to #ffffff."
  (should (equal (kuro--rgb-to-emacs #xFFFFFF) "#ffffff")))

(ert-deftest kuro-faces-color--rgb-to-emacs-midtone ()
  "0x7F7F7F encodes to #7f7f7f."
  (should (equal (kuro--rgb-to-emacs #x7F7F7F) "#7f7f7f")))

(ert-deftest kuro-faces-color--rgb-to-emacs-channel-isolation ()
  "Each color channel is masked independently."
  ;; Only blue channel: 0x0000FF → #0000ff
  (should (equal (kuro--rgb-to-emacs #x0000FF) "#0000ff"))
  ;; Only green channel: 0x00FF00 → #00ff00
  (should (equal (kuro--rgb-to-emacs #x00FF00) "#00ff00"))
  ;; Only red channel: 0xFF0000 → #ff0000
  (should (equal (kuro--rgb-to-emacs #xFF0000) "#ff0000")))

;;; Group 5: kuro--indexed-to-emacs — boundary values not in kuro-faces-test.el

(kuro-faces-color-test--should-indexed-color
 kuro-faces-color--indexed-to-emacs-index-16-is-black
 16
 "#000000")

(kuro-faces-color-test--should-indexed-color
 kuro-faces-color--indexed-to-emacs-index-231-is-white
 231
 "#ffffff")

(kuro-faces-color-test--should-indexed-color
 kuro-faces-color--indexed-to-emacs-index-232-grayscale-start
 232
 "#080808")

(kuro-faces-color-test--should-indexed-color
 kuro-faces-color--indexed-to-emacs-index-255-grayscale-end
 255
 "#eeeeee")

(ert-deftest kuro-faces-color--indexed-to-emacs-out-of-range-returns-nil ()
  "Index 256 (out of range) must return nil."
  (should (null (kuro--indexed-to-emacs 256))))

;;; Group 6: kuro--decode-ffi-color — true black and RGB boundary

(kuro-faces-color-test--should-decode
 kuro-faces-color--decode-ffi-color-true-black
 #x00000000
 '(rgb . 0))

(ert-deftest kuro-faces-color--decode-ffi-color-rgb-black ()
  "True black RGB (rgb . 0) converts to #000000 via kuro--color-to-emacs."
  (let* ((decoded (kuro--decode-ffi-color #x00000000))
         (result (kuro--rgb-to-emacs (cdr decoded))))
    (should (equal result "#000000"))))

(kuro-faces-color-test--should-decode
 kuro-faces-color--decode-ffi-color-named-index-0
 #x80000000
 '(named . "black"))

;;; Group 7: kuro--color-to-emacs dispatch

;; kuro--color-to-emacs looks up kuro--named-colors (defined in kuro-colors.el).
;; We bind a minimal stub hash-table so the tests stay self-contained.

(defmacro kuro-faces-color-test--with-named-colors (alist &rest body)
  "Execute BODY with `kuro--named-colors' bound to a fresh hash-table from ALIST.
ALIST is a list of (name . hex-string) pairs."
  (declare (indent 1))
  `(let ((kuro--named-colors (make-hash-table :test #'equal)))
     (dolist (pair ,alist)
       (puthash (car pair) (cdr pair) kuro--named-colors))
     ,@body))

(ert-deftest kuro-faces-color--color-to-emacs-default-returns-nil ()
  "kuro--color-to-emacs with :default keyword returns nil."
  (kuro-faces-color-test--with-named-colors '()
    (should (null (kuro--color-to-emacs :default)))))

(ert-deftest kuro-faces-color--color-to-emacs-unknown-returns-nil ()
  "kuro--color-to-emacs with non-cons non-:default input returns nil."
  (kuro-faces-color-test--with-named-colors '()
    (should (null (kuro--color-to-emacs 42)))
    (should (null (kuro--color-to-emacs nil)))
    (should (null (kuro--color-to-emacs "unknown")))))

(ert-deftest kuro-faces-color--color-to-emacs-named-known-key ()
  "kuro--color-to-emacs (named . \"red\") looks up kuro--named-colors."
  (kuro-faces-color-test--with-named-colors '(("red" . "#cc0000"))
    (should (equal (kuro--color-to-emacs '(named . "red")) "#cc0000"))))

(ert-deftest kuro-faces-color--color-to-emacs-named-fallback-to-cdr ()
  "kuro--color-to-emacs (named . name) returns name when not in hash-table."
  (kuro-faces-color-test--with-named-colors '()
    ;; gethash returns nil → (or nil cdr) → \"cyan\"
    (should (equal (kuro--color-to-emacs '(named . "cyan")) "cyan"))))

(ert-deftest kuro-faces-color--color-to-emacs-indexed-cube ()
  "kuro--color-to-emacs (indexed . 52) returns the cube entry for index 52."
  (kuro-faces-color-test--with-named-colors '()
    ;; Index 52 is in the cube range (16-231). Cube offset = 52-16 = 36.
    ;; r = (36/36)*51 = 51, g = ((36 mod 6)/6 * 6)*51... let kuro--indexed-to-emacs compute.
    (let ((result (kuro--color-to-emacs '(indexed . 52))))
      (should (stringp result))
      (should (string-prefix-p "#" result))
      (should (= (length result) 7)))))

(ert-deftest kuro-faces-color--color-to-emacs-indexed-named-range ()
  "kuro--color-to-emacs (indexed . 0) uses kuro--indexed-to-emacs → named-colors lookup."
  (kuro-faces-color-test--with-named-colors '(("black" . "#000000"))
    (should (equal (kuro--color-to-emacs '(indexed . 0)) "#000000"))))

(ert-deftest kuro-faces-color--color-to-emacs-indexed-grayscale ()
  "kuro--color-to-emacs (indexed . 240) returns grayscale entry for index 240."
  (kuro-faces-color-test--with-named-colors '()
    ;; Index 240 is in the grayscale range (232-255): offset = 240-232 = 8.
    ;; val = 8*10+8 = 88 = 0x58 → #585858
    (should (equal (kuro--color-to-emacs '(indexed . 240)) "#585858"))))

(ert-deftest kuro-faces-color--color-to-emacs-rgb-value ()
  "kuro--color-to-emacs (rgb . #x1A2B3C) converts to hex color string."
  (kuro-faces-color-test--with-named-colors '()
    (should (equal (kuro--color-to-emacs '(rgb . #x1A2B3C)) "#1a2b3c"))))

(ert-deftest kuro-faces-color--color-to-emacs-rgb-zero ()
  "kuro--color-to-emacs (rgb . 0) returns #000000 (true black)."
  (kuro-faces-color-test--with-named-colors '()
    (should (equal (kuro--color-to-emacs '(rgb . 0)) "#000000"))))

(ert-deftest kuro-faces-color--color-to-emacs-rgb-max ()
  "kuro--color-to-emacs (rgb . #xFFFFFF) returns #ffffff."
  (kuro-faces-color-test--with-named-colors '()
    (should (equal (kuro--color-to-emacs '(rgb . #xFFFFFF)) "#ffffff"))))

;;; ── Color constant structural invariants ─────────────────────────────────────

(ert-deftest kuro-faces-color-cube-range-is-consistent ()
  "`kuro--color-cube-start' + 6^3 - 1 = `kuro--color-cube-end' (216 indexed colors)."
  (should (= kuro--color-cube-end
             (+ kuro--color-cube-start
                (* kuro--color-cube-size kuro--color-cube-size kuro--color-cube-size)
                -1))))

(ert-deftest kuro-faces-color-gray-start-follows-cube-end ()
  "`kuro--color-gray-start' is one past `kuro--color-cube-end' (no gap in 256-palette)."
  (should (= kuro--color-gray-start (1+ kuro--color-cube-end))))

(ert-deftest kuro-faces-color-rgb-mask-is-24-bits ()
  "`kuro--color-rgb-mask' is exactly 24 bits wide (#xFFFFFF)."
  (should (= kuro--color-rgb-mask #xFFFFFF)))

(ert-deftest kuro-faces-color-tag-bits-dont-overlap-rgb ()
  "`kuro--color-tag-indexed' has no overlap with `kuro--color-rgb-mask'."
  (should (= 0 (logand kuro--color-tag-indexed kuro--color-rgb-mask))))

(ert-deftest kuro-faces-color-named-color-conses-has-16-entries ()
  "`kuro--named-color-conses' has exactly 16 entries (ANSI colors 0–15)."
  (should (= 16 (length kuro--named-color-conses))))

(ert-deftest kuro-faces-color-indexed-color-conses-has-256-entries ()
  "`kuro--indexed-color-conses' has exactly 256 entries (full 8-bit palette)."
  (should (= 256 (length kuro--indexed-color-conses))))

(ert-deftest kuro-faces-color-rgb-string-cache-is-hash-table ()
  "`kuro--rgb-string-cache' is an `eql'-keyed hash table for memoizing RGB strings."
  (should (hash-table-p kuro--rgb-string-cache)))

(provide 'kuro-faces-color-test)
;;; kuro-faces-color-test.el ends here
