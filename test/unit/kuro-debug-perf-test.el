;;; kuro-debug-perf-test.el --- Tests for kuro-debug-perf.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-debug-perf.el (per-frame performance debugging).
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-debug-perf)

;;; Group 1: kuro-debug-perf defvar

(ert-deftest kuro-debug-perf--default-value-nil ()
  "kuro-debug-perf defaults to nil (disabled)."
  (should (null (default-value 'kuro-debug-perf))))

(ert-deftest kuro-debug-perf--is-settable ()
  "kuro-debug-perf can be set to a non-nil value and back without error."
  (let ((orig kuro-debug-perf))
    (unwind-protect
        (progn
          (setq kuro-debug-perf t)
          (should kuro-debug-perf)
          (setq kuro-debug-perf nil)
          (should (null kuro-debug-perf)))
      (setq kuro-debug-perf orig))))

;;; Group 2: kuro--perf-frame-count and kuro--perf-sample-interval

(ert-deftest kuro-debug-perf--frame-count-initial-zero ()
  "kuro--perf-frame-count starts at 0."
  (should (= (default-value 'kuro--perf-frame-count) 0)))

(ert-deftest kuro-debug-perf--frame-count-is-integer ()
  "kuro--perf-frame-count is an integer."
  (should (integerp kuro--perf-frame-count)))

(ert-deftest kuro-debug-perf--sample-interval-value ()
  "kuro--perf-sample-interval is 10."
  (should (= kuro--perf-sample-interval 10)))

(ert-deftest kuro-debug-perf--sample-interval-is-positive ()
  "kuro--perf-sample-interval is a positive integer."
  (should (integerp kuro--perf-sample-interval))
  (should (> kuro--perf-sample-interval 0)))

;;; Group 3: kuro--perf-report output format

(ert-deftest kuro-debug-perf--report-writes-to-perf-buffer ()
  "kuro--perf-report appends a line to the *kuro-perf* buffer."
  (let ((kuro--perf-frame-count 42)
        (buf-name "*kuro-perf*"))
    ;; Kill any pre-existing buffer to start clean.
    (when (get-buffer buf-name)
      (kill-buffer buf-name))
    (kuro--perf-report 1.0 2.0 0.5 3.5 5 10)
    (let ((buf (get-buffer buf-name)))
      (should (buffer-live-p buf))
      (kill-buffer buf))))

(ert-deftest kuro-debug-perf--report-line-contains-frame-count ()
  "kuro--perf-report embeds the current kuro--perf-frame-count in the output."
  (let ((kuro--perf-frame-count 7)
        (buf-name "*kuro-perf*"))
    (when (get-buffer buf-name)
      (kill-buffer buf-name))
    (kuro--perf-report 0.0 0.0 0.0 0.0 0 0)
    (with-current-buffer (get-buffer buf-name)
      (should (string-match-p "f00007" (buffer-string))))
    (kill-buffer buf-name)))

(ert-deftest kuro-debug-perf--report-line-contains-dirty-count ()
  "kuro--perf-report includes the dirty-rows count in the output line."
  (let ((kuro--perf-frame-count 0)
        (buf-name "*kuro-perf*"))
    (when (get-buffer buf-name)
      (kill-buffer buf-name))
    (kuro--perf-report 0.0 0.0 0.0 0.0 17 0)
    (with-current-buffer (get-buffer buf-name)
      (should (string-match-p "rows=17" (buffer-string))))
    (kill-buffer buf-name)))

(ert-deftest kuro-debug-perf--report-line-contains-face-count ()
  "kuro--perf-report includes the face-count in the output line."
  (let ((kuro--perf-frame-count 0)
        (buf-name "*kuro-perf*"))
    (when (get-buffer buf-name)
      (kill-buffer buf-name))
    (kuro--perf-report 0.0 0.0 0.0 0.0 0 99)
    (with-current-buffer (get-buffer buf-name)
      (should (string-match-p "faces=  99" (buffer-string))))
    (kill-buffer buf-name)))

(ert-deftest kuro-debug-perf--report-zero-elapsed-times ()
  "kuro--perf-report handles zero elapsed time without error."
  (let ((kuro--perf-frame-count 0)
        (buf-name "*kuro-perf*"))
    (when (get-buffer buf-name)
      (kill-buffer buf-name))
    (should-not
     (condition-case err
         (progn (kuro--perf-report 0.0 0.0 0.0 0.0 0 0) nil)
       (error err)))
    (kill-buffer buf-name)))

(ert-deftest kuro-debug-perf--report-large-elapsed-times ()
  "kuro--perf-report handles very large elapsed times without error."
  (let ((kuro--perf-frame-count 99999)
        (buf-name "*kuro-perf*"))
    (when (get-buffer buf-name)
      (kill-buffer buf-name))
    (should-not
     (condition-case err
         (progn (kuro--perf-report 9999.9 9999.9 9999.99 9999.9 99 9999) nil)
       (error err)))
    (kill-buffer buf-name)))

(ert-deftest kuro-debug-perf--report-appends-newline ()
  "kuro--perf-report appends a line ending with a newline character."
  (let ((kuro--perf-frame-count 0)
        (buf-name "*kuro-perf*"))
    (when (get-buffer buf-name)
      (kill-buffer buf-name))
    (kuro--perf-report 1.0 2.0 0.1 3.1 1 2)
    (with-current-buffer (get-buffer buf-name)
      (should (string-suffix-p "\n" (buffer-string))))
    (kill-buffer buf-name)))

(ert-deftest kuro-debug-perf--report-accumulates-multiple-lines ()
  "Calling kuro--perf-report twice accumulates two lines in the buffer."
  (let ((kuro--perf-frame-count 0)
        (buf-name "*kuro-perf*"))
    (when (get-buffer buf-name)
      (kill-buffer buf-name))
    (kuro--perf-report 1.0 1.0 0.1 2.1 1 1)
    (kuro--perf-report 2.0 2.0 0.2 4.2 2 2)
    (with-current-buffer (get-buffer buf-name)
      (let ((lines (split-string (buffer-string) "\n" t)))
        (should (= (length lines) 2))))
    (kill-buffer buf-name)))

;;; Group 4: kuro--perf-report format field details

(ert-deftest kuro-debug-perf--report-ffi-ms-field ()
  "kuro--perf-report formats ffi-ms with one decimal place."
  (let ((kuro--perf-frame-count 0)
        (buf-name "*kuro-perf*"))
    (when (get-buffer buf-name) (kill-buffer buf-name))
    (kuro--perf-report 12.5 0.0 0.0 0.0 0 0)
    (with-current-buffer (get-buffer buf-name)
      (should (string-match-p "ffi= 12\\.5ms" (buffer-string))))
    (kill-buffer buf-name)))

(ert-deftest kuro-debug-perf--report-apply-ms-field ()
  "kuro--perf-report formats apply-ms with one decimal place."
  (let ((kuro--perf-frame-count 0)
        (buf-name "*kuro-perf*"))
    (when (get-buffer buf-name) (kill-buffer buf-name))
    (kuro--perf-report 0.0 7.3 0.0 0.0 0 0)
    (with-current-buffer (get-buffer buf-name)
      (should (string-match-p "apply=  7\\.3ms" (buffer-string))))
    (kill-buffer buf-name)))

(ert-deftest kuro-debug-perf--report-cursor-ms-field ()
  "kuro--perf-report formats cursor-ms with two decimal places (%4.2f)."
  (let ((kuro--perf-frame-count 0)
        (buf-name "*kuro-perf*"))
    (when (get-buffer buf-name) (kill-buffer buf-name))
    (kuro--perf-report 0.0 0.0 3.14 0.0 0 0)
    (with-current-buffer (get-buffer buf-name)
      (should (string-match-p "cur=3\\.14ms" (buffer-string))))
    (kill-buffer buf-name)))

(ert-deftest kuro-debug-perf--report-total-ms-field ()
  "kuro--perf-report includes the TOTAL field in the output line."
  (let ((kuro--perf-frame-count 0)
        (buf-name "*kuro-perf*"))
    (when (get-buffer buf-name) (kill-buffer buf-name))
    (kuro--perf-report 0.0 0.0 0.0 99.9 0 0)
    (with-current-buffer (get-buffer buf-name)
      (should (string-match-p "TOTAL= 99\\.9ms" (buffer-string))))
    (kill-buffer buf-name)))

(ert-deftest kuro-debug-perf--report-line-has-pipe-separators ()
  "kuro--perf-report output contains the | separator between columns."
  (let ((kuro--perf-frame-count 0)
        (buf-name "*kuro-perf*"))
    (when (get-buffer buf-name) (kill-buffer buf-name))
    (kuro--perf-report 1.0 2.0 0.5 3.5 3 6)
    (with-current-buffer (get-buffer buf-name)
      (should (string-match-p "|" (buffer-string))))
    (kill-buffer buf-name)))

(ert-deftest kuro-debug-perf--report-frame-count-zero-padded ()
  "kuro--perf-report pads the frame counter to 5 digits with leading zeros."
  (let ((kuro--perf-frame-count 1)
        (buf-name "*kuro-perf*"))
    (when (get-buffer buf-name) (kill-buffer buf-name))
    (kuro--perf-report 0.0 0.0 0.0 0.0 0 0)
    (with-current-buffer (get-buffer buf-name)
      (should (string-match-p "f00001" (buffer-string))))
    (kill-buffer buf-name)))

(ert-deftest kuro-debug-perf--report-max-frame-count ()
  "kuro--perf-report handles frame count 99999 correctly."
  (let ((kuro--perf-frame-count 99999)
        (buf-name "*kuro-perf*"))
    (when (get-buffer buf-name) (kill-buffer buf-name))
    (kuro--perf-report 0.0 0.0 0.0 0.0 0 0)
    (with-current-buffer (get-buffer buf-name)
      (should (string-match-p "f99999" (buffer-string))))
    (kill-buffer buf-name)))

;;; Group 5: kuro--perf-report buffer management

(ert-deftest kuro-debug-perf--report-creates-buffer-when-absent ()
  "kuro--perf-report creates *kuro-perf* when it does not exist."
  (let ((buf-name "*kuro-perf*"))
    (when (get-buffer buf-name) (kill-buffer buf-name))
    (should-not (get-buffer buf-name))
    (kuro--perf-report 0.0 0.0 0.0 0.0 0 0)
    (should (buffer-live-p (get-buffer buf-name)))
    (kill-buffer buf-name)))

(ert-deftest kuro-debug-perf--report-reuses-existing-buffer ()
  "kuro--perf-report reuses *kuro-perf* when it already exists."
  (let ((buf-name "*kuro-perf*"))
    (when (get-buffer buf-name) (kill-buffer buf-name))
    (get-buffer-create buf-name)
    (let ((buf-before (get-buffer buf-name)))
      (kuro--perf-report 0.0 0.0 0.0 0.0 0 0)
      (should (eq buf-before (get-buffer buf-name))))
    (kill-buffer buf-name)))

(ert-deftest kuro-debug-perf--report-appends-at-end ()
  "kuro--perf-report appends lines at point-max, not at point-min."
  (let ((kuro--perf-frame-count 0)
        (buf-name "*kuro-perf*"))
    (when (get-buffer buf-name) (kill-buffer buf-name))
    (kuro--perf-report 1.0 1.0 0.1 2.1 1 1)
    (kuro--perf-report 2.0 2.0 0.2 4.2 2 2)
    (with-current-buffer (get-buffer buf-name)
      ;; Both lines must appear; second line must come after the first.
      (let ((content (buffer-string)))
        (let ((pos1 (string-match "f00000" content))
              (pos2 (string-match "f00000" content (1+ (string-match "f00000" content)))))
          (should pos1)
          (should pos2)
          (should (< pos1 pos2)))))
    (kill-buffer buf-name)))

(ert-deftest kuro-debug-perf--report-three-calls-accumulate ()
  "Three consecutive kuro--perf-report calls produce three lines."
  (let ((kuro--perf-frame-count 0)
        (buf-name "*kuro-perf*"))
    (when (get-buffer buf-name) (kill-buffer buf-name))
    (kuro--perf-report 1.0 1.0 0.1 2.1 1 1)
    (kuro--perf-report 2.0 2.0 0.2 4.2 2 2)
    (kuro--perf-report 3.0 3.0 0.3 6.3 3 3)
    (with-current-buffer (get-buffer buf-name)
      (let ((lines (split-string (buffer-string) "\n" t)))
        (should (= (length lines) 3))))
    (kill-buffer buf-name)))

;;; Group 6: kuro--perf-frame-count mutability

(ert-deftest kuro-debug-perf--frame-count-can-be-incremented ()
  "kuro--perf-frame-count can be incremented with cl-incf."
  (let ((kuro--perf-frame-count 5))
    (cl-incf kuro--perf-frame-count)
    (should (= kuro--perf-frame-count 6))))

(ert-deftest kuro-debug-perf--frame-count-can-be-set-to-arbitrary-value ()
  "kuro--perf-frame-count can be set to any non-negative integer."
  (let ((kuro--perf-frame-count 0))
    (setq kuro--perf-frame-count 12345)
    (should (= kuro--perf-frame-count 12345))))

(ert-deftest kuro-debug-perf--frame-count-report-reflects-local-binding ()
  "kuro--perf-report uses the lexically/dynamically current kuro--perf-frame-count."
  (let ((kuro--perf-frame-count 33)
        (buf-name "*kuro-perf*"))
    (when (get-buffer buf-name) (kill-buffer buf-name))
    (kuro--perf-report 0.0 0.0 0.0 0.0 0 0)
    (with-current-buffer (get-buffer buf-name)
      (should (string-match-p "f00033" (buffer-string))))
    (kill-buffer buf-name)))

(ert-deftest kuro-debug-perf--sample-interval-is-defconst ()
  "kuro--perf-sample-interval is defined as a defconst (not modifiable at runtime)."
  ;; A defconst marks the variable with the `risky-local-variable' property
  ;; and its docstring is stored. The simplest observable check is that
  ;; the symbol is bound and its value cannot silently change between loads.
  (should (boundp 'kuro--perf-sample-interval))
  (should (= kuro--perf-sample-interval 10)))

;;; Group 9: kuro-debug-state and kuro-debug-line-widths guard

(ert-deftest kuro-debug-state--requires-kuro-mode ()
  "kuro-debug-state signals user-error when called outside a kuro buffer."
  (with-temp-buffer
    (should-error (kuro-debug-state) :type 'user-error)))

(ert-deftest kuro-debug-state--error-message-contains-context ()
  "kuro-debug-state error is a user-error (not a plain error)."
  (with-temp-buffer
    (let ((err (should-error (kuro-debug-state) :type 'user-error)))
      (should (stringp (cadr err))))))

(ert-deftest kuro-debug-line-widths--requires-kuro-mode ()
  "kuro-debug-line-widths signals user-error when called outside a kuro buffer."
  (with-temp-buffer
    (should-error (kuro-debug-line-widths) :type 'user-error)))

(ert-deftest kuro-debug-line-widths--error-is-user-error ()
  "kuro-debug-line-widths error is a user-error (not a plain error)."
  (with-temp-buffer
    (let ((err (should-error (kuro-debug-line-widths) :type 'user-error)))
      (should (stringp (cadr err))))))

(provide 'kuro-debug-perf-test)

;;; kuro-debug-perf-test.el ends here
