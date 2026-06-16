;;; kuro-input-mode-test-macros.el --- Shared input-mode test macros  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-stubs)
(eval-and-compile (require 'cl-lib))
(require 'kuro-config)
(require 'kuro-ffi)
(require 'kuro-input-keymap)
(require 'kuro-input-mode)
(require 'kuro-input-mode-test-cases)

;; Forward declaration: kuro-mode is defined in kuro.el but we test
;; kuro-input-mode.el in isolation.  Provide a minimal derived mode.
(unless (fboundp 'kuro-mode)
  (define-derived-mode kuro-mode fundamental-mode "Kuro-test"))

(defmacro kuro-input-mode-test--with-buffer (&rest body)
  "Run BODY in a fresh `kuro-mode' buffer with stubs active."
  `(with-temp-buffer
     (kuro-mode)
     ;; Ensure both keymaps are built before each test
     (kuro--build-keymap)
     ;; kuro-mode-map must have kuro--keymap as parent for mode switches to work
     (set-keymap-parent kuro-mode-map kuro--keymap)
     (use-local-map kuro-mode-map)
     ,@body))

(defmacro kuro-input-mode-test--with-edit (&rest body)
  "Run BODY in a kuro-mode buffer with `kuro--line-mode-update-display' stubbed.
Encodes the test invariant: every line-mode mutation ends with a display update,
so the stub is the default environment for all mutation unit tests."
  `(kuro-input-mode-test--with-buffer
    (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
      ,@body)))

(defmacro kuro-input-mode-test--with-line (buf-str point-pos &rest body)
  "Run BODY in line mode with `kuro--line-buffer' = BUF-STR and point at POINT-POS."
  `(kuro-input-mode-test--with-buffer
    (setq kuro--input-mode 'line
          kuro--line-buffer ,buf-str
          kuro--line-point  ,point-pos)
    ,@body))

(defmacro kuro-input-mode-readline-test--def-line-keymap (test-name key-str fn-symbol)
  "Define TEST-NAME asserting KEY-STR is bound to FN-SYMBOL in line mode."
  `(ert-deftest ,test-name ()
     ,(format "Line keymap binds %S to `%s'." key-str fn-symbol)
     (kuro-input-mode-test--with-buffer
      (kuro--build-keymap)
      (kuro--build-line-mode-keymap)
      (should (eq (lookup-key kuro--line-mode-keymap (kbd ,key-str)) #',fn-symbol)))))

(defmacro kuro-input-mode-readline-test--deftest-line-keymaps ()
  "Define line keymap binding tests from shared readline binding data."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (pcase-let ((`(,test-name ,key-str ,fn-symbol) entry))
            `(kuro-input-mode-readline-test--def-line-keymap
              ,test-name ,key-str ,fn-symbol)))
        kuro-input-mode-readline-test--line-keymap-bindings-table)))

(defun kuro-input-mode-test--selected-cases (cases names)
  "Return CASES filtered to NAMES, or all CASES when NAMES is nil."
  (if names
      (cl-remove-if-not (lambda (case) (memq (car case) names)) cases)
    cases))

(defmacro kuro-input-mode-readline-test--def-command-line-case
    (test-name command input point expected-buffer expected-point)
  "Define TEST-NAME asserting COMMAND transforms line state as expected."
  `(ert-deftest ,test-name ()
     ,(format "`%s' transforms %S at point %S." command input point)
     (kuro-input-mode-test--with-edit
      (setq kuro--line-buffer ,input
            kuro--line-point ,point)
      (,command)
      (should (string= kuro--line-buffer ,expected-buffer))
      (should (= kuro--line-point ,expected-point)))))

(defmacro kuro-input-mode-readline-test--deftest-command-line-cases (cases &rest names)
  "Define command line-edit tests from CASES, optionally restricted to NAMES."
  (let ((selected-cases
         (kuro-input-mode-test--selected-cases (symbol-value cases) names)))
    `(progn
       ,@(mapcar
          (lambda (entry)
            (pcase-let ((`(,test-name ,command ,input ,point
                                      ,expected-buffer ,expected-point)
                         entry))
              `(kuro-input-mode-readline-test--def-command-line-case
                ,test-name ,command ,input ,point ,expected-buffer ,expected-point)))
          selected-cases))))

(defmacro kuro-input-mode-edit-test--with-line-edit (name content point &rest body)
  "Open a kuro line-edit buffer for CONTENT with terminal buffer named NAME.
BODY runs with `edit-buf' and `term-buf' bound; cleanup is automatic."
  `(kuro-input-mode-test--with-buffer
     (let ((term-buf (current-buffer)))
       (setq kuro--line-buffer ,content
             kuro--line-point ,point)
       (rename-buffer (concat "*kuro: " ,name "*") t)
       (cl-letf (((symbol-function 'switch-to-buffer) #'ignore)
                 ((symbol-function 'message) #'ignore)
                 ((symbol-function 'kuro--line-clear-overlay) #'ignore))
         (kuro--line-edit-in-buffer)
         (let ((edit-buf (get-buffer (concat "*kuro-line-edit: *kuro: " ,name "**"))))
           (unwind-protect
               (progn ,@body)
             (when (buffer-live-p edit-buf)
               (kill-buffer edit-buf))))))))

(defmacro kuro-input-mode-edit-test--def-line-keymap (test-name key-str fn-symbol)
  "Define TEST-NAME asserting KEY-STR is bound to FN-SYMBOL in line mode."
  `(ert-deftest ,test-name ()
     ,(format "Line keymap binds %S to `%s'." key-str fn-symbol)
     (kuro-input-mode-test--with-buffer
      (kuro--build-keymap)
      (kuro--build-line-mode-keymap)
      (should (eq (lookup-key kuro--line-mode-keymap (kbd ,key-str)) #',fn-symbol)))))

(defmacro kuro-input-mode-edit-test--deftest-line-keymaps ()
  "Define edit-mode line keymap binding tests from shared data."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (pcase-let ((`(,test-name ,key-str ,fn-symbol) entry))
            `(kuro-input-mode-edit-test--def-line-keymap
              ,test-name ,key-str ,fn-symbol)))
        kuro-input-mode-edit-test--line-keymap-bindings-table)))

(defmacro kuro-input-mode-edit-test--def-quoted-insert
    (test-name input point quoted-char expected expected-point)
  "Define TEST-NAME for one `kuro--line-quoted-insert' case."
  `(ert-deftest ,test-name ()
     ,(format "C-q inserts %S at point %S." quoted-char point)
     (kuro-input-mode-test--with-buffer
      (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore)
                ((symbol-function 'read-quoted-char)
                 (lambda (&optional _p) ,quoted-char)))
        (setq kuro--line-buffer ,input)
        (setq kuro--line-point ,point)
        (kuro--line-quoted-insert)
        (should (string= kuro--line-buffer ,expected))
        (should (= kuro--line-point ,expected-point))))))

(defmacro kuro-input-mode-edit-test--deftest-quoted-inserts ()
  "Define quoted-insert tests from shared data."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (pcase-let ((`(,test-name ,input ,point ,quoted-char ,expected ,expected-point) entry))
            `(kuro-input-mode-edit-test--def-quoted-insert
              ,test-name ,input ,point ,quoted-char ,expected ,expected-point)))
        kuro-input-mode-edit-test--quoted-insert-table)))

(defmacro kuro-input-mode-edit-test--def-line-newline
    (test-name input point expected expected-point)
  "Define TEST-NAME for one `kuro--line-newline' case."
  `(ert-deftest ,test-name ()
     ,(format "C-o inserts newline at point %S." point)
     (kuro-input-mode-test--with-edit
       (setq kuro--line-buffer ,input)
       (setq kuro--line-point ,point)
       (kuro--line-newline)
       (should (string= kuro--line-buffer ,expected))
       (should (= kuro--line-point ,expected-point)))))

(defmacro kuro-input-mode-edit-test--deftest-line-newlines ()
  "Define newline insertion tests from shared data."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (pcase-let ((`(,test-name ,input ,point ,expected ,expected-point) entry))
            `(kuro-input-mode-edit-test--def-line-newline
              ,test-name ,input ,point ,expected ,expected-point)))
        kuro-input-mode-edit-test--line-newline-table)))

(defmacro kuro-input-mode-edit-test--def-word-span
    (test-name input point expected-span)
  "Define TEST-NAME for one `kuro--line-word-span-before-point' case."
  `(ert-deftest ,test-name ()
     ,(format "`kuro--line-word-span-before-point' returns %S." expected-span)
     (kuro-input-mode-test--with-line ,input ,point
       (should (equal (kuro--line-word-span-before-point) ',expected-span)))))

(defmacro kuro-input-mode-edit-test--deftest-word-spans ()
  "Define word-span tests from shared data."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (pcase-let ((`(,test-name ,input ,point ,expected-span) entry))
            `(kuro-input-mode-edit-test--def-word-span
              ,test-name ,input ,point ,expected-span)))
        kuro-input-mode-edit-test--word-span-table)))

(defmacro kuro-input-mode-edit-test--def-line-last-word
    (test-name input expected)
  "Define TEST-NAME for one `kuro--line-last-word' case."
  `(ert-deftest ,test-name ()
     ,(format "`kuro--line-last-word' returns %S for %S." expected input)
     (should (equal (kuro--line-last-word ,input) ,expected))))

(defmacro kuro-input-mode-edit-test--deftest-line-last-words ()
  "Define last-word tests from shared data."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (pcase-let ((`(,test-name ,input ,expected) entry))
            `(kuro-input-mode-edit-test--def-line-last-word
              ,test-name ,input ,expected)))
        kuro-input-mode-edit-test--line-last-word-table)))

(defmacro kuro-input-mode-macros-test--def-skip-case
    (test-name fn input point expected)
  "Define TEST-NAME for scanner FN over INPUT from POINT."
  `(ert-deftest ,test-name ()
     ,(format "`%s' returns %S for %S at %S." fn expected input point)
     (should (= (,fn ,input ,point) ,expected))))

(defmacro kuro-input-mode-macros-test--deftest-skip-cases ()
  "Define word-skip scanner tests from shared data."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (pcase-let ((`(,test-name ,fn ,input ,point ,expected) entry))
            `(kuro-input-mode-macros-test--def-skip-case
              ,test-name ,fn ,input ,point ,expected)))
        kuro-input-mode-macros-test--skip-cases)))

(defmacro kuro-input-mode-macros-test--def-word-bounds-forward
    (test-name input point expected-span)
  "Define TEST-NAME for `kuro--line-word-bounds-forward'."
  `(ert-deftest ,test-name ()
     ,(format "`kuro--line-word-bounds-forward' returns %S." expected-span)
     (let ((kuro--line-buffer ,input)
           (kuro--line-point ,point))
       (should (equal (kuro--line-word-bounds-forward) ',expected-span)))))

(defmacro kuro-input-mode-macros-test--deftest-word-bounds-forward ()
  "Define forward word-bound tests from shared data."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (pcase-let ((`(,test-name ,input ,point ,expected-span) entry))
            `(kuro-input-mode-macros-test--def-word-bounds-forward
              ,test-name ,input ,point ,expected-span)))
        kuro-input-mode-macros-test--word-bounds-forward-cases)))

(defmacro kuro-input-mode-macros-test--def-macro-head
    (test-name form expected-head expected-second)
  "Define TEST-NAME asserting FORM expands to EXPECTED-HEAD and EXPECTED-SECOND."
  `(ert-deftest ,test-name ()
     ,(format "%S expands to `%s'." (car form) expected-head)
     (let ((exp (macroexpand-1 ',form)))
       (should (eq (car exp) ',expected-head))
       ,@(when expected-second
           `((should (eq (cadr exp) ',expected-second)))))))

(defmacro kuro-input-mode-macros-test--deftest-macro-heads ()
  "Define macro-head expansion tests from shared data."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (pcase-let ((`(,test-name ,form ,expected-head ,expected-second) entry))
            `(kuro-input-mode-macros-test--def-macro-head
              ,test-name ,form ,expected-head ,expected-second)))
        kuro-input-mode-macros-test--macro-head-cases)))

(defmacro kuro-input-mode-macros-test--def-macro-member
    (test-name form expected-member)
  "Define TEST-NAME asserting EXPECTED-MEMBER is in FORM expansion body."
  `(ert-deftest ,test-name ()
     ,(format "%S expansion contains %S." (car form) expected-member)
     (let ((exp (macroexpand-1 ',form)))
       (should (member ',expected-member (cddr exp))))))

(defmacro kuro-input-mode-macros-test--deftest-macro-members ()
  "Define macro expansion membership tests from shared data."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (pcase-let ((`(,test-name ,form ,expected-member) entry))
            `(kuro-input-mode-macros-test--def-macro-member
              ,test-name ,form ,expected-member)))
        kuro-input-mode-macros-test--macro-member-cases)))

(defmacro kuro-input-mode-macros-test--def-macro-tail
    (test-name form expected-tail)
  "Define TEST-NAME asserting FORM expansion ends with EXPECTED-TAIL."
  `(ert-deftest ,test-name ()
     ,(format "%S expansion ends with %S." (car form) expected-tail)
     (let* ((exp (macroexpand-1 ',form))
            (forms (if (eq (car exp) 'defun) (cddr exp) (cdr exp))))
       (should (equal (car (last forms)) ',expected-tail)))))

(defmacro kuro-input-mode-macros-test--deftest-macro-tails ()
  "Define macro tail tests from shared data."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (pcase-let ((`(,test-name ,form ,expected-tail) entry))
            `(kuro-input-mode-macros-test--def-macro-tail
              ,test-name ,form ,expected-tail)))
        kuro-input-mode-macros-test--macro-tail-cases)))

(defmacro kuro-input-mode-macros-test--def-macro-form-position
    (test-name form accessor expected)
  "Define TEST-NAME asserting ACCESSOR of FORM expansion is EXPECTED."
  `(ert-deftest ,test-name ()
     ,(format "%S expansion %S is %S." (car form) accessor expected)
     (let* ((exp (macroexpand-1 ',form))
            (forms (cdr exp))
            (actual (pcase ',accessor
                      ('car (car forms))
                      ('cadr (cadr exp))
                      ('nth-3 (nth 3 exp)))))
       (should (equal actual ',expected)))))

(defmacro kuro-input-mode-macros-test--deftest-macro-form-positions ()
  "Define positional macro expansion tests from shared data."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (pcase-let ((`(,test-name ,form ,accessor ,expected) entry))
            `(kuro-input-mode-macros-test--def-macro-form-position
              ,test-name ,form ,accessor ,expected)))
        kuro-input-mode-macros-test--macro-form-position-cases)))

(defmacro kuro-input-mode-macros-test--def-interactive-commands
    (test-name &rest commands)
  "Define TEST-NAME asserting COMMANDS are interactive."
  `(ert-deftest ,test-name ()
     ,(format "Generated commands are interactive: %S." commands)
     ,@(mapcar (lambda (cmd) `(should (commandp #',cmd))) commands)))

(defmacro kuro-input-mode-macros-test--deftest-interactive-commands ()
  "Define generated-command interactivity tests from shared data."
  `(progn
     ,@(mapcar
        (lambda (entry)
          `(kuro-input-mode-macros-test--def-interactive-commands ,@entry))
        kuro-input-mode-macros-test--interactive-command-cases)))

(provide 'kuro-input-mode-test-macros)
;;; kuro-input-mode-test-macros.el ends here
