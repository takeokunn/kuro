;;; kuro-ffi-ext-test.el --- Unit tests for kuro-ffi.el (log/show-log)  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-ffi.el (kuro--log, kuro-log-errors, kuro-show-log).
;; These tests exercise only pure Emacs Lisp logic without the Rust module.
;; All Rust FFI functions are stubbed with cl-letf.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-ffi)

;;; Test helpers

(defmacro kuro-ffi-test--with-stub (fn lambda-body &rest body)
  "Execute BODY with `kuro--initialized' t, `kuro--session-id' 1, and FN stubbed.
FN is a symbol; LAMBDA-BODY is the stub lambda expression (unquoted).
Reduces the repeated `(let ((kuro--initialized t)) (cl-letf ...))' boilerplate."
  `(let ((kuro--initialized t)
         (kuro--session-id 1))
     (cl-letf (((symbol-function ',fn) ,lambda-body))
       ,@body)))

;;; Group 23: kuro--log and kuro-log-errors

(ert-deftest kuro-ffi-call-logs-error-when-kuro-log-errors-enabled ()
  "kuro--call logs to *kuro-log* when kuro-log-errors is t and BODY errors."
  (let ((kuro--initialized t)
        (kuro-log-errors t))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))
    (kuro--call nil (error "test-log-error"))
    (let ((buf (get-buffer kuro--log-buffer-name)))
      (should buf)
      (should (string-match-p "ERROR: test-log-error"
                              (with-current-buffer buf (buffer-string))))
      (kill-buffer buf))))

(ert-deftest kuro-ffi-call-does-not-log-when-kuro-log-errors-disabled ()
  "kuro--call does not log when kuro-log-errors is nil."
  (let ((kuro--initialized t)
        (kuro-log-errors nil))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))
    (kuro--call nil (error "should-not-appear"))
    (let ((buf (get-buffer kuro--log-buffer-name)))
      (when buf
        (should (string= "" (with-current-buffer buf (buffer-string))))
        (kill-buffer buf)))))

(ert-deftest kuro-ffi-call-does-not-log-on-success ()
  "kuro--call does not write to *kuro-log* when BODY succeeds."
  (let ((kuro--initialized t)
        (kuro-log-errors t))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))
    (kuro--call nil 42)
    (let ((buf (get-buffer kuro--log-buffer-name)))
      (if buf
          (progn
            (should (string= "" (with-current-buffer buf (buffer-string))))
            (kill-buffer buf))
        (should-not buf)))))

(ert-deftest kuro-ffi-log-buffer-uses-special-mode ()
  "The *kuro-log* buffer uses special-mode (read-only)."
  (let ((kuro--initialized t)
        (kuro-log-errors t))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))
    (kuro--call nil (error "mode-test"))
    (let ((buf (get-buffer kuro--log-buffer-name)))
      (should buf)
      (with-current-buffer buf
        (should (derived-mode-p 'special-mode))
        (should buffer-read-only))
      (kill-buffer buf))))

(ert-deftest kuro-ffi-log-entries-have-timestamp-format ()
  "Each log entry has [HH:MM:SS] timestamp prefix."
  (let ((kuro--initialized t)
        (kuro-log-errors t))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))
    (kuro--call nil (error "timestamp-test"))
    (let ((buf (get-buffer kuro--log-buffer-name)))
      (should buf)
      (should (string-match-p "^\\[[0-9]\\{2\\}:[0-9]\\{2\\}:[0-9]\\{2\\}\\] ERROR:"
                              (with-current-buffer buf (buffer-string))))
      (kill-buffer buf))))

(ert-deftest kuro-ffi-show-log-creates-buffer ()
  "kuro-show-log creates the *kuro-log* buffer if it does not exist."
  (when (get-buffer kuro--log-buffer-name)
    (kill-buffer kuro--log-buffer-name))
  (save-window-excursion
    (kuro-show-log))
  (let ((buf (get-buffer kuro--log-buffer-name)))
    (should buf)
    (with-current-buffer buf
      (should (derived-mode-p 'special-mode)))
    (kill-buffer buf)))

(ert-deftest kuro-ffi-call-still-returns-fallback-when-logging ()
  "kuro--call returns fallback value even when logging is enabled."
  (let ((kuro--initialized t)
        (kuro-log-errors t))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))
    (should (= -1 (kuro--call -1 (error "fallback-with-log"))))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))))

;;; Group 24: kuro-show-log

(ert-deftest kuro-ffi-show-log-calls-display-buffer ()
  "kuro-show-log calls `display-buffer' with the log buffer."
  (let ((display-called-with nil))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))
    (cl-letf (((symbol-function 'display-buffer)
               (lambda (buf) (setq display-called-with buf))))
      (kuro-show-log))
    (should display-called-with)
    (should (bufferp display-called-with))
    (should (string= (buffer-name display-called-with) kuro--log-buffer-name))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))))

(ert-deftest kuro-ffi-show-log-idempotent-special-mode ()
  "Calling kuro-show-log twice leaves *kuro-log* in special-mode."
  (when (get-buffer kuro--log-buffer-name)
    (kill-buffer kuro--log-buffer-name))
  (cl-letf (((symbol-function 'display-buffer) #'ignore))
    (kuro-show-log)
    (kuro-show-log))
  (let ((buf (get-buffer kuro--log-buffer-name)))
    (should buf)
    (with-current-buffer buf
      (should (derived-mode-p 'special-mode)))
    (kill-buffer buf)))

(ert-deftest kuro-ffi-show-log-buffer-name-matches-constant ()
  "kuro-show-log creates a buffer whose name equals kuro--log-buffer-name."
  (when (get-buffer kuro--log-buffer-name)
    (kill-buffer kuro--log-buffer-name))
  (cl-letf (((symbol-function 'display-buffer) #'ignore))
    (kuro-show-log))
  (let ((buf (get-buffer kuro--log-buffer-name)))
    (should buf)
    (should (string= (buffer-name buf) kuro--log-buffer-name))
    (kill-buffer buf)))

;;; Group 25: kuro--log buffer truncation

(ert-deftest kuro-ffi-ext-log-truncation-removes-oldest-content ()
  "After truncation, the oldest content (inserted before overflow) is gone."
  (let ((kuro-log-errors t))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))
    (unwind-protect
        (let ((buf (get-buffer-create kuro--log-buffer-name)))
          (with-current-buffer buf
            (unless (derived-mode-p 'special-mode) (special-mode))
            (let ((inhibit-read-only t))
              ;; Insert a sentinel string at the very beginning, then pad the
              ;; buffer past kuro--log-max-size so the next kuro--log call
              ;; triggers deletion of the oldest half.
              (insert "OLDEST-SENTINEL\n")
              (insert (make-string kuro--log-max-size ?x))
              (insert "\n")))
          ;; One more log call should trigger truncation.
          (kuro--log '(error "truncation-trigger"))
          (let ((content (with-current-buffer buf (buffer-string))))
            (should-not (string-match-p "OLDEST-SENTINEL" content))))
      (when (get-buffer kuro--log-buffer-name)
        (kill-buffer kuro--log-buffer-name)))))

(ert-deftest kuro-ffi-ext-log-truncation-preserves-newest-content ()
  "After truncation, the entry that triggered truncation is still present."
  (let ((kuro-log-errors t))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))
    (unwind-protect
        (let ((buf (get-buffer-create kuro--log-buffer-name)))
          (with-current-buffer buf
            (unless (derived-mode-p 'special-mode) (special-mode))
            (let ((inhibit-read-only t))
              (insert (make-string (1+ kuro--log-max-size) ?y))
              (insert "\n")))
          (kuro--log '(error "NEWEST-SENTINEL"))
          (let ((content (with-current-buffer buf (buffer-string))))
            (should (string-match-p "NEWEST-SENTINEL" content))))
      (when (get-buffer kuro--log-buffer-name)
        (kill-buffer kuro--log-buffer-name)))))

(ert-deftest kuro-ffi-ext-log-truncation-reduces-size-below-max ()
  "After truncation the buffer size is at most kuro--log-max-size bytes."
  (let ((kuro-log-errors t))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))
    (unwind-protect
        (let ((buf (get-buffer-create kuro--log-buffer-name)))
          (with-current-buffer buf
            (unless (derived-mode-p 'special-mode) (special-mode))
            (let ((inhibit-read-only t))
              ;; Fill to exactly twice the max so the post-truncation size is
              ;; kuro--log-max-size/2 + the new entry (a short line), still
              ;; well under kuro--log-max-size.
              (insert (make-string (* 2 kuro--log-max-size) ?z))
              (insert "\n")))
          (kuro--log '(error "size-check"))
          (should (< (with-current-buffer buf (buffer-size))
                     kuro--log-max-size)))
      (when (get-buffer kuro--log-buffer-name)
        (kill-buffer kuro--log-buffer-name)))))

(ert-deftest kuro-ffi-ext-log-truncation-fires-at-threshold ()
  "Truncation fires when buffer size is just over kuro--log-max-size."
  (let ((kuro-log-errors t))
    (when (get-buffer kuro--log-buffer-name)
      (kill-buffer kuro--log-buffer-name))
    (unwind-protect
        (let ((buf (get-buffer-create kuro--log-buffer-name)))
          (with-current-buffer buf
            (unless (derived-mode-p 'special-mode) (special-mode))
            (let ((inhibit-read-only t))
              ;; Fill to exactly kuro--log-max-size; the new kuro--log entry
              ;; will push it just over the threshold.
              (insert "AT-THRESHOLD-MARKER\n")
              (insert (make-string kuro--log-max-size ?t))))
          ;; This call should push size over max and trigger truncation.
          (kuro--log '(error "threshold-entry"))
          ;; The old sentinel written before the pad should be gone.
          (let ((content (with-current-buffer buf (buffer-string))))
            (should-not (string-match-p "AT-THRESHOLD-MARKER" content))))
      (when (get-buffer kuro--log-buffer-name)
        (kill-buffer kuro--log-buffer-name)))))

(provide 'kuro-ffi-ext-test)

;;; kuro-ffi-ext-test.el ends here
