;;; kuro-input-mode-test-2.el --- kuro-input-mode-test (part 2)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-input-mode-test-support)

;;; Group 7 — Mode switching commands

(defmacro kuro-input-mode-test--def-mode-clears-buffer (test-name mode-fn)
  "Define a test that MODE-FN clears `kuro--line-buffer' on entry."
  `(ert-deftest ,test-name ()
     ,(format "`%s' clears any accumulated line buffer on entry." mode-fn)
     (kuro-input-mode-test--with-buffer
      (setq kuro--line-buffer "leftover")
      (,mode-fn)
      (should (string= kuro--line-buffer "")))))



(ert-deftest kuro-input-mode-test-kuro-char-mode-sets-mode ()
  "`kuro-char-mode' sets `kuro--input-mode' to `char'."
  (kuro-input-mode-test--with-buffer
   (kuro-char-mode)
   (should (eq kuro--input-mode 'char))))

(ert-deftest kuro-input-mode-test-kuro-semi-char-mode-sets-mode ()
  "`kuro-semi-char-mode' sets `kuro--input-mode' to `semi-char'."
  (kuro-input-mode-test--with-buffer
   (kuro-char-mode)
   (kuro-semi-char-mode)
   (should (eq kuro--input-mode 'semi-char))))

(ert-deftest kuro-input-mode-test-kuro-line-mode-sets-mode ()
  "`kuro-line-mode' sets `kuro--input-mode' to `line'."
  (kuro-input-mode-test--with-buffer
   (kuro-line-mode)
   (should (eq kuro--input-mode 'line))))

(kuro-input-mode-test--def-mode-clears-buffer kuro-input-mode-test-kuro-char-mode-clears-line-buffer      kuro-char-mode)
(kuro-input-mode-test--def-mode-clears-buffer kuro-input-mode-test-kuro-semi-char-mode-clears-line-buffer kuro-semi-char-mode)
(kuro-input-mode-test--def-mode-clears-buffer kuro-input-mode-test-kuro-line-mode-clears-line-buffer      kuro-line-mode)

(eval-and-compile
  (defconst kuro-input-mode-test--fails-outside-kuro-table
    '((kuro-input-mode-test-kuro-char-mode-fails-outside-kuro      kuro-char-mode)
      (kuro-input-mode-test-kuro-line-mode-fails-outside-kuro      kuro-line-mode)
      (kuro-input-mode-test-kuro-semi-char-mode-fails-outside-kuro kuro-semi-char-mode))
    "Table of (test-name mode-fn): mode functions that must signal user-error outside kuro-mode."))

(defmacro kuro-input-mode-test--def-fails-outside-kuro (test-name mode-fn)
  `(ert-deftest ,test-name ()
     ,(format "`%s' signals `user-error' when called outside a kuro-mode buffer." mode-fn)
     (with-temp-buffer
       (should-error (,mode-fn) :type 'user-error))))

(defmacro kuro-input-mode-test--deftest-fails-outside-kuro ()
  "Define tests that verify mode commands fail outside kuro-mode."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (pcase-let ((`(,test-name ,mode-fn) entry))
            `(kuro-input-mode-test--def-fails-outside-kuro
              ,test-name ,mode-fn)))
        kuro-input-mode-test--fails-outside-kuro-table)))

(kuro-input-mode-test--deftest-fails-outside-kuro)


;;; Group 8 — kuro-cycle-input-mode

(eval-and-compile
  (defconst kuro-input-mode-test--cycle-table
    '((kuro-input-mode-test-cycle-semi-char-to-char semi-char char)
      (kuro-input-mode-test-cycle-char-to-line       char      line)
      (kuro-input-mode-test-cycle-line-to-semi-char  line      semi-char))
    "Table of (test-name initial-mode next-mode) for `kuro-cycle-input-mode' ring transitions."))

(defmacro kuro-input-mode-test--def-cycle (test-name initial-mode next-mode)
  `(ert-deftest ,test-name ()
     ,(format "`kuro-cycle-input-mode' transitions %s → %s." initial-mode next-mode)
     (kuro-input-mode-test--with-buffer
       (setq kuro--input-mode ',initial-mode)
       (kuro-cycle-input-mode)
       (should (eq kuro--input-mode ',next-mode)))))

(defmacro kuro-input-mode-test--deftest-cycle ()
  "Define transition tests for `kuro-cycle-input-mode'."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (pcase-let ((`(,test-name ,initial-mode ,next-mode) entry))
            `(kuro-input-mode-test--def-cycle
              ,test-name ,initial-mode ,next-mode)))
        kuro-input-mode-test--cycle-table)))

(kuro-input-mode-test--deftest-cycle)

(ert-deftest kuro-input-mode-test-cycle-full-round-trip ()
  "Three full cycles returns to the original mode."
  (kuro-input-mode-test--with-buffer
   (should (eq kuro--input-mode 'semi-char))
   (kuro-cycle-input-mode)  ; → char
   (kuro-cycle-input-mode)  ; → line
   (kuro-cycle-input-mode)  ; → semi-char
   (should (eq kuro--input-mode 'semi-char))))

(ert-deftest kuro-input-mode-test-cycle-fails-outside-kuro ()
  "`kuro-cycle-input-mode' signals `user-error' outside a kuro-mode buffer."
  (with-temp-buffer
   (should-error (kuro-cycle-input-mode) :type 'user-error)))


;;; Group 9 — Line mode keymap shape

(eval-and-compile
  (defconst kuro-input-mode-test--line-keymap-bindings
    '((kuro-input-mode-test-line-keymap-binds-commit          [return]                    kuro--line-commit)
      (kuro-input-mode-test-line-keymap-binds-delete          [backspace]                 kuro--line-delete)
      (kuro-input-mode-test-line-keymap-binds-abort           (kbd "C-g")                 kuro--line-abort)
      (kuro-input-mode-test-line-keymap-binds-kill-line       (kbd "C-k")                 kuro--line-kill-line)
      (kuro-input-mode-test-line-keymap-remaps-self-insert    [remap self-insert-command] kuro--line-self-insert)
      (kuro-input-mode-test-line-keymap-binds-minibuffer-send (kbd "C-c C-r")             kuro-line-minibuffer-send))
    "Table of (test-name key fn) for `kuro--line-mode-keymap' binding assertions."))

(defmacro kuro-input-mode-test--def-line-keymap-binding (test-name key fn)
  "Define a test asserting `kuro--line-mode-keymap' binds KEY to FN."
  `(ert-deftest ,test-name ()
     ,(format "`kuro--line-mode-keymap' binds %S to `%s'." key fn)
     (kuro-input-mode-test--with-buffer
      (kuro--build-keymap)
      (kuro--build-line-mode-keymap)
      (should (eq (lookup-key kuro--line-mode-keymap ,key) #',fn)))))

(defmacro kuro-input-mode-test--deftest-line-keymap-bindings ()
  "Define all line keymap binding tests."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (pcase-let ((`(,test-name ,key ,fn) entry))
            `(kuro-input-mode-test--def-line-keymap-binding
              ,test-name ,key ,fn)))
        kuro-input-mode-test--line-keymap-bindings)))

(kuro-input-mode-test--deftest-line-keymap-bindings)


;;; Group 10 — Minibuffer path (IME support)

(ert-deftest kuro-input-mode-test-minibuffer-send-sends-text-plus-cr ()
  "`kuro-line-minibuffer-send' sends the minibuffer result followed by CR."
  (kuro-input-mode-test--with-buffer
   (let ((sent nil))
     (cl-letf (((symbol-function 'read-from-minibuffer)
                (lambda (&rest _) "ls -la"))
               ((symbol-function 'kuro--send-key)
                (lambda (s) (setq sent s)))
               ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
       (kuro-line-minibuffer-send)
       (should (string= sent "ls -la\r"))))))

(ert-deftest kuro-input-mode-test-minibuffer-send-clears-buffer ()
  "`kuro-line-minibuffer-send' clears `kuro--line-buffer' after sending."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-buffer "partial")
   (cl-letf (((symbol-function 'read-from-minibuffer)
              (lambda (&rest _) "done"))
             ((symbol-function 'kuro--send-key)    #'ignore)
             ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
     (kuro-line-minibuffer-send)
     (should (string= kuro--line-buffer "")))))

(ert-deftest kuro-input-mode-test-minibuffer-send-passes-history-arg ()
  "`kuro-line-minibuffer-send' passes `kuro--line-history' to `read-from-minibuffer'."
  (kuro-input-mode-test--with-buffer
   (let ((hist-arg :unset))
     (cl-letf (((symbol-function 'read-from-minibuffer)
                (lambda (_prompt _init _map _read hist &rest _)
                  (setq hist-arg hist)
                  ""))
               ((symbol-function 'kuro--send-key)    #'ignore)
               ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
       (kuro-line-minibuffer-send)
       (should (eq hist-arg 'kuro--line-history))))))

(ert-deftest kuro-input-mode-test-minibuffer-send-quit-does-not-send ()
  "C-g in minibuffer (quit signal) does not send anything to PTY."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-buffer "partial")
   (let ((sent nil))
     (cl-letf (((symbol-function 'read-from-minibuffer)
                (lambda (&rest _) (signal 'quit nil)))
               ((symbol-function 'kuro--send-key)
                (lambda (s) (setq sent s)))
               ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
       (kuro-line-minibuffer-send)
       (should (null sent))
       (should (string= kuro--line-buffer ""))))))

(ert-deftest kuro-input-mode-test-minibuffer-send-fails-outside-kuro ()
  "`kuro-line-minibuffer-send' signals `user-error' outside a kuro buffer."
  (with-temp-buffer
   (should-error (kuro-line-minibuffer-send) :type 'user-error)))

(ert-deftest kuro-input-mode-test-use-minibuffer-nil-accumulates-overlay ()
  "With `kuro-line-use-minibuffer' nil, `kuro--line-self-insert' appends to buffer."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (let ((kuro-line-use-minibuffer nil))
     (setq last-command-event ?a)
     (kuro--line-self-insert)
     (should (string= kuro--line-buffer "a")))))

(ert-deftest kuro-input-mode-test-use-minibuffer-t-delegates-to-minibuffer ()
  "With `kuro-line-use-minibuffer' t, `kuro--line-self-insert' delegates to minibuffer send."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (let ((kuro-line-use-minibuffer t)
         (called nil))
     (cl-letf (((symbol-function 'kuro-line-minibuffer-send)
                (lambda () (setq called t))))
       (setq last-command-event ?a)
       (kuro--line-self-insert)
       (should called)))))

(provide 'kuro-input-mode-test-2)

;;; kuro-input-mode-test-2.el ends here
