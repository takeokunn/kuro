;;; kuro-input-mode-edit-test-2.el --- kuro-input-mode-edit-test (part 2)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-input-mode-test-support)

;;; Group 36 — kuro--line-yank-last-arg (M-., M-_)

(ert-deftest kuro-input-mode-test-yank-last-arg-inserts-last-word ()
  "First M-. inserts the last whitespace-delimited word of the most recent history entry."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history '("git commit -m msg"))
    (setq kuro--line-buffer "")
    (setq kuro--line-point 0)
    (kuro--line-yank-last-arg)
    (should (string= kuro--line-buffer "msg"))
    (should (= kuro--line-point 3))))

(ert-deftest kuro-input-mode-test-yank-last-arg-inserts-at-point ()
  "M-. inserts at the current cursor position, not always at end."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history '("echo hello"))
    (setq kuro--line-buffer "echo ")
    (setq kuro--line-point 5)
    (kuro--line-yank-last-arg)
    (should (string= kuro--line-buffer "echo hello"))
    (should (= kuro--line-point 10))))

(ert-deftest kuro-input-mode-test-yank-last-arg-cycles-to-older-entry ()
  "Repeated M-. cycles to the last word of progressively older history entries."
  (kuro-input-mode-test--with-edit
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
    (should (string= kuro--line-buffer "test"))))

(ert-deftest kuro-input-mode-test-yank-last-arg-stops-at-oldest ()
  "M-. does not error when cycling past the oldest history entry; stays at oldest."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history '("ls -la" "pwd"))
    (setq kuro--line-buffer "")
    (setq kuro--line-point 0)
    (kuro--line-yank-last-arg)            ; idx=0 → "la"
    (setq last-command 'kuro--line-yank-last-arg)
    (kuro--line-yank-last-arg)            ; idx=1 → "pwd"
    (setq last-command 'kuro--line-yank-last-arg)
    (kuro--line-yank-last-arg)            ; idx capped at 1 → "pwd" again
    (should (string= kuro--line-buffer "pwd"))
    (should (= kuro--line-yank-last-arg-idx 1))))

(ert-deftest kuro-input-mode-test-yank-last-arg-resets-on-other-command ()
  "A non-M-. command between two M-. presses restarts cycling from the top."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history '("git push" "git pull"))
    (setq kuro--line-buffer "")
    (setq kuro--line-point 0)
    (kuro--line-yank-last-arg)            ; idx=0 → "push"
    (setq last-command 'kuro--line-self-insert)
    (setq kuro--line-buffer "")
    (setq kuro--line-point 0)
    (kuro--line-yank-last-arg)            ; should restart at idx=0 → "push"
    (should (string= kuro--line-buffer "push"))
    (should (= kuro--line-yank-last-arg-idx 0))))

(ert-deftest kuro-input-mode-test-yank-last-arg-empty-history-errors ()
  "`kuro--line-yank-last-arg' signals user-error when history is empty."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-history nil)
   (should-error (kuro--line-yank-last-arg) :type 'user-error)))

(ert-deftest kuro-input-mode-test-yank-last-arg-pushes-undo ()
  "M-. pushes to `kuro--line-undo-stack' before modifying the buffer."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history '("rm -rf /tmp/foo"))
    (setq kuro--line-buffer "cd ")
    (setq kuro--line-point 3)
    (kuro--line-yank-last-arg)
    (should (= (length kuro--line-undo-stack) 1))
    (should (equal (car kuro--line-undo-stack) '("cd " . 3)))))

;;; Group 37 — kuro--line-quoted-insert (C-q)

(kuro-input-mode-edit-test--deftest-quoted-inserts)

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

;;; Group 38 — kuro--line-newline (C-o) multi-line composition

(kuro-input-mode-edit-test--deftest-line-newlines)

(ert-deftest kuro-input-mode-test-line-newline-pushes-undo ()
  "C-o pushes the pre-insert state onto the undo stack."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-buffer "x")
    (setq kuro--line-point 1)
    (setq kuro--line-undo-stack nil)
    (kuro--line-newline)
    (should (= (length kuro--line-undo-stack) 1))
    (should (equal (car kuro--line-undo-stack) '("x" . 1)))))

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

;;; Group 39 — kuro--line-word-span-before-point + kuro--line-load-history-entry

(kuro-input-mode-edit-test--deftest-word-spans)

(ert-deftest kuro-input-mode-test-word-span-point-after-space ()
  "`kuro--line-word-span-before-point' returns (N . N) when point is at a space."
  (kuro-input-mode-test--with-line "git status" 4
    (let ((span (kuro--line-word-span-before-point)))
      (should (= (car span) (cdr span))))))

(ert-deftest kuro-input-mode-test-load-history-entry-sets-buffer ()
  "`kuro--line-load-history-entry' loads the Nth history entry into `kuro--line-buffer'."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history '("ls -la" "git status" "echo hello"))
    (kuro--line-load-history-entry 1)
    (should (string= kuro--line-buffer "git status"))))

(ert-deftest kuro-input-mode-test-load-history-entry-sets-point-at-end ()
  "`kuro--line-load-history-entry' sets `kuro--line-point' to the end of the loaded entry."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history '("ls -la" "echo hi"))
    (kuro--line-load-history-entry 0)
    (should (= kuro--line-point (length "ls -la")))))

(ert-deftest kuro-input-mode-test-load-history-entry-calls-display-update ()
  "`kuro--line-load-history-entry' calls `kuro--line-mode-update-display'."
  (kuro-input-mode-test--with-buffer
   (let ((called nil))
     (cl-letf (((symbol-function 'kuro--line-mode-update-display)
                (lambda () (setq called t))))
       (setq kuro--line-history '("test"))
       (kuro--line-load-history-entry 0)
       (should called)))))

;;; Group 40 — kuro--line-last-word + kuro--line-undo-push

(kuro-input-mode-edit-test--deftest-line-last-words)

(ert-deftest kuro-input-mode-test-line-undo-push-grows-stack ()
  "`kuro--line-undo-push' pushes current (buffer . point) onto the undo stack."
  (kuro-input-mode-test--with-buffer
    (setq kuro--line-buffer "hello" kuro--line-point 3 kuro--line-undo-stack nil)
    (kuro--line-undo-push)
    (should (= (length kuro--line-undo-stack) 1))
    (should (equal (car kuro--line-undo-stack) '("hello" . 3)))))

(ert-deftest kuro-input-mode-test-line-undo-push-caps-at-max-depth ()
  "`kuro--line-undo-push' trims the stack to `kuro--line-undo-max-depth'."
  (kuro-input-mode-test--with-buffer
    (let ((kuro--line-undo-max-depth 2))
      (setq kuro--line-undo-stack nil)
      (setq kuro--line-buffer "a" kuro--line-point 1) (kuro--line-undo-push)
      (setq kuro--line-buffer "b" kuro--line-point 1) (kuro--line-undo-push)
      (setq kuro--line-buffer "c" kuro--line-point 1) (kuro--line-undo-push)
      (should (= (length kuro--line-undo-stack) 2)))))

;;; Group 41 — kuro--line-transpose-chars (C-t)

(ert-deftest kuro-input-mode-test-transpose-chars-mid-string ()
  "`kuro--line-transpose-chars' swaps the char before point with the char at point."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-buffer "hello" kuro--line-point 2)
    (kuro--line-transpose-chars)
    (should (string= kuro--line-buffer "hlelo"))
    (should (= kuro--line-point 3))))

(ert-deftest kuro-input-mode-test-transpose-chars-at-eol ()
  "`kuro--line-transpose-chars' at end-of-line swaps the last two chars."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-buffer "hello" kuro--line-point 5)
    (kuro--line-transpose-chars)
    (should (string= kuro--line-buffer "helol"))
    (should (= kuro--line-point 5))))

(ert-deftest kuro-input-mode-test-transpose-chars-single-char-noop ()
  "`kuro--line-transpose-chars' is a no-op when buffer has fewer than two chars."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-buffer "a" kuro--line-point 1)
    (kuro--line-transpose-chars)
    (should (string= kuro--line-buffer "a"))))

;;; Group 42 — kuro--line-yank (C-y)

(ert-deftest kuro-input-mode-test-yank-inserts-top-of-kill-ring ()
  "`kuro--line-yank' inserts the top kill-ring entry at point."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-buffer "ab" kuro--line-point 2)
    (let ((kill-ring '("XYZ")))
      (kuro--line-yank)
      (should (string= kuro--line-buffer "abXYZ"))
      (should (= kuro--line-point 5)))))

(ert-deftest kuro-input-mode-test-yank-sets-yank-length ()
  "`kuro--line-yank' sets `kuro--line-yank-length' to the length of the yanked text."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-buffer "" kuro--line-point 0)
    (let ((kill-ring '("hello")))
      (kuro--line-yank)
      (should (= kuro--line-yank-length 5)))))

(ert-deftest kuro-input-mode-test-yank-empty-kill-ring-is-noop ()
  "`kuro--line-yank' displays a message and leaves buffer unchanged when kill ring is empty."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-buffer "abc" kuro--line-point 3)
    (let ((kill-ring nil))
      (cl-letf (((symbol-function 'message) #'ignore))
        (kuro--line-yank))
      (should (string= kuro--line-buffer "abc")))))

(ert-deftest kuro-input-mode-test-yank-at-interior-point ()
  "`kuro--line-yank' inserts at a mid-buffer point, not necessarily the end."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-buffer "ac" kuro--line-point 1)
    (let ((kill-ring '("b")))
      (kuro--line-yank)
      (should (string= kuro--line-buffer "abc"))
      (should (= kuro--line-point 2)))))

;;; Group 43 — kuro--line-yank-pop (M-y)

(ert-deftest kuro-input-mode-test-yank-pop-replaces-last-yank ()
  "`kuro--line-yank-pop' replaces the previously yanked region with the next kill."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-buffer "" kuro--line-point 0)
    (let ((kill-ring '("first" "second")) kill-ring-yank-pointer)
      (kuro--line-yank)
      (setq last-command 'kuro--line-yank)
      (kuro--line-yank-pop)
      (should (string= kuro--line-buffer "second"))
      (should (= kuro--line-yank-length 6)))))

(ert-deftest kuro-input-mode-test-yank-pop-requires-prior-yank ()
  "`kuro--line-yank-pop' signals `user-error' when the previous command was not a yank."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-buffer "" kuro--line-point 0)
    (let ((kill-ring '("text")) kill-ring-yank-pointer
          (last-command 'self-insert-command))
      (should-error (kuro--line-yank-pop) :type 'user-error))))

(ert-deftest kuro-input-mode-test-yank-pop-chain-accepted ()
  "`kuro--line-yank-pop' is accepted as previous command for a second invocation.
`current-kill 1 t' uses do-not-move=t so the kill-ring pointer stays fixed;
both pops return the same next-kill entry (\"B\"), making the result idempotent."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-buffer "" kuro--line-point 0)
    (let ((kill-ring '("A" "B" "C")) kill-ring-yank-pointer)
      (kuro--line-yank)
      (setq last-command 'kuro--line-yank)
      (kuro--line-yank-pop)
      (setq last-command 'kuro--line-yank-pop)
      (kuro--line-yank-pop)
      (should (string= kuro--line-buffer "B")))))

(provide 'kuro-input-mode-edit-test-2)

;;; kuro-input-mode-edit-test-2.el ends here
