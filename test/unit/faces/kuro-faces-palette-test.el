;;; kuro-faces-ext-test.el --- Extended unit tests for kuro-faces.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Extended unit tests for kuro-faces.el (palette updates, face cache edge cases,
;; font remapping, default color application).
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-faces)
(require 'kuro-char-width)
(require 'kuro-overlays)

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

(ert-deftest kuro-test-merge-palette-entry-valid-index ()
  "kuro--apply-palette-updates writes the correct hex color for a valid index."
  (let ((kuro--initialized t))
    (kuro--rebuild-named-colors)
    ;; Index 4 = "blue" in kuro--ansi-color-names; default is #492ee1, not #0000ff
    (cl-letf (((symbol-function 'kuro--get-palette-updates)
               (lambda () '((4 0 0 255)))))
      (kuro--apply-palette-updates)
      (should (equal (gethash "blue" kuro--named-colors) "#0000ff")))))

(ert-deftest kuro-test-merge-palette-entry-index-15 ()
  "kuro--apply-palette-updates handles the last valid index (15 = bright-white)."
  (let ((kuro--initialized t))
    (kuro--rebuild-named-colors)
    (cl-letf (((symbol-function 'kuro--get-palette-updates)
               (lambda () '((15 200 210 220)))))
      (kuro--apply-palette-updates)
      (should (equal (gethash "bright-white" kuro--named-colors) "#c8d2dc")))))

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

(ert-deftest kuro-faces-cached-face-raw-max-u32-ul-is-distinct ()
  "ul-enc=#xFFFFFFFF (max u32) is NOT normalized to 0 and produces a distinct face."
  (kuro--clear-face-cache)
  (let ((face-zero   (kuro--get-cached-face-raw 0 0 0 0))
        (face-maxu32 (kuro--get-cached-face-raw 0 0 0 #xFFFFFFFF)))
    (should-not (eq face-zero face-maxu32))))

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

;;; Group 15: Color variables, named-color table, and face uniqueness

(ert-deftest kuro-faces-color-black-is-hex-string ()
  "kuro-color-black is a 6-digit hex color string."
  (should (stringp kuro-color-black))
  (should (string-match-p kuro--hex-color-regexp kuro-color-black)))

(ert-deftest kuro-faces-color-white-is-hex-string ()
  "kuro-color-white is a 6-digit hex color string."
  (should (stringp kuro-color-white))
  (should (string-match-p kuro--hex-color-regexp kuro-color-white)))

(ert-deftest kuro-faces-all-16-color-vars-are-hex-strings ()
  "All 16 kuro-color-* defcustom variables hold valid hex color strings."
  (dolist (sym '(kuro-color-black kuro-color-red kuro-color-green
                 kuro-color-yellow kuro-color-blue kuro-color-magenta
                 kuro-color-cyan kuro-color-white
                 kuro-color-bright-black kuro-color-bright-red
                 kuro-color-bright-green kuro-color-bright-yellow
                 kuro-color-bright-blue kuro-color-bright-magenta
                 kuro-color-bright-cyan kuro-color-bright-white))
    (let ((val (symbol-value sym)))
      (should (stringp val))
      (should (string-match-p kuro--hex-color-regexp val)))))

(ert-deftest kuro-faces-named-colors-hash-has-16-entries ()
  "kuro--named-colors contains exactly 16 entries after rebuild."
  (kuro--rebuild-named-colors)
  (should (= (hash-table-count kuro--named-colors) 16)))

(ert-deftest kuro-faces-named-colors-hash-contains-standard-names ()
  "kuro--named-colors has entries for all standard ANSI color names."
  (kuro--rebuild-named-colors)
  (dolist (name '("black" "red" "green" "yellow"
                  "blue" "magenta" "cyan" "white"
                  "bright-black" "bright-red" "bright-green" "bright-yellow"
                  "bright-blue" "bright-magenta" "bright-cyan" "bright-white"))
    (should (gethash name kuro--named-colors))))

(ert-deftest kuro-faces-cache-miss-returns-nil-on-gethash ()
  "A fresh cache has no entry for an unusual key — gethash returns nil."
  (kuro--clear-face-cache)
  ;; Use a key that we know has never been inserted.
  (let ((key (vector #xDEADBEEF #xDEADBEEF 0 0)))
    (should-not (gethash key kuro--face-cache))))

(ert-deftest kuro-faces-cache-hit-returns-eq-object ()
  "After one cache-miss lookup, a second lookup for the same args returns eq."
  (kuro--clear-face-cache)
  (let ((face1 (kuro--get-cached-face-raw #x80000002 0 0 0))
        (face2 (kuro--get-cached-face-raw #x80000002 0 0 0)))
    (should (eq face1 face2))))

(ert-deftest kuro-faces-unique-attrs-produce-distinct-faces ()
  "Four different attribute flag combinations produce four distinct cache entries.
This exercises the key-uniqueness property that kuro--make-face-name would provide
for named face registration: bold, italic, dim, and strikethrough must not alias."
  (kuro--clear-face-cache)
  (let ((f-bold   (kuro--get-cached-face-raw 0 0 #x01 0))   ; bold
        (f-italic (kuro--get-cached-face-raw 0 0 #x04 0))   ; italic
        (f-dim    (kuro--get-cached-face-raw 0 0 #x02 0))   ; dim
        (f-strike (kuro--get-cached-face-raw 0 0 #x100 0))) ; strikethrough
    (should-not (eq f-bold f-italic))
    (should-not (eq f-bold f-dim))
    (should-not (eq f-bold f-strike))
    (should-not (eq f-italic f-dim))
    (should-not (eq f-italic f-strike))
    (should-not (eq f-dim f-strike))))

(ert-deftest kuro-faces-ansi-color-names-vector-length-16 ()
  "kuro--ansi-color-names is a vector of exactly 16 elements."
  (should (vectorp kuro--ansi-color-names))
  (should (= (length kuro--ansi-color-names) 16)))

(ert-deftest kuro-faces-ansi-color-names-all-strings ()
  "Every element of kuro--ansi-color-names is a non-empty string."
  (dotimes (i 16)
    (let ((name (aref kuro--ansi-color-names i)))
      (should (stringp name))
      (should (< 0 (length name))))))

(ert-deftest kuro-faces-named-colors-all-values-are-hex ()
  "Every value in kuro--named-colors is a 6-digit hex color string."
  (kuro--rebuild-named-colors)
  (maphash (lambda (_k v)
             (should (stringp v))
             (should (string-match-p kuro--hex-color-regexp v)))
           kuro--named-colors))

;;; Group 16: kuro--apply-palette-entry — OSC 4 named-color update

(ert-deftest kuro-faces-apply-palette-entry-updates-named-colors ()
  "idx=0, r=255, g=0, b=0 stores #ff0000 under the name at index 0."
  (kuro--rebuild-named-colors)
  (kuro--apply-palette-entry 0 255 0 0)
  (let ((name (aref kuro--ansi-color-names 0)))
    (should (equal (gethash name kuro--named-colors) "#ff0000"))))

(ert-deftest kuro-faces-apply-palette-entry-returns-t-on-change ()
  "Returns t when the stored color actually changes."
  (kuro--rebuild-named-colors)
  (should (eq t (kuro--apply-palette-entry 0 255 0 0))))

(ert-deftest kuro-faces-apply-palette-entry-returns-nil-when-unchanged ()
  "Returns nil on the second call with identical RGB (no change)."
  (kuro--rebuild-named-colors)
  (kuro--apply-palette-entry 2 0 200 0)
  (should-not (kuro--apply-palette-entry 2 0 200 0)))

(ert-deftest kuro-faces-apply-palette-entry-ignores-idx-16-and-above ()
  "idx=16 returns nil and does not modify kuro--named-colors."
  (kuro--rebuild-named-colors)
  (let ((before (hash-table-count kuro--named-colors)))
    (should-not (kuro--apply-palette-entry 16 255 0 0))
    (should (= (hash-table-count kuro--named-colors) before))))

(ert-deftest kuro-faces-apply-palette-entry-idx-15-accepted ()
  "idx=15 (last valid index) updates the corresponding named color."
  (kuro--rebuild-named-colors)
  (kuro--apply-palette-entry 15 10 20 30)
  (let ((name (aref kuro--ansi-color-names 15)))
    (should (equal (gethash name kuro--named-colors) "#0a141e"))))

;;; Group 17: kuro--apply-font-to-buffer and kuro--remap-default-face

(ert-deftest kuro-faces-apply-font-to-buffer-noop-in-non-graphical ()
  "kuro--apply-font-to-buffer is a no-op when display-graphic-p returns nil."
  (with-temp-buffer
    (setq-local kuro--font-remap-cookie nil)
    (cl-letf (((symbol-function 'display-graphic-p) (lambda () nil)))
      (kuro--apply-font-to-buffer (current-buffer))
      (should (null kuro--font-remap-cookie)))))

(ert-deftest kuro-faces-apply-font-to-buffer-sets-cookie-with-family ()
  "kuro--apply-font-to-buffer sets kuro--font-remap-cookie in graphical frame."
  (with-temp-buffer
    (setq-local kuro--font-remap-cookie nil)
    (let ((kuro-font-family "Monospace")
          (kuro-font-size nil))
      (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
                ((symbol-function 'face-remap-add-relative)
                 (lambda (&rest _) 'fake-cookie)))
        (kuro--apply-font-to-buffer (current-buffer))
        (should (eq kuro--font-remap-cookie 'fake-cookie))))))

(ert-deftest kuro-faces-apply-font-to-buffer-removes-old-cookie ()
  "kuro--apply-font-to-buffer removes the existing cookie before setting a new one."
  (with-temp-buffer
    (setq-local kuro--font-remap-cookie 'old-cookie)
    (let ((removed nil)
          (kuro-font-family "Mono")
          (kuro-font-size nil))
      (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
                ((symbol-function 'face-remap-remove-relative)
                 (lambda (cookie) (setq removed cookie)))
                ((symbol-function 'face-remap-add-relative)
                 (lambda (&rest _) 'new-cookie)))
        (kuro--apply-font-to-buffer (current-buffer))
        (should (eq removed 'old-cookie))
        (should (eq kuro--font-remap-cookie 'new-cookie))))))

(ert-deftest kuro-faces-remap-default-face-noop-in-non-graphical ()
  "kuro--remap-default-face is a no-op when display-graphic-p returns nil."
  (with-temp-buffer
    (setq-local kuro--default-color-remap-cookie nil)
    (cl-letf (((symbol-function 'display-graphic-p) (lambda () nil)))
      (kuro--remap-default-face "#ffffff" "#000000")
      (should (null kuro--default-color-remap-cookie)))))

(ert-deftest kuro-faces-remap-default-face-sets-cookie ()
  "kuro--remap-default-face calls face-remap-add-relative and stores cookie."
  (with-temp-buffer
    (setq-local kuro--default-color-remap-cookie nil)
    (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
              ((symbol-function 'face-remap-add-relative)
               (lambda (&rest _) 'color-cookie)))
      (kuro--remap-default-face "#ffffff" "#000000")
      (should (eq kuro--default-color-remap-cookie 'color-cookie)))))

;;; Group 18: kuro--apply-default-colors

(ert-deftest kuro-faces-apply-default-colors-noop-when-not-initialized ()
  "kuro--apply-default-colors does nothing when kuro--initialized is nil."
  (with-temp-buffer
    (setq-local kuro--initialized nil)
    (let ((remapped nil))
      (cl-letf (((symbol-function 'kuro--remap-default-face)
                 (lambda (&rest _) (setq remapped t))))
        (kuro--apply-default-colors)
        (should-not remapped)))))

(ert-deftest kuro-faces-apply-default-colors-noop-when-colors-nil ()
  "kuro--apply-default-colors does nothing when kuro--get-default-colors returns nil."
  (with-temp-buffer
    (setq-local kuro--initialized t)
    (let ((remapped nil))
      (cl-letf (((symbol-function 'kuro--get-default-colors) (lambda () nil))
                ((symbol-function 'kuro--remap-default-face)
                 (lambda (&rest _) (setq remapped t))))
        (kuro--apply-default-colors)
        (should-not remapped)))))

(ert-deftest kuro-faces-apply-default-colors-calls-remap-when-colors-present ()
  "kuro--apply-default-colors calls kuro--remap-default-face with decoded color strings."
  (with-temp-buffer
    (setq-local kuro--initialized t)
    (let ((fg-arg nil) (bg-arg nil))
      (cl-letf (((symbol-function 'kuro--get-default-colors)
                 (lambda () (list 0 0 0)))
                ((symbol-function 'kuro--decode-ffi-color)
                 (lambda (_) 'fake-color))
                ((symbol-function 'kuro--color-to-emacs)
                 (lambda (_) "#aabbcc"))
                ((symbol-function 'kuro--remap-default-face)
                 (lambda (fg bg) (setq fg-arg fg bg-arg bg))))
        (kuro--apply-default-colors)
        (should (equal fg-arg "#aabbcc"))
        (should (equal bg-arg "#aabbcc"))))))

;;; Group 19: kuro--with-face-remap macro

(ert-deftest kuro-faces-ext-test-with-face-remap-removes-non-nil-cookie ()
  "`kuro--with-face-remap' calls face-remap-remove-relative when cookie is non-nil."
  (let ((cookie 'sentinel)
        removed)
    (cl-letf (((symbol-function 'face-remap-remove-relative)
               (lambda (c) (setq removed c))))
      (kuro--with-face-remap cookie))
    (should (eq removed 'sentinel))))

(ert-deftest kuro-faces-ext-test-with-face-remap-clears-cookie-before-body ()
  "`kuro--with-face-remap' sets cookie var to nil before evaluating body."
  (let ((cookie 'old)
        captured)
    (cl-letf (((symbol-function 'face-remap-remove-relative) #'ignore))
      (kuro--with-face-remap cookie
        (setq captured cookie)))
    (should (null captured))))

(ert-deftest kuro-faces-ext-test-with-face-remap-skips-remove-when-nil ()
  "`kuro--with-face-remap' does not call face-remap-remove-relative when cookie is nil."
  (let ((cookie nil)
        remove-called)
    (cl-letf (((symbol-function 'face-remap-remove-relative)
               (lambda (_) (setq remove-called t))))
      (kuro--with-face-remap cookie))
    (should-not remove-called)))

(ert-deftest kuro-faces-ext-test-with-face-remap-executes-body ()
  "`kuro--with-face-remap' evaluates body forms after removing old cookie."
  (let ((cookie nil)
        ran)
    (kuro--with-face-remap cookie
      (setq ran t))
    (should ran)))

(ert-deftest kuro-faces-ext-test-with-face-remap-empty-body-is-pure-remove ()
  "`kuro--with-face-remap' with no body acts as a pure remove."
  (let ((cookie 'old)
        removed)
    (cl-letf (((symbol-function 'face-remap-remove-relative)
               (lambda (c) (setq removed c))))
      (kuro--with-face-remap cookie))
    (should (eq removed 'old))
    (should (null cookie))))

(provide 'kuro-faces-ext-test)

;;; kuro-faces-ext-test.el ends here
