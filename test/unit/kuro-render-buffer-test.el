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
(require 'kuro-render-buffer)

;;; Helpers

(defmacro kuro-render-buffer-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer with render-buffer state initialized."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (inhibit-modification-hooks t)
           (kuro--initialized nil)
           (kuro--scroll-offset 0)
           (kuro--last-rows 24)
           (kuro--col-to-buf-map (make-hash-table :test 'eql))
           (kuro--blink-overlays-by-row nil)
           kuro--blink-overlays
           kuro--image-overlays)
       ,@body)))

(defun kuro-render-buffer-test--line-count (buf)
  "Return the number of lines in BUF."
  (with-current-buffer buf
    (count-lines (point-min) (point-max))))

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

(ert-deftest kuro-render-buffer-decscusr-0-is-box ()
  "DECSCUSR 0 (default) returns box cursor."
  (should (eq (kuro--decscusr-to-cursor-type 0) 'box)))

(ert-deftest kuro-render-buffer-decscusr-1-is-box ()
  "DECSCUSR 1 (blinking block) returns box cursor."
  (should (eq (kuro--decscusr-to-cursor-type 1) 'box)))

(ert-deftest kuro-render-buffer-decscusr-2-is-box ()
  "DECSCUSR 2 (steady block) returns box cursor."
  (should (eq (kuro--decscusr-to-cursor-type 2) 'box)))

(ert-deftest kuro-render-buffer-decscusr-3-is-hbar ()
  "DECSCUSR 3 (blinking underline) returns hbar cursor of height 2."
  (should (equal (kuro--decscusr-to-cursor-type 3) '(hbar . 2))))

(ert-deftest kuro-render-buffer-decscusr-4-is-hbar ()
  "DECSCUSR 4 (steady underline) returns hbar cursor of height 2."
  (should (equal (kuro--decscusr-to-cursor-type 4) '(hbar . 2))))

(ert-deftest kuro-render-buffer-decscusr-5-is-bar ()
  "DECSCUSR 5 (blinking bar/I-beam) returns bar cursor of width 2."
  (should (equal (kuro--decscusr-to-cursor-type 5) '(bar . 2))))

(ert-deftest kuro-render-buffer-decscusr-6-is-bar ()
  "DECSCUSR 6 (steady bar/I-beam) returns bar cursor of width 2."
  (should (equal (kuro--decscusr-to-cursor-type 6) '(bar . 2))))

(ert-deftest kuro-render-buffer-decscusr-unknown-defaults-to-box ()
  "Unknown DECSCUSR value falls through to box cursor (safe default)."
  (should (eq (kuro--decscusr-to-cursor-type 99) 'box))
  (should (eq (kuro--decscusr-to-cursor-type 7) 'box))
  (should (eq (kuro--decscusr-to-cursor-type -1) 'box)))

(ert-deftest kuro-render-buffer-decscusr-0-and-1-return-same ()
  "DECSCUSR 0 and 1 are aliases; both return identical cursor types."
  (should (equal (kuro--decscusr-to-cursor-type 0)
                 (kuro--decscusr-to-cursor-type 1))))

(ert-deftest kuro-render-buffer-decscusr-3-and-4-return-same ()
  "DECSCUSR 3 and 4 are aliases; both return identical cursor types."
  (should (equal (kuro--decscusr-to-cursor-type 3)
                 (kuro--decscusr-to-cursor-type 4))))

(ert-deftest kuro-render-buffer-decscusr-5-and-6-return-same ()
  "DECSCUSR 5 and 6 are aliases; both return identical cursor types."
  (should (equal (kuro--decscusr-to-cursor-type 5)
                 (kuro--decscusr-to-cursor-type 6))))

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

(ert-deftest kuro-render-buffer-apply-cursor-display-visible-shape-0 ()
  "Visible cursor with shape 0 sets cursor-type to box."
  (kuro-render-buffer-test--with-buffer
    (kuro--apply-cursor-display t 0)
    (should (eq cursor-type 'box))))

(ert-deftest kuro-render-buffer-apply-cursor-display-visible-shape-3 ()
  "Visible cursor with shape 3 (blinking underline) sets hbar cursor."
  (kuro-render-buffer-test--with-buffer
    (kuro--apply-cursor-display t 3)
    (should (equal cursor-type '(hbar . 2)))))

(ert-deftest kuro-render-buffer-apply-cursor-display-hidden ()
  "Hidden cursor (DECTCEM off) sets cursor-type to nil."
  (kuro-render-buffer-test--with-buffer
    (setq-local cursor-type 'box)
    (kuro--apply-cursor-display nil 0)
    (should-not cursor-type)))

(ert-deftest kuro-render-buffer-apply-cursor-display-nil-shape-defaults-to-box ()
  "Nil shape (missing DECSCUSR) defaults to shape 0 (box)."
  (kuro-render-buffer-test--with-buffer
    (kuro--apply-cursor-display t nil)
    (should (eq cursor-type 'box))))

;;; Group 8: kuro--anchor-window-at-pos

(ert-deftest kuro-render-buffer-anchor-window-sets-window-point ()
  "`kuro--anchor-window-at-pos' moves the window point to target-pos."
  (kuro-render-buffer-test--with-buffer
    (insert "row0\nrow1\nrow2\n")
    (let* ((win (selected-window)))
      (set-window-buffer win (current-buffer))
      (kuro--anchor-window-at-pos win 6)
      (should (= (window-point win) 6)))))

;;; Group 9: kuro--clear-line-blink-overlays

(ert-deftest kuro-render-buffer-clear-blink-overlays-noop-when-no-overlays ()
  "kuro--clear-line-blink-overlays is a no-op when kuro--blink-overlays is nil."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    (should-not (condition-case err
                    (progn (kuro--clear-line-blink-overlays (point-min)) nil)
                  (error err)))))

(ert-deftest kuro-render-buffer-clear-blink-overlays-removes-in-range ()
  "Overlays within the current line are deleted and removed from the list."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\nworld\n")
    (let ((ov (make-overlay 1 5)))
      (setq kuro--blink-overlays (list ov))
      (goto-char (point-min))
      (kuro--clear-line-blink-overlays 1)
      (should (null (overlay-buffer ov)))
      (should (null kuro--blink-overlays)))))

(ert-deftest kuro-render-buffer-clear-blink-overlays-preserves-out-of-range ()
  "Overlays outside the current line are retained."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\nworld\n")
    ;; Overlay on second line (positions 7–11); clear from line-start=1 (first line).
    (let ((ov (make-overlay 7 11)))
      (setq kuro--blink-overlays (list ov))
      (goto-char (point-min))
      (kuro--clear-line-blink-overlays 1)
      (should (= (length kuro--blink-overlays) 1))
      (should (eq (car kuro--blink-overlays) ov)))))

;;; Group 10: kuro--apply-face-ranges

(ert-deftest kuro-render-buffer-apply-face-ranges-noop-when-nil ()
  "kuro--apply-face-ranges with nil face-ranges does nothing."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    (should-not (condition-case err
                    (progn (kuro--apply-face-ranges nil 1 6) nil)
                  (error err)))))

(ert-deftest kuro-render-buffer-apply-face-ranges-calls-apply-ffi-face ()
  "kuro--apply-face-ranges calls kuro--apply-ffi-face-at for each valid range."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    (let ((calls nil))
      (cl-letf (((symbol-function 'kuro--apply-ffi-face-at)
                 (lambda (s e fg bg fl _ul) (push (list s e fg bg fl) calls))))
        ;; range (0 3 1 0 0 0): start-pos = min(1+0,6) = 1, end-pos = min(1+3,6) = 4
        (kuro--apply-face-ranges '((0 3 1 0 0 0)) 1 6)
        (should (= (length calls) 1))
        (should (equal (car calls) '(1 4 1 0 0)))))))

(ert-deftest kuro-render-buffer-apply-face-ranges-skips-zero-width ()
  "kuro--apply-face-ranges skips ranges where start-pos >= end-pos."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    (let ((calls nil))
      (cl-letf (((symbol-function 'kuro--apply-ffi-face-at)
                 (lambda (s e fg bg fl _ul) (push (list s e fg bg fl) calls))))
        ;; start-buf=3 end-buf=3 → start-pos=end-pos → no call
        (kuro--apply-face-ranges '((3 3 1 0 0 0)) 1 6)
        (should (null calls))))))

(ert-deftest kuro-render-buffer-apply-face-ranges-clamps-to-line-end ()
  "kuro--apply-face-ranges clamps start-pos and end-pos to line-end."
  (kuro-render-buffer-test--with-buffer
    (insert "ab\n")
    ;; line-start=1, line-end=3 ("ab" occupies positions 1-2, newline at 3)
    (let ((calls nil))
      (cl-letf (((symbol-function 'kuro--apply-ffi-face-at)
                 (lambda (s e fg bg fl _ul) (push (list s e fg bg fl) calls))))
        ;; range (0 99 1 0 0 0): end-pos = min(1+99, 3) = 3
        (kuro--apply-face-ranges '((0 99 1 0 0 0)) 1 3)
        (should (= (length calls) 1))
        (should (= (nth 1 (car calls)) 3))))))

;;; Group 11: kuro--scroll-lines

(ert-deftest kuro-render-buffer-scroll-lines-up-removes-top-line ()
  "kuro--scroll-lines \\='up removes the first line from the buffer."
  (kuro-render-buffer-test--with-buffer
    (insert "line0\nline1\nline2\n")
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--scroll-lines 'up 1 3))
    (goto-char (point-min))
    (should (looking-at "line1\n"))))

(ert-deftest kuro-render-buffer-scroll-lines-up-appends-blank-line ()
  "kuro--scroll-lines \\='up appends a blank line at the bottom."
  (kuro-render-buffer-test--with-buffer
    (insert "line0\nline1\nline2\n")
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--scroll-lines 'up 1 3))
    (goto-char (point-max))
    (forward-line -1)
    (should (looking-at "\n"))))

(ert-deftest kuro-render-buffer-scroll-lines-up-preserves-line-count ()
  "kuro--scroll-lines \\='up keeps total line count unchanged."
  (kuro-render-buffer-test--with-buffer
    (insert "a\nb\nc\n")
    (let ((count-before (count-lines (point-min) (point-max)))
          (inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--scroll-lines 'up 1 3)
      (should (= (count-lines (point-min) (point-max)) count-before)))))

(ert-deftest kuro-render-buffer-scroll-lines-down-prepends-blank-line ()
  "kuro--scroll-lines \\='down prepends a blank line at the top."
  (kuro-render-buffer-test--with-buffer
    (insert "line0\nline1\nline2\n")
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--scroll-lines 'down 1 3))
    (goto-char (point-min))
    (should (looking-at "\n"))))

(ert-deftest kuro-render-buffer-scroll-lines-down-shifts-content-down ()
  "kuro--scroll-lines \\='down shifts content down: original line0 becomes line1."
  (kuro-render-buffer-test--with-buffer
    (insert "first\nsecond\nthird\n")
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--scroll-lines 'down 1 3))
    (goto-char (point-min))
    (should (looking-at "\n"))
    (forward-line 1)
    (should (looking-at "first\n"))))

(ert-deftest kuro-render-buffer-scroll-lines-down-removes-last-line ()
  "kuro--scroll-lines \\='down removes the last buffer line."
  (kuro-render-buffer-test--with-buffer
    (insert "line0\nline1\nline2\n")
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--scroll-lines 'down 1 3))
    ;; "line2" must no longer be present
    (should-not (save-excursion
                  (goto-char (point-min))
                  (search-forward "line2" nil t)))))

(ert-deftest kuro-render-buffer-apply-buffer-scroll-delegates-up ()
  "kuro--apply-buffer-scroll with up>0 delegates to kuro--scroll-lines \\='up."
  (kuro-render-buffer-test--with-buffer
    (insert "line0\nline1\nline2\n")
    (let ((calls nil))
      (cl-letf (((symbol-function 'kuro--scroll-lines)
                 (lambda (dir n lr) (push (list dir n lr) calls))))
        (kuro--apply-buffer-scroll 2 0)
        (should (= (length calls) 1))
        (should (equal (car calls) (list 'up 2 kuro--last-rows)))))))

(ert-deftest kuro-render-buffer-apply-buffer-scroll-delegates-down ()
  "kuro--apply-buffer-scroll with down>0 delegates to kuro--scroll-lines \\='down."
  (kuro-render-buffer-test--with-buffer
    (insert "line0\nline1\nline2\n")
    (let ((calls nil))
      (cl-letf (((symbol-function 'kuro--scroll-lines)
                 (lambda (dir n lr) (push (list dir n lr) calls))))
        (kuro--apply-buffer-scroll 0 2)
        (should (= (length calls) 1))
        (should (equal (car calls) (list 'down 2 kuro--last-rows)))))))

(ert-deftest kuro-render-buffer-apply-buffer-scroll-zero-skips-scroll-lines ()
  "kuro--apply-buffer-scroll with up=0 down=0 never calls kuro--scroll-lines."
  (kuro-render-buffer-test--with-buffer
    (insert "x\ny\nz\n")
    (let ((calls nil))
      (cl-letf (((symbol-function 'kuro--scroll-lines)
                 (lambda (dir n lr) (push (list dir n lr) calls))))
        (kuro--apply-buffer-scroll 0 0)
        (should (null calls))))))

;;; Group 12: kuro--clear-row-overlays

(ert-deftest kuro-render-buffer-clear-row-overlays-removes-blink-on-row ()
  "kuro--clear-row-overlays removes blink overlays on the target row."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\nworld\n")
    ;; Overlay on row 0 (positions 1–5)
    (let ((ov (make-overlay 1 5)))
      (setq kuro--blink-overlays (list ov))
      ;; Position point at row 0 (as kuro--ensure-buffer-row-exists would)
      (goto-char (point-min))
      (forward-line 0)
      (kuro--clear-row-overlays 0)
      (should (null (overlay-buffer ov)))
      (should (null kuro--blink-overlays)))))

(ert-deftest kuro-render-buffer-clear-row-overlays-keeps-overlays-on-other-rows ()
  "kuro--clear-row-overlays does not touch overlays on other rows."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\nworld\n")
    ;; Overlay on row 1 (positions 7–11); clear row 0
    (let ((ov (make-overlay 7 11)))
      (setq kuro--blink-overlays (list ov))
      ;; Position point at row 0
      (goto-char (point-min))
      (forward-line 0)
      (kuro--clear-row-overlays 0)
      ;; Overlay on row 1 must be untouched
      (should (= (length kuro--blink-overlays) 1))
      (should (eq (car kuro--blink-overlays) ov)))))

;;; Group 13: kuro--store-col-to-buf

(ert-deftest kuro-render-buffer-store-col-to-buf-stores-vector ()
  "kuro--store-col-to-buf stores a non-empty vector in the hash table."
  (kuro-render-buffer-test--with-buffer
    (let ((mapping [0 1 2]))
      (kuro--store-col-to-buf 3 mapping)
      (should (equal (gethash 3 kuro--col-to-buf-map) mapping)))))

(ert-deftest kuro-render-buffer-store-col-to-buf-removes-nil ()
  "kuro--store-col-to-buf removes existing entry when given nil."
  (kuro-render-buffer-test--with-buffer
    ;; Pre-populate row 2 with a mapping
    (puthash 2 [0 1] kuro--col-to-buf-map)
    (should (gethash 2 kuro--col-to-buf-map))
    (kuro--store-col-to-buf 2 nil)
    (should (null (gethash 2 kuro--col-to-buf-map)))))

(ert-deftest kuro-render-buffer-store-col-to-buf-removes-empty-vector ()
  "kuro--store-col-to-buf removes an existing entry when given an empty vector.
An empty vector is functionally equivalent to absent (identity fallback),
so storing it would waste hash table space without any semantic benefit."
  (kuro-render-buffer-test--with-buffer
    ;; Pre-populate so we can confirm the remhash actually fires.
    (puthash 5 [1 2 3] kuro--col-to-buf-map)
    (kuro--store-col-to-buf 5 [])
    (should (null (gethash 5 kuro--col-to-buf-map)))))

;;; Group 14: kuro--with-buffer-edit

(ert-deftest kuro-render-buffer-with-buffer-edit-sets-inhibit-read-only ()
  "`kuro--with-buffer-edit' binds `inhibit-read-only' to t inside its body."
  (kuro-render-buffer-test--with-buffer
    (let (captured)
      (kuro--with-buffer-edit
        (setq captured inhibit-read-only))
      (should (eq captured t)))))

(ert-deftest kuro-render-buffer-with-buffer-edit-sets-inhibit-modification-hooks ()
  "`kuro--with-buffer-edit' binds `inhibit-modification-hooks' to t inside its body."
  (kuro-render-buffer-test--with-buffer
    (let (captured)
      (kuro--with-buffer-edit
        (setq captured inhibit-modification-hooks))
      (should (eq captured t)))))

(ert-deftest kuro-render-buffer-with-buffer-edit-restores-inhibit-read-only ()
  "`kuro--with-buffer-edit' restores `inhibit-read-only' to its prior value on exit."
  (kuro-render-buffer-test--with-buffer
    (let ((inhibit-read-only nil))
      (kuro--with-buffer-edit
        (ignore))
      (should (eq inhibit-read-only nil)))))

(ert-deftest kuro-render-buffer-with-buffer-edit-restores-inhibit-modification-hooks ()
  "`kuro--with-buffer-edit' restores `inhibit-modification-hooks' to its prior value on exit."
  (kuro-render-buffer-test--with-buffer
    (let ((inhibit-modification-hooks nil))
      (kuro--with-buffer-edit
        (ignore))
      (should (eq inhibit-modification-hooks nil)))))

(ert-deftest kuro-render-buffer-with-buffer-edit-restores-point ()
  "`kuro--with-buffer-edit' restores point to its pre-body value on exit."
  (kuro-render-buffer-test--with-buffer
    (insert "abc\ndef\n")
    (goto-char (point-min))
    (let ((pos-before (point)))
      (kuro--with-buffer-edit
        (goto-char (point-max)))
      (should (= (point) pos-before)))))

(ert-deftest kuro-render-buffer-with-buffer-edit-allows-buffer-modification ()
  "`kuro--with-buffer-edit' permits inserting into a read-only buffer."
  (kuro-render-buffer-test--with-buffer
    (setq buffer-read-only t)
    (kuro--with-buffer-edit
      (insert "x"))
    (should (string-match-p "x" (buffer-string)))))

;;; Group 15: kuro--update-line-full

(ert-deftest kuro-render-buffer-update-line-full-replaces-text ()
  "kuro--update-line-full replaces the text on the target row."
  (kuro-render-buffer-test--with-buffer
    (insert "original\n")
    (cl-letf (((symbol-function 'kuro--apply-ffi-face-at) #'ignore)
              ((symbol-function 'kuro--clear-row-image-overlays) #'ignore))
      (kuro--update-line-full 0 "replaced" nil nil))
    (goto-char (point-min))
    (should (looking-at "replaced\n"))))

(ert-deftest kuro-render-buffer-update-line-full-nil-text-is-noop ()
  "kuro--update-line-full with nil text does not modify the buffer."
  (kuro-render-buffer-test--with-buffer
    (insert "keep\n")
    (kuro--update-line-full 0 nil nil nil)
    (goto-char (point-min))
    (should (looking-at "keep\n"))))

(ert-deftest kuro-render-buffer-update-line-full-applies-face-ranges ()
  "kuro--update-line-full calls kuro--apply-ffi-face-at for each face range."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    (let ((face-calls 0))
      (cl-letf (((symbol-function 'kuro--apply-ffi-face-at)
                 (lambda (_s _e _fg _bg _fl _ul) (cl-incf face-calls)))
                ((symbol-function 'kuro--clear-row-image-overlays) #'ignore))
        ;; A single face range: start=0, end=5, fg=0, bg=0, flags=0, ul=0
        (kuro--update-line-full 0 "hello" '((0 5 0 0 0 0)) nil))
      (should (= face-calls 1)))))

(ert-deftest kuro-render-buffer-update-line-full-stores-col-to-buf ()
  "kuro--update-line-full stores the col-to-buf vector in kuro--col-to-buf-map."
  (kuro-render-buffer-test--with-buffer
    (insert "abc\n")
    (let ((vec (vector 0 1 2)))
      (cl-letf (((symbol-function 'kuro--apply-ffi-face-at) #'ignore)
                ((symbol-function 'kuro--clear-row-image-overlays) #'ignore))
        (kuro--update-line-full 0 "abc" nil vec))
      (should (equal (gethash 0 kuro--col-to-buf-map) vec)))))

(ert-deftest kuro-render-buffer-update-line-full-non-integer-row-is-noop ()
  "kuro--update-line-full with a non-integer row does not modify the buffer."
  (kuro-render-buffer-test--with-buffer
    (insert "keep\n")
    (kuro--update-line-full nil "replaced" nil nil)
    (goto-char (point-min))
    (should (looking-at "keep\n"))))

;;; Group 16: kuro--update-cursor

(defmacro kuro-render-buffer-cursor-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer with cursor-update state initialized."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (inhibit-modification-hooks t)
           (kuro--scroll-offset 0)
           (kuro--col-to-buf-map (make-hash-table :test 'eql))
           kuro--cursor-marker
           kuro--last-cursor-row
           kuro--last-cursor-col
           kuro--last-cursor-visible
           kuro--last-cursor-shape
           kuro--blink-overlays
           kuro--image-overlays)
       ,@body)))

(ert-deftest kuro-render-buffer-update-cursor-moves-marker-to-position ()
  "kuro--update-cursor sets kuro--cursor-marker to the grid (row,col) buffer position."
  (kuro-render-buffer-cursor-test--with-buffer
    (insert "row0\nrow1\nrow2\n")
    (setq kuro--cursor-marker (point-marker))
    ;; row=1, col=2, visible=t, shape=0 → "row1\n" starts at pos 6, col 2 → pos 8
    (cl-letf (((symbol-function 'kuro--get-cursor-state) (lambda () '(1 2 t 0)))
              ((symbol-function 'get-buffer-window) (lambda (&rest _) (selected-window))))
      (kuro--update-cursor))
    (should (= (marker-position kuro--cursor-marker) 8))))

(ert-deftest kuro-render-buffer-update-cursor-hidden-sets-cursor-type-nil ()
  "kuro--update-cursor sets cursor-type to nil when cursor is hidden."
  (kuro-render-buffer-cursor-test--with-buffer
    (insert "line\n")
    (setq kuro--cursor-marker (point-marker))
    (cl-letf (((symbol-function 'kuro--get-cursor-state) (lambda () '(0 0 nil 0)))
              ((symbol-function 'get-buffer-window) (lambda (&rest _) (selected-window))))
      (kuro--update-cursor))
    (should-not cursor-type)))

(ert-deftest kuro-render-buffer-update-cursor-visible-sets-cursor-type ()
  "kuro--update-cursor sets cursor-type to a non-nil value when cursor is visible."
  (kuro-render-buffer-cursor-test--with-buffer
    (insert "line\n")
    (setq kuro--cursor-marker (point-marker))
    (cl-letf (((symbol-function 'kuro--get-cursor-state) (lambda () '(0 0 t 0)))
              ((symbol-function 'get-buffer-window) (lambda (&rest _) (selected-window))))
      (kuro--update-cursor))
    (should cursor-type)))

(ert-deftest kuro-render-buffer-update-cursor-skips-when-scroll-offset-positive ()
  "kuro--update-cursor is a no-op when kuro--scroll-offset > 0 (viewport scrolled)."
  (kuro-render-buffer-cursor-test--with-buffer
    (insert "line\n")
    (setq kuro--cursor-marker (copy-marker (point-min))
          kuro--scroll-offset 5)
    (let ((state-calls 0))
      (cl-letf (((symbol-function 'kuro--get-cursor-state)
                 (lambda () (cl-incf state-calls) '(0 0 t 0))))
        (kuro--update-cursor)
        (should (= state-calls 0))))))

(ert-deftest kuro-render-buffer-update-cursor-caches-state-and-skips-on-repeat ()
  "kuro--update-cursor skips buffer-position work when cursor state is unchanged."
  (kuro-render-buffer-cursor-test--with-buffer
    (insert "hello\n")
    (setq kuro--cursor-marker (point-marker)
          kuro--last-cursor-row     0
          kuro--last-cursor-col     0
          kuro--last-cursor-visible t
          kuro--last-cursor-shape   0)
    (let ((apply-calls 0))
      (cl-letf (((symbol-function 'kuro--get-cursor-state) (lambda () '(0 0 t 0)))
                ((symbol-function 'get-buffer-window) (lambda (&rest _) (selected-window)))
                ((symbol-function 'kuro--anchor-window-at-pos) #'ignore)
                ((symbol-function 'kuro--apply-cursor-display)
                 (lambda (_v _s) (cl-incf apply-calls))))
        (kuro--update-cursor)
        ;; State unchanged → apply-cursor-display must NOT be called
        (should (= apply-calls 0))))))

;;; Group 17: kuro--scroll-lines — zero-count no-op and multi-step
;; ------------------------------------------------------------

(ert-deftest kuro-render-buffer-scroll-lines-up-zero-is-noop ()
  "kuro--scroll-lines 'up with n=0 leaves the buffer unchanged."
  (kuro-render-buffer-test--with-buffer
    (insert "a\nb\nc\n")
    (let ((content-before (buffer-string))
          (inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--scroll-lines 'up 0 3)
      (should (string= (buffer-string) content-before)))))

(ert-deftest kuro-render-buffer-scroll-lines-down-zero-is-noop ()
  "kuro--scroll-lines 'down with n=0 leaves the buffer unchanged."
  (kuro-render-buffer-test--with-buffer
    (insert "a\nb\nc\n")
    (let ((content-before (buffer-string))
          (inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--scroll-lines 'down 0 3)
      (should (string= (buffer-string) content-before)))))

(ert-deftest kuro-render-buffer-scroll-lines-up-multiple-steps ()
  "kuro--scroll-lines 'up with n=2 removes the first two lines."
  (kuro-render-buffer-test--with-buffer
    (insert "line0\nline1\nline2\nline3\n")
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--scroll-lines 'up 2 4))
    (goto-char (point-min))
    (should (looking-at "line2\n"))))

(ert-deftest kuro-render-buffer-scroll-lines-down-multiple-steps ()
  "kuro--scroll-lines 'down with n=2 removes the last two lines and prepends two blanks."
  (kuro-render-buffer-test--with-buffer
    (insert "line0\nline1\nline2\nline3\n")
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--scroll-lines 'down 2 4))
    (goto-char (point-min))
    ;; Two blank lines prepended
    (should (looking-at "\n"))
    (forward-line 1)
    (should (looking-at "\n"))
    ;; line2 and line3 are gone
    (should-not (save-excursion
                  (goto-char (point-min))
                  (search-forward "line2" nil t)))))

;;; Group 18: kuro--apply-buffer-scroll — col-to-buf-map clearing
;; ------------------------------------------------------------

(ert-deftest kuro-render-buffer-apply-buffer-scroll-up-clears-col-to-buf-map ()
  "kuro--apply-buffer-scroll clears kuro--col-to-buf-map after a scroll-up."
  (kuro-render-buffer-test--with-buffer
    (insert "a\nb\nc\n")
    (puthash 0 [0 1 2] kuro--col-to-buf-map)
    (puthash 1 [0 1] kuro--col-to-buf-map)
    (kuro--apply-buffer-scroll 1 0)
    (should (zerop (hash-table-count kuro--col-to-buf-map)))))

(ert-deftest kuro-render-buffer-apply-buffer-scroll-down-clears-col-to-buf-map ()
  "kuro--apply-buffer-scroll clears kuro--col-to-buf-map after a scroll-down."
  (kuro-render-buffer-test--with-buffer
    (insert "a\nb\nc\n")
    (puthash 2 [0 1] kuro--col-to-buf-map)
    (kuro--apply-buffer-scroll 0 1)
    (should (zerop (hash-table-count kuro--col-to-buf-map)))))

(ert-deftest kuro-render-buffer-apply-buffer-scroll-zero-does-not-clear-map ()
  "kuro--apply-buffer-scroll with zero counts does not clear kuro--col-to-buf-map."
  (kuro-render-buffer-test--with-buffer
    (insert "a\nb\n")
    (puthash 0 [0 1] kuro--col-to-buf-map)
    (kuro--apply-buffer-scroll 0 0)
    (should (= (hash-table-count kuro--col-to-buf-map) 1))))

;;; Group 19: kuro--store-col-to-buf — nil-with-non-integer-row guard and overwrite
;; ------------------------------------------------------------

(ert-deftest kuro-render-buffer-store-col-to-buf-nil-non-integer-row-is-noop ()
  "kuro--store-col-to-buf with nil col-to-buf and a non-integer row does not remove anything.
The guard `(when (and (integerp row) (null col-to-buf)))' rejects non-integer rows."
  (kuro-render-buffer-test--with-buffer
    (puthash 'foo [0 1] kuro--col-to-buf-map)
    (kuro--store-col-to-buf 'foo nil)
    ;; Non-integer key: the remhash branch is skipped; entry stays
    (should (equal (gethash 'foo kuro--col-to-buf-map) [0 1]))))

(ert-deftest kuro-render-buffer-store-col-to-buf-overwrites-existing-vector ()
  "kuro--store-col-to-buf replaces an existing vector entry with a new one."
  (kuro-render-buffer-test--with-buffer
    (puthash 0 [0 1 2] kuro--col-to-buf-map)
    (let ((new-vec [0 0 1]))
      (kuro--store-col-to-buf 0 new-vec)
      (should (equal (gethash 0 kuro--col-to-buf-map) new-vec)))))

(ert-deftest kuro-render-buffer-store-col-to-buf-nil-row-without-entry-is-noop ()
  "kuro--store-col-to-buf with nil col-to-buf and no existing entry is a no-op."
  (kuro-render-buffer-test--with-buffer
    (kuro--store-col-to-buf 7 nil)
    (should (null (gethash 7 kuro--col-to-buf-map)))))

;;; Group 20: kuro--clear-line-blink-overlays — dead-overlay handling
;; ------------------------------------------------------------

(ert-deftest kuro-render-buffer-clear-blink-overlays-skips-dead-overlay ()
  "Dead overlays (overlay-buffer returns nil) are kept in the list without crashing.
A dead overlay passes the (overlay-buffer ov) guard as falsy so it lands in
the `remaining' list rather than being deleted again."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    (let ((dead-ov (make-overlay 1 3)))
      (delete-overlay dead-ov)          ; make it dead
      (setq kuro--blink-overlays (list dead-ov))
      (goto-char (point-min))
      ;; Must not signal an error
      (should-not (condition-case err
                      (progn (kuro--clear-line-blink-overlays 1) nil)
                    (error err)))
      ;; Dead overlay ends up in remaining (the guard `(overlay-buffer ov)' is nil)
      (should (= (length kuro--blink-overlays) 1)))))

(ert-deftest kuro-render-buffer-clear-blink-overlays-mixed-live-dead ()
  "Live overlay in range is deleted; dead overlay is kept; out-of-range live overlay is kept."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\nworld\n")
    (let ((live-in-range  (make-overlay 1 5))
          (dead-ov        (make-overlay 1 3))
          (live-other-row (make-overlay 7 11)))
      (delete-overlay dead-ov)
      (setq kuro--blink-overlays (list live-in-range dead-ov live-other-row))
      (goto-char (point-min))
      (kuro--clear-line-blink-overlays 1)
      ;; live-in-range was deleted
      (should (null (overlay-buffer live-in-range)))
      ;; remaining: dead-ov + live-other-row (order determined by nreverse)
      (should (= (length kuro--blink-overlays) 2)))))

;;; Group 21: kuro--update-cursor — nil state, cache update
;; ------------------------------------------------------------

(ert-deftest kuro-render-buffer-update-cursor-nil-state-is-noop ()
  "kuro--update-cursor is a no-op when kuro--get-cursor-state returns nil."
  (kuro-render-buffer-cursor-test--with-buffer
    (insert "line\n")
    (setq kuro--cursor-marker (copy-marker (point-min)))
    (let ((apply-calls 0))
      (cl-letf (((symbol-function 'kuro--get-cursor-state) (lambda () nil))
                ((symbol-function 'kuro--apply-cursor-display)
                 (lambda (_v _s) (cl-incf apply-calls))))
        (kuro--update-cursor)
        (should (= apply-calls 0))))))

(ert-deftest kuro-render-buffer-update-cursor-updates-cached-row-col ()
  "kuro--update-cursor updates kuro--last-cursor-row and kuro--last-cursor-col on change."
  (kuro-render-buffer-cursor-test--with-buffer
    (insert "row0\nrow1\n")
    (setq kuro--cursor-marker (point-marker))
    (cl-letf (((symbol-function 'kuro--get-cursor-state) (lambda () '(1 3 t 0)))
              ((symbol-function 'get-buffer-window) (lambda (&rest _) (selected-window))))
      (kuro--update-cursor))
    (should (eql kuro--last-cursor-row 1))
    (should (eql kuro--last-cursor-col 3))))

(ert-deftest kuro-render-buffer-update-cursor-updates-cached-visible-shape ()
  "kuro--update-cursor updates kuro--last-cursor-visible and kuro--last-cursor-shape."
  (kuro-render-buffer-cursor-test--with-buffer
    (insert "line\n")
    (setq kuro--cursor-marker (point-marker))
    (cl-letf (((symbol-function 'kuro--get-cursor-state) (lambda () '(0 0 nil 5)))
              ((symbol-function 'get-buffer-window) (lambda (&rest _) (selected-window))))
      (kuro--update-cursor))
    (should (eq kuro--last-cursor-visible nil))
    (should (eql kuro--last-cursor-shape 5))))

(ert-deftest kuro-render-buffer-update-cursor-unchanged-still-anchors-window ()
  "kuro--update-cursor re-anchors the window even when cursor state is unchanged.
The TUI distortion fix ensures every frame re-anchors the viewport at point-min
to prevent Emacs' native redisplay from drifting between render cycles."
  (kuro-render-buffer-cursor-test--with-buffer
    (insert "hello\nworld\n")
    (setq kuro--cursor-marker (copy-marker 3))
    (setq kuro--last-cursor-row     0
          kuro--last-cursor-col     2
          kuro--last-cursor-visible t
          kuro--last-cursor-shape   0)
    (let ((anchor-calls 0)
          (apply-calls 0))
      (cl-letf (((symbol-function 'kuro--get-cursor-state) (lambda () '(0 2 t 0)))
                ((symbol-function 'get-buffer-window) (lambda (&rest _) (selected-window)))
                ((symbol-function 'kuro--anchor-window-at-pos)
                 (lambda (_win _pos) (cl-incf anchor-calls)))
                ((symbol-function 'kuro--apply-cursor-display)
                 (lambda (_v _s) (cl-incf apply-calls))))
        (kuro--update-cursor)
        (should (= anchor-calls 1))
        (should (= apply-calls 0))))))

(ert-deftest kuro-render-buffer-update-cursor-unchanged-uses-marker-position ()
  "When cursor is unchanged and marker exists, anchor receives marker position.
kuro--grid-col-to-buffer-pos must NOT be called — the marker is the fast path."
  (kuro-render-buffer-cursor-test--with-buffer
    (insert "hello\nworld\n")
    (setq kuro--cursor-marker (copy-marker 8))
    (setq kuro--last-cursor-row     1
          kuro--last-cursor-col     1
          kuro--last-cursor-visible t
          kuro--last-cursor-shape   0)
    (let ((anchor-pos nil)
          (grid-col-calls 0))
      (cl-letf (((symbol-function 'kuro--get-cursor-state) (lambda () '(1 1 t 0)))
                ((symbol-function 'get-buffer-window) (lambda (&rest _) (selected-window)))
                ((symbol-function 'kuro--anchor-window-at-pos)
                 (lambda (_win pos) (setq anchor-pos pos)))
                ((symbol-function 'kuro--grid-col-to-buffer-pos)
                 (lambda (_r _c) (cl-incf grid-col-calls) 99)))
        (kuro--update-cursor)
        (should (= anchor-pos 8))
        (should (= grid-col-calls 0))))))

(ert-deftest kuro-render-buffer-update-cursor-unchanged-falls-back-without-marker ()
  "When cursor is unchanged but marker is nil, anchor uses grid-col-to-buffer-pos."
  (kuro-render-buffer-cursor-test--with-buffer
    (insert "hello\n")
    (setq kuro--cursor-marker nil)
    (setq kuro--last-cursor-row     0
          kuro--last-cursor-col     3
          kuro--last-cursor-visible t
          kuro--last-cursor-shape   0)
    (let ((anchor-pos nil))
      (cl-letf (((symbol-function 'kuro--get-cursor-state) (lambda () '(0 3 t 0)))
                ((symbol-function 'get-buffer-window) (lambda (&rest _) (selected-window)))
                ((symbol-function 'kuro--anchor-window-at-pos)
                 (lambda (_win pos) (setq anchor-pos pos)))
                ((symbol-function 'kuro--grid-col-to-buffer-pos)
                 (lambda (_r _c) 42)))
        (kuro--update-cursor)
        (should (= anchor-pos 42))))))

(ert-deftest kuro-render-buffer-update-cursor-partial-cache-miss-triggers-update ()
  "kuro--update-cursor updates when only shape changes (partial cache miss)."
  (kuro-render-buffer-cursor-test--with-buffer
    (insert "abc\n")
    (setq kuro--cursor-marker (point-marker)
          kuro--last-cursor-row     0
          kuro--last-cursor-col     0
          kuro--last-cursor-visible t
          kuro--last-cursor-shape   0)   ; shape was 0, now 2
    (let ((apply-calls 0))
      (cl-letf (((symbol-function 'kuro--get-cursor-state) (lambda () '(0 0 t 2)))
                ((symbol-function 'get-buffer-window) (lambda (&rest _) (selected-window)))
                ((symbol-function 'kuro--apply-cursor-display)
                 (lambda (_v _s) (cl-incf apply-calls))))
        (kuro--update-cursor)
        (should (= apply-calls 1))))))

(provide 'kuro-render-buffer-test)

;;; kuro-render-buffer-test.el ends here
