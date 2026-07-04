;;; kuro-colors-test-support.el --- Shared helpers  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-colors)

;;; Test helpers

(defun kuro-colors-test--color-symbols ()
  "Return all `kuro-color-*' symbols in palette order."
  (mapcar #'cdr kuro--color-name-alist))

(defun kuro-colors-test--color-names ()
  "Return all ANSI color names in palette order."
  (mapcar #'car kuro--color-name-alist))

(defun kuro-colors-test--color-name-vector ()
  "Return all ANSI color names as a vector in palette order."
  (vconcat (kuro-colors-test--color-names)))

(defun kuro-colors-test--color-name-subvector (start end)
  "Return ANSI color names from START up to END as a vector."
  (vconcat (cl-subseq (kuro-colors-test--color-names) start end)))

(defun kuro-colors-test--palette-symbol (suffix)
  "Return the `kuro-color-*' symbol for palette SUFFIX."
  (cdr (assoc suffix kuro--color-name-alist)))

(defmacro kuro-colors-test--dolist-color-symbol (binding &rest body)
  "Execute BODY for each color symbol, binding it to SYM."
  (declare (indent 1))
  (let ((sym (car binding)))
    `(dolist (,sym (kuro-colors-test--color-symbols))
       ,@body)))

(defmacro kuro-colors-test--deftest-palette-defaults ()
  "Generate default-value tests for every entry in `kuro--color-palette'."
  `(progn
     ,@(mapcar (lambda (entry)
                 (let* ((suffix (nth 0 entry))
                        (default (nth 1 entry))
                        (sym (kuro-colors-test--palette-symbol suffix))
                        (test-name (intern (format "kuro-colors--defcolor-%s-default-value"
                                                   suffix))))
                   `(ert-deftest ,test-name ()
                      ,(format "kuro--defcolor generates `%s' with default value %s."
                               sym default)
                      (should (equal ,sym ,default)))))
               kuro--color-palette)))

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
