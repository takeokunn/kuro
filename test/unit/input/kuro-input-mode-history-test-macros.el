;;; kuro-input-mode-history-test-macros.el --- History input test macros  -*- lexical-binding: t; -*-

;;; Commentary:

;; Macro generators and shared wrappers for history-related input-mode tests.

;;; Code:

(require 'seq)
(require 'kuro-input-mode-test-support)
(require 'kuro-input-mode-history-test-cases)

(defmacro kuro-history-test--def-complete-history (name docstring buffer history expected)
  "Define one `kuro--line-complete-history' test."
  `(ert-deftest ,name ()
     ,docstring
     (kuro-input-mode-test--with-edit
      (setq kuro--line-buffer ,buffer
            kuro--line-history ',history)
      (let (msg-text)
        (cl-letf (((symbol-function 'message)
                   (lambda (fmt &rest args)
                     (setq msg-text (apply #'format fmt args)))))
          (kuro--line-complete-history))
        (should (equal kuro--line-buffer ,(plist-get expected :buffer)))
        (should (= kuro--line-point ,(plist-get expected :point)))
        ,@(when (plist-member expected :message)
            `((should (string-match-p ,(plist-get expected :message)
                                      (or msg-text "")))))))))

(defmacro kuro-history-test--deftest-complete-history ()
  "Define `kuro--line-complete-history' data-driven tests."
  `(progn
     ,@(mapcar
        (pcase-lambda (`(,name ,docstring ,buffer ,history ,expected))
          `(kuro-history-test--def-complete-history
            ,name ,docstring ,buffer ,history ,expected))
        kuro-history-test--complete-history-cases)))

(defmacro kuro-history2--def-all-completion (name prefix history expected docstring)
  "Define one `kuro--line-all-history-completions' test."
  `(ert-deftest ,name ()
     ,docstring
     (kuro-input-mode-test--with-edit
      (setq kuro--line-history ',history)
      (should (equal (kuro--line-all-history-completions ,prefix)
                     ',expected)))))

(defmacro kuro-history2--deftest-all-completions (&rest names)
  "Define `kuro--line-all-history-completions' tests selected by NAMES."
  (declare (indent 0))
  `(progn
     ,@(mapcar
        (pcase-lambda (`(,name ,prefix ,history ,expected ,docstring))
          `(kuro-history2--def-all-completion
            ,name ,prefix ,history ,expected ,docstring))
        (seq-filter (lambda (case)
                      (or (null names) (memq (car case) names)))
                    kuro-history2--all-completions-cases))))

(defmacro kuro-history2--def-word-span (name buffer point expected docstring)
  "Define one `kuro--line-word-span-before-point' test."
  `(ert-deftest ,name ()
     ,docstring
     (kuro-input-mode-test--with-edit
      (setq kuro--line-buffer ,buffer
            kuro--line-point ,point)
      (should (equal (kuro--line-word-span-before-point)
                     ',expected)))))

(defmacro kuro-history2--deftest-word-spans (&rest names)
  "Define `kuro--line-word-span-before-point' tests selected by NAMES."
  (declare (indent 0))
  `(progn
     ,@(mapcar
        (pcase-lambda (`(,name ,buffer ,point ,expected ,docstring))
          `(kuro-history2--def-word-span
            ,name ,buffer ,point ,expected ,docstring))
        (seq-filter (lambda (case)
                      (or (null names) (memq (car case) names)))
                    kuro-history2--word-span-cases))))

(defmacro kuro-history2--deftest-complete-dispatches ()
  "Define `kuro--line-complete' dispatch tests."
  `(progn
     ,@(mapcar
        (pcase-lambda (`(,name ,docstring ,completion-function ,expected-call))
          `(ert-deftest ,name ()
             ,docstring
             (kuro-input-mode-test--with-edit
              (let ((kuro-line-completion-function
                     ,(when completion-function `#',completion-function))
                    called)
                (cl-letf (((symbol-function 'kuro--line-complete-history-multi)
                           (lambda () (setq called 'kuro--line-complete-history-multi)))
                          ((symbol-function 'kuro--line-complete-word)
                           (lambda () (setq called 'kuro--line-complete-word))))
                  (kuro--line-complete)
                  (should (eq called ',expected-call)))))))
        kuro-history2--complete-dispatch-cases)))

(defmacro kuro-history2--deftest-complete-history-multi ()
  "Define `kuro--line-complete-history-multi' tests."
  `(progn
     ,@(mapcar
        (pcase-lambda (`(,name ,docstring ,history ,buffer ,point ,expected))
          (let (assertions)
            (when (plist-member expected :buffer)
              (push `(should (equal kuro--line-buffer
                                    ,(plist-get expected :buffer)))
                    assertions))
            (when (plist-member expected :message-match)
              (push `(should (string-match-p ,(plist-get expected :message-match)
                                             (or msg "")))
                    assertions))
            `(ert-deftest ,name ()
               ,docstring
               (kuro-input-mode-test--with-edit
                (setq kuro--line-history ',history
                      kuro--line-buffer ,buffer
                      kuro--line-point ,point)
                (let (msg)
                  (cl-letf (((symbol-function 'message)
                             (lambda (fmt &rest args)
                               (setq msg (apply #'format fmt args))))
                            ((symbol-function 'display-completion-list) #'ignore))
                    (kuro--line-complete-history-multi)
                    ,@(nreverse assertions)))))))
        kuro-history2--complete-history-multi-cases)))

(defmacro kuro-history2--deftest-complete-words ()
  "Define `kuro--line-complete-word' tests."
  `(progn
     ,@(mapcar
        (pcase-lambda (`(,name ,docstring ,candidates ,buffer ,point ,expected))
          (let (assertions)
            (when (plist-member expected :buffer)
              (push `(should (equal kuro--line-buffer
                                    ,(plist-get expected :buffer)))
                    assertions))
            (when (plist-member expected :message)
              (push `(should (stringp msg)) assertions))
            (when (plist-member expected :message-match)
              (push `(should (string-match-p ,(plist-get expected :message-match)
                                             (or msg "")))
                    assertions))
            `(ert-deftest ,name ()
               ,docstring
               (kuro-input-mode-test--with-edit
                (let ((kuro-line-completion-function
                       (lambda (_prefix) ',candidates)))
                  (setq kuro--line-buffer ,buffer
                        kuro--line-point ,point)
                  (let (msg)
                    (cl-letf (((symbol-function 'message)
                               (lambda (fmt &rest args)
                                 (setq msg (apply #'format fmt args))))
                              ((symbol-function 'display-completion-list) #'ignore))
                      (kuro--line-complete-word)
                      ,@(nreverse assertions))))))))
        kuro-history2--complete-word-cases)))

(defmacro kuro-history2--deftest-expand-abbrevs ()
  "Define `kuro--line-expand-abbrev' tests."
  `(progn
     ,@(mapcar
        (pcase-lambda (`(,name ,docstring ,abbrevs ,buffer ,point ,expected))
          (let (assertions)
            (when (plist-member expected :buffer)
              (push `(should (equal kuro--line-buffer
                                    ,(plist-get expected :buffer)))
                    assertions))
            (when (plist-member expected :prefix)
              (push `(should (string-prefix-p ,(plist-get expected :prefix)
                                              kuro--line-buffer))
                    assertions))
            (when (plist-member expected :message-match)
              (push `(should (string-match-p ,(plist-get expected :message-match)
                                             (or msg "")))
                    assertions))
            `(ert-deftest ,name ()
               ,docstring
               (kuro-input-mode-test--with-edit
                (let ((kuro-line-abbrev-alist ',abbrevs))
                  (setq kuro--line-buffer ,buffer
                        kuro--line-point ,point)
                  (let (msg)
                    (cl-letf (((symbol-function 'message)
                               (lambda (fmt &rest args)
                                 (setq msg (apply #'format fmt args)))))
                      (kuro--line-expand-abbrev)
                      ,@(nreverse assertions))))))))
        kuro-history2--expand-abbrev-cases)))

(defmacro kuro-history2--deftest-history-searches ()
  "Define non-error `kuro--line-history-search' tests."
  `(progn
     ,@(mapcar
        (pcase-lambda (`(,name ,docstring ,history ,buffer ,selection ,expected))
          (let (assertions)
            (when (plist-member expected :collection)
              (push `(should (equal cr-collection kuro--line-history))
                    assertions))
            (when (plist-member expected :buffer)
              (push `(should (equal kuro--line-buffer
                                    ,(plist-get expected :buffer)))
                    assertions))
            `(ert-deftest ,name ()
               ,docstring
               (kuro-input-mode-test--with-edit
                (setq kuro--line-history ',history
                      kuro--line-buffer ,buffer)
                (let (cr-collection)
                  (cl-letf (((symbol-function 'completing-read)
                             (lambda (_prompt collection &rest _)
                               (setq cr-collection collection)
                               ,(if (eq selection :quit)
                                    `(signal 'quit nil)
                                  selection))))
                    (kuro--line-history-search)
                    ,@(nreverse assertions)))))))
        kuro-history2--history-search-cases)))

(defmacro kuro-history2--deftest-nav-actions (&rest cases)
  "Define navigation action tests selected by CASES.
When CASES is nil, define every case from `kuro-history2--nav-action-cases'."
  (declare (indent 0))
  (let ((selected-cases
         (seq-filter (lambda (case)
                       (or (null cases) (memq (car case) cases)))
                     kuro-history2--nav-action-cases)))
    (cons 'progn
          (mapcar
           (lambda (case)
             (pcase-let ((`(,name ,docstring ,history ,buffer ,idx ,stash ,action ,expected)
                          case))
               (let (assertions)
                 (when (plist-member expected :buffer)
                   (push `(should (equal kuro--line-buffer
                                         ,(plist-get expected :buffer)))
                         assertions))
                 (when (plist-member expected :idx)
                   (push `(should (= kuro--line-history-idx
                                     ,(plist-get expected :idx)))
                         assertions))
                 (when (plist-member expected :stash)
                   (push `(should (equal kuro--line-history-stash
                                         ,(plist-get expected :stash)))
                         assertions))
                 `(ert-deftest ,name ()
                    ,docstring
                    (kuro-input-mode-test--with-edit
                     (setq kuro--line-history ',history
                           kuro--line-buffer ,buffer
                           kuro--line-history-idx ,idx
                           kuro--line-history-stash ,stash)
                     (,action)
                     ,@(nreverse assertions))))))
           selected-cases))))

(defmacro kuro-history2--deftest-history-index-table
    (test-name docstring cases function)
  "Define one table-driven history-index test.
CASES must be a symbol naming a `defconst' whose value is a list of
((IDX HISTORY) . EXPECTED) entries. FUNCTION is the index helper to call."
  `(ert-deftest ,test-name ()
     ,docstring
     ,@(mapcar
        (lambda (case)
          (pcase-let ((`((,idx ,history) . ,expected) case))
            `(kuro-input-mode-test--with-edit
               (setq kuro--line-history ',history
                     kuro--line-history-idx ,idx)
               (should (= (,function) ,expected)))))
        (symbol-value cases))))

(provide 'kuro-input-mode-history-test-macros)

;;; kuro-input-mode-history-test-macros.el ends here
