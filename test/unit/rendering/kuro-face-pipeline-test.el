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

;;; Group 1: SGR attribute flags

(ert-deftest kuro-face-pipeline-bold-flag-produces-weight-bold ()
  "SGR bold flag produces :weight bold face property."
  (let* ((face-ranges (vector 0 4 kuro--ffi-color-default kuro--ffi-color-default
                              kuro--sgr-flag-bold 0))
         (face (kuro-face-pipeline-test--face-at-0 "test" face-ranges)))
    (should (eq (plist-get face :weight) 'bold))))

(ert-deftest kuro-face-pipeline-dim-flag-produces-weight-light ()
  "SGR dim flag produces :weight light face property."
  (let* ((face-ranges (vector 0 4 kuro--ffi-color-default kuro--ffi-color-default
                              kuro--sgr-flag-dim 0))
         (face (kuro-face-pipeline-test--face-at-0 "test" face-ranges)))
    (should (eq (plist-get face :weight) 'light))))

(ert-deftest kuro-face-pipeline-italic-flag-produces-slant-italic ()
  "SGR italic flag produces :slant italic face property."
  (let* ((face-ranges (vector 0 4 kuro--ffi-color-default kuro--ffi-color-default
                              kuro--sgr-flag-italic 0))
         (face (kuro-face-pipeline-test--face-at-0 "test" face-ranges)))
    (should (eq (plist-get face :slant) 'italic))))

(ert-deftest kuro-face-pipeline-underline-flag-produces-underline-t ()
  "SGR underline flag produces :underline t face property."
  (let* ((face-ranges (vector 0 4 kuro--ffi-color-default kuro--ffi-color-default
                              kuro--sgr-flag-underline 0))
         (face (kuro-face-pipeline-test--face-at-0 "test" face-ranges)))
    (should (plist-get face :underline))))

(ert-deftest kuro-face-pipeline-strikethrough-flag-produces-strike-through ()
  "SGR strikethrough flag produces :strike-through t face property."
  (let* ((face-ranges (vector 0 4 kuro--ffi-color-default kuro--ffi-color-default
                              kuro--sgr-flag-strikethrough 0))
         (face (kuro-face-pipeline-test--face-at-0 "test" face-ranges)))
    (should (plist-get face :strike-through))))

;;; Group 2: Color encoding — RGB foreground and background

(ert-deftest kuro-face-pipeline-rgb-fg-encodes-to-foreground-hex ()
  "RGB fg encoding #xFF0000 produces :foreground \"#ff0000\"."
  (let* ((face-ranges (vector 0 4 #xFF0000 kuro--ffi-color-default 0 0))
         (face (kuro-face-pipeline-test--face-at-0 "test" face-ranges)))
    (should (equal (plist-get face :foreground) "#ff0000"))))

(ert-deftest kuro-face-pipeline-rgb-bg-encodes-to-background-hex ()
  "RGB bg encoding #xFF0000 produces :background \"#ff0000\"."
  (let* ((face-ranges (vector 0 4 kuro--ffi-color-default #xFF0000 0 0))
         (face (kuro-face-pipeline-test--face-at-0 "test" face-ranges)))
    (should (equal (plist-get face :background) "#ff0000"))))

(ert-deftest kuro-face-pipeline-truecolor-rgb-green-fg ()
  "TrueColor RGB encoding #x00FF80 produces :foreground \"#00ff80\"."
  (let* ((face-ranges (vector 0 4 #x00FF80 kuro--ffi-color-default 0 0))
         (face (kuro-face-pipeline-test--face-at-0 "test" face-ranges)))
    (should (equal (plist-get face :foreground) "#00ff80"))))

;;; Group 3: Indexed 256-color

(ert-deftest kuro-face-pipeline-indexed-256-bg-index21-is-blue ()
  "256-color indexed bg index 21 produces :background \"#0000ff\".
Index 21 in 6x6x6 cube: n=21-16=5, r=0, g=0, b=5*51=255 => #0000ff."
  (let* ((face-ranges (vector 0 4 kuro--ffi-color-default
                              (logior #x40000000 21) 0 0))
         (face (kuro-face-pipeline-test--face-at-0 "test" face-ranges)))
    (should (equal (plist-get face :background) "#0000ff"))))

(ert-deftest kuro-face-pipeline-indexed-256-fg-index21 ()
  "256-color indexed fg index 21 produces :foreground \"#0000ff\"."
  (let* ((face-ranges (vector 0 4 (logior #x40000000 21)
                              kuro--ffi-color-default 0 0))
         (face (kuro-face-pipeline-test--face-at-0 "test" face-ranges)))
    (should (equal (plist-get face :foreground) "#0000ff"))))

;;; Group 4: nil/default cases

(ert-deftest kuro-face-pipeline-nil-face-ranges-no-face ()
  "nil face-ranges leaves no face text property."
  (let ((face (kuro-face-pipeline-test--face-at-0 "test" nil)))
    (should-not face)))

(ert-deftest kuro-face-pipeline-default-color-no-fg-no-bg ()
  "All-default face range (fast-path) leaves no face text property."
  (let* ((face-ranges (vector 0 4 kuro--ffi-color-default kuro--ffi-color-default 0 0))
         (face (kuro-face-pipeline-test--face-at-0 "test" face-ranges)))
    (should-not face)))

;;; Group 5: Multiple attributes combined

(ert-deftest kuro-face-pipeline-bold-plus-italic-combo ()
  "Combined bold+italic flags produce both :weight bold and :slant italic."
  (let* ((face-ranges (vector 0 4 kuro--ffi-color-default kuro--ffi-color-default
                              (logior kuro--sgr-flag-bold kuro--sgr-flag-italic) 0))
         (face (kuro-face-pipeline-test--face-at-0 "test" face-ranges)))
    (should (eq (plist-get face :weight) 'bold))
    (should (eq (plist-get face :slant) 'italic))))

(ert-deftest kuro-face-pipeline-fg-color-plus-bold ()
  "RGB fg color combined with bold flag produces both :foreground and :weight bold."
  (let* ((face-ranges (vector 0 4 #x00FF00 kuro--ffi-color-default
                              kuro--sgr-flag-bold 0))
         (face (kuro-face-pipeline-test--face-at-0 "test" face-ranges)))
    (should (equal (plist-get face :foreground) "#00ff00"))
    (should (eq (plist-get face :weight) 'bold))))

(provide 'kuro-face-pipeline-test)

;;; kuro-face-pipeline-test.el ends here
