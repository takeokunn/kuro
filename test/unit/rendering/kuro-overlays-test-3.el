;;; kuro-overlays-test-3.el --- kuro-overlays-test (part 3)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-overlays-test-support)

;;; Group 17: kuro--render-image-notification — error handling paths

(ert-deftest kuro-overlays-ext-render-image-notification-handles-bad-base64 ()
  "kuro--render-image-notification catches errors from malformed base64 without propagating.
The condition-case in `kuro--render-image-notification' must swallow the error
that `kuro--decode-png-image' signals when base64-decode-string fails."
  (kuro-overlays-test--with-buffer
    (insert "line0\nline1\n")
    (cl-letf (((symbol-function 'kuro--get-image)
               (lambda (_id) "not-valid-base64!!!!")))
      ;; No error must escape — condition-case catches and messages it
      (should-not
       (condition-case err
           (progn (kuro--render-image-notification '(1 0 0 2 1)) nil)
         (error err))))))

(ert-deftest kuro-overlays-ext-render-image-notification-handles-create-image-error ()
  "kuro--render-image-notification catches errors from create-image failing.
When `kuro--decode-png-image' signals because `create-image' errors, the
outer condition-case must absorb it and leave no overlay."
  (kuro-overlays-test--with-buffer
    (insert "line0\nline1\n")
    (let* ((fake-b64 (base64-encode-string "PNG")))
      (cl-letf (((symbol-function 'kuro--get-image) (lambda (_id) fake-b64))
                ((symbol-function 'create-image)
                 (lambda (_data _type _inline) (error "create-image: unsupported format"))))
        (should-not
         (condition-case err
             (progn (kuro--render-image-notification '(1 0 0 2 1)) nil)
           (error err)))
        ;; No overlay should have been placed
        (should (null kuro--image-overlays))))))

(ert-deftest kuro-overlays-ext-render-image-notification-noop-when-no-image ()
  "kuro--render-image-notification is a no-op when kuro--get-image returns nil.
The `when (and b64 ...)' guard must short-circuit and leave the overlay list empty."
  (kuro-overlays-test--with-buffer
    (insert "line0\nline1\n")
    (cl-letf (((symbol-function 'kuro--get-image) (lambda (_id) nil)))
      (kuro--render-image-notification '(1 0 0 2 1))
      (should (null kuro--image-overlays)))))

;;; Group 18: kuro--register-blink-overlay macro + kuro--decode-png-image

(defconst kuro-overlays-test--register-blink-overlay-table
  '((kuro-overlays-register-blink-overlay-slow slow 0 kuro--blink-overlays-slow kuro--blink-overlays-fast)
    (kuro-overlays-register-blink-overlay-fast fast 1 kuro--blink-overlays-fast kuro--blink-overlays-slow))
  "Table of (test-name type row own-list-sym other-list-sym).")

(defmacro kuro-overlays-test--def-register-blink-overlay
    (test-name type row own-list other-list)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--register-blink-overlay' type=%s row=%d: in own list, absent from other." type row)
     (kuro-overlays-test--with-buffer
       (insert "hello\n")
       (let ((ov (make-overlay 1 3))
             (kuro--blink-overlays nil)
             (kuro--blink-overlays-slow nil)
             (kuro--blink-overlays-fast nil)
             (kuro--blink-overlays-by-row (make-hash-table :test 'eql)))
         (kuro--register-blink-overlay ov ',type ,row)
         (should     (memq ov kuro--blink-overlays))
         (should     (memq ov ,own-list))
         (should-not (memq ov ,other-list))
         (should     (memq ov (gethash ,row kuro--blink-overlays-by-row)))))))

(kuro-overlays-test--def-register-blink-overlay
 kuro-overlays-register-blink-overlay-slow slow 0 kuro--blink-overlays-slow kuro--blink-overlays-fast)
(kuro-overlays-test--def-register-blink-overlay
 kuro-overlays-register-blink-overlay-fast fast 1 kuro--blink-overlays-fast kuro--blink-overlays-slow)

(kuro-overlays-test--deftest-table-cases
    kuro-overlays-test--register-blink-overlay-both-types
    "Invariant: register-blink-overlay adds to own list and excludes from other for both types."
    kuro-overlays-test--register-blink-overlay-table
    (`(,_name ,type ,row ,own-sym ,other-sym)
     (kuro-overlays-test--with-buffer
       (insert "hello\n")
       (let ((ov (make-overlay 1 3))
             (kuro--blink-overlays nil)
             (kuro--blink-overlays-slow nil)
             (kuro--blink-overlays-fast nil)
             (kuro--blink-overlays-by-row (make-hash-table :test 'eql)))
         (kuro--register-blink-overlay ov type row)
         (should     (memq ov kuro--blink-overlays))
         (should     (memq ov (symbol-value own-sym)))
         (should-not (memq ov (symbol-value other-sym)))
         (should     (memq ov (gethash row kuro--blink-overlays-by-row)))))))

(ert-deftest kuro-overlays-register-blink-overlay-appends-to-row-hash ()
  "`kuro--register-blink-overlay' prepends OV to existing row hash entries."
  (kuro-overlays-test--with-buffer
    (insert "hello\n")
    (let ((ov1 (make-overlay 1 3))
          (ov2 (make-overlay 1 3))
          (kuro--blink-overlays nil)
          (kuro--blink-overlays-slow nil)
          (kuro--blink-overlays-fast nil)
          (kuro--blink-overlays-by-row (make-hash-table :test 'eql)))
      (kuro--register-blink-overlay ov1 'slow 0)
      (kuro--register-blink-overlay ov2 'slow 0)
      (let ((row-list (gethash 0 kuro--blink-overlays-by-row)))
        (should (memq ov1 row-list))
        (should (memq ov2 row-list))))))

(ert-deftest kuro-overlays-reset-blink-overlays-rebuilds-typed-lists ()
  "`kuro--reset-blink-overlays' preserves survivor order while rebuilding typed lists."
  (kuro-overlays-test--with-buffer
    (insert "hello\n")
    (let* ((ov1 (make-overlay 1 2))
           (ov2 (make-overlay 2 3))
           (ov3 (make-overlay 3 4))
           (remaining (list ov1 ov2 ov3))
           (kuro--blink-overlays (list 'old))
           (kuro--blink-overlays-slow (list 'old-slow))
           (kuro--blink-overlays-fast (list 'old-fast)))
      (overlay-put ov1 'kuro-blink-type 'slow)
      (overlay-put ov2 'kuro-blink-type 'fast)
      (overlay-put ov3 'kuro-blink-type 'slow)
      (kuro--reset-blink-overlays remaining)
      (should (equal (mapcar (lambda (ov) (overlay-get ov 'kuro-blink-type))
                             kuro--blink-overlays)
                     '(slow fast slow)))
      (should (equal kuro--blink-overlays-slow (list ov1 ov3)))
      (should (equal kuro--blink-overlays-fast (list ov2))))))

(ert-deftest kuro-overlays-decode-png-image-calls-create-image-with-decoded-data ()
  "`kuro--decode-png-image' base64-decodes the input and passes it to `create-image'."
  ;; Encode a known binary sequence as base64 to verify round-trip.
  (let* ((raw "FAKE-PNG-BYTES")
         (b64 (base64-encode-string (encode-coding-string raw 'binary)))
         (captured-data nil)
         (captured-type nil))
    (cl-letf (((symbol-function 'create-image)
               (lambda (data type _inline)
                 (setq captured-data data captured-type type)
                 'mock-image)))
      (let ((result (kuro--decode-png-image b64)))
        (should (eq result 'mock-image))
        (should (eq captured-type 'png))
        (should (stringp captured-data))))))

(ert-deftest kuro-overlays-decode-png-image-signals-on-invalid-base64 ()
  "`kuro--decode-png-image' signals an error when base64 decoding fails."
  (should-error (kuro--decode-png-image "not-valid-base64!!!")))

(defconst kuro-overlays-test--place-image-overlay-table
  '((kuro-overlays-place-image-overlay-creates-overlay-at-position 0 0 1 1 2 "line0\nline1\n")
    (kuro-overlays-place-image-overlay-noop-when-row-beyond-buffer 99 0 1 nil nil "one-line\n")
    (kuro-overlays-place-image-overlay-with-col-offset               0 3 1 4 5 "hello\n")
    (kuro-overlays-place-image-overlay-wide-cell-width               0 0 3 1 4 "hello\n"))
  "Table of (test-name row col cell-width expected-start expected-end buffer-text).")

(kuro-overlays-test--deftest-table-cases
    kuro-overlays-place-image-overlay-all-cases
    "All `kuro--place-image-overlay' cases keep placement and no-op behavior consistent."
    kuro-overlays-test--place-image-overlay-table
    (`(,_name ,row ,col ,cell-width ,expected-start ,expected-end ,buffer-text)
     (kuro-overlays-test--with-buffer
       (insert buffer-text)
       (kuro--place-image-overlay 'fake-img row col cell-width)
       (if expected-start
           (progn
             (should (= (length kuro--image-overlays) 1))
             (should kuro--has-images)
             (let ((ov (car kuro--image-overlays)))
               (should (= (overlay-start ov) expected-start))
               (should (= (overlay-end ov) expected-end))
               (should (overlay-get ov 'kuro-image))
               (should (eq (overlay-get ov 'display) 'fake-img))
               (should (overlay-get ov 'evaporate))))
         (should (null kuro--image-overlays))
         (should-not kuro--has-images)))))

;;; Group 19: kuro--ffi-face-default-p — pure predicate coverage

(defmacro kuro-overlays-test--def-ffi-face-default (test-name fg bg flags ul expectedp)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--ffi-face-default-p' (fg=%s bg=%s flags=%s ul=%s) => %s." fg bg flags ul expectedp)
     ,(if expectedp
          `(should     (kuro--ffi-face-default-p ,fg ,bg ,flags ,ul))
        `(should-not (kuro--ffi-face-default-p ,fg ,bg ,flags ,ul)))))

(kuro-overlays-test--def-ffi-face-default kuro-overlays-ffi-face-default-p-all-defaults              kuro--ffi-color-default kuro--ffi-color-default  0          0           t)
(kuro-overlays-test--def-ffi-face-default kuro-overlays-ffi-face-default-p-non-default-fg             #x00FF0000              kuro--ffi-color-default  0          0           nil)
(kuro-overlays-test--def-ffi-face-default kuro-overlays-ffi-face-default-p-non-default-bg             kuro--ffi-color-default #x000000FF               0          0           nil)
(kuro-overlays-test--def-ffi-face-default kuro-overlays-ffi-face-default-p-non-zero-flags             kuro--ffi-color-default kuro--ffi-color-default  1          0           nil)
(kuro-overlays-test--def-ffi-face-default kuro-overlays-ffi-face-default-p-non-zero-ul-color          kuro--ffi-color-default kuro--ffi-color-default  0          #x00FF0000  nil)
(kuro-overlays-test--def-ffi-face-default kuro-overlays-ffi-face-default-p-flags-and-ul-both-nonzero  kuro--ffi-color-default kuro--ffi-color-default  3          5           nil)

;;; Group 20: kuro--ffi-face-has-visual-effects-p — blink/hidden flags

(defmacro kuro-overlays-test--def-has-visual-effects (test-name flags expectedp)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--ffi-face-has-visual-effects-p' flags=%s => %s." flags expectedp)
     ,(if expectedp
          `(should     (kuro--ffi-face-has-visual-effects-p ,flags))
        `(should-not (kuro--ffi-face-has-visual-effects-p ,flags)))))

(kuro-overlays-test--def-has-visual-effects kuro-overlays-ffi-face-has-visual-effects-p-zero-flags         0                                      nil)
(kuro-overlays-test--def-has-visual-effects kuro-overlays-ffi-face-has-visual-effects-p-blink-slow         kuro--sgr-flag-blink-slow               t)
(kuro-overlays-test--def-has-visual-effects kuro-overlays-ffi-face-has-visual-effects-p-blink-fast         kuro--sgr-flag-blink-fast               t)
(kuro-overlays-test--def-has-visual-effects kuro-overlays-ffi-face-has-visual-effects-p-hidden             kuro--sgr-flag-hidden                   t)
(kuro-overlays-test--def-has-visual-effects kuro-overlays-ffi-face-has-visual-effects-p-bold-only-is-false #x01                                    nil)
(kuro-overlays-test--def-has-visual-effects kuro-overlays-ffi-face-has-visual-effects-p-combined           (logior #x01 kuro--sgr-flag-blink-slow) t)

;;; Group 21: kuro--apply-ffi-face-effects — blink and hidden text-property dispatch

(defconst kuro-overlays-test--ffi-face-invisible-table
  '((kuro-overlays-ffi-face-effects-hidden-flag-adds-invisible  kuro--sgr-flag-hidden t)
    (kuro-overlays-ffi-face-effects-no-hidden-no-invisible      0                     nil))
  "Table of (test-name flags expectedp) for invisible text property from ffi-face-effects.")

(defmacro kuro-overlays-test--def-ffi-face-invisible (test-name flags expectedp)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--apply-ffi-face-effects' invisible %s when flags=%s." expectedp flags)
     (kuro-overlays-test--with-buffer
       (insert "hello")
       (kuro--apply-ffi-face-effects (point-min) (point-max) ,flags)
       ,(if expectedp
            `(should (get-text-property (point-min) 'invisible))
          `(should-not (get-text-property (point-min) 'invisible))))))

(kuro-overlays-test--def-ffi-face-invisible kuro-overlays-ffi-face-effects-hidden-flag-adds-invisible  kuro--sgr-flag-hidden t)
(kuro-overlays-test--def-ffi-face-invisible kuro-overlays-ffi-face-effects-no-hidden-no-invisible      0                     nil)

(kuro-overlays-test--deftest-table-cases
    kuro-overlays-ffi-face-invisible-all-table-entries-correct
    "All entries in `kuro-overlays-test--ffi-face-invisible-table' match actual behavior."
    kuro-overlays-test--ffi-face-invisible-table
    (`(,_name ,flags ,expectedp)
     (kuro-overlays-test--with-buffer
       (insert "hello")
       (kuro--apply-ffi-face-effects (point-min) (point-max)
                                     (if (symbolp flags) (symbol-value flags) flags))
       (if expectedp
           (should (get-text-property (point-min) 'invisible))
         (should-not (get-text-property (point-min) 'invisible))))))

(defconst kuro-overlays-test--ffi-face-blink-table
  '((kuro-overlays-ffi-face-effects-blink-fast-creates-overlay kuro--sgr-flag-blink-fast)
    (kuro-overlays-ffi-face-effects-blink-slow-creates-overlay kuro--sgr-flag-blink-slow))
  "Table of (test-name flag) for blink overlay creation from ffi-face-effects.")

(defmacro kuro-overlays-test--def-ffi-face-blink (test-name flag)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--apply-ffi-face-effects' creates blink overlay for %s." flag)
     (kuro-overlays-test--with-buffer
       (insert "xx")
       (kuro--apply-ffi-face-effects (point-min) (point-max) ,flag)
       (should kuro--blink-overlays))))

(kuro-overlays-test--def-ffi-face-blink kuro-overlays-ffi-face-effects-blink-fast-creates-overlay kuro--sgr-flag-blink-fast)
(kuro-overlays-test--def-ffi-face-blink kuro-overlays-ffi-face-effects-blink-slow-creates-overlay kuro--sgr-flag-blink-slow)

(kuro-overlays-test--deftest-table-cases
    kuro-overlays-ffi-face-blink-all-table-entries-correct
    "All entries in `kuro-overlays-test--ffi-face-blink-table' create blink overlays."
    kuro-overlays-test--ffi-face-blink-table
    (`(,_name ,flag)
     (kuro-overlays-test--with-buffer
       (insert "xx")
       (kuro--apply-ffi-face-effects (point-min) (point-max) (symbol-value flag))
       (should kuro--blink-overlays))))

(ert-deftest kuro-overlays-sgr-visual-flags-mask-is-nonzero ()
  "`kuro--sgr-visual-flags-mask' is a non-zero integer covering blink+hidden bits."
  (should (and (integerp kuro--sgr-visual-flags-mask)
               (/= 0 kuro--sgr-visual-flags-mask))))

(ert-deftest kuro-overlays-blink-frames-cached-are-positive-integers ()
  "`kuro--blink-fast-frames-cached' and `kuro--blink-slow-frames-cached' are positive integers."
  (should (and (integerp kuro--blink-fast-frames-cached) (> kuro--blink-fast-frames-cached 0)))
  (should (and (integerp kuro--blink-slow-frames-cached) (> kuro--blink-slow-frames-cached 0))))

(provide 'kuro-overlays-test-3)

;;; kuro-overlays-test-3.el ends here
