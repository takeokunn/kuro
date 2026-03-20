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

;;; Group 5: kuro--module-loaded state variable

(ert-deftest kuro-module-test--module-loaded-var-is-defined ()
  "`kuro--module-loaded' is defined as a variable."
  (should (boundp 'kuro--module-loaded)))

(ert-deftest kuro-module-test--ensure-module-loaded-is-callable ()
  "`kuro--ensure-module-loaded' is a function that can be called."
  (should (fboundp 'kuro--ensure-module-loaded)))

(ert-deftest kuro-module-test--module-load-is-callable ()
  "`kuro-module-load' is a function."
  (should (fboundp 'kuro-module-load)))

(provide 'kuro-module-test)

;;; kuro-module-test.el ends here
