;;; kuro-dnd-test.el --- Unit tests for kuro-dnd.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;;; Commentary:
;; Unit tests for drag-and-drop support in Kuro terminal buffers.
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-dnd)

;;; Group 1: kuro-dnd-handle-uri

(ert-deftest kuro-dnd--handle-uri-sends-shell-quoted-path ()
  "kuro-dnd-handle-uri sends shell-quoted file path via kuro--send-key."
  (let ((sent nil))
    (cl-letf (((symbol-function 'kuro--send-key)
               (lambda (s) (setq sent s)))
              ((symbol-function 'dnd-get-local-file-name)
               (lambda (_uri _must-exist) "/tmp/my file.txt")))
      (kuro-dnd-handle-uri "file:///tmp/my file.txt" nil)
      (should (stringp sent))
      (should (string-match-p "my\\\\ file\\.txt" sent)))))

(ert-deftest kuro-dnd--handle-uri-returns-private ()
  "kuro-dnd-handle-uri returns `private' on success."
  (cl-letf (((symbol-function 'kuro--send-key) #'ignore)
            ((symbol-function 'dnd-get-local-file-name)
             (lambda (_uri _must-exist) "/tmp/test.txt")))
    (should (eq 'private (kuro-dnd-handle-uri "file:///tmp/test.txt" nil)))))

(ert-deftest kuro-dnd--handle-uri-returns-nil-for-non-file ()
  "kuro-dnd-handle-uri returns nil for non-file:// URIs."
  (cl-letf (((symbol-function 'kuro--send-key)
             (lambda (_) (error "Should not be called"))))
    (should-not (kuro-dnd-handle-uri "https://example.com" nil))))

;;; Group 2: kuro--setup-dnd

(ert-deftest kuro-dnd--setup-dnd-adds-entries ()
  "kuro--setup-dnd adds file:// handlers to dnd-protocol-alist buffer-locally."
  (with-temp-buffer
    (let ((dnd-protocol-alist '(("^http" . some-handler))))
      (kuro--setup-dnd)
      (should (>= (length dnd-protocol-alist) 3))
      (should (equal (caar dnd-protocol-alist) "^file:///"))
      (should (equal (cdr (car dnd-protocol-alist)) 'kuro-dnd-handle-uri))
      (should (equal (cadr dnd-protocol-alist) '("^file://" . kuro-dnd-handle-uri)))
      (should (equal (nth 2 dnd-protocol-alist) '("^http" . some-handler))))))

;;; Group 3: kuro--teardown-dnd

(ert-deftest kuro-dnd--teardown-restores-global-alist ()
  "kuro--teardown-dnd removes the buffer-local dnd-protocol-alist."
  (with-temp-buffer
    (let ((dnd-protocol-alist '(("^http" . some-handler))))
      (kuro--setup-dnd)
      (should (>= (length dnd-protocol-alist) 3))
      (kuro--teardown-dnd)
      (should (equal dnd-protocol-alist '(("^http" . some-handler)))))))

(provide 'kuro-dnd-test)
;;; kuro-dnd-test.el ends here
