;;; kuro-ffi-log-truncation-test.el --- Tests for kuro--log buffer truncation  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-ffi)

;;; Group 25: kuro--log buffer truncation

(cl-defmacro kuro-ffi-test--with-log-buf (buf-sym (&rest setup) &rest body)
  "Create *kuro-log*, run SETUP forms under inhibit-read-only, run BODY, then cleanup."
  (declare (indent 2))
  `(let ((kuro-log-errors t))
     (when (get-buffer kuro--log-buffer-name)
       (kill-buffer kuro--log-buffer-name))
     (unwind-protect
         (let ((,buf-sym (get-buffer-create kuro--log-buffer-name)))
           (with-current-buffer ,buf-sym
             (unless (derived-mode-p 'special-mode) (special-mode))
             (let ((inhibit-read-only t)) ,@setup))
           ,@body)
       (when (get-buffer kuro--log-buffer-name)
         (kill-buffer kuro--log-buffer-name)))))

(ert-deftest kuro-ffi-ext-log-truncation-removes-oldest-content ()
  "After truncation, the oldest content (inserted before overflow) is gone."
  (kuro-ffi-test--with-log-buf buf
      ((insert "OLDEST-SENTINEL\n")
       (insert (make-string kuro--log-max-size ?x))
       (insert "\n"))
    (kuro--log '(error "truncation-trigger"))
    (should-not (string-match-p "OLDEST-SENTINEL"
                                (with-current-buffer buf (buffer-string))))))

(ert-deftest kuro-ffi-ext-log-truncation-preserves-newest-content ()
  "After truncation, the entry that triggered truncation is still present."
  (kuro-ffi-test--with-log-buf buf
      ((insert (make-string (1+ kuro--log-max-size) ?y))
       (insert "\n"))
    (kuro--log '(error "NEWEST-SENTINEL"))
    (should (string-match-p "NEWEST-SENTINEL"
                            (with-current-buffer buf (buffer-string))))))

(ert-deftest kuro-ffi-ext-log-truncation-reduces-size-below-max ()
  "After truncation the buffer size is at most kuro--log-max-size bytes."
  (kuro-ffi-test--with-log-buf buf
      ((insert (make-string (* 2 kuro--log-max-size) ?z))
       (insert "\n"))
    (kuro--log '(error "size-check"))
    (should (< (with-current-buffer buf (buffer-size)) kuro--log-max-size))))

(ert-deftest kuro-ffi-ext-log-truncation-fires-at-threshold ()
  "Truncation fires when buffer size is just over kuro--log-max-size."
  (kuro-ffi-test--with-log-buf buf
      ((insert "AT-THRESHOLD-MARKER\n")
       (insert (make-string kuro--log-max-size ?t)))
    (kuro--log '(error "threshold-entry"))
    (should-not (string-match-p "AT-THRESHOLD-MARKER"
                                (with-current-buffer buf (buffer-string))))))

(provide 'kuro-ffi-log-truncation-test)
;;; kuro-ffi-log-truncation-test.el ends here
