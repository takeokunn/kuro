;;; kuro-url-detect-test-macros.el --- Macros for kuro-url-detect tests  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-url-detect)
(require 'kuro-url-detect-test-cases)

(defmacro kuro-url-detect-test--with-buffer (&rest body)
  "Run BODY in a temp buffer with URL detection state initialized to defaults."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (kuro--url-overlays nil)
           (kuro--url-detect-timer nil)
           (kuro-url-detection t))
       ,@body)))

(defmacro kuro-url-detect-test--deftest-url-matches (table)
  "Generate URL regexp tests from TABLE."
  (declare (indent 1))
  `(progn
     ,@(mapcar
        (lambda (case)
          (let ((test-name (nth 0 case))
                (url (nth 1 case)))
            `(ert-deftest ,test-name ()
               ,(format "`kuro--url-regexp' matches `%s'." url)
               (should (string-match kuro--url-regexp ,url)))))
        (symbol-value table))))

(defmacro kuro-url-detect-test--deftest-trailing-punctuation (table)
  "Generate URL trailing punctuation tests from TABLE."
  (declare (indent 1))
  `(progn
     ,@(mapcar
        (lambda (case)
          (let ((test-name (nth 0 case))
                (input (nth 1 case))
                (expected (nth 2 case)))
            `(ert-deftest ,test-name ()
               ,(format "`kuro--url-regexp' excludes trailing punctuation in `%s'."
                        input)
               (string-match kuro--url-regexp ,input)
               (should (string= (match-string 0 ,input) ,expected)))))
        (symbol-value table))))

(defmacro kuro-url-detect-test--deftest-defcustom-defaults (table)
  "Generate defcustom default tests from TABLE."
  (declare (indent 1))
  `(progn
     ,@(mapcar
        (lambda (case)
          (let ((test-name (nth 0 case))
                (variable (nth 1 case))
                (expected (nth 2 case))
                (predicate (nth 3 case)))
            `(ert-deftest ,test-name ()
               ,(format "`%s' defcustom defaults to `%s'." variable expected)
               (should (,predicate (default-value ',variable) ,expected)))))
        (symbol-value table))))

(defmacro kuro-url-detect-test--deftest-detection-proceeds (table)
  "Generate visible detection tests from TABLE."
  (declare (indent 1))
  `(progn
     ,@(mapcar
        (lambda (case)
          (let ((test-name (nth 0 case))
                (url-flag (nth 1 case)))
            `(ert-deftest ,test-name ()
               ,(format "`kuro--url-detect-visible' scans when url=%s."
                        url-flag)
               (kuro-url-detect-test--with-buffer
                 (let ((kuro-url-detection ,url-flag)
                       (scanned nil))
                   (cl-letf (((symbol-function 'derived-mode-p)
                              (lambda (&rest _) t))
                             ((symbol-function 'window-start)
                              (lambda () (point-min)))
                             ((symbol-function 'window-end)
                              (lambda (_w _u) (point-max)))
                             ((symbol-function 'kuro--scan-urls-in-region)
                              (lambda (&rest _) (setq scanned t))))
                     (kuro--url-detect-visible)
                     (should scanned)))))))
        (symbol-value table))))

(provide 'kuro-url-detect-test-macros)
;;; kuro-url-detect-test-macros.el ends here
