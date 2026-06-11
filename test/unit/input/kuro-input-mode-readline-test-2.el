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

(ert-deftest kuro-input-mode-test-undo-keymap-bindings ()
  "Line keymap binds C-/ and C-_ to `kuro--line-undo'."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   (kuro--build-line-mode-keymap)
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "C-/")) #'kuro--line-undo))
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "C-_")) #'kuro--line-undo))))

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

(ert-deftest kuro-input-mode-test-history-search-bound-in-line-keymap ()
  "Line keymap binds C-r to `kuro--line-history-search'."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   (kuro--build-line-mode-keymap)
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "C-r"))
               #'kuro--line-history-search))))

;;; Group 28 — kuro--line-unix-word-rubout (C-w)

(ert-deftest kuro-input-mode-test-unix-word-rubout-kills-to-whitespace ()
  "C-w kills backward to the nearest space, treating hyphens as word chars."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-buffer "git commit-amend")
   (setq kuro--line-point 16)
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
     (kuro--line-unix-word-rubout)
     (should (string= kuro--line-buffer "git "))
     (should (= kuro--line-point 4)))))

(ert-deftest kuro-input-mode-test-unix-word-rubout-skips-trailing-spaces ()
  "C-w skips whitespace before the token to kill."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-buffer "foo   ")
   (setq kuro--line-point 6)
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
     (kuro--line-unix-word-rubout)
     (should (string= kuro--line-buffer ""))
     (should (= kuro--line-point 0)))))

(ert-deftest kuro-input-mode-test-unix-word-rubout-at-bol-is-noop ()
  "C-w at beginning of line leaves the buffer unchanged."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-buffer "hello")
   (setq kuro--line-point 0)
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
     (kuro--line-unix-word-rubout)
     (should (string= kuro--line-buffer "hello"))
     (should (= kuro--line-point 0)))))

(ert-deftest kuro-input-mode-test-unix-word-rubout-keeps-text-after-point ()
  "C-w does not disturb text after point."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-buffer "rm -rf /tmp/foo bar")
   (setq kuro--line-point 15)
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
     (kuro--line-unix-word-rubout)
     (should (string= kuro--line-buffer "rm -rf  bar"))
     (should (= kuro--line-point 7)))))

;;; Group 29 — word case operations (M-u, M-l, M-c)

(ert-deftest kuro-input-mode-test-upcase-word-from-point ()
  "M-u upcases the next word and advances point to word end."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-buffer "hello world")
   (setq kuro--line-point 6)
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
     (kuro--line-upcase-word)
     (should (string= kuro--line-buffer "hello WORLD"))
     (should (= kuro--line-point 11)))))

(ert-deftest kuro-input-mode-test-downcase-word-from-point ()
  "M-l downcases the next word and advances point to word end."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-buffer "HELLO WORLD")
   (setq kuro--line-point 6)
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
     (kuro--line-downcase-word)
     (should (string= kuro--line-buffer "HELLO world"))
     (should (= kuro--line-point 11)))))

(ert-deftest kuro-input-mode-test-capitalize-word-from-point ()
  "M-c capitalizes the next word: first char upper, rest lower."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-buffer "HELLO wOrLd")
   (setq kuro--line-point 6)
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
     (kuro--line-capitalize-word)
     (should (string= kuro--line-buffer "HELLO World"))
     (should (= kuro--line-point 11)))))

(ert-deftest kuro-input-mode-test-upcase-word-skips-leading-punct ()
  "M-u skips non-word chars before the word."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-buffer "  hello")
   (setq kuro--line-point 0)
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
     (kuro--line-upcase-word)
     (should (string= kuro--line-buffer "  HELLO"))
     (should (= kuro--line-point 7)))))

(ert-deftest kuro-input-mode-test-word-case-at-eol-is-noop ()
  "Case commands at EOL where no word follows are no-ops."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-buffer "done")
   (setq kuro--line-point 4)
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
     (kuro--line-upcase-word)
     (should (string= kuro--line-buffer "done"))
     (should (= kuro--line-point 4)))))

;;; Group 30 — kuro--line-transpose-words (M-t)

(ert-deftest kuro-input-mode-test-transpose-words-basic ()
  "M-t swaps word before point with word after point."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-buffer "foo bar baz")
   (setq kuro--line-point 7)
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
     (kuro--line-transpose-words)
     (should (string= kuro--line-buffer "foo baz bar"))
     (should (= kuro--line-point 11)))))

(ert-deftest kuro-input-mode-test-transpose-words-point-in-space ()
  "M-t with point in whitespace between words still transposes them."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-buffer "alpha beta")
   (setq kuro--line-point 5)
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
     (kuro--line-transpose-words)
     (should (string= kuro--line-buffer "beta alpha"))
     (should (= kuro--line-point 10)))))

(ert-deftest kuro-input-mode-test-transpose-words-no-second-word-is-noop ()
  "M-t at end of last word does not modify the buffer."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-buffer "only")
   (setq kuro--line-point 4)
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
     (kuro--line-transpose-words)
     (should (string= kuro--line-buffer "only"))
     (should (= kuro--line-point 4)))))

;;; Group 31 — keymap bindings for iter-28 commands

(ert-deftest kuro-input-mode-test-keymap-binds-c-w-unix-word-rubout ()
  "Line keymap binds C-w to `kuro--line-unix-word-rubout'."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   (kuro--build-line-mode-keymap)
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "C-w"))
               #'kuro--line-unix-word-rubout))))

(ert-deftest kuro-input-mode-test-keymap-binds-word-case-ops ()
  "Line keymap binds M-u/M-l/M-c to word-case commands."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   (kuro--build-line-mode-keymap)
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "M-u"))
               #'kuro--line-upcase-word))
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "M-l"))
               #'kuro--line-downcase-word))
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "M-c"))
               #'kuro--line-capitalize-word))))

(ert-deftest kuro-input-mode-test-keymap-binds-c-p-c-n-history-aliases ()
  "Line keymap binds C-p/C-n as aliases for history prev/next."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   (kuro--build-line-mode-keymap)
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "C-p"))
               #'kuro--line-history-prev))
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "C-n"))
               #'kuro--line-history-next))))

(ert-deftest kuro-input-mode-test-keymap-binds-m-t-transpose-words ()
  "Line keymap binds M-t to `kuro--line-transpose-words'."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   (kuro--build-line-mode-keymap)
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "M-t"))
               #'kuro--line-transpose-words))))

(provide 'kuro-input-mode-readline-test-2)

;;; kuro-input-mode-readline-test-2.el ends here
