;;; kuro-faces-test-2.el --- Unit tests for kuro-faces.el (part 2)  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-faces)
(require 'kuro-char-width)
(require 'kuro-overlays)

;;; Group 10: Character width table and font detection

(defconst kuro-faces-test--char-width-table
  '((kuro-test-char-width-table-emoji ?\U0001F525 2)
    (kuro-test-char-width-table-cjk   ?\u65E5     2)
    (kuro-test-char-width-table-pua   ?\xE0B0     1))
  "Table of (test-name char expected-width) after `kuro--setup-char-width-table'.")

(defmacro kuro-faces-test--def-char-width (test-name char expected)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--setup-char-width-table': char-width of U+%04X \u2192 %d." char expected)
     (with-temp-buffer
       (kuro--setup-char-width-table)
       (should (= (char-width ,char) ,expected)))))

(kuro-faces-test--def-char-width kuro-test-char-width-table-emoji ?\U0001F525 2)
(kuro-faces-test--def-char-width kuro-test-char-width-table-cjk   ?\u65E5     2)
(kuro-faces-test--def-char-width kuro-test-char-width-table-pua   ?\xE0B0     1)

(ert-deftest kuro-faces-test--char-width-all-entries ()
  "Invariant: char-width matches expected for all entries in char-width table."
  (dolist (entry kuro-faces-test--char-width-table)
    (pcase-let ((`(,_name ,char ,expected) entry))
      (with-temp-buffer
        (kuro--setup-char-width-table)
        (should (= (char-width char) expected))))))

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
    ;; Use index 0 (black) with a non-default color (R=1,G=2,B=3) to force a change.
    (cl-letf (((symbol-function 'kuro--get-palette-updates)
               (lambda () '((0 1 2 3)))))
      (kuro--rebuild-named-colors)         ; reset to defaults first
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

;;; Group 12: palette entry application via kuro--apply-palette-updates

(defconst kuro-faces-test--merge-palette-entry-table
  '((kuro-test-merge-palette-entry-valid-index  4  0   0   255 "blue"         "#0000ff")
    (kuro-test-merge-palette-entry-index-15    15 200 210  220 "bright-white" "#c8d2dc"))
  "Table of (test-name idx r g b color-name expected-hex) for palette-update writes.")

(defmacro kuro-faces-test--def-merge-palette-entry (test-name idx r g b color-name expected-hex)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--apply-palette-updates' idx=%d → %s in named-colors." idx expected-hex)
     (let ((kuro--initialized t))
       (kuro--rebuild-named-colors)
       (cl-letf (((symbol-function 'kuro--get-palette-updates)
                  (lambda () (list (list ,idx ,r ,g ,b)))))
         (kuro--apply-palette-updates)
         (should (equal (gethash ,color-name kuro--named-colors) ,expected-hex))))))

(kuro-faces-test--def-merge-palette-entry kuro-test-merge-palette-entry-valid-index  4  0   0   255 "blue"         "#0000ff")
(kuro-faces-test--def-merge-palette-entry kuro-test-merge-palette-entry-index-15    15 200 210  220 "bright-white" "#c8d2dc")

(ert-deftest kuro-faces-test--all-merge-palette-entries-correct ()
  "All entries in `kuro-faces-test--merge-palette-entry-table' write correct hex colors."
  (dolist (entry kuro-faces-test--merge-palette-entry-table)
    (pcase-let ((`(,_name ,idx ,r ,g ,b ,color-name ,expected-hex) entry))
      (let ((kuro--initialized t))
        (kuro--rebuild-named-colors)
        (cl-letf (((symbol-function 'kuro--get-palette-updates)
                   (lambda () (list (list idx r g b)))))
          (kuro--apply-palette-updates)
          (should (equal (gethash color-name kuro--named-colors) expected-hex)))))))

(ert-deftest kuro-test-merge-palette-entry-index-16-ignored ()
  "kuro--apply-palette-updates silently ignores index 16 (out of ANSI range)."
  (let ((kuro--initialized t))
    (kuro--rebuild-named-colors)
    (let ((before (gethash "black" kuro--named-colors)))
      (cl-letf (((symbol-function 'kuro--get-palette-updates)
                 (lambda () '((16 1 2 3)))))
        (kuro--apply-palette-updates)
        ;; The named-colors table should be unchanged for all 16 ANSI names.
        (should (equal (gethash "black" kuro--named-colors) before))))))

(ert-deftest kuro-test-merge-palette-entry-no-face-cache-side-effect ()
  "kuro--apply-palette-updates does not flush the face cache when no color changes."
  (let ((kuro--initialized t))
    (kuro--rebuild-named-colors)
    (kuro--clear-face-cache)
    (kuro--get-cached-face-raw 0 0 0 0)  ; seed one entry
    (let ((count-before (hash-table-count kuro--face-cache)))
      ;; Use the default black color (#000000) so no change occurs and cache is preserved.
      (cl-letf (((symbol-function 'kuro--get-palette-updates)
                 (lambda () '((0 0 0 0)))))
        (kuro--apply-palette-updates)
        (should (= (hash-table-count kuro--face-cache) count-before))))))

;;; Group 13: kuro--make-face

(ert-deftest kuro-faces-make-face-returns-list ()
  "kuro--make-face returns a plist (list) for default color args."
  (let ((result (kuro--make-face :default :default 0 nil)))
    (should (listp result))))

(defconst kuro-faces-test--make-face-single-attr-table
  '((kuro-faces-make-face-bold-weight  1 :weight bold)
    (kuro-faces-make-face-italic-slant 4 :slant  italic))
  "Table of (test-name flags plist-key expected-val) for single-attribute kuro--make-face.")

(defmacro kuro-faces-test--def-make-face-single-attr (test-name flags plist-key expected-val)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--make-face' flags=%d: plist-get %s → %s." flags plist-key expected-val)
     (let ((result (kuro--make-face :default :default ,flags nil)))
       (should (eq (plist-get result ,plist-key) ',expected-val)))))

(kuro-faces-test--def-make-face-single-attr kuro-faces-make-face-bold-weight  1 :weight bold)
(kuro-faces-test--def-make-face-single-attr kuro-faces-make-face-italic-slant 4 :slant  italic)

(ert-deftest kuro-faces-test--make-face-single-attr-all-entries ()
  "Invariant: each flag produces the expected plist attribute in kuro--make-face."
  (dolist (entry kuro-faces-test--make-face-single-attr-table)
    (pcase-let ((`(,_name ,flags ,plist-key ,expected-val) entry))
      (let ((result (kuro--make-face :default :default flags nil)))
        (should (eq (plist-get result plist-key) expected-val))))))

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

(defconst kuro-faces-test--ul-enc-distinct-table
  '((kuro-faces-cached-face-raw-max-u32-ul-is-distinct #xFFFFFFFF)
    (kuro-faces-cached-face-raw-nonzero-ul-distinct     #x0000FF))
  "Table: (test-name ul-enc) — each ul-enc must be cache-distinct from ul-enc=0.")

(defmacro kuro-faces-test--def-ul-enc-distinct (test-name ul-enc)
  `(ert-deftest ,test-name ()
     ,(format "ul-enc=#x%X is NOT normalized to 0 and produces a distinct cache entry." ul-enc)
     (kuro--clear-face-cache)
     (let ((face-zero  (kuro--get-cached-face-raw 0 0 0 0))
           (face-other (kuro--get-cached-face-raw 0 0 0 ,ul-enc)))
       (should-not (eq face-zero face-other)))))

(kuro-faces-test--def-ul-enc-distinct kuro-faces-cached-face-raw-max-u32-ul-is-distinct #xFFFFFFFF)
(kuro-faces-test--def-ul-enc-distinct kuro-faces-cached-face-raw-nonzero-ul-distinct     #x0000FF)

(ert-deftest kuro-faces-test--all-ul-enc-distinct ()
  "Invariant: each ul-enc in the table produces a cache entry distinct from ul-enc=0."
  (dolist (entry kuro-faces-test--ul-enc-distinct-table)
    (pcase-let ((`(,_name ,ul-enc) entry))
      (kuro--clear-face-cache)
      (let ((face-zero  (kuro--get-cached-face-raw 0 0 0 0))
            (face-other (kuro--get-cached-face-raw 0 0 0 ul-enc)))
        (should-not (eq face-zero face-other))))))

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

(provide 'kuro-faces-test-2)

;;; kuro-faces-test-2.el ends here
