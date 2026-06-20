;;; kuro-mux-test-macros.el --- Macros for kuro-mux tests  -*- lexical-binding: t; -*-

;;; Code:

(eval-and-compile
  (require 'cl-lib))

(require 'kuro-mux-test-cases)

(defmacro kuro-mux-test--with-registry (&rest body)
  "Run BODY with a clean `kuro-mux--sessions' registry, restored on exit."
  `(let ((kuro-mux--sessions nil)
         (kuro-mux-tab-bar-mode nil))
     ,@body
     ;; Clean up any buffers created by kuro-create stubs.
     (dolist (buf kuro-mux--sessions)
       (when (buffer-live-p buf)
         (kill-buffer buf)))
     (setq kuro-mux--sessions nil)))

(defmacro kuro-mux-test--make-session (name)
  "Create a mock kuro-mode buffer named NAME and register it."
  `(let ((buf (get-buffer-create ,name)))
     (with-current-buffer buf
       (kuro-mode)
       (kuro-mux--register))
     buf))

(defmacro kuro-mux-test--check-spec (buf-name setup-form key expected)
  "Make session BUF-NAME, apply SETUP-FORM, and check plist KEY equals EXPECTED."
  `(kuro-mux-test--with-registry
     (let ((buf (kuro-mux-test--make-session ,buf-name)))
       (with-current-buffer buf ,setup-form)
       (should (equal (plist-get (kuro-mux--session-spec buf) ,key) ,expected))
       (kill-buffer buf))))

(defmacro kuro-mux-test--with-layout-file (&rest body)
  "Run BODY with a temporary layout file, cleaned up on exit."
  `(let ((kuro-mux-layout-file (make-temp-file "kuro-mux-test-layout" nil ".el")))
     (unwind-protect
         (progn ,@body)
       (when (file-exists-p kuro-mux-layout-file)
         (delete-file kuro-mux-layout-file)))))

(defmacro kuro-mux-test--def-name-lighter (test-name buf-name name-val expected)
  "Define TEST-NAME for `kuro-mux--name-lighter'."
  `(ert-deftest ,test-name ()
     ,(format "`kuro-mux--name-lighter': name=%S -> %S." name-val expected)
     (kuro-mux-test--with-registry
       (let ((buf (kuro-mux-test--make-session ,buf-name)))
         (with-current-buffer buf
           (setq kuro-mux--name ,name-val)
           (should (string= (kuro-mux--name-lighter) ,expected)))
         (kill-buffer buf)))))

(defmacro kuro-mux-test--deftest-name-lighters ()
  "Define all `kuro-mux--name-lighter' tests."
  `(progn
     ,@(cl-loop for (test-name buf-name name-val expected)
                in kuro-mux-test--name-lighter-table
                collect
                `(kuro-mux-test--def-name-lighter
                  ,test-name ,buf-name ,name-val ,expected))))

(defmacro kuro-mux-test--def-session-spec (test-name buf-name var key expected)
  "Define TEST-NAME for one `kuro-mux--session-spec' field."
  `(ert-deftest ,test-name ()
     ,(format "`kuro-mux--session-spec' includes `%s' in the plist." key)
     (kuro-mux-test--check-spec ,buf-name (setq ,var ,expected) ,key ,expected)))

(defmacro kuro-mux-test--deftest-session-specs ()
  "Define all `kuro-mux--session-spec' field tests."
  `(progn
     ,@(cl-loop for (test-name buf-name var key expected)
                in kuro-mux-test--session-spec-table
                collect
                `(kuro-mux-test--def-session-spec
                  ,test-name ,buf-name ,var ,key ,expected))))

(defmacro kuro-mux-test--def-parse-layout-plists
    (test-name raw expected-length expected-first-fields)
  "Define TEST-NAME for `kuro-mux--parse-layout-plists'."
  `(ert-deftest ,test-name ()
     ,(format "`kuro-mux--parse-layout-plists' parses %S." raw)
     (let ((parsed (kuro-mux--parse-layout-plists ',raw)))
       (should (= (length parsed) ,expected-length))
       ,@(cl-loop for (key value) on expected-first-fields by #'cddr
                  collect
                  `(should (string= (plist-get (car parsed) ,key) ,value))))))

(defmacro kuro-mux-test--deftest-parse-layout-plists ()
  "Define all `kuro-mux--parse-layout-plists' tests."
  `(progn
     ,@(cl-loop for (test-name raw expected-length expected-first-fields)
                in kuro-mux-test--parse-layout-plists-table
                collect
                `(kuro-mux-test--def-parse-layout-plists
                  ,test-name ,raw ,expected-length ,expected-first-fields))))

(defmacro kuro-mux-test--deftest-prefix-bindings-invariants ()
  "Define all `kuro-mux--prefix-bindings' invariant tests."
  `(progn
     ,@(cl-loop for (test-name docstring . body)
                in kuro-mux-test--prefix-bindings-invariant-table
                collect
                `(ert-deftest ,test-name ()
                   ,docstring
                   ,@body))))

(defmacro kuro-mux-test--deftest-prefix-resize-bindings-invariants ()
  "Define all `kuro-mux--prefix-resize-bindings' invariant tests."
  `(progn
     ,@(cl-loop for (test-name docstring . body)
                in kuro-mux-test--prefix-resize-bindings-invariant-table
                collect
                `(ert-deftest ,test-name ()
                   ,docstring
                   ,@body))))

(provide 'kuro-mux-test-macros)
;;; kuro-mux-test-macros.el ends here
