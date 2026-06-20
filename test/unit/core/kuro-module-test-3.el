;;; kuro-module-test-3.el --- ERT tests for kuro-module.el (part 3)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-module-test-support)

;;; Group 14: kuro-module--lib-name helper

(ert-deftest kuro-module-lib-name-is-string ()
  "`kuro-module--lib-name' returns a non-empty string."
  (should (stringp (kuro-module--lib-name)))
  (should (> (length (kuro-module--lib-name)) 0)))

(ert-deftest kuro-module-lib-name-starts-with-libkuro-core ()
  "`kuro-module--lib-name' always starts with \"libkuro_core.\"."
  (should (string-prefix-p "libkuro_core." (kuro-module--lib-name))))

(ert-deftest kuro-module-lib-name-matches-tier-functions ()
  "`kuro-module--lib-name' is consistent with what tier functions use."
  (cl-letf (((symbol-function 'locate-library)
             (lambda (_name) "/stub/emacs-lisp/core/kuro-module.el"))
            ((symbol-function 'file-exists-p) (lambda (_) t)))
    (let ((lib-name (kuro-module--lib-name))
          (dev-path  (kuro-module--tier-dev)))
      (should (stringp dev-path))
      (should (string-match-p (regexp-quote lib-name) dev-path)))))

(ert-deftest kuro-module-lib-name-no-dot-in-stem ()
  "`kuro-module--lib-name' stem (before the extension dot) contains no dots."
  (let* ((lib-name (kuro-module--lib-name))
         (stem (substring lib-name 0 (string-match "\\." lib-name))))
    (should-not (string-match-p "\\." stem))))

(ert-deftest kuro-module-tier-xdg-uses-lib-name ()
  "`kuro-module--tier-xdg' result (when file exists) ends with kuro-module--lib-name."
  (let* ((lib-name (kuro-module--lib-name)))
    (cl-letf (((symbol-function 'file-exists-p) (lambda (_) t)))
      (should (string-suffix-p lib-name (kuro-module--tier-xdg))))))

;;; Group 15: kuro-module--platform-extension — unsupported platform

(ert-deftest kuro-module-platform-extension-unsupported-signals-error ()
  "`kuro-module--platform-extension' signals an error for unsupported system-type."
  (let ((system-type 'windows-nt))
    (should-error (kuro-module--platform-extension) :type 'error)))

(ert-deftest kuro-module-platform-extension-linux-returns-so ()
  "`kuro-module--platform-extension' returns \"so\" when system-type is gnu/linux."
  (let ((system-type 'gnu/linux))
    (should (equal (kuro-module--platform-extension) "so"))))

(ert-deftest kuro-module-platform-extension-darwin-returns-dylib ()
  "`kuro-module--platform-extension' returns \"dylib\" when system-type is darwin."
  (let ((system-type 'darwin))
    (should (equal (kuro-module--platform-extension) "dylib"))))

(ert-deftest kuro-module-lib-name-linux-ends-in-so ()
  "`kuro-module--lib-name' ends with \".so\" on GNU/Linux."
  (let ((system-type 'gnu/linux))
    (should (string-suffix-p ".so" (kuro-module--lib-name)))))

(ert-deftest kuro-module-lib-name-darwin-ends-in-dylib ()
  "`kuro-module--lib-name' ends with \".dylib\" on macOS/darwin."
  (let ((system-type 'darwin))
    (should (string-suffix-p ".dylib" (kuro-module--lib-name)))))


;;; Group 16: kuro-module-load — module-load invocation path

(ert-deftest kuro-module-test--module-load-calls-module-load-when-file-found ()
  "`kuro-module-load' calls `module-load' with the located file path when it exists."
  (let ((loaded-path nil))
    (let ((was-bound (fboundp 'kuro-core-init)))
      (when was-bound (fmakunbound 'kuro-core-init))
      (cl-letf (((symbol-function 'kuro-module--find-library)
                 (lambda () "/fake/libkuro_core.so"))
                ((symbol-function 'file-exists-p)
                 (lambda (p) (equal p "/fake/libkuro_core.so")))
                ((symbol-function 'message) (lambda (&rest _) nil))
                ((symbol-function 'module-load)
                 (lambda (path) (setq loaded-path path))))
        (unwind-protect
            (progn
              (kuro-module-load)
              (should (equal loaded-path "/fake/libkuro_core.so")))
          (when was-bound
            (fset 'kuro-core-init (lambda () nil))))))))

(ert-deftest kuro-module-test--module-load-message-fmt-contains-path ()
  "`kuro-module-load' calls `message' with the module path in the format string."
  (let ((captured-fmt nil)
        (captured-arg nil))
    (let ((was-bound (fboundp 'kuro-core-init)))
      (when was-bound (fmakunbound 'kuro-core-init))
      (cl-letf (((symbol-function 'kuro-module--find-library)
                 (lambda () "/stub/libkuro_core.so"))
                ((symbol-function 'file-exists-p)
                 (lambda (p) (equal p "/stub/libkuro_core.so")))
                ((symbol-function 'module-load) (lambda (_) nil))
                ((symbol-function 'message)
                 (lambda (fmt &rest args)
                   (setq captured-fmt fmt)
                   (setq captured-arg (car args)))))
        (unwind-protect
            (progn
              (kuro-module-load)
              (should (stringp captured-fmt))
              (should (equal captured-arg "/stub/libkuro_core.so")))
          (when was-bound
            (fset 'kuro-core-init (lambda () nil))))))))

(ert-deftest kuro-module-test--ensure-module-loaded-idempotent ()
  "`kuro--ensure-module-loaded' is idempotent: second call is a no-op."
  (let ((load-call-count 0))
    (fmakunbound 'kuro-core-init)
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-module-load)
                   (lambda ()
                     (setq load-call-count (1+ load-call-count))
                     (fset 'kuro-core-init (lambda (&rest _) t)))))
          (kuro--ensure-module-loaded)
          (kuro--ensure-module-loaded))
      (unless (fboundp 'kuro-core-init)
        (fset 'kuro-core-init (lambda (&rest _) t))))
    (should (= load-call-count 1))))

(ert-deftest kuro-module-test--ensure-module-loaded-flag-stays-non-nil ()
  "`kuro-core-init' remains fbound after two calls to `kuro--ensure-module-loaded'."
  (fmakunbound 'kuro-core-init)
  (unwind-protect
      (cl-letf (((symbol-function 'kuro-module-load)
                 (lambda () (fset 'kuro-core-init (lambda (&rest _) t)))))
        (kuro--ensure-module-loaded)
        (kuro--ensure-module-loaded)
        (should (fboundp 'kuro-core-init)))
    (unless (fboundp 'kuro-core-init)
      (fset 'kuro-core-init (lambda (&rest _) t)))))

(ert-deftest kuro-module-test--module-try-empty-string-file-exists-stubbed-nil ()
  "`kuro--module-try' returns nil for empty string when file-exists-p is stubbed nil."
  (cl-letf (((symbol-function 'file-exists-p) (lambda (_) nil)))
    (should-not (kuro--module-try ""))))

(ert-deftest kuro-module-test--module-load-noop-is-repeatable ()
  "`kuro-module-load' can be called twice safely when kuro-core-init is fbound."
  (let ((call-count 0))
    (cl-letf (((symbol-function 'kuro-core-init) (lambda () nil))
              ((symbol-function 'module-load)
               (lambda (_) (setq call-count (1+ call-count)))))
      (kuro-module-load)
      (kuro-module-load)
      (should (= call-count 0)))))

;;; Group 18: kuro-module--verify-sha256

(ert-deftest kuro-module--verify-sha256-nil-hash-returns-t ()
  "`kuro-module--verify-sha256' returns t when expected-hash is nil."
  (cl-letf (((symbol-function 'display-warning) (lambda (&rest _) nil)))
    (should (kuro-module--verify-sha256 "/any/path" nil))))

(ert-deftest kuro-module--verify-sha256-nil-hash-emits-warning ()
  "`kuro-module--verify-sha256' calls `display-warning' when hash is nil."
  (let ((warned nil))
    (cl-letf (((symbol-function 'display-warning)
               (lambda (_cat _msg &rest _) (setq warned t))))
      (kuro-module--verify-sha256 "/any/path" nil)
      (should warned))))

(ert-deftest kuro-module--verify-sha256-matching-hash-returns-t ()
  "`kuro-module--verify-sha256' returns t when hash matches file content."
  (kuro-module-test--with-temp-file (tmpfile "kuro-test-sha256-")
    (let* ((content "hello kuro")
           (expected (with-temp-buffer
                       (set-buffer-multibyte nil)
                       (insert content)
                       (secure-hash 'sha256 (current-buffer)))))
      (with-temp-file tmpfile (insert content))
      (should (kuro-module--verify-sha256 tmpfile expected)))))

(ert-deftest kuro-module--verify-sha256-wrong-hash-returns-nil ()
  "`kuro-module--verify-sha256' returns nil when hash does not match."
  (kuro-module-test--with-temp-file (tmpfile "kuro-test-sha256-")
    (with-temp-file tmpfile (insert "actual content"))
    (should-not (kuro-module--verify-sha256 tmpfile "0000deadbeef"))))

;;; Group 25: kuro-module--locate-cargo-toml direct tests

(ert-deftest kuro-module-test--locate-cargo-toml-finds-in-repo ()
  "`kuro-module--locate-cargo-toml' returns a string ending in rust-core/Cargo.toml in this repo."
  ;; Bind load-file-name to a file in the repo so the walker has a starting point.
  (let* ((load-file-name (expand-file-name "emacs-lisp/core/kuro-module.el"))
         (result (kuro-module--locate-cargo-toml)))
    (should (stringp result))
    (should (string-suffix-p "rust-core/Cargo.toml" result))
    (should (file-exists-p result))))

(ert-deftest kuro-module-test--locate-cargo-toml-returns-nil-from-unrelated-dir ()
  "`kuro-module--locate-cargo-toml' returns nil when started in a temp dir with no Cargo.toml parent."
  (kuro-module-test--with-temp-dir (tmp "kuro-test-")
    (let ((load-file-name (expand-file-name "fake.el" tmp)))
      (should-not (kuro-module--locate-cargo-toml)))))

(ert-deftest kuro-module-test--locate-cargo-toml-finds-in-nested-subdir ()
  "`kuro-module--locate-cargo-toml' walks up from nested dirs and finds Cargo.toml."
  (kuro-module-test--with-cargo-toml-tree (tmp rust-dir sub-dir "kuro-locate-")
    (let ((load-file-name nil)
          (buffer-file-name (expand-file-name "test.el" sub-dir)))
      (cl-letf (((symbol-function 'locate-library) (lambda (_name) nil)))
        (let ((result (kuro-module--locate-cargo-toml)))
          (should (stringp result))
          (should (string= result (expand-file-name "rust-core/Cargo.toml" tmp)))
          (should (file-exists-p result)))))))

;;; kuro--module-try macro structural tests

(ert-deftest kuro-module-try-expands-to-let ()
  "`kuro--module-try' single-step expands to a `let' form."
  (let ((exp (macroexpand-1
              '(kuro--module-try (concat "test" ".so")))))
    (should (eq (car exp) 'let))))

(ert-deftest kuro-module-try-expansion-binds-p ()
  "`kuro--module-try' binds the path expression to `p' in the `let'."
  (let* ((exp (macroexpand-1
               '(kuro--module-try "/some/path")))
         ;; (let ((p ...)) ...) → bindings = ((p ...)) → first = (p ...) → car = p
         (var (caaadr exp)))
    (should (eq var 'p))))

(ert-deftest kuro-module-try-expansion-guards-with-when ()
  "`kuro--module-try' body is a `when' guarded by `file-exists-p'."
  (let* ((exp (macroexpand-1
               '(kuro--module-try "/some/path")))
         (when-form (caddr exp)))
    (should (eq (car when-form) 'when))))

(provide 'kuro-module-test-3)
;;; kuro-module-test-3.el ends here
