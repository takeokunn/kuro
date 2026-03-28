;;; kuro-performance-test.el --- Performance and correctness tests for Kuro render pipeline  -*- lexical-binding: t; -*-

;; Tests for the cmatrix performance fix:
;; - FR-007: Render cycle timing under full-dirty conditions
;; - FR-008: Post-insert face position correctness in multi-row batch updates

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-faces)
(require 'kuro-renderer)
(require 'kuro-overlays)
(require 'kuro-ffi)

;;; Helper macro

(defmacro kuro-perf-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer with all kuro buffer-local state initialized.
Mirrors the pattern used in kuro-renderer-unit-test.el."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (inhibit-modification-hooks t)
           ;; kuro-ffi state
           (kuro--initialized nil)
           (kuro--col-to-buf-map (make-hash-table :test 'eql))
           (kuro--resize-pending nil)
           ;; kuro-renderer state
           (kuro--cursor-marker nil)
           (kuro--mode-poll-frame-count 9)
           (kuro--scroll-offset 0)
           (kuro-timer nil)
           ;; kuro-overlays state
           (kuro--blink-overlays nil)
           (kuro--image-overlays nil)
           (kuro--hyperlink-overlays nil)
           (kuro--prompt-positions nil)
           (kuro--blink-frame-count 0)
           (kuro--blink-visible-slow t)
           (kuro--blink-visible-fast t)
           ;; kuro-ffi mode state (polled every 10 frames)
           (kuro--application-cursor-keys-mode nil)
           (kuro--app-keypad-mode nil)
           (kuro--mouse-mode nil)
           (kuro--mouse-sgr nil)
           (kuro--mouse-pixel-mode nil)
           (kuro--bracketed-paste-mode nil)
           (kuro--keyboard-flags 0)
           ;; resize tracking
           (kuro--last-rows 0)
           (kuro--last-cols 0))
       ,@body)))

;;; FR-007: Render cycle timing test

(defun kuro-perf-test--make-stub-updates (rows cols)
  "Build a list of simulated `kuro--poll-updates-with-faces' results.
Each entry simulates one dirty row with COLS colored cells.
Format per entry: (((row . text) . face-list) . col-to-buf-vector)"
  (let (result)
    (dotimes (row rows)
      ;; Two face spans per row: first half one color, second half another.
      ;; Use distinct RGB colors per row to exercise the face cache.
      (let* ((text (make-string cols ?A))
             (mid (/ cols 2))
             (fg1 (logior (ash (mod (* row 7)  256) 16)
                          (ash (mod (* row 13) 256) 8)
                          (mod (* row 17) 256)))
             (fg2 (logior (ash (mod (* row 11) 256) 16)
                          (ash (mod (* row 19) 256) 8)
                          (mod (* row 23) 256)))
             ;; face-range format: (start-col end-col fg-enc bg-enc flags)
             (face-ranges (list (list 0   mid fg1 #xFF000000 0)
                                (list mid cols fg2 #xFF000000 0)))
             ;; col-to-buf vector: identity mapping for ASCII text
             (col-to-buf (let ((v (make-vector cols 0)))
                           (dotimes (i cols) (aset v i i))
                           v))
             ;; line-update = (((row . text) . face-ranges) . col-to-buf)
             (line-data (cons (cons row text) face-ranges))
             (entry (cons line-data col-to-buf)))
        (push entry result)))
    (nreverse result)))

(ert-deftest test-kuro-render-cycle-timing ()
  "Measure render cycle time for a full-dirty 24x80 update (cmatrix scenario).
Threshold: must complete under 10ms per frame with all FFI stubbed.
Skips if the kuro-core Rust module is not available."
  :tags '(performance kuro)
  (skip-unless (fboundp 'kuro-core-init))
  (let* ((rows 24)
         (cols 80)
         (stub-updates (kuro-perf-test--make-stub-updates rows cols))
         (iterations 50)
         elapsed-ms)
    (kuro-perf-test--with-buffer
      ;; Pre-fill buffer with blank lines to match terminal rows
      (erase-buffer)
      (dotimes (_ rows) (insert "\n"))
      (setq kuro--cursor-marker (point-marker)
            kuro--initialized t
            kuro--last-rows rows
            kuro--last-cols cols)
      ;; Stub all FFI calls so we measure only Elisp render work.
      ;; Disable binary FFI so kuro--poll-updates-with-faces is used (it is
      ;; already stubbed below; the binary path would require a live Rust module).
      (let ((kuro-use-binary-ffi nil))
      (cl-letf (((symbol-function 'kuro--poll-updates-with-faces)
                 (lambda () stub-updates))
                ((symbol-function 'kuro-core-bell-pending)
                 (lambda () nil))
                ((symbol-function 'kuro-core-clear-bell)
                 (lambda () nil))
                ((symbol-function 'kuro--get-and-clear-title)
                 (lambda () nil))
                ((symbol-function 'kuro--get-cursor)
                 (lambda () '(0 . 0)))
                ((symbol-function 'kuro--get-cursor-visible)
                 (lambda () t))
                ((symbol-function 'kuro--get-cursor-shape)
                 (lambda () 0))
                ((symbol-function 'kuro--get-cwd)
                 (lambda () nil))
                ((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () nil))
                ((symbol-function 'kuro--poll-prompt-marks)
                 (lambda () nil))
                ((symbol-function 'kuro--poll-image-notifications)
                 (lambda () nil))
                ((symbol-function 'kuro--apply-palette-updates)
                 (lambda () nil))
                ((symbol-function 'kuro--apply-default-colors)
                 (lambda () nil))
                ((symbol-function 'kuro--has-pending-output)
                 (lambda () nil)))
        ;; Warm-up pass: populates face cache, JIT-compiles hot paths
        (kuro--render-cycle)
        ;; Timed run
        (let ((t0 (float-time)))
          (dotimes (_ iterations)
            (kuro--render-cycle))
          (setq elapsed-ms (* 1000.0 (- (float-time) t0))))))
      (let ((per-frame-ms (/ elapsed-ms iterations)))
        (message "kuro render cycle: %.2fms/frame for %dx%d full-dirty (%d iterations)"
                 per-frame-ms rows cols iterations)
        ;; 10ms threshold per frame: conservative target for Elisp-only rendering
        (should (< per-frame-ms 10.0))))))

;;; FR-008: Post-insert face position correctness test for kuro--update-line-full

(defun kuro-perf-test--get-face-at-col (line-num col)
  "Return the `face' text property at column COL of LINE-NUM (0-indexed)."
  (save-excursion
    (goto-char (point-min))
    (forward-line line-num)
    (get-text-property (+ (point) col) 'face)))

(ert-deftest test-kuro-update-line-full-face-position ()
  "Verify kuro--update-line-full applies face ranges at correct buffer positions
after variable-length text replacement in a single-pass batch update.

Tests two correctness properties of Fix 2 (single-pass line update):
1. line-end is recomputed AFTER delete-region + insert so face ranges are
   applied to the new text offsets, not the pre-insert (stale) line end.
2. Face positions for row N are not corrupted by row N-1's text changes.

face-range format: (start-buf end-buf fg-enc bg-enc flags)
where start-buf/end-buf are buffer char offsets relative to line-start,
fg-enc/bg-enc are raw u32 FFI color values, and flags is a bitmask."
  :tags '(correctness kuro)
  ;; Fresh face cache per test to avoid cross-test pollution.
  (let ((kuro--face-cache (make-hash-table :test 'equal)))
    (kuro-perf-test--with-buffer
      ;; Pre-fill with 5 rows of identical-length ASCII content.
      (erase-buffer)
      (dotimes (_ 5) (insert "AAAAAAAAAA\n"))  ; rows 0-4: 10 chars each

      ;; ---- Test 1: single row, text grows longer ----
      ;; Replace row 0 (10 chars) with 19-char text.  Applies a red face
      ;; (RGB #FF0000 = u32 0x00FF0000) to buffer offsets [3, 6).
      ;; If line-end were not recomputed after insert, the 19-char new text
      ;; would be incorrectly clamped to the old 10-char line-end and offsets
      ;; 3-6 would be valid in the new text but could be misclamped.
      (kuro--update-line-full 0 "XXXXXXXXXXXXXXXXXXX"        ; 19 chars (was 10)
                              (list (list 3 6 #x00FF0000 #xFF000000 0))
                              nil)
      ;; Text content is the new 19-char string.
      (save-excursion
        (goto-char (point-min))
        (should (string= (buffer-substring-no-properties (point) (line-end-position))
                         "XXXXXXXXXXXXXXXXXXX")))
      ;; Face applied at offsets 3, 4, 5 (inside [3, 6)).
      (should (kuro-perf-test--get-face-at-col 0 3))
      (should (kuro-perf-test--get-face-at-col 0 5))
      ;; No face at offset 6 (exclusive end of range).
      (should-not (kuro-perf-test--get-face-at-col 0 6))

      ;; ---- Test 2: batch update, face position isolation ----
      ;; Row 1 replaced with shorter text (5 chars), no face.
      ;; Row 2 replaced with longer text (12 chars), blue face (RGB #0000FF =
      ;; u32 0x000000FF) at buffer offsets [4, 8).
      ;; Verifies row 2's face positions are computed from row 2's own
      ;; line-start and are not offset by row 1's content-length change.
      (kuro--update-line-full 1 "SHORT" nil nil)
      (kuro--update-line-full 2 "LONGERLONGER"              ; 12 chars (was 10)
                              (list (list 4 8 #x000000FF #xFF000000 0))
                              nil)
      ;; Row 2 content correct.
      (save-excursion
        (goto-char (point-min))
        (forward-line 2)
        (should (string= (buffer-substring-no-properties (point) (line-end-position))
                         "LONGERLONGER")))
      ;; Face on row 2 at offsets 4, 5, 6, 7 (inside [4, 8)).
      (should (kuro-perf-test--get-face-at-col 2 4))
      (should (kuro-perf-test--get-face-at-col 2 7))
      ;; No face at offset 8 (exclusive end).
      (should-not (kuro-perf-test--get-face-at-col 2 8))
      ;; Row 3 (AAAA...) untouched: no content change, no face bleed.
      (save-excursion
        (goto-char (point-min))
        (forward-line 3)
        (should (string= (buffer-substring-no-properties (point) (line-end-position))
                         "AAAAAAAAAA")))
      (should-not (kuro-perf-test--get-face-at-col 3 0)))))

(provide 'kuro-performance-test)

;;; kuro-performance-test.el ends here
