;;; kuro-copy-mode-test.el --- ERT tests for kuro.el — copy-mode Groups 17-22  -*-  lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-support)

;;; ── Group 17 (keymap): copy-mode pager bindings (vi/less mnemonics) ──────────

(ert-deftest kuro-el-test--copy-mode-j-bound-to-scroll-up-line ()
  "Copy-mode keymap binds j to scroll-up-line (vi: scroll buffer down)."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "j")) #'scroll-up-line))))

(ert-deftest kuro-el-test--copy-mode-k-bound-to-scroll-down-line ()
  "Copy-mode keymap binds k to scroll-down-line (vi: scroll buffer up)."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "k")) #'scroll-down-line))))

(ert-deftest kuro-el-test--copy-mode-g-bound-to-beginning-of-buffer ()
  "Copy-mode keymap binds g to beginning-of-buffer (jump to scrollback top)."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "g")) #'beginning-of-buffer))))

(ert-deftest kuro-el-test--copy-mode-G-bound-to-end-of-buffer ()
  "Copy-mode keymap binds G to end-of-buffer (jump to scrollback bottom)."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "G")) #'end-of-buffer))))

(ert-deftest kuro-el-test--copy-mode-b-bound-to-scroll-down-command ()
  "Copy-mode keymap binds b to scroll-down-command (less: back a page)."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "b")) #'scroll-down-command))))

(ert-deftest kuro-el-test--copy-mode-f-bound-to-scroll-up-command ()
  "Copy-mode keymap binds f to scroll-up-command (less: forward a page)."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "f")) #'scroll-up-command))))

(ert-deftest kuro-el-test--copy-mode-spc-bound-to-scroll-up-command ()
  "Copy-mode keymap binds SPC to scroll-up-command (less: space = page down)."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "SPC")) #'scroll-up-command))))

(ert-deftest kuro-el-test--copy-mode-q-bound-to-kuro-copy-mode ()
  "Copy-mode keymap binds q to kuro-copy-mode for pager-style exit."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "q")) #'kuro-copy-mode))))

;;; ── Group 18 (keymap): copy-mode hl-line visual cursor ──────────────────────

(ert-deftest kuro-el-test--copy-mode-hl-line-defcustom-default-is-t ()
  "kuro-copy-mode-hl-line default value is t."
  (should (eq (default-value 'kuro-copy-mode-hl-line) t)))

(ert-deftest kuro-el-test--copy-mode-enables-hl-line-when-defcustom-t ()
  "kuro--enter-copy-mode enables hl-line-mode when kuro-copy-mode-hl-line is t."
  (kuro-el-test--with-kuro-mode-buffer
    (let ((kuro-copy-mode-hl-line t))
      (kuro--enter-copy-mode)
      (should hl-line-mode))))

(ert-deftest kuro-el-test--copy-mode-no-hl-line-when-defcustom-nil ()
  "kuro--enter-copy-mode does not enable hl-line-mode when kuro-copy-mode-hl-line is nil."
  (kuro-el-test--with-kuro-mode-buffer
    (let ((kuro-copy-mode-hl-line nil))
      (kuro--enter-copy-mode)
      (should-not hl-line-mode))))

(ert-deftest kuro-el-test--exit-copy-mode-disables-hl-line ()
  "kuro--exit-copy-mode disables hl-line-mode regardless of how it was enabled."
  (kuro-el-test--with-kuro-mode-buffer
    (let ((kuro-copy-mode-hl-line t))
      (kuro--enter-copy-mode)
      (should hl-line-mode)
      (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore))
        (kuro--exit-copy-mode))
      (should-not hl-line-mode))))

;;; ── Group 19: copy-mode region selection and kill-ring operations ─────────────

(ert-deftest kuro-copy-mode-test-copy-region-and-exit-copies-to-kill-ring ()
  "kuro--copy-copy-region-and-exit puts selected text into the kill-ring."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (let ((inhibit-read-only t))
      (insert "hello world"))
    (set-mark (point-min))
    (goto-char (point-max))
    (cl-letf (((symbol-function 'kuro-copy-mode) #'ignore))
      (kuro--copy-copy-region-and-exit))
    (should (equal (car kill-ring) "hello world"))))

(ert-deftest kuro-copy-mode-test-copy-region-and-exit-exits-copy-mode ()
  "kuro--copy-copy-region-and-exit calls kuro-copy-mode to exit copy mode."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (let ((inhibit-read-only t))
      (insert "exit test"))
    (set-mark (point-min))
    (goto-char (point-max))
    (let ((exit-called nil))
      (cl-letf (((symbol-function 'kuro-copy-mode)
                 (lambda () (setq exit-called t))))
        (kuro--copy-copy-region-and-exit))
      (should exit-called))))

(ert-deftest kuro-copy-mode-test-copy-region-and-exit-errors-without-region ()
  "kuro--copy-copy-region-and-exit signals user-error when no region is active."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (deactivate-mark)
    (should-error (kuro--copy-copy-region-and-exit) :type 'user-error)))

(ert-deftest kuro-copy-mode-test-set-mark-is-interactive ()
  "kuro--copy-set-mark is an interactive command."
  (should (commandp #'kuro--copy-set-mark)))

(ert-deftest kuro-copy-mode-test-copy-region-keymap-bindings ()
  "M-w and y are both bound to kuro--copy-copy-region-and-exit in copy keymap."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "M-w"))
                #'kuro--copy-copy-region-and-exit))
    (should (eq (lookup-key (current-local-map) (kbd "y"))
                #'kuro--copy-copy-region-and-exit))))

(ert-deftest kuro-copy-mode-test-v-bound-to-set-mark ()
  "v is bound to kuro--copy-set-mark in the copy-mode keymap."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "v"))
                #'kuro--copy-set-mark))))

(ert-deftest kuro-copy-mode-test-copy-region-partial-selection ()
  "kuro--copy-copy-region-and-exit copies only the selected portion."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (let ((inhibit-read-only t))
      (insert "abcdef"))
    (goto-char (point-min))
    (set-mark (point-min))
    (forward-char 3)
    (cl-letf (((symbol-function 'kuro-copy-mode) #'ignore))
      (kuro--copy-copy-region-and-exit))
    (should (equal (car kill-ring) "abc"))))

(ert-deftest kuro-copy-mode-test-copy-region-message-includes-char-count ()
  "kuro--copy-copy-region-and-exit messages the number of characters copied."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (let ((inhibit-read-only t))
      (insert "12345"))
    (set-mark (point-min))
    (goto-char (point-max))
    (let ((msg nil))
      (cl-letf (((symbol-function 'kuro-copy-mode) #'ignore)
                ((symbol-function 'message)
                 (lambda (fmt &rest args) (setq msg (apply #'format fmt args)))))
        (kuro--copy-copy-region-and-exit))
      (should (string-match-p "5" msg)))))

;;; ── Group 20: copy-mode vim character/word/line motion bindings ──────────────

(ert-deftest kuro-copy-mode-test-h-l-bound-to-char-motion ()
  "h/l are bound to backward-char/forward-char in copy-mode keymap."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "h")) #'backward-char))
    (should (eq (lookup-key (current-local-map) (kbd "l")) #'forward-char))))

(ert-deftest kuro-copy-mode-test-w-e-bound-to-forward-word ()
  "w and e are both bound to forward-word in copy-mode keymap."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "w")) #'forward-word))
    (should (eq (lookup-key (current-local-map) (kbd "e")) #'forward-word))))

(ert-deftest kuro-copy-mode-test-B-bound-to-backward-word ()
  "B is bound to backward-word in copy-mode keymap (b is taken by scroll-down)."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "B")) #'backward-word))))

(ert-deftest kuro-copy-mode-test-bol-eol-bindings ()
  "0 and $ are bound to beginning-of-line/end-of-line."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "0")) #'beginning-of-line))
    (should (eq (lookup-key (current-local-map) (kbd "$")) #'end-of-line))))

(ert-deftest kuro-copy-mode-test-H-M-L-bound-to-window-line-fns ()
  "H/M/L are bound to kuro--copy-move-to-top/middle/bottom."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "H")) #'kuro--copy-move-to-top))
    (should (eq (lookup-key (current-local-map) (kbd "M")) #'kuro--copy-move-to-middle))
    (should (eq (lookup-key (current-local-map) (kbd "L")) #'kuro--copy-move-to-bottom))))

(ert-deftest kuro-copy-mode-test-move-to-top-is-interactive ()
  "`kuro--copy-move-to-top' is an interactive command."
  (should (commandp #'kuro--copy-move-to-top)))

(ert-deftest kuro-copy-mode-test-move-to-middle-is-interactive ()
  "`kuro--copy-move-to-middle' is an interactive command."
  (should (commandp #'kuro--copy-move-to-middle)))

(ert-deftest kuro-copy-mode-test-move-to-bottom-is-interactive ()
  "`kuro--copy-move-to-bottom' is an interactive command."
  (should (commandp #'kuro--copy-move-to-bottom)))

(ert-deftest kuro-copy-mode-test-vim-motions-do-not-shadow-existing ()
  "Existing pager bindings j/k/g/G/b/f/SPC survive after adding vim motions."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "j")) #'scroll-up-line))
    (should (eq (lookup-key (current-local-map) (kbd "k")) #'scroll-down-line))
    (should (eq (lookup-key (current-local-map) (kbd "g")) #'beginning-of-buffer))
    (should (eq (lookup-key (current-local-map) (kbd "G")) #'end-of-buffer))
    (should (eq (lookup-key (current-local-map) (kbd "b")) #'scroll-down-command))))

;;; ── Group 21: copy-mode n/N/* vim search repeat ──────────────────────────────

(ert-deftest kuro-copy-mode-test-n-bound-to-search-next ()
  "copy-map binds `n' to `kuro--copy-search-next'."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "n"))
                #'kuro--copy-search-next))))

(ert-deftest kuro-copy-mode-test-N-bound-to-search-prev ()
  "copy-map binds `N' to `kuro--copy-search-prev'."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "N"))
                #'kuro--copy-search-prev))))

(ert-deftest kuro-copy-mode-test-star-bound-to-search-word ()
  "copy-map binds `*' to `kuro--copy-search-word-forward'."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "*"))
                #'kuro--copy-search-word-forward))))

(ert-deftest kuro-copy-mode-test-search-next-finds-forward ()
  "`kuro--copy-search-next' moves point to the next match."
  (with-temp-buffer
    (insert "foo bar foo baz")
    (goto-char (point-min))
    (let ((isearch-string "foo")
          (isearch-regexp nil))
      (kuro--copy-search-next)
      (should (= (point) 4)))))

(ert-deftest kuro-copy-mode-test-search-next-wraps ()
  "`kuro--copy-search-next' wraps to beginning when no forward match."
  (with-temp-buffer
    (insert "foo bar")
    (goto-char (point-max))
    (let ((isearch-string "foo")
          (isearch-regexp nil))
      (kuro--copy-search-next)
      (should (= (point) 4)))))

(ert-deftest kuro-copy-mode-test-search-prev-finds-backward ()
  "`kuro--copy-search-prev' moves point to the previous match."
  (with-temp-buffer
    (insert "foo bar foo baz")
    (goto-char (point-max))
    (let ((isearch-string "foo")
          (isearch-regexp nil))
      (kuro--copy-search-prev)
      (should (= (point) 9)))))

(ert-deftest kuro-copy-mode-test-search-prev-wraps ()
  "`kuro--copy-search-prev' wraps to end when no backward match."
  (with-temp-buffer
    (insert "foo bar foo")
    (goto-char (point-min))
    (let ((isearch-string "foo")
          (isearch-regexp nil))
      (kuro--copy-search-prev)
      ;; "foo bar foo": second "foo" begins at position 9
      (should (= (point) 9)))))

(ert-deftest kuro-copy-mode-test-search-next-no-pattern-calls-isearch ()
  "`kuro--copy-search-next' with empty `isearch-string' falls through to `isearch-forward'."
  (let ((called nil))
    (cl-letf (((symbol-function 'isearch-forward)
               (lambda () (interactive) (setq called t))))
      (let ((isearch-string ""))
        (kuro--copy-search-next))
      (should called))))

(ert-deftest kuro-copy-mode-test-search-word-forward-sets-isearch-string ()
  "`kuro--copy-search-word-forward' sets `isearch-string' to the word at point."
  (with-temp-buffer
    (insert "hello world")
    (goto-char 1)
    (cl-letf (((symbol-function 'kuro--copy-search-next) #'ignore))
      (kuro--copy-search-word-forward)
      (should (equal isearch-string "hello")))))

(ert-deftest kuro-copy-mode-test-search-word-forward-no-word-messages ()
  "`kuro--copy-search-word-forward' messages when no word at point."
  (with-temp-buffer
    (let ((msgs nil))
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args)
                   (push (apply #'format fmt args) msgs))))
        (kuro--copy-search-word-forward)
        (should (cl-some (lambda (m) (string-match-p "No word" m)) msgs))))))

;;; ── Group 22: copy-mode {/} prompt overlay navigation ───────────────────────

(ert-deftest kuro-copy-mode-test-prompt-overlay-positions-empty ()
  "`kuro--prompt-overlay-positions' returns nil when no prompt overlays exist."
  (with-temp-buffer
    (insert "hello world")
    (should (null (kuro--prompt-overlay-positions)))))

(ert-deftest kuro-copy-mode-test-prompt-overlay-positions-sorted ()
  "`kuro--prompt-overlay-positions' returns positions in ascending order."
  (kuro-copy-mode-test--with-prompt-overlays '(15 5 10)
    (should (equal (kuro--prompt-overlay-positions) '(5 10 15)))))

(ert-deftest kuro-copy-mode-test-prompt-overlay-positions-ignores-untagged ()
  "`kuro--prompt-overlay-positions' ignores overlays without `kuro-prompt-status'."
  (with-temp-buffer
    (insert (make-string 20 ?x))
    (let ((ov (make-overlay 5 5)))
      (overlay-put ov 'some-other-property t))
    (should (null (kuro--prompt-overlay-positions)))))

(ert-deftest kuro-copy-mode-test-goto-next-prompt-basic ()
  "`kuro--copy-goto-next-prompt' moves point to the next prompt overlay."
  (kuro-copy-mode-test--with-prompt-overlays '(5 15)
    (goto-char 1)
    (kuro--copy-goto-next-prompt)
    (should (= (point) 5))))

(ert-deftest kuro-copy-mode-test-goto-next-prompt-advances-past-current ()
  "`kuro--copy-goto-next-prompt' skips the overlay at the current position."
  (kuro-copy-mode-test--with-prompt-overlays '(5 15)
    (goto-char 5)
    (kuro--copy-goto-next-prompt)
    (should (= (point) 15))))

(ert-deftest kuro-copy-mode-test-goto-next-prompt-fallback-paragraph ()
  "`kuro--copy-goto-next-prompt' calls `forward-paragraph' when no overlays exist."
  (with-temp-buffer
    (insert "line one\n\nline two\n")
    (goto-char (point-min))
    (let ((called nil))
      (cl-letf (((symbol-function 'forward-paragraph)
                 (lambda () (interactive) (setq called t))))
        (kuro--copy-goto-next-prompt)
        (should called)))))

(ert-deftest kuro-copy-mode-test-goto-prev-prompt-basic ()
  "`kuro--copy-goto-prev-prompt' moves point to the previous prompt overlay."
  (kuro-copy-mode-test--with-prompt-overlays '(5 15)
    (goto-char 20)
    (kuro--copy-goto-prev-prompt)
    (should (= (point) 15))))

(ert-deftest kuro-copy-mode-test-goto-prev-prompt-skips-current ()
  "`kuro--copy-goto-prev-prompt' finds the overlay strictly before current point."
  (kuro-copy-mode-test--with-prompt-overlays '(5 15)
    (goto-char 15)
    (kuro--copy-goto-prev-prompt)
    (should (= (point) 5))))

(ert-deftest kuro-copy-mode-test-goto-prev-prompt-fallback-paragraph ()
  "`kuro--copy-goto-prev-prompt' calls `backward-paragraph' when no overlays exist."
  (with-temp-buffer
    (insert "line one\n\nline two\n")
    (goto-char (point-max))
    (let ((called nil))
      (cl-letf (((symbol-function 'backward-paragraph)
                 (lambda () (interactive) (setq called t))))
        (kuro--copy-goto-prev-prompt)
        (should called)))))

(ert-deftest kuro-copy-mode-test-copy-map-has-brace-bindings ()
  "`kuro--enter-copy-mode' binds `{' to prev-prompt and `}' to next-prompt."
  (with-temp-buffer
    (kuro-mode)
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "{"))
                #'kuro--copy-goto-prev-prompt))
    (should (eq (lookup-key (current-local-map) (kbd "}"))
                #'kuro--copy-goto-next-prompt))
    (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore))
      (kuro--exit-copy-mode))))

(provide 'kuro-copy-mode-test)
;;; kuro-copy-mode-test.el ends here
