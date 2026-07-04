;;; kuro-copy-mode-test.el --- ERT tests for kuro.el — copy-mode Groups 17-22  -*-  lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-support)

;;; ── Groups 17+19+20+21+22 (keymap): copy-mode key bindings ─────────────────

(defconst kuro-copy-mode-test--keymap-binding-table
  '(;; Group 17 — pager mnemonics (vi/less)
    (kuro-copy-mode-test-keymap-j-scroll-up-line      "j"   scroll-up-line)
    (kuro-copy-mode-test-keymap-k-scroll-down-line    "k"   scroll-down-line)
    (kuro-copy-mode-test-keymap-g-beginning-of-buffer "g"   beginning-of-buffer)
    (kuro-copy-mode-test-keymap-G-end-of-buffer       "G"   end-of-buffer)
    (kuro-copy-mode-test-keymap-b-scroll-down-command "b"   scroll-down-command)
    (kuro-copy-mode-test-keymap-f-scroll-up-command   "f"   scroll-up-command)
    (kuro-copy-mode-test-keymap-SPC-scroll-up-command "SPC" scroll-up-command)
    (kuro-copy-mode-test-keymap-q-exit-copy-mode      "q"   kuro-copy-mode)
    ;; Group 19 — region copy / mark
    (kuro-copy-mode-test-keymap-M-w-copy-region       "M-w" kuro--copy-copy-region-and-exit)
    (kuro-copy-mode-test-keymap-y-copy-region         "y"   kuro--copy-copy-region-and-exit)
    (kuro-copy-mode-test-keymap-v-set-mark            "v"   kuro--copy-set-mark)
    ;; Group 20 — vim char/word/line motions
    (kuro-copy-mode-test-keymap-h-backward-char       "h"   backward-char)
    (kuro-copy-mode-test-keymap-l-forward-char        "l"   forward-char)
    (kuro-copy-mode-test-keymap-w-forward-word        "w"   forward-word)
    (kuro-copy-mode-test-keymap-e-forward-word        "e"   forward-word)
    (kuro-copy-mode-test-keymap-B-backward-word       "B"   backward-word)
    (kuro-copy-mode-test-keymap-0-beginning-of-line   "0"   beginning-of-line)
    (kuro-copy-mode-test-keymap-dollar-end-of-line    "$"   end-of-line)
    (kuro-copy-mode-test-keymap-H-move-to-top         "H"   kuro--copy-move-to-top)
    (kuro-copy-mode-test-keymap-M-move-to-middle      "M"   kuro--copy-move-to-middle)
    (kuro-copy-mode-test-keymap-L-move-to-bottom      "L"   kuro--copy-move-to-bottom)
    ;; Group 21 — search-repeat bindings
    (kuro-copy-mode-test-keymap-n-search-next         "n"   kuro--copy-search-next)
    (kuro-copy-mode-test-keymap-N-search-prev         "N"   kuro--copy-search-prev)
    (kuro-copy-mode-test-keymap-star-search-word      "*"   kuro--copy-search-word-forward)
    ;; Group 22 — prompt overlay navigation
    (kuro-copy-mode-test-keymap-lbrace-goto-prev      "{"   kuro--copy-goto-prev-prompt)
    (kuro-copy-mode-test-keymap-rbrace-goto-next      "}"   kuro--copy-goto-next-prompt))
  "Table of (test-name key-str fn-symbol) for copy-mode keymap bindings.")

(defmacro kuro-copy-mode-test--def-keymap-binding (test-name key-str fn-symbol)
  `(ert-deftest ,test-name ()
     ,(format "Copy-mode keymap binds %S to `%s'." key-str fn-symbol)
     (kuro-el-test--with-kuro-mode-buffer
       (kuro--enter-copy-mode)
       (should (eq (lookup-key (current-local-map) (kbd ,key-str)) #',fn-symbol)))))

;; Group 17 — pager mnemonics
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-j-scroll-up-line      "j"   scroll-up-line)
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-k-scroll-down-line    "k"   scroll-down-line)
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-g-beginning-of-buffer "g"   beginning-of-buffer)
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-G-end-of-buffer       "G"   end-of-buffer)
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-b-scroll-down-command "b"   scroll-down-command)
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-f-scroll-up-command   "f"   scroll-up-command)
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-SPC-scroll-up-command "SPC" scroll-up-command)
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-q-exit-copy-mode      "q"   kuro-copy-mode)
;; Group 19 — region copy / mark
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-M-w-copy-region       "M-w" kuro--copy-copy-region-and-exit)
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-y-copy-region         "y"   kuro--copy-copy-region-and-exit)
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-v-set-mark            "v"   kuro--copy-set-mark)
;; Group 20 — vim motions
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-h-backward-char       "h"   backward-char)
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-l-forward-char        "l"   forward-char)
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-w-forward-word        "w"   forward-word)
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-e-forward-word        "e"   forward-word)
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-B-backward-word       "B"   backward-word)
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-0-beginning-of-line   "0"   beginning-of-line)
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-dollar-end-of-line    "$"   end-of-line)
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-H-move-to-top         "H"   kuro--copy-move-to-top)
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-M-move-to-middle      "M"   kuro--copy-move-to-middle)
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-L-move-to-bottom      "L"   kuro--copy-move-to-bottom)
;; Group 21 — search repeat
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-n-search-next         "n"   kuro--copy-search-next)
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-N-search-prev         "N"   kuro--copy-search-prev)
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-star-search-word      "*"   kuro--copy-search-word-forward)
;; Group 22 — prompt navigation
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-lbrace-goto-prev      "{"   kuro--copy-goto-prev-prompt)
(kuro-copy-mode-test--def-keymap-binding kuro-copy-mode-test-keymap-rbrace-goto-next      "}"   kuro--copy-goto-next-prompt)

(ert-deftest kuro-copy-mode-test-all-keymap-bindings-correct ()
  "Every entry in `kuro-copy-mode-test--keymap-binding-table' binds correctly."
  (dolist (entry kuro-copy-mode-test--keymap-binding-table)
    (pcase-let ((`(,_name ,key-str ,fn-sym) entry))
      (kuro-el-test--with-kuro-mode-buffer
        (kuro--enter-copy-mode)
        (should (eq (lookup-key (current-local-map) (kbd key-str)) fn-sym))))))

(ert-deftest kuro-copy-mode-test-production-bindings-have-valid-shape ()
  "`kuro--copy-mode-bindings' contains only key/command pairs."
  (dolist (binding kuro--copy-mode-bindings)
    (pcase-let ((`(,key . ,command) binding))
      (should (or (vectorp key) (stringp key)))
      (should (symbolp command)))))

(ert-deftest kuro-copy-mode-test-production-bindings-are-installed ()
  "Every production copy-mode binding is present in `kuro--copy-mode-map'."
  (dolist (binding kuro--copy-mode-bindings)
    (pcase-let ((`(,key . ,command) binding))
      (kuro-el-test--with-kuro-mode-buffer
        (kuro--enter-copy-mode)
        (should (eq (lookup-key (current-local-map)
                                (if (vectorp key) key (kbd key)))
                    command))))))

;;; ── Groups 19+20 (commandp): interactive command assertions ─────────────────

(defconst kuro-copy-mode-test--commandp-table
  '((kuro-copy-mode-test-set-mark-is-interactive        kuro--copy-set-mark)
    (kuro-copy-mode-test-move-to-top-is-interactive    kuro--copy-move-to-top)
    (kuro-copy-mode-test-move-to-middle-is-interactive kuro--copy-move-to-middle)
    (kuro-copy-mode-test-move-to-bottom-is-interactive kuro--copy-move-to-bottom))
  "Table of (test-name fn-symbol) for copy-mode commandp checks.")

(defmacro kuro-copy-mode-test--def-commandp (test-name fn-symbol)
  `(ert-deftest ,test-name ()
     ,(format "`%s' is an interactive command." fn-symbol)
     (should (commandp #',fn-symbol))))

(kuro-copy-mode-test--def-commandp kuro-copy-mode-test-set-mark-is-interactive        kuro--copy-set-mark)
(kuro-copy-mode-test--def-commandp kuro-copy-mode-test-move-to-top-is-interactive    kuro--copy-move-to-top)
(kuro-copy-mode-test--def-commandp kuro-copy-mode-test-move-to-middle-is-interactive kuro--copy-move-to-middle)
(kuro-copy-mode-test--def-commandp kuro-copy-mode-test-move-to-bottom-is-interactive kuro--copy-move-to-bottom)

(ert-deftest kuro-copy-mode-test-all-window-nav-commands-interactive ()
  "Every entry in `kuro-copy-mode-test--commandp-table' is an interactive command."
  (dolist (entry kuro-copy-mode-test--commandp-table)
    (pcase-let ((`(,_name ,fn-sym) entry))
      (should (commandp fn-sym)))))

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

;;; ── Group 21: copy-mode n/N/* vim search repeat ──────────────────────────────

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

(provide 'kuro-copy-mode-test)
;;; kuro-copy-mode-test.el ends here
