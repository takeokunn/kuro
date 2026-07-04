;;; kuro-mux-test-8.el --- Unit tests for kuro-mux-ext2.el binding tables  -*- lexical-binding: t; -*-

;;; Commentary:
;; Groups 37-38: data-invariant tests for kuro-mux--prefix-bindings and
;; kuro-mux--prefix-resize-bindings, plus a table-driven binding coverage
;; test that verifies every entry is correctly installed in kuro-mux-prefix-map.

;;; Code:

(require 'kuro-test-stubs)
(require 'kuro-config)
(require 'kuro-mux)
(require 'kuro-mux-test-macros)


(kuro-mux-test--deftest-prefix-bindings-invariants)
(kuro-mux-test--deftest-prefix-resize-bindings-invariants)

(provide 'kuro-mux-test-8)
;;; kuro-mux-test-8.el ends here
