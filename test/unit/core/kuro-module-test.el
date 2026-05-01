;;; kuro-module-test.el --- ERT tests for kuro-module.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-module.el covering pure path-manipulation functions.
;; These tests do NOT require the Rust dynamic module to be loaded.
;; kuro-module-load and kuro--ensure-module-loaded are NOT tested here
;; because they call `module-load' which requires the compiled .so/.dylib.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Stub module-load before loading kuro-module so the file can be required
;; safely in batch mode without a compiled Rust binary present.
(unless (fboundp 'module-load)
  (fset 'module-load (lambda (_path) nil)))

(require 'kuro-config)
(require 'kuro-module)

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

(ert-deftest kuro-module-test--find-library-returns-string ()
  "kuro-module--find-library always returns a non-empty string."
  (let ((kuro-module-binary-path nil))
    (let ((path (kuro-module--find-library)))
      (should (stringp path))
      (should (> (length path) 0)))))

(ert-deftest kuro-module-test--find-library-custom-path-existing ()
  "Tier 1: when kuro-module-binary-path points to an existing file, it is returned."
  (let* ((tmpdir (make-temp-file "kuro-mod-test-" t))
         (ext (kuro-module--platform-extension))
         (tmpfile (expand-file-name (format "libkuro_core.%s" ext) tmpdir)))
    (write-region "" nil tmpfile)
    (unwind-protect
        (let ((kuro-module-binary-path tmpfile))
          (should (equal (kuro-module--find-library) tmpfile)))
      (delete-directory tmpdir t))))

(ert-deftest kuro-module-test--find-library-nonexistent-custom-path-skipped ()
  "Tier 1: a nonexistent kuro-module-binary-path falls through to lower tiers."
  (let ((kuro-module-binary-path "/nonexistent/path/libkuro_core.so"))
    (let ((result (kuro-module--find-library)))
      (should (stringp result))
      (should-not (equal result "/nonexistent/path/libkuro_core.so")))))

(ert-deftest kuro-module-test--find-library-nil-custom-path-no-error ()
  "Tier 1: nil kuro-module-binary-path does not signal an error."
  (let ((kuro-module-binary-path nil))
    (should-not (condition-case err
                    (progn (kuro-module--find-library) nil)
                  (error err)))))

;;; Group 3: kuro-module--find-library — tier 2 (KURO_MODULE_PATH env var)

(ert-deftest kuro-module-test--find-library-env-var-existing ()
  "Tier 2: KURO_MODULE_PATH pointing to a dir with the lib returns its path."
  (let* ((tmpdir (make-temp-file "kuro-env-test-" t))
         (ext (kuro-module--platform-extension))
         (lib-name (format "libkuro_core.%s" ext))
         (tmpfile (expand-file-name lib-name tmpdir)))
    (write-region "" nil tmpfile)
    (unwind-protect
        (let ((kuro-module-binary-path nil))
          (cl-letf (((symbol-function 'getenv)
                     (lambda (var)
                       (if (equal var "KURO_MODULE_PATH") tmpdir
                         (getenv var)))))
            (let ((result (kuro-module--find-library)))
              (should (equal result tmpfile)))))
      (delete-directory tmpdir t))))

(ert-deftest kuro-module-test--find-library-env-var-nonexistent-falls-through ()
  "Tier 2: KURO_MODULE_PATH pointing to a dir without the lib falls through."
  (let* ((tmpdir (make-temp-file "kuro-env-empty-" t)))
    (unwind-protect
        (let ((kuro-module-binary-path nil))
          (cl-letf (((symbol-function 'getenv)
                     (lambda (var)
                       (if (equal var "KURO_MODULE_PATH") tmpdir
                         (getenv var)))))
            ;; No lib file in tmpdir — must fall through (no error, different path)
            (let ((result (kuro-module--find-library)))
              (should (stringp result))
              (should-not (string-prefix-p tmpdir result)))))
      (delete-directory tmpdir t))))

;;; Group 4: kuro-module--find-library — lib name in result

(ert-deftest kuro-module-test--find-library-path-contains-lib-name ()
  "The resolved path always contains the platform-specific library filename."
  (let ((kuro-module-binary-path nil))
    (let* ((path (kuro-module--find-library))
           (ext (kuro-module--platform-extension))
           (lib-name (format "libkuro_core.%s" ext)))
      (should (string-match-p (regexp-quote lib-name) path)))))

(ert-deftest kuro-module-test--find-library-dev-path-contains-target-release ()
  "Tier 4 dev path includes target/release in the resolved path."
  ;; Force tier 4 by providing nil custom path and ensuring env var is unset.
  (let ((kuro-module-binary-path nil))
    (cl-letf (((symbol-function 'getenv)
               (lambda (var)
                 (if (equal var "KURO_MODULE_PATH") nil
                   ;; preserve other env vars like HOME
                   (getenv var)))))
      ;; Only assert when XDG path does not exist (dev environment).
      (let* ((ext (kuro-module--platform-extension))
             (lib-name (format "libkuro_core.%s" ext))
             (xdg-path (expand-file-name lib-name "~/.local/share/kuro/")))
        (unless (file-exists-p xdg-path)
          (let ((path (kuro-module--find-library)))
            (should (string-match-p "target/release" path))))))))

;;; Group 5: Individual tier functions

(ert-deftest kuro-module-tier-custom-returns-path-when-exists ()
  "kuro-module--tier-custom returns kuro-module-binary-path when file exists."
  (let* ((tmpdir (make-temp-file "kuro-tier1-" t))
         (tmpfile (expand-file-name "libkuro_core.so" tmpdir)))
    (write-region "" nil tmpfile)
    (unwind-protect
        (let ((kuro-module-binary-path tmpfile))
          (should (equal (kuro-module--tier-custom) tmpfile)))
      (delete-directory tmpdir t))))

(ert-deftest kuro-module-tier-custom-returns-nil-when-missing ()
  "kuro-module--tier-custom returns nil when the file does not exist."
  (let ((kuro-module-binary-path "/nonexistent-kuro-tier1.so"))
    (cl-letf (((symbol-function 'file-exists-p) (lambda (_) nil)))
      (should-not (kuro-module--tier-custom)))))

(ert-deftest kuro-module-tier-custom-returns-nil-when-path-nil ()
  "kuro-module--tier-custom returns nil when kuro-module-binary-path is nil."
  (let ((kuro-module-binary-path nil))
    (should-not (kuro-module--tier-custom))))

(ert-deftest kuro-module-tier-env-uses-env-var ()
  "kuro-module--tier-env returns the expanded lib path when env dir and file exist."
  (let* ((tmpdir (make-temp-file "kuro-tier2-" t))
         (ext (kuro-module--platform-extension))
         (lib-name (format "libkuro_core.%s" ext))
         (tmpfile (expand-file-name lib-name tmpdir)))
    (write-region "" nil tmpfile)
    (unwind-protect
        (cl-letf (((symbol-function 'getenv)
                   (lambda (var)
                     (if (equal var "KURO_MODULE_PATH") tmpdir
                       (getenv var)))))
          (should (equal (kuro-module--tier-env) tmpfile)))
      (delete-directory tmpdir t))))

(ert-deftest kuro-module-tier-env-returns-nil-when-env-unset ()
  "kuro-module--tier-env returns nil when KURO_MODULE_PATH is unset."
  (cl-letf (((symbol-function 'getenv)
             (lambda (var)
               (if (equal var "KURO_MODULE_PATH") nil
                 (getenv var)))))
    (should-not (kuro-module--tier-env))))

(ert-deftest kuro-module-search-tiers-is-defconst ()
  "kuro-module--search-tiers is a list of exactly 4 function symbols."
  (should (= (length kuro-module--search-tiers) 4))
  (should (cl-every #'symbolp kuro-module--search-tiers)))

(ert-deftest kuro-module-find-library-uses-first-found-tier ()
  "kuro-module--find-library returns the first non-nil tier result."
  (cl-letf (((symbol-function 'kuro-module--tier-custom) (lambda () nil))
            ((symbol-function 'kuro-module--tier-env)    (lambda () "/found/kuro.so"))
            ((symbol-function 'kuro-module--tier-xdg)   (lambda () (error "should not reach xdg")))
            ((symbol-function 'kuro-module--tier-dev)   (lambda () (error "should not reach dev"))))
    (should (equal (kuro-module--find-library) "/found/kuro.so"))))

(ert-deftest kuro-module-find-library-falls-through-to-dev ()
  "kuro-module--find-library reaches tier-dev when all preceding tiers return nil."
  (cl-letf (((symbol-function 'kuro-module--tier-custom) (lambda () nil))
            ((symbol-function 'kuro-module--tier-env)    (lambda () nil))
            ((symbol-function 'kuro-module--tier-xdg)   (lambda () nil))
            ((symbol-function 'kuro-module--tier-dev)   (lambda () "/dev/libkuro_core.so")))
    (should (equal (kuro-module--find-library) "/dev/libkuro_core.so"))))

;;; Group 6: kuro--ensure-module-loaded interface

(ert-deftest kuro-module-test--ensure-module-loaded-is-callable ()
  "`kuro--ensure-module-loaded' is a function that can be called."
  (should (fboundp 'kuro--ensure-module-loaded)))

(ert-deftest kuro-module-test--module-load-is-callable ()
  "`kuro-module-load' is a function."
  (should (fboundp 'kuro-module-load)))

;;; Group 7: kuro--module-try macro

(ert-deftest kuro-module-test--module-try-returns-path-when-file-exists ()
  "`kuro--module-try' returns the path string when the file exists."
  (let* ((tmpdir (make-temp-file "kuro-try-test-" t))
         (tmpfile (expand-file-name "test.so" tmpdir)))
    (write-region "" nil tmpfile)
    (unwind-protect
        (should (equal (kuro--module-try tmpfile) tmpfile))
      (delete-directory tmpdir t))))

(ert-deftest kuro-module-test--module-try-returns-nil-when-file-missing ()
  "`kuro--module-try' returns nil when the file does not exist."
  (should-not (kuro--module-try "/nonexistent-kuro-try-test.so")))

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
  ;; Compute the expected XDG path using the same expression as the SUT, then
  ;; stub file-exists-p to return t for that exact path.
  (let* ((ext (kuro-module--platform-extension))
         (lib-name (format "libkuro_core.%s" ext))
         (expected (expand-file-name lib-name "~/.local/share/kuro/")))
    (cl-letf (((symbol-function 'file-exists-p)
               (lambda (path) (equal path expected))))
      (should (equal (kuro-module--tier-xdg) expected)))))

(ert-deftest kuro-module-tier-xdg-returns-nil-when-file-absent ()
  "`kuro-module--tier-xdg' returns nil when the XDG path does not exist."
  ;; Stub file-exists-p to always return nil for the xdg path specifically.
  (cl-letf (((symbol-function 'file-exists-p) (lambda (_) nil)))
    (should-not (kuro-module--tier-xdg))))

(ert-deftest kuro-module-tier-xdg-path-contains-xdg-dir ()
  "`kuro-module--tier-xdg' constructs a path that includes the XDG share directory."
  ;; Bypass file-exists-p so we can inspect the path expression; we compare
  ;; the path returned by expand-file-name (before the file-exists-p check).
  (let* ((ext (kuro-module--platform-extension))
         (lib-name (format "libkuro_core.%s" ext))
         (expected-xdg (expand-file-name lib-name "~/.local/share/kuro/")))
    ;; Stub file-exists-p to return t so tier-xdg returns the path.
    (cl-letf (((symbol-function 'file-exists-p) (lambda (_) t)))
      (let ((result (kuro-module--tier-xdg)))
        (should (equal result expected-xdg))))))

;;; Group 9: kuro-module--tier-dev

(ert-deftest kuro-module-tier-dev-returns-string ()
  "`kuro-module--tier-dev' returns a string when a dev binary path is accessible."
  (cl-letf (((symbol-function 'locate-library)
             (lambda (_name) "/stub/emacs-lisp/core/kuro-module.el"))
            ((symbol-function 'file-exists-p) (lambda (_) t)))
    (should (stringp (kuro-module--tier-dev)))))

(ert-deftest kuro-module-tier-dev-path-contains-target-release ()
  "`kuro-module--tier-dev' path contains \"target/release\"."
  (cl-letf (((symbol-function 'locate-library)
             (lambda (_name) "/stub/emacs-lisp/core/kuro-module.el"))
            ((symbol-function 'file-exists-p) (lambda (_) t)))
    (should (string-match-p "target/release" (kuro-module--tier-dev)))))

(ert-deftest kuro-module-tier-dev-path-contains-lib-name ()
  "`kuro-module--tier-dev' path contains the platform library filename."
  (let* ((ext (kuro-module--platform-extension))
         (lib-name (format "libkuro_core.%s" ext)))
    (cl-letf (((symbol-function 'locate-library)
               (lambda (_name) "/stub/emacs-lisp/core/kuro-module.el"))
              ((symbol-function 'file-exists-p) (lambda (_) t)))
      (should (string-match-p (regexp-quote lib-name) (kuro-module--tier-dev))))))

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

;;; Group 11: kuro-module--find-library — all tiers return nil

(ert-deftest kuro-module-find-library-all-tiers-nil-returns-dev-fallback ()
  "When custom/env/xdg tiers return nil and dev returns a string, the string is returned."
  ;; This is equivalent to the all-nil path: dev cannot return nil (it uses
  ;; expand-file-name unconditionally), so test that only-dev-non-nil works.
  (cl-letf (((symbol-function 'kuro-module--tier-custom) (lambda () nil))
            ((symbol-function 'kuro-module--tier-env)    (lambda () nil))
            ((symbol-function 'kuro-module--tier-xdg)   (lambda () nil))
            ((symbol-function 'kuro-module--tier-dev)   (lambda () "/stub/libkuro_core.so")))
    (should (equal (kuro-module--find-library) "/stub/libkuro_core.so"))))

(ert-deftest kuro-module-find-library-stops-at-first-non-nil ()
  "kuro-module--find-library stops at tier-custom and does not call later tiers."
  (let ((env-called nil)
        (xdg-called nil)
        (dev-called nil))
    (cl-letf (((symbol-function 'kuro-module--tier-custom)
               (lambda () "/custom/libkuro_core.so"))
              ((symbol-function 'kuro-module--tier-env)
               (lambda () (setq env-called t) "/env/lib.so"))
              ((symbol-function 'kuro-module--tier-xdg)
               (lambda () (setq xdg-called t) "/xdg/lib.so"))
              ((symbol-function 'kuro-module--tier-dev)
               (lambda () (setq dev-called t) "/dev/lib.so")))
      (kuro-module--find-library)
      (should-not env-called)
      (should-not xdg-called)
      (should-not dev-called))))

;;; Group 12: kuro--ensure-module-loaded

(ert-deftest kuro-module-test--ensure-module-loaded-noop-when-already-loaded ()
  "`kuro--ensure-module-loaded' does not call `kuro-module-load' when already loaded."
  (let ((kuro--module-loaded t)
        (load-called nil))
    (cl-letf (((symbol-function 'kuro-module-load)
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
  (let ((last-message nil))
    (cl-letf (((symbol-function 'fboundp) (lambda (sym)
                                            (if (eq sym 'kuro-core-init) nil
                                              (fboundp sym))))
              ((symbol-function 'kuro-module--find-library)
               (lambda () "/nonexistent/libkuro_core.so"))
              ((symbol-function 'file-exists-p) (lambda (_) nil))
              ((symbol-function 'message)
               (lambda (fmt &rest args) (setq last-message (apply #'format fmt args)))))
      (kuro-module-load)
      ;; The message must contain either "not found" or the searched path.
      (should (stringp last-message))
      (should (string-match-p "kuro" last-message)))))

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
  ;; Format is always libkuro_core.<ext>; the stem uses underscores not dots.
  (let* ((lib-name (kuro-module--lib-name))
         (stem (substring lib-name 0 (string-match "\\." lib-name))))
    (should-not (string-match-p "\\." stem))))

(ert-deftest kuro-module-tier-xdg-uses-lib-name ()
  "`kuro-module--tier-xdg' result (when file exists) ends with kuro-module--lib-name."
  (let* ((lib-name (kuro-module--lib-name))
         (expected (expand-file-name lib-name "~/.local/share/kuro/")))
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
  "`kuro-module-load' calls `module-load' with the located file path when it exists.
kuro-core-init is naturally unbound in the test environment, so no fboundp stub needed."
  (let ((loaded-path nil))
    ;; Temporarily unbind kuro-core-init if somehow bound (defensive).
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
  ;; Capture the format string and first arg rather than the formatted result
  ;; to avoid any recursive message calls.
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
              ;; The path is passed as the %s argument to message.
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


;;; Group 17: kuro-module--platform-string Rust-triple mapping

(ert-deftest kuro-module-test--platform-string-darwin-aarch64 ()
  "`kuro-module--platform-string' returns aarch64-apple-darwin on darwin/arm64."
  (should (equal (kuro-module--platform-string 'darwin "aarch64-apple-darwin23.0")
                 "aarch64-apple-darwin")))

(ert-deftest kuro-module-test--platform-string-darwin-arm64-prefix ()
  "`kuro-module--platform-string' also accepts arm64 as the aarch64 prefix on darwin."
  (should (equal (kuro-module--platform-string 'darwin "arm64-apple-darwin23.0")
                 "aarch64-apple-darwin")))

(ert-deftest kuro-module-test--platform-string-darwin-x86_64 ()
  "`kuro-module--platform-string' returns x86_64-apple-darwin on darwin/x86_64."
  (should (equal (kuro-module--platform-string 'darwin "x86_64-apple-darwin23.0")
                 "x86_64-apple-darwin")))

(ert-deftest kuro-module-test--platform-string-linux-x86_64 ()
  "`kuro-module--platform-string' returns x86_64-unknown-linux-gnu on Linux/x86_64."
  (should (equal (kuro-module--platform-string 'gnu/linux "x86_64-pc-linux-gnu")
                 "x86_64-unknown-linux-gnu")))

(ert-deftest kuro-module-test--platform-string-linux-aarch64 ()
  "`kuro-module--platform-string' returns aarch64-unknown-linux-gnu on Linux/arm64."
  (should (equal (kuro-module--platform-string 'gnu/linux "aarch64-unknown-linux-gnu")
                 "aarch64-unknown-linux-gnu")))

(ert-deftest kuro-module-test--platform-string-unknown-errors ()
  "`kuro-module--platform-string' signals an error for unsupported platforms."
  (should-error (kuro-module--platform-string 'windows-nt "x86_64-pc-windows-msvc")
                :type 'error))

;;; Group 18: kuro-module--verify-sha256

(ert-deftest kuro-module-test--verify-sha256-match-passes ()
  "`kuro-module--verify-sha256' returns t when the file digest matches."
  (let ((tmpfile (make-temp-file "kuro-hash-")))
    (unwind-protect
        (progn
          (with-temp-file tmpfile (insert "hello kuro"))
          (let ((expected (with-temp-buffer
                            (set-buffer-multibyte nil)
                            (insert-file-contents-literally tmpfile)
                            (secure-hash 'sha256 (current-buffer)))))
            (should (kuro-module--verify-sha256 tmpfile expected))))
      (delete-file tmpfile))))

(ert-deftest kuro-module-test--verify-sha256-mismatch-rejects ()
  "`kuro-module--verify-sha256' returns nil when the digest does not match."
  (let ((tmpfile (make-temp-file "kuro-hash-")))
    (unwind-protect
        (progn
          (with-temp-file tmpfile (insert "hello kuro"))
          (should-not
           (kuro-module--verify-sha256
            tmpfile
            "0000000000000000000000000000000000000000000000000000000000000000")))
      (delete-file tmpfile))))

(ert-deftest kuro-module-test--verify-sha256-nil-hash-warns-and-passes ()
  "`kuro-module--verify-sha256' returns t when EXPECTED-HASH is nil and emits a warning."
  (let ((tmpfile (make-temp-file "kuro-hash-"))
        (warned nil))
    (unwind-protect
        (cl-letf (((symbol-function 'display-warning)
                   (lambda (&rest _args) (setq warned t))))
          (with-temp-file tmpfile (insert "hello kuro"))
          (should (kuro-module--verify-sha256 tmpfile nil))
          (should warned))
      (delete-file tmpfile))))

;;; Group 19: kuro-module--shared-extension

(ert-deftest kuro-module-test--shared-extension-darwin ()
  "`kuro-module--shared-extension' returns \".dylib\" on darwin."
  (let ((system-type 'darwin))
    (should (equal (kuro-module--shared-extension) ".dylib"))))

(ert-deftest kuro-module-test--shared-extension-linux ()
  "`kuro-module--shared-extension' returns \".so\" on GNU/Linux."
  (let ((system-type 'gnu/linux))
    (should (equal (kuro-module--shared-extension) ".so"))))

;;; Group 20: kuro-module--target-path

(ert-deftest kuro-module-test--target-path-honours-xdg ()
  "`kuro-module--target-path' uses XDG_DATA_HOME when set."
  (let* ((tmpdir (make-temp-file "kuro-xdg-" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'getenv)
                   (lambda (var)
                     (if (equal var "XDG_DATA_HOME") tmpdir (getenv var)))))
          (let ((dir (kuro-module--target-path)))
            (should (equal dir (expand-file-name "kuro" tmpdir)))
            (should (file-directory-p dir))))
      (delete-directory tmpdir t))))

(ert-deftest kuro-module-test--target-path-creates-directory ()
  "`kuro-module--target-path' creates the install directory if it is missing."
  (let* ((tmpdir (make-temp-file "kuro-xdg-" t))
         (target (expand-file-name "kuro" tmpdir)))
    (unwind-protect
        (cl-letf (((symbol-function 'getenv)
                   (lambda (var)
                     (if (equal var "XDG_DATA_HOME") tmpdir (getenv var)))))
          (should-not (file-directory-p target))
          (kuro-module--target-path)
          (should (file-directory-p target)))
      (delete-directory tmpdir t))))

;;; Group 21: kuro-module-download error paths

(ert-deftest kuro-module-test--download-tar-not-found ()
  "`kuro-module-download' errors when `tar' is not found in PATH."
  (cl-letf (((symbol-function 'executable-find) (lambda (_cmd) nil)))
    (should (string-match-p "executable not found"
                            (cadr (should-error (kuro-module-download "0.0.0")
                                                :type 'error))))))

(ert-deftest kuro-module-test--download-sha256-fetch-fails ()
  "`kuro-module-download' errors when the .sha256 URL fetch returns nil."
  (cl-letf (((symbol-function 'executable-find) (lambda (_cmd) "/usr/bin/tar"))
            ((symbol-function 'kuro-module--platform-string)
             (lambda (&rest _) "x86_64-unknown-linux-gnu"))
            ((symbol-function 'kuro-module--target-path)
             (lambda () (make-temp-file "kuro-dl-test-" t)))
            ((symbol-function 'url-retrieve-synchronously) (lambda (&rest _) nil))
            ((symbol-function 'message) #'ignore))
    (should (string-match-p "failed to fetch SHA256"
                            (cadr (should-error (kuro-module-download "0.0.0")
                                                :type 'error))))))

(ert-deftest kuro-module-test--download-sha256-mismatch ()
  "`kuro-module-download' errors when SHA256 computed from file differs from expected."
  (let* ((tmpdir (make-temp-file "kuro-dl-mismatch-" t))
         (tmp-tar (expand-file-name "kuro-test.tar.gz" tmpdir))
         (sha-buf (generate-new-buffer " *kuro-sha-test*")))
    (unwind-protect
        (progn
          ;; Create a fake sha buffer with header + a known hash
          (with-current-buffer sha-buf
            (insert "HTTP/1.1 200 OK\r\n\r\n")
            (insert "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
          ;; Create a real temp tar file to write into
          (with-temp-file tmp-tar (insert "fake tarball content"))
          (cl-letf (((symbol-function 'executable-find)
                     (lambda (_cmd) "/usr/bin/tar"))
                    ((symbol-function 'kuro-module--platform-string)
                     (lambda (&rest _) "x86_64-unknown-linux-gnu"))
                    ((symbol-function 'kuro-module--target-path)
                     (lambda () tmpdir))
                    ((symbol-function 'make-temp-file)
                     (lambda (&rest _) tmp-tar))
                    ((symbol-function 'url-retrieve-synchronously)
                     (lambda (url &rest _)
                       (if (string-suffix-p ".sha256" url)
                           sha-buf
                         ;; return a minimal HTTP buffer for the tarball
                         (let ((buf (generate-new-buffer " *kuro-dl-test*")))
                           (with-current-buffer buf
                             (insert "HTTP/1.1 200 OK\r\n\r\nfake"))
                           buf))))
                    ((symbol-function 'write-region) #'ignore)
                    ((symbol-function 'kuro-module--verify-sha256)
                     (lambda (_file _hash) nil))
                    ((symbol-function 'message) #'ignore))
            (should (string-match-p "SHA256 mismatch"
                                    (cadr (should-error (kuro-module-download "0.0.0")
                                                        :type 'error))))))
      (ignore-errors (kill-buffer sha-buf))
      (delete-directory tmpdir t))))

(ert-deftest kuro-module-test--download-tar-extraction-fails ()
  "`kuro-module-download' errors when tar exits with a nonzero code."
  (let* ((tmpdir (make-temp-file "kuro-dl-tarfail-" t))
         (tmp-tar (expand-file-name "kuro-test.tar.gz" tmpdir))
         (sha-buf (generate-new-buffer " *kuro-sha-tarfail*")))
    (unwind-protect
        (progn
          (with-current-buffer sha-buf
            (insert "HTTP/1.1 200 OK\r\n\r\nabc123"))
          (with-temp-file tmp-tar (insert "fake"))
          (cl-letf (((symbol-function 'executable-find)
                     (lambda (_cmd) "/usr/bin/tar"))
                    ((symbol-function 'kuro-module--platform-string)
                     (lambda (&rest _) "x86_64-unknown-linux-gnu"))
                    ((symbol-function 'kuro-module--target-path)
                     (lambda () tmpdir))
                    ((symbol-function 'make-temp-file)
                     (lambda (&rest _) tmp-tar))
                    ((symbol-function 'url-retrieve-synchronously)
                     (lambda (url &rest _)
                       (if (string-suffix-p ".sha256" url)
                           sha-buf
                         (let ((buf (generate-new-buffer " *kuro-dl-tarfail-body*")))
                           (with-current-buffer buf
                             (insert "HTTP/1.1 200 OK\r\n\r\nfake"))
                           buf))))
                    ((symbol-function 'write-region) #'ignore)
                    ((symbol-function 'kuro-module--verify-sha256)
                     (lambda (_file _hash) t))
                    ((symbol-function 'call-process)
                     (lambda (&rest _) 1))
                    ((symbol-function 'delete-file) #'ignore)
                    ((symbol-function 'message) #'ignore))
            (should (string-match-p "tar extraction failed"
                                    (cadr (should-error (kuro-module-download "0.0.0")
                                                        :type 'error))))))
      (ignore-errors (kill-buffer sha-buf))
      (delete-directory tmpdir t))))

(ert-deftest kuro-module-test--download-extracted-binary-missing ()
  "`kuro-module-download' errors when tar succeeds but the extracted file is absent.
Uses a real tmpdir that contains no libkuro_core binary, so file-exists-p
naturally returns nil for the installed-binary check without global stubbing."
  (let* ((tmpdir (make-temp-file "kuro-dl-binmiss-" t))
         (tmp-tar (expand-file-name "kuro-test.tar.gz" tmpdir))
         (sha-buf (generate-new-buffer " *kuro-sha-binmiss*")))
    (unwind-protect
        (progn
          (with-current-buffer sha-buf
            (insert "HTTP/1.1 200 OK\r\n\r\nabc123"))
          (with-temp-file tmp-tar (insert "fake tarball"))
          (cl-letf (((symbol-function 'executable-find)
                     (lambda (_cmd) "/usr/bin/tar"))
                    ((symbol-function 'kuro-module--platform-string)
                     (lambda (&rest _) "x86_64-unknown-linux-gnu"))
                    ((symbol-function 'kuro-module--target-path)
                     (lambda () tmpdir))
                    ((symbol-function 'make-temp-file)
                     (lambda (&rest _) tmp-tar))
                    ((symbol-function 'url-retrieve-synchronously)
                     (lambda (url &rest _)
                       (if (string-suffix-p ".sha256" url)
                           sha-buf
                         (let ((buf (generate-new-buffer " *kuro-dl-binmiss-body*")))
                           (with-current-buffer buf
                             (insert "HTTP/1.1 200 OK\r\n\r\nfake"))
                           buf))))
                    ;; Verify passes, tar returns 0 — but no binary is extracted
                    ((symbol-function 'kuro-module--verify-sha256)
                     (lambda (_file _hash) t))
                    ((symbol-function 'call-process)
                     (lambda (&rest _) 0))
                    ((symbol-function 'message) #'ignore))
            ;; tmpdir has no libkuro_core.so/.dylib → file-exists-p naturally nil
            (should (string-match-p "extracted archive does not contain"
                                    (cadr (should-error (kuro-module-download "0.0.0")
                                                        :type 'error))))))
      (ignore-errors (kill-buffer sha-buf))
      (delete-directory tmpdir t))))

(ert-deftest kuro-module-test--download-sha256-malformed-response ()
  "`kuro-module-download' errors when SHA256 HTTP response has no blank-line separator."
  (let* ((tmpdir (make-temp-file "kuro-dl-malformed-" t))
         (tmp-tar (expand-file-name "kuro-test.tar.gz" tmpdir))
         ;; A buffer with no blank line between headers and body
         (sha-buf (generate-new-buffer " *kuro-sha-malformed*")))
    (unwind-protect
        (progn
          (with-current-buffer sha-buf
            (insert "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nabc123"))
          (with-temp-file tmp-tar (insert "fake"))
          (cl-letf (((symbol-function 'executable-find)
                     (lambda (_cmd) "/usr/bin/tar"))
                    ((symbol-function 'kuro-module--platform-string)
                     (lambda (&rest _) "x86_64-unknown-linux-gnu"))
                    ((symbol-function 'kuro-module--target-path)
                     (lambda () tmpdir))
                    ((symbol-function 'make-temp-file)
                     (lambda (&rest _) tmp-tar))
                    ((symbol-function 'url-retrieve-synchronously)
                     (lambda (url &rest _)
                       (when (string-suffix-p ".sha256" url) sha-buf)))
                    ((symbol-function 'message) #'ignore))
            (should (string-match-p "malformed SHA256 response"
                                    (cadr (should-error (kuro-module-download "0.0.0")
                                                        :type 'error))))))
      (ignore-errors (kill-buffer sha-buf))
      (delete-directory tmpdir t))))

;;; Group 22: kuro-module-build error paths

(ert-deftest kuro-module-test--build-cargo-toml-not-found ()
  "`kuro-module-build' errors when `kuro-module--locate-cargo-toml' returns nil."
  (cl-letf (((symbol-function 'kuro-module--locate-cargo-toml) (lambda () nil)))
    (should (string-match-p "rust-core not found alongside"
                            (cadr (should-error (kuro-module-build) :type 'error))))))

(ert-deftest kuro-module-test--build-cargo-not-found ()
  "`kuro-module-build' errors when `cargo' is not found in PATH."
  (cl-letf (((symbol-function 'kuro-module--locate-cargo-toml)
             (lambda () "/fake/rust-core/Cargo.toml"))
            ((symbol-function 'file-exists-p)
             (lambda (p) (equal p "/fake/rust-core/Cargo.toml")))
            ((symbol-function 'executable-find) (lambda (_cmd) nil)))
    (should (string-match-p "executable not found"
                            (cadr (should-error (kuro-module-build) :type 'error))))))

(ert-deftest kuro-module-test--build-cargo-build-fails ()
  "`kuro-module-build' errors and pops to buffer when cargo exits with nonzero."
  (let ((pop-called nil))
    (cl-letf (((symbol-function 'kuro-module--locate-cargo-toml)
               (lambda () "/fake/rust-core/Cargo.toml"))
              ((symbol-function 'executable-find)
               (lambda (_cmd) "/usr/bin/cargo"))
              ((symbol-function 'call-process)
               (lambda (&rest _) 1))
              ((symbol-function 'pop-to-buffer)
               (lambda (_buf) (setq pop-called t)))
              ((symbol-function 'message) #'ignore))
      (should (string-match-p "cargo build failed"
                              (cadr (should-error (kuro-module-build) :type 'error))))
      (should pop-called))))

(ert-deftest kuro-module-test--build-lib-missing-after-build ()
  "`kuro-module-build' errors when cargo exits 0 but the built lib path is absent."
  (cl-letf (((symbol-function 'kuro-module--locate-cargo-toml)
             (lambda () "/fake/rust-core/Cargo.toml"))
            ((symbol-function 'executable-find)
             (lambda (_cmd) "/usr/bin/cargo"))
            ((symbol-function 'call-process)
             (lambda (&rest _) 0))
            ;; file-exists-p: always returns nil so built lib appears missing
            ((symbol-function 'file-exists-p)
             (lambda (_p) nil))
            ((symbol-function 'kuro-module--target-path)
             (lambda () "/fake/target-dir"))
            ((symbol-function 'message) #'ignore))
    (should (string-match-p "cargo reported success but"
                            (cadr (should-error (kuro-module-build) :type 'error))))))

;;; Group 23: kuro-module--verify-sha256 — dedicated coverage

(ert-deftest kuro-module-test--verify-sha256-nil-hash-warns-and-returns-t ()
  "`kuro-module--verify-sha256' returns t and calls `display-warning' when hash is nil."
  (let ((warned nil)
        (tmpfile (make-temp-file "kuro-verify-nil-")))
    (unwind-protect
        (cl-letf (((symbol-function 'display-warning)
                   (lambda (&rest _) (setq warned t))))
          (with-temp-file tmpfile (insert "content"))
          (should (kuro-module--verify-sha256 tmpfile nil))
          (should warned))
      (delete-file tmpfile))))

(ert-deftest kuro-module-test--verify-sha256-matching-hash-returns-t ()
  "`kuro-module--verify-sha256' returns t when the file hash matches exactly."
  (let ((tmpfile (make-temp-file "kuro-verify-match-")))
    (unwind-protect
        (progn
          (with-temp-file tmpfile (insert "kuro test content"))
          (let ((hash (with-temp-buffer
                        (set-buffer-multibyte nil)
                        (insert-file-contents-literally tmpfile)
                        (secure-hash 'sha256 (current-buffer)))))
            (should (kuro-module--verify-sha256 tmpfile hash))))
      (delete-file tmpfile))))

(ert-deftest kuro-module-test--verify-sha256-mismatched-hash-returns-nil ()
  "`kuro-module--verify-sha256' returns nil when the expected hash does not match."
  (let ((tmpfile (make-temp-file "kuro-verify-mismatch-")))
    (unwind-protect
        (progn
          (with-temp-file tmpfile (insert "kuro test content"))
          (should-not
           (kuro-module--verify-sha256
            tmpfile
            "0000000000000000000000000000000000000000000000000000000000000000")))
      (delete-file tmpfile))))

;;; Group 24: kuro--ensure-module-loaded error path

(ert-deftest kuro-module-test--ensure-module-loaded-errors-when-load-fails ()
  "`kuro--ensure-module-loaded' signals error containing \"native module could not be loaded\"
when `kuro-module-load' runs but `kuro-core-init' remains unbound."
  (let ((was-bound (fboundp 'kuro-core-init)))
    (when was-bound (fmakunbound 'kuro-core-init))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-module-load) #'ignore))
          (should (string-match-p "native module could not be loaded"
                                  (cadr (should-error (kuro--ensure-module-loaded)
                                                      :type 'error)))))
      (when was-bound
        (fset 'kuro-core-init (lambda () nil))))))

(provide 'kuro-module-test)

;;; kuro-module-test.el ends here
