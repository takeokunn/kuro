;;; kuro-colors-test-support.el --- Shared helpers  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-colors)


(require 'ert)
(require 'cl-lib)
(require 'kuro-colors)

;;; Test helpers

(defmacro kuro-colors-test--with-saved-color (sym &rest body)
  "Execute BODY with SYM's current value saved, restoring it on exit.
Also calls `kuro--rebuild-named-colors' after restoration so that
`kuro--named-colors' reflects the original state."
  (declare (indent 1))
  (let ((orig-var (gensym "orig-")))
    `(let ((,orig-var (symbol-value ',sym)))
       (unwind-protect
           (progn ,@body)
         (set-default ',sym ,orig-var)
         (kuro--rebuild-named-colors)))))


(provide 'kuro-colors-test-support)
;;; kuro-colors-test-support.el ends here
