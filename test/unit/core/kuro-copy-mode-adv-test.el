;;; kuro-copy-mode-adv-test.el --- ERT tests for kuro.el — copy-mode Groups 23-N (rectangle, linewise, append-region, finalize)  -*-  lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-support)

;;; ── Group 23: copy-mode rectangle (block) selection ──────────────────────────

(ert-deftest kuro-copy-mode-test-rectangle-toggle-is-interactive ()
  "`kuro--copy-rectangle-toggle' is an interactive command."
  (should (commandp #'kuro--copy-rectangle-toggle)))

(ert-deftest kuro-copy-mode-test-rectangle-toggle-keymap-bindings ()
  "C-v and R are both bound to `kuro--copy-rectangle-toggle' in the copy keymap."
  (with-temp-buffer
    (kuro-mode)
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "C-v"))
                #'kuro--copy-rectangle-toggle))
    (should (eq (lookup-key (current-local-map) (kbd "R"))
                #'kuro--copy-rectangle-toggle))
    (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore))
      (kuro--exit-copy-mode))))

(ert-deftest kuro-copy-mode-test-rectangle-toggle-sets-mark-when-none ()
  "`kuro--copy-rectangle-toggle' sets the mark when no region is active."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (let ((inhibit-read-only t))
      (insert "abcde\nfghij\nklmno"))
    (deactivate-mark)
    (goto-char (point-min))
    (kuro--copy-rectangle-toggle)
    (should (mark t))
    (should (bound-and-true-p rectangle-mark-mode))
    (rectangle-mark-mode -1)))

(ert-deftest kuro-copy-mode-test-rectangle-toggle-turns-off ()
  "Calling `kuro--copy-rectangle-toggle' twice disables rectangle selection."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (let ((inhibit-read-only t))
      (insert "abcde\nfghij\nklmno"))
    (goto-char (point-min))
    (set-mark (point))
    (kuro--copy-rectangle-toggle)
    (should (bound-and-true-p rectangle-mark-mode))
    (kuro--copy-rectangle-toggle)
    (should-not (bound-and-true-p rectangle-mark-mode))))

(ert-deftest kuro-copy-mode-test-rectangle-copy-block-as-text ()
  "Copying with rectangle selection active yields a newline-joined block.
Also confirms the copy turns rectangle-mark-mode back off on exit."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (let ((inhibit-read-only t))
      (insert "abcde\nfghij\nklmno"))
    ;; Anchor at row 0 col 1, extend to row 2 col 4 → block columns 1..4.
    (goto-char (point-min))
    (forward-char 1)
    (set-mark (point))
    (rectangle-mark-mode 1)
    (goto-char (point-min))
    (forward-line 2)
    (forward-char 4)
    (cl-letf (((symbol-function 'kuro-copy-mode) #'ignore))
      (kuro--copy-copy-region-and-exit))
    (should (equal (car kill-ring) "bcd\nghi\nlmn"))
    (should-not (bound-and-true-p rectangle-mark-mode))))

(ert-deftest kuro-copy-mode-test-rectangle-cleared-on-exit ()
  "`kuro--exit-copy-mode' clears a lingering rectangle-mark-mode."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (let ((inhibit-read-only t))
      (insert "abcde\nfghij"))
    (goto-char (point-min))
    (set-mark (point))
    (rectangle-mark-mode 1)
    (should (bound-and-true-p rectangle-mark-mode))
    (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore))
      (kuro--exit-copy-mode))
    (should-not (bound-and-true-p rectangle-mark-mode))))

;;; ── Group 24: copy-mode line-wise (vim V) selection ──────────────────────────

(ert-deftest kuro-copy-mode-test-set-mark-line-is-interactive ()
  "`kuro--copy-set-mark-line' is an interactive command."
  (should (commandp #'kuro--copy-set-mark-line)))

(ert-deftest kuro-copy-mode-test-V-bound-to-set-mark-line ()
  "V is bound to `kuro--copy-set-mark-line' in the copy-mode keymap."
  (with-temp-buffer
    (kuro-mode)
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "V"))
                #'kuro--copy-set-mark-line))
    (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore))
      (kuro--exit-copy-mode))))

(ert-deftest kuro-copy-mode-test-set-mark-line-sets-flag-and-bol-mark ()
  "`kuro--copy-set-mark-line' flags line-wise and sets the mark at BOL."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (let ((inhibit-read-only t))
      (insert "abcde\nfghij\nklmno"))
    (goto-char (point-min))
    (forward-line 1)
    (forward-char 2)                    ; mid-line on row 1
    (kuro--copy-set-mark-line)
    (should kuro--copy-linewise)
    ;; mark snapped to beginning of row 1
    (should (= (mark) (save-excursion (goto-char (mark)) (line-beginning-position))))))

(ert-deftest kuro-copy-mode-test-linewise-copy-grabs-whole-lines ()
  "Line-wise copy grabs complete lines including the trailing newline."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (let ((inhibit-read-only t))
      (insert "abcde\nfghij\nklmno\n"))
    ;; Anchor mid-row-0, extend mid-row-1 → should capture rows 0 and 1 fully.
    (goto-char (point-min))
    (forward-char 2)
    (kuro--copy-set-mark-line)          ; mark at BOL row 0, linewise on
    (goto-char (point-min))
    (forward-line 1)
    (forward-char 3)                    ; point mid-row-1
    (cl-letf (((symbol-function 'kuro-copy-mode) #'ignore))
      (kuro--copy-copy-region-and-exit))
    (should (equal (car kill-ring) "abcde\nfghij\n"))
    (should-not kuro--copy-linewise)))

(ert-deftest kuro-copy-mode-test-set-mark-clears-linewise ()
  "Char-wise `kuro--copy-set-mark' (v) clears a prior line-wise flag."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (let ((inhibit-read-only t))
      (insert "abc\ndef"))
    (setq kuro--copy-linewise t)
    (goto-char (point-min))
    (kuro--copy-set-mark)
    (should-not kuro--copy-linewise)))

(ert-deftest kuro-copy-mode-test-rectangle-toggle-clears-linewise ()
  "`kuro--copy-rectangle-toggle' clears a prior line-wise flag."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (let ((inhibit-read-only t))
      (insert "abc\ndef"))
    (setq kuro--copy-linewise t)
    (goto-char (point-min))
    (set-mark (point))
    (kuro--copy-rectangle-toggle)
    (should-not kuro--copy-linewise)
    (when (bound-and-true-p rectangle-mark-mode) (rectangle-mark-mode -1))))

(ert-deftest kuro-copy-mode-test-linewise-cleared-on-exit ()
  "`kuro--exit-copy-mode' clears a lingering line-wise selection flag."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (setq kuro--copy-linewise t)
    (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore))
      (kuro--exit-copy-mode))
    (should-not kuro--copy-linewise)))

;;; ── Group 25: copy-mode append-region (accumulate fragments) ─────────────────

(ert-deftest kuro-copy-mode-test-append-region-is-interactive ()
  "`kuro--copy-append-region' is an interactive command."
  (should (commandp #'kuro--copy-append-region)))

(ert-deftest kuro-copy-mode-test-A-bound-to-append-region ()
  "A is bound to `kuro--copy-append-region' in the copy-mode keymap."
  (with-temp-buffer
    (kuro-mode)
    (kuro--enter-copy-mode)
    (should (eq (lookup-key (current-local-map) (kbd "A"))
                #'kuro--copy-append-region))
    (cl-letf (((symbol-function 'kuro--render-cycle) #'ignore))
      (kuro--exit-copy-mode))))

(ert-deftest kuro-copy-mode-test-append-region-errors-without-region ()
  "`kuro--copy-append-region' signals user-error when no region is active."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (deactivate-mark)
    (should-error (kuro--copy-append-region) :type 'user-error)))

(ert-deftest kuro-copy-mode-test-append-region-first-copies-normally ()
  "With an empty kill ring, the first append behaves like a plain copy."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (let ((inhibit-read-only t))
      (insert "hello world"))
    (let ((kill-ring nil))
      (goto-char (point-min))
      (set-mark (point-min))
      (forward-char 5)                   ; select "hello"
      (kuro--copy-append-region)
      (should (equal (current-kill 0) "hello")))))

(ert-deftest kuro-copy-mode-test-append-region-accumulates ()
  "A second append adds the selection to the same kill, newline-separated."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (let ((inhibit-read-only t))
      (insert "alpha beta gamma"))
    (let ((kill-ring nil))
      ;; First fragment: "alpha"
      (goto-char (point-min))
      (set-mark (point-min))
      (forward-char 5)
      (kuro--copy-append-region)
      ;; Second fragment: "gamma" (positions 12..17)
      (goto-char (point-min))
      (forward-char 11)
      (set-mark (point))
      (goto-char (point-max))
      (kuro--copy-append-region)
      (should (equal (current-kill 0) "alpha\ngamma")))))

(ert-deftest kuro-copy-mode-test-append-region-stays-in-copy-mode ()
  "`kuro--copy-append-region' does not exit copy mode."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (let ((inhibit-read-only t))
      (insert "stay here"))
    (let ((kill-ring nil)
          (exit-called nil))
      (goto-char (point-min))
      (set-mark (point-min))
      (forward-char 4)
      (cl-letf (((symbol-function 'kuro-copy-mode)
                 (lambda () (setq exit-called t))))
        (kuro--copy-append-region))
      (should-not exit-called))))

(ert-deftest kuro-copy-mode-test-append-region-deactivates-mark ()
  "`kuro--copy-append-region' deactivates the mark after appending."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (let ((inhibit-read-only t))
      (insert "abcdef"))
    (let ((kill-ring nil))
      (goto-char (point-min))
      (set-mark (point-min))
      (forward-char 3)
      (kuro--copy-append-region)
      (should-not (region-active-p)))))

;;; ── Group N: kuro--copy-finalize + macro-generated commands ─────────────────

(ert-deftest kuro-copy-test-finalize-exits-copy-mode ()
  "`kuro--copy-finalize' calls `kuro-copy-mode' to exit copy mode."
  (kuro-el-test--with-kuro-mode-buffer
    (kuro--enter-copy-mode)
    (let ((exit-called nil))
      (cl-letf (((symbol-function 'kuro-copy-mode) (lambda () (setq exit-called t))))
        (kuro--copy-finalize)
        (should exit-called)))))

(ert-deftest kuro-copy-test-finalize-clears-linewise ()
  "`kuro--copy-finalize' resets `kuro--copy-linewise' to nil."
  (kuro-el-test--with-kuro-mode-buffer
    (setq kuro--copy-linewise t)
    (cl-letf (((symbol-function 'kuro-copy-mode) #'ignore))
      (kuro--copy-finalize)
      (should-not kuro--copy-linewise))))

(ert-deftest kuro-copy-test-finalize-cancel-rect ()
  "`kuro--copy-finalize' with non-nil CANCEL-RECT disables `rectangle-mark-mode'."
  (kuro-el-test--with-kuro-mode-buffer
    (let ((rect-disabled nil))
      (cl-letf (((symbol-function 'rectangle-mark-mode) (lambda (n) (when (= n -1) (setq rect-disabled t))))
                ((symbol-function 'kuro-copy-mode) #'ignore))
        (kuro--copy-finalize t)
        (should rect-disabled)))))

(ert-deftest kuro-copy-test-finalize-no-cancel-rect-by-default ()
  "`kuro--copy-finalize' with nil CANCEL-RECT does not call `rectangle-mark-mode'."
  (kuro-el-test--with-kuro-mode-buffer
    (let ((rect-called nil))
      (cl-letf (((symbol-function 'rectangle-mark-mode) (lambda (_) (setq rect-called t)))
                ((symbol-function 'kuro-copy-mode) #'ignore))
        (kuro--copy-finalize)
        (should-not rect-called)))))

(ert-deftest kuro-copy-test-move-to-top-is-command ()
  "`kuro--copy-move-to-top' is an interactive command (macro-generated)."
  (should (commandp #'kuro--copy-move-to-top)))

(ert-deftest kuro-copy-test-move-to-middle-is-command ()
  "`kuro--copy-move-to-middle' is an interactive command (macro-generated)."
  (should (commandp #'kuro--copy-move-to-middle)))

(ert-deftest kuro-copy-test-move-to-bottom-is-command ()
  "`kuro--copy-move-to-bottom' is an interactive command (macro-generated)."
  (should (commandp #'kuro--copy-move-to-bottom)))

(ert-deftest kuro-copy-test-search-forward-is-command ()
  "`kuro-search-forward' is an interactive command (macro-generated)."
  (should (commandp #'kuro-search-forward)))

(ert-deftest kuro-copy-test-search-backward-is-command ()
  "`kuro-search-backward' is an interactive command (macro-generated)."
  (should (commandp #'kuro-search-backward)))

(provide 'kuro-test)

(provide 'kuro-copy-mode-adv-test)
;;; kuro-copy-mode-adv-test.el ends here
