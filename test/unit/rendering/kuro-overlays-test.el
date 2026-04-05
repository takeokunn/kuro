;;; kuro-overlays-test.el --- Unit tests for kuro-overlays.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-overlays.el (blink overlays, image overlays,
;; prompt navigation, focus events).
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-overlays)
(require 'kuro-faces-attrs)

;;; Helpers

(defmacro kuro-overlays-test--with-buffer (&rest body)
  "Run BODY in a temp buffer with overlay state initialized to defaults.
Sets the following buffer-local variables:
  `kuro--blink-overlays' nil (no active blink overlays)
  `kuro--blink-visible-slow' t (slow blink phase starts visible)
  `kuro--blink-visible-fast' t (fast blink phase starts visible)
  `kuro--image-overlays' nil (no active image overlays)
  `kuro--prompt-positions' nil (no known prompt positions)
  `kuro--blink-frame-count' 0 (frame counter reset)
  `inhibit-read-only' t (allows buffer modification in tests)"
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (kuro--blink-overlays nil)
           (kuro--image-overlays nil)
           (kuro--prompt-positions nil)
           (kuro--blink-frame-count 0)
           (kuro--blink-visible-slow t)
           (kuro--blink-visible-fast t))
       ,@body)))

;;; Group 1: Blink overlays

(ert-deftest kuro-overlays-apply-blink-slow-creates-overlay ()
  "kuro--apply-blink-overlay creates a blink overlay with correct properties."
  (kuro-overlays-test--with-buffer
    (insert "Hello\n")
    (kuro--apply-blink-overlay 1 6 'slow)
    (should (= (length kuro--blink-overlays) 1))
    (let ((ov (car kuro--blink-overlays)))
      (should (overlay-get ov 'kuro-blink))
      (should (eq (overlay-get ov 'kuro-blink-type) 'slow)))))

(ert-deftest kuro-overlays-apply-blink-fast-creates-overlay ()
  "Fast blink overlay has kuro-blink-type = fast."
  (kuro-overlays-test--with-buffer
    (insert "Hello\n")
    (kuro--apply-blink-overlay 1 6 'fast)
    (let ((ov (car kuro--blink-overlays)))
      (should (eq (overlay-get ov 'kuro-blink-type) 'fast)))))

(ert-deftest kuro-overlays-apply-blink-visible-when-visible ()
  "Blink overlay is visible (invisible=nil) when blink state is visible."
  (kuro-overlays-test--with-buffer
    (insert "Hello\n")
    (setq kuro--blink-visible-slow t)
    (kuro--apply-blink-overlay 1 6 'slow)
    (let ((ov (car kuro--blink-overlays)))
      ;; visible-slow=t → invisible should be nil (= not invisible = visible)
      (should-not (overlay-get ov 'invisible)))))

(ert-deftest kuro-overlays-apply-blink-invisible-when-hidden ()
  "Blink overlay is invisible when blink state is hidden."
  (kuro-overlays-test--with-buffer
    (insert "Hello\n")
    (setq kuro--blink-visible-slow nil)
    (kuro--apply-blink-overlay 1 6 'slow)
    (let ((ov (car kuro--blink-overlays)))
      (should (overlay-get ov 'invisible)))))

;;; Group 2: kuro--tick-blink-overlays

(ert-deftest kuro-overlays-tick-blink-increments-counter ()
  "kuro--tick-blink-overlays increments kuro--blink-frame-count by 1."
  (kuro-overlays-test--with-buffer
    (setq kuro--blink-frame-count 0)
    (kuro--tick-blink-overlays)
    (should (= kuro--blink-frame-count 1))))

(ert-deftest kuro-overlays-tick-blink-slow-toggles-at-interval ()
  "Slow blink state toggles when frame count reaches multiple of slow-frames.
At the default 120 fps, `kuro--blink-slow-frames' returns 60."
  (kuro-overlays-test--with-buffer
    (let ((slow (kuro--blink-slow-frames)))
      (setq kuro--blink-frame-count (1- slow)
            kuro--blink-visible-slow t)
      (kuro--tick-blink-overlays)
      (should (= kuro--blink-frame-count slow))
      (should-not kuro--blink-visible-slow))))

(ert-deftest kuro-overlays-tick-blink-fast-toggles-at-interval ()
  "Fast blink state toggles when frame count reaches multiple of fast-frames.
At the default 120 fps, `kuro--blink-fast-frames' returns 20."
  (kuro-overlays-test--with-buffer
    (let ((fast (kuro--blink-fast-frames)))
      (setq kuro--blink-frame-count (1- fast)
            kuro--blink-visible-fast t)
      (kuro--tick-blink-overlays)
      (should (= kuro--blink-frame-count fast))
      (should-not kuro--blink-visible-fast))))

(ert-deftest kuro-overlays-tick-blink-adapts-to-frame-rate ()
  "Blink intervals scale with `kuro-frame-rate' for correct real-time timing.
After changing `kuro-frame-rate', `kuro--recompute-blink-frame-intervals'
must be called to update the cached values."
  (kuro-overlays-test--with-buffer
    (let ((kuro-frame-rate 30))
      (kuro--recompute-blink-frame-intervals)
      ;; At 30 fps: slow = round(30 * 0.5) = 15, fast = round(30 * 0.167) = 5
      (should (= (kuro--blink-slow-frames) 15))
      (should (= (kuro--blink-fast-frames) 5)))
    (let ((kuro-frame-rate 120))
      (kuro--recompute-blink-frame-intervals)
      ;; At 120 fps: slow = round(120 * 0.5) = 60, fast = round(120 * 0.167) = 20
      (should (= (kuro--blink-slow-frames) 60))
      (should (= (kuro--blink-fast-frames) 20)))
    ;; Edge case: very low frame rate should not produce 0 (division-by-zero guard)
    (let ((kuro-frame-rate 1))
      (kuro--recompute-blink-frame-intervals)
      (should (>= (kuro--blink-slow-frames) 1))
      (should (>= (kuro--blink-fast-frames) 1)))
    ;; Restore default
    (let ((kuro-frame-rate 60))
      (kuro--recompute-blink-frame-intervals))))

(ert-deftest kuro-overlays-tick-blink-no-toggle-at-non-boundary ()
  "Slow/fast blink states do NOT toggle at non-boundary frame counts."
  (kuro-overlays-test--with-buffer
    (setq kuro--blink-frame-count 5
          kuro--blink-visible-slow t
          kuro--blink-visible-fast t)
    (kuro--tick-blink-overlays)  ; count becomes 6
    (should kuro--blink-visible-slow)
    (should kuro--blink-visible-fast)))

;;; Group 3: Image overlays

(ert-deftest kuro-overlays-clear-all-image-overlays-empties-list ()
  "kuro--clear-all-image-overlays removes all image overlays and clears the list."
  (kuro-overlays-test--with-buffer
    (insert "line\n")
    ;; Create a dummy overlay and push it
    (let ((ov (make-overlay 1 5)))
      (overlay-put ov 'kuro-image t)
      (push ov kuro--image-overlays))
    (should (= (length kuro--image-overlays) 1))
    (kuro--clear-all-image-overlays)
    (should (null kuro--image-overlays))))

(ert-deftest kuro-overlays-clear-row-image-overlays-removes-on-row ()
  "kuro--clear-row-image-overlays removes overlays starting on the target row."
  (kuro-overlays-test--with-buffer
    (insert "row0\nrow1\n")
    ;; Create overlay on row 1
    (save-excursion
      (goto-char (point-min))
      (forward-line 1)
      (let ((ov (make-overlay (point) (+ (point) 3))))
        (overlay-put ov 'kuro-image t)
        (push ov kuro--image-overlays)))
    (should (= (length kuro--image-overlays) 1))
    (kuro--clear-row-image-overlays 1)
    (should (null kuro--image-overlays))))

(ert-deftest kuro-overlays-clear-row-image-overlays-preserves-other-rows ()
  "kuro--clear-row-image-overlays preserves overlays on other rows."
  (kuro-overlays-test--with-buffer
    (insert "row0\nrow1\n")
    ;; Create overlay on row 0
    (save-excursion
      (goto-char (point-min))
      (let ((ov (make-overlay (point) (+ (point) 3))))
        (overlay-put ov 'kuro-image t)
        (push ov kuro--image-overlays)))
    (should (= (length kuro--image-overlays) 1))
    ;; Clear row 1 — should not remove the overlay on row 0
    (kuro--clear-row-image-overlays 1)
    (should (= (length kuro--image-overlays) 1))))

;;; Group 4: Prompt navigation (OSC 133)

(ert-deftest kuro-overlays-prompt-positions-initially-nil ()
  "kuro--prompt-positions starts as nil in a new buffer context."
  (kuro-overlays-test--with-buffer
    (should (null kuro--prompt-positions))))

(ert-deftest kuro-overlays-previous-prompt-no-prompts ()
  "kuro-previous-prompt shows message when no prompts available."
  (kuro-overlays-test--with-buffer
    (insert "line1\nline2\n")
    ;; With no prompt marks, should message "no previous prompt"
    (let ((messages nil))
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) messages))))
        (kuro-previous-prompt)
        (should (cl-some (lambda (m) (string-match-p "no previous prompt" m)) messages))))))

(ert-deftest kuro-overlays-next-prompt-no-prompts ()
  "kuro-next-prompt shows message when no prompts available."
  (kuro-overlays-test--with-buffer
    (insert "line1\nline2\n")
    (let ((messages nil))
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) messages))))
        (kuro-next-prompt)
        (should (cl-some (lambda (m) (string-match-p "no next prompt" m)) messages))))))

(ert-deftest kuro-overlays-next-prompt-jumps-to-mark ()
  "kuro-next-prompt moves point to the next prompt-start row."
  (kuro-overlays-test--with-buffer
    (insert "line0\nline1\nPROMPT\nline3\n")
    ;; Register row 2 as a prompt-start (proper list: MARK-TYPE ROW COL)
    (setq kuro--prompt-positions (list (list "prompt-start" 2 0)))
    ;; Start at row 0
    (goto-char (point-min))
    (kuro-next-prompt)
    ;; Should now be on row 2
    (should (= (1- (line-number-at-pos)) 2))))

;;; Group 5: kuro--apply-ffi-face-at (overlay and text-property side effects)

(ert-deftest kuro-overlays-apply-ffi-face-at-blink-slow-creates-overlay ()
  "kuro--apply-ffi-face-at creates a slow blink overlay when flags include blink-slow."
  (kuro-overlays-test--with-buffer
    (insert "Hello\n")
    ;; kuro--sgr-flag-blink-slow (bit 4) bypasses the all-default fast-path
    (kuro--apply-ffi-face-at 1 6 #xFF000000 #xFF000000 kuro--sgr-flag-blink-slow 0)
    (should (> (length kuro--blink-overlays) 0))
    (should (eq (overlay-get (car kuro--blink-overlays) 'kuro-blink-type) 'slow))))

(ert-deftest kuro-overlays-apply-ffi-face-at-blink-fast-creates-overlay ()
  "kuro--apply-ffi-face-at creates a fast blink overlay when flags include blink-fast."
  (kuro-overlays-test--with-buffer
    (insert "Hello\n")
    ;; kuro--sgr-flag-blink-fast (bit 5) bypasses the all-default fast-path
    (kuro--apply-ffi-face-at 1 6 #xFF000000 #xFF000000 kuro--sgr-flag-blink-fast 0)
    (should (> (length kuro--blink-overlays) 0))
    (should (eq (overlay-get (car kuro--blink-overlays) 'kuro-blink-type) 'fast))))

(ert-deftest kuro-overlays-apply-ffi-face-at-hidden-sets-invisible ()
  "kuro--apply-ffi-face-at sets invisible text property when flags include hidden."
  (kuro-overlays-test--with-buffer
    (insert "Hello\n")
    ;; kuro--sgr-flag-hidden (bit 7) bypasses the all-default fast-path
    (kuro--apply-ffi-face-at 1 6 #xFF000000 #xFF000000 kuro--sgr-flag-hidden 0)
    (should (get-text-property 1 'invisible))))

(ert-deftest kuro-overlays-apply-ffi-face-at-no-blink-no-overlay ()
  "kuro--apply-ffi-face-at creates no blink overlay when no blink flags set."
  (kuro-overlays-test--with-buffer
    (insert "Hello\n")
    ;; flags=0, fg/bg both default — fast-path skips everything
    (kuro--apply-ffi-face-at 1 6 #xFF000000 #xFF000000 0 0)
    (should (null kuro--blink-overlays))))

(ert-deftest kuro-overlays-call-with-normalized-ffi-face-range-calls-continuation ()
  "Normalized face ranges invoke the continuation with clamped positions."
  (let (captured)
    (should
     (kuro--call-with-normalized-ffi-face-range
      [1 99 10 20 30 40] 5 10
      (lambda (&rest args)
        (setq captured args))))
    (should (equal captured '(6 10 10 20 30 40)))))

(ert-deftest kuro-overlays-call-with-normalized-ffi-face-range-skips-empty-range ()
  "Zero-width normalized face ranges do not invoke the continuation."
  (let ((called nil))
    (should-not
     (kuro--call-with-normalized-ffi-face-range
      [3 3 10 20 30 40] 5 10
      (lambda (&rest _args)
        (setq called t))))
    (should-not called)))

;;; Group 6: kuro--render-image-notification

(ert-deftest kuro-overlays-render-image-notification-no-error-when-image-nil ()
  "kuro--render-image-notification is a no-op (no error) when kuro--get-image returns nil."
  ;; Stub kuro--get-image to return nil so the (when (and b64 ...)) guard
  ;; prevents create-image from being called.  The function must not signal.
  (kuro-overlays-test--with-buffer
    (insert "placeholder\n")
    (cl-letf (((symbol-function 'kuro--get-image) (lambda (_id) nil)))
      (should-not
       (condition-case err
           (progn
             (kuro--render-image-notification '(42 0 0 2 1))
             nil)
         (error err))))))

(ert-deftest kuro-overlays-render-image-notification-no-error-when-b64-empty ()
  "kuro--render-image-notification is a no-op (no error) when image data is empty string."
  (kuro-overlays-test--with-buffer
    (insert "placeholder\n")
    (cl-letf (((symbol-function 'kuro--get-image) (lambda (_id) "")))
      (should-not
       (condition-case err
           (progn
             (kuro--render-image-notification '(42 0 0 2 1))
             nil)
         (error err))))))

;;; Group 7: Multi-row image overlay clearing

(ert-deftest test-kuro-overlays-clear-row-image-overlays-multi-row-overlap ()
  "Clearing a row removes overlays that span across it (not just start on it)."
  (with-temp-buffer
    (dotimes (_ 5) (insert "test line\n"))
    (let* ((kuro--image-overlays nil)
           ;; Create an overlay that spans rows 1-3 (starts at row 1, ends at row 3)
           (start (save-excursion (goto-char (point-min)) (forward-line 1) (point)))
           (end (save-excursion (goto-char (point-min)) (forward-line 3) (+ (point) 5))))
      (let ((ov (make-overlay start end)))
        (overlay-put ov 'kuro-image t)
        (push ov kuro--image-overlays))
      ;; Clearing row 2 should remove the multi-row overlay (it overlaps row 2)
      (kuro--clear-row-image-overlays 2)
      (should (null kuro--image-overlays)))))

(ert-deftest test-kuro-overlays-clear-row-image-overlays-multi-row-no-overlap ()
  "Clearing a row preserves overlays that do not overlap it."
  (with-temp-buffer
    (dotimes (_ 5) (insert "test line\n"))
    (let* ((kuro--image-overlays nil)
           ;; Create an overlay that spans rows 1-2
           (start (save-excursion (goto-char (point-min)) (forward-line 1) (point)))
           (end (save-excursion (goto-char (point-min)) (forward-line 2) (+ (point) 5))))
      (let ((ov (make-overlay start end)))
        (overlay-put ov 'kuro-image t)
        (push ov kuro--image-overlays))
      ;; Clearing row 4 should NOT remove the overlay (no overlap)
      (kuro--clear-row-image-overlays 4)
      (should (= 1 (length kuro--image-overlays))))))

;;; Group 8: kuro--toggle-blink-phase

(ert-deftest kuro-overlays-toggle-blink-phase-slow-flips-state ()
  "kuro--toggle-blink-phase 'slow toggles kuro--blink-visible-slow."
  (kuro-overlays-test--with-buffer
    (setq kuro--blink-visible-slow t)
    (kuro--toggle-blink-phase 'slow)
    (should-not kuro--blink-visible-slow)
    (kuro--toggle-blink-phase 'slow)
    (should kuro--blink-visible-slow)))

(ert-deftest kuro-overlays-toggle-blink-phase-fast-flips-state ()
  "kuro--toggle-blink-phase 'fast toggles kuro--blink-visible-fast."
  (kuro-overlays-test--with-buffer
    (setq kuro--blink-visible-fast t)
    (kuro--toggle-blink-phase 'fast)
    (should-not kuro--blink-visible-fast)))

(ert-deftest kuro-overlays-toggle-blink-phase-updates-matching-overlays ()
  "kuro--toggle-blink-phase sets `invisible' on overlays of the matching type."
  (kuro-overlays-test--with-buffer
    (insert "Hello\n")
    (setq kuro--blink-visible-slow t)
    (kuro--apply-blink-overlay 1 6 'slow)
    (let ((ov (car kuro--blink-overlays)))
      ;; Overlay is initially visible (invisible=nil)
      (should-not (overlay-get ov 'invisible))
      ;; Toggle slow: state becomes nil → invisible should become t
      (kuro--toggle-blink-phase 'slow)
      (should (overlay-get ov 'invisible))
      ;; Toggle again: state becomes t → invisible becomes nil
      (kuro--toggle-blink-phase 'slow)
      (should-not (overlay-get ov 'invisible)))))

(ert-deftest kuro-overlays-toggle-blink-phase-does-not-affect-other-type ()
  "kuro--toggle-blink-phase 'slow does not alter overlays of type 'fast."
  (kuro-overlays-test--with-buffer
    (insert "Hello World\n")
    (setq kuro--blink-visible-slow t
          kuro--blink-visible-fast t)
    (kuro--apply-blink-overlay 1 6 'fast)
    (let ((fast-ov (car kuro--blink-overlays)))
      (kuro--toggle-blink-phase 'slow)
      ;; slow toggle must not touch the fast overlay
      (should-not (overlay-get fast-ov 'invisible)))))

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

(provide 'kuro-overlays-test)

;;; kuro-overlays-test.el ends here
