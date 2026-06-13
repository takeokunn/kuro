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

;;; Group 10: kuro--toggle-blink-state / kuro--register-blink-overlay structural tests

(ert-deftest kuro-overlays-toggle-blink-state-expands-to-if ()
  "`kuro--toggle-blink-state' expands to an `if' dispatch on BLINK-TYPE."
  (let ((exp (macroexpand-1 '(kuro--toggle-blink-state my-type))))
    (should (eq (car exp) 'if))))

(ert-deftest kuro-overlays-toggle-blink-state-slow-path-sets-slow-var ()
  "`kuro--toggle-blink-state' slow path toggles `kuro--blink-visible-slow'."
  (let* ((exp (macroexpand-1 '(kuro--toggle-blink-state my-type)))
         (then-branch (nth 2 exp)))
    ;; then-branch should be (setq kuro--blink-visible-slow ...)
    (should (eq (car then-branch) 'setq))
    (should (eq (cadr then-branch) 'kuro--blink-visible-slow))))

(ert-deftest kuro-overlays-register-blink-overlay-expands-to-progn ()
  "`kuro--register-blink-overlay' expands to a `progn' wrapper."
  (let ((exp (macroexpand-1
              '(kuro--register-blink-overlay ov blink-type row))))
    (should (eq (car exp) 'progn))))

(provide 'kuro-overlays-test-2)

;;; kuro-overlays-test-2.el ends here
