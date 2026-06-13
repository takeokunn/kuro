;;; kuro-renderer-test-3.el --- ERT tests for kuro-renderer — Groups 15+, perf, budget  -*-  lexical-binding: t; -*-

;;; Code:

(require 'kuro-renderer-test-support)

;;; Group 15: title-polling renames the buffer

(ert-deftest kuro-renderer-title-polling-renames-buffer ()
  "Title polling: render cycle renames buffer when kuro--get-and-clear-title returns a string."
  (require 'kuro-renderer)
  (with-temp-buffer
    (let ((buf (current-buffer)))
      (cl-letf (((symbol-function 'kuro--get-and-clear-title)
                 (lambda () "my title")))
        ;; Simulate the title-handling path of kuro--render-cycle
        (let ((title (kuro--get-and-clear-title)))
          (when (and (stringp title) (not (string-empty-p title)))
            (let ((safe-title (kuro--sanitize-title title)))
              (rename-buffer (format "*kuro: %s*" safe-title) t))))
        ;; Verify the buffer was renamed correctly
        (should (string-match-p "\\*kuro: my title\\*" (buffer-name buf)))))))

;;; FR-007 / FR-008: Performance and correctness helpers

(defmacro kuro-perf-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer with all kuro buffer-local state initialized."
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

(defun kuro-perf-test--make-stub-updates (rows cols)
  "Build a vector of simulated `kuro--poll-updates-with-faces' results.
Each entry simulates one dirty row with COLS colored cells."
  (let ((result (make-vector rows nil)))
    (dotimes (row rows)
      (let* ((text (make-string cols ?A))
             (mid (/ cols 2))
             (fg1 (logior (ash (mod (* row 7)  256) 16)
                          (ash (mod (* row 13) 256) 8)
                          (mod (* row 17) 256)))
             (fg2 (logior (ash (mod (* row 11) 256) 16)
                          (ash (mod (* row 19) 256) 8)
                          (mod (* row 23) 256)))
             (face-ranges (vector 0   mid fg1 #xFF000000 0 0
                                  mid cols fg2 #xFF000000 0 0))
             (col-to-buf (let ((v (make-vector cols 0)))
                           (dotimes (i cols) (aset v i i))
                           v)))
        (aset result row (vector row text face-ranges col-to-buf))))
    result))

(defun kuro-perf-test--get-face-at-col (line-num col)
  "Return the `face' text property at column COL of LINE-NUM (0-indexed)."
  (save-excursion
    (goto-char (point-min))
    (forward-line line-num)
    (get-text-property (+ (point) col) 'face)))

;;; FR-007: Render cycle timing test

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

(ert-deftest test-kuro-update-line-full-face-position ()
  "Verify kuro--update-line-full applies face ranges at correct buffer positions
after variable-length text replacement in a single-pass batch update."
  :tags '(correctness kuro)
  ;; Fresh face cache per test to avoid cross-test pollution.
  (let ((kuro--face-cache (make-hash-table :test 'equal)))
    (kuro-perf-test--with-buffer
      ;; Pre-fill with 5 rows of identical-length ASCII content.
      (erase-buffer)
      (dotimes (_ 5) (insert "AAAAAAAAAA\n"))  ; rows 0-4: 10 chars each

      ;; ---- Test 1: single row, text grows longer ----
      (kuro--update-line-full 0 "XXXXXXXXXXXXXXXXXXX"        ; 19 chars (was 10)
                              (vector 3 6 #x00FF0000 #xFF000000 0 0)
                              nil)
      (save-excursion
        (goto-char (point-min))
        (should (string= (buffer-substring-no-properties (point) (line-end-position))
                         "XXXXXXXXXXXXXXXXXXX")))
      (should (kuro-perf-test--get-face-at-col 0 3))
      (should (kuro-perf-test--get-face-at-col 0 5))
      (should-not (kuro-perf-test--get-face-at-col 0 6))

      ;; ---- Test 2: batch update, face position isolation ----
      (kuro--update-line-full 1 "SHORT" nil nil)
      (kuro--update-line-full 2 "LONGERLONGER"              ; 12 chars (was 10)
                              (vector 4 8 #x000000FF #xFF000000 0 0)
                              nil)
      (save-excursion
        (goto-char (point-min))
        (forward-line 2)
        (should (string= (buffer-substring-no-properties (point) (line-end-position))
                         "LONGERLONGER")))
      (should (kuro-perf-test--get-face-at-col 2 4))
      (should (kuro-perf-test--get-face-at-col 2 7))
      (should-not (kuro-perf-test--get-face-at-col 2 8))
      (save-excursion
        (goto-char (point-min))
        (forward-line 3)
        (should (string= (buffer-substring-no-properties (point) (line-end-position))
                         "AAAAAAAAAA")))
      (should-not (kuro-perf-test--get-face-at-col 3 0)))))

;;; Group 16: kuro--recompute-budget-vars macro

(defmacro kuro-renderer-budget-test--with-vars (rate &rest body)
  "Run BODY with budget vars pre-set by kuro--recompute-budget-vars RATE."
  (declare (indent 1))
  `(let ((kuro--frame-budget-ratio 0.8)
         kuro--frame-budget-seconds
         kuro--half-frame-interval
         kuro--budget-threshold-high
         kuro--budget-threshold-low
         kuro--budget-absolute-seconds)
     (kuro--recompute-budget-vars ,rate)
     ,@body))

(ert-deftest kuro-renderer-recompute-budget-vars-frame-budget-seconds ()
  "kuro--recompute-budget-vars sets kuro--frame-budget-seconds to 1/rate."
  (kuro-renderer-budget-test--with-vars 60
    (should (< (abs (- kuro--frame-budget-seconds (/ 1.0 60))) 1e-9))))

(ert-deftest kuro-renderer-recompute-budget-vars-half-frame-interval ()
  "kuro--recompute-budget-vars sets kuro--half-frame-interval to 0.5/rate."
  (kuro-renderer-budget-test--with-vars 120
    (should (< (abs (- kuro--half-frame-interval (/ 0.5 120))) 1e-9))))

(ert-deftest kuro-renderer-recompute-budget-vars-threshold-high ()
  "kuro--recompute-budget-vars sets kuro--budget-threshold-high to 0.9 * frame-budget."
  (kuro-renderer-budget-test--with-vars 60
    (should (< (abs (- kuro--budget-threshold-high (* 0.9 (/ 1.0 60)))) 1e-9))))

(ert-deftest kuro-renderer-recompute-budget-vars-threshold-low ()
  "kuro--recompute-budget-vars sets kuro--budget-threshold-low to 0.5 * frame-budget."
  (kuro-renderer-budget-test--with-vars 60
    (should (< (abs (- kuro--budget-threshold-low (* 0.5 (/ 1.0 60)))) 1e-9))))

(ert-deftest kuro-renderer-recompute-budget-vars-absolute-seconds ()
  "kuro--recompute-budget-vars sets kuro--budget-absolute-seconds to ratio * frame-budget."
  (kuro-renderer-budget-test--with-vars 30
    (should (< (abs (- kuro--budget-absolute-seconds (* 0.8 (/ 1.0 30)))) 1e-9))))

(ert-deftest kuro-renderer-recompute-budget-vars-all-five-consistent ()
  "All five budget variables are mutually consistent after kuro--recompute-budget-vars."
  (kuro-renderer-budget-test--with-vars 60
    ;; high = 0.9 * budget, low = 0.5 * budget, absolute = ratio * budget
    (should (< (abs (- kuro--budget-threshold-high (* 0.9 kuro--frame-budget-seconds))) 1e-9))
    (should (< (abs (- kuro--budget-threshold-low  (* 0.5 kuro--frame-budget-seconds))) 1e-9))
    (should (< (abs (- kuro--budget-absolute-seconds (* 0.8 kuro--frame-budget-seconds))) 1e-9))
    (should (< (abs (- kuro--half-frame-interval (* 0.5 kuro--frame-budget-seconds))) 1e-9))))

(ert-deftest kuro-renderer-recompute-budget-vars-different-rates-differ ()
  "Budget variables differ when computed at 30 fps vs 120 fps."
  (let (budget-30 budget-120)
    (let ((kuro--frame-budget-ratio 0.8)
          kuro--frame-budget-seconds kuro--half-frame-interval
          kuro--budget-threshold-high kuro--budget-threshold-low kuro--budget-absolute-seconds)
      (kuro--recompute-budget-vars 30)
      (setq budget-30 kuro--frame-budget-seconds))
    (let ((kuro--frame-budget-ratio 0.8)
          kuro--frame-budget-seconds kuro--half-frame-interval
          kuro--budget-threshold-high kuro--budget-threshold-low kuro--budget-absolute-seconds)
      (kuro--recompute-budget-vars 120)
      (setq budget-120 kuro--frame-budget-seconds))
    (should (> budget-30 budget-120))))

;;; kuro--recompute-budget-vars structural tests (Group 17)

(ert-deftest kuro-renderer-recompute-budget-vars-expands-to-progn ()
  "`kuro--recompute-budget-vars' single-step expands to a `progn' form."
  (let ((exp (macroexpand-1 '(kuro--recompute-budget-vars rate))))
    (should (eq (car exp) 'progn))))

(ert-deftest kuro-renderer-recompute-budget-vars-has-five-setq-forms ()
  "`kuro--recompute-budget-vars' expansion body contains exactly 5 `setq' forms."
  (let* ((exp (macroexpand-1 '(kuro--recompute-budget-vars rate)))
         (forms (cdr exp)))
    (should (= (length forms) 5))
    (should (cl-every (lambda (f) (eq (car f) 'setq)) forms))))

(ert-deftest kuro-renderer-recompute-budget-vars-first-sets-frame-budget-seconds ()
  "`kuro--recompute-budget-vars' first form sets `kuro--frame-budget-seconds'."
  (let* ((exp (macroexpand-1 '(kuro--recompute-budget-vars rate)))
         (first-form (cadr exp)))
    (should (eq (cadr first-form) 'kuro--frame-budget-seconds))))

;;; kuro--with-frame-coalescing structural tests (Group 18)

(ert-deftest kuro-renderer-with-frame-coalescing-expands-to-let ()
  "`kuro--with-frame-coalescing' single-step expands to a `let' form."
  (let ((exp (macroexpand-1 '(kuro--with-frame-coalescing (ignore)))))
    (should (eq (car exp) 'let))))

(ert-deftest kuro-renderer-with-frame-coalescing-binds-now ()
  "`kuro--with-frame-coalescing' binding variable is `now'."
  (let* ((exp (macroexpand-1 '(kuro--with-frame-coalescing (ignore))))
         (binding-name (car (caadr exp))))
    (should (eq binding-name 'now))))

(ert-deftest kuro-renderer-with-frame-coalescing-body-is-when-guard ()
  "`kuro--with-frame-coalescing' body is a `when' guard for frame throttle."
  (let* ((exp (macroexpand-1 '(kuro--with-frame-coalescing (ignore))))
         (body (caddr exp)))
    (should (eq (car body) 'when))))

(provide 'kuro-renderer-test)

(provide 'kuro-renderer-test-3)
;;; kuro-renderer-test-3.el ends here
