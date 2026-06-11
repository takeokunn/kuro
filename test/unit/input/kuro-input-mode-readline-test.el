;;; kuro-input-mode-readline-test.el --- Readline operation tests  -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for readline-style operations: cursor motion, kill/yank, undo,
;; history search, word-case, transpose.  Groups 23-31.
;; Depends on kuro-input-mode-test for shared setup macros.

;;; Code:

(require 'kuro-input-mode-test-support)

;;; Group 23 — kuro--line-complete-history

(ert-deftest kuro-input-mode-test-complete-history-is-interactive ()
  "`kuro--line-complete-history' is an interactive command."
  (should (commandp #'kuro--line-complete-history)))

(ert-deftest kuro-input-mode-test-complete-history-replaces-buffer-with-match ()
  "`kuro--line-complete-history' replaces buffer with first prefix-matching entry."
  (kuro-input-mode-test--with-buffer
   (let ((kuro--line-history '("git status" "git diff" "ls"))
         (kuro--line-buffer "git"))
     (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
       (kuro--line-complete-history)
       (should (equal kuro--line-buffer "git status"))))))

(ert-deftest kuro-input-mode-test-complete-history-skips-exact-match ()
  "`kuro--line-complete-history' skips the history entry that equals the current buffer."
  (kuro-input-mode-test--with-buffer
   (let ((kuro--line-history '("git" "git status"))
         (kuro--line-buffer "git"))
     (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
       (kuro--line-complete-history)
       ;; "git" is exact match → skip; "git status" is prefix match → use it
       (should (equal kuro--line-buffer "git status"))))))

(ert-deftest kuro-input-mode-test-complete-history-no-op-when-no-match ()
  "`kuro--line-complete-history' leaves buffer unchanged when no prefix match exists."
  (kuro-input-mode-test--with-buffer
   (let ((kuro--line-history '("ls" "pwd"))
         (kuro--line-buffer "git"))
     (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
       (kuro--line-complete-history)
       (should (equal kuro--line-buffer "git"))))))

(ert-deftest kuro-input-mode-test-complete-history-empty-prefix-matches-first ()
  "`kuro--line-complete-history' with empty buffer completes to first history entry."
  (kuro-input-mode-test--with-buffer
   (let ((kuro--line-history '("ls -la" "pwd"))
         (kuro--line-buffer ""))
     (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore))
       (kuro--line-complete-history)
       (should (equal kuro--line-buffer "ls -la"))))))

(ert-deftest kuro-input-mode-test-complete-history-bound-in-line-keymap ()
  "`kuro--line-mode-keymap' binds \"M-/\" to `kuro--line-complete-history'."
  (kuro-input-mode-test--with-buffer
   (kuro--build-line-mode-keymap)
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "M-/"))
               #'kuro--line-complete-history))))

;;; Group 24 — kuro--line-point cursor tracking and readline operations

(ert-deftest kuro-input-mode-test-line-point-initial-is-zero ()
  "`kuro--line-point' starts at 0 in a fresh buffer."
  (kuro-input-mode-test--with-buffer
   (should (= kuro--line-point 0))))

(ert-deftest kuro-input-mode-test-line-self-insert-increments-point ()
  "`kuro--line-self-insert' increments `kuro--line-point' after inserting."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq last-command-event ?a)
   (kuro--line-self-insert)
   (should (= kuro--line-point 1))))

(ert-deftest kuro-input-mode-test-line-insert-at-middle-inserts-correctly ()
  "Inserting with point in the middle inserts at the correct position."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "ac")
   (setq kuro--line-point 1)
   (setq last-command-event ?b)
   (kuro--line-self-insert)
   (should (string= kuro--line-buffer "abc"))
   (should (= kuro--line-point 2))))

(ert-deftest kuro-input-mode-test-line-delete-decrements-point ()
  "`kuro--line-delete' decrements `kuro--line-point' after removing a char."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "hi")
   (setq kuro--line-point 2)
   (kuro--line-delete)
   (should (string= kuro--line-buffer "h"))
   (should (= kuro--line-point 1))))

(ert-deftest kuro-input-mode-test-line-forward-char-moves-right ()
  "`kuro--line-forward-char' increments `kuro--line-point'."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "abc")
   (setq kuro--line-point 0)
   (kuro--line-forward-char)
   (should (= kuro--line-point 1))))

(ert-deftest kuro-input-mode-test-line-forward-char-clamps-at-eol ()
  "`kuro--line-forward-char' at EOL stays at EOL."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "abc")
   (setq kuro--line-point 3)
   (kuro--line-forward-char)
   (should (= kuro--line-point 3))))

(ert-deftest kuro-input-mode-test-line-backward-char-moves-left ()
  "`kuro--line-backward-char' decrements `kuro--line-point'."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "abc")
   (setq kuro--line-point 3)
   (kuro--line-backward-char)
   (should (= kuro--line-point 2))))

(ert-deftest kuro-input-mode-test-line-backward-char-clamps-at-bol ()
  "`kuro--line-backward-char' at BOL stays at 0."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "abc")
   (setq kuro--line-point 0)
   (kuro--line-backward-char)
   (should (= kuro--line-point 0))))

(ert-deftest kuro-input-mode-test-line-beginning-of-line-moves-to-bol ()
  "`kuro--line-beginning-of-line' sets `kuro--line-point' to 0."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "hello")
   (setq kuro--line-point 5)
   (kuro--line-beginning-of-line)
   (should (= kuro--line-point 0))))

(ert-deftest kuro-input-mode-test-line-end-of-line-moves-to-eol ()
  "`kuro--line-end-of-line' sets `kuro--line-point' to (length buffer)."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "hello")
   (setq kuro--line-point 0)
   (kuro--line-end-of-line)
   (should (= kuro--line-point 5))))

(ert-deftest kuro-input-mode-test-line-forward-word-skips-word ()
  "`kuro--line-forward-word' moves past the next word."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "git status")
   (setq kuro--line-point 0)
   (kuro--line-forward-word)
   (should (= kuro--line-point 3))))

(ert-deftest kuro-input-mode-test-line-backward-word-skips-word ()
  "`kuro--line-backward-word' moves to start of previous word."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "git status")
   (setq kuro--line-point 10)
   (kuro--line-backward-word)
   (should (= kuro--line-point 4))))

(ert-deftest kuro-input-mode-test-line-kill-word-kills-forward ()
  "`kuro--line-kill-word' kills from point to end of next word."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "git status")
   (setq kuro--line-point 4)
   (kuro--line-kill-word)
   (should (string= kuro--line-buffer "git "))
   (should (= kuro--line-point 4))))

(ert-deftest kuro-input-mode-test-line-backward-kill-word-kills-backward ()
  "`kuro--line-backward-kill-word' kills from start of previous word to point."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "git status")
   (setq kuro--line-point 10)
   (kuro--line-backward-kill-word)
   (should (string= kuro--line-buffer "git "))
   (should (= kuro--line-point 4))))

(ert-deftest kuro-input-mode-test-line-delete-char-deletes-at-point ()
  "`kuro--line-delete-char' removes the character at `kuro--line-point'."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "abc")
   (setq kuro--line-point 1)
   (kuro--line-delete-char)
   (should (string= kuro--line-buffer "ac"))
   (should (= kuro--line-point 1))))

(ert-deftest kuro-input-mode-test-line-delete-char-noop-at-eol ()
  "`kuro--line-delete-char' is a no-op when point is at EOL."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "abc")
   (setq kuro--line-point 3)
   (kuro--line-delete-char)
   (should (string= kuro--line-buffer "abc"))))

(ert-deftest kuro-input-mode-test-line-kill-to-bol-kills-backward ()
  "`kuro--line-kill-to-bol' kills from BOL to point."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "git status")
   (setq kuro--line-point 4)
   (kuro--line-kill-to-bol)
   (should (string= kuro--line-buffer "status"))
   (should (= kuro--line-point 0))))

(ert-deftest kuro-input-mode-test-line-transpose-chars ()
  "`kuro--line-transpose-chars' swaps the char before and at point."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "abcd")
   (setq kuro--line-point 2)
   (kuro--line-transpose-chars)
   (should (string= kuro--line-buffer "acbd"))))

(ert-deftest kuro-input-mode-test-line-keymap-binds-readline-ops ()
  "Line keymap binds all readline motion/editing keys."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   (kuro--build-line-mode-keymap)
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "C-a")) #'kuro--line-beginning-of-line))
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "C-e")) #'kuro--line-end-of-line))
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "C-f")) #'kuro--line-forward-char))
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "C-b")) #'kuro--line-backward-char))
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "M-f")) #'kuro--line-forward-word))
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "M-b")) #'kuro--line-backward-word))
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "M-d")) #'kuro--line-kill-word))
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "M-DEL")) #'kuro--line-backward-kill-word))
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "C-d")) #'kuro--line-delete-char))
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "C-u")) #'kuro--line-kill-to-bol))
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "C-t")) #'kuro--line-transpose-chars))))

;;; Group 25 — kuro--line-yank and kuro--line-yank-pop

(ert-deftest kuro-input-mode-test-line-yank-inserts-kill-at-point ()
  "`kuro--line-yank' inserts the current kill at `kuro--line-point'."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "ac")
   (setq kuro--line-point 1)
   (let ((kill-ring '("b")))
     (kuro--line-yank)
     (should (string= kuro--line-buffer "abc")))))

(ert-deftest kuro-input-mode-test-line-yank-advances-point ()
  "`kuro--line-yank' advances `kuro--line-point' past the inserted text."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "")
   (setq kuro--line-point 0)
   (let ((kill-ring '("hello")))
     (kuro--line-yank)
     (should (= kuro--line-point 5)))))

(ert-deftest kuro-input-mode-test-line-yank-sets-yank-length ()
  "`kuro--line-yank' sets `kuro--line-yank-length' to the kill length."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "")
   (setq kuro--line-point 0)
   (let ((kill-ring '("world")))
     (kuro--line-yank)
     (should (= kuro--line-yank-length 5)))))

(ert-deftest kuro-input-mode-test-line-yank-noop-on-empty-kill-ring ()
  "`kuro--line-yank' is a no-op when the kill ring is empty."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "abc")
   (setq kuro--line-point 0)
   (let ((kill-ring nil))
     (kuro--line-yank)
     (should (string= kuro--line-buffer "abc"))
     (should (= kuro--line-point 0)))))

(ert-deftest kuro-input-mode-test-line-yank-at-eol ()
  "`kuro--line-yank' at EOL appends to the buffer."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "git ")
   (setq kuro--line-point 4)
   (let ((kill-ring '("status")))
     (kuro--line-yank)
     (should (string= kuro--line-buffer "git status"))
     (should (= kuro--line-point 10)))))

(ert-deftest kuro-input-mode-test-line-yank-pop-replaces-last-yank ()
  "`kuro--line-yank-pop' replaces the most recently yanked text."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (setq kuro--line-buffer "hello")
   (setq kuro--line-point 5)
   (setq kuro--line-yank-length 5)
   (let ((kill-ring '("hello" "world"))
         (kill-ring-yank-pointer nil))
     (setq kill-ring-yank-pointer kill-ring)
     (let ((last-command 'kuro--line-yank))
       (kuro--line-yank-pop)
       (should (string= kuro--line-buffer "world"))
       (should (= kuro--line-point 5))))))

(ert-deftest kuro-input-mode-test-line-yank-pop-errors-without-prior-yank ()
  "`kuro--line-yank-pop' signals user-error when previous command was not a yank."
  (kuro-input-mode-test--with-buffer
   (setq kuro--input-mode 'line)
   (let ((last-command 'self-insert-command))
     (should-error (kuro--line-yank-pop) :type 'user-error))))

(ert-deftest kuro-input-mode-test-line-keymap-binds-yank-ops ()
  "Line keymap binds C-y to `kuro--line-yank' and M-y to `kuro--line-yank-pop'."
  (kuro-input-mode-test--with-buffer
   (kuro--build-keymap)
   (kuro--build-line-mode-keymap)
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "C-y")) #'kuro--line-yank))
   (should (eq (lookup-key kuro--line-mode-keymap (kbd "M-y")) #'kuro--line-yank-pop))))

(provide 'kuro-input-mode-readline-test)
;;; kuro-input-mode-readline-test.el ends here
