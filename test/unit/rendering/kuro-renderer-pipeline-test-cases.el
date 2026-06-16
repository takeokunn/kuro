;;; kuro-renderer-pipeline-test-cases.el --- Pipeline test case data  -*- lexical-binding: t; -*-

;;; Commentary:
;; Data-only fixtures for kuro-renderer-pipeline.el unit tests.

;;; Code:

(defconst kuro-renderer-pipeline-test--constant-invariant-cases
  '((kuro-renderer-pipeline-const-col-to-buf-evict-factor-positive
     "`kuro--col-to-buf-evict-factor' is a positive integer."
     (and (integerp kuro--col-to-buf-evict-factor)
          (> kuro--col-to-buf-evict-factor 0)))
    (kuro-renderer-pipeline-const-frame-duration-ring-size-matches-ring
     "`kuro--frame-duration-ring-size' equals the frame-duration ring length."
     (= kuro--frame-duration-ring-size
        (length kuro--frame-duration-ring)))
    (kuro-renderer-pipeline-const-title-sanitize-regexp-is-string
     "`kuro--title-sanitize-regexp' is a non-empty regexp string."
     (and (stringp kuro--title-sanitize-regexp)
          (> (length kuro--title-sanitize-regexp) 0))))
  "Constant invariant tests for `kuro-renderer-pipeline.el'.")

(defconst kuro-renderer-pipeline-test--resize-skips-zero-cases
  '((test-kuro-pipeline-ext3-handle-pending-resize-skips-zero-rows
     (0 . 80))
    (test-kuro-pipeline-ext3-handle-pending-resize-skips-zero-cols
     (24 . 0)))
  "Cases where `kuro--handle-pending-resize' must not call resize.")

(defconst kuro-renderer-pipeline-test--pending-resize-validity-cases
  '(((t 24 80) . t)
    ((nil 24 80) . nil)
    ((t 0 80) . nil)
    ((t 24 0) . nil))
  "Cases of ((initialized rows cols) . expected) for pending resize validation.")

(defconst kuro-renderer-pipeline-test--row-count-cases
  '((kuro-renderer-pipeline-current-buffer-row-count-uses-trailing-newline-model
     "`kuro--current-buffer-row-count' treats one trailing newline as one renderer row."
     3 nil 3 nil)
    (kuro-renderer-pipeline-adjust-buffer-row-count-inserts-lines
     "`kuro--adjust-buffer-row-count' grows the current buffer to the requested row count."
     2 5 5 nil)
    (kuro-renderer-pipeline-adjust-buffer-row-count-deletes-lines
     "`kuro--adjust-buffer-row-count' shrinks the current buffer to the requested row count."
     5 2 2 nil)
    (kuro-renderer-pipeline-adjust-buffer-row-count-noop-when-equal
     "`kuro--adjust-buffer-row-count' leaves equal-sized buffers unchanged."
     4 4 4 t))
  "Cases for renderer buffer row count helpers.")

(defconst kuro-renderer-pipeline-test--render-env-gc-cases
  '((kuro-renderer-pipeline-ext3-with-render-env-sets-gc-threshold
     gc-cons-threshold  kuro--render-gc-threshold)
    (kuro-renderer-pipeline-ext3-with-render-env-sets-gc-percentage
     gc-cons-percentage kuro--render-gc-percentage))
  "Cases of (test-name gc-var expected-const) for `kuro--with-render-env'.")

(provide 'kuro-renderer-pipeline-test-cases)

;;; kuro-renderer-pipeline-test-cases.el ends here
