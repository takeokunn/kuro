;;; kuro-render-buffer-ext2-test.el --- Unit tests for kuro-render-buffer.el (part 3)  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-render-buffer.el (buffer update helpers), part 3.
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;;
;; Covered (Groups 21–26):
;;   - kuro--update-cursor: nil state, cache update, unchanged-state anchor paths
;;   - kuro--decscusr-cursor-types: data vector + kuro--decscusr-to-cursor-type
;;   - kuro--cursor-state-changed-p + kuro--cache-cursor-state
;;   - kuro--update-scroll-indicator
;;   - kuro--init-row-positions + kuro--invalidate-row-positions
;;   - kuro--clear-row-overlays: kuro--has-images branch

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

;;; Group 21: kuro--update-cursor — nil state, cache update
;; ------------------------------------------------------------

(ert-deftest kuro-render-buffer-ext2-update-cursor-nil-state-is-noop ()
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

(ert-deftest kuro-render-buffer-ext2-update-cursor-updates-cached-row-col ()
  "kuro--update-cursor updates kuro--last-cursor-row and kuro--last-cursor-col on change."
  (kuro-render-buffer-cursor-test--with-buffer
    (insert "row0\nrow1\n")
    (setq kuro--cursor-marker (point-marker))
    (cl-letf (((symbol-function 'kuro--get-cursor-state) (lambda () '(1 3 t 0)))
              ((symbol-function 'get-buffer-window) (lambda (&rest _) (selected-window))))
      (kuro--update-cursor))
    (should (eql kuro--last-cursor-row 1))
    (should (eql kuro--last-cursor-col 3))))

(ert-deftest kuro-render-buffer-ext2-update-cursor-updates-cached-visible-shape ()
  "kuro--update-cursor updates kuro--last-cursor-visible and kuro--last-cursor-shape."
  (kuro-render-buffer-cursor-test--with-buffer
    (insert "line\n")
    (setq kuro--cursor-marker (point-marker))
    (cl-letf (((symbol-function 'kuro--get-cursor-state) (lambda () '(0 0 nil 5)))
              ((symbol-function 'get-buffer-window) (lambda (&rest _) (selected-window))))
      (kuro--update-cursor))
    (should (eq kuro--last-cursor-visible nil))
    (should (eql kuro--last-cursor-shape 5))))

(ert-deftest kuro-render-buffer-ext2-update-cursor-unchanged-still-anchors-window ()
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

(ert-deftest kuro-render-buffer-ext2-update-cursor-unchanged-uses-marker-position ()
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

(ert-deftest kuro-render-buffer-ext2-update-cursor-unchanged-falls-back-without-marker ()
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

(ert-deftest kuro-render-buffer-ext2-update-cursor-partial-cache-miss-triggers-update ()
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

;;; Group 22: kuro--decscusr-cursor-types — data vector + kuro--decscusr-to-cursor-type

(ert-deftest kuro-render-buffer-ext2-decscusr-cursor-types-is-vector ()
  (should (vectorp kuro--decscusr-cursor-types)))

(ert-deftest kuro-render-buffer-ext2-decscusr-cursor-types-length-7 ()
  (should (= 7 (length kuro--decscusr-cursor-types))))

(ert-deftest kuro-render-buffer-ext2-decscusr-cursor-types-index-0-is-box ()
  (should (eq 'box (aref kuro--decscusr-cursor-types 0))))

(ert-deftest kuro-render-buffer-ext2-decscusr-cursor-types-index-3-is-hbar ()
  (should (equal '(hbar . 2) (aref kuro--decscusr-cursor-types 3))))

(ert-deftest kuro-render-buffer-ext2-decscusr-cursor-types-index-5-is-bar ()
  (should (equal '(bar . 2) (aref kuro--decscusr-cursor-types 5))))

;;; Group 23: kuro--cursor-state-changed-p + kuro--cache-cursor-state

(ert-deftest kuro-render-buffer-ext2-cursor-state-changed-p-returns-nil-when-same ()
  (let ((kuro--last-cursor-row 0)
        (kuro--last-cursor-col 0)
        (kuro--last-cursor-visible t)
        (kuro--last-cursor-shape 0))
    (should-not (kuro--cursor-state-changed-p 0 0 t 0))))

(ert-deftest kuro-render-buffer-ext2-cursor-state-changed-p-returns-t-when-row-differs ()
  (let ((kuro--last-cursor-row 0)
        (kuro--last-cursor-col 0)
        (kuro--last-cursor-visible t)
        (kuro--last-cursor-shape 0))
    (should (kuro--cursor-state-changed-p 1 0 t 0))))

(ert-deftest kuro-render-buffer-ext2-cursor-state-changed-p-returns-t-when-col-differs ()
  (let ((kuro--last-cursor-row 0)
        (kuro--last-cursor-col 0)
        (kuro--last-cursor-visible t)
        (kuro--last-cursor-shape 0))
    (should (kuro--cursor-state-changed-p 0 1 t 0))))

(ert-deftest kuro-render-buffer-ext2-cursor-state-changed-p-returns-t-when-visible-differs ()
  (let ((kuro--last-cursor-row 0)
        (kuro--last-cursor-col 0)
        (kuro--last-cursor-visible t)
        (kuro--last-cursor-shape 0))
    (should (kuro--cursor-state-changed-p 0 0 nil 0))))

(ert-deftest kuro-render-buffer-ext2-cursor-state-changed-p-returns-t-when-shape-differs ()
  (let ((kuro--last-cursor-row 0)
        (kuro--last-cursor-col 0)
        (kuro--last-cursor-visible t)
        (kuro--last-cursor-shape 0))
    (should (kuro--cursor-state-changed-p 0 0 t 1))))

(ert-deftest kuro-render-buffer-ext2-cache-cursor-state-updates-all-four-vars ()
  (let ((kuro--last-cursor-row 0)
        (kuro--last-cursor-col 0)
        (kuro--last-cursor-visible t)
        (kuro--last-cursor-shape 0))
    (kuro--cache-cursor-state 5 10 nil 3)
    (should (= kuro--last-cursor-row 5))
    (should (= kuro--last-cursor-col 10))
    (should (eq kuro--last-cursor-visible nil))
    (should (= kuro--last-cursor-shape 3))))

;;; Group 24: kuro--update-scroll-indicator

(ert-deftest kuro-render-buffer-ext2-scroll-indicator-nil-when-offset-zero ()
  "header-line-format is nil when kuro--scroll-offset is 0 (live view)."
  (with-temp-buffer
    (setq-local kuro--scroll-offset 0)
    (setq header-line-format "stale")
    (kuro--update-scroll-indicator)
    (should (null header-line-format))))

(ert-deftest kuro-render-buffer-ext2-scroll-indicator-shows-offset-when-positive ()
  "header-line-format shows offset when kuro--scroll-offset > 0."
  (with-temp-buffer
    (setq-local kuro--scroll-offset 42)
    (kuro--update-scroll-indicator)
    (should (stringp header-line-format))
    (should (string-match-p "42" header-line-format))))

(ert-deftest kuro-render-buffer-ext2-scroll-indicator-returns-to-nil-after-scroll-bottom ()
  "header-line-format returns to nil after offset goes back to 0."
  (with-temp-buffer
    (setq-local kuro--scroll-offset 10)
    (kuro--update-scroll-indicator)
    (should (stringp header-line-format))
    ;; Simulate scroll-bottom: offset returns to 0
    (setq-local kuro--scroll-offset 0)
    (kuro--update-scroll-indicator)
    (should (null header-line-format))))

(ert-deftest kuro-render-buffer-ext2-scroll-indicator-format-includes-offset-number ()
  "Format string includes the numeric offset value."
  (with-temp-buffer
    (setq-local kuro--scroll-offset 137)
    (kuro--update-scroll-indicator)
    (should (string-match-p "137" header-line-format))))

(ert-deftest kuro-render-buffer-ext2-scroll-indicator-noop-when-unchanged ()
  "kuro--update-scroll-indicator does not update header-line-format when value is unchanged.
This tests the lightweight equality guard."
  (with-temp-buffer
    (setq-local kuro--scroll-offset 5)
    (kuro--update-scroll-indicator)
    (let ((first-value header-line-format))
      (kuro--update-scroll-indicator)
      ;; The exact same string object should be retained (eq, not just equal)
      (should (eq header-line-format first-value)))))

(ert-deftest kuro-render-buffer-ext2-scroll-indicator-includes-return-hint ()
  "Format string includes the S-End return hint."
  (with-temp-buffer
    (setq-local kuro--scroll-offset 1)
    (kuro--update-scroll-indicator)
    (should (string-match-p "S-End" header-line-format))))

;;; Group 25: kuro--init-row-positions + kuro--invalidate-row-positions

(ert-deftest kuro-render-buffer-ext2-init-row-positions-creates-nil-vector ()
  "kuro--init-row-positions sets kuro--row-positions to a vector of nils."
  (with-temp-buffer
    (setq-local kuro--row-positions nil)
    (kuro--init-row-positions 5)
    (should (vectorp kuro--row-positions))
    (should (= (length kuro--row-positions) 5))
    (dotimes (i 5)
      (should (null (aref kuro--row-positions i))))))

(ert-deftest kuro-render-buffer-ext2-init-row-positions-length-matches-rows ()
  "kuro--init-row-positions length equals the ROWS argument."
  (with-temp-buffer
    (setq-local kuro--row-positions nil)
    (kuro--init-row-positions 24)
    (should (= (length kuro--row-positions) 24))))

(ert-deftest kuro-render-buffer-ext2-invalidate-row-positions-clears-entries ()
  "kuro--invalidate-row-positions fills vector with nils."
  (with-temp-buffer
    (setq-local kuro--row-positions (vector 10 20 30))
    (kuro--invalidate-row-positions)
    (should (null (aref kuro--row-positions 0)))
    (should (null (aref kuro--row-positions 1)))
    (should (null (aref kuro--row-positions 2)))))

(ert-deftest kuro-render-buffer-ext2-invalidate-row-positions-noop-when-nil ()
  "kuro--invalidate-row-positions does nothing when kuro--row-positions is nil."
  (with-temp-buffer
    (setq-local kuro--row-positions nil)
    (should-not (kuro--invalidate-row-positions))))

;;; Group 26: kuro--clear-row-overlays — kuro--has-images branch

(ert-deftest kuro-render-buffer-ext2-clear-row-overlays-calls-image-clear-when-has-images ()
  "kuro--clear-row-overlays calls kuro--clear-row-image-overlays when kuro--has-images is t."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    (goto-char (point-min))
    (let ((image-clear-called nil))
      (setq-local kuro--has-images t)
      (cl-letf (((symbol-function 'kuro--clear-row-image-overlays)
                 (lambda (_row) (setq image-clear-called t))))
        (kuro--clear-row-overlays 0))
      (should image-clear-called))))

(ert-deftest kuro-render-buffer-ext2-clear-row-overlays-skips-image-clear-when-no-images ()
  "kuro--clear-row-overlays does NOT call kuro--clear-row-image-overlays when kuro--has-images is nil."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    (goto-char (point-min))
    (let ((image-clear-called nil))
      (setq-local kuro--has-images nil)
      (cl-letf (((symbol-function 'kuro--clear-row-image-overlays)
                 (lambda (_row) (setq image-clear-called t))))
        (kuro--clear-row-overlays 0))
      (should-not image-clear-called))))

(ert-deftest kuro-render-buffer-ext2-clear-row-overlays-always-clears-blink ()
  "kuro--clear-row-overlays always calls kuro--clear-line-blink-overlays regardless of kuro--has-images."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    (goto-char (point-min))
    (let ((blink-clear-called nil))
      (setq-local kuro--has-images t)
      (cl-letf (((symbol-function 'kuro--clear-row-image-overlays) #'ignore)
                ((symbol-function 'kuro--clear-line-blink-overlays)
                 (lambda (_pt _row &optional _pre-end) (setq blink-clear-called t))))
        (kuro--clear-row-overlays 0))
      (should blink-clear-called))))

(provide 'kuro-render-buffer-ext2-test)

;;; kuro-render-buffer-ext2-test.el ends here
