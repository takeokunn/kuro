;;; kuro-renderer-pipeline-test-3.el --- kuro-renderer pipeline tests (part 3) — Groups 24a-c  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-renderer)
(require 'kuro-render-buffer)
(require 'kuro-binary-decoder)
(require 'kuro-renderer-pipeline-test-support)

;;; Group 24: kuro--apply-dirty-updates

(kuro-renderer-pipeline-test--deftest-apply-dirty-updates-cases)

(ert-deftest kuro-renderer-pipeline-apply-dirty-updates-skips-finalize-on-error ()
  "A pipeline error restores render bindings without budget or finalization."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((kuro-debug-perf nil)
          (original-gc-threshold gc-cons-threshold)
          (original-gc-percentage gc-cons-percentage)
          (budget-called nil)
          (finalize-called nil))
      (cl-letf (((symbol-function 'kuro--apply-title-update) #'ignore)
                ((symbol-function 'kuro--poll-frame-updates)
                 (lambda () (error "poll failed")))
                ((symbol-function 'kuro--update-frame-budget-ratio)
                 (lambda (_) (setq budget-called t)))
                ((symbol-function 'kuro--finalize-dirty-updates)
                 (lambda (_) (setq finalize-called t))))
        (should-error (kuro--apply-dirty-updates) :type 'error)
        (should-not budget-called)
        (should-not finalize-called)
        (should (= gc-cons-threshold original-gc-threshold))
        (should (= gc-cons-percentage original-gc-percentage))))))


(provide 'kuro-renderer-pipeline-test-3)

;;; kuro-renderer-pipeline-test-3.el ends here
