;;; kuro-debug-perf-ext-test.el --- Extended tests for kuro-debug-perf.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Extended unit tests for kuro-debug-perf.el (happy-path state/line-widths).
;; Split from kuro-debug-perf-test.el at Group 9 boundary.
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-debug-perf)

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

(provide 'kuro-debug-perf-ext-test)

;;; kuro-debug-perf-ext-test.el ends here
