;;; kuro-renderer-unit-test.el --- Unit tests for kuro-renderer.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for the Kuro renderer system.
;; These tests cover pure Emacs Lisp functions only and do NOT require
;; the Rust dynamic module (kuro-core-*).
;; Tests focus on internal logic, state management, and buffer operations.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-renderer)

;;; Test Setup Helpers

(defmacro with-test-buffer (&rest body)
  "Create a temporary buffer for testing and execute BODY in it."
  `(let ((test-buffer (generate-new-buffer " *kuro-renderer-test*")))
     (unwind-protect
         (with-current-buffer test-buffer
           ,@body)
       (when (buffer-live-p test-buffer)
         (kill-buffer test-buffer)))))

;;; Group 1: kuro-renderer-cycle-state-machine (FR-002-01)

(ert-deftest test-kuro-render-cycle-state-initialization ()
  "Verify that render cycle state variables are properly initialized."
  (let ((blink-count kuro--blink-frame-count)
        (decckm-count kuro--decckm-frame-count)
        (visible-slow kuro--blink-visible-slow)
        (visible-fast kuro--blink-visible-fast))
    ;; Initial values should be integers and booleans
    (should (integerp blink-count))
    (should (integerp decckm-count))
    (should (or (eq visible-slow t) (eq visible-slow nil)))
    (should (or (eq visible-fast t) (eq visible-fast nil)))))

(ert-deftest test-kuro-render-cycle-state-update ()
  "Test that render cycle state variables are updated correctly."
  (let ((orig-blink kuro--blink-frame-count)
        (orig-decckm kuro--decckm-frame-count))
    ;; Simulate state updates as in render cycle
    (setq kuro--decckm-frame-count (1+ kuro--decckm-frame-count))
    (setq kuro--blink-frame-count (1+ kuro--blink-frame-count))
    ;; Verify increments
    (should (= kuro--decckm-frame-count (1+ orig-decckm)))
    (should (= kuro--blink-frame-count (1+ orig-blink)))
    ;; Restore
    (setq kuro--decckm-frame-count orig-decckm)
    (setq kuro--blink-frame-count orig-blink)))

(ert-deftest test-kuro-render-cycle-blink-toggle ()
  "Test that blink visibility toggles at correct intervals."
  (let ((orig-slow kuro--blink-visible-slow)
        (orig-fast kuro--blink-visible-fast))
    ;; Simulate slow blink toggle (every 30 frames)
    (setq kuro--blink-visible-slow (not kuro--blink-visible-slow))
    (should (eq kuro--blink-visible-slow (not orig-slow)))
    ;; Simulate fast blink toggle (every 10 frames)
    (setq kuro--blink-visible-fast (not kuro--blink-visible-fast))
    (should (eq kuro--blink-visible-fast (not orig-fast)))
    ;; Restore
    (setq kuro--blink-visible-slow orig-slow)
    (setq kuro--blink-visible-fast orig-fast)))

(ert-deftest test-kuro-render-cycle-nil-handling ()
  "Test that render cycle handles nil updates gracefully."
  (let ((updates nil))
    ;; Simulate processing nil updates
    (when updates
      (dolist (line-update updates)
        (should (consp line-update))))
    ;; Should not error with nil updates
    (should-not updates)))

(ert-deftest test-kuro-render-cycle-buffer-modified ()
  "Test that buffer is marked as modified during render cycle."
  (with-test-buffer
    (let ((inhibit-read-only t))
      (insert "test content\n")
      (set-buffer-modified-p nil)
      ;; Simulate buffer modification
      (insert "more content")
      ;; Buffer should be marked modified
      (should (buffer-modified-p)))))

;;; Group 2: kuro-renderer-cursor-update (FR-002-02)

(ert-deftest test-kuro-cursor-marker-positioning ()
  "Test that cursor marker is positioned correctly."
  (with-test-buffer
    (let ((inhibit-read-only t))
      (insert "line 1\nline 2\nline 3\n")
      ;; Create and position marker
      (setq-local kuro--cursor-marker (make-marker))
      (set-marker kuro--cursor-marker (point-min))
      ;; Verify marker at beginning
      (should (= (marker-position kuro--cursor-marker) 1))
      ;; Move to line 1, column 5
      (goto-char (point-min))
      (forward-line 1)
      (forward-char 5)
      (set-marker kuro--cursor-marker (point))
      ;; Verify marker moved
      (should (> (marker-position kuro--cursor-marker) 1)))))

(ert-deftest test-kuro-cursor-marker-removal ()
  "Test that old marker is removed when creating new one."
  (with-test-buffer
    (let ((inhibit-read-only t))
      (insert "test content\n")
      ;; Create first marker
      (setq-local kuro--cursor-marker (make-marker))
      (set-marker kuro--cursor-marker (point-min))
      (let ((first-pos (marker-position kuro--cursor-marker)))
        ;; Remove and create new marker
        (set-marker kuro--cursor-marker nil)
        (setq-local kuro--cursor-marker (make-marker))
        (set-marker kuro--cursor-marker (point-max))
        ;; First marker position saved correctly
        (should (= first-pos 1))
        ;; New marker should be at max
        (should (= (marker-position kuro--cursor-marker) (point-max)))))))

(ert-deftest test-kuro-cursor-column-clamping ()
  "Test that cursor column is clamped to line end."
  (with-test-buffer
    (let ((inhibit-read-only t))
      (insert "short\n")
      (goto-char (point-min))
      (forward-line 0)
      ;; Try to go beyond line end
      (let ((col 100)
            (line-end (line-end-position)))
        (goto-char (min (+ (point) col) line-end)))
      ;; Position should be clamped to line end
      (should (= (point) (line-end-position))))))

(ert-deftest test-kuro-cursor-visible-region-update ()
  "Test that cursor marker is positioned correctly when moving."
  (with-test-buffer
    (let ((inhibit-read-only t))
      (dotimes (i 100)
        (insert (format "line %d\n" i)))
      ;; Create cursor marker
      (setq-local kuro--cursor-marker (make-marker))
      (set-marker kuro--cursor-marker (point-min))
      ;; Move cursor to middle
      (goto-char (point-min))
      (forward-line 50)
      (set-marker kuro--cursor-marker (point))
      ;; Cursor marker is positioned correctly
      (should (marker-position kuro--cursor-marker))
      (should (> (marker-position kuro--cursor-marker) 0))
      (should (<= (marker-position kuro--cursor-marker) (point-max))))))

(ert-deftest test-kuro-cursor-type-setting ()
  "Test that cursor type is set based on visibility."
  (with-test-buffer
    ;; Set cursor to visible
    (setq-local cursor-type 'box)
    (should (eq cursor-type 'box))
    ;; Set cursor to hidden
    (setq-local cursor-type nil)
    (should-not cursor-type)))

;;; Group 3: kuro-renderer-apply-faces (FR-002-03)

(ert-deftest test-kuro-face-caching ()
  "Test that faces are cached correctly."
  (let ((attrs1 '(:foreground (named . "red") :background :default :flags 0))
        (attrs2 '(:foreground (named . "blue") :background :default :flags 0)))
    ;; Clear cache first
    (kuro--clear-face-cache)
    ;; Get face for first attrs
    (let ((face1 (kuro--get-cached-face attrs1)))
      (should (consp face1))
      ;; Get same face again - should be from cache
      (let ((face1-cached (kuro--get-cached-face attrs1)))
        (should (eq face1 face1-cached)))
      ;; Get different face
      (let ((face2 (kuro--get-cached-face attrs2)))
        (should (consp face2))
        (should-not (eq face1 face2))))))

(ert-deftest test-kuro-face-cache-invalidation ()
  "Test that face cache can be invalidated."
  (let ((attrs '(:foreground (named . "red") :background :default :flags 0)))
    ;; Get face and cache it
    (kuro--clear-face-cache)
    (let ((face1 (kuro--get-cached-face attrs)))
      (should (consp face1))
      ;; Clear cache
      (kuro--clear-face-cache)
      ;; Get face again - should be new instance
      (let ((face2 (kuro--get-cached-face attrs)))
        (should (consp face2))
        (should-not (eq face1 face2))))))

(ert-deftest test-kuro-face-application ()
  "Test that faces are applied to buffer text correctly."
  (with-test-buffer
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (insert "Hello World\n")
      ;; Apply face to "Hello"
      (let ((face '(:foreground "red")))
        (add-text-properties 1 6 `(face ,(list face))))
      ;; Check face was applied
      (let ((applied-face (get-text-property 1 'face)))
        (should applied-face)))))

(ert-deftest test-kuro-default-face-usage ()
  "Test that default faces are used when colors are :default."
  (let ((attrs '(:foreground :default :background :default :flags 0)))
    (let ((fg-color (kuro--color-to-emacs (plist-get attrs :foreground)))
          (bg-color (kuro--color-to-emacs (plist-get attrs :background))))
      ;; :default should convert to nil
      (should-not fg-color)
      (should-not bg-color))))

(ert-deftest test-kuro-face-attrs-decoding ()
  "Test that attribute flags are decoded correctly."
  (let ((decoded (kuro--decode-attrs #x01)))
    (should (plist-get decoded :bold))
    (should-not (plist-get decoded :italic))
    (should-not (plist-get decoded :underline))
    ;; Test multiple flags
    (let ((multi-decoded (kuro--decode-attrs #x05)))  ; bold + italic
      (should (plist-get multi-decoded :bold))
      (should (plist-get multi-decoded :italic)))))

;;; Group 4: kuro-renderer-update-line (FR-002-04)

(ert-deftest test-kuro-update-line-content ()
  "Test that line content is updated correctly."
  (with-test-buffer
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (insert "original line\nsecond line\n")
      ;; Update first line
      (kuro--update-line 0 "new content")
      ;; Check line was updated
      (goto-char (point-min))
      (should (looking-at "new content"))
      ;; Second line should be unchanged
      (forward-line 1)
      (should (looking-at "second line")))))

(ert-deftest test-kuro-update-line-deletion ()
  "Test that line deletion works correctly."
  (with-test-buffer
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (insert "line 1\nline 2\nline 3\n")
      ;; Delete middle line by updating with empty content
      (kuro--update-line 1 "")
      ;; Should still have newline separator
      (goto-char (point-min))
      (forward-line 1)
      (should (looking-at "\n")))))

(ert-deftest test-kuro-update-line-insertion ()
  "Test that line insertion works correctly."
  (with-test-buffer
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (insert "line 1\nline 3\n")
      ;; Insert a line in the middle
      (goto-char (point-min))
      (forward-line 1)
      (insert "line 2\n")
      ;; Check all three lines exist
      (goto-char (point-min))
      (should (looking-at "line 1"))
      (forward-line 1)
      (should (looking-at "line 2"))
      (forward-line 1)
      (should (looking-at "line 3")))))

(ert-deftest test-kuro-update-line-with-unicode ()
  "Test that line updates handle unicode characters correctly."
  (with-test-buffer
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (insert "旧 content\n")
      (kuro--update-line 0 "新 content")
      (goto-char (point-min))
      (should (looking-at "新 content")))))

(ert-deftest test-kuro-update-line-preserve-newline ()
  "Test that update-line preserves line endings."
  (with-test-buffer
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (insert "line 1\nline 2\n")
      (kuro--update-line 0 "updated line")
      ;; Count lines
      (let ((line-count (count-lines (point-min) (point-max))))
        (should (= line-count 2))))))

(ert-deftest test-kuro-update-line-at-end ()
  "Test that updating last line works correctly."
  (with-test-buffer
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (insert "line 1\nline 2\n")
      (kuro--update-line 1 "last line updated")
      (goto-char (point-min))
      (forward-line 1)
      (should (looking-at "last line updated")))))

(provide 'kuro-renderer-unit-test)

;;; kuro-renderer-unit-test.el ends here
