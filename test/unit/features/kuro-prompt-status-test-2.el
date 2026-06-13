;;; kuro-prompt-status-test-2.el --- ERT tests for kuro-prompt-status.el (part 2)  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;;; Commentary:

;; ERT tests for kuro-prompt-status.el (prompt exit-status indicators), part 2.
;;
;; Groups:
;;   Group 7: kuro-prompt-status-min-duration-ms threshold
;;   Group 8: mode-line exit-status segment
;;   Group 9: kuro--apply-prompt-extras-overlay

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Stub FFI symbols so kuro-prompt-status loads without the Rust module.
(dolist (sym '(kuro-core-init
               kuro-core-send-key
               kuro-core-poll-updates
               kuro-core-poll-updates-with-faces
               kuro-core-resize
               kuro-core-shutdown
               kuro-core-get-cursor
               kuro-core-get-cursor-visible
               kuro-core-get-cursor-shape
               kuro-core-is-process-alive))
  (unless (fboundp sym)
    (fset sym (lambda (&rest _) nil))))

(unless (fboundp 'module-load)
  (fset 'module-load (lambda (_path) nil)))

(let* ((this-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory)))
       (el-dir (expand-file-name "../../emacs-lisp" this-dir)))
  (add-to-list 'load-path el-dir t))

(require 'kuro-prompt-status)

;;; Helpers

(defmacro kuro-prompt-status-test--with-buffer (&rest body)
  "Run BODY in a temp buffer with prompt status state initialized."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (kuro--prompt-status-overlays nil)
           (kuro-prompt-status-annotations t)
           (kuro-prompt-status-success-indicator "✓")
           (kuro-prompt-status-failure-indicator "✗"))
       ,@body)))

;;; Group 7: kuro-prompt-status-min-duration-ms threshold

(ert-deftest kuro-prompt-status--min-duration-default-is-zero ()
  "`kuro-prompt-status-min-duration-ms' defaults to 0 (show all durations)."
  (should (= (default-value 'kuro-prompt-status-min-duration-ms) 0)))

(ert-deftest kuro-prompt-status--duration-shown-at-or-above-threshold ()
  "Duration appears in extras when duration-ms >= threshold."
  (let ((kuro-prompt-status-min-duration-ms 2000))
    (let ((result (kuro--format-prompt-extras nil 2000 nil)))
      (should (and result (string-match-p "2.0s" result))))))

(ert-deftest kuro-prompt-status--duration-suppressed-below-threshold ()
  "Duration is suppressed from extras when duration-ms < threshold."
  (let ((kuro-prompt-status-min-duration-ms 2000))
    (let ((result (kuro--format-prompt-extras nil 500 nil)))
      (should (null result)))))

(ert-deftest kuro-prompt-status--duration-shown-when-threshold-zero ()
  "With threshold 0 (default), all durations including fast ones are shown."
  (let ((kuro-prompt-status-min-duration-ms 0))
    (let ((result (kuro--format-prompt-extras nil 50 nil)))
      (should (and result (string-match-p "50ms" result))))))

(ert-deftest kuro-prompt-status--aid-still-shown-below-threshold ()
  "Aid annotation is unaffected by duration threshold."
  (let ((kuro-prompt-status-min-duration-ms 2000))
    (let ((result (kuro--format-prompt-extras "abc" 100 nil)))
      (should (and result (string-match-p "aid=abc" result))))))

(ert-deftest kuro-prompt-status--threshold-exact-boundary-is-inclusive ()
  "Duration equal to threshold is shown (>= not >)."
  (let ((kuro-prompt-status-min-duration-ms 1000))
    (let ((result (kuro--format-prompt-extras nil 1000 nil)))
      (should (and result (string-match-p "1.0s" result))))))

;;; Group 8: mode-line exit-status segment

(ert-deftest kuro-prompt-status--records-last-exit-code ()
  "`kuro--update-prompt-status' records the most recent command-end exit code."
  (kuro-prompt-status-test--with-buffer
    (dotimes (_ 10) (insert "line\n"))
    (let ((kuro--last-exit-code nil))
      (kuro--update-prompt-status '(("command-end" 2 0 0)
                                    ("command-end" 4 0 3)))
      (should (= kuro--last-exit-code 3)))))

(ert-deftest kuro-prompt-status--records-exit-even-when-annotations-off ()
  "Exit code is tracked for the mode line even when margin annotations are off."
  (kuro-prompt-status-test--with-buffer
    (dotimes (_ 10) (insert "line\n"))
    (let ((kuro-prompt-status-annotations nil)
          (kuro--last-exit-code nil))
      (kuro--update-prompt-status '(("command-end" 2 0 7)))
      (should (= kuro--last-exit-code 7))
      (should (null kuro--prompt-status-overlays)))))

(ert-deftest kuro-prompt-status--segment-empty-before-any-command ()
  "The segment is an empty string when no command has completed."
  (kuro-prompt-status-test--with-buffer
    (let ((kuro--last-exit-code nil))
      (should (equal (kuro-prompt-status-mode-line-segment) "")))))

(ert-deftest kuro-prompt-status--segment-shows-success-indicator ()
  "Exit 0 renders the success indicator with the success face."
  (kuro-prompt-status-test--with-buffer
    (let ((kuro--last-exit-code 0))
      (let ((seg (kuro-prompt-status-mode-line-segment)))
        (should (string-match-p "✓" seg))
        (should (eq (get-text-property (1- (length seg)) 'face seg)
                    'kuro-prompt-success))))))

(ert-deftest kuro-prompt-status--segment-shows-failure-with-code ()
  "Non-zero exit renders the failure indicator plus the numeric code."
  (kuro-prompt-status-test--with-buffer
    (let ((kuro--last-exit-code 127))
      (let ((seg (kuro-prompt-status-mode-line-segment)))
        (should (string-match-p "✗127" seg))
        (should (eq (get-text-property (1- (length seg)) 'face seg)
                    'kuro-prompt-failure))))))

(ert-deftest kuro-prompt-status--install-mode-line-idempotent ()
  "`kuro-prompt-status-install-mode-line' appends the segment exactly once."
  (with-temp-buffer
    (setq-local mode-line-format '("%b"))
    (kuro-prompt-status-install-mode-line)
    (kuro-prompt-status-install-mode-line)
    (let ((count (cl-count '(:eval (kuro-prompt-status-mode-line-segment))
                           mode-line-format :test #'equal)))
      (should (= count 1)))))

(ert-deftest kuro-prompt-status--install-mode-line-wraps-non-list-format ()
  "`kuro-prompt-status-install-mode-line' wraps a non-list `mode-line-format' in a list first."
  (with-temp-buffer
    ;; mode-line-format as a plain string (non-list)
    (setq-local mode-line-format "%b %m")
    (kuro-prompt-status-install-mode-line)
    (should (listp mode-line-format))
    (should (member '(:eval (kuro-prompt-status-mode-line-segment)) mode-line-format))
    ;; The original string is preserved as the first element
    (should (equal (car mode-line-format) "%b %m"))))

;;; Group 9: kuro--apply-prompt-extras-overlay

(ert-deftest kuro-prompt-status-apply-extras-overlay-nil-all-is-noop ()
  "`kuro--apply-prompt-extras-overlay' does nothing when all extras are nil."
  (with-temp-buffer
    (insert "line0\n")
    (let ((kuro--prompt-status-overlays nil))
      (kuro--apply-prompt-extras-overlay 0 nil nil nil)
      (should (null kuro--prompt-status-overlays)))))

(defconst kuro-prompt-status-test--extras-creates-table
  '((kuro-prompt-status-apply-extras-overlay-with-aid-creates-overlay      "abc123" nil  nil)
    (kuro-prompt-status-apply-extras-overlay-with-duration-creates-overlay nil     1500 nil))
  "Table of (test-name aid duration-ms err-path) that each produce 1 extras overlay.")

(defmacro kuro-prompt-status-test--def-extras-creates
    (test-name aid duration-ms err-path)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--apply-prompt-extras-overlay' aid=%S duration=%S → 1 overlay."
              aid duration-ms)
     (with-temp-buffer
       (insert "line0\n")
       (let ((kuro--prompt-status-overlays nil))
         (kuro--apply-prompt-extras-overlay 0 ,aid ,duration-ms ,err-path)
         (should (= (length kuro--prompt-status-overlays) 1))
         (should (overlay-get (car kuro--prompt-status-overlays) 'kuro-prompt-extras))))))

(kuro-prompt-status-test--def-extras-creates
 kuro-prompt-status-apply-extras-overlay-with-aid-creates-overlay      "abc123" nil  nil)
(kuro-prompt-status-test--def-extras-creates
 kuro-prompt-status-apply-extras-overlay-with-duration-creates-overlay nil     1500 nil)

(ert-deftest kuro-prompt-status--extras-creates-all-variants ()
  "Invariant: apply-extras-overlay creates 1 kuro-prompt-extras overlay for each non-nil input."
  (dolist (entry kuro-prompt-status-test--extras-creates-table)
    (pcase-let ((`(,_name ,aid ,duration-ms ,err-path) entry))
      (with-temp-buffer
        (insert "line0\n")
        (let ((kuro--prompt-status-overlays nil))
          (kuro--apply-prompt-extras-overlay 0 aid duration-ms err-path)
          (should (= (length kuro--prompt-status-overlays) 1))
          (should (overlay-get (car kuro--prompt-status-overlays) 'kuro-prompt-extras)))))))

(ert-deftest kuro-prompt-status-apply-extras-overlay-beyond-buffer-is-noop ()
  "`kuro--apply-prompt-extras-overlay' does nothing when ROW is past buffer end."
  (with-temp-buffer
    (insert "one-line\n")
    (let ((kuro--prompt-status-overlays nil))
      (kuro--apply-prompt-extras-overlay 99 "x" nil nil)
      (should (null kuro--prompt-status-overlays)))))

(provide 'kuro-prompt-status-test-2)

;;; kuro-prompt-status-test-2.el ends here
