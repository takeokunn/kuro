;;; kuro-input-mode-edit-test-2.el --- kuro-input-mode-edit-test (part 2)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-input-mode-test-support)

;;; Group 36 — kuro--line-yank-last-arg (M-., M-_)

(ert-deftest kuro-input-mode-test-yank-last-arg-inserts-last-word ()
  "First M-. inserts the last whitespace-delimited word of the most recent history entry."
  (kuro-input-mode-test--with-buffer
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
     (setq kuro--line-history '("git commit -m msg"))
     (setq kuro--line-buffer "")
     (setq kuro--line-point 0)
     (kuro--line-yank-last-arg)
     (should (string= kuro--line-buffer "msg"))
     (should (= kuro--line-point 3)))))

(ert-deftest kuro-input-mode-test-yank-last-arg-inserts-at-point ()
  "M-. inserts at the current cursor position, not always at end."
  (kuro-input-mode-test--with-buffer
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
     (setq kuro--line-history '("echo hello"))
     (setq kuro--line-buffer "echo ")
     (setq kuro--line-point 5)
     (kuro--line-yank-last-arg)
     (should (string= kuro--line-buffer "echo hello"))
     (should (= kuro--line-point 10)))))

(ert-deftest kuro-input-mode-test-yank-last-arg-cycles-to-older-entry ()
  "Repeated M-. cycles to the last word of progressively older history entries."
  (kuro-input-mode-test--with-buffer
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
     (setq kuro--line-history '("git push origin" "git pull upstream" "make test"))
     (setq kuro--line-buffer "")
     (setq kuro--line-point 0)
     (kuro--line-yank-last-arg)
     (should (string= kuro--line-buffer "origin"))
     (setq last-command 'kuro--line-yank-last-arg)
     (kuro--line-yank-last-arg)
     (should (string= kuro--line-buffer "upstream"))
     (setq last-command 'kuro--line-yank-last-arg)
     (kuro--line-yank-last-arg)
     (should (string= kuro--line-buffer "test")))))

(ert-deftest kuro-input-mode-test-yank-last-arg-stops-at-oldest ()
  "M-. does not error when cycling past the oldest history entry; stays at oldest."
  (kuro-input-mode-test--with-buffer
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
     (setq kuro--line-history '("ls -la" "pwd"))
     (setq kuro--line-buffer "")
     (setq kuro--line-point 0)
     (kuro--line-yank-last-arg)            ; idx=0 → "la"
     (setq last-command 'kuro--line-yank-last-arg)
     (kuro--line-yank-last-arg)            ; idx=1 → "pwd"
     (setq last-command 'kuro--line-yank-last-arg)
     (kuro--line-yank-last-arg)            ; idx capped at 1 → "pwd" again
     (should (string= kuro--line-buffer "pwd"))
     (should (= kuro--line-yank-last-arg-idx 1)))))

(ert-deftest kuro-input-mode-test-yank-last-arg-resets-on-other-command ()
  "A non-M-. command between two M-. presses restarts cycling from the top."
  (kuro-input-mode-test--with-buffer
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
     (setq kuro--line-history '("git push" "git pull"))
     (setq kuro--line-buffer "")
     (setq kuro--line-point 0)
     (kuro--line-yank-last-arg)            ; idx=0 → "push"
     (setq last-command 'kuro--line-self-insert)
     (setq kuro--line-buffer "")
     (setq kuro--line-point 0)
     (kuro--line-yank-last-arg)            ; should restart at idx=0 → "push"
     (should (string= kuro--line-buffer "push"))
     (should (= kuro--line-yank-last-arg-idx 0)))))

(ert-deftest kuro-input-mode-test-yank-last-arg-empty-history-errors ()
  "`kuro--line-yank-last-arg' signals user-error when history is empty."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-history nil)
   (should-error (kuro--line-yank-last-arg) :type 'user-error)))

(ert-deftest kuro-input-mode-test-yank-last-arg-pushes-undo ()
  "M-. pushes to `kuro--line-undo-stack' before modifying the buffer."
  (kuro-input-mode-test--with-buffer
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
     (setq kuro--line-history '("rm -rf /tmp/foo"))
     (setq kuro--line-buffer "cd ")
     (setq kuro--line-point 3)
     (kuro--line-yank-last-arg)
     (should (= (length kuro--line-undo-stack) 1))
     (should (equal (car kuro--line-undo-stack) '("cd " . 3))))))

(ert-deftest kuro-input-mode-test-yank-last-arg-keymap-bindings ()
  "Line keymap binds both M-. and M-_ to `kuro--line-yank-last-arg'."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   (kuro--build-line-mode-keymap)
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "M-."))
               #'kuro--line-yank-last-arg))
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "M-_"))
               #'kuro--line-yank-last-arg))))

;;; Group 37 — kuro--line-quoted-insert (C-q)

(ert-deftest kuro-input-mode-test-quoted-insert-inserts-literal-tab ()
  "C-q inserts a literal TAB read via `read-quoted-char' at point."
  (kuro-input-mode-test--with-buffer
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore)
             ((symbol-function 'read-quoted-char) (lambda (&optional _p) ?\t)))
     (setq kuro--line-buffer "ab")
     (setq kuro--line-point 2)
     (kuro--line-quoted-insert)
     (should (string= kuro--line-buffer "ab\t"))
     (should (= kuro--line-point 3)))))

(ert-deftest kuro-input-mode-test-quoted-insert-at-point ()
  "C-q inserts the literal char at the cursor position, not the end."
  (kuro-input-mode-test--with-buffer
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore)
             ((symbol-function 'read-quoted-char) (lambda (&optional _p) ?X)))
     (setq kuro--line-buffer "ac")
     (setq kuro--line-point 1)
     (kuro--line-quoted-insert)
     (should (string= kuro--line-buffer "aXc"))
     (should (= kuro--line-point 2)))))

(ert-deftest kuro-input-mode-test-quoted-insert-control-char ()
  "C-q can embed a raw control character (e.g. ESC) into the line buffer."
  (kuro-input-mode-test--with-buffer
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore)
             ((symbol-function 'read-quoted-char) (lambda (&optional _p) ?\e)))
     (setq kuro--line-buffer "")
     (setq kuro--line-point 0)
     (kuro--line-quoted-insert)
     (should (string= kuro--line-buffer "\e"))
     (should (= kuro--line-point 1)))))

(ert-deftest kuro-input-mode-test-quoted-insert-pushes-undo ()
  "C-q pushes the pre-insert state onto the line undo stack."
  (kuro-input-mode-test--with-buffer
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore)
             ((symbol-function 'read-quoted-char) (lambda (&optional _p) ?z)))
     (setq kuro--line-buffer "q")
     (setq kuro--line-point 1)
     (setq kuro--line-undo-stack nil)
     (kuro--line-quoted-insert)
     (should (= (length kuro--line-undo-stack) 1))
     (should (equal (car kuro--line-undo-stack) '("q" . 1))))))

(ert-deftest kuro-input-mode-test-quoted-insert-keymap-binding ()
  "Line keymap binds C-q to `kuro--line-quoted-insert'."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   (kuro--build-line-mode-keymap)
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "C-q"))
               #'kuro--line-quoted-insert))))

;;; Group 38 — kuro--line-newline (C-o) multi-line composition

(ert-deftest kuro-input-mode-test-line-newline-inserts-at-point ()
  "C-o inserts a literal newline at point and advances point past it."
  (kuro-input-mode-test--with-buffer
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
     (setq kuro--line-buffer "for i in 1 2 3")
     (setq kuro--line-point 14)
     (kuro--line-newline)
     (should (string= kuro--line-buffer "for i in 1 2 3\n"))
     (should (= kuro--line-point 15)))))

(ert-deftest kuro-input-mode-test-line-newline-mid-buffer ()
  "C-o inserts the newline at the cursor, splitting the buffer."
  (kuro-input-mode-test--with-buffer
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
     (setq kuro--line-buffer "aceg")
     (setq kuro--line-point 2)
     (kuro--line-newline)
     (should (string= kuro--line-buffer "ac\neg"))
     (should (= kuro--line-point 3)))))

(ert-deftest kuro-input-mode-test-line-newline-pushes-undo ()
  "C-o pushes the pre-insert state onto the undo stack."
  (kuro-input-mode-test--with-buffer
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
     (setq kuro--line-buffer "x")
     (setq kuro--line-point 1)
     (setq kuro--line-undo-stack nil)
     (kuro--line-newline)
     (should (= (length kuro--line-undo-stack) 1))
     (should (equal (car kuro--line-undo-stack) '("x" . 1))))))

(ert-deftest kuro-input-mode-test-line-newline-then-commit-sends-multiline ()
  "A composed multi-line buffer is sent verbatim plus a trailing CR on commit."
  (kuro-input-mode-test--with-buffer
   (let ((sent nil))
     (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore)
               ((symbol-function 'kuro--send-key) (lambda (s) (setq sent s)))
               ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
       (setq kuro--line-buffer "echo a")
       (setq kuro--line-point 6)
       (kuro--line-newline)
       (setq kuro--line-buffer (concat kuro--line-buffer "echo b"))
       (setq kuro--line-point (length kuro--line-buffer))
       (kuro--line-commit)
       (should (string= sent "echo a\necho b\r"))))))

(ert-deftest kuro-input-mode-test-line-newline-keymap-binding ()
  "Line keymap binds C-o to `kuro--line-newline'."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   (kuro--build-line-mode-keymap)
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "C-o"))
               #'kuro--line-newline))))

(ert-deftest kuro-input-mode-test-line-cj-commits ()
  "Line keymap binds C-j to `kuro--line-commit' (readline accept-line parity)."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   (kuro--build-line-mode-keymap)
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "C-j"))
               #'kuro--line-commit))))

;;; Group 39 — kuro--line-word-span-before-point + kuro--line-load-history-entry

(ert-deftest kuro-input-mode-test-word-span-empty-buffer ()
  "`kuro--line-word-span-before-point' returns (0 . 0) when buffer is empty."
  (kuro-input-mode-test--with-line "" 0
    (should (equal (kuro--line-word-span-before-point) '(0 . 0)))))

(ert-deftest kuro-input-mode-test-word-span-at-end-of-word ()
  "`kuro--line-word-span-before-point' returns span of the word ending at point."
  (kuro-input-mode-test--with-line "git status" 3
    (should (equal (kuro--line-word-span-before-point) '(0 . 3)))))

(ert-deftest kuro-input-mode-test-word-span-second-word ()
  "`kuro--line-word-span-before-point' returns span of the last token when preceded by space."
  (kuro-input-mode-test--with-line "git status" 10
    (should (equal (kuro--line-word-span-before-point) '(4 . 10)))))

(ert-deftest kuro-input-mode-test-word-span-point-after-space ()
  "`kuro--line-word-span-before-point' returns (N . N) when point is at a space."
  (kuro-input-mode-test--with-line "git status" 4
    (let ((span (kuro--line-word-span-before-point)))
      (should (= (car span) (cdr span))))))

(ert-deftest kuro-input-mode-test-word-span-at-point-zero ()
  "`kuro--line-word-span-before-point' returns (0 . 0) when point is at BOL."
  (kuro-input-mode-test--with-line "hello" 0
    (should (equal (kuro--line-word-span-before-point) '(0 . 0)))))

(ert-deftest kuro-input-mode-test-load-history-entry-sets-buffer ()
  "`kuro--line-load-history-entry' loads the Nth history entry into `kuro--line-buffer'."
  (kuro-input-mode-test--with-buffer
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
     (setq kuro--line-history '("ls -la" "git status" "echo hello"))
     (kuro--line-load-history-entry 1)
     (should (string= kuro--line-buffer "git status")))))

(ert-deftest kuro-input-mode-test-load-history-entry-sets-point-at-end ()
  "`kuro--line-load-history-entry' sets `kuro--line-point' to the end of the loaded entry."
  (kuro-input-mode-test--with-buffer
   (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
     (setq kuro--line-history '("ls -la" "echo hi"))
     (kuro--line-load-history-entry 0)
     (should (= kuro--line-point (length "ls -la"))))))

(ert-deftest kuro-input-mode-test-load-history-entry-calls-display-update ()
  "`kuro--line-load-history-entry' calls `kuro--line-mode-update-display'."
  (kuro-input-mode-test--with-buffer
   (let ((called nil))
     (cl-letf (((symbol-function 'kuro--line-mode-update-display)
                (lambda () (setq called t))))
       (setq kuro--line-history '("test"))
       (kuro--line-load-history-entry 0)
       (should called)))))

(provide 'kuro-input-mode-edit-test-2)

;;; kuro-input-mode-edit-test-2.el ends here
