;;; kuro-input-mode-edit-test.el --- Edit-buffer and completion tests  -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for line-edit-in-buffer, history oldest/newest navigation,
;; TAB completion, abbrev expansion, yank-last-arg, quoted-insert,
;; and multi-line newline composition.  Groups 32-39.
;; Depends on kuro-input-mode-test for shared setup macros.

;;; Code:

(require 'kuro-input-mode-test-support)

;;; Group 32 — kuro-line-edit-mode and kuro--line-edit-in-buffer

(ert-deftest kuro-input-mode-test-line-edit-in-buffer-creates-edit-buffer ()
  "`kuro--line-edit-in-buffer' creates a *kuro-line-edit: <name>* buffer."
  (kuro-input-mode-edit-test--with-line-edit "test-term" "echo hello" 10
    (should (buffer-live-p edit-buf))
    (with-current-buffer edit-buf
      (should (string= (buffer-string) "echo hello")))))

(ert-deftest kuro-input-mode-test-line-edit-in-buffer-clears-line-buffer ()
  "`kuro--line-edit-in-buffer' clears `kuro--line-buffer' in the terminal buffer."
  (kuro-input-mode-edit-test--with-line-edit "clear-test" "ls -la" 6
    (should (string= kuro--line-buffer ""))
    (should (= kuro--line-point 0))))

(ert-deftest kuro-input-mode-test-line-edit-in-buffer-stores-source ()
  "Edit buffer records the source kuro buffer."
  (kuro-input-mode-edit-test--with-line-edit "src-test" "pwd" 3
    (with-current-buffer edit-buf
      (should (eq kuro--line-edit-source-buffer term-buf))
      (should (string= kuro--line-edit-original "pwd")))))

(ert-deftest kuro-input-mode-test-line-edit-send-sends-and-kills-buffer ()
  "`kuro-line-edit-send' sends buffer text with RET and kills the edit buffer."
  (kuro-input-mode-edit-test--with-line-edit "send-test" "" 0
    (with-current-buffer edit-buf
      (insert "git status")
      (setq kuro--line-edit-original ""
            kuro--line-edit-source-buffer term-buf))
    (should (string= (kuro-input-mode-test--capture-sent-string
                      (with-current-buffer edit-buf
                        (kuro-line-edit-send)))
                     "git status\r"))
    (should-not (buffer-live-p edit-buf))))

(ert-deftest kuro-input-mode-test-line-edit-discard-restores-line-buffer ()
  "`kuro-line-edit-discard' restores `kuro--line-buffer' in the terminal buffer."
  (kuro-input-mode-edit-test--with-line-edit "discard-test" "partial-cmd" 11
    (cl-letf (((symbol-function 'kuro--line-mode-update-display) #'ignore)
              ((symbol-function 'message) #'ignore))
      (with-current-buffer edit-buf
        (kuro-line-edit-discard)))
    (should (string= kuro--line-buffer "partial-cmd"))
    (should (= kuro--line-point 11))
    (should-not (buffer-live-p edit-buf))))

(ert-deftest kuro-input-mode-test-line-edit-keymap-has-send-and-discard ()
  "`kuro--line-edit-keymap' binds C-c C-c and C-c C-k."
  (should (eq (lookup-key kuro--line-edit-keymap (kbd "C-c C-c"))
              #'kuro-line-edit-send))
  (should (eq (lookup-key kuro--line-edit-keymap (kbd "C-c C-k"))
              #'kuro-line-edit-discard)))

(kuro-input-mode-edit-test--deftest-line-keymaps)

;;; Group 33 — kuro--line-goto-history-oldest + kuro--line-goto-history-newest

(ert-deftest kuro-input-mode-test-goto-history-oldest-is-interactive ()
  "`kuro--line-goto-history-oldest' is an interactive command."
  (should (commandp #'kuro--line-goto-history-oldest)))

(ert-deftest kuro-input-mode-test-goto-history-newest-is-interactive ()
  "`kuro--line-goto-history-newest' is an interactive command."
  (should (commandp #'kuro--line-goto-history-newest)))

(ert-deftest kuro-input-mode-test-goto-history-oldest-noop-on-empty ()
  "`kuro--line-goto-history-oldest' is a no-op when history is empty."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-buffer "partial")
    (setq kuro--line-point 7)
    (setq kuro--line-history nil)
    (kuro--line-goto-history-oldest)
    (should (string= kuro--line-buffer "partial"))
    (should (= kuro--line-history-idx -1))))

(ert-deftest kuro-input-mode-test-goto-history-oldest-jumps-to-last-entry ()
  "`kuro--line-goto-history-oldest' sets buffer to the last history entry."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-buffer "current")
    (setq kuro--line-point 7)
    (setq kuro--line-history '("cmd1" "cmd2" "cmd3"))
    (kuro--line-goto-history-oldest)
    (should (string= kuro--line-buffer "cmd3"))
    (should (= kuro--line-history-idx 2))))

(ert-deftest kuro-input-mode-test-goto-history-oldest-stashes-current ()
  "`kuro--line-goto-history-oldest' stashes the current input before navigating."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-buffer "my-input")
    (setq kuro--line-history-idx -1)
    (setq kuro--line-history '("old-cmd"))
    (kuro--line-goto-history-oldest)
    (should (string= kuro--line-history-stash "my-input"))))

(ert-deftest kuro-input-mode-test-goto-history-oldest-does-not-restash ()
  "`kuro--line-goto-history-oldest' does not overwrite stash when already navigating."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history-stash "original-stash")
    (setq kuro--line-history-idx 0)
    (setq kuro--line-history '("cmd1" "cmd2"))
    (kuro--line-goto-history-oldest)
    (should (string= kuro--line-history-stash "original-stash"))))

(ert-deftest kuro-input-mode-test-goto-history-newest-noop-at-current ()
  "`kuro--line-goto-history-newest' is a no-op when already at current input."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-buffer "current")
    (setq kuro--line-history-idx -1)
    (kuro--line-goto-history-newest)
    (should (string= kuro--line-buffer "current"))
    (should (= kuro--line-history-idx -1))))

(ert-deftest kuro-input-mode-test-goto-history-newest-restores-stash ()
  "`kuro--line-goto-history-newest' restores the stash and resets idx."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history-stash "my-draft")
    (setq kuro--line-history-idx 2)
    (setq kuro--line-history '("a" "b" "c"))
    (kuro--line-goto-history-newest)
    (should (string= kuro--line-buffer "my-draft"))
    (should (= kuro--line-history-idx -1))))

;;; Group 34 — kuro--line-complete (TAB) + kuro-line-completion-function

(ert-deftest kuro-input-mode-test-all-history-completions-empty ()
  "`kuro--line-all-history-completions' returns nil when history is empty."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-history nil)
   (should (null (kuro--line-all-history-completions "git")))))

(ert-deftest kuro-input-mode-test-all-history-completions-finds-matches ()
  "`kuro--line-all-history-completions' returns entries that start with prefix."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-history '("git commit" "git push" "ls -la" "git pull"))
   (should (equal (kuro--line-all-history-completions "git")
                  '("git commit" "git push" "git pull")))))

(ert-deftest kuro-input-mode-test-all-history-completions-excludes-exact ()
  "`kuro--line-all-history-completions' excludes entries equal to the prefix."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-history '("git" "git commit"))
   (should (equal (kuro--line-all-history-completions "git")
                  '("git commit")))))

(ert-deftest kuro-input-mode-test-all-history-completions-deduplicates ()
  "`kuro--line-all-history-completions' returns each unique entry only once."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-history '("git commit" "git push" "git commit"))
   (let ((result (kuro--line-all-history-completions "git")))
     (should (= (length result) 2))
     (should (equal result '("git commit" "git push"))))))

(ert-deftest kuro-input-mode-test-line-complete-no-match-messages ()
  "`kuro--line-complete' messages when no history matches the prefix."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-history '("ls -la"))
   (setq kuro--line-buffer "git")
   (setq kuro--line-point 3)
   (let ((msgs nil))
     (cl-letf (((symbol-function 'message)
                (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
       (kuro--line-complete)
       (should (cl-some (lambda (m) (string-match-p "no history completions" m)) msgs))))))

(ert-deftest kuro-input-mode-test-line-complete-single-match-completes ()
  "`kuro--line-complete' replaces buffer on a unique history match."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-history '("git commit -m 'fix'" "ls -la"))
    (setq kuro--line-buffer "git c")
    (setq kuro--line-point 5)
    (kuro--line-complete)
    (should (string= kuro--line-buffer "git commit -m 'fix'"))
    (should (= kuro--line-point 19))))

(ert-deftest kuro-input-mode-test-line-complete-multi-match-messages-count ()
  "`kuro--line-complete' messages the candidate count when multiple history matches exist."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-history '("git commit" "git push" "git pull"))
   (setq kuro--line-buffer "git")
   (setq kuro--line-point 3)
   (let ((msgs nil))
     (cl-letf (((symbol-function 'message)
                (lambda (fmt &rest args) (push (apply #'format fmt args) msgs)))
               ((symbol-function 'display-completion-list) #'ignore))
       (kuro--line-complete)
       (should (cl-some (lambda (m) (string-match-p "3 history completions" m)) msgs))))))

(ert-deftest kuro-input-mode-test-line-complete-calls-custom-function ()
  "`kuro--line-complete' calls `kuro-line-completion-function' with word at point."
  (kuro-input-mode-test--with-buffer
   (let ((received-prefix nil))
     (let ((kuro-line-completion-function
            (lambda (prefix) (setq received-prefix prefix) nil)))
       (setq kuro--line-buffer "make in")
       (setq kuro--line-point 7)
       (cl-letf (((symbol-function 'message) #'ignore))
         (kuro--line-complete))
       (should (equal received-prefix "in"))))))

(ert-deftest kuro-input-mode-test-line-complete-word-single-replaces ()
  "`kuro--line-complete' with custom fn replaces just the word at point."
  (kuro-input-mode-test--with-edit
    (let ((kuro-line-completion-function (lambda (_) '("install"))))
      (setq kuro--line-buffer "make in")
      (setq kuro--line-point 7)
      (kuro--line-complete)
      (should (string= kuro--line-buffer "make install"))
      (should (= kuro--line-point 12)))))

;;; Group 35 — kuro--line-expand-abbrev (M-SPC)

(ert-deftest kuro-input-mode-test-expand-abbrev-nil-alist-messages ()
  "`kuro--line-expand-abbrev' messages when `kuro-line-abbrev-alist' is nil."
  (kuro-input-mode-test--with-buffer
   (let ((kuro-line-abbrev-alist nil)
         (msgs nil))
     (setq kuro--line-buffer "gs")
     (setq kuro--line-point 2)
     (cl-letf (((symbol-function 'message)
                (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
       (kuro--line-expand-abbrev)
       (should (cl-some (lambda (m) (string-match-p "no abbreviation" m)) msgs))))))

(ert-deftest kuro-input-mode-test-expand-abbrev-no-match-messages ()
  "`kuro--line-expand-abbrev' messages when no alist entry matches the word."
  (kuro-input-mode-test--with-buffer
   (let ((kuro-line-abbrev-alist '(("gl" . "git log --oneline")))
         (msgs nil))
     (setq kuro--line-buffer "gs")
     (setq kuro--line-point 2)
     (cl-letf (((symbol-function 'message)
                (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
       (kuro--line-expand-abbrev)
       (should (cl-some (lambda (m) (string-match-p "no abbreviation" m)) msgs))))))

(ert-deftest kuro-input-mode-test-expand-abbrev-replaces-word ()
  "`kuro--line-expand-abbrev' replaces the entire word before point."
  (kuro-input-mode-test--with-edit
    (let ((kuro-line-abbrev-alist '(("gs" . "git status"))))
      (setq kuro--line-buffer "gs")
      (setq kuro--line-point 2)
      (kuro--line-expand-abbrev)
      (should (string= kuro--line-buffer "git status"))
      (should (= kuro--line-point 10)))))

(ert-deftest kuro-input-mode-test-expand-abbrev-mid-line ()
  "`kuro--line-expand-abbrev' expands a word in the middle of the buffer."
  (kuro-input-mode-test--with-edit
    (let ((kuro-line-abbrev-alist '(("gs" . "git status"))))
      (setq kuro--line-buffer "make gs")
      (setq kuro--line-point 7)
      (kuro--line-expand-abbrev)
      (should (string= kuro--line-buffer "make git status"))
      (should (= kuro--line-point 15)))))

(ert-deftest kuro-input-mode-test-expand-abbrev-preserves-trailing ()
  "`kuro--line-expand-abbrev' preserves text after the expanded word."
  (kuro-input-mode-test--with-edit
    (let ((kuro-line-abbrev-alist '(("gs" . "git status"))))
      (setq kuro--line-buffer "gs -- master")
      (setq kuro--line-point 2)
      (kuro--line-expand-abbrev)
      (should (string= kuro--line-buffer "git status -- master"))
      (should (= kuro--line-point 10)))))

(ert-deftest kuro-input-mode-test-expand-abbrev-pushes-undo ()
  "`kuro--line-expand-abbrev' pushes the prior state onto the undo stack."
  (kuro-input-mode-test--with-edit
    (let ((kuro-line-abbrev-alist '(("gs" . "git status"))))
      (setq kuro--line-buffer "gs")
      (setq kuro--line-point 2)
      (setq kuro--line-undo-stack nil)
      (kuro--line-expand-abbrev)
      (should (= (length kuro--line-undo-stack) 1))
      (should (equal (car kuro--line-undo-stack) '("gs" . 2))))))

(ert-deftest kuro-input-mode-test-expand-abbrev-does-not-expand-partial ()
  "`kuro--line-expand-abbrev' does not expand if only a prefix is typed."
  (kuro-input-mode-test--with-buffer
   (let ((kuro-line-abbrev-alist '(("gst" . "git status")))
         (msgs nil))
     (setq kuro--line-buffer "gs")
     (setq kuro--line-point 2)
     (cl-letf (((symbol-function 'message)
                (lambda (fmt &rest args) (push (apply #'format fmt args) msgs)))
               ((symbol-function 'kuro--line-mode-update-display) #'ignore))
       (kuro--line-expand-abbrev)
       (should (string= kuro--line-buffer "gs"))
       (should (cl-some (lambda (m) (string-match-p "no abbreviation" m)) msgs))))))

;;; Group 36 — kuro--line-clear-overlay

(ert-deftest kuro-input-mode-test-clear-overlay-noop-when-nil ()
  "`kuro--line-clear-overlay' is a no-op when `kuro--line-overlay' is nil."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-overlay nil)
   (kuro--line-clear-overlay)
   (should (null kuro--line-overlay))))

(ert-deftest kuro-input-mode-test-clear-overlay-deletes-and-clears ()
  "`kuro--line-clear-overlay' deletes the overlay and sets var to nil."
  (kuro-input-mode-test--with-buffer
   (setq kuro--line-overlay (make-overlay (point-min) (point-max)))
   (should (overlayp kuro--line-overlay))
   (kuro--line-clear-overlay)
   (should (null kuro--line-overlay))))

(provide 'kuro-input-mode-edit-test)
;;; kuro-input-mode-edit-test.el ends here
