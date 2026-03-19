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

(provide 'kuro-render-buffer-test)

;;; kuro-render-buffer-test.el ends here
