;;; kuro-input-mode-readline-test-2.el --- kuro-input-mode-readline-test (part 2)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-input-mode-test-support)

;;; Group 26 — kuro--line-undo

(ert-deftest kuro-input-mode-test-undo-stack-initial-empty ()
  "`kuro--line-undo-stack' starts empty in a fresh buffer."
  (kuro-input-mode-test--with-buffer
   (should (null kuro--line-undo-stack))))

(ert-deftest kuro-input-mode-test-undo-after-insert-restores-state ()
  "Undo after inserting a char restores the previous buffer and point."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "hello")
   (setq kuro--line-point 5)
   (setq last-command-event ?!)
   (kuro--line-self-insert)
   (should (string= kuro--line-buffer "hello!"))
   (kuro--line-undo)
   (should (string= kuro--line-buffer "hello"))
   (should (= kuro--line-point 5))))

(ert-deftest kuro-input-mode-test-undo-after-delete-restores-state ()
  "Undo after backspace restores the deleted character."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "hello")
   (setq kuro--line-point 5)
   (kuro--line-delete)
   (should (string= kuro--line-buffer "hell"))
   (kuro--line-undo)
   (should (string= kuro--line-buffer "hello"))
   (should (= kuro--line-point 5))))

(ert-deftest kuro-input-mode-test-undo-after-kill-line-restores-state ()
  "Undo after C-k restores the killed text."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "git status")
   (setq kuro--line-point 4)
   (kuro--line-kill-line)
   (should (string= kuro--line-buffer "git "))
   (kuro--line-undo)
   (should (string= kuro--line-buffer "git status"))
   (should (= kuro--line-point 4))))

(ert-deftest kuro-input-mode-test-undo-multiple-restores-chain ()
  "Multiple undos restore states in reverse order."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "")
   (setq kuro--line-point 0)
   (setq last-command-event ?a)
   (kuro--line-self-insert)         ; buffer="a", point=1
   (setq last-command-event ?b)
   (kuro--line-self-insert)         ; buffer="ab", point=2
   (kuro--line-undo)                ; back to "a", point=1
   (should (string= kuro--line-buffer "a"))
   (should (= kuro--line-point 1))
   (kuro--line-undo)                ; back to "", point=0
   (should (string= kuro--line-buffer ""))
   (should (= kuro--line-point 0))))

(ert-deftest kuro-input-mode-test-undo-noop-on-empty-stack ()
  "Undo with an empty stack shows a message and does not error."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "abc")
   (setq kuro--line-point 3)
   (should (null kuro--line-undo-stack))
   (kuro--line-undo)
   (should (string= kuro--line-buffer "abc"))))

(ert-deftest kuro-input-mode-test-commit-clears-undo-stack ()
  "`kuro--line-commit' resets the undo stack."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "ls")
   (setq kuro--line-point 2)
   (setq kuro--line-undo-stack '(("" . 0)))
   (cl-letf (((symbol-function 'kuro--send-key) #'ignore)
             ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
     (kuro--line-commit)
     (should (null kuro--line-undo-stack)))))

(ert-deftest kuro-input-mode-test-abort-clears-undo-stack ()
  "`kuro--line-abort' resets the undo stack."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-undo-stack '(("partial" . 3)))
   (kuro--line-abort)
   (should (null kuro--line-undo-stack))))

(kuro-input-mode-readline-test--deftest-line-keymaps)

(ert-deftest kuro-input-mode-test-undo-all-keymap-bindings-correct ()
  "Every entry in `kuro-input-mode-readline-test--line-keymap-bindings-table' binds correctly."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   (kuro--build-line-mode-keymap)
   (dolist (entry kuro-input-mode-readline-test--line-keymap-bindings-table)
     (pcase-let ((`(,_name ,key-str ,fn-sym) entry))
       (should (eq (lookup-key kuro--line-mode-keymap (kbd key-str)) fn-sym))))))

;;; Group 27 — kuro--line-history-search

(ert-deftest kuro-input-mode-test-history-search-is-interactive ()
  "`kuro--line-history-search' is an interactive command."
  (should (commandp #'kuro--line-history-search)))

(ert-deftest kuro-input-mode-test-history-search-errors-on-empty-history ()
  "`kuro--line-history-search' signals user-error when history is empty."
  (kuro-input-mode-test--with-buffer
   (let ((kuro--line-history nil))
     (should-error (kuro--line-history-search) :type 'user-error))))

(ert-deftest kuro-input-mode-test-history-search-sets-buffer-from-selection ()
  "Selecting an entry replaces `kuro--line-buffer'."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "")
   (setq kuro--line-point 0)
   (let ((kuro--line-history '("git status" "ls -la")))
     (cl-letf (((symbol-function 'completing-read)
                (lambda (&rest _) "git status"))
               ((symbol-function 'kuro--line-mode-update-display) #'ignore))
       (kuro--line-history-search)
       (should (string= kuro--line-buffer "git status"))))))

(ert-deftest kuro-input-mode-test-history-search-sets-point-to-end ()
  "After selection, `kuro--line-point' is at end of the selected entry."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "")
   (setq kuro--line-point 0)
   (let ((kuro--line-history '("echo hello")))
     (cl-letf (((symbol-function 'completing-read)
                (lambda (&rest _) "echo hello"))
               ((symbol-function 'kuro--line-mode-update-display) #'ignore))
       (kuro--line-history-search)
       (should (= kuro--line-point 10))))))

(ert-deftest kuro-input-mode-test-history-search-quit-does-not-change-buffer ()
  "C-g (quit signal) leaves `kuro--line-buffer' unchanged."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "draft")
   (setq kuro--line-point 5)
   (let ((kuro--line-history '("git status")))
     (cl-letf (((symbol-function 'completing-read)
                (lambda (&rest _) (signal 'quit nil))))
       (kuro--line-history-search)
       (should (string= kuro--line-buffer "draft"))
       (should (= kuro--line-point 5))))))

(ert-deftest kuro-input-mode-test-history-search-pushes-undo ()
  "Successful selection pushes previous state onto `kuro--line-undo-stack'."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "old")
   (setq kuro--line-point 3)
   (setq kuro--line-undo-stack nil)
   (let ((kuro--line-history '("git status")))
     (cl-letf (((symbol-function 'completing-read)
                (lambda (&rest _) "git status"))
               ((symbol-function 'kuro--line-mode-update-display) #'ignore))
       (kuro--line-history-search)
       (should (= (length kuro--line-undo-stack) 1))
       (should (string= (caar kuro--line-undo-stack) "old"))))))

(ert-deftest kuro-input-mode-test-history-search-passes-current-buffer-as-initial ()
  "`kuro--line-buffer' is passed as initial-input to `completing-read'."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "git")
   (setq kuro--line-point 3)
   (let ((kuro--line-history '("git status" "git diff"))
         (captured-initial :unset))
     (cl-letf (((symbol-function 'completing-read)
                (lambda (_prompt _cands _pred _req _hist _def initial)
                  (setq captured-initial initial)
                  "git status"))
               ((symbol-function 'kuro--line-mode-update-display) #'ignore))
       (kuro--line-history-search)
       (should (string= captured-initial "git"))))))

;;; Group 28 — kuro--line-unix-word-rubout (C-w)

(kuro-input-mode-readline-test--deftest-command-line-cases
 kuro-input-mode-readline-test--unix-word-rubout-cases)

;;; Group 29 — word case operations (M-u, M-l, M-c)

(kuro-input-mode-readline-test--deftest-command-line-cases
 kuro-input-mode-readline-test--word-case-cases)

;;; Group 30 — kuro--line-transpose-words (M-t)

(kuro-input-mode-readline-test--deftest-command-line-cases
 kuro-input-mode-readline-test--transpose-word-cases)

;;; Group 32 — kuro--def-line-kill-word macro structural coverage

(ert-deftest kuro-input-mode-test-def-line-kill-word-kill-word-is-interactive ()
  "`kuro--line-kill-word' is an interactive command (macro-generated)."
  (should (commandp #'kuro--line-kill-word)))

(ert-deftest kuro-input-mode-test-def-line-kill-word-backward-kill-word-is-interactive ()
  "`kuro--line-backward-kill-word' is an interactive command (macro-generated)."
  (should (commandp #'kuro--line-backward-kill-word)))

(ert-deftest kuro-input-mode-test-def-line-kill-word-macroexpand-1-is-defun ()
  "`kuro--def-line-kill-word' single-step expands to a `defun' form."
  (let ((exp (macroexpand-1
              '(kuro--def-line-kill-word kuro-test--dummy-kill
                 kuro--line-skip-non-word-fwd kuro--line-skip-word-fwd
                 p bound bound "doc"))))
    (should (eq (car exp) 'defun))
    (should (eq (cadr exp) 'kuro-test--dummy-kill))))

(ert-deftest kuro-input-mode-test-def-line-kill-word-expansion-contains-interactive ()
  "`kuro--def-line-kill-word' expansion contains (interactive) form."
  (let ((exp (macroexpand-1
              '(kuro--def-line-kill-word kuro-test--dummy-kill2
                 kuro--line-skip-non-word-fwd kuro--line-skip-word-fwd
                 p bound bound "doc"))))
    (should (member '(interactive) (cddr exp)))))

;;; Group 33 — kuro--line-kill-to-bol and kuro--line-kill-line edge cases

(kuro-input-mode-readline-test--deftest-command-line-cases
 kuro-input-mode-readline-test--line-kill-cases)

(provide 'kuro-input-mode-readline-test-2)

;;; kuro-input-mode-readline-test-2.el ends here
