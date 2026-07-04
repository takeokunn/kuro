;;; kuro-faces-color-test-support.el --- Shared helpers  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-faces-color)

(defmacro kuro-faces-color-test--should-decode (name encoded expected)
  "Define NAME as an ERT test asserting ENCODED decodes to EXPECTED."
  `(ert-deftest ,name ()
     (should (equal (kuro--decode-ffi-color ,encoded) ,expected))))

(defmacro kuro-faces-color-test--should-indexed-color (name index expected)
  "Define NAME as an ERT test asserting INDEX resolves to EXPECTED."
  `(ert-deftest ,name ()
     (should (equal (kuro--indexed-to-emacs ,index) ,expected))))


(provide 'kuro-faces-color-test-support)
;;; kuro-faces-color-test-support.el ends here
