;;; kuro-render-buffer-test-macros.el --- Render-buffer test macros  -*- lexical-binding: t; -*-

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'kuro-render-buffer)
(require 'kuro-render-buffer-test-cases)

;;; Primary test buffer helper

(defmacro kuro-render-buffer-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer with render-buffer state initialized."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (inhibit-modification-hooks t)
           (kuro--initialized nil)
           (kuro--scroll-offset 0)
           (kuro--last-rows 24)
           (kuro--col-to-buf-map (make-hash-table :test 'eql))
           (kuro--blink-overlays-by-row nil)
           kuro--blink-overlays
           kuro--image-overlays)
       ,@body)))

;;; Utility

(defun kuro-render-buffer-test--line-count (buf)
  "Return the number of lines in BUF."
  (with-current-buffer buf
    (count-lines (point-min) (point-max))))

;;; Face-call recording and stubbing

(defmacro kuro-render-buffer-test--capture-face-calls (calls-var &rest body)
  "Run BODY while recording `kuro--apply-ffi-face-at' calls in CALLS-VAR."
  (declare (indent 1))
  `(let ((,calls-var nil))
     (cl-letf (((symbol-function 'kuro--apply-ffi-face-at)
                (lambda (s e fg bg fl _ul)
                  (push (list s e fg bg fl) ,calls-var))))
       ,@body)))

(defmacro kuro-render-buffer-test--with-render-stubs (&rest body)
  "Run BODY with face and image overlay side-effects stubbed to no-ops.
Stubs `kuro--apply-ffi-face-at' and `kuro--clear-row-image-overlays' so
tests focused on text content or position cache logic are not affected by
face application or image overlay management side-effects."
  `(cl-letf (((symbol-function 'kuro--apply-ffi-face-at)        #'ignore)
             ((symbol-function 'kuro--clear-row-image-overlays)  #'ignore))
     ,@body))

;;; Cursor test buffer helper

(defmacro kuro-render-buffer-cursor-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer with cursor-update state initialized."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (inhibit-modification-hooks t)
           (kuro--scroll-offset 0)
           (kuro--col-to-buf-map (make-hash-table :test 'eql))
           kuro--cursor-marker
           kuro--last-cursor-row
           kuro--last-cursor-col
           kuro--last-cursor-visible
           kuro--last-cursor-shape
           kuro--blink-overlays
           kuro--image-overlays)
       ,@body)))

(defmacro kuro-render-buffer-cursor-test--with-cursor-stubs (state &rest body)
  "Run BODY with cursor-state and window lookup stubbed.
STATE is the list returned by `kuro--get-cursor-state'."
  `(cl-letf (((symbol-function 'kuro--get-cursor-state)
              (lambda () ,state))
             ((symbol-function 'get-buffer-window)
              (lambda (&rest _) (selected-window))))
     ,@body))

(defmacro kuro-render-buffer-test--def-decscusr-case (case)
  "Define one DECSCUSR conversion test from CASE."
  (pcase-let ((`(,name ,doc ,input ,expected) case))
    `(ert-deftest ,name ()
       ,doc
       (should (equal (kuro--decscusr-to-cursor-type ,input) ',expected)))))

(defmacro kuro-render-buffer-test--deftest-decscusr-cases ()
  "Define DECSCUSR conversion tests."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-render-buffer-test--def-decscusr-case ,case))
               kuro-render-buffer-test--decscusr-cases)))

(defmacro kuro-render-buffer-test--deftest-decscusr-default-cases ()
  "Define unknown DECSCUSR fallback tests."
  `(ert-deftest kuro-render-buffer-decscusr-unknown-defaults-to-box ()
     "Unknown DECSCUSR value falls through to box cursor (safe default)."
     ,@(mapcar (lambda (case)
                 (pcase-let ((`(,input ,expected) case))
                   `(should (equal (kuro--decscusr-to-cursor-type ,input)
                                   ',expected))))
               kuro-render-buffer-test--decscusr-default-cases)))

(defmacro kuro-render-buffer-test--def-decscusr-alias-case (case)
  "Define one DECSCUSR alias test from CASE."
  (pcase-let ((`(,name ,doc ,left ,right) case))
    `(ert-deftest ,name ()
       ,doc
       (should (equal (kuro--decscusr-to-cursor-type ,left)
                      (kuro--decscusr-to-cursor-type ,right))))))

(defmacro kuro-render-buffer-test--deftest-decscusr-alias-cases ()
  "Define DECSCUSR alias tests."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-render-buffer-test--def-decscusr-alias-case ,case))
               kuro-render-buffer-test--decscusr-alias-cases)))

(defmacro kuro-render-buffer-test--def-decscusr-shape-kind-case (case)
  "Define one DECSCUSR shape-to-kind test from CASE."
  (pcase-let ((`(,name ,doc ,shape ,kind) case))
    `(ert-deftest ,name ()
       ,doc
       (let ((result (kuro--decscusr-to-cursor-type ,shape)))
         ,(if (eq kind 'box)
              `(should (eq 'box result))
            `(progn
               (should (consp result))
               (should (eq (car result) ',kind))))))))

(defmacro kuro-render-buffer-test--deftest-decscusr-shape-kind-cases ()
  "Define DECSCUSR shape-to-kind cursor tests."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-render-buffer-test--def-decscusr-shape-kind-case ,case))
               kuro-render-buffer-test--decscusr-shape-kind-cases)))

(defmacro kuro-render-buffer-test--def-decscusr-fallback-shape-case (case)
  "Define one invalid DECSCUSR fallback test from CASE."
  (pcase-let ((`(,name ,doc ,shapes) case))
    `(ert-deftest ,name ()
       ,doc
       ,@(mapcar (lambda (shape)
                   `(should (eq 'box (kuro--decscusr-to-cursor-type ,shape))))
                 shapes))))

(defmacro kuro-render-buffer-test--deftest-decscusr-fallback-shape-cases ()
  "Define invalid DECSCUSR shape fallback tests."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-render-buffer-test--def-decscusr-fallback-shape-case ,case))
               kuro-render-buffer-test--decscusr-fallback-shape-cases)))

(defmacro kuro-render-buffer-test--deftest-decscusr-valid-shapes-non-nil ()
  "Define the DECSCUSR valid-shape non-nil invariant test."
  `(ert-deftest kuro-render-buffer-decscusr-all-valid-shapes-non-nil ()
     "All valid shapes 0-6 return non-nil cursor-type values."
     (dotimes (n 7)
       (should (kuro--decscusr-to-cursor-type n)))))

(defmacro kuro-render-buffer-test--def-apply-cursor-display-case (case)
  "Define one `kuro--apply-cursor-display' test from CASE."
  (pcase-let ((`(,name ,doc ,visible ,shape ,initial ,expected) case))
    `(ert-deftest ,name ()
       ,doc
       (kuro-render-buffer-test--with-buffer
         (setq-local cursor-type ',initial)
         (kuro--apply-cursor-display ,visible ,shape)
         (should (equal cursor-type ',expected))))))

(defmacro kuro-render-buffer-test--deftest-apply-cursor-display-cases ()
  "Define cursor display application tests."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-render-buffer-test--def-apply-cursor-display-case ,case))
               kuro-render-buffer-test--apply-cursor-display-cases)))

(defmacro kuro-render-buffer-test--def-decscusr-cursor-type-vector-case (case)
  "Define one cursor type vector invariant test from CASE."
  (pcase-let ((`(,name ,predicate) case))
    `(ert-deftest ,name ()
       (should ,predicate))))

(defmacro kuro-render-buffer-test--deftest-decscusr-cursor-type-vector-cases ()
  "Define cursor type vector invariant tests."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-render-buffer-test--def-decscusr-cursor-type-vector-case ,case))
               kuro-render-buffer-test--decscusr-cursor-type-vector-cases)))

(defmacro kuro-render-buffer-test--def-cursor-state-changed-case (case)
  "Define one `kuro--cursor-state-changed-p' test from CASE."
  (pcase-let ((`(,name ,cached ,incoming ,expected) case))
    (pcase-let ((`(,last-row ,last-col ,last-visible ,last-shape) cached)
                (`(,row ,col ,visible ,shape) incoming))
      `(ert-deftest ,name ()
         (let ((kuro--last-cursor-row ,last-row)
               (kuro--last-cursor-col ,last-col)
               (kuro--last-cursor-visible ,last-visible)
               (kuro--last-cursor-shape ,last-shape))
           ,(if expected
                `(should (kuro--cursor-state-changed-p ,row ,col ,visible ,shape))
              `(should-not (kuro--cursor-state-changed-p ,row ,col ,visible ,shape))))))))

(defmacro kuro-render-buffer-test--deftest-cursor-state-changed-cases ()
  "Define cursor state change detection tests."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-render-buffer-test--def-cursor-state-changed-case ,case))
               kuro-render-buffer-test--cursor-state-changed-cases)))

(defmacro kuro-render-buffer-test--def-cache-cursor-state-expansion-case (case)
  "Define one cache-cursor-state macro expansion test from CASE."
  (pcase-let ((`(,name ,doc ,predicate) case))
    `(ert-deftest ,name ()
       ,doc
       (let ((exp (macroexpand-1 '(kuro--cache-cursor-state r c v s))))
         (should ,predicate)))))

(defmacro kuro-render-buffer-test--deftest-cache-cursor-state-expansion-cases ()
  "Define cache-cursor-state macro expansion tests."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-render-buffer-test--def-cache-cursor-state-expansion-case ,case))
               kuro-render-buffer-test--cache-cursor-state-expansion-cases)))

(provide 'kuro-render-buffer-test-macros)

;;; kuro-render-buffer-test-macros.el ends here
