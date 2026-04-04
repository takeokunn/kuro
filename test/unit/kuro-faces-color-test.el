;;; kuro-faces-color-test.el --- Unit tests for kuro-faces-color.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-faces-color.el (FFI color sentinel, ANSI color name
;; vector, and color conversion helpers).
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-faces-color)

(defmacro kuro-faces-color-test--should-decode (name encoded expected)
  "Define NAME as an ERT test asserting ENCODED decodes to EXPECTED."
  `(ert-deftest ,name ()
     (should (equal (kuro--decode-ffi-color ,encoded) ,expected))))

(defmacro kuro-faces-color-test--should-indexed-color (name index expected)
  "Define NAME as an ERT test asserting INDEX resolves to EXPECTED."
  `(ert-deftest ,name ()
     (should (equal (kuro--indexed-to-emacs ,index) ,expected))))

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

;;; Group 8: kuro--indexed-to-emacs — mid-range cube values

(ert-deftest kuro-faces-color--indexed-to-emacs-cube-mid-index-52 ()
  "Index 52: cube offset=36, r=1*51=51, g=0*51=0, b=0*51=0 → #330000."
  ;; cube offset = 52-16 = 36
  ;; r = (36/36)*51 = 51 = 0x33
  ;; g = ((36 mod 36)/6)*51 = 0
  ;; b = (36 mod 6)*51 = 0
  (should (equal (kuro--indexed-to-emacs 52) "#330000")))

(ert-deftest kuro-faces-color--indexed-to-emacs-cube-mid-index-118 ()
  "Index 118: cube offset=102, r=2*51=102, g=5*51=255, b=0*51=0 → #66ff00."
  ;; cube offset = 118-16 = 102
  ;; r = (102/36)*51 = 2*51 = 102 = 0x66
  ;; g = ((102 mod 36)/6)*51 = (102 mod 36)=30, 30/6=5 → 5*51=255 = 0xff
  ;; b = (102 mod 6)*51 = 0*51 = 0
  (should (equal (kuro--indexed-to-emacs 118) "#66ff00")))

(ert-deftest kuro-faces-color--indexed-to-emacs-grayscale-mid-index-244 ()
  "Index 244: grayscale offset=12, val=12*10+8=128=0x80 → #808080."
  (should (equal (kuro--indexed-to-emacs 244) "#808080")))

(ert-deftest kuro-faces-color--indexed-to-emacs-named-range-index-7 ()
  "Index 7 falls in the named range (0-15); returns hash-table lookup for \"white\"."
  ;; kuro--indexed-to-emacs delegates to kuro--named-colors for indices 0-15
  ;; In test environment kuro--named-colors may be empty; result is nil or a string.
  (let ((result (kuro--indexed-to-emacs 7)))
    ;; Must be nil or a string — not an error
    (should (or (null result) (stringp result)))))

;;; Group 9: kuro--rgb-to-emacs — asymmetric and low-byte values

(ert-deftest kuro-faces-color--rgb-to-emacs-asymmetric ()
  "kuro--rgb-to-emacs correctly extracts non-equal R/G/B channels."
  (should (equal (kuro--rgb-to-emacs #xAB1234) "#ab1234"))
  (should (equal (kuro--rgb-to-emacs #x010203) "#010203"))
  (should (equal (kuro--rgb-to-emacs #xFE0080) "#fe0080")))

(ert-deftest kuro-faces-color--rgb-to-emacs-single-red-channel ()
  "kuro--rgb-to-emacs isolates the red channel correctly."
  (should (equal (kuro--rgb-to-emacs #xFF0000) "#ff0000"))
  (should (equal (kuro--rgb-to-emacs #x010000) "#010000")))

(ert-deftest kuro-faces-color--rgb-to-emacs-single-green-channel ()
  "kuro--rgb-to-emacs isolates the green channel correctly."
  (should (equal (kuro--rgb-to-emacs #x00FF00) "#00ff00"))
  (should (equal (kuro--rgb-to-emacs #x000100) "#000100")))

(ert-deftest kuro-faces-color--rgb-to-emacs-single-blue-channel ()
  "kuro--rgb-to-emacs isolates the blue channel correctly."
  (should (equal (kuro--rgb-to-emacs #x0000FF) "#0000ff"))
  (should (equal (kuro--rgb-to-emacs #x000001) "#000001")))

;;; Group 10: kuro--decode-ffi-color — named indices 1-7

(ert-deftest kuro-faces-color--decode-ffi-color-named-index-1 ()
  "Named color at index 1 decodes to (named . \"red\")."
  (let ((result (kuro--decode-ffi-color (logior #x80000000 1))))
    (should (consp result))
    (should (eq (car result) 'named))
    (should (string= (cdr result) "red"))))

(ert-deftest kuro-faces-color--decode-ffi-color-named-index-7 ()
  "Named color at index 7 decodes to (named . \"white\")."
  (let ((result (kuro--decode-ffi-color (logior #x80000000 7))))
    (should (consp result))
    (should (eq (car result) 'named))
    (should (string= (cdr result) "white"))))

(ert-deftest kuro-faces-color--decode-ffi-color-named-index-8 ()
  "Named color at index 8 decodes to (named . \"bright-black\")."
  (let ((result (kuro--decode-ffi-color (logior #x80000000 8))))
    (should (consp result))
    (should (eq (car result) 'named))
    (should (string= (cdr result) "bright-black"))))

(ert-deftest kuro-faces-color--decode-ffi-color-indexed-mid ()
  "Indexed color at index 128 decodes to (indexed . 128)."
  (let ((result (kuro--decode-ffi-color (logior #x40000000 128))))
    (should (consp result))
    (should (eq (car result) 'indexed))
    (should (= (cdr result) 128))))

(ert-deftest kuro-faces-color--decode-ffi-color-rgb-mid ()
  "0x007F3F1F decodes to (rgb . #x7F3F1F)."
  (let ((result (kuro--decode-ffi-color #x007F3F1F)))
    (should (consp result))
    (should (eq (car result) 'rgb))
    (should (= (cdr result) #x7F3F1F))))

;;; Group 11: kuro--get-cached-face-raw — ul-enc normalization and cache eviction
;;
;; kuro--get-cached-face-raw is defined in kuro-faces.el which requires kuro-faces-color.
;; These tests verify the underline-color normalization logic and the max-size eviction
;; guard without touching the face-display layer (kuro--attrs-to-face-props is stubbed).

(defmacro kuro-faces-color-test--with-face-stubs (&rest body)
  "Execute BODY with kuro--attrs-to-face-props and kuro--decode-ffi-color stubbed.
The stubs return deterministic values so tests do not depend on display state."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'kuro--attrs-to-face-props)
              (lambda (fg bg _flags _ul) (list :fg fg :bg bg)))
             ((symbol-function 'kuro--decode-ffi-color)
              (lambda (enc) (cons 'rgb enc)))
             ((symbol-function 'display-graphic-p) #'ignore))
     ,@body))

(ert-deftest kuro-faces-color--cached-face-raw-ul-zero-normalized ()
  "ul-enc=0 and ul-enc=#xFF000000 produce the same cache entry (both normalized to 0)."
  (require 'kuro-faces)
  (kuro-faces-color-test--with-face-stubs
    (kuro--clear-face-cache)
    (let ((face-zero (kuro--get-cached-face-raw 0 0 0 0))
          (face-sentinel (kuro--get-cached-face-raw 0 0 0 #xFF000000)))
      ;; Both calls must return the same cached object (eq, not just equal).
      (should (eq face-zero face-sentinel)))))

(ert-deftest kuro-faces-color--cached-face-raw-ul-nil-normalized ()
  "ul-enc=nil is normalized to 0 and hits the same cache slot as ul-enc=0."
  (require 'kuro-faces)
  (kuro-faces-color-test--with-face-stubs
    (kuro--clear-face-cache)
    (let ((face-zero (kuro--get-cached-face-raw 0 0 0 0))
          (face-nil  (kuro--get-cached-face-raw 0 0 0 nil)))
      (should (eq face-zero face-nil)))))

(ert-deftest kuro-faces-color--cached-face-raw-nonzero-ul-distinct-from-zero ()
  "A non-zero, non-sentinel ul-enc is kept distinct from ul-enc=0 in the cache."
  (require 'kuro-faces)
  (kuro-faces-color-test--with-face-stubs
    (kuro--clear-face-cache)
    (let ((face-no-ul   (kuro--get-cached-face-raw 0 0 0 0))
          (face-with-ul (kuro--get-cached-face-raw 0 0 0 #x0000FF)))
      ;; Different cache keys must produce different (non-eq) entries.
      (should-not (eq face-no-ul face-with-ul)))))

(ert-deftest kuro-faces-color--cached-face-raw-cache-hit-returns-eq ()
  "Two identical calls return the exact same (eq) object from the cache."
  (require 'kuro-faces)
  (kuro-faces-color-test--with-face-stubs
    (kuro--clear-face-cache)
    (let ((first  (kuro--get-cached-face-raw 1 2 3 4))
          (second (kuro--get-cached-face-raw 1 2 3 4)))
      (should (eq first second)))))

(ert-deftest kuro-faces-color--cached-face-raw-evicts-at-max-size ()
  "kuro--get-cached-face-raw clears the cache when it exceeds kuro--face-cache-max-size."
  (require 'kuro-faces)
  (kuro-faces-color-test--with-face-stubs
    (kuro--clear-face-cache)
    ;; Flood the cache past the max size using distinct fg values 0..N.
    ;; We use kuro--face-cache-max-size + 2 to guarantee we cross the threshold.
    (dotimes (i (+ kuro--face-cache-max-size 2))
      (kuro--get-cached-face-raw i 0 0 0))
    ;; After eviction the cache should be small (just the last inserted entry).
    (should (< (hash-table-count kuro--face-cache)
               kuro--face-cache-max-size))))

(ert-deftest kuro-faces-color--cached-face-raw-lookup-key-reused ()
  "kuro--face-cache-lookup-key is a pre-allocated vector (not nil after first call)."
  (require 'kuro-faces)
  (kuro-faces-color-test--with-face-stubs
    (kuro--clear-face-cache)
    (kuro--get-cached-face-raw 0 0 0 0)
    (should (vectorp kuro--face-cache-lookup-key))
    (should (= (length kuro--face-cache-lookup-key) 4))))

;;; Group 12: kuro--color-cube-table and kuro--grayscale-table constants

(ert-deftest kuro-faces-color--color-cube-table-is-vector ()
  "kuro--color-cube-table must be a vector."
  (should (vectorp kuro--color-cube-table)))

(ert-deftest kuro-faces-color--color-cube-table-length-216 ()
  "kuro--color-cube-table must have exactly 216 entries."
  (should (= (length kuro--color-cube-table) 216)))

(ert-deftest kuro-faces-color--color-cube-table-all-hex-strings ()
  "Every entry in kuro--color-cube-table must be a 7-char #RRGGBB string."
  (dotimes (i 216)
    (let ((entry (aref kuro--color-cube-table i)))
      (should (stringp entry))
      (should (string-match-p "^#[0-9a-f]\\{6\\}$" entry)))))

(ert-deftest kuro-faces-color--color-cube-table-first-entry-black ()
  "Entry 0 of kuro--color-cube-table (index 16) must be #000000."
  (should (equal (aref kuro--color-cube-table 0) "#000000")))

(ert-deftest kuro-faces-color--color-cube-table-last-entry-white ()
  "Entry 215 of kuro--color-cube-table (index 231) must be #ffffff."
  (should (equal (aref kuro--color-cube-table 215) "#ffffff")))

(ert-deftest kuro-faces-color--grayscale-table-is-vector ()
  "kuro--grayscale-table must be a vector."
  (should (vectorp kuro--grayscale-table)))

(ert-deftest kuro-faces-color--grayscale-table-length-24 ()
  "kuro--grayscale-table must have exactly 24 entries."
  (should (= (length kuro--grayscale-table) 24)))

(ert-deftest kuro-faces-color--grayscale-table-entries-equal-rgb-components ()
  "Every grayscale entry must have equal R=G=B components."
  (dotimes (i 24)
    (let ((entry (aref kuro--grayscale-table i)))
      (should (string-match "^#\\([0-9a-f][0-9a-f]\\)\\1\\1$" entry)))))

;;; Group 13: kuro--decode-ffi-color — ffi-color-default vs named tag bit priority

(ert-deftest kuro-faces-color--decode-ffi-color-default-sentinel-has-priority ()
  "kuro--ffi-color-default (#xFF000000) decodes to :default, not a named color.
The sentinel check precedes the tag-bit check in kuro--decode-ffi-color."
  ;; #xFF000000 has bit 31 set (named tag), but the sentinel check fires first.
  (should (eq (kuro--decode-ffi-color #xFF000000) :default)))

(ert-deftest kuro-faces-color--decode-ffi-color-named-index-5 ()
  "Named color at index 5 decodes to (named . \"magenta\")."
  (let ((result (kuro--decode-ffi-color (logior #x80000000 5))))
    (should (consp result))
    (should (eq (car result) 'named))
    (should (string= (cdr result) "magenta"))))

(ert-deftest kuro-faces-color--decode-ffi-color-named-index-14 ()
  "Named color at index 14 decodes to (named . \"bright-cyan\")."
  (let ((result (kuro--decode-ffi-color (logior #x80000000 14))))
    (should (consp result))
    (should (eq (car result) 'named))
    (should (string= (cdr result) "bright-cyan"))))

(ert-deftest kuro-faces-color--decode-ffi-color-named-index-17-out-of-range ()
  "Named tag with index 17 (beyond 0-15) returns nil."
  (let ((result (kuro--decode-ffi-color (logior #x80000000 17))))
    (should (null result))))

(ert-deftest kuro-faces-color--decode-ffi-color-indexed-named-boundary ()
  "Indexed color at index 15 (named ANSI range boundary) decodes to (indexed . 15)."
  ;; kuro--decode-ffi-color bit-30 path does NOT delegate; returns (indexed . N).
  (let ((result (kuro--decode-ffi-color (logior #x40000000 15))))
    (should (consp result))
    (should (eq (car result) 'indexed))
    (should (= (cdr result) 15))))

(ert-deftest kuro-faces-color--decode-ffi-color-rgb-max-value ()
  "0x00FFFFFF decodes to (rgb . #xFFFFFF) — max RGB value."
  (let ((result (kuro--decode-ffi-color #x00FFFFFF)))
    (should (consp result))
    (should (eq (car result) 'rgb))
    (should (= (cdr result) #xFFFFFF))))

(ert-deftest kuro-faces-color--decode-ffi-color-rgb-single-byte ()
  "0x00000001 decodes to (rgb . 1) — single low-byte RGB value."
  (let ((result (kuro--decode-ffi-color 1)))
    (should (consp result))
    (should (eq (car result) 'rgb))
    (should (= (cdr result) 1))))

(ert-deftest kuro-faces-color--color-to-emacs-indexed-255 ()
  "kuro--color-to-emacs (indexed . 255) returns grayscale entry #eeeeee."
  (kuro-faces-color-test--with-named-colors '()
    (should (equal (kuro--color-to-emacs '(indexed . 255)) "#eeeeee"))))

(ert-deftest kuro-faces-color--color-to-emacs-indexed-232 ()
  "kuro--color-to-emacs (indexed . 232) returns grayscale entry #080808."
  (kuro-faces-color-test--with-named-colors '()
    (should (equal (kuro--color-to-emacs '(indexed . 232)) "#080808"))))

(ert-deftest kuro-faces-color--color-to-emacs-indexed-out-of-range-nil ()
  "kuro--color-to-emacs (indexed . 256) returns nil (delegates to kuro--indexed-to-emacs)."
  (kuro-faces-color-test--with-named-colors '()
    (should (null (kuro--color-to-emacs '(indexed . 256))))))

;;; Group 14: named color full-range, cube/grayscale boundary verification,
;;;           and kuro--color-to-emacs default fg/bg handling

;; Macro: iterate named-color indices and verify decoded name
(defmacro kuro-faces-color-test--assert-named-color (index expected-name)
  "Assert that FFI encoding of named color at INDEX decodes to EXPECTED-NAME."
  `(let ((result (kuro--decode-ffi-color (logior kuro--color-tag-named ,index))))
     (should (consp result))
     (should (eq (car result) 'named))
     (should (string= (cdr result) ,expected-name))))

(ert-deftest kuro-faces-color--named-colors-indices-2-and-3 ()
  "Named color indices 2 (green) and 3 (yellow) decode correctly."
  (kuro-faces-color-test--assert-named-color 2 "green")
  (kuro-faces-color-test--assert-named-color 3 "yellow"))

(ert-deftest kuro-faces-color--named-colors-indices-4-and-6 ()
  "Named color indices 4 (blue) and 6 (cyan) decode correctly."
  (kuro-faces-color-test--assert-named-color 4 "blue")
  (kuro-faces-color-test--assert-named-color 6 "cyan"))

(ert-deftest kuro-faces-color--named-colors-indices-9-10-11 ()
  "Named color indices 9/10/11 decode to bright-red/bright-green/bright-yellow."
  (kuro-faces-color-test--assert-named-color 9  "bright-red")
  (kuro-faces-color-test--assert-named-color 10 "bright-green")
  (kuro-faces-color-test--assert-named-color 11 "bright-yellow"))

(ert-deftest kuro-faces-color--named-colors-indices-12-13 ()
  "Named color indices 12/13 decode to bright-blue/bright-magenta."
  (kuro-faces-color-test--assert-named-color 12 "bright-blue")
  (kuro-faces-color-test--assert-named-color 13 "bright-magenta"))

(ert-deftest kuro-faces-color--color-cube-table-entry-16-exact ()
  "Index 16 (cube offset 0): r=0,g=0,b=0 → #000000."
  ;; offset = 16-16 = 0; r=0*51=0, g=0*51=0, b=0*51=0
  (should (equal (aref kuro--color-cube-table 0) "#000000")))

(ert-deftest kuro-faces-color--indexed-to-emacs-index-16-exact ()
  "kuro--indexed-to-emacs 16 returns #000000 (start of cube)."
  (should (equal (kuro--indexed-to-emacs 16) "#000000")))

(ert-deftest kuro-faces-color--indexed-to-emacs-index-232-exact ()
  "kuro--indexed-to-emacs 232 returns #080808 (start of grayscale ramp).
offset=0, val=0*10+8=8=0x08 → #080808."
  (should (equal (kuro--indexed-to-emacs 232) "#080808")))

(ert-deftest kuro-faces-color--indexed-to-emacs-index-255-exact ()
  "kuro--indexed-to-emacs 255 returns #eeeeee (last grayscale ramp entry).
offset=23, val=23*10+8=238=0xee → #eeeeee."
  (should (equal (kuro--indexed-to-emacs 255) "#eeeeee")))

(ert-deftest kuro-faces-color--color-to-emacs-default-fg-and-bg ()
  "kuro--color-to-emacs returns nil for both :default (fg) and :default (bg).
This models the no-color fast-path where both fg and bg use terminal default."
  (kuro-faces-color-test--with-named-colors '()
    (should (null (kuro--color-to-emacs :default)))
    ;; Simulate a second call for bg — must also be nil.
    (should (null (kuro--color-to-emacs :default)))))

(ert-deftest kuro-faces-color--color-to-emacs-rgb-full-coverage ()
  "kuro--color-to-emacs handles (rgb . N) for low, mid, and max N values."
  (kuro-faces-color-test--with-named-colors '()
    (should (equal (kuro--color-to-emacs '(rgb . 0))        "#000000"))
    (should (equal (kuro--color-to-emacs '(rgb . #x808080)) "#808080"))
    (should (equal (kuro--color-to-emacs '(rgb . #xFFFFFF)) "#ffffff"))))

(ert-deftest kuro-faces-color--color-cube-table-index-108-exact ()
  "kuro--color-cube-table entry at offset 108 (index 124): r=3,g=0,b=0 → #990000."
  ;; offset = 108; r=(108/36)*51=3*51=153=0x99; g=((108 mod 36)/6)*51=0*51=0; b=(108 mod 6)*51=0
  (should (equal (aref kuro--color-cube-table 108) "#990000")))

(ert-deftest kuro-faces-color--grayscale-table-entry-0-exact ()
  "kuro--grayscale-table entry 0 (index 232): val=0*10+8=8=0x08 → #080808."
  (should (equal (aref kuro--grayscale-table 0) "#080808")))

(ert-deftest kuro-faces-color--grayscale-table-entry-23-exact ()
  "kuro--grayscale-table entry 23 (index 255): val=23*10+8=238=0xee → #eeeeee."
  (should (equal (aref kuro--grayscale-table 23) "#eeeeee")))

(provide 'kuro-faces-color-test)

;;; kuro-faces-color-test.el ends here
