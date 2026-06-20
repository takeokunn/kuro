;;; kuro-input-mouse-test-macros.el --- Mouse input test macros  -*- lexical-binding: t; -*-

;;; Commentary:

;; Macro and helper logic for generated mouse input tests.

;;; Code:

(require 'cl-lib)
(require 'kuro-input-mouse-test-cases)

(defmacro kuro-input-mouse-test--with-send (mode sgr pixel col row &rest body)
  "Execute BODY with mouse stubs installed and `sent' bound."
  (declare (indent 5))
  `(kuro-mouse-test--with-state ,mode ,sgr ,pixel
     (let ((sent nil))
       (cl-letf (((symbol-function 'kuro--send-key)
                  (lambda (s) (setq sent s)))
                 ((symbol-function 'event-start)
                  (lambda (_ev) 'fake-pos))
                 ((symbol-function 'posn-col-row)
                  (lambda (_pos) (cons ,col ,row)))
                 ((symbol-function 'posn-x-y)
                  (lambda (_pos) (cons ,col ,row))))
         ,@body))))

(defmacro kuro-input-mouse-test--with-send-and-type (mode sgr pixel col row event-type &rest body)
  "Like `kuro-input-mouse-test--with-send' but stubs `event-basic-type'."
  (declare (indent 6))
  `(kuro-mouse-test--with-state ,mode ,sgr ,pixel
     (let ((sent nil))
       (cl-letf (((symbol-function 'kuro--send-key)
                  (lambda (s) (setq sent s)))
                 ((symbol-function 'event-basic-type)
                  (lambda (_ev) ,event-type))
                 ((symbol-function 'event-start)
                  (lambda (_ev) 'fake-pos))
                 ((symbol-function 'posn-col-row)
                  (lambda (_pos) (cons ,col ,row)))
                 ((symbol-function 'posn-x-y)
                  (lambda (_pos) (cons ,col ,row))))
         ,@body))))

(defmacro kuro-mouse-test--with-state (mode sgr pixel &rest body)
  "Execute BODY in a temp buffer with mouse MODE, SGR, and PIXEL state."
  (declare (indent 3))
  `(with-temp-buffer
     (setq-local kuro--mouse-mode ,mode
                 kuro--mouse-sgr ,sgr
                 kuro--mouse-pixel-mode ,pixel)
     ,@body))

(defmacro kuro-mouse-test--with-event (col row &rest body)
  "Execute BODY with event position functions stubbed for COL and ROW."
  (declare (indent 2))
  `(cl-letf (((symbol-function 'event-start)
               (lambda (_ev) 'fake-pos))
              ((symbol-function 'posn-col-row)
               (lambda (_pos) (cons ,col ,row)))
              ((symbol-function 'posn-x-y)
               (lambda (_pos) (cons ,col ,row))))
     ,@body))

(defmacro kuro-mouse-test--with-encode-buffer (mode sgr pixel col row &rest body)
  "Temp buffer with mouse MODE/SGR/PIXEL and event position COL/ROW; run BODY."
  (declare (indent 5))
  `(kuro-mouse-test--with-state ,mode ,sgr ,pixel
     (kuro-mouse-test--with-event ,col ,row
       ,@body)))

(defmacro kuro-mouse-test--full-stub (col row btn-type &rest body)
  "Stub all event functions and run BODY with COL/ROW position and BTN-TYPE basic type."
  (declare (indent 3))
  `(cl-letf (((symbol-function 'event-start)
               (lambda (_ev) 'fake-pos))
              ((symbol-function 'event-basic-type)
               (lambda (_ev) ,btn-type))
              ((symbol-function 'posn-col-row)
               (lambda (_pos) (cons ,col ,row)))
              ((symbol-function 'posn-x-y)
               (lambda (_pos) (cons ,col ,row))))
     ,@body))

(defun kuro-input-mouse-test--selected-cases (cases names)
  "Return CASES filtered by NAMES, preserving CASES order."
  (if names
      (cl-remove-if-not (lambda (case) (memq (car case) names)) cases)
    cases))

(defmacro kuro-input-mouse-test--deftest-dispatch-cases (&rest names)
  "Define dispatch mouse tests selected by NAMES."
  `(progn
     ,@(mapcar
        (lambda (case)
          (pcase-let ((`(,name ,doc ,mode ,sgr ,pixel ,col ,row ,button ,press ,expected)
                       case))
            `(ert-deftest ,name ()
               ,doc
               (kuro-input-mouse-test--with-send ,mode ,sgr ,pixel ,col ,row
                 (kuro--dispatch-mouse-event ,button ,press)
                 ,(if expected
                      `(should (equal sent ,expected))
                    `(should-not sent))))))
        (kuro-input-mouse-test--selected-cases
         kuro-input-mouse-test--dispatch-cases names))))

(defmacro kuro-input-mouse-test--deftest-encode-cases (&rest names)
  "Define encode mouse tests selected by NAMES."
  `(progn
     ,@(mapcar
        (lambda (case)
          (pcase-let ((`(,name ,doc ,mode ,sgr ,pixel ,col ,row ,button ,press ,expected)
                       case))
            `(ert-deftest ,name ()
               ,doc
               (kuro-mouse-test--with-encode-buffer ,mode ,sgr ,pixel ,col ,row
                 (let ((result (kuro--encode-mouse 'fake-event ,button ,press)))
                   ,(if expected
                        `(should (equal result ,expected))
                      `(should-not result)))))))
        (kuro-input-mouse-test--selected-cases
         kuro-input-mouse-test--encode-cases names))))

(defmacro kuro-input-mouse-test--deftest-event-command-cases (&rest names)
  "Define generated mouse command tests selected by NAMES."
  `(progn
     ,@(mapcar
        (lambda (case)
          (pcase-let ((`(,name ,doc ,mode ,sgr ,pixel ,col ,row ,event-type
                        ,command ,expected)
                       case))
            `(ert-deftest ,name ()
               ,doc
               (kuro-input-mouse-test--with-send-and-type
                   ,mode ,sgr ,pixel ,col ,row ',event-type
                 (funcall #',command)
                 ,(if expected
                      `(should (equal sent ,expected))
                    `(should-not sent))))))
        (kuro-input-mouse-test--selected-cases
         kuro-input-mouse-test--event-command-cases names))))

(defmacro kuro-input-mouse-test--deftest-scroll-command-cases (&rest names)
  "Define scroll mouse command tests selected by NAMES."
  `(progn
     ,@(mapcar
        (lambda (case)
          (pcase-let ((`(,name ,doc ,mode ,sgr ,pixel ,col ,row ,command ,expected)
                       case))
            `(ert-deftest ,name ()
               ,doc
               (kuro-input-mouse-test--with-send ,mode ,sgr ,pixel ,col ,row
                 (funcall #',command)
                 ,(if expected
                      `(should (equal sent ,expected))
                    `(should-not sent))))))
        (kuro-input-mouse-test--selected-cases
         kuro-input-mouse-test--scroll-command-cases names))))

(defmacro kuro-input-mouse-test--deftest-button-alist-cases (&rest names)
  "Define `kuro--mouse-button-alist' lookup tests selected by NAMES."
  `(progn
     ,@(mapcar
        (lambda (case)
          (pcase-let ((`(,name ,doc ,event-type ,expected) case))
            `(ert-deftest ,name ()
               ,doc
               ,(if expected
                    `(should (= (alist-get ',event-type kuro--mouse-button-alist)
                                ,expected))
                  `(should (null (alist-get ',event-type
                                            kuro--mouse-button-alist)))))))
        (kuro-input-mouse-test--selected-cases
         kuro-input-mouse-test--button-alist-cases names))))

(provide 'kuro-input-mouse-test-macros)

;;; kuro-input-mouse-test-macros.el ends here
