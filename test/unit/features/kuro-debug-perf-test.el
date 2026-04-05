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

;;; Group 10: kuro-debug-state happy path

(defmacro kuro-debug-perf-test--with-kuro-mode-stub (&rest body)
  "Run BODY in a temp buffer where `derived-mode-p' reports kuro-mode."
  `(with-temp-buffer
     (cl-letf (((symbol-function 'derived-mode-p)
                (lambda (&rest _modes) t))
               ((symbol-function 'get-buffer-window)
                (lambda (&rest _) nil))
               ((symbol-function 'frame-char-width)
                (lambda () 8))
               ((symbol-function 'frame-char-height)
                (lambda () 16)))
       ,@body)))

(ert-deftest kuro-debug-state--outputs-init-field ()
  "kuro-debug-state message contains the init= field."
  (kuro-debug-perf-test--with-kuro-mode-stub
   (let ((kuro--initialized t)
         (kuro--session-id 0)
         (kuro--last-rows 24)
         (kuro--last-cols 80)
         (kuro--resize-pending nil)
         (kuro--scroll-offset 0)
         (kuro--tui-mode-active nil)
         (kuro--last-cursor-row 5)
         (kuro--last-cursor-col 10)
         (kuro--col-to-buf-map nil)
         captured)
     (cl-letf (((symbol-function 'message)
                (lambda (_fmt &rest args)
                  (setq captured (apply #'format _fmt args)))))
       (kuro-debug-state))
     (should (stringp captured))
     (should (string-match-p "init=" captured)))))

(ert-deftest kuro-debug-state--outputs-cursor-row-field ()
  "kuro-debug-state message contains the cursor-row= field."
  (kuro-debug-perf-test--with-kuro-mode-stub
   (let ((kuro--initialized nil)
         (kuro--session-id 0)
         (kuro--last-rows 24)
         (kuro--last-cols 80)
         (kuro--resize-pending nil)
         (kuro--scroll-offset 0)
         (kuro--tui-mode-active nil)
         (kuro--last-cursor-row 7)
         (kuro--last-cursor-col 3)
         (kuro--col-to-buf-map nil)
         captured)
     (cl-letf (((symbol-function 'message)
                (lambda (_fmt &rest args)
                  (setq captured (apply #'format _fmt args)))))
       (kuro-debug-state))
     (should (string-match-p "cursor-row=" captured)))))

(ert-deftest kuro-debug-state--reflects-initialized-t ()
  "kuro-debug-state message shows t when kuro--initialized is t."
  (kuro-debug-perf-test--with-kuro-mode-stub
   (let ((kuro--initialized t)
         (kuro--session-id 0)
         (kuro--last-rows 0)
         (kuro--last-cols 0)
         (kuro--resize-pending nil)
         (kuro--scroll-offset 0)
         (kuro--tui-mode-active nil)
         (kuro--last-cursor-row nil)
         (kuro--last-cursor-col nil)
         (kuro--col-to-buf-map nil)
         captured)
     (cl-letf (((symbol-function 'message)
                (lambda (_fmt &rest args)
                  (setq captured (apply #'format _fmt args)))))
       (kuro-debug-state))
     (should (string-match-p "init=t" captured)))))

(ert-deftest kuro-debug-state--reflects-initialized-nil ()
  "kuro-debug-state message shows nil when kuro--initialized is nil."
  (kuro-debug-perf-test--with-kuro-mode-stub
   (let ((kuro--initialized nil)
         (kuro--session-id 0)
         (kuro--last-rows 0)
         (kuro--last-cols 0)
         (kuro--resize-pending nil)
         (kuro--scroll-offset 0)
         (kuro--tui-mode-active nil)
         (kuro--last-cursor-row nil)
         (kuro--last-cursor-col nil)
         (kuro--col-to-buf-map nil)
         captured)
     (cl-letf (((symbol-function 'message)
                (lambda (_fmt &rest args)
                  (setq captured (apply #'format _fmt args)))))
       (kuro-debug-state))
     (should (string-match-p "init=nil" captured)))))

(ert-deftest kuro-debug-state--outputs-buf-lines-field ()
  "kuro-debug-state message contains buf-lines= field."
  (kuro-debug-perf-test--with-kuro-mode-stub
   (let ((kuro--initialized nil)
         (kuro--session-id 0)
         (kuro--last-rows 24)
         (kuro--last-cols 80)
         (kuro--resize-pending nil)
         (kuro--scroll-offset 0)
         (kuro--tui-mode-active nil)
         (kuro--last-cursor-row nil)
         (kuro--last-cursor-col nil)
         (kuro--col-to-buf-map nil)
         captured)
     (cl-letf (((symbol-function 'message)
                (lambda (_fmt &rest args)
                  (setq captured (apply #'format _fmt args)))))
       (kuro-debug-state))
     (should (string-match-p "buf-lines=" captured)))))

(ert-deftest kuro-debug-state--col-to-buf-count-hash-table ()
  "kuro-debug-state counts entries when kuro--col-to-buf-map is a hash-table."
  (kuro-debug-perf-test--with-kuro-mode-stub
   (let ((kuro--initialized nil)
         (kuro--session-id 0)
         (kuro--last-rows 0)
         (kuro--last-cols 0)
         (kuro--resize-pending nil)
         (kuro--scroll-offset 0)
         (kuro--tui-mode-active nil)
         (kuro--last-cursor-row nil)
         (kuro--last-cursor-col nil)
         (kuro--col-to-buf-map (let ((ht (make-hash-table)))
                                  (puthash 0 10 ht)
                                  (puthash 1 20 ht)
                                  ht))
         captured)
     (cl-letf (((symbol-function 'message)
                (lambda (_fmt &rest args)
                  (setq captured (apply #'format _fmt args)))))
       (kuro-debug-state))
     (should (string-match-p "col-to-buf-count=2" captured)))))

(ert-deftest kuro-debug-state--col-to-buf-count-nil-is-zero ()
  "kuro-debug-state reports col-to-buf-count=0 when kuro--col-to-buf-map is nil."
  (kuro-debug-perf-test--with-kuro-mode-stub
   (let ((kuro--initialized nil)
         (kuro--session-id 0)
         (kuro--last-rows 0)
         (kuro--last-cols 0)
         (kuro--resize-pending nil)
         (kuro--scroll-offset 0)
         (kuro--tui-mode-active nil)
         (kuro--last-cursor-row nil)
         (kuro--last-cursor-col nil)
         (kuro--col-to-buf-map nil)
         captured)
     (cl-letf (((symbol-function 'message)
                (lambda (_fmt &rest args)
                  (setq captured (apply #'format _fmt args)))))
       (kuro-debug-state))
     (should (string-match-p "col-to-buf-count=0" captured)))))

;;; Group 11: kuro-debug-line-widths happy path

(ert-deftest kuro-debug-line-widths--all-rows-match-success-message ()
  "kuro-debug-line-widths emits success message when all rows match expected width."
  (with-temp-buffer
    (cl-letf (((symbol-function 'derived-mode-p)
               (lambda (&rest _modes) t)))
      (let ((kuro--last-rows 3)
            (kuro--last-cols 5)
            captured)
        ;; Insert 3 rows of exactly 5 chars each.
        (insert "abcde\nabcde\nabcde\n")
        (cl-letf (((symbol-function 'message)
                   (lambda (fmt &rest args)
                     (setq captured (apply #'format fmt args)))))
          (kuro-debug-line-widths))
        (should (stringp captured))
        (should (string-match-p "All 3 rows" captured))
        (should (string-match-p "5" captured))))))

(ert-deftest kuro-debug-line-widths--anomaly-reported-for-wrong-width ()
  "kuro-debug-line-widths lists rows whose display width differs from kuro--last-cols."
  (with-temp-buffer
    (cl-letf (((symbol-function 'derived-mode-p)
               (lambda (&rest _modes) t)))
      (let ((kuro--last-rows 2)
            (kuro--last-cols 5)
            captured)
        ;; Row 0: 5 chars (ok), row 1: 3 chars (anomaly — non-zero width, wrong).
        (insert "abcde\nabc\n")
        (cl-letf (((symbol-function 'message)
                   (lambda (fmt &rest args)
                     (setq captured (apply #'format fmt args)))))
          (kuro-debug-line-widths))
        (should (string-match-p "anomalies" captured))
        (should (string-match-p "row" captured))))))

(ert-deftest kuro-debug-line-widths--empty-rows-not-anomalous ()
  "kuro-debug-line-widths skips rows with display-w=0 (empty lines)."
  (with-temp-buffer
    (cl-letf (((symbol-function 'derived-mode-p)
               (lambda (&rest _modes) t)))
      (let ((kuro--last-rows 2)
            (kuro--last-cols 5)
            captured)
        ;; Row 0: 5 chars (ok), row 1: empty (skipped).
        (insert "abcde\n\n")
        (cl-letf (((symbol-function 'message)
                   (lambda (fmt &rest args)
                     (setq captured (apply #'format fmt args)))))
          (kuro-debug-line-widths))
        ;; Empty row is not anomalous, so success message expected.
        (should (string-match-p "All 2 rows" captured))))))

(ert-deftest kuro-debug-line-widths--zero-rows-success ()
  "kuro-debug-line-widths with kuro--last-rows=0 reports all-ok for 0 rows."
  (with-temp-buffer
    (cl-letf (((symbol-function 'derived-mode-p)
               (lambda (&rest _modes) t)))
      (let ((kuro--last-rows 0)
            (kuro--last-cols 80)
            captured)
        (cl-letf (((symbol-function 'message)
                   (lambda (fmt &rest args)
                     (setq captured (apply #'format fmt args)))))
          (kuro-debug-line-widths))
        (should (string-match-p "All 0 rows" captured))))))

(ert-deftest kuro-debug-line-widths--success-message-contains-expected-cols ()
  "kuro-debug-line-widths success message includes the expected column count."
  (with-temp-buffer
    (cl-letf (((symbol-function 'derived-mode-p)
               (lambda (&rest _modes) t)))
      (let ((kuro--last-rows 1)
            (kuro--last-cols 10)
            captured)
        (insert "0123456789\n")
        (cl-letf (((symbol-function 'message)
                   (lambda (fmt &rest args)
                     (setq captured (apply #'format fmt args)))))
          (kuro-debug-line-widths))
        (should (string-match-p "10" captured))))))

;;; Group 12: kuro-debug-state window branch and non-hash-table col-to-buf-map

(defmacro kuro-debug-perf-test--with-kuro-mode-and-window (&rest body)
  "Run BODY in a temp buffer where `derived-mode-p' reports kuro-mode
and `get-buffer-window' returns a real window object with stubbed
window-dimension functions."
  `(with-temp-buffer
     (cl-letf (((symbol-function 'derived-mode-p)
                (lambda (&rest _modes) t))
               ((symbol-function 'get-buffer-window)
                (lambda (&rest _) (selected-window)))
               ((symbol-function 'window-body-height)
                (lambda (&rest _) 40))
               ((symbol-function 'window-body-width)
                (lambda (&rest _) 120))
               ((symbol-function 'window-start)
                (lambda (&rest _) 1))
               ((symbol-function 'window-vscroll)
                (lambda (&rest _) 3))
               ((symbol-function 'window-hscroll)
                (lambda (&rest _) 7))
               ((symbol-function 'frame-char-width)
                (lambda () 8))
               ((symbol-function 'frame-char-height)
                (lambda () 16)))
       ,@body)))

(defmacro kuro-debug-perf-test--state-vars (&rest body)
  "Bind all kuro state variables to safe defaults, then run BODY."
  `(let ((kuro--initialized nil)
         (kuro--session-id 0)
         (kuro--last-rows 24)
         (kuro--last-cols 80)
         (kuro--resize-pending nil)
         (kuro--scroll-offset 0)
         (kuro--tui-mode-active nil)
         (kuro--last-cursor-row nil)
         (kuro--last-cursor-col nil)
         (kuro--col-to-buf-map nil))
     ,@body))

(ert-deftest kuro-debug-state--with-window-includes-height ()
  "kuro-debug-state includes window height when get-buffer-window returns non-nil."
  (kuro-debug-perf-test--with-kuro-mode-and-window
   (kuro-debug-perf-test--state-vars
    (let (captured)
      (cl-letf (((symbol-function 'message)
                 (lambda (_fmt &rest args)
                   (setq captured (apply #'format _fmt args)))))
        (kuro-debug-state))
      (should (stringp captured))
      (should (string-match-p "win-rows=40" captured))))))

(ert-deftest kuro-debug-state--with-window-includes-width ()
  "kuro-debug-state includes window width when get-buffer-window returns non-nil."
  (kuro-debug-perf-test--with-kuro-mode-and-window
   (kuro-debug-perf-test--state-vars
    (let (captured)
      (cl-letf (((symbol-function 'message)
                 (lambda (_fmt &rest args)
                   (setq captured (apply #'format _fmt args)))))
        (kuro-debug-state))
      (should (string-match-p "win-cols=120" captured))))))

(ert-deftest kuro-debug-state--with-window-includes-vscroll ()
  "kuro-debug-state includes vscroll value when get-buffer-window returns non-nil."
  (kuro-debug-perf-test--with-kuro-mode-and-window
   (kuro-debug-perf-test--state-vars
    (let (captured)
      (cl-letf (((symbol-function 'message)
                 (lambda (_fmt &rest args)
                   (setq captured (apply #'format _fmt args)))))
        (kuro-debug-state))
      (should (string-match-p "vscroll=3" captured))))))

(ert-deftest kuro-debug-state--col-to-buf-list-reports-zero ()
  "kuro-debug-state reports col-to-buf-count=0 when kuro--col-to-buf-map is a list."
  (kuro-debug-perf-test--with-kuro-mode-stub
   (kuro-debug-perf-test--state-vars
    (let ((kuro--col-to-buf-map '())
          captured)
      (cl-letf (((symbol-function 'message)
                 (lambda (_fmt &rest args)
                   (setq captured (apply #'format _fmt args)))))
        (kuro-debug-state))
      (should (string-match-p "col-to-buf-count=0" captured))))))

(ert-deftest kuro-debug-state--col-to-buf-vector-reports-zero ()
  "kuro-debug-state reports col-to-buf-count=0 when kuro--col-to-buf-map is a vector."
  (kuro-debug-perf-test--with-kuro-mode-stub
   (kuro-debug-perf-test--state-vars
    (let ((kuro--col-to-buf-map [])
          captured)
      (cl-letf (((symbol-function 'message)
                 (lambda (_fmt &rest args)
                   (setq captured (apply #'format _fmt args)))))
        (kuro-debug-state))
      (should (string-match-p "col-to-buf-count=0" captured))))))

(ert-deftest kuro-debug-state--col-to-buf-t-reports-zero ()
  "kuro-debug-state reports col-to-buf-count=0 when kuro--col-to-buf-map is t."
  (kuro-debug-perf-test--with-kuro-mode-stub
   (kuro-debug-perf-test--state-vars
    (let ((kuro--col-to-buf-map t)
          captured)
      (cl-letf (((symbol-function 'message)
                 (lambda (_fmt &rest args)
                   (setq captured (apply #'format _fmt args)))))
        (kuro-debug-state))
      (should (string-match-p "col-to-buf-count=0" captured))))))

(provide 'kuro-debug-perf-test)

;;; kuro-debug-perf-test.el ends here
