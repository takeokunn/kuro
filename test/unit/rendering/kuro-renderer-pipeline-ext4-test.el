;;; kuro-renderer-pipeline-ext4-test.el --- Pipeline tests: binary FFI, resize, evict  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-renderer-pipeline-test-support)

;;; Group 20: kuro--core-render-pipeline binary FFI dispatch

(ert-deftest kuro-renderer-pipeline-ext3-core-pipeline-dispatches-binary-when-flag-set ()
  "kuro--core-render-pipeline calls kuro--poll-updates-binary-optimised when kuro-use-binary-ffi is t."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((binary-called nil)
          (faces-called nil)
          (kuro-use-binary-ffi t))
      (cl-letf (((symbol-function 'kuro--apply-title-update)    #'ignore)
                ((symbol-function 'kuro--process-scroll-events) #'ignore)
                ((symbol-function 'kuro--poll-updates-binary-optimised)
                 (lambda (_session-id) (setq binary-called t) nil))
                ((symbol-function 'kuro--poll-updates-with-faces)
                 (lambda () (setq faces-called t) (error "should not be called")))
                ((symbol-function 'kuro--apply-dirty-lines)     #'ignore)
                ((symbol-function 'kuro--update-cursor)         #'ignore))
        (kuro--core-render-pipeline)
        (should binary-called)
        (should-not faces-called)))))

;;; Group 21: kuro--handle-pending-resize

(ert-deftest test-kuro-pipeline-ext3-handle-pending-resize-noop-when-nil ()
  "kuro--handle-pending-resize does nothing when kuro--resize-pending is nil."
  (kuro-renderer-pipeline-resize-test--with-buffer
    (let ((resize-called nil))
      (cl-letf (((symbol-function 'kuro--resize)
                 (lambda (_r _c) (setq resize-called t))))
        (kuro--handle-pending-resize)
        (should-not resize-called)
        (should (= kuro--last-rows 24))
        (should (= kuro--last-cols 80))))))

(ert-deftest test-kuro-pipeline-ext3-handle-pending-resize-calls-resize ()
  "kuro--handle-pending-resize calls kuro--resize with (new-rows new-cols)."
  (kuro-renderer-pipeline-resize-test--with-buffer
    (setq kuro--resize-pending '(30 . 100))
    (let ((resize-args nil))
      (cl-letf (((symbol-function 'kuro--resize)
                 (lambda (r c) (setq resize-args (list r c)))))
        (kuro--handle-pending-resize)
        (should (equal resize-args '(30 100)))))))

(ert-deftest test-kuro-pipeline-ext3-handle-pending-resize-clears-pending ()
  "After kuro--handle-pending-resize runs, kuro--resize-pending is nil."
  (kuro-renderer-pipeline-resize-test--with-buffer
    (setq kuro--resize-pending '(24 . 80))
    (cl-letf (((symbol-function 'kuro--resize) #'ignore))
      (kuro--handle-pending-resize)
      (should-not kuro--resize-pending))))

(ert-deftest test-kuro-pipeline-ext3-handle-pending-resize-updates-last-rows-cols ()
  "kuro--handle-pending-resize updates kuro--last-rows and kuro--last-cols."
  (kuro-renderer-pipeline-resize-test--with-buffer
    (setq kuro--resize-pending '(30 . 120))
    (cl-letf (((symbol-function 'kuro--resize) #'ignore))
      (kuro--handle-pending-resize)
      (should (= kuro--last-rows 30))
      (should (= kuro--last-cols 120)))))

(ert-deftest test-kuro-pipeline-ext3-handle-pending-resize-clears-col-to-buf-map ()
  "kuro--handle-pending-resize clears kuro--col-to-buf-map via clrhash."
  (kuro-renderer-pipeline-resize-test--with-buffer
    (puthash 0 [0 1 2] kuro--col-to-buf-map)
    (puthash 5 [0 2 4] kuro--col-to-buf-map)
    (setq kuro--resize-pending '(24 . 80))
    (cl-letf (((symbol-function 'kuro--resize) #'ignore))
      (kuro--handle-pending-resize)
      (should (= (hash-table-count kuro--col-to-buf-map) 0)))))

(ert-deftest test-kuro-pipeline-ext3-handle-pending-resize-skips-when-not-initialized ()
  "kuro--handle-pending-resize skips kuro--resize when kuro--initialized is nil."
  (kuro-renderer-pipeline-resize-test--with-buffer
    (setq kuro--initialized nil
          kuro--resize-pending '(24 . 80))
    (let ((resize-called nil))
      (cl-letf (((symbol-function 'kuro--resize)
                 (lambda (_r _c) (setq resize-called t))))
        (kuro--handle-pending-resize)
        (should-not resize-called)
        ;; pending is drained even when not initialized
        (should-not kuro--resize-pending)))))

(defconst kuro-renderer-pipeline-ext3-test--resize-skips-zero-table
  '((test-kuro-pipeline-ext3-handle-pending-resize-skips-zero-rows  (0  . 80))
    (test-kuro-pipeline-ext3-handle-pending-resize-skips-zero-cols  (24 . 0)))
  "Table of (test-name pending-dims) where kuro--handle-pending-resize must NOT call resize.")

(defmacro kuro-renderer-pipeline-ext3-test--def-resize-skips-zero (test-name pending-dims)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--handle-pending-resize' skips resize for pending=%s." pending-dims)
     (kuro-renderer-pipeline-resize-test--with-buffer
       (setq kuro--resize-pending ',pending-dims)
       (let ((resize-called nil))
         (cl-letf (((symbol-function 'kuro--resize)
                    (lambda (_r _c) (setq resize-called t))))
           (kuro--handle-pending-resize)
           (should-not resize-called))))))

(kuro-renderer-pipeline-ext3-test--def-resize-skips-zero test-kuro-pipeline-ext3-handle-pending-resize-skips-zero-rows  (0  . 80))
(kuro-renderer-pipeline-ext3-test--def-resize-skips-zero test-kuro-pipeline-ext3-handle-pending-resize-skips-zero-cols  (24 . 0))

(ert-deftest kuro-renderer-pipeline-ext3-test--all-resize-skips-zero-correct ()
  "All entries in `kuro-renderer-pipeline-ext3-test--resize-skips-zero-table' skip resize."
  (dolist (entry kuro-renderer-pipeline-ext3-test--resize-skips-zero-table)
    (pcase-let ((`(,_name ,pending-dims) entry))
      (kuro-renderer-pipeline-resize-test--with-buffer
        (setq kuro--resize-pending pending-dims)
        (let ((resize-called nil))
          (cl-letf (((symbol-function 'kuro--resize)
                     (lambda (_r _c) (setq resize-called t))))
            (kuro--handle-pending-resize)
            (should-not resize-called)))))))

(ert-deftest test-kuro-pipeline-ext3-handle-pending-resize-adds-buffer-lines ()
  "Resizing from 10 to 15 rows inserts 5 newlines at end of buffer."
  (with-temp-buffer
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t)
          (kuro--initialized t)
          (kuro--resize-pending '(15 . 80))
          (kuro--last-rows 10)
          (kuro--last-cols 80)
          (kuro--col-to-buf-map (make-hash-table :test 'eql))
          kuro--last-cursor-row kuro--last-cursor-col
          kuro--last-cursor-visible kuro--last-cursor-shape)
      (dotimes (_ 10) (insert "\n"))
      (should (= (1- (line-number-at-pos (point-max))) 10))
      (cl-letf (((symbol-function 'kuro--resize) #'ignore))
        (kuro--handle-pending-resize))
      (should (= (1- (line-number-at-pos (point-max))) 15)))))

(ert-deftest test-kuro-pipeline-ext3-handle-pending-resize-removes-buffer-lines ()
  "Resizing from 20 to 15 rows deletes 5 lines from end of buffer."
  (with-temp-buffer
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t)
          (kuro--initialized t)
          (kuro--resize-pending '(15 . 80))
          (kuro--last-rows 20)
          (kuro--last-cols 80)
          (kuro--col-to-buf-map (make-hash-table :test 'eql))
          kuro--last-cursor-row kuro--last-cursor-col
          kuro--last-cursor-visible kuro--last-cursor-shape)
      (dotimes (_ 20) (insert "\n"))
      (should (= (1- (line-number-at-pos (point-max))) 20))
      (cl-letf (((symbol-function 'kuro--resize) #'ignore))
        (kuro--handle-pending-resize))
      (should (= (1- (line-number-at-pos (point-max))) 15)))))

;;; Group 22: kuro--with-render-env macro

(defconst kuro-renderer-pipeline-ext3-test--render-env-gc-table
  '((kuro-renderer-pipeline-ext3-with-render-env-sets-gc-threshold
     gc-cons-threshold  kuro--render-gc-threshold)
    (kuro-renderer-pipeline-ext3-with-render-env-sets-gc-percentage
     gc-cons-percentage kuro--render-gc-percentage))
  "Table of (test-name gc-var expected-const) for `kuro--with-render-env' GC bindings.")

(defmacro kuro-renderer-pipeline-ext3-test--def-render-env-gc (test-name gc-var expected-const)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--with-render-env' binds %s to %s." gc-var expected-const)
     (let (captured)
       (kuro--with-render-env
         (setq captured ,gc-var))
       (should (= captured ,expected-const)))))

(kuro-renderer-pipeline-ext3-test--def-render-env-gc
 kuro-renderer-pipeline-ext3-with-render-env-sets-gc-threshold
 gc-cons-threshold  kuro--render-gc-threshold)
(kuro-renderer-pipeline-ext3-test--def-render-env-gc
 kuro-renderer-pipeline-ext3-with-render-env-sets-gc-percentage
 gc-cons-percentage kuro--render-gc-percentage)

(ert-deftest kuro-renderer-pipeline-ext3-test--all-render-env-gc-bindings-correct ()
  "All entries in `kuro-renderer-pipeline-ext3-test--render-env-gc-table' bind correctly."
  (dolist (entry kuro-renderer-pipeline-ext3-test--render-env-gc-table)
    (pcase-let ((`(,_name ,gc-var ,expected-const) entry))
      (let (captured)
        (kuro--with-render-env
          (setq captured (symbol-value gc-var)))
        (should (= captured (symbol-value expected-const)))))))

(ert-deftest kuro-renderer-pipeline-ext3-with-render-env-returns-body-value ()
  "`kuro--with-render-env' propagates the return value of BODY."
  (should (equal (kuro--with-render-env (+ 1 2)) 3)))

(ert-deftest kuro-renderer-pipeline-ext3-with-render-env-restores-gc-threshold ()
  "`kuro--with-render-env' restores gc-cons-threshold after body."
  (let ((before gc-cons-threshold))
    (kuro--with-render-env t)
    (should (= gc-cons-threshold before))))

(ert-deftest kuro-renderer-pipeline-ext3-with-render-env-executes-body ()
  "`kuro--with-render-env' evaluates all body forms as a progn."
  (let (a b)
    (kuro--with-render-env
      (setq a 1)
      (setq b 2))
    (should (= a 1))
    (should (= b 2))))

;;; From kuro-renderer-pipeline-timer-test.el (Groups 25-28)

;;; Group 25: kuro--switch-render-timer

(ert-deftest kuro-renderer-pipeline-switch-render-timer-calls-install-with-rate ()
  "kuro--switch-render-timer calls kuro--install-render-timer with the given rate."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((install-rate :unset))
      (cl-letf (((symbol-function 'kuro--install-render-timer)
                 (lambda (r) (setq install-rate r)))
                ((symbol-function 'kuro--recompute-blink-frame-intervals) #'ignore))
        (kuro--switch-render-timer 30)
        (should (= install-rate 30))))))

(ert-deftest kuro-renderer-pipeline-switch-render-timer-calls-recompute-blink ()
  "kuro--switch-render-timer calls kuro--recompute-blink-frame-intervals."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((blink-calls 0))
      (cl-letf (((symbol-function 'kuro--install-render-timer) #'ignore)
                ((symbol-function 'kuro--recompute-blink-frame-intervals)
                 (lambda () (cl-incf blink-calls))))
        (kuro--switch-render-timer 60)
        (should (= blink-calls 1))))))

(ert-deftest kuro-renderer-pipeline-switch-render-timer-passes-rate-verbatim ()
  "kuro--switch-render-timer forwards the exact rate value to kuro--install-render-timer."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((captured-rate :unset))
      (cl-letf (((symbol-function 'kuro--install-render-timer)
                 (lambda (r) (setq captured-rate r)))
                ((symbol-function 'kuro--recompute-blink-frame-intervals) #'ignore))
        (kuro--switch-render-timer 120)
        (should (= captured-rate 120))))))

(ert-deftest kuro-renderer-pipeline-switch-render-timer-updates-budget-vars ()
  "kuro--switch-render-timer updates all five budget variables via kuro--recompute-budget-vars."
  (kuro-renderer-pipeline-test--with-buffer
    (cl-letf (((symbol-function 'kuro--install-render-timer) #'ignore)
              ((symbol-function 'kuro--recompute-blink-frame-intervals) #'ignore))
      (kuro--switch-render-timer 30)
      (should (< (abs (- kuro--frame-budget-seconds (/ 1.0 30))) 1e-9))
      (should (< (abs (- kuro--half-frame-interval  (/ 0.5 30))) 1e-9))
      (should (< (abs (- kuro--budget-threshold-high (* 0.9 (/ 1.0 30)))) 1e-9))
      (should (< (abs (- kuro--budget-threshold-low  (* 0.5 (/ 1.0 30)))) 1e-9)))))

(ert-deftest kuro-renderer-pipeline-start-render-loop-updates-budget-vars ()
  "kuro--start-render-loop updates all five budget variables via kuro--recompute-budget-vars."
  (kuro-renderer-pipeline-test--with-buffer
    (setq-local kuro-frame-rate 60)
    (cl-letf (((symbol-function 'kuro--recompute-blink-frame-intervals) #'ignore)
              ((symbol-function 'kuro--start-stream-idle-timer) #'ignore))
      (kuro--start-render-loop)
      (when kuro--timer
        (cancel-timer kuro--timer)
        (setq kuro--timer nil))
      (should (< (abs (- kuro--frame-budget-seconds (/ 1.0 60))) 1e-9))
      (should (< (abs (- kuro--half-frame-interval  (/ 0.5 60))) 1e-9))
      (should (< (abs (- kuro--budget-threshold-high (* 0.9 (/ 1.0 60)))) 1e-9))
      (should (< (abs (- kuro--budget-threshold-low  (* 0.5 (/ 1.0 60)))) 1e-9)))))

;;; Group 26: kuro--evict-stale-col-to-buf-entries (threshold + eviction paths)

(ert-deftest kuro-renderer-pipeline-evict-stale-noop-when-last-rows-zero ()
  "kuro--evict-stale-col-to-buf-entries is a no-op when kuro--last-rows is 0."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--last-rows 0)
    (puthash 0 [0 1] kuro--col-to-buf-map)
    (puthash 1 [0 1] kuro--col-to-buf-map)
    (kuro--evict-stale-col-to-buf-entries nil)
    (should (= (hash-table-count kuro--col-to-buf-map) 2))))

(ert-deftest kuro-renderer-pipeline-evict-stale-noop-below-threshold ()
  "kuro--evict-stale-col-to-buf-entries is a no-op when map size <= 2x row count."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--last-rows 4)
    ;; 4 rows * 2 = 8 threshold; put 8 entries (at threshold, not above).
    (dotimes (i 8) (puthash i [0] kuro--col-to-buf-map))
    (kuro--evict-stale-col-to-buf-entries nil)
    ;; Map should be unchanged — 8 is not > 8.
    (should (= (hash-table-count kuro--col-to-buf-map) 8))))

(ert-deftest kuro-renderer-pipeline-evict-stale-triggers-above-threshold ()
  "kuro--evict-stale-col-to-buf-entries evicts when map size > 2x row count."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--last-rows 4)
    ;; 4 rows * 2 = 8; put 9 entries to exceed threshold.
    (dotimes (i 9) (puthash i [0] kuro--col-to-buf-map))
    (kuro--evict-stale-col-to-buf-entries nil)
    ;; Out-of-bounds rows (4,5,6,7,8) should be removed; in-bounds (0,1,2,3) kept.
    (should (= (hash-table-count kuro--col-to-buf-map) 4))
    (dotimes (i 4) (should (gethash i kuro--col-to-buf-map)))))

(ert-deftest kuro-renderer-pipeline-evict-stale-removes-empty-c2b-dirty-rows ()
  "kuro--evict-stale-col-to-buf-entries removes rows with empty col-to-buf vectors from dirty list."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--last-rows 2)
    ;; Put 5 entries to exceed 2*2=4 threshold.
    (dotimes (i 5) (puthash i [0 1] kuro--col-to-buf-map))
    ;; dirty-rows: row 0 has empty col-to-buf vector (CJK→ASCII transition).
    (let ((dirty-rows (vector (vector 0 "ascii" nil []))))
      (kuro--evict-stale-col-to-buf-entries dirty-rows))
    ;; Row 0 should be evicted (empty c2b) + rows 2,3,4 (out-of-bounds >= 2).
    (should-not (gethash 0 kuro--col-to-buf-map))
    ;; Row 1 is in-bounds with non-empty vector — should remain.
    (should (gethash 1 kuro--col-to-buf-map))))

(ert-deftest kuro-renderer-pipeline-evict-stale-returns-nil ()
  "kuro--evict-stale-col-to-buf-entries always returns nil."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--last-rows 4)
    ;; Exceed threshold so eviction actually runs.
    (dotimes (i 9) (puthash i [0] kuro--col-to-buf-map))
    (should (null (kuro--evict-stale-col-to-buf-entries nil)))))


;;; kuro--with-render-env structural tests (Group 22 ext.)

(ert-deftest kuro-renderer-with-render-env-expands-to-let-star ()
  "`kuro--with-render-env' single-step expands to a `let*' form."
  (let ((exp (macroexpand-1 '(kuro--with-render-env (ignore)))))
    (should (eq (car exp) 'let*))))

(ert-deftest kuro-renderer-with-render-env-first-binding-is-gc-threshold ()
  "`kuro--with-render-env' first binding rebinds `gc-cons-threshold'."
  (let* ((exp (macroexpand-1 '(kuro--with-render-env (ignore))))
         (first-binding-name (caar (cadr exp))))
    (should (eq first-binding-name 'gc-cons-threshold))))

(ert-deftest kuro-renderer-with-render-env-binds-inhibit-redisplay ()
  "`kuro--with-render-env' binds `inhibit-redisplay' to prevent partial redraws."
  (let* ((exp (macroexpand-1 '(kuro--with-render-env (ignore))))
         (binding-names (mapcar #'car (cadr exp))))
    (should (memq 'inhibit-redisplay binding-names))))

(provide 'kuro-renderer-pipeline-ext4-test)

;;; kuro-renderer-pipeline-ext4-test.el ends here
