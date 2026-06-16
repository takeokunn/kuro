;;; kuro-input-mode-test-cases.el --- Shared input-mode test data  -*- lexical-binding: t; -*-

;;; Code:

(defconst kuro-input-mode-readline-test--line-keymap-bindings-table
  '((kuro-input-mode-test-keymap-C-slash-undo         "C-/"  kuro--line-undo)
    (kuro-input-mode-test-keymap-C-underscore-undo    "C-_"  kuro--line-undo)
    (kuro-input-mode-test-keymap-C-r-history-search   "C-r"  kuro--line-history-search)
    (kuro-input-mode-test-keymap-C-w-unix-word-rubout "C-w"  kuro--line-unix-word-rubout)
    (kuro-input-mode-test-keymap-M-u-upcase-word      "M-u"  kuro--line-upcase-word)
    (kuro-input-mode-test-keymap-M-l-downcase-word    "M-l"  kuro--line-downcase-word)
    (kuro-input-mode-test-keymap-M-c-capitalize-word  "M-c"  kuro--line-capitalize-word)
    (kuro-input-mode-test-keymap-C-p-history-prev     "C-p"  kuro--line-history-prev)
    (kuro-input-mode-test-keymap-C-n-history-next     "C-n"  kuro--line-history-next)
    (kuro-input-mode-test-keymap-M-t-transpose-words  "M-t"  kuro--line-transpose-words))
  "Table of (test-name key-str fn-symbol) for `kuro--line-mode-keymap'.")

(defconst kuro-input-mode-readline-test--unix-word-rubout-cases
  '((kuro-input-mode-test-unix-word-rubout-kills-to-whitespace
     kuro--line-unix-word-rubout "git commit-amend" 16 "git " 4)
    (kuro-input-mode-test-unix-word-rubout-skips-trailing-spaces
     kuro--line-unix-word-rubout "foo   " 6 "" 0)
    (kuro-input-mode-test-unix-word-rubout-at-bol-is-noop
     kuro--line-unix-word-rubout "hello" 0 "hello" 0)
    (kuro-input-mode-test-unix-word-rubout-keeps-text-after-point
     kuro--line-unix-word-rubout "rm -rf /tmp/foo bar" 15 "rm -rf  bar" 7))
  "Table of C-w command line-edit behavior cases.")

(defconst kuro-input-mode-readline-test--word-case-cases
  '((kuro-input-mode-test-upcase-word-from-point
     kuro--line-upcase-word "hello world" 6 "hello WORLD" 11)
    (kuro-input-mode-test-downcase-word-from-point
     kuro--line-downcase-word "HELLO WORLD" 6 "HELLO world" 11)
    (kuro-input-mode-test-capitalize-word-from-point
     kuro--line-capitalize-word "HELLO wOrLd" 6 "HELLO World" 11)
    (kuro-input-mode-test-upcase-word-skips-leading-punct
     kuro--line-upcase-word "  hello" 0 "  HELLO" 7)
    (kuro-input-mode-test-word-case-at-eol-is-noop
     kuro--line-upcase-word "done" 4 "done" 4))
  "Table of M-u, M-l, and M-c command line-edit behavior cases.")

(defconst kuro-input-mode-readline-test--transpose-word-cases
  '((kuro-input-mode-test-transpose-words-basic
     kuro--line-transpose-words "foo bar baz" 7 "foo baz bar" 11)
    (kuro-input-mode-test-transpose-words-point-in-space
     kuro--line-transpose-words "alpha beta" 5 "beta alpha" 10)
    (kuro-input-mode-test-transpose-words-no-second-word-is-noop
     kuro--line-transpose-words "only" 4 "only" 4))
  "Table of M-t command line-edit behavior cases.")

(defconst kuro-input-mode-readline-test--line-kill-cases
  '((kuro-input-mode-test-line-kill-to-bol-at-bol-is-noop
     kuro--line-kill-to-bol "git" 0 "git" 0)
    (kuro-input-mode-test-line-kill-to-bol-at-eol-kills-all
     kuro--line-kill-to-bol "git" 3 "" 0)
    (kuro-input-mode-test-line-kill-line-from-middle
     kuro--line-kill-line "git status" 4 "git " 4)
    (kuro-input-mode-test-line-kill-line-from-bol-kills-all
     kuro--line-kill-line "git" 0 "" 0)
    (kuro-input-mode-test-line-kill-line-at-eol-is-noop
     kuro--line-kill-line "git" 3 "git" 3))
  "Table of line-kill command behavior cases.")

(defconst kuro-input-mode-edit-test--line-keymap-bindings-table
  '((kuro-input-mode-test-keymap-binds-c-x-c-e-line-edit "C-x C-e" kuro--line-edit-in-buffer)
    (kuro-input-mode-test-M-less-bound-in-line-keymap "M-<" kuro--line-goto-history-oldest)
    (kuro-input-mode-test-M-greater-bound-in-line-keymap "M->" kuro--line-goto-history-newest)
    (kuro-input-mode-test-tab-bound-to-line-complete "TAB" kuro--line-complete)
    (kuro-input-mode-test-M-SPC-bound-in-line-keymap "M-SPC" kuro--line-expand-abbrev)
    (kuro-input-mode-test-yank-last-arg-M-dot-keymap-binding "M-." kuro--line-yank-last-arg)
    (kuro-input-mode-test-yank-last-arg-M-underscore-keymap-binding "M-_" kuro--line-yank-last-arg)
    (kuro-input-mode-test-quoted-insert-keymap-binding "C-q" kuro--line-quoted-insert)
    (kuro-input-mode-test-line-newline-keymap-binding "C-o" kuro--line-newline)
    (kuro-input-mode-test-line-cj-commits "C-j" kuro--line-commit))
  "Table of edit-mode line keymap binding tests.")

(defconst kuro-input-mode-edit-test--quoted-insert-table
  '((kuro-input-mode-test-quoted-insert-inserts-literal-tab "ab" 2 ?\t "ab\t" 3)
    (kuro-input-mode-test-quoted-insert-at-point "ac" 1 ?X "aXc" 2)
    (kuro-input-mode-test-quoted-insert-control-char "" 0 ?\e "\e" 1))
  "Table of (test-name input point quoted-char expected expected-point).")

(defconst kuro-input-mode-edit-test--line-newline-table
  '((kuro-input-mode-test-line-newline-inserts-at-point
     "for i in 1 2 3" 14 "for i in 1 2 3\n" 15)
    (kuro-input-mode-test-line-newline-mid-buffer
     "aceg" 2 "ac\neg" 3))
  "Table of (test-name input point expected expected-point).")

(defconst kuro-input-mode-edit-test--word-span-table
  '((kuro-input-mode-test-word-span-empty-buffer "" 0 (0 . 0))
    (kuro-input-mode-test-word-span-at-end-of-word "git status" 3 (0 . 3))
    (kuro-input-mode-test-word-span-second-word "git status" 10 (4 . 10))
    (kuro-input-mode-test-word-span-at-point-zero "hello" 0 (0 . 0)))
  "Table of (test-name input point expected-span).")

(defconst kuro-input-mode-edit-test--line-last-word-table
  '((kuro-input-mode-test-line-last-word-simple "git commit" "commit")
    (kuro-input-mode-test-line-last-word-trailing-space "git commit " "commit")
    (kuro-input-mode-test-line-last-word-single-token "ls" "ls")
    (kuro-input-mode-test-line-last-word-nil-input nil nil)
    (kuro-input-mode-test-line-last-word-only-spaces "   " nil))
  "Table of (test-name input expected-last-word).")

(defconst kuro-input-mode-macros-test--skip-cases
  '((kuro-input-mode-macros-skip-non-word-fwd-skips-spaces
     kuro--line-skip-non-word-fwd "  hello" 0 2)
    (kuro-input-mode-macros-skip-non-word-fwd-at-word-is-noop
     kuro--line-skip-non-word-fwd "hello" 0 0)
    (kuro-input-mode-macros-skip-non-word-fwd-at-end-returns-len
     kuro--line-skip-non-word-fwd "   " 0 3)
    (kuro-input-mode-macros-skip-word-fwd-advances-past-word
     kuro--line-skip-word-fwd "hello world" 0 5)
    (kuro-input-mode-macros-skip-word-fwd-at-non-word-is-noop
     kuro--line-skip-word-fwd " hello" 0 0)
    (kuro-input-mode-macros-skip-word-fwd-at-end-returns-len
     kuro--line-skip-word-fwd "hi" 2 2)
    (kuro-input-mode-macros-skip-non-word-bwd-skips-trailing-spaces
     kuro--line-skip-non-word-bwd "hello  " 7 5)
    (kuro-input-mode-macros-skip-non-word-bwd-at-word-is-noop
     kuro--line-skip-non-word-bwd "hello" 5 5)
    (kuro-input-mode-macros-skip-word-bwd-retreats-past-word
     kuro--line-skip-word-bwd "hello" 5 0)
    (kuro-input-mode-macros-skip-word-bwd-stops-at-space
     kuro--line-skip-word-bwd "foo bar" 7 4))
  "Table of (test-name function input point expected) for word-skip scanners.")

(defconst kuro-input-mode-macros-test--word-bounds-forward-cases
  '((kuro-input-mode-macros-word-bounds-forward-at-start-of-word
     "hello world" 0 (0 . 5))
    (kuro-input-mode-macros-word-bounds-forward-skips-leading-space
     "  foo" 0 (2 . 5))
    (kuro-input-mode-macros-word-bounds-forward-empty-buffer
     "" 0 (0 . 0))
    (kuro-input-mode-macros-word-bounds-forward-all-spaces
     "   " 0 (3 . 3)))
  "Table of (test-name input point expected-span) for forward word bounds.")

(defconst kuro-input-mode-macros-test--macro-head-cases
  '((kuro-input-mode-macros-def-input-mode-expands-to-defun
     (kuro--def-input-mode kuro-test--fake-mode fake-mode
       "test mode" (ignore))
     defun kuro-test--fake-mode)
    (kuro-input-mode-macros-def-line-nav-expands-to-defun
     (kuro--def-line-nav kuro-test--fake-nav "Test nav command." (ignore))
     defun kuro-test--fake-nav)
    (kuro-input-mode-macros-def-line-word-case-expands-to-defun
     (kuro--def-line-word-case kuro-test--upcase-word
       "Test upcase." (upcase (substring s start end)))
     defun kuro-test--upcase-word)
    (kuro-input-mode-macros-def-line-kill-word-expands-to-defun
     (kuro--def-line-kill-word kuro-test--kw
       kuro--line-skip-non-word-fwd kuro--line-skip-word-fwd
       p bound p "Test kill-word.")
     defun kuro-test--kw)
    (kuro-input-mode-macros-with-line-edit-expands-to-progn
     (kuro--with-line-edit (setq x 1))
     progn nil)
    (kuro-input-mode-macros-with-line-edit-undo-expands-to-progn
     (kuro--with-line-edit-undo (setq x 1))
     progn nil)
    (kuro-input-mode-macros-line-splice-expands-to-setq
     (kuro--line-splice 0 3 "new" 3)
     setq nil))
  "Table of (test-name macro-form expected-head expected-second-or-nil).")

(defconst kuro-input-mode-macros-test--macro-member-cases
  '((kuro-input-mode-macros-def-input-mode-expansion-has-interactive
     (kuro--def-input-mode kuro-test--fake-mode2 fake-mode "test mode")
     (interactive))
    (kuro-input-mode-macros-def-line-nav-expansion-has-interactive
     (kuro--def-line-nav kuro-test--fake-nav2 "Test." (ignore))
     (interactive))
    (kuro-input-mode-macros-def-line-word-case-expansion-has-interactive
     (kuro--def-line-word-case kuro-test--wc2 "doc"
       (downcase (substring s start end)))
     (interactive))
    (kuro-input-mode-macros-def-line-kill-word-expansion-has-interactive
     (kuro--def-line-kill-word kuro-test--kw2
       kuro--line-skip-non-word-bwd kuro--line-skip-word-bwd
       bound p bound "Test backward kill-word.")
     (interactive)))
  "Table of (test-name macro-form expected-member) expansion membership checks.")

(defconst kuro-input-mode-macros-test--macro-tail-cases
  '((kuro-input-mode-macros-def-line-nav-expansion-ends-with-update-display
     (kuro--def-line-nav kuro-test--fake-nav3 "Test." (ignore))
     (kuro--line-mode-update-display))
    (kuro-input-mode-macros-with-line-edit-cps-tail-is-update-display
     (kuro--with-line-edit (setq x 1) (setq y 2))
     (kuro--line-mode-update-display))
    (kuro-input-mode-macros-with-line-edit-undo-cps-tail-is-update-display
     (kuro--with-line-edit-undo (setq x 1))
     (kuro--line-mode-update-display)))
  "Table of (test-name macro-form expected-tail) CPS tail checks.")

(defconst kuro-input-mode-macros-test--macro-form-position-cases
  '((kuro-input-mode-macros-with-line-edit-undo-first-form-is-undo-push
     (kuro--with-line-edit-undo (setq x 1))
     car (kuro--line-undo-push))
    (kuro-input-mode-macros-line-splice-first-target-is-line-buffer
     (kuro--line-splice 1 4 "x" 2)
     cadr kuro--line-buffer)
    (kuro-input-mode-macros-line-splice-second-target-is-line-point
     (kuro--line-splice 0 2 "" 0)
     nth-3 kuro--line-point))
  "Table of (test-name macro-form accessor expected) positional checks.")

(defconst kuro-input-mode-macros-test--interactive-command-cases
  '((kuro-input-mode-macros-def-input-mode-generated-fn-is-command
     kuro-char-mode kuro-semi-char-mode kuro-line-mode)
    (kuro-input-mode-macros-def-line-nav-generated-cmds-are-interactive
     kuro--line-beginning-of-line kuro--line-end-of-line
     kuro--line-forward-char kuro--line-backward-char)
    (kuro-input-mode-macros-def-line-word-case-generated-cmds-are-interactive
     kuro--line-upcase-word kuro--line-downcase-word kuro--line-capitalize-word)
    (kuro-input-mode-macros-def-line-kill-word-generated-cmds-are-interactive
     kuro--line-kill-word kuro--line-backward-kill-word))
  "Table of (test-name . commands) for generated interactive commands.")

(provide 'kuro-input-mode-test-cases)
;;; kuro-input-mode-test-cases.el ends here
