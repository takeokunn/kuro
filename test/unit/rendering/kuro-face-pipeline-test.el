;;; kuro-face-pipeline-test.el --- Unit tests for face/attribute pipeline  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for the face/attribute encoding pipeline from FFI wire format
;; through to Emacs text properties.
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;;
;; Covered:
;;   Group 1: SGR attribute flags (bold, dim, italic, underline, strikethrough)
;;   Group 2: Color encoding — RGB foreground and background
;;   Group 3: Indexed 256-color foreground and background
;;   Group 4: nil/default cases (no face applied)
;;   Group 5: Multiple attributes combined

;;; Code:

(require 'ert)
(require 'kuro-render-buffer)
(require 'kuro-faces-attrs)
(require 'kuro-faces-color)

;;; Helpers

(defmacro kuro-face-pipeline-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer with face pipeline state initialized."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (inhibit-modification-hooks t)
           (kuro--initialized nil)
           (kuro--scroll-offset 0)
           (kuro--last-rows 24)
           (kuro--col-to-buf-map (make-hash-table :test 'eql))
           (kuro--blink-overlays-by-row (make-hash-table :test 'eql))
           (kuro--current-render-row -1)
           kuro--blink-overlays
           kuro--image-overlays)
       ,@body)))

(defmacro kuro-face-pipeline-test--face-at-0 (text face-ranges)
  "Insert TEXT in a temp buffer, apply FACE-RANGES to the full text, return face at point-min."
  `(kuro-face-pipeline-test--with-buffer
     (insert ,text)
     (kuro--apply-face-ranges ,face-ranges (point-min) (point-max))
     (get-text-property (point-min) 'face)))

(defconst kuro-face-pipeline-test--sgr-attribute-cases
  `((kuro-face-pipeline-bold-flag-produces-weight-bold
     "SGR bold flag produces :weight bold face property."
     ,(vector 0 4 kuro--ffi-color-default kuro--ffi-color-default
              kuro--sgr-flag-bold 0)
     ((:weight . bold)))
    (kuro-face-pipeline-dim-flag-produces-weight-light
     "SGR dim flag produces :weight light face property."
     ,(vector 0 4 kuro--ffi-color-default kuro--ffi-color-default
              kuro--sgr-flag-dim 0)
     ((:weight . light)))
    (kuro-face-pipeline-italic-flag-produces-slant-italic
     "SGR italic flag produces :slant italic face property."
     ,(vector 0 4 kuro--ffi-color-default kuro--ffi-color-default
              kuro--sgr-flag-italic 0)
     ((:slant . italic)))
    (kuro-face-pipeline-underline-flag-produces-underline-t
     "SGR underline flag produces :underline t face property."
     ,(vector 0 4 kuro--ffi-color-default kuro--ffi-color-default
              kuro--sgr-flag-underline 0)
     ((:underline . t)))
    (kuro-face-pipeline-strikethrough-flag-produces-strike-through
     "SGR strikethrough flag produces :strike-through t face property."
     ,(vector 0 4 kuro--ffi-color-default kuro--ffi-color-default
              kuro--sgr-flag-strikethrough 0)
     ((:strike-through . t))))
  "Cases for SGR attribute flag materialization.
Each case is (TEST-NAME DOC FACE-RANGES EXPECTED-PROPERTIES).")

(defconst kuro-face-pipeline-test--rgb-color-cases
  `((kuro-face-pipeline-rgb-fg-encodes-to-foreground-hex
     "RGB fg encoding #xFF0000 produces :foreground \"#ff0000\"."
     ,(vector 0 4 #xFF0000 kuro--ffi-color-default 0 0)
     ((:foreground . "#ff0000")))
    (kuro-face-pipeline-rgb-bg-encodes-to-background-hex
     "RGB bg encoding #xFF0000 produces :background \"#ff0000\"."
     ,(vector 0 4 kuro--ffi-color-default #xFF0000 0 0)
     ((:background . "#ff0000")))
    (kuro-face-pipeline-truecolor-rgb-green-fg
     "TrueColor RGB encoding #x00FF80 produces :foreground \"#00ff80\"."
     ,(vector 0 4 #x00FF80 kuro--ffi-color-default 0 0)
     ((:foreground . "#00ff80"))))
  "Cases for RGB color face property materialization.
Each case is (TEST-NAME DOC FACE-RANGES EXPECTED-PROPERTIES).")

(defconst kuro-face-pipeline-test--indexed-color-cases
  `((kuro-face-pipeline-indexed-256-bg-index21-is-blue
     "256-color indexed bg index 21 produces :background \"#0000ff\"."
     ,(vector 0 4 kuro--ffi-color-default (logior #x40000000 21) 0 0)
     ((:background . "#0000ff")))
    (kuro-face-pipeline-indexed-256-fg-index21
     "256-color indexed fg index 21 produces :foreground \"#0000ff\"."
     ,(vector 0 4 (logior #x40000000 21) kuro--ffi-color-default 0 0)
     ((:foreground . "#0000ff"))))
  "Cases for indexed color face property materialization.
Each case is (TEST-NAME DOC FACE-RANGES EXPECTED-PROPERTIES).")

(defconst kuro-face-pipeline-test--combined-property-cases
  `((kuro-face-pipeline-bold-plus-italic-combo
     "Combined bold+italic flags produce both :weight bold and :slant italic."
     ,(vector 0 4 kuro--ffi-color-default kuro--ffi-color-default
              (logior kuro--sgr-flag-bold kuro--sgr-flag-italic) 0)
     ((:weight . bold)
      (:slant . italic)))
    (kuro-face-pipeline-fg-color-plus-bold
     "RGB fg color combined with bold flag produces both :foreground and :weight bold."
     ,(vector 0 4 #x00FF00 kuro--ffi-color-default kuro--sgr-flag-bold 0)
     ((:foreground . "#00ff00")
      (:weight . bold))))
  "Cases for combined face property materialization.
Each case is (TEST-NAME DOC FACE-RANGES EXPECTED-PROPERTIES).")

(defmacro kuro-face-pipeline-test--def-face-property-case (case)
  "Define one face pipeline property test from CASE."
  (declare (indent 0))
  (let ((name (nth 0 case))
        (doc (nth 1 case))
        (face-ranges (nth 2 case))
        (expected-properties (nth 3 case)))
    `(ert-deftest ,name ()
       ,doc
       (let ((face (kuro-face-pipeline-test--face-at-0 "test" ',face-ranges)))
         ,@(mapcar
            (lambda (expected)
              `(should (equal (plist-get face ,(car expected)) ',(cdr expected))))
            expected-properties)))))

(defmacro kuro-face-pipeline-test--deftest-face-property-cases (cases)
  "Define face pipeline property tests from CASES."
  (let ((resolved-cases (if (symbolp cases) (symbol-value cases) cases)))
    `(progn
       ,@(mapcar (lambda (case)
                   `(kuro-face-pipeline-test--def-face-property-case ,case))
                 resolved-cases))))

(defconst kuro-face-pipeline-test--no-face-cases
  `((kuro-face-pipeline-nil-face-ranges-no-face
     "nil face-ranges leaves no face text property."
     nil)
    (kuro-face-pipeline-default-color-no-fg-no-bg
     "All-default face range (fast-path) leaves no face text property."
     ,(vector 0 4 kuro--ffi-color-default kuro--ffi-color-default 0 0)))
  "Cases where applying face ranges must leave no face property.
Each case is (TEST-NAME DOC FACE-RANGES).")

(defmacro kuro-face-pipeline-test--def-no-face-case (case)
  "Define one face pipeline no-face test from CASE."
  (declare (indent 0))
  (let ((name (nth 0 case))
        (doc (nth 1 case))
        (face-ranges (nth 2 case)))
    `(ert-deftest ,name ()
       ,doc
       (let ((face (kuro-face-pipeline-test--face-at-0 "test" ',face-ranges)))
         (should-not face)))))

(defmacro kuro-face-pipeline-test--deftest-no-face-cases ()
  "Define face pipeline no-face tests from `kuro-face-pipeline-test--no-face-cases'."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-face-pipeline-test--def-no-face-case ,case))
               kuro-face-pipeline-test--no-face-cases)))

;;; Group 1: SGR attribute flags

(kuro-face-pipeline-test--deftest-face-property-cases
 kuro-face-pipeline-test--sgr-attribute-cases)

;;; Group 2: Color encoding — RGB foreground and background

(kuro-face-pipeline-test--deftest-face-property-cases
 kuro-face-pipeline-test--rgb-color-cases)

;;; Group 3: Indexed 256-color

(kuro-face-pipeline-test--deftest-face-property-cases
 kuro-face-pipeline-test--indexed-color-cases)

;;; Group 4: nil/default cases

(kuro-face-pipeline-test--deftest-no-face-cases)

;;; Group 5: Multiple attributes combined

(kuro-face-pipeline-test--deftest-face-property-cases
 kuro-face-pipeline-test--combined-property-cases)

(provide 'kuro-face-pipeline-test)

;;; kuro-face-pipeline-test.el ends here
