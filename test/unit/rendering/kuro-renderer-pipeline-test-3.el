;;; kuro-renderer-pipeline-test-3.el --- kuro-renderer pipeline tests (part 3) — Groups 24a-c  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-renderer)
(require 'kuro-render-buffer)
(require 'kuro-binary-decoder)

;;; Group 24a: kuro--apply-dirty-updates — non-debug path

(ert-deftest kuro-renderer-pipeline-apply-dirty-updates-calls-core-pipeline ()
  "kuro--apply-dirty-updates calls kuro--core-render-pipeline when kuro-debug-perf is nil."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((kuro-debug-perf nil))
      (kuro-renderer-pipeline-test--with-apply-dirty-updates-stubs
          core-calls timing-calls finalize-arg nil nil
        (kuro--apply-dirty-updates)
        (should (= core-calls 1))
        (should (= timing-calls 0))))))

(ert-deftest kuro-renderer-pipeline-apply-dirty-updates-does-not-call-timing-on-non-debug ()
  "kuro--apply-dirty-updates never calls the timing variant when kuro-debug-perf is nil."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((kuro-debug-perf nil))
      (kuro-renderer-pipeline-test--with-apply-dirty-updates-stubs
          core-calls timing-calls finalize-arg nil nil
        (kuro--apply-dirty-updates)
        (should (= timing-calls 0))))))

;;; Group 24b: kuro--apply-dirty-updates — debug path (kuro-debug-perf non-nil)

(ert-deftest kuro-renderer-pipeline-apply-dirty-updates-calls-timing-when-debug-perf ()
  "kuro--apply-dirty-updates calls kuro--core-render-pipeline-with-timing when kuro-debug-perf is non-nil."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((kuro-debug-perf t)
          (kuro--perf-frame-count 0))
      (kuro-renderer-pipeline-test--with-apply-dirty-updates-stubs
          core-calls timing-calls finalize-arg nil nil
        (kuro--apply-dirty-updates)
        (should (= timing-calls 1))
        (should (= core-calls 0))))))

(ert-deftest kuro-renderer-pipeline-apply-dirty-updates-does-not-call-core-on-debug ()
  "kuro--apply-dirty-updates never calls kuro--core-render-pipeline when kuro-debug-perf is non-nil."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((kuro-debug-perf t)
          (kuro--perf-frame-count 0))
      (kuro-renderer-pipeline-test--with-apply-dirty-updates-stubs
          core-calls timing-calls finalize-arg nil nil
        (kuro--apply-dirty-updates)
        (should (= core-calls 0))))))

;;; Group 24c: kuro--apply-dirty-updates — delegates result to kuro--finalize-dirty-updates

(ert-deftest kuro-renderer-pipeline-apply-dirty-updates-passes-result-to-finalize ()
  "kuro--apply-dirty-updates passes the pipeline result to kuro--finalize-dirty-updates."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((finalize-arg :unset)
          (fake-updates '(a b c))
          (kuro-debug-perf nil))
      (kuro-renderer-pipeline-test--with-apply-dirty-updates-stubs
          core-calls timing-calls finalize-arg fake-updates nil
        (kuro--apply-dirty-updates)
        (should (equal finalize-arg fake-updates))))))

(ert-deftest kuro-renderer-pipeline-apply-dirty-updates-passes-nil-to-finalize ()
  "kuro--apply-dirty-updates passes nil to kuro--finalize-dirty-updates when pipeline returns nil."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((kuro-debug-perf nil))
      (kuro-renderer-pipeline-test--with-apply-dirty-updates-stubs
          core-calls timing-calls finalize-arg nil nil
        (kuro--apply-dirty-updates)
        (should (null finalize-arg))))))


(provide 'kuro-renderer-pipeline-test-3)

;;; kuro-renderer-pipeline-test-3.el ends here
