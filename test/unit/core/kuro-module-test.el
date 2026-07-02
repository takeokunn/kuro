;;; kuro-module-test.el --- ERT tests for kuro-module.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-module.el covering pure path-manipulation functions.
;; These tests do NOT require the Rust dynamic module to be loaded.
;; `module-load' is stubbed where needed; no compiled Rust module is required.

;;; Code:

(require 'kuro-module-test-support)

;;; Group 1: kuro-module--platform-extension

(ert-deftest kuro-module-test--platform-extension-linux ()
  "On GNU/Linux, kuro-module--platform-extension returns \"so\"."
  (when (eq system-type 'gnu/linux)
    (should (equal (kuro-module--platform-extension) "so"))))

(ert-deftest kuro-module-test--platform-extension-darwin ()
  "On macOS, kuro-module--platform-extension returns \"dylib\"."
  (when (eq system-type 'darwin)
    (should (equal (kuro-module--platform-extension) "dylib"))))

(ert-deftest kuro-module-test--platform-extension-returns-non-empty-string ()
  "kuro-module--platform-extension returns a non-empty string on supported systems."
  (when (memq system-type '(gnu/linux darwin))
    (let ((ext (kuro-module--platform-extension)))
      (should (stringp ext))
      (should (> (length ext) 0)))))

(ert-deftest kuro-module-test--platform-extension-no-dot-prefix ()
  "kuro-module--platform-extension returns the bare extension without a leading dot."
  (when (memq system-type '(gnu/linux darwin))
    (let ((ext (kuro-module--platform-extension)))
      (should-not (string-prefix-p "." ext)))))

;;; Group 2: kuro-module--find-library — tier 1 (custom path)

(ert-deftest kuro-module-test--find-library-returns-candidate-or-nil ()
  "kuro-module--find-library returns nil when no tier provides a candidate."
  (cl-letf (((symbol-function 'kuro-module--tier-custom) (lambda () nil))
            ((symbol-function 'kuro-module--tier-env) (lambda () nil))
            ((symbol-function 'kuro-module--tier-xdg) (lambda () nil))
            ((symbol-function 'kuro-module--tier-dev) (lambda () nil)))
    (should-not (kuro-module--find-library))))

(ert-deftest kuro-module-test--find-library-custom-path-existing ()
  "Tier 1: when kuro-module-binary-path points to an existing file, it is returned."
  (kuro-module-test--with-temp-dir (tmpdir "kuro-mod-test-")
    (let ((tmpfile (expand-file-name (kuro-module--lib-name) tmpdir)))
      (kuro-module-test--write-valid-library-file tmpfile)
      (let ((kuro-module-binary-path tmpfile))
        (should (equal (kuro-module-test--candidate-path
                        (kuro-module--find-library))
                       tmpfile))))))

(ert-deftest kuro-module-test--find-library-nonexistent-custom-path-errors ()
  "Tier 1: an explicit nonexistent kuro-module-binary-path is an error."
  (let ((kuro-module-binary-path
         (expand-file-name (kuro-module--lib-name) "/nonexistent/path")))
    (should-error (kuro-module--find-library) :type 'error)))

(ert-deftest kuro-module-test--find-library-nil-custom-path-no-error ()
  "Tier 1: nil kuro-module-binary-path does not signal an error."
  (let ((kuro-module-binary-path nil))
    (should-not (condition-case err
                    (progn (kuro-module--tier-custom) nil)
                  (error err)))))

;;; Group 3: kuro-module--find-library — tier 2 (KURO_MODULE_PATH env var)

(ert-deftest kuro-module-test--find-library-env-var-existing ()
  "Tier 2: KURO_MODULE_PATH pointing to a dir with the lib returns its path."
  (let ((kuro-module-binary-path nil))
    (kuro-module-test--with-temp-dir-env (tmpdir "kuro-env-test-" "KURO_MODULE_PATH")
      (let* ((ext (kuro-module--platform-extension))
             (lib-name (format "libkuro_core.%s" ext))
             (tmpfile (expand-file-name lib-name tmpdir)))
        (kuro-module-test--write-valid-library-file tmpfile)
        (let ((result (kuro-module--find-library)))
          (should (equal (kuro-module-test--candidate-path result)
                         tmpfile)))))))

(ert-deftest kuro-module-test--find-library-env-var-nonexistent-errors ()
  "Tier 2: KURO_MODULE_PATH pointing to a dir without the lib errors."
  (let ((kuro-module-binary-path nil))
    (kuro-module-test--with-temp-dir-env (tmpdir "kuro-env-empty-" "KURO_MODULE_PATH")
      (should-error (kuro-module--find-library) :type 'error))))

;;; Group 4: kuro-module--find-library — lib name in result

(ert-deftest kuro-module-test--find-library-path-contains-lib-name ()
  "The resolved path always contains the platform-specific library filename."
  (kuro-module-test--with-temp-dir (tmpdir "kuro-path-name-")
    (let* ((tmpfile (expand-file-name (kuro-module--lib-name) tmpdir))
           (kuro-module-binary-path tmpfile))
      (kuro-module-test--write-valid-library-file tmpfile)
      (should (string-match-p
               (regexp-quote (kuro-module--lib-name))
               (kuro-module-test--candidate-path
                (kuro-module--find-library)))))))

(ert-deftest kuro-module-test--find-library-dev-path-contains-target-release ()
  "Tier 4 dev path includes target/release in the resolved path."
  (kuro-module-test--with-dev-stubs
    (should (string-match-p
             "target/release"
             (kuro-module-test--candidate-path (kuro-module--tier-dev))))))

;;; Group 5: Individual tier functions

(ert-deftest kuro-module-tier-custom-returns-path-when-exists ()
  "kuro-module--tier-custom returns kuro-module-binary-path when file exists."
  (kuro-module-test--with-temp-dir (tmpdir "kuro-tier1-")
    (let* ((tmpfile (expand-file-name (kuro-module--lib-name) tmpdir)))
      (kuro-module-test--write-valid-library-file tmpfile)
      (let ((kuro-module-binary-path tmpfile))
        (should (equal (kuro-module-test--candidate-path
                        (kuro-module--tier-custom))
                       tmpfile))))))

(ert-deftest kuro-module-tier-custom-errors-when-missing ()
  "kuro-module--tier-custom errors when an explicit path does not exist."
  (let ((kuro-module-binary-path
         (expand-file-name (kuro-module--lib-name) "/nonexistent-kuro-tier1")))
    (should-error (kuro-module--tier-custom) :type 'error)))

(ert-deftest kuro-module-tier-custom-returns-nil-when-path-nil ()
  "kuro-module--tier-custom returns nil when kuro-module-binary-path is nil."
  (let ((kuro-module-binary-path nil))
    (should-not (kuro-module--tier-custom))))

(ert-deftest kuro-module-tier-env-uses-env-var ()
  "kuro-module--tier-env returns the expanded lib path when env dir and file exist."
  (kuro-module-test--with-temp-dir-env (tmpdir "kuro-tier2-" "KURO_MODULE_PATH")
    (let* ((ext (kuro-module--platform-extension))
           (lib-name (format "libkuro_core.%s" ext))
           (tmpfile (expand-file-name lib-name tmpdir)))
      (kuro-module-test--write-valid-library-file tmpfile)
      (should (equal (kuro-module-test--candidate-path
                      (kuro-module--tier-env))
                     tmpfile)))))

(ert-deftest kuro-module-tier-env-returns-nil-when-env-unset ()
  "kuro-module--tier-env returns nil when KURO_MODULE_PATH is unset."
  (kuro-module-test--with-env-var "KURO_MODULE_PATH" nil
    (should-not (kuro-module--tier-env))))

(ert-deftest kuro-module-search-tiers-is-defconst ()
  "kuro-module--search-tiers is a list of exactly 4 function symbols."
  (should (= (length kuro-module--search-tiers) 4))
  (should (cl-every #'symbolp kuro-module--search-tiers)))

(ert-deftest kuro-module-find-library-uses-first-found-tier ()
  "kuro-module--find-library returns the first non-nil tier result."
  (let ((candidate (kuro-module--library-candidate-create
                    :path "/found/libkuro_core.so" :device 1 :inode 2)))
    (cl-letf (((symbol-function 'kuro-module--tier-custom) (lambda () nil))
              ((symbol-function 'kuro-module--tier-env)    (lambda () candidate))
              ((symbol-function 'kuro-module--tier-xdg)   (lambda () (error "should not reach xdg")))
              ((symbol-function 'kuro-module--tier-dev)   (lambda () (error "should not reach dev"))))
      (should (eq (kuro-module--find-library) candidate)))))

(ert-deftest kuro-module-find-library-falls-through-to-dev ()
  "kuro-module--find-library reaches tier-dev when all preceding tiers return nil."
  (let ((candidate (kuro-module--library-candidate-create
                    :path "/dev/libkuro_core.so" :device 1 :inode 2)))
    (cl-letf (((symbol-function 'kuro-module--tier-custom) (lambda () nil))
              ((symbol-function 'kuro-module--tier-env)    (lambda () nil))
              ((symbol-function 'kuro-module--tier-xdg)   (lambda () nil))
              ((symbol-function 'kuro-module--tier-dev)   (lambda () candidate)))
      (should (eq (kuro-module--find-library) candidate)))))

;;; Group 6: kuro--ensure-module-loaded interface

(ert-deftest kuro-module-test--ensure-module-loaded-is-callable ()
  "`kuro--ensure-module-loaded' is a function that can be called."
  (should (fboundp 'kuro--ensure-module-loaded)))

(ert-deftest kuro-module-test--module-load-is-callable ()
  "`kuro-module-load' is a function."
  (should (fboundp 'kuro-module-load)))

;;; Group 7: kuro--module-try macro

(ert-deftest kuro-module-test--module-try-returns-path-when-file-exists ()
  "`kuro--module-try' returns a typed candidate when the file exists."
  (kuro-module-test--with-temp-dir (tmpdir "kuro-try-test-")
    (let ((tmpfile (expand-file-name (kuro-module--lib-name) tmpdir)))
      (kuro-module-test--write-valid-library-file tmpfile)
      (should (equal (kuro-module-test--candidate-path
                      (kuro--module-try tmpfile))
                     tmpfile)))))

(ert-deftest kuro-module-test--module-try-returns-nil-when-file-missing ()
  "`kuro--module-try' returns nil when the file does not exist."
  (should-not
   (kuro--module-try
    (expand-file-name (kuro-module--lib-name) "/nonexistent-kuro-try-test"))))

(ert-deftest kuro-module-test--module-try-returns-nil-when-path-is-nil ()
  "`kuro--module-try' returns nil without error when path-expr evaluates to nil."
  (should-not (kuro--module-try nil)))

(ert-deftest kuro-module-test--module-try-evaluates-path-expr-once ()
  "`kuro--module-try' evaluates its argument exactly once (macro hygiene)."
  (let ((eval-count 0))
    ;; The counter increments inside the path-expr; confirm it runs exactly once.
    (kuro--module-try (progn (setq eval-count (1+ eval-count)) nil))
    (should (= eval-count 1))))

;;; Group 8: kuro-module--tier-xdg

(ert-deftest kuro-module-tier-xdg-returns-path-when-file-exists ()
  "`kuro-module--tier-xdg' returns the canonical XDG library path when the file exists."
  (let* ((ext (kuro-module--platform-extension))
         (lib-name (format "libkuro_core.%s" ext))
         (expected (expand-file-name lib-name "~/.local/share/kuro/")))
    (cl-letf (((symbol-function 'kuro-module--library-candidate-from-path)
               (lambda (path &optional _required _source)
                 (when (equal path expected)
                   (kuro-module--library-candidate-create
                    :path path :device 1 :inode 2)))))
      (should (equal (kuro-module-test--candidate-path
                      (kuro-module--tier-xdg))
                     expected)))))

(ert-deftest kuro-module-tier-xdg-returns-nil-when-file-absent ()
  "`kuro-module--tier-xdg' returns nil when the XDG path does not exist."
  (cl-letf (((symbol-function 'kuro-module--library-candidate-from-path)
             (lambda (&rest _) nil)))
    (should-not (kuro-module--tier-xdg))))

(ert-deftest kuro-module-tier-xdg-path-contains-xdg-dir ()
  "`kuro-module--tier-xdg' constructs a path that includes the XDG share directory."
  (let* ((ext (kuro-module--platform-extension))
         (lib-name (format "libkuro_core.%s" ext))
         (expected-xdg (expand-file-name lib-name "~/.local/share/kuro/"))
         (captured nil))
    (cl-letf (((symbol-function 'kuro-module--library-candidate-from-path)
               (lambda (path &rest _)
                 (setq captured path)
                 nil)))
      (should-not (kuro-module--tier-xdg))
      (should (equal captured expected-xdg)))))

;;; Group 9: kuro-module--tier-dev

(ert-deftest kuro-module-tier-dev-returns-string ()
  "`kuro-module--tier-dev' returns a typed candidate when a dev binary path is accessible."
  (kuro-module-test--with-dev-stubs
    (should (kuro-module--library-candidate-p (kuro-module--tier-dev)))))

(ert-deftest kuro-module-tier-dev-path-contains-target-release ()
  "`kuro-module--tier-dev' path contains \"target/release\"."
  (kuro-module-test--with-dev-stubs
    (should (string-match-p
             "target/release"
             (kuro-module-test--candidate-path (kuro-module--tier-dev))))))

(ert-deftest kuro-module-tier-dev-path-contains-lib-name ()
  "`kuro-module--tier-dev' path contains the platform library filename."
  (let* ((ext (kuro-module--platform-extension))
         (lib-name (format "libkuro_core.%s" ext)))
    (kuro-module-test--with-dev-stubs
      (should (string-match-p
               (regexp-quote lib-name)
               (kuro-module-test--candidate-path (kuro-module--tier-dev)))))))

;;; Group 10: kuro-module--search-tiers defconst

(ert-deftest kuro-module-search-tiers-has-four-elements ()
  "`kuro-module--search-tiers' contains exactly 4 elements."
  (should (= (length kuro-module--search-tiers) 4)))

(ert-deftest kuro-module-search-tiers-all-are-symbols ()
  "Every element of `kuro-module--search-tiers' is a symbol."
  (should (cl-every #'symbolp kuro-module--search-tiers)))

(ert-deftest kuro-module-search-tiers-all-are-fbound ()
  "Every symbol in `kuro-module--search-tiers' names a defined function."
  (should (cl-every #'fboundp kuro-module--search-tiers)))

(ert-deftest kuro-module-search-tiers-priority-order ()
  "The 4 tiers appear in the documented priority order: custom, env, xdg, dev."
  (should (equal kuro-module--search-tiers
                 '(kuro-module--tier-custom
                   kuro-module--tier-env
                   kuro-module--tier-xdg
                   kuro-module--tier-dev))))

(ert-deftest kuro-module-run-search-tiers-macroexpands-to-or-chain ()
  "`kuro--run-module-search-tiers' expands to a direct `or' chain."
  (should (equal (macroexpand-1 '(kuro--run-module-search-tiers))
                 '(or (kuro-module--tier-custom)
                      (kuro-module--tier-env)
                      (kuro-module--tier-xdg)
                      (kuro-module--tier-dev)))))

;;; Group 11: kuro-module--find-library — all tiers return nil

(ert-deftest kuro-module-find-library-all-tiers-nil-returns-nil ()
  "When every search tier returns nil, no module candidate is found."
  (cl-letf (((symbol-function 'kuro-module--tier-custom) (lambda () nil))
            ((symbol-function 'kuro-module--tier-env)    (lambda () nil))
            ((symbol-function 'kuro-module--tier-xdg)   (lambda () nil))
            ((symbol-function 'kuro-module--tier-dev)   (lambda () nil)))
    (should-not (kuro-module--find-library))))

(ert-deftest kuro-module-find-library-stops-at-first-non-nil ()
  "kuro-module--find-library stops at tier-custom and does not call later tiers."
  (let ((env-called nil)
        (xdg-called nil)
        (dev-called nil)
        (candidate (kuro-module--library-candidate-create
                    :path "/custom/libkuro_core.so" :device 1 :inode 2)))
    (cl-letf (((symbol-function 'kuro-module--tier-custom)
               (lambda () candidate))
              ((symbol-function 'kuro-module--tier-env)
               (lambda () (setq env-called t)
                 (kuro-module--library-candidate-create
                  :path "/env/libkuro_core.so" :device 1 :inode 3)))
              ((symbol-function 'kuro-module--tier-xdg)
               (lambda () (setq xdg-called t)
                 (kuro-module--library-candidate-create
                  :path "/xdg/libkuro_core.so" :device 1 :inode 4)))
              ((symbol-function 'kuro-module--tier-dev)
               (lambda () (setq dev-called t)
                 (kuro-module--library-candidate-create
                  :path "/dev/libkuro_core.so" :device 1 :inode 5))))
      (should (eq (kuro-module--find-library) candidate))
      (should-not env-called)
      (should-not xdg-called)
      (should-not dev-called))))

;;; Group 12: kuro--ensure-module-loaded

(ert-deftest kuro-module-test--ensure-module-loaded-noop-when-already-loaded ()
  "`kuro--ensure-module-loaded' does not call `kuro-module-load' when already loaded."
  (let ((load-called nil))
    (cl-letf (((symbol-function 'kuro-core-init) (lambda (&rest _) t))
              ((symbol-function 'kuro-module-load)
               (lambda () (setq load-called t))))
      (kuro--ensure-module-loaded)
      (should-not load-called))))

(ert-deftest kuro-module-test--ensure-module-loaded-calls-load-when-not-loaded ()
  "`kuro--ensure-module-loaded' calls `kuro-module-load' exactly once when unloaded."
  (let ((load-call-count 0))
    (fmakunbound 'kuro-core-init)
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-module-load)
                   (lambda ()
                     (setq load-call-count (1+ load-call-count))
                     (fset 'kuro-core-init (lambda (&rest _) t)))))
          (kuro--ensure-module-loaded))
      (unless (fboundp 'kuro-core-init)
        (fset 'kuro-core-init (lambda (&rest _) t))))
    (should (= load-call-count 1))))

(ert-deftest kuro-module-test--ensure-module-loaded-sets-flag-after-load ()
  "`kuro--ensure-module-loaded' results in `kuro-core-init' being fbound after loading."
  (fmakunbound 'kuro-core-init)
  (unwind-protect
      (cl-letf (((symbol-function 'kuro-module-load)
                 (lambda () (fset 'kuro-core-init (lambda (&rest _) t)))))
        (kuro--ensure-module-loaded)
        (should (fboundp 'kuro-core-init)))
    (unless (fboundp 'kuro-core-init)
      (fset 'kuro-core-init (lambda (&rest _) t)))))

;;; Group 13: kuro-module-load — already-fbound guard

(ert-deftest kuro-module-test--module-load-noop-when-kuro-core-init-fbound ()
  "`kuro-module-load' does not call `module-load' when `kuro-core-init' is already fbound."
  (let ((module-load-called nil))
    (cl-letf (((symbol-function 'kuro-core-init) (lambda () nil))
              ((symbol-function 'module-load)
               (lambda (_path) (setq module-load-called t))))
      ;; kuro-core-init is now fbound — load must be a no-op.
      (kuro-module-load)
      (should-not module-load-called))))

(ert-deftest kuro-module-test--module-load-emits-message-when-not-found ()
  "`kuro-module-load' emits a message containing useful info when the module is missing."
  ;; Ensure kuro-core-init is NOT fbound so the load path is taken.
  (let ((last-message nil)
        (was-bound (fboundp 'kuro-core-init))
        (original-def (and (fboundp 'kuro-core-init)
                           (symbol-function 'kuro-core-init))))
    (when was-bound
      (fmakunbound 'kuro-core-init))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-module--find-library)
                   (lambda () nil))
                  ((symbol-function 'message)
                   (lambda (fmt &rest args)
                     (setq last-message (apply #'format fmt args)))))
          (kuro-module-load)
          (should (stringp last-message))
          (should (string-match-p "kuro" last-message)))
      (when was-bound
        (fset 'kuro-core-init original-def)))))

(provide 'kuro-module-test)
;;; kuro-module-test.el ends here
