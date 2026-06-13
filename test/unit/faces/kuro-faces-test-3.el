;;; kuro-faces-test-3.el --- Unit tests for kuro-faces.el (part 3)  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-faces)
(require 'kuro-char-width)
(require 'kuro-overlays)

;;; Group 15: Color variables, named-color table, and face uniqueness

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

(defconst kuro-faces-test--apply-palette-entry-update-table
  '((kuro-faces-apply-palette-entry-updates-named-colors  0  255  0  0  "#ff0000")
    (kuro-faces-apply-palette-entry-idx-15-accepted       15  10 20 30 "#0a141e"))
  "Table: (test-name idx r g b expected-hex) for valid-index named-color updates.")

(defmacro kuro-faces-test--def-apply-palette-entry-update (test-name idx r g b expected-hex)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--apply-palette-entry' idx=%d rgb=(%d,%d,%d) → %s in named-colors."
              idx r g b expected-hex)
     (kuro--rebuild-named-colors)
     (kuro--apply-palette-entry ,idx ,r ,g ,b)
     (let ((name (aref kuro--ansi-color-names ,idx)))
       (should (equal (gethash name kuro--named-colors) ,expected-hex)))))

(kuro-faces-test--def-apply-palette-entry-update
 kuro-faces-apply-palette-entry-updates-named-colors  0  255  0  0  "#ff0000")
(kuro-faces-test--def-apply-palette-entry-update
 kuro-faces-apply-palette-entry-idx-15-accepted       15  10 20 30 "#0a141e")

(ert-deftest kuro-faces-test--all-apply-palette-entry-updates-correct ()
  "Invariant: each valid-index entry in the table stores the expected hex in named-colors."
  (dolist (entry kuro-faces-test--apply-palette-entry-update-table)
    (pcase-let ((`(,_name ,idx ,r ,g ,b ,expected-hex) entry))
      (kuro--rebuild-named-colors)
      (kuro--apply-palette-entry idx r g b)
      (let ((name (aref kuro--ansi-color-names idx)))
        (should (equal (gethash name kuro--named-colors) expected-hex))))))

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

(defconst kuro-faces-test--apply-default-colors-noop-table
  '((kuro-faces-apply-default-colors-noop-when-not-initialized nil)
    (kuro-faces-apply-default-colors-noop-when-colors-nil       t))
  "Table of (test-name initialized) for `kuro--apply-default-colors' no-op paths.")

(defmacro kuro-faces-test--def-apply-default-colors-noop (test-name initialized)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--apply-default-colors' noop when %s."
              (if initialized "get-default-colors returns nil" "not initialized"))
     (with-temp-buffer
       (setq-local kuro--initialized ,initialized)
       (let ((remapped nil))
         (cl-letf (((symbol-function 'kuro--get-default-colors) (lambda () nil))
                   ((symbol-function 'kuro--remap-default-face)
                    (lambda (&rest _) (setq remapped t))))
           (kuro--apply-default-colors)
           (should-not remapped))))))

(kuro-faces-test--def-apply-default-colors-noop kuro-faces-apply-default-colors-noop-when-not-initialized nil)
(kuro-faces-test--def-apply-default-colors-noop kuro-faces-apply-default-colors-noop-when-colors-nil       t)

(ert-deftest kuro-faces-test--all-apply-default-colors-noop-correct ()
  "All entries in `kuro-faces-test--apply-default-colors-noop-table' skip remapping."
  (dolist (entry kuro-faces-test--apply-default-colors-noop-table)
    (pcase-let ((`(,_name ,initialized) entry))
      (with-temp-buffer
        (setq-local kuro--initialized initialized)
        (let ((remapped nil))
          (cl-letf (((symbol-function 'kuro--get-default-colors) (lambda () nil))
                    ((symbol-function 'kuro--remap-default-face)
                     (lambda (&rest _) (setq remapped t))))
            (kuro--apply-default-colors)
            (should-not remapped)))))))

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

;;; Group 20: kuro--get-cached-face-raw--miss — cache insertion and FIFO eviction

(ert-deftest kuro-faces-test--cache-miss-stores-face ()
  "`kuro--get-cached-face-raw--miss' stores the new face in `kuro--face-cache'."
  (let ((kuro--face-cache (make-hash-table :test 'equal)))
    (kuro--get-cached-face-raw--miss kuro--ffi-color-default kuro--ffi-color-default 0 0)
    (should (= (hash-table-count kuro--face-cache) 1))))

(ert-deftest kuro-faces-test--cache-miss-returns-face-plist ()
  "`kuro--get-cached-face-raw--miss' returns a non-nil face plist when given real colors.
With all-default inputs the plist is nil (inherits from default face), so use
a plain 24-bit RGB fg (#x00FF0000 = no tag bits, decodes to (cons 'rgb #xFF0000))."
  (let ((kuro--face-cache (make-hash-table :test 'equal)))
    ;; #x00FF0000: bits 31+30 clear → plain RGB, decoded to (cons 'rgb ...) → non-nil fg
    (let ((face (kuro--get-cached-face-raw--miss #x00FF0000 kuro--ffi-color-default 0 0)))
      (should face))))

(ert-deftest kuro-faces-test--cache-miss-lookup-key-vector-correct ()
  "`kuro--get-cached-face-raw--miss' stores under a key vector matching the inputs."
  (let ((kuro--face-cache (make-hash-table :test 'equal)))
    (kuro--get-cached-face-raw--miss #x00FF0000 #x000000FF #x01 0)
    (should (gethash (vector #x00FF0000 #x000000FF #x01 0) kuro--face-cache))))

(ert-deftest kuro-faces-test--cache-miss-evicts-when-over-limit ()
  "`kuro--get-cached-face-raw--miss' evicts entries when cache exceeds max size."
  (let* ((kuro--face-cache (make-hash-table :test 'equal))
         (kuro--face-cache-max-size 4)
         (kuro--face-cache-evict-fraction 0.5))
    ;; Fill cache just past the limit
    (dotimes (i 5)
      (puthash (vector i 0 0 0) t kuro--face-cache))
    (kuro--get-cached-face-raw--miss kuro--ffi-color-default kuro--ffi-color-default 0 0)
    ;; After eviction, cache should be smaller than 5 + 1 = 6
    (should (< (hash-table-count kuro--face-cache) 6))))

(provide 'kuro-faces-test-3)

;;; kuro-faces-test-3.el ends here
