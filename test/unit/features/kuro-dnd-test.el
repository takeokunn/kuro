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

(defmacro kuro-dnd-test--with-dnd-path (path &rest body)
  "Execute BODY with `dnd-get-local-file-name' returning PATH."
  (declare (indent 1))
  `(let ((kuro-dnd-test--path ,path))
     (cl-letf (((symbol-function 'dnd-get-local-file-name)
                (lambda (_uri _must-exist) kuro-dnd-test--path)))
       ,@body)))

(defmacro kuro-dnd-test--with-temp-file-path (path-var &rest body)
  "Execute BODY with PATH-VAR bound to an existing local temp file."
  (declare (indent 1))
  `(let ((,path-var (make-temp-file "kuro dnd test-" nil ".txt")))
     (unwind-protect
         (progn ,@body)
       (when (file-exists-p ,path-var)
         (delete-file ,path-var)))))

(defmacro kuro-dnd-test--with-named-temp-file-path (path-var name &rest body)
  "Execute BODY with PATH-VAR bound to an existing temp file named NAME."
  (declare (indent 2))
  `(let* ((kuro-dnd-test--dir (make-temp-file "kuro-dnd-test-" t))
          (,path-var (expand-file-name ,name kuro-dnd-test--dir)))
     (unwind-protect
         (progn
           (with-temp-file ,path-var)
           ,@body)
       (when (file-exists-p ,path-var)
         (delete-file ,path-var))
       (when (file-directory-p kuro-dnd-test--dir)
         (delete-directory kuro-dnd-test--dir)))))

(ert-deftest kuro-dnd--handle-uri-sends-shell-quoted-path-via-paste ()
  "kuro-dnd-handle-uri sends shell-quoted local paths via paste-safe path."
  (let ((sent nil))
    (kuro-dnd-test--with-temp-file-path path
      (kuro-dnd-test--with-dnd-path path
        (cl-letf (((symbol-function 'kuro--send-paste-or-raw)
                   (lambda (s) (setq sent s))))
          (kuro-dnd-handle-uri "file:///tmp/my%20file.txt" nil))))
    (should (stringp sent))
    (should (string-match-p "kuro\\\\ dnd\\\\ test-" sent))))

(ert-deftest kuro-dnd--handle-uri-returns-private ()
  "kuro-dnd-handle-uri returns `private' on successful local file handling."
  (kuro-dnd-test--with-temp-file-path path
    (kuro-dnd-test--with-dnd-path path
      (cl-letf (((symbol-function 'kuro--send-paste-or-raw) #'ignore))
        (should (eq 'private (kuro-dnd-handle-uri "file:///tmp/test.txt" nil)))))))

(ert-deftest kuro-dnd--handle-uri-returns-nil-for-non-file ()
  "kuro-dnd-handle-uri returns nil for non-file:// URIs."
  (cl-letf (((symbol-function 'kuro--send-paste-or-raw)
             (lambda (_) (error "Should not be called")))
            ((symbol-function 'dnd-get-local-file-name)
             (lambda (&rest _) (error "Should not parse non-file URI"))))
    (should-not (kuro-dnd-handle-uri "https://example.com" nil))))

(ert-deftest kuro-dnd--handle-uri-returns-nil-for-non-string-uri ()
  "kuro-dnd-handle-uri returns nil for non-string URIs."
  (cl-letf (((symbol-function 'kuro--send-paste-or-raw)
             (lambda (_) (error "Should not be called")))
            ((symbol-function 'dnd-get-local-file-name)
              (lambda (&rest _) (error "Should not parse non-string URI"))))
    (should-not (kuro-dnd-handle-uri 42 nil))))

(ert-deftest kuro-dnd--handle-uri-rejects-control-character-uri ()
  "kuro-dnd-handle-uri rejects control characters before URI parsing."
  (cl-letf (((symbol-function 'kuro--send-paste-or-raw)
             (lambda (_) (error "Should not be called")))
            ((symbol-function 'dnd-get-local-file-name)
             (lambda (&rest _) (error "Should not parse unsafe URI"))))
    (should-not (kuro-dnd-handle-uri "file:///tmp/bad\nname.txt" nil))))

(ert-deftest kuro-dnd--handle-uri-returns-nil-when-uri-parsing-fails ()
  "kuro-dnd-handle-uri returns nil when file URI parsing fails."
  (cl-letf (((symbol-function 'kuro--send-paste-or-raw)
             (lambda (_) (error "Should not be called")))
            ((symbol-function 'dnd-get-local-file-name)
             (lambda (&rest _) (error "Malformed file URI"))))
    (should-not (kuro-dnd-handle-uri "file:///%00" nil))))

(ert-deftest kuro-dnd--handle-uri-rejects-non-string-local-path ()
  "kuro-dnd-handle-uri rejects non-string local paths."
  (kuro-dnd-test--with-dnd-path 42
    (cl-letf (((symbol-function 'kuro--send-paste-or-raw)
               (lambda (_) (error "Should not be called"))))
      (should-not (kuro-dnd-handle-uri "file:///tmp/test.txt" nil)))))

(ert-deftest kuro-dnd--handle-uri-rejects-empty-local-path ()
  "kuro-dnd-handle-uri rejects empty local paths."
  (kuro-dnd-test--with-dnd-path ""
    (cl-letf (((symbol-function 'kuro--send-paste-or-raw)
               (lambda (_) (error "Should not be called"))))
      (should-not (kuro-dnd-handle-uri "file:///tmp/test.txt" nil)))))

(ert-deftest kuro-dnd--handle-uri-rejects-remote-local-path ()
  "kuro-dnd-handle-uri rejects TRAMP/remote paths."
  (let ((path "/ssh:host:/tmp/test.txt"))
    (kuro-dnd-test--with-dnd-path path
      (cl-letf (((symbol-function 'file-remote-p)
                 (lambda (_candidate) "/ssh:host:"))
                ((symbol-function 'kuro--send-paste-or-raw)
                 (lambda (_) (error "Should not be called"))))
        (should-not (kuro-dnd-handle-uri "file:///tmp/test.txt" nil))))))

(ert-deftest kuro-dnd--handle-uri-rejects-nonexistent-local-path ()
  "kuro-dnd-handle-uri rejects nonexistent local paths."
  (let ((path (make-temp-file "kuro-dnd-missing-" nil ".txt")))
    (delete-file path)
    (kuro-dnd-test--with-dnd-path path
      (cl-letf (((symbol-function 'kuro--send-paste-or-raw)
                 (lambda (_) (error "Should not be called"))))
        (should-not (kuro-dnd-handle-uri "file:///tmp/missing.txt" nil))))))

(ert-deftest kuro-dnd--handle-uri-rejects-relative-local-path ()
  "kuro-dnd-handle-uri rejects existing relative paths."
  (let* ((dir (make-temp-file "kuro-dnd-relative-" t))
         (default-directory dir)
         (path "relative.txt"))
    (unwind-protect
        (progn
          (with-temp-file path)
          (kuro-dnd-test--with-dnd-path path
            (cl-letf (((symbol-function 'kuro--send-paste-or-raw)
                       (lambda (_) (error "Should not be called"))))
              (should (file-exists-p path))
              (should-not (kuro-dnd-handle-uri "file:///tmp/relative.txt" nil)))))
      (when (file-exists-p (expand-file-name path dir))
        (delete-file (expand-file-name path dir)))
      (when (file-directory-p dir)
        (delete-directory dir)))))

(ert-deftest kuro-dnd--handle-uri-rejects-control-character-local-path ()
  "kuro-dnd-handle-uri rejects local paths containing control characters."
  (kuro-dnd-test--with-named-temp-file-path path "bad\nname.txt"
    (kuro-dnd-test--with-dnd-path path
      (cl-letf (((symbol-function 'kuro--send-paste-or-raw)
                 (lambda (_) (error "Should not be called"))))
        (should-not (kuro-dnd-handle-uri "file:///tmp/bad%0Aname.txt" nil))))))

(ert-deftest kuro-dnd--local-file-path-rejects-delete-char ()
  "kuro-dnd--local-file-path-p rejects ASCII DEL in paths."
  (kuro-dnd-test--with-named-temp-file-path path (concat "bad" (string 127) "name.txt")
    (should-not (kuro-dnd--local-file-path-p path))))

;;; Group 2: kuro--setup-dnd

(ert-deftest kuro-dnd--setup-dnd-adds-entries ()
  "kuro--setup-dnd adds file:// handlers to dnd-protocol-alist buffer-locally."
  (let ((original-dnd-protocol-alist dnd-protocol-alist))
    (unwind-protect
        (progn
          (setq dnd-protocol-alist '(("^http" . some-handler)))
          (with-temp-buffer
            (kuro--setup-dnd)
            (should (>= (length dnd-protocol-alist) 3))
            (should (equal (caar dnd-protocol-alist) "^file:///"))
            (should (equal (cdr (car dnd-protocol-alist)) 'kuro-dnd-handle-uri))
            (should (equal (cadr dnd-protocol-alist) '("^file://" . kuro-dnd-handle-uri)))
            (should (equal (nth 2 dnd-protocol-alist) '("^http" . some-handler)))))
      (setq dnd-protocol-alist original-dnd-protocol-alist))))

;;; Group 3: kuro--teardown-dnd

(ert-deftest kuro-dnd--teardown-restores-global-alist ()
  "kuro--teardown-dnd removes the buffer-local dnd-protocol-alist."
  (let ((original-dnd-protocol-alist dnd-protocol-alist))
    (unwind-protect
        (progn
          (setq dnd-protocol-alist '(("^http" . some-handler)))
          (with-temp-buffer
            (kuro--setup-dnd)
            (should (>= (length dnd-protocol-alist) 3))
            (kuro--teardown-dnd)
            (should (equal dnd-protocol-alist '(("^http" . some-handler))))))
      (setq dnd-protocol-alist original-dnd-protocol-alist))))

(ert-deftest kuro-dnd--teardown-without-setup-is-noop ()
  "kuro--teardown-dnd is a no-op when dnd-protocol-alist was never made buffer-local."
  (let ((original-dnd-protocol-alist dnd-protocol-alist))
    (unwind-protect
        (progn
          (setq dnd-protocol-alist '(("^http" . some-handler)))
          (with-temp-buffer
            ;; No kuro--setup-dnd call; local var is not set.
            (kuro--teardown-dnd)
            ;; kill-local-variable on a non-local var is a safe no-op; global is unchanged.
            (should (equal dnd-protocol-alist '(("^http" . some-handler))))))
      (setq dnd-protocol-alist original-dnd-protocol-alist))))

(provide 'kuro-dnd-test)
;;; kuro-dnd-test.el ends here
