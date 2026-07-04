;;; kuro-input-keys-test-macros.el --- Shared key input test macros  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-input)
(require 'kuro-input-keys-test-cases)

(defun kuro-input-keys-test--all-sequence-handlers ()
  "Return all handlers generated from input key sequences."
  (append (mapcar #'car kuro-input-keys-test--arrow-sequences)
          (mapcar #'car kuro-input-keys-test--navigation-sequences)
          (mapcar #'car kuro-input-keys-test--function-key-sequences)))

(defun kuro-input-keys-test--function-sequence-range (start end)
  "Return function-key sequence entries from START up to END."
  (cl-subseq kuro-input-keys-test--function-key-sequences start end))

(defun kuro-input-keys-test--string-sequence-sample-handlers ()
  "Return a representative list of handlers that should send strings."
  (append (mapcar #'car kuro-input-keys-test--arrow-sequences)
          '(kuro--HOME kuro--END kuro--F1 kuro--F4 kuro--F5 kuro--F12)))

(defvar kuro-input-keys-test--sent nil
  "List of strings sent via `kuro--send-key' during tests (most recent first).")

(defmacro kuro-input-keys-test--dolist-cursor-mode (spec &rest body)
  "Execute BODY once for each cursor mode.
SPEC is a one-element list containing the variable to bind."
  (declare (indent 1))
  (let ((mode (car spec)))
    `(dolist (,mode kuro-input-keys-test--cursor-modes)
       ,@body)))

(defmacro kuro-input-keys-test--with-cursor-mode (mode &rest body)
  "Execute BODY with `kuro--application-cursor-keys-mode' bound to MODE."
  (declare (indent 1))
  `(let ((kuro--application-cursor-keys-mode ,mode))
     ,@body))

(defmacro kuro-input-keys-test--with-capture (&rest body)
  "Execute BODY with `kuro--send-key' capturing to `kuro-input-keys-test--sent'."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'kuro--send-key)
              (lambda (data) (push data kuro-input-keys-test--sent)))
             ((symbol-function 'kuro--schedule-immediate-render)
              (lambda () nil)))
     (setq kuro-input-keys-test--sent nil)
     ,@body))

(defmacro kuro-input-keys-test--with-kkp (flags &rest body)
  "Execute BODY with `kuro--keyboard-flags' bound to FLAGS and key capture active."
  (declare (indent 1))
  `(kuro-input-keys-test--with-capture
     (let ((kuro--keyboard-flags ,flags))
       ,@body)))

(defmacro kuro-input-keys-test--assert-sequence (fn mode expected)
  "Assert that FN sends EXPECTED in cursor MODE."
  `(kuro-input-keys-test--with-cursor-mode ,mode
     (kuro-input-keys-test--with-capture
       (funcall ,fn)
       (should (equal (car kuro-input-keys-test--sent) ,expected)))))

(defmacro kuro-input-keys-test--deftest-sequences (&rest specs)
  "Define ERT sequence tests from SPECS.
Each spec is (NAME FN MODE EXPECTED DOCSTRING)."
  (declare (indent 0))
  `(progn
     ,@(mapcar
        (lambda (spec)
          (let ((name (nth 0 spec))
                (fn (nth 1 spec))
                (mode (nth 2 spec))
                (expected (nth 3 spec))
                (docstring (nth 4 spec)))
            `(ert-deftest ,name ()
               ,docstring
               (kuro-input-keys-test--assert-sequence #',fn ,mode ,expected))))
        specs)))

(defmacro kuro-input-keys-test--deftest-sequence-cases (cases)
  "Define sequence tests from the data list named by CASES."
  (declare (indent 0))
  `(kuro-input-keys-test--deftest-sequences
     ,@(symbol-value cases)))

(defmacro kuro-input-keys-test--def-ctrl-modified-case (case)
  "Define one ctrl-modified ERT test from CASE."
  (let ((name (nth 0 case))
        (docstring (nth 1 case))
        (char (nth 2 case))
        (modifier (nth 3 case))
        (expected-byte (nth 4 case)))
    `(ert-deftest ,name ()
       ,docstring
       (kuro-input-keys-test--with-capture
         (kuro--ctrl-modified ,char ,modifier)
         (should (equal (car kuro-input-keys-test--sent)
                        (string ,expected-byte)))))))

(defmacro kuro-input-keys-test--deftest-ctrl-modified-cases ()
  "Define ctrl-modified send tests."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-input-keys-test--def-ctrl-modified-case ,case))
               kuro-input-keys-test--ctrl-modified-cases)))

(defmacro kuro-input-keys-test--def-alt-modified-case (case)
  "Define one alt-modified ERT test from CASE."
  (let ((name (nth 0 case))
        (docstring (nth 1 case))
        (char (nth 2 case))
        (expected (nth 3 case)))
    `(ert-deftest ,name ()
       ,docstring
       (kuro-input-keys-test--with-capture
         (kuro--alt-modified ,char)
         (should (equal (car kuro-input-keys-test--sent) ,expected))))))

(defmacro kuro-input-keys-test--deftest-alt-modified-cases ()
  "Define alt-modified send tests."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-input-keys-test--def-alt-modified-case ,case))
               kuro-input-keys-test--alt-modified-cases)))

(defmacro kuro-input-keys-test--def-same-sequence-navigation-case (case)
  "Define one cursor-mode invariant navigation ERT test from CASE."
  (let ((name (nth 0 case))
        (docstring (nth 1 case))
        (fn (nth 2 case))
        (expected (nth 3 case)))
    `(ert-deftest ,name ()
       ,docstring
       (kuro-input-keys-test--dolist-cursor-mode (mode)
         (kuro-input-keys-test--assert-sequence #',fn mode ,expected)))))

(defmacro kuro-input-keys-test--deftest-same-sequence-navigation-cases ()
  "Define cursor-mode invariant navigation tests."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-input-keys-test--def-same-sequence-navigation-case ,case))
               kuro-input-keys-test--same-sequence-navigation-cases)))

(defmacro kuro-input-keys-test--def-kkp-send-case (case)
  "Define one KKP send ERT test from CASE."
  (let ((name (nth 0 case))
        (docstring (nth 1 case))
        (flags (nth 2 case))
        (body (nth 3 case))
        (expected (nth 4 case)))
    `(ert-deftest ,name ()
       ,docstring
       (kuro-input-keys-test--with-kkp ,flags
         ,body
         (should (equal (car kuro-input-keys-test--sent) ,expected))))))

(defmacro kuro-input-keys-test--deftest-kkp-send-cases ()
  "Define KKP send behavior tests from `kuro-input-keys-test--kkp-send-cases'."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-input-keys-test--def-kkp-send-case ,case))
               kuro-input-keys-test--kkp-send-cases)))

(defmacro kuro-input-keys-test--def-encode-kitty-key-case (case)
  "Define one `kuro--encode-kitty-key' ERT test from CASE."
  (let ((name (nth 0 case))
        (docstring (nth 1 case))
        (key (nth 2 case))
        (modifier (nth 3 case))
        (expected (nth 4 case)))
    `(ert-deftest ,name ()
       ,docstring
       (should (equal (kuro--encode-kitty-key ,key ,modifier) ,expected)))))

(defmacro kuro-input-keys-test--deftest-encode-kitty-key-cases ()
  "Define encode-kitty-key tests from `kuro-input-keys-test--encode-kitty-key-cases'."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-input-keys-test--def-encode-kitty-key-case ,case))
               kuro-input-keys-test--encode-kitty-key-cases)))

(defmacro kuro-input-keys-test--def-kkp-flag-p-case (case)
  "Define one `kuro--kkp-flag-p' ERT test from CASE."
  (let ((name (nth 0 case))
        (docstring (nth 1 case))
        (flags (nth 2 case))
        (flag (nth 3 case))
        (expected (nth 4 case)))
    `(ert-deftest ,name ()
       ,docstring
       (let ((kuro--keyboard-flags ,flags))
         (if ,expected
             (should (kuro--kkp-flag-p ,flag))
           (should-not (kuro--kkp-flag-p ,flag)))))))

(defmacro kuro-input-keys-test--deftest-kkp-flag-p-cases ()
  "Define `kuro--kkp-flag-p' tests from `kuro-input-keys-test--kkp-flag-p-cases'."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-input-keys-test--def-kkp-flag-p-case ,case))
               kuro-input-keys-test--kkp-flag-p-cases)))

(provide 'kuro-input-keys-test-macros)
;;; kuro-input-keys-test-macros.el ends here
