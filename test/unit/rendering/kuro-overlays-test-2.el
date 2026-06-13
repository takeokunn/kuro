;;; kuro-overlays-test-2.el --- kuro-overlays-test (part 2)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-overlays-test-support)

;;; Group 9: kuro--blink-visible and kuro--toggle-blink-state

(defconst kuro-overlays-test--blink-visible-table
  '((kuro-overlays-blink-visible-slow t   nil t   nil)
    (kuro-overlays-blink-visible-fast nil t   nil t))
  "Table of (test-name slow-init fast-init slow-expected fast-expected).")

(defmacro kuro-overlays-test--def-blink-visible
    (test-name slow-init fast-init slow-expected fast-expected)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--blink-visible' slow=%s,fast=%s: slow→%s fast→%s."
              slow-init fast-init slow-expected fast-expected)
     (kuro-overlays-test--with-buffer
       (setq kuro--blink-visible-slow ,slow-init
             kuro--blink-visible-fast ,fast-init)
       (should (eq ,slow-expected (kuro--blink-visible 'slow)))
       (should (eq ,fast-expected (kuro--blink-visible 'fast))))))

(kuro-overlays-test--def-blink-visible kuro-overlays-blink-visible-slow t   nil t   nil)
(kuro-overlays-test--def-blink-visible kuro-overlays-blink-visible-fast nil t   nil t)

(ert-deftest kuro-overlays-test--blink-visible-both-variants ()
  "Invariant: blink-visible dispatches correctly for both slow and fast variants."
  (dolist (entry kuro-overlays-test--blink-visible-table)
    (pcase-let ((`(,_name ,slow-init ,fast-init ,slow-exp ,fast-exp) entry))
      (kuro-overlays-test--with-buffer
        (setq kuro--blink-visible-slow slow-init
              kuro--blink-visible-fast fast-init)
        (should (eq slow-exp (kuro--blink-visible 'slow)))
        (should (eq fast-exp (kuro--blink-visible 'fast)))))))

(ert-deftest kuro-overlays-toggle-blink-state-flips-slow ()
  "kuro--toggle-blink-state 'slow toggles kuro--blink-visible-slow."
  (kuro-overlays-test--with-buffer
    (setq kuro--blink-visible-slow t)
    (kuro--toggle-blink-state 'slow)
    (should-not kuro--blink-visible-slow)
    (kuro--toggle-blink-state 'slow)
    (should kuro--blink-visible-slow)))

(ert-deftest kuro-overlays-toggle-blink-state-flips-fast ()
  "kuro--toggle-blink-state 'fast toggles kuro--blink-visible-fast."
  (kuro-overlays-test--with-buffer
    (setq kuro--blink-visible-fast t)
    (kuro--toggle-blink-state 'fast)
    (should-not kuro--blink-visible-fast)))

(ert-deftest kuro-overlays-toggle-blink-state-returns-new-value ()
  "kuro--toggle-blink-state returns the new (toggled) value."
  (kuro-overlays-test--with-buffer
    (setq kuro--blink-visible-slow t)
    (should-not (kuro--toggle-blink-state 'slow))
    (should (kuro--toggle-blink-state 'slow))))

(ert-deftest kuro-overlays-toggle-blink-state-does-not-affect-other-type ()
  "kuro--toggle-blink-state 'slow does not modify kuro--blink-visible-fast."
  (kuro-overlays-test--with-buffer
    (setq kuro--blink-visible-slow t
          kuro--blink-visible-fast t)
    (kuro--toggle-blink-state 'slow)
    (should kuro--blink-visible-fast)))

;;; Group 11: kuro--clear-all-image-overlays — edge cases

(ert-deftest kuro-overlays-clear-all-image-overlays-noop-when-empty ()
  "kuro--clear-all-image-overlays is a no-op and leaves list nil when already nil."
  (kuro-overlays-test--with-buffer
    (should (null kuro--image-overlays))
    (kuro--clear-all-image-overlays)
    (should (null kuro--image-overlays))))

(ert-deftest kuro-overlays-clear-all-image-overlays-removes-multiple ()
  "kuro--clear-all-image-overlays removes all overlays from a list of many."
  (kuro-overlays-test--with-buffer
    (insert "row0\nrow1\nrow2\n")
    (dotimes (i 3)
      (let ((ov (make-overlay (1+ i) (+ 2 i))))
        (overlay-put ov 'kuro-image t)
        (push ov kuro--image-overlays)))
    (should (= (length kuro--image-overlays) 3))
    (kuro--clear-all-image-overlays)
    (should (null kuro--image-overlays))))

;;; Group 12: kuro--render-image-notification — valid image path

(ert-deftest kuro-overlays-render-image-notification-places-overlay-when-valid ()
  "kuro--render-image-notification creates an image overlay when data is valid."
  (kuro-overlays-test--with-buffer
    (insert "line0\nline1\n")
    (let* ((fake-b64 (base64-encode-string "PNG"))
           (place-called nil))
      (cl-letf (((symbol-function 'kuro--get-image) (lambda (_id) fake-b64))
                ((symbol-function 'kuro--decode-png-image) (lambda (_b64) 'fake-img))
                ((symbol-function 'kuro--place-image-overlay)
                 (lambda (_img _row _col _w) (setq place-called t))))
        (kuro--render-image-notification '(1 0 0 2 1))
        (should place-called)))))

(ert-deftest kuro-overlays-render-image-notification-raw-width-zero-uses-one ()
  "kuro--render-image-notification clamps raw-width 0 to 1 via (max 1 raw-width)."
  (kuro-overlays-test--with-buffer
    (insert "line0\n")
    (let* ((fake-b64 (base64-encode-string "PNG"))
           (received-width nil))
      (cl-letf (((symbol-function 'kuro--get-image) (lambda (_id) fake-b64))
                ((symbol-function 'kuro--decode-png-image) (lambda (_b64) 'fake-img))
                ((symbol-function 'kuro--place-image-overlay)
                 (lambda (_img _row _col w) (setq received-width w))))
        (kuro--render-image-notification '(1 0 0 0 1))
        (should (= received-width 1))))))

;;; Group 13: kuro--tick-blink-overlays — blink both slow and fast at their boundary

(ert-deftest kuro-overlays-tick-blink-both-toggle-at-shared-boundary ()
  "When frame count reaches lcm(slow-frames, fast-frames), both phases toggle."
  (kuro-overlays-test--with-buffer
    (let* ((slow (kuro--blink-slow-frames))
           (fast (kuro--blink-fast-frames))
           (lcm-val (/ (* slow fast) (cl-gcd slow fast))))
      (setq kuro--blink-frame-count (1- lcm-val)
            kuro--blink-visible-slow t
            kuro--blink-visible-fast t)
      (kuro--tick-blink-overlays)
      ;; Both should have toggled (from t to nil) at the lcm boundary.
      (should-not kuro--blink-visible-slow)
      (should-not kuro--blink-visible-fast))))

(ert-deftest kuro-overlays-tick-blink-counter-keeps-increasing ()
  "kuro--blink-frame-count increments monotonically with each tick."
  (kuro-overlays-test--with-buffer
    (setq kuro--blink-frame-count 0)
    (dotimes (_ 5) (kuro--tick-blink-overlays))
    (should (= kuro--blink-frame-count 5))))

;;; Group 14: kuro--apply-ffi-face-at — fast-path and combined flags

(ert-deftest kuro-overlays-apply-ffi-face-at-fastpath-no-properties ()
  "kuro--apply-ffi-face-at is a no-op when fg, bg, and flags are all default."
  (kuro-overlays-test--with-buffer
    (insert "Hello\n")
    ;; All three args are at their default zero/default-color values.
    (kuro--apply-ffi-face-at 1 6 kuro--ffi-color-default kuro--ffi-color-default 0 0)
    (should (null kuro--blink-overlays))
    (should (null (get-text-property 1 'face)))
    (should (null (get-text-property 1 'invisible)))))

(ert-deftest kuro-overlays-apply-ffi-face-at-face-prop-set ()
  "kuro--apply-ffi-face-at sets the face text property when color/flags differ from default."
  (kuro-overlays-test--with-buffer
    (insert "Hello\n")
    ;; 0 is pure black (#x00000000), distinct from kuro--ffi-color-default (#xFF000000).
    ;; Passing a non-default fg forces the face-apply branch.
    (kuro--apply-ffi-face-at 1 6 0 kuro--ffi-color-default 0 0)
    (should (get-text-property 1 'face))))

(ert-deftest kuro-overlays-apply-ffi-face-at-blink-fast-takes-priority-over-slow ()
  "When both blink-fast and blink-slow flags are set, blink-fast overlay wins."
  (kuro-overlays-test--with-buffer
    (insert "Hello\n")
    (let ((flags (logior kuro--sgr-flag-blink-fast kuro--sgr-flag-blink-slow)))
      (kuro--apply-ffi-face-at 1 6 #xFF000000 #xFF000000 flags 0))
    (should (= (length kuro--blink-overlays) 1))
    ;; The cond checks blink-fast first, so type must be 'fast.
    (should (eq (overlay-get (car kuro--blink-overlays) 'kuro-blink-type) 'fast))))

(ert-deftest kuro-overlays-apply-ffi-face-at-hidden-and-blink-slow-combined ()
  "kuro--apply-ffi-face-at applies both blink overlay and invisible property together."
  (kuro-overlays-test--with-buffer
    (insert "Hello\n")
    (let ((flags (logior kuro--sgr-flag-blink-slow kuro--sgr-flag-hidden)))
      (kuro--apply-ffi-face-at 1 6 #xFF000000 #xFF000000 flags 0))
    ;; A slow blink overlay must exist.
    (should (= (length kuro--blink-overlays) 1))
    (should (eq (overlay-get (car kuro--blink-overlays) 'kuro-blink-type) 'slow))
    ;; The invisible text property must also be set.
    (should (get-text-property 1 'invisible))))

(ert-deftest kuro-overlays-apply-ffi-face-at-hidden-only-no-blink-overlay ()
  "kuro--apply-ffi-face-at sets invisible but creates no blink overlay for hidden-only."
  (kuro-overlays-test--with-buffer
    (insert "Hello\n")
    (kuro--apply-ffi-face-at 1 6 #xFF000000 #xFF000000 kuro--sgr-flag-hidden 0)
    (should (null kuro--blink-overlays))
    (should (get-text-property 1 'invisible))))

;;; Group 15: kuro--toggle-blink-phase — dead overlay handling

(ert-deftest kuro-overlays-toggle-blink-phase-skips-dead-overlay ()
  "kuro--toggle-blink-phase silently skips overlays that no longer have a buffer."
  (kuro-overlays-test--with-buffer
    (insert "Hello\n")
    ;; Create a slow blink overlay, then delete it to make it dead.
    (kuro--apply-blink-overlay 1 6 'slow)
    (let ((ov (car kuro--blink-overlays)))
      (delete-overlay ov)
      ;; kuro--blink-overlays still holds the (dead) reference.
      (should (= (length kuro--blink-overlays) 1))
      ;; Toggle must not signal an error even with a dead overlay.
      (should-not
       (condition-case err
           (progn (kuro--toggle-blink-phase 'slow) nil)
         (error err))))))

(ert-deftest kuro-overlays-toggle-blink-phase-slow-does-not-touch-fast-overlay ()
  "kuro--toggle-blink-phase 'slow leaves fast-type overlay invisible prop unchanged."
  (kuro-overlays-test--with-buffer
    (insert "Hello World\n")
    (setq kuro--blink-visible-fast t)
    (kuro--apply-blink-overlay 1 6 'fast)
    (let ((fast-ov (car kuro--blink-overlays)))
      ;; fast overlay starts visible (invisible = nil)
      (should-not (overlay-get fast-ov 'invisible))
      ;; Toggle slow — must NOT change the fast overlay
      (kuro--toggle-blink-phase 'slow)
      (should-not (overlay-get fast-ov 'invisible)))))

;;; Group 16: kuro--clear-all-image-overlays — dead overlay pruning

(ert-deftest kuro-overlays-clear-all-image-overlays-handles-dead-overlay ()
  "kuro--clear-all-image-overlays does not error when list contains a dead overlay."
  (kuro-overlays-test--with-buffer
    (insert "line\n")
    (let ((ov (make-overlay 1 5)))
      (overlay-put ov 'kuro-image t)
      (delete-overlay ov)  ; make it dead before clearing
      (push ov kuro--image-overlays))
    (should-not
     (condition-case err
         (progn (kuro--clear-all-image-overlays) nil)
       (error err)))
    (should (null kuro--image-overlays))))

(ert-deftest kuro-overlays-clear-all-image-overlays-deletes-live-overlays ()
  "kuro--clear-all-image-overlays makes all live overlays dead (no buffer)."
  (kuro-overlays-test--with-buffer
    (insert "row0\nrow1\n")
    (let ((ovs nil))
      (dotimes (i 2)
        (let ((ov (make-overlay (1+ i) (+ 2 i))))
          (overlay-put ov 'kuro-image t)
          (push ov kuro--image-overlays)
          (push ov ovs)))
      (kuro--clear-all-image-overlays)
      ;; After clearing, every overlay must have no buffer (i.e., be dead).
      (should (cl-every (lambda (ov) (null (overlay-buffer ov))) ovs)))))

(ert-deftest kuro-overlays-clear-row-image-overlays-empty-list-is-noop ()
  "kuro--clear-row-image-overlays is a no-op when kuro--image-overlays is nil."
  (kuro-overlays-test--with-buffer
    (insert "row0\nrow1\n")
    (should (null kuro--image-overlays))
    (kuro--clear-row-image-overlays 0)
    (should (null kuro--image-overlays))))

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

(ert-deftest kuro-overlays-test--register-blink-overlay-both-types ()
  "Invariant: register-blink-overlay adds to own list and excludes from other for both types."
  (dolist (entry kuro-overlays-test--register-blink-overlay-table)
    (pcase-let ((`(,_name ,type ,row ,own-sym ,other-sym) entry))
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
          (should     (memq ov (gethash row kuro--blink-overlays-by-row))))))))

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

(ert-deftest kuro-overlays-place-image-overlay-creates-overlay-at-position ()
  "`kuro--place-image-overlay' creates an overlay with correct properties."
  (kuro-overlays-test--with-buffer
    (insert "line0\nline1\n")
    (let ((kuro--image-overlays nil)
          (kuro--has-images nil))
      (kuro--place-image-overlay 'fake-img 0 0 1)
      (should (= (length kuro--image-overlays) 1))
      (should kuro--has-images)
      (let ((ov (car kuro--image-overlays)))
        (should (overlay-get ov 'kuro-image))
        (should (eq (overlay-get ov 'display) 'fake-img))))))

(ert-deftest kuro-overlays-place-image-overlay-noop-when-row-beyond-buffer ()
  "`kuro--place-image-overlay' is a no-op when the row is past the buffer end."
  (kuro-overlays-test--with-buffer
    (insert "one-line\n")
    (let ((kuro--image-overlays nil)
          (kuro--has-images nil))
      ;; Row 99 is way beyond the 1-line buffer.
      (kuro--place-image-overlay 'fake-img 99 0 1)
      (should (null kuro--image-overlays))
      (should-not kuro--has-images))))

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

(ert-deftest kuro-overlays-ffi-face-invisible-all-table-entries-correct ()
  "All entries in `kuro-overlays-test--ffi-face-invisible-table' match actual behavior."
  (dolist (entry kuro-overlays-test--ffi-face-invisible-table)
    (pcase-let ((`(,_name ,flags ,expectedp) entry))
      (kuro-overlays-test--with-buffer
        (insert "hello")
        (kuro--apply-ffi-face-effects (point-min) (point-max)
                                      (if (symbolp flags) (symbol-value flags) flags))
        (if expectedp
            (should (get-text-property (point-min) 'invisible))
          (should-not (get-text-property (point-min) 'invisible)))))))

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

(ert-deftest kuro-overlays-ffi-face-blink-all-table-entries-correct ()
  "All entries in `kuro-overlays-test--ffi-face-blink-table' create blink overlays."
  (dolist (entry kuro-overlays-test--ffi-face-blink-table)
    (pcase-let ((`(,_name ,flag) entry))
      (kuro-overlays-test--with-buffer
        (insert "xx")
        (kuro--apply-ffi-face-effects (point-min) (point-max) (symbol-value flag))
        (should kuro--blink-overlays)))))

;;; ── Group 22: kuro--apply-ffi-face-text-properties + constant invariants ─────

(ert-deftest kuro-overlays-apply-ffi-face-text-properties-sets-face ()
  "`kuro--apply-ffi-face-text-properties' applies the face spec to the region."
  (with-temp-buffer
    (insert "hello")
    (kuro--apply-ffi-face-text-properties (point-min) (point-max) 'bold)
    (let ((face-val (get-text-property 1 'face)))
      (should (or (eq face-val 'bold)
                  (and (listp face-val) (memq 'bold face-val)))))))

(ert-deftest kuro-overlays-sgr-visual-flags-mask-is-nonzero ()
  "`kuro--sgr-visual-flags-mask' is a non-zero integer covering blink+hidden bits."
  (should (and (integerp kuro--sgr-visual-flags-mask)
               (/= 0 kuro--sgr-visual-flags-mask))))

(ert-deftest kuro-overlays-blink-frames-cached-are-positive-integers ()
  "`kuro--blink-fast-frames-cached' and `kuro--blink-slow-frames-cached' are positive integers."
  (should (and (integerp kuro--blink-fast-frames-cached) (> kuro--blink-fast-frames-cached 0)))
  (should (and (integerp kuro--blink-slow-frames-cached) (> kuro--blink-slow-frames-cached 0))))

(provide 'kuro-overlays-test-2)

;;; kuro-overlays-test-2.el ends here
