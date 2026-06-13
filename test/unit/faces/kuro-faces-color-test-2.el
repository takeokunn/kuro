;;; kuro-faces-color-test-2.el --- kuro-faces-color-test (part 2)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-faces-color-test-support)

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

(defconst kuro-faces-color-test--rgb-to-emacs-extended-table
  ;;  test-name                                           input       expected
  '((kuro-faces-color--rgb-to-emacs-asymmetric-ab1234    #xAB1234    "#ab1234")
    (kuro-faces-color--rgb-to-emacs-asymmetric-010203    #x010203    "#010203")
    (kuro-faces-color--rgb-to-emacs-asymmetric-fe0080    #xFE0080    "#fe0080")
    (kuro-faces-color--rgb-to-emacs-red-full             #xFF0000    "#ff0000")
    (kuro-faces-color--rgb-to-emacs-red-low              #x010000    "#010000")
    (kuro-faces-color--rgb-to-emacs-green-full           #x00FF00    "#00ff00")
    (kuro-faces-color--rgb-to-emacs-green-low            #x000100    "#000100")
    (kuro-faces-color--rgb-to-emacs-blue-full            #x0000FF    "#0000ff")
    (kuro-faces-color--rgb-to-emacs-blue-low             #x000001    "#000001"))
  "Table of (test-name rgb-int expected-hex) for extended `kuro--rgb-to-emacs' coverage.")

(defmacro kuro-faces-color-test--def-rgb-to-emacs-ext (test-name input expected)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--rgb-to-emacs' #x%X → %S." input expected)
     (should (equal (kuro--rgb-to-emacs ,input) ,expected))))

(kuro-faces-color-test--def-rgb-to-emacs-ext kuro-faces-color--rgb-to-emacs-asymmetric-ab1234 #xAB1234 "#ab1234")
(kuro-faces-color-test--def-rgb-to-emacs-ext kuro-faces-color--rgb-to-emacs-asymmetric-010203 #x010203 "#010203")
(kuro-faces-color-test--def-rgb-to-emacs-ext kuro-faces-color--rgb-to-emacs-asymmetric-fe0080 #xFE0080 "#fe0080")
(kuro-faces-color-test--def-rgb-to-emacs-ext kuro-faces-color--rgb-to-emacs-red-full          #xFF0000 "#ff0000")
(kuro-faces-color-test--def-rgb-to-emacs-ext kuro-faces-color--rgb-to-emacs-red-low           #x010000 "#010000")
(kuro-faces-color-test--def-rgb-to-emacs-ext kuro-faces-color--rgb-to-emacs-green-full        #x00FF00 "#00ff00")
(kuro-faces-color-test--def-rgb-to-emacs-ext kuro-faces-color--rgb-to-emacs-green-low         #x000100 "#000100")
(kuro-faces-color-test--def-rgb-to-emacs-ext kuro-faces-color--rgb-to-emacs-blue-full         #x0000FF "#0000ff")
(kuro-faces-color-test--def-rgb-to-emacs-ext kuro-faces-color--rgb-to-emacs-blue-low          #x000001 "#000001")

(ert-deftest kuro-faces-color-test--all-rgb-to-emacs-ext-correct ()
  "All kuro-faces-color-test--rgb-to-emacs-extended-table entries produce the expected hex."
  (dolist (entry kuro-faces-color-test--rgb-to-emacs-extended-table)
    (pcase-let ((`(,_name ,input ,expected) entry))
      (should (equal (kuro--rgb-to-emacs input) expected)))))

;;; Groups 10+13: kuro--decode-ffi-color — cons-result cases

(defconst kuro-faces-color-test--decode-ffi-color-cons-table
  `((kuro-faces-color--decode-ffi-color-named-index-1          ,(logior #x80000000  1)  named   "red")
    (kuro-faces-color--decode-ffi-color-named-index-5          ,(logior #x80000000  5)  named   "magenta")
    (kuro-faces-color--decode-ffi-color-named-index-7          ,(logior #x80000000  7)  named   "white")
    (kuro-faces-color--decode-ffi-color-named-index-8          ,(logior #x80000000  8)  named   "bright-black")
    (kuro-faces-color--decode-ffi-color-named-index-14         ,(logior #x80000000 14)  named   "bright-cyan")
    (kuro-faces-color--decode-ffi-color-indexed-mid            ,(logior #x40000000 128) indexed 128)
    (kuro-faces-color--decode-ffi-color-indexed-named-boundary ,(logior #x40000000  15) indexed 15)
    (kuro-faces-color--decode-ffi-color-rgb-mid                #x007F3F1F               rgb     #x7F3F1F)
    (kuro-faces-color--decode-ffi-color-rgb-max-value          #x00FFFFFF               rgb     #xFFFFFF)
    (kuro-faces-color--decode-ffi-color-rgb-single-byte        1                        rgb     1))
  "Table of (test-name enc type value) for `kuro--decode-ffi-color' cons-result cases.")

(defmacro kuro-faces-color-test--def-decode-ffi-color-cons (test-name enc type value)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--decode-ffi-color' → (%s . %S)." type value)
     (let ((result (kuro--decode-ffi-color ,enc)))
       (should (consp result))
       (should (eq    (car result) ',type))
       (should (equal (cdr result) ,value)))))

(kuro-faces-color-test--def-decode-ffi-color-cons kuro-faces-color--decode-ffi-color-named-index-1          (logior #x80000000  1)  named   "red")
(kuro-faces-color-test--def-decode-ffi-color-cons kuro-faces-color--decode-ffi-color-named-index-5          (logior #x80000000  5)  named   "magenta")
(kuro-faces-color-test--def-decode-ffi-color-cons kuro-faces-color--decode-ffi-color-named-index-7          (logior #x80000000  7)  named   "white")
(kuro-faces-color-test--def-decode-ffi-color-cons kuro-faces-color--decode-ffi-color-named-index-8          (logior #x80000000  8)  named   "bright-black")
(kuro-faces-color-test--def-decode-ffi-color-cons kuro-faces-color--decode-ffi-color-named-index-14         (logior #x80000000 14)  named   "bright-cyan")
(kuro-faces-color-test--def-decode-ffi-color-cons kuro-faces-color--decode-ffi-color-indexed-mid            (logior #x40000000 128) indexed 128)
(kuro-faces-color-test--def-decode-ffi-color-cons kuro-faces-color--decode-ffi-color-indexed-named-boundary (logior #x40000000  15) indexed 15)
(kuro-faces-color-test--def-decode-ffi-color-cons kuro-faces-color--decode-ffi-color-rgb-mid                #x007F3F1F               rgb     #x7F3F1F)
(kuro-faces-color-test--def-decode-ffi-color-cons kuro-faces-color--decode-ffi-color-rgb-max-value          #x00FFFFFF               rgb     #xFFFFFF)
(kuro-faces-color-test--def-decode-ffi-color-cons kuro-faces-color--decode-ffi-color-rgb-single-byte        1                        rgb     1)

(ert-deftest kuro-faces-color--decode-ffi-color-cons-table-all-correct ()
  "Every entry in `kuro-faces-color-test--decode-ffi-color-cons-table' returns the expected cons."
  (dolist (entry kuro-faces-color-test--decode-ffi-color-cons-table)
    (pcase-let ((`(,_name ,enc ,type ,value) entry))
      (let ((result (kuro--decode-ffi-color enc)))
        (should (consp result))
        (should (eq    (car result) type))
        (should (equal (cdr result) value))))))

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

(ert-deftest kuro-faces-color--cached-face-raw-ul-maxu32-not-normalized ()
  "ul-enc=#xFFFFFFFF (max u32) is NOT normalized to 0 — distinct cache slot."
  (require 'kuro-faces)
  (kuro-faces-color-test--with-face-stubs
    (kuro--clear-face-cache)
    (let ((face-zero   (kuro--get-cached-face-raw 0 0 0 0))
          (face-maxu32 (kuro--get-cached-face-raw 0 0 0 #xFFFFFFFF)))
      (should-not (eq face-zero face-maxu32)))))

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

(ert-deftest kuro-faces-color--decode-ffi-color-named-index-17-out-of-range ()
  "Named tag with index 17 (beyond 0-15) returns nil."
  (let ((result (kuro--decode-ffi-color (logior #x80000000 17))))
    (should (null result))))

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

(kuro-faces-color-test--def-decode-ffi-color-cons kuro-faces-color--decode-ffi-color-named-index-2  (logior kuro--color-tag-named  2) named "green")
(kuro-faces-color-test--def-decode-ffi-color-cons kuro-faces-color--decode-ffi-color-named-index-3  (logior kuro--color-tag-named  3) named "yellow")
(kuro-faces-color-test--def-decode-ffi-color-cons kuro-faces-color--decode-ffi-color-named-index-4  (logior kuro--color-tag-named  4) named "blue")
(kuro-faces-color-test--def-decode-ffi-color-cons kuro-faces-color--decode-ffi-color-named-index-6  (logior kuro--color-tag-named  6) named "cyan")
(kuro-faces-color-test--def-decode-ffi-color-cons kuro-faces-color--decode-ffi-color-named-index-9  (logior kuro--color-tag-named  9) named "bright-red")
(kuro-faces-color-test--def-decode-ffi-color-cons kuro-faces-color--decode-ffi-color-named-index-10 (logior kuro--color-tag-named 10) named "bright-green")
(kuro-faces-color-test--def-decode-ffi-color-cons kuro-faces-color--decode-ffi-color-named-index-11 (logior kuro--color-tag-named 11) named "bright-yellow")
(kuro-faces-color-test--def-decode-ffi-color-cons kuro-faces-color--decode-ffi-color-named-index-12 (logior kuro--color-tag-named 12) named "bright-blue")
(kuro-faces-color-test--def-decode-ffi-color-cons kuro-faces-color--decode-ffi-color-named-index-13 (logior kuro--color-tag-named 13) named "bright-magenta")

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

;;; Group 15: kuro--color-type-handlers invariants + kuro--color-named-to-emacs ─

(ert-deftest kuro-faces-color--color-type-handlers-is-alist ()
  "`kuro--color-type-handlers' is a non-empty alist."
  (should (consp kuro--color-type-handlers))
  (should (listp kuro--color-type-handlers)))

(ert-deftest kuro-faces-color--color-type-handlers-has-three-entries ()
  "`kuro--color-type-handlers' has exactly three entries (named, indexed, rgb)."
  (should (= 3 (length kuro--color-type-handlers))))

(ert-deftest kuro-faces-color--color-type-handlers-all-keys-present ()
  "`kuro--color-type-handlers' has keys for all three Rust Color variants."
  (should (assq 'named   kuro--color-type-handlers))
  (should (assq 'indexed kuro--color-type-handlers))
  (should (assq 'rgb     kuro--color-type-handlers)))

(ert-deftest kuro-faces-color--color-type-handlers-all-values-fbound ()
  "Every value in `kuro--color-type-handlers' is a bound function symbol."
  (dolist (entry kuro--color-type-handlers)
    (should (fboundp (cdr entry)))))

(ert-deftest kuro-faces-color--color-named-to-emacs-known-name ()
  "`kuro--color-named-to-emacs' returns Emacs color string for a known name."
  (let ((result (kuro--color-named-to-emacs "red")))
    (should (stringp result))))

(ert-deftest kuro-faces-color--color-named-to-emacs-unknown-name-passthrough ()
  "`kuro--color-named-to-emacs' returns the name itself when not in hash table."
  (should (equal (kuro--color-named-to-emacs "not-a-real-color") "not-a-real-color")))

(ert-deftest kuro-faces-color--color-to-emacs-unknown-type-nil ()
  "`kuro--color-to-emacs' returns nil for a cons cell with an unknown type tag."
  (should (null (kuro--color-to-emacs '(unknown-type . 42)))))

(provide 'kuro-faces-color-test-2)

;;; kuro-faces-color-test-2.el ends here
