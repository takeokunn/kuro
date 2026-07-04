;;; kuro-typewriter-test-macros.el --- Typewriter test macros  -*- lexical-binding: t; -*-

;;; Commentary:
;; Macro and helper logic for expanding typewriter unit tests.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'kuro-input)
(require 'kuro-typewriter)
(require 'kuro-typewriter-test-cases)

(defmacro kuro-typewriter-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer with typewriter state initialized.
`kuro--initialized' is set to t so that `kuro--typewriter-tick' guards pass."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (inhibit-modification-hooks t)
           (kuro--initialized t)
           kuro--typewriter-queue
           kuro--typewriter-timer
           kuro--typewriter-current-row
           kuro--typewriter-current-text
           (kuro--typewriter-written-len 0)
           (kuro--typewriter-current-text-len 0))
       ,@body)))

(defmacro kuro-typewriter-test--with-timer-stub (var &rest body)
  "Run BODY with `run-with-timer' stubbed; VAR captures (DELAY REPEAT FN).
The stub stores the full timer call as a list in VAR and returns the symbol
`fake-timer'."
  (declare (indent 1))
  `(let ((,var nil))
     (cl-letf (((symbol-function 'run-with-timer)
                (lambda (delay repeat fn)
                  (setq ,var (list delay repeat fn))
                  'fake-timer)))
       ,@body)))

(defmacro kuro-typewriter-test--with-key-capture (var &rest body)
  "Run BODY with `kuro--send-key' captured into VAR (most recent first).
`kuro--schedule-immediate-render' is stubbed as a no-op."
  (declare (indent 1))
  `(let ((,var nil))
     (cl-letf (((symbol-function 'kuro--send-key)
                (lambda (data) (push data ,var)))
                 ((symbol-function 'kuro--schedule-immediate-render)
                  (lambda () nil)))
        ,@body)))

(defmacro kuro-typewriter-test--with-write-partial-log (var &rest body)
  "Run BODY while capturing `kuro--typewriter-write-partial' calls in VAR.
VAR receives (ROW . TEXT) cons cells, newest first."
  (declare (indent 1))
  `(let ((,var nil))
     (cl-letf (((symbol-function 'kuro--typewriter-write-partial)
                (lambda (row text)
                  (push (cons row text) ,var))))
       ,@body)))

(defun kuro-typewriter-test--assert-state (row text written-len queue)
  "Assert the current typewriter state matches ROW, TEXT, WRITTEN-LEN, and QUEUE."
  (should (equal kuro--typewriter-current-row row))
  (should (equal kuro--typewriter-current-text text))
  (should (= kuro--typewriter-written-len written-len))
  (should (equal kuro--typewriter-queue queue)))

(defmacro kuro-typewriter-test--tick-sequence (&rest steps)
  "Run a sequence of typewriter ticks.
Each step must be (tick FORM...)."
  (declare (indent 0))
  `(progn
     ,@(mapcar (lambda (step)
                 (unless (and (consp step) (eq (car step) 'tick))
                   (error "Expected (tick ...) step, got %S" step))
                 `(progn
                    (kuro--typewriter-tick)
                    ,@(cdr step)))
               steps)))

(defmacro kuro-typewriter-test--def-tick-partial-write-case (case)
  "Define one partial-write tick test from CASE."
  (declare (indent 0))
  (let ((name (nth 0 case))
        (doc (nth 1 case))
        (buffer (nth 2 case))
        (row (nth 3 case))
        (text (nth 4 case))
        (text-len (nth 5 case))
        (written-len (nth 6 case))
        (expected-written-len (nth 7 case))
        (expected-partial-text (nth 8 case)))
    `(ert-deftest ,name ()
       ,doc
       (kuro-typewriter-test--with-buffer
         (insert ,buffer)
         (setq kuro--typewriter-current-row ,row
               kuro--typewriter-current-text ,text
               kuro--typewriter-current-text-len ,text-len
               kuro--typewriter-written-len ,written-len)
         (let ((write-calls nil))
           (cl-letf (((symbol-function 'kuro--typewriter-write-partial)
                      (lambda (write-row write-text)
                        (push (cons write-row write-text) write-calls))))
             (kuro--typewriter-tick)
             (should (= kuro--typewriter-written-len ,expected-written-len))
             (should (= (length write-calls) 1))
             (should (equal (car write-calls)
                            (cons ,row ,expected-partial-text)))))))))

(defmacro kuro-typewriter-test--deftest-tick-partial-write-cases ()
  "Define partial-write tick tests from `kuro-typewriter-test--tick-partial-write-cases'."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-typewriter-test--def-tick-partial-write-case ,case))
               kuro-typewriter-test--tick-partial-write-cases)))

(defmacro kuro-typewriter-test--def-tick-no-write-state-case (case)
  "Define one no-write tick state test from CASE."
  (declare (indent 0))
  (let ((name (nth 0 case))
        (doc (nth 1 case))
        (initialized (nth 2 case))
        (row (nth 3 case))
        (text (nth 4 case))
        (written-len (nth 5 case))
        (queue (nth 6 case))
        (expected-row (nth 7 case))
        (expected-text (nth 8 case))
        (expected-written-len (nth 9 case)))
    `(ert-deftest ,name ()
       ,doc
       (kuro-typewriter-test--with-buffer
         (setq kuro--initialized ,initialized
               kuro--typewriter-current-row ,row
               kuro--typewriter-current-text ,text
               kuro--typewriter-written-len ,written-len
               kuro--typewriter-queue ,queue)
         (cl-letf (((symbol-function 'kuro--typewriter-write-partial)
                    (lambda (_row _text)
                      (error "write-partial must not be called"))))
           (kuro--typewriter-tick)
           (should (equal kuro--typewriter-current-row ,expected-row))
           (should (equal kuro--typewriter-current-text ,expected-text))
           (should (= kuro--typewriter-written-len ,expected-written-len)))))))

(defmacro kuro-typewriter-test--deftest-tick-no-write-state-cases ()
  "Define no-write tick tests from `kuro-typewriter-test--tick-no-write-state-cases'."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-typewriter-test--def-tick-no-write-state-case ,case))
               kuro-typewriter-test--tick-no-write-state-cases)))

(defmacro kuro-typewriter-test--def-timer-interval-case (case)
  "Define one typewriter timer interval test from CASE."
  (declare (indent 0))
  (let ((name (nth 0 case))
        (doc (nth 1 case))
        (cps (nth 2 case))
        (expected (nth 3 case)))
    `(ert-deftest ,name ()
       ,doc
       (kuro-typewriter-test--with-buffer
         (let ((kuro-typewriter-effect t)
               (kuro-typewriter-chars-per-second ,cps)
               (captured nil))
           (kuro-typewriter-test--with-timer-stub captured
             (kuro--start-typewriter-timer)
             (should (floatp (nth 0 captured)))
             (should (floatp (nth 1 captured)))
             (should (< (abs (- (nth 0 captured) (nth 1 captured))) 1e-10))
             (should (< (abs (- (nth 0 captured) ,expected)) 1e-10))))))))

(defmacro kuro-typewriter-test--deftest-timer-interval-cases ()
  "Define typewriter timer interval tests from `kuro-typewriter-test--timer-interval-cases'."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-typewriter-test--def-timer-interval-case ,case))
               kuro-typewriter-test--timer-interval-cases)))

(defmacro kuro-typewriter-test--def-default-value-case (case)
  "Define one typewriter default value invariant test from CASE."
  (declare (indent 0))
  (let ((name (nth 0 case))
        (doc (nth 1 case))
        (variable (nth 2 case))
        (checker (nth 3 case)))
    `(ert-deftest ,name ()
       ,doc
       (should (funcall ,checker (default-value ',variable))))))

(defmacro kuro-typewriter-test--deftest-default-value-cases ()
  "Define typewriter default value tests from `kuro-typewriter-test--default-value-cases'."
  `(progn
     ,@(mapcar (lambda (case)
                 `(kuro-typewriter-test--def-default-value-case ,case))
               kuro-typewriter-test--default-value-cases)))

(provide 'kuro-typewriter-test-macros)

;;; kuro-typewriter-test-macros.el ends here
