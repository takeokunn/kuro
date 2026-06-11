;;; kuro-overlays-test-2.el --- kuro-overlays-test (part 2)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-overlays-test-support)

;;; Group 9: kuro--blink-visible and kuro--toggle-blink-state

(ert-deftest kuro-overlays-blink-visible-returns-slow-state ()
  "kuro--blink-visible 'slow returns kuro--blink-visible-slow."
  (kuro-overlays-test--with-buffer
    (setq kuro--blink-visible-slow t
          kuro--blink-visible-fast nil)
    (should (eq t   (kuro--blink-visible 'slow)))
    (should (eq nil (kuro--blink-visible 'fast)))))

(ert-deftest kuro-overlays-blink-visible-returns-fast-state ()
  "kuro--blink-visible 'fast returns kuro--blink-visible-fast."
  (kuro-overlays-test--with-buffer
    (setq kuro--blink-visible-slow nil
          kuro--blink-visible-fast t)
    (should (eq nil (kuro--blink-visible 'slow)))
    (should (eq t   (kuro--blink-visible 'fast)))))

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

(ert-deftest kuro-overlays-register-blink-overlay-slow-adds-to-all-structures ()
  "`kuro--register-blink-overlay' with \\='slow adds OV to all 3 tracking structures."
  (kuro-overlays-test--with-buffer
    (insert "hello\n")
    (let ((ov (make-overlay 1 3))
          (kuro--blink-overlays nil)
          (kuro--blink-overlays-slow nil)
          (kuro--blink-overlays-fast nil)
          (kuro--blink-overlays-by-row (make-hash-table :test 'eql)))
      (kuro--register-blink-overlay ov 'slow 0)
      (should (memq ov kuro--blink-overlays))
      (should (memq ov kuro--blink-overlays-slow))
      (should-not (memq ov kuro--blink-overlays-fast))
      (should (memq ov (gethash 0 kuro--blink-overlays-by-row))))))

(ert-deftest kuro-overlays-register-blink-overlay-fast-adds-to-fast-list ()
  "`kuro--register-blink-overlay' with \\='fast adds OV to fast sub-list only."
  (kuro-overlays-test--with-buffer
    (insert "hello\n")
    (let ((ov (make-overlay 1 3))
          (kuro--blink-overlays nil)
          (kuro--blink-overlays-slow nil)
          (kuro--blink-overlays-fast nil)
          (kuro--blink-overlays-by-row (make-hash-table :test 'eql)))
      (kuro--register-blink-overlay ov 'fast 1)
      (should (memq ov kuro--blink-overlays))
      (should (memq ov kuro--blink-overlays-fast))
      (should-not (memq ov kuro--blink-overlays-slow))
      (should (memq ov (gethash 1 kuro--blink-overlays-by-row))))))

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

(ert-deftest kuro-overlays-ffi-face-default-p-all-defaults ()
  "`kuro--ffi-face-default-p' returns t when all args are the \"default\" sentinel."
  (should (kuro--ffi-face-default-p kuro--ffi-color-default kuro--ffi-color-default 0 0)))

(ert-deftest kuro-overlays-ffi-face-default-p-non-default-fg ()
  "`kuro--ffi-face-default-p' returns nil when fg differs from the sentinel."
  (should-not (kuro--ffi-face-default-p #x00FF0000 kuro--ffi-color-default 0 0)))

(ert-deftest kuro-overlays-ffi-face-default-p-non-default-bg ()
  "`kuro--ffi-face-default-p' returns nil when bg differs from the sentinel."
  (should-not (kuro--ffi-face-default-p kuro--ffi-color-default #x000000FF 0 0)))

(ert-deftest kuro-overlays-ffi-face-default-p-non-zero-flags ()
  "`kuro--ffi-face-default-p' returns nil when flags is non-zero (logior short-circuit)."
  (should-not (kuro--ffi-face-default-p kuro--ffi-color-default kuro--ffi-color-default 1 0)))

(ert-deftest kuro-overlays-ffi-face-default-p-non-zero-ul-color ()
  "`kuro--ffi-face-default-p' returns nil when ul-color-enc is non-zero."
  (should-not (kuro--ffi-face-default-p kuro--ffi-color-default kuro--ffi-color-default 0 #x00FF0000)))

(ert-deftest kuro-overlays-ffi-face-default-p-flags-and-ul-both-nonzero ()
  "`kuro--ffi-face-default-p' returns nil when both flags and ul-color-enc are non-zero."
  (should-not (kuro--ffi-face-default-p kuro--ffi-color-default kuro--ffi-color-default 3 5)))

;;; Group 20: kuro--ffi-face-has-visual-effects-p — blink/hidden flags

(ert-deftest kuro-overlays-ffi-face-has-visual-effects-p-zero-flags ()
  "`kuro--ffi-face-has-visual-effects-p' returns nil for flags = 0."
  (should-not (kuro--ffi-face-has-visual-effects-p 0)))

(ert-deftest kuro-overlays-ffi-face-has-visual-effects-p-blink-slow ()
  "`kuro--ffi-face-has-visual-effects-p' detects slow-blink flag."
  (should (kuro--ffi-face-has-visual-effects-p kuro--sgr-flag-blink-slow)))

(ert-deftest kuro-overlays-ffi-face-has-visual-effects-p-blink-fast ()
  "`kuro--ffi-face-has-visual-effects-p' detects fast-blink flag."
  (should (kuro--ffi-face-has-visual-effects-p kuro--sgr-flag-blink-fast)))

(ert-deftest kuro-overlays-ffi-face-has-visual-effects-p-hidden ()
  "`kuro--ffi-face-has-visual-effects-p' detects hidden (invisible) flag."
  (should (kuro--ffi-face-has-visual-effects-p kuro--sgr-flag-hidden)))

(ert-deftest kuro-overlays-ffi-face-has-visual-effects-p-bold-only-is-false ()
  "`kuro--ffi-face-has-visual-effects-p' returns nil for bold-only (no blink/hidden)."
  (should-not (kuro--ffi-face-has-visual-effects-p #x01)))

(ert-deftest kuro-overlays-ffi-face-has-visual-effects-p-combined ()
  "`kuro--ffi-face-has-visual-effects-p' detects blink when combined with other flags."
  (should (kuro--ffi-face-has-visual-effects-p (logior #x01 kuro--sgr-flag-blink-slow))))

;;; Group 21: kuro--apply-ffi-face-effects — blink and hidden text-property dispatch

(ert-deftest kuro-overlays-ffi-face-effects-hidden-flag-adds-invisible ()
  "`kuro--apply-ffi-face-effects' adds invisible property when hidden flag is set."
  (kuro-overlays-test--with-buffer
    (insert "hello")
    (kuro--apply-ffi-face-effects (point-min) (point-max) kuro--sgr-flag-hidden)
    (should (get-text-property (point-min) 'invisible))))

(ert-deftest kuro-overlays-ffi-face-effects-no-hidden-no-invisible ()
  "`kuro--apply-ffi-face-effects' does not add invisible when hidden flag absent."
  (kuro-overlays-test--with-buffer
    (insert "hello")
    (kuro--apply-ffi-face-effects (point-min) (point-max) 0)
    (should-not (get-text-property (point-min) 'invisible))))

(ert-deftest kuro-overlays-ffi-face-effects-blink-fast-creates-overlay ()
  "`kuro--apply-ffi-face-effects' registers a fast-blink overlay for the region."
  (kuro-overlays-test--with-buffer
    (insert "xx")
    (kuro--apply-ffi-face-effects (point-min) (point-max) kuro--sgr-flag-blink-fast)
    ;; The overlay list for 'fast must be non-nil
    (should kuro--blink-overlays)))

(ert-deftest kuro-overlays-ffi-face-effects-blink-slow-creates-overlay ()
  "`kuro--apply-ffi-face-effects' registers a slow-blink overlay for the region."
  (kuro-overlays-test--with-buffer
    (insert "xx")
    (kuro--apply-ffi-face-effects (point-min) (point-max) kuro--sgr-flag-blink-slow)
    (should kuro--blink-overlays)))

(provide 'kuro-overlays-test-2)

;;; kuro-overlays-test-2.el ends here
