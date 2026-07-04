;;; kuro-text-size-test.el --- Unit tests for kuro-text-size.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;;; Commentary:

;; ERT tests for kuro-text-size.el (Kitty OSC 66 text-sizing overlays).
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;;
;; Groups:
;;   Group 1: kuro--text-size-permille-to-height — permille → :height float
;;   Group 2: kuro--clear-text-size-overlays — cleanup
;;   Group 3: kuro--apply-text-size-ranges — overlay creation from polled data
;;   Group 4: edge cases — empty / out-of-range / missing-row ranges ignored
;;   Group 5: no regression — text-size overlays compose with face/hyperlink

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Stub FFI symbols so kuro-text-size loads without the Rust module.
(dolist (sym '(kuro-core-init
               kuro-core-send-key
               kuro-core-poll-updates
               kuro-core-poll-updates-with-faces
               kuro-core-resize
               kuro-core-shutdown
               kuro-core-get-cursor
               kuro-core-get-cursor-visible
               kuro-core-get-cursor-shape
               kuro-core-is-process-alive
               kuro-core-poll-hyperlink-ranges
               kuro-core-poll-text-size-ranges))
  (unless (fboundp sym)
    (fset sym (lambda (&rest _) nil))))

(unless (fboundp 'module-load)
  (fset 'module-load (lambda (_path) nil)))

(let* ((this-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory)))
       (el-dir (expand-file-name "../../emacs-lisp" this-dir)))
  (add-to-list 'load-path el-dir t))

(require 'kuro-text-size)

;;; Helpers

(defmacro kuro-text-size-test--with-buffer (&rest body)
  "Run BODY in a temp buffer with text-size overlay state initialized."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (kuro--text-size-overlays nil))
       ,@body)))

;;; Group 1: kuro--text-size-permille-to-height

(ert-deftest test-kuro-text-size-permille-scale-2-is-2.0 ()
  "INTENT: SCALED-PERMILLE 2000 (scale s=2) maps to :height float 2.0."
  (should (equal (kuro--text-size-permille-to-height 2000) 2.0)))

(ert-deftest test-kuro-text-size-permille-fractional-half ()
  "INTENT: SCALED-PERMILLE 500 (n=1/d=2 half-size) maps to :height 0.5."
  (should (equal (kuro--text-size-permille-to-height 500) 0.5)))

(ert-deftest test-kuro-text-size-permille-fractional-three-halves ()
  "INTENT: SCALED-PERMILLE 1500 (n=3/d=2) maps to :height 1.5."
  (should (equal (kuro--text-size-permille-to-height 1500) 1.5)))

(ert-deftest test-kuro-text-size-permille-normal-1000-is-nil ()
  "INTENT: SCALED-PERMILLE 1000 is the normal/unscaled size and yields nil."
  (should (null (kuro--text-size-permille-to-height 1000))))

(ert-deftest test-kuro-text-size-permille-zero-is-nil ()
  "INTENT: a degenerate zero permille yields nil (no scaling)."
  (should (null (kuro--text-size-permille-to-height 0))))

(ert-deftest test-kuro-text-size-permille-over-range-is-nil ()
  "INTENT: a permille above the 7x protocol ceiling (8000) is rejected as nil."
  (should (null (kuro--text-size-permille-to-height 8000))))

(ert-deftest test-kuro-text-size-permille-non-integer-is-nil ()
  "INTENT: a non-integer permille is rejected as nil."
  (should (null (kuro--text-size-permille-to-height 2.0))))

(ert-deftest test-kuro-text-size-permille-max-7000-is-7.0 ()
  "INTENT: the protocol ceiling 7000 (scale s=7) is accepted and maps to 7.0."
  (should (equal (kuro--text-size-permille-to-height 7000) 7.0)))

;;; Group 2: kuro--clear-text-size-overlays

(ert-deftest test-kuro-text-size-clear-removes-all-overlays ()
  "INTENT: clear removes every text-size overlay and empties the list."
  (kuro-text-size-test--with-buffer
    (insert "some text here\n")
    (let ((ov1 (make-overlay 1 5))
          (ov2 (make-overlay 6 10)))
      (push ov1 kuro--text-size-overlays)
      (push ov2 kuro--text-size-overlays)
      (should (= (length kuro--text-size-overlays) 2))
      (kuro--clear-text-size-overlays)
      (should (null kuro--text-size-overlays)))))

(ert-deftest test-kuro-text-size-clear-handles-empty-list ()
  "INTENT: clear is a no-op (no error) when there are no overlays."
  (kuro-text-size-test--with-buffer
    (should (null kuro--text-size-overlays))
    (kuro--clear-text-size-overlays)
    (should (null kuro--text-size-overlays))))

;;; Group 3: kuro--apply-text-size-ranges

(ert-deftest test-kuro-text-size-apply-scale-2-sets-height-2.0 ()
  "INTENT: a scale-2 range (permille 2000) applies :height 2.0 over its columns."
  (kuro-text-size-test--with-buffer
    (insert "Double size row\n")
    (cl-letf (((symbol-function 'kuro--poll-text-size-ranges)
               (lambda () '((0 0 6 2000))))
              ((symbol-function 'kuro--row-position)
               (lambda (_row) 1)))
      (kuro--apply-text-size-ranges)
      (should (= (length kuro--text-size-overlays) 1))
      (let ((ov (car kuro--text-size-overlays)))
        (should (equal (overlay-get ov 'face) '(:height 2.0)))
        (should (equal (overlay-get ov 'kuro-text-size-height) 2.0))
        ;; columns 0..6 → buffer positions 1..7
        (should (= (overlay-start ov) 1))
        (should (= (overlay-end ov) 7))))))

(ert-deftest test-kuro-text-size-apply-fractional-half-sets-height-0.5 ()
  "INTENT: a fractional half-size range (permille 500) applies :height 0.5."
  (kuro-text-size-test--with-buffer
    (insert "Ha\n")
    (cl-letf (((symbol-function 'kuro--poll-text-size-ranges)
               (lambda () '((0 0 2 500))))
              ((symbol-function 'kuro--row-position)
               (lambda (_row) 1)))
      (kuro--apply-text-size-ranges)
      (should (= (length kuro--text-size-overlays) 1))
      (should (equal (overlay-get (car kuro--text-size-overlays) 'face)
                     '(:height 0.5))))))

(ert-deftest test-kuro-text-size-apply-multiple-ranges-on-row ()
  "INTENT: multiple sized ranges on one row each get their own overlay/height."
  (kuro-text-size-test--with-buffer
    (insert "abcdefghij\n")
    (cl-letf (((symbol-function 'kuro--poll-text-size-ranges)
               (lambda () '((0 0 3 2000) (0 5 8 1500))))
              ((symbol-function 'kuro--row-position)
               (lambda (_row) 1)))
      (kuro--apply-text-size-ranges)
      (should (= (length kuro--text-size-overlays) 2))
      (let ((heights (sort (mapcar (lambda (ov)
                                     (overlay-get ov 'kuro-text-size-height))
                                   kuro--text-size-overlays)
                           #'<)))
        (should (equal heights '(1.5 2.0)))))))

(ert-deftest test-kuro-text-size-apply-clears-old-before-creating ()
  "INTENT: applying clears any prior text-size overlays before creating new ones."
  (kuro-text-size-test--with-buffer
    (insert "Double size row\n")
    (let ((old-ov (make-overlay 1 3)))
      (push old-ov kuro--text-size-overlays))
    (cl-letf (((symbol-function 'kuro--poll-text-size-ranges)
               (lambda () '((0 0 6 2000))))
              ((symbol-function 'kuro--row-position)
               (lambda (_row) 1)))
      (kuro--apply-text-size-ranges)
      (should (= (length kuro--text-size-overlays) 1))
      (should (equal (overlay-get (car kuro--text-size-overlays)
                                  'kuro-text-size-height)
                     2.0)))))

(ert-deftest test-kuro-text-size-apply-clears-stale-when-poll-nil ()
  "INTENT: a nil poll still clears stale overlays from a previous frame."
  (kuro-text-size-test--with-buffer
    (insert "row\n")
    (let ((old-ov (make-overlay 1 3)))
      (push old-ov kuro--text-size-overlays))
    (should (= (length kuro--text-size-overlays) 1))
    (cl-letf (((symbol-function 'kuro--poll-text-size-ranges)
               (lambda () nil)))
      (kuro--apply-text-size-ranges)
      (should (null kuro--text-size-overlays)))))

(ert-deftest test-kuro-text-size-apply-nil-poll-no-overlays-noop ()
  "INTENT: nil poll with no existing overlays creates nothing and does not error."
  (kuro-text-size-test--with-buffer
    (insert "row\n")
    (cl-letf (((symbol-function 'kuro--poll-text-size-ranges)
               (lambda () nil)))
      (kuro--apply-text-size-ranges)
      (should (null kuro--text-size-overlays)))))

;;; Group 4: edge cases — invalid ranges ignored

(ert-deftest test-kuro-text-size-apply-ignores-empty-range ()
  "INTENT: an empty range (START == END) creates no overlay."
  (kuro-text-size-test--with-buffer
    (insert "row text\n")
    (cl-letf (((symbol-function 'kuro--poll-text-size-ranges)
               (lambda () '((0 3 3 2000))))
              ((symbol-function 'kuro--row-position)
               (lambda (_row) 1)))
      (kuro--apply-text-size-ranges)
      (should (null kuro--text-size-overlays)))))

(ert-deftest test-kuro-text-size-apply-ignores-inverted-range ()
  "INTENT: an inverted range (START > END) creates no overlay."
  (kuro-text-size-test--with-buffer
    (insert "row text\n")
    (cl-letf (((symbol-function 'kuro--poll-text-size-ranges)
               (lambda () '((0 6 2 2000))))
              ((symbol-function 'kuro--row-position)
               (lambda (_row) 1)))
      (kuro--apply-text-size-ranges)
      (should (null kuro--text-size-overlays)))))

(ert-deftest test-kuro-text-size-apply-ignores-over-range-permille ()
  "INTENT: a range whose permille exceeds the 7x ceiling is skipped."
  (kuro-text-size-test--with-buffer
    (insert "row text\n")
    (cl-letf (((symbol-function 'kuro--poll-text-size-ranges)
               (lambda () '((0 0 5 9000))))
              ((symbol-function 'kuro--row-position)
               (lambda (_row) 1)))
      (kuro--apply-text-size-ranges)
      (should (null kuro--text-size-overlays)))))

(ert-deftest test-kuro-text-size-apply-ignores-normal-size-permille ()
  "INTENT: a range at normal size (permille 1000) carries no scaling and is skipped."
  (kuro-text-size-test--with-buffer
    (insert "row text\n")
    (cl-letf (((symbol-function 'kuro--poll-text-size-ranges)
               (lambda () '((0 0 5 1000))))
              ((symbol-function 'kuro--row-position)
               (lambda (_row) 1)))
      (kuro--apply-text-size-ranges)
      (should (null kuro--text-size-overlays)))))

(ert-deftest test-kuro-text-size-apply-skips-missing-row ()
  "INTENT: a range whose row resolves to nil position creates no overlay,
but a valid sibling range on the same poll is still applied."
  (kuro-text-size-test--with-buffer
    (insert "row text\n")
    (cl-letf (((symbol-function 'kuro--poll-text-size-ranges)
               (lambda () '((99 0 3 2000) (0 0 3 2000))))
              ((symbol-function 'kuro--row-position)
               (lambda (row) (when (= row 0) 1))))
      (kuro--apply-text-size-ranges)
      (should (= (length kuro--text-size-overlays) 1))
      (should (= (overlay-start (car kuro--text-size-overlays)) 1)))))

(ert-deftest test-kuro-text-size-apply-mixed-valid-and-invalid ()
  "INTENT: in a batch of mixed ranges only the valid scaled ones create overlays."
  (kuro-text-size-test--with-buffer
    (insert "0123456789\n")
    (cl-letf (((symbol-function 'kuro--poll-text-size-ranges)
               (lambda () '((0 0 2 2000)    ; valid 2x
                            (0 3 3 2000)    ; empty → skip
                            (0 4 6 1000)    ; normal → skip
                            (0 7 9 500))))  ; valid 0.5x
              ((symbol-function 'kuro--row-position)
               (lambda (_row) 1)))
      (kuro--apply-text-size-ranges)
      (should (= (length kuro--text-size-overlays) 2)))))

;;; Group 5: no regression — composition with other faces

(ert-deftest test-kuro-text-size-overlay-face-is-anonymous-height-only ()
  "INTENT: the overlay face is an anonymous (:height H) plist so it merges on
top of underlying SGR/face text-properties rather than replacing them —
guards against regressing existing face/hyperlink rendering."
  (kuro-text-size-test--with-buffer
    (insert "styled\n")
    ;; Pre-apply an underlying face text-property (as kuro--apply-face-ranges would).
    (put-text-property 1 7 'face '(:foreground "red"))
    (cl-letf (((symbol-function 'kuro--poll-text-size-ranges)
               (lambda () '((0 0 6 2000))))
              ((symbol-function 'kuro--row-position)
               (lambda (_row) 1)))
      (kuro--apply-text-size-ranges)
      (let ((ov (car kuro--text-size-overlays)))
        ;; Overlay face is the height plist (no :foreground), so the underlying
        ;; text-property color is untouched and composes via overlay priority.
        (should (equal (overlay-get ov 'face) '(:height 2.0)))
        (should (null (plist-get (overlay-get ov 'face) :foreground)))
        ;; The underlying text-property face survives unchanged.
        (should (equal (get-text-property 1 'face) '(:foreground "red")))))))

(provide 'kuro-text-size-test)

;;; kuro-text-size-test.el ends here
