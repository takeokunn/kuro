;;; kuro-renderer-pipeline-ext3-test.el --- Pipeline tests: TUI, resize, env, budget  -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for kuro-renderer-pipeline.el — Groups 16-28, plus 25-26.
;; Groups 11b-15, 22b-24c are in kuro-renderer-pipeline-test.el.
;; Helper macros (kuro-renderer-pipeline-test--with-buffer etc.) are defined
;; in kuro-renderer-pipeline-test.el which loads before this file alphabetically.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-renderer-pipeline-test-support)

;;; Group 16: kuro--enter-tui-mode / kuro--exit-tui-mode

;; ── Timer side-effects ─────────────────────────────────────────────────────

(defconst kuro-renderer-pipeline-ext3-test--enter-exit-timer-table
  '((kuro-renderer-pipeline-ext3-enter-tui-mode-stops-idle-timer   kuro--enter-tui-mode stopped t)
    (kuro-renderer-pipeline-ext3-exit-tui-mode-restarts-idle-timer kuro--exit-tui-mode  started t))
  "Table of (test-name fn check-sym expectedp) for enter/exit timer side-effects.")

(defmacro kuro-renderer-pipeline-ext3-test--def-enter-exit-timer (test-name fn check-sym expectedp)
  `(ert-deftest ,test-name ()
     ,(format "Timer side-effect: `%s' — %s %s." fn check-sym
              (if expectedp "fires" "does not fire"))
     (kuro-renderer-pipeline-test--with-buffer
       (kuro-renderer-pipeline-test--with-tui-stubs stopped started switched
         (,fn)
         ,(if expectedp `(should ,check-sym) `(should-not ,check-sym))))))

(kuro-renderer-pipeline-ext3-test--def-enter-exit-timer kuro-renderer-pipeline-ext3-enter-tui-mode-stops-idle-timer   kuro--enter-tui-mode stopped t)
(kuro-renderer-pipeline-ext3-test--def-enter-exit-timer kuro-renderer-pipeline-ext3-exit-tui-mode-restarts-idle-timer kuro--exit-tui-mode  started t)

(ert-deftest kuro-renderer-pipeline-ext3-test--all-timer-side-effects-correct ()
  "All entries in `kuro-renderer-pipeline-ext3-test--enter-exit-timer-table' match behavior."
  (dolist (entry kuro-renderer-pipeline-ext3-test--enter-exit-timer-table)
    (pcase-let ((`(,_name ,fn ,check-sym ,expectedp) entry))
      (kuro-renderer-pipeline-test--with-buffer
        (kuro-renderer-pipeline-test--with-tui-stubs stopped started switched
          (funcall fn)
          (let ((val (if (eq check-sym 'stopped) stopped started)))
            (if expectedp (should val) (should-not val))))))))

;; ── Rate-switch assertions ──────────────────────────────────────────────────

(defconst kuro-renderer-pipeline-ext3-test--enter-exit-rate-table
  '((kuro-renderer-pipeline-ext3-enter-tui-mode-switches-to-tui-rate   kuro--enter-tui-mode kuro-tui-frame-rate t)
    (kuro-renderer-pipeline-ext3-exit-tui-mode-switches-to-normal-rate kuro--exit-tui-mode  kuro-frame-rate     t))
  "Table of (test-name fn rate expectedp) for enter/exit rate-switch assertions.")

(defmacro kuro-renderer-pipeline-ext3-test--def-enter-exit-rate (test-name fn rate expectedp)
  `(ert-deftest ,test-name ()
     ,(format "Rate-switch: `%s' switched to %s %s." fn rate
              (if expectedp "as expected" "not expected"))
     (kuro-renderer-pipeline-test--with-buffer
       (kuro-renderer-pipeline-test--with-tui-stubs stopped started switched
         (,fn)
         ,(if expectedp `(should (= switched ,rate)) `(should-not (= switched ,rate)))))))

(kuro-renderer-pipeline-ext3-test--def-enter-exit-rate kuro-renderer-pipeline-ext3-enter-tui-mode-switches-to-tui-rate   kuro--enter-tui-mode kuro-tui-frame-rate t)
(kuro-renderer-pipeline-ext3-test--def-enter-exit-rate kuro-renderer-pipeline-ext3-exit-tui-mode-switches-to-normal-rate kuro--exit-tui-mode  kuro-frame-rate     t)

(ert-deftest kuro-renderer-pipeline-ext3-test--all-rate-switches-correct ()
  "All entries in `kuro-renderer-pipeline-ext3-test--enter-exit-rate-table' match behavior."
  (dolist (entry kuro-renderer-pipeline-ext3-test--enter-exit-rate-table)
    (pcase-let ((`(,_name ,fn ,rate ,expectedp) entry))
      (kuro-renderer-pipeline-test--with-buffer
        (kuro-renderer-pipeline-test--with-tui-stubs stopped started switched
          (funcall fn)
          (if expectedp
              (should (= switched (symbol-value rate)))
            (should-not (= switched (symbol-value rate)))))))))

;; ── Active-flag assertions ──────────────────────────────────────────────────

(defconst kuro-renderer-pipeline-ext3-test--enter-exit-flag-table
  '((kuro-renderer-pipeline-ext3-enter-tui-mode-sets-active-flag   kuro--enter-tui-mode nil t)
    (kuro-renderer-pipeline-ext3-exit-tui-mode-clears-active-flag  kuro--exit-tui-mode  t   nil))
  "Table of (test-name fn init-active expected-active) for enter/exit flag toggles.")

(defmacro kuro-renderer-pipeline-ext3-test--def-enter-exit-flag (test-name fn init-val expected-val)
  `(ert-deftest ,test-name ()
     ,(format "Active flag: `%s' %s." fn (if expected-val "sets to t" "clears to nil"))
     (kuro-renderer-pipeline-test--with-buffer
       (setq kuro--tui-mode-active ,init-val)
       (kuro-renderer-pipeline-test--with-tui-stubs stopped started switched
         (,fn)
         ,(if expected-val `(should kuro--tui-mode-active) `(should-not kuro--tui-mode-active))))))

(kuro-renderer-pipeline-ext3-test--def-enter-exit-flag kuro-renderer-pipeline-ext3-enter-tui-mode-sets-active-flag   kuro--enter-tui-mode nil t)
(kuro-renderer-pipeline-ext3-test--def-enter-exit-flag kuro-renderer-pipeline-ext3-exit-tui-mode-clears-active-flag  kuro--exit-tui-mode  t   nil)

(ert-deftest kuro-renderer-pipeline-ext3-test--all-flag-toggles-correct ()
  "All entries in `kuro-renderer-pipeline-ext3-test--enter-exit-flag-table' match behavior."
  (dolist (entry kuro-renderer-pipeline-ext3-test--enter-exit-flag-table)
    (pcase-let ((`(,_name ,fn ,init-val ,expected-val) entry))
      (kuro-renderer-pipeline-test--with-buffer
        (setq kuro--tui-mode-active init-val)
        (kuro-renderer-pipeline-test--with-tui-stubs stopped started switched
          (funcall fn)
          (if expected-val
              (should kuro--tui-mode-active)
            (should-not kuro--tui-mode-active)))))))

;;; Group 18: kuro--finalize-dirty-updates

(ert-deftest kuro-renderer-pipeline-ext3-finalize-dirty-updates-records-count ()
  "kuro--finalize-dirty-updates sets kuro--last-dirty-count to (length updates)."
  (kuro-renderer-pipeline-test--with-buffer
    (cl-letf (((symbol-function 'kuro--evict-stale-col-to-buf-entries) #'ignore))
      (kuro--finalize-dirty-updates '(a b c))
      (should (= kuro--last-dirty-count 3)))))

(ert-deftest kuro-renderer-pipeline-ext3-finalize-dirty-updates-zero-on-nil ()
  "kuro--finalize-dirty-updates sets kuro--last-dirty-count to 0 for nil."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--last-dirty-count 99)
    (cl-letf (((symbol-function 'kuro--evict-stale-col-to-buf-entries) #'ignore))
      (kuro--finalize-dirty-updates nil)
      (should (= kuro--last-dirty-count 0)))))

(ert-deftest kuro-renderer-pipeline-ext3-finalize-dirty-updates-calls-evict ()
  "kuro--finalize-dirty-updates calls kuro--evict-stale-col-to-buf-entries."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((evict-called-with :unset))
      (cl-letf (((symbol-function 'kuro--evict-stale-col-to-buf-entries)
                 (lambda (u) (setq evict-called-with u))))
        (kuro--finalize-dirty-updates '(x y))
        (should (equal evict-called-with '(x y)))))))

;;; Group 19: kuro--core-render-pipeline

(ert-deftest kuro-renderer-pipeline-ext3-core-pipeline-returns-updates ()
  "kuro--core-render-pipeline returns the list from kuro--poll-updates-with-faces."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((fake-updates '((((0 . "text") . nil) . nil)))
          (kuro-use-binary-ffi nil))
      (cl-letf (((symbol-function 'kuro--apply-title-update)      #'ignore)
                ((symbol-function 'kuro--process-scroll-events)   #'ignore)
                ((symbol-function 'kuro--poll-updates-with-faces) (lambda () fake-updates))
                ((symbol-function 'kuro--apply-dirty-lines)       #'ignore)
                ((symbol-function 'kuro--update-cursor)           #'ignore))
        (should (equal (kuro--core-render-pipeline) fake-updates))))))

(ert-deftest kuro-renderer-pipeline-ext3-core-pipeline-returns-nil-when-no-updates ()
  "kuro--core-render-pipeline returns nil when poll returns nil."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((kuro-use-binary-ffi nil))
      (cl-letf (((symbol-function 'kuro--apply-title-update)      #'ignore)
                ((symbol-function 'kuro--process-scroll-events)   #'ignore)
                ((symbol-function 'kuro--poll-updates-with-faces) (lambda () nil))
                ((symbol-function 'kuro--apply-dirty-lines)       #'ignore)
                ((symbol-function 'kuro--update-cursor)           #'ignore))
        (should-not (kuro--core-render-pipeline))))))

(ert-deftest kuro-renderer-pipeline-ext3-core-pipeline-calls-all-steps ()
  "kuro--core-render-pipeline calls all 5 pipeline steps in order."
  (kuro-renderer-pipeline-test--with-buffer
    (let (log
          (kuro-use-binary-ffi nil))
      (cl-letf (((symbol-function 'kuro--apply-title-update)      (lambda () (push 'title log)))
                ((symbol-function 'kuro--process-scroll-events)   (lambda () (push 'scroll log)))
                ((symbol-function 'kuro--poll-updates-with-faces) (lambda () (push 'poll log) '(x)))
                ((symbol-function 'kuro--apply-dirty-lines)       (lambda (_) (push 'dirty log)))
                ((symbol-function 'kuro--update-cursor)           (lambda () (push 'cursor log))))
        (kuro--core-render-pipeline)
        (should (equal (nreverse log) '(title scroll poll dirty cursor)))))))

(provide 'kuro-renderer-pipeline-ext3-test)

;;; kuro-renderer-pipeline-ext3-test.el ends here
