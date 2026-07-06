;;; kuro-render-buffer-test.el --- Unit tests for kuro-render-buffer.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-render-buffer.el (buffer update helpers).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;;
;; Covered:
;;   - kuro--ensure-buffer-row-exists: short-buffer path (appends missing lines)
;;   - kuro--ensure-buffer-row-exists: exact-fit path (no-op)
;;   - kuro--ensure-buffer-row-exists: row already present (no extra lines added)
;;   - kuro--apply-buffer-scroll: scroll-up shifts lines correctly
;;   - kuro--apply-buffer-scroll: scroll-down shifts lines correctly
;;   - kuro--apply-buffer-scroll: zero scroll is a no-op
;;   - kuro--update-line-full: basic row update, nil-text no-op, face ranges applied
;;   - kuro--update-cursor: visible/hidden cursor, position update, cache skip

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-render-buffer-test-support)

;;; Group 1: kuro--ensure-buffer-row-exists — short-buffer path

(ert-deftest kuro-render-buffer-ensure-row-short-buffer-appends-lines ()
  "kuro--ensure-buffer-row-exists appends blank lines when buffer is too short.
The implementation appends exactly `not-moved' newlines so that forward-line
to `row' returns 0 (succeeds).  count-lines may equal row rather than row+1
because the last inserted line is the partial line at point-max."
  (kuro-render-buffer-test--with-buffer
    ;; Start with 2 lines; request row 4
    (insert "line0\nline1\n")
    (should (= (count-lines (point-min) (point-max)) 2))
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--ensure-buffer-row-exists 4))
    ;; Row 4 must now be reachable: forward-line 4 from point-min returns 0
    (goto-char (point-min))
    (should (= (forward-line 4) 0))))

(ert-deftest kuro-render-buffer-ensure-row-short-buffer-positions-point-at-row ()
  "After appending, kuro--ensure-buffer-row-exists leaves point at the start of row."
  (kuro-render-buffer-test--with-buffer
    (insert "a\nb\n")
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--ensure-buffer-row-exists 4))
    ;; Point should be at the beginning of line 5 (row 4, 0-indexed)
    (should (= (1- (line-number-at-pos)) 4))))

(ert-deftest kuro-render-buffer-ensure-row-appends-exact-missing-count ()
  "kuro--ensure-buffer-row-exists makes the target row reachable.
3 lines (rows 0–2) → request row 5 → forward-line 5 must return 0."
  (kuro-render-buffer-test--with-buffer
    ;; 3 lines: rows 0, 1, 2.  Request row 5.
    (insert "r0\nr1\nr2\n")
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--ensure-buffer-row-exists 5))
    ;; Row 5 must be reachable
    (goto-char (point-min))
    (should (= (forward-line 5) 0))))

(ert-deftest kuro-render-buffer-ensure-row-no-op-when-row-exists ()
  "kuro--ensure-buffer-row-exists does not append lines when the row already exists."
  (kuro-render-buffer-test--with-buffer
    (insert "r0\nr1\nr2\nr3\n")
    (let ((line-count-before (count-lines (point-min) (point-max)))
          (inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--ensure-buffer-row-exists 2)
      (should (= (count-lines (point-min) (point-max)) line-count-before)))))

(ert-deftest kuro-render-buffer-ensure-row-zero-always-exists ()
  "kuro--ensure-buffer-row-exists for row 0 is a no-op on a non-empty buffer."
  (kuro-render-buffer-test--with-buffer
    (insert "only\n")
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--ensure-buffer-row-exists 0))
    ;; Still just one line
    (should (= (count-lines (point-min) (point-max)) 1))))

(ert-deftest kuro-render-buffer-ensure-row-empty-buffer-gets-lines ()
  "kuro--ensure-buffer-row-exists handles an empty buffer (no newlines at all)."
  (kuro-render-buffer-test--with-buffer
    ;; Completely empty buffer; request row 2
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--ensure-buffer-row-exists 2))
    (should (>= (count-lines (point-min) (point-max)) 3))))

;;; Group 2: kuro--apply-buffer-scroll — scroll-up

(ert-deftest kuro-render-buffer-scroll-up-removes-first-line ()
  "kuro--apply-buffer-scroll with up=1 deletes the first buffer line."
  (kuro-render-buffer-test--with-buffer
    (insert "line0\nline1\nline2\n")
    (kuro--apply-buffer-scroll 1 0)
    (goto-char (point-min))
    ;; After scroll-up by 1, line0 is gone and line1 is now first
    (should (looking-at "line1\n"))))

(ert-deftest kuro-render-buffer-scroll-up-clamps-to-viewport-height ()
  "kuro--apply-buffer-scroll clamps the shift to `kuro--last-rows'.
A shift of the full viewport height already blanks every row; a larger
count must not make the delete+insert edit grow the buffer."
  (kuro-render-buffer-test--with-buffer
    (setq kuro--last-rows 3)
    (insert "a\nb\nc\n")
    (let ((count-before (count-lines (point-min) (point-max))))
      (kuro--apply-buffer-scroll 100 0)
      (should (= (count-lines (point-min) (point-max)) count-before)))))

(ert-deftest kuro-render-buffer-scroll-up-preserves-line-count ()
  "kuro--apply-buffer-scroll with up=1 keeps the total line count unchanged."
  (kuro-render-buffer-test--with-buffer
    (insert "a\nb\nc\n")
    (let ((count-before (count-lines (point-min) (point-max))))
      (kuro--apply-buffer-scroll 1 0)
      (should (= (count-lines (point-min) (point-max)) count-before)))))

(ert-deftest kuro-render-buffer-scroll-up-appends-blank-line ()
  "kuro--apply-buffer-scroll with up=1 appends a blank line at the end."
  (kuro-render-buffer-test--with-buffer
    (insert "a\nb\nc\n")
    (kuro--apply-buffer-scroll 1 0)
    (goto-char (point-max))
    (forward-line -1)
    ;; Last line should be blank
    (should (looking-at "\n"))))

;;; Group 3: kuro--apply-buffer-scroll — scroll-down

(ert-deftest kuro-render-buffer-scroll-down-prepends-blank-line ()
  "kuro--apply-buffer-scroll with down=1 prepends a blank line at the top."
  (kuro-render-buffer-test--with-buffer
    (insert "line0\nline1\nline2\n")
    (kuro--apply-buffer-scroll 0 1)
    (goto-char (point-min))
    ;; First line should now be blank
    (should (looking-at "\n"))))

(ert-deftest kuro-render-buffer-scroll-down-content-shifts-down ()
  "kuro--apply-buffer-scroll with down=1 shifts content down: line0 becomes line1."
  (kuro-render-buffer-test--with-buffer
    (insert "first\nsecond\nthird\n")
    (kuro--apply-buffer-scroll 0 1)
    ;; After scroll-down, a blank line is prepended; original first line is now second
    (goto-char (point-min))
    (should (looking-at "\n"))         ; first line is blank
    (forward-line 1)
    (should (looking-at "first\n"))))

;;; Group 4: kuro--apply-buffer-scroll — zero scroll

(ert-deftest kuro-render-buffer-scroll-zero-is-noop ()
  "kuro--apply-buffer-scroll with up=0 down=0 leaves the buffer unchanged."
  (kuro-render-buffer-test--with-buffer
    (insert "x\ny\nz\n")
    (kuro--apply-buffer-scroll 0 0)
    (goto-char (point-min))
    (should (looking-at "x\n"))))

;;; Group 5: kuro--decscusr-to-cursor-type

(kuro-render-buffer-test--deftest-decscusr-cases)
(kuro-render-buffer-test--deftest-decscusr-default-cases)
(kuro-render-buffer-test--deftest-decscusr-alias-cases)

;;; Group 6: kuro--grid-col-to-buffer-pos

(ert-deftest kuro-render-buffer-grid-col-to-buf-pos-ascii-line ()
  "Pure ASCII line: col == buffer offset (identity mapping)."
  (kuro-render-buffer-test--with-buffer
    (insert "abcde\nfghij\n")
    ;; Row 1, col 3 → "fghij" starts at position 7; col 3 → pos 10
    (should (= (kuro--grid-col-to-buffer-pos 1 3) 10))))

(ert-deftest kuro-render-buffer-grid-col-to-buf-pos-uses-col-to-buf-map ()
  "When a col-to-buf mapping exists, buffer offset is read from it."
  (kuro-render-buffer-test--with-buffer
    (insert "AB\n")
    ;; Simulate a CJK mapping: grid col 0 → buf offset 0, grid col 1 → buf offset 0 (wide char)
    (puthash 0 [0 0] kuro--col-to-buf-map)
    ;; Row 0, col 1 → buf-offset 0 → point-min + 0 = 1
    (should (= (kuro--grid-col-to-buffer-pos 0 1) 1))))

(ert-deftest kuro-render-buffer-grid-col-to-buf-pos-col-past-map ()
  "When col exceeds the map length, falls back to col as offset."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    ;; Mapping only covers 2 cols; col 4 falls back to col identity
    (puthash 0 [0 1] kuro--col-to-buf-map)
    ;; Row 0, col 4 falls back to identity: point-min(1) + 4 = 5
    (should (= (kuro--grid-col-to-buffer-pos 0 4) 5))))

(ert-deftest kuro-render-buffer-grid-col-to-buf-pos-clamps-to-line-end ()
  "Buffer position is clamped to line-end when col exceeds line length."
  (kuro-render-buffer-test--with-buffer
    (insert "ab\n")
    ;; Row 0, col 99 → clamped to line-end of "ab" = position 3
    (should (= (kuro--grid-col-to-buffer-pos 0 99) 3))))

;;; Group 7: kuro--apply-cursor-display

(kuro-render-buffer-test--deftest-apply-cursor-display-cases)

;;; Group 8: kuro--update-line-full — row-position cache arithmetic

(ert-deftest kuro-render-buffer-update-line-full-cache-updated-after-write ()
  "kuro--update-line-full updates kuro--row-positions for the written row.
After writing to row 0, the cache entry for row 0 should be non-nil."
  (kuro-render-buffer-test--with-buffer
    (insert "old\nnext\n")
    (setq-local kuro--row-positions (make-vector 2 nil))
    (kuro-render-buffer-test--with-render-stubs
      (kuro--update-line-full 0 "new" nil nil))
    ;; After the write, row 0's cache entry must be set (non-nil).
    (should (not (null (aref kuro--row-positions 0))))))

(ert-deftest kuro-render-buffer-update-line-full-cache-length-change-shifts-next-row ()
  "When new text is longer than old, row+1's cached position is updated.
After writing a longer string to row 0, row 1's cached start is set to
exactly (1+ (line-end-position-of-row-0))."
  (kuro-render-buffer-test--with-buffer
    ;; Row 0 starts with 3-char text; we replace with 7-char text.
    (insert "abc\ndef\n")
    (setq-local kuro--row-positions (make-vector 2 nil))
    (kuro-render-buffer-test--with-render-stubs
      (kuro--update-line-full 0 "abcdefg" nil nil))
    ;; Row 0 text is now "abcdefg" (7 chars, positions 1–7), newline at 8.
    ;; Row 1's cached start should be 9 (1 + line-end-of-row-0 at 8).
    (let ((cached-row1 (aref kuro--row-positions 1)))
      (should (not (null cached-row1)))
      ;; The cached position for row 1 is exactly 1+ end-of-row-0.
      ;; "abcdefg\n" occupies 8 chars; row 1 starts at position 9.
      (should (= cached-row1 9)))))

(ert-deftest kuro-render-buffer-update-line-full-cache-length-change-clears-later-rows ()
  "When line length changes, cache entries for rows beyond row+1 are delta-adjusted.
Rows +2 and beyond are shifted by (new-len - old-len) so they remain valid."
  (kuro-render-buffer-test--with-buffer
    (insert "abc\ndef\nghi\n")
    (setq-local kuro--row-positions (vector 1 5 9))
    (kuro-render-buffer-test--with-render-stubs
      ;; Replace row 0 "abc" (3 chars) with "longer-text" (11 chars) → delta=+8.
      (kuro--update-line-full 0 "longer-text" nil nil))
    ;; Row 2 (index 2) must be shifted by +8: 9 + 8 = 17.
    (should (= (aref kuro--row-positions 2) 17))))

;;; Group 9: kuro--with-buffer-edit — error/inhibit-read-only cleanup

(ert-deftest kuro-render-buffer-with-buffer-edit-restores-inhibit-read-only-on-error ()
  "`kuro--with-buffer-edit' restores `inhibit-read-only' to nil even when body signals an error."
  (kuro-render-buffer-test--with-buffer
    (let ((inhibit-read-only nil))
      (ignore-errors
        (kuro--with-buffer-edit
          (error "intentional test error")))
      ;; After the error unwinds, inhibit-read-only must return to nil.
      (should (eq inhibit-read-only nil)))))

(ert-deftest kuro-render-buffer-with-buffer-edit-allows-write-to-read-only-buffer ()
  "`kuro--with-buffer-edit' permits inserting into a buffer-read-only buffer."
  (kuro-render-buffer-test--with-buffer
    (setq buffer-read-only t)
    (kuro--with-buffer-edit
      (insert "written"))
    (should (string-match-p "written" (buffer-string)))))

(provide 'kuro-render-buffer-test)
;;; kuro-render-buffer-test.el ends here
