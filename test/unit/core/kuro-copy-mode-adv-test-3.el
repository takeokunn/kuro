;;; kuro-copy-mode-adv-test-3.el --- Copy-mode: find-prompt, window-move, search macros  -*-  lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-support)

;;; ── Group 26: kuro--copy-find-prompt ─────────────────────────────────────────

(ert-deftest kuro-copy-test-find-prompt-fwd-returns-next-position ()
  "`kuro--copy-find-prompt' with :fwd returns the first position strictly > point."
  (with-temp-buffer
    (insert (make-string 10 ?x))
    (goto-char 5)
    (cl-letf (((symbol-function 'kuro--prompt-overlay-positions)
               (lambda () '(2 7 12))))
      (should (= (kuro--copy-find-prompt :fwd) 7)))))

(ert-deftest kuro-copy-test-find-prompt-fwd-returns-nil-when-no-forward ()
  "`kuro--copy-find-prompt' with :fwd returns nil when point is past all prompts."
  (with-temp-buffer
    (insert (make-string 10 ?x))
    (goto-char 9)
    (cl-letf (((symbol-function 'kuro--prompt-overlay-positions)
               (lambda () '(2 5))))
      (should-not (kuro--copy-find-prompt :fwd)))))

(ert-deftest kuro-copy-test-find-prompt-bwd-returns-prev-position ()
  "`kuro--copy-find-prompt' with :bwd returns the last position strictly < point."
  (with-temp-buffer
    (insert (make-string 10 ?x))
    (goto-char 8)
    (cl-letf (((symbol-function 'kuro--prompt-overlay-positions)
               (lambda () '(3 6 10))))
      (should (= (kuro--copy-find-prompt :bwd) 6)))))

(ert-deftest kuro-copy-test-find-prompt-bwd-returns-nil-when-no-backward ()
  "`kuro--copy-find-prompt' with :bwd returns nil when point is before all prompts."
  (with-temp-buffer
    (insert (make-string 10 ?x))
    (goto-char 1)
    (cl-letf (((symbol-function 'kuro--prompt-overlay-positions)
               (lambda () '(5 9))))
      (should-not (kuro--copy-find-prompt :bwd)))))

;;; ── Group 34: kuro--def-copy-window-move structural (from adv-test) ──────────

(ert-deftest kuro-copy-test-def-copy-window-move-macroexpand-1-is-defun ()
  "`kuro--def-copy-window-move' single-step expands to a `defun' form."
  (let ((exp (macroexpand-1
              '(kuro--def-copy-window-move kuro-copy-test--wm-dummy 0 "doc"))))
    (should (eq (car exp) 'defun))
    (should (eq (cadr exp) 'kuro-copy-test--wm-dummy))))

(ert-deftest kuro-copy-test-def-copy-window-move-expansion-contains-move-call ()
  "`kuro--def-copy-window-move' expansion calls `move-to-window-line' with the given arg."
  (let ((exp (macroexpand-1
              '(kuro--def-copy-window-move kuro-copy-test--wm-dummy2 -1 "doc"))))
    (should (member '(move-to-window-line -1) (cddr exp)))))

;;; ── Group 35: kuro--def-copy-search behavioral tests ────────────────────────

(ert-deftest kuro-copy-test-def-copy-search-macroexpand-1-is-defun ()
  "`kuro--def-copy-search' single-step expands to a `defun' with `(interactive)'."
  (let ((exp (macroexpand-1
              '(kuro--def-copy-search kuro-copy-test--srch-dummy
                 search-forward isearch-forward (point-min) "doc"))))
    (should (eq (car exp) 'defun))
    (should (member '(interactive) (cddr exp)))))

(ert-deftest kuro-copy-test-search-next-calls-fallback-when-no-pattern ()
  "`kuro--copy-search-next' calls `isearch-forward' when `isearch-string' is empty."
  (let ((isearch-string "")
        (fallback-called nil))
    (cl-letf (((symbol-function 'isearch-forward)
               (lambda () (interactive) (setq fallback-called t))))
      (kuro--copy-search-next))
    (should fallback-called)))

(ert-deftest kuro-copy-test-search-next-moves-to-match ()
  "`kuro--copy-search-next' moves point to the next occurrence of `isearch-string'."
  (with-temp-buffer
    (insert "abc def abc")
    (goto-char (point-min))
    (let ((isearch-string "def"))
      (kuro--copy-search-next))
    (should (= (point) 8))))

(ert-deftest kuro-copy-test-search-next-messages-when-not-found ()
  "`kuro--copy-search-next' messages when the pattern is nowhere in the buffer."
  (with-temp-buffer
    (insert "abc def")
    (goto-char (point-min))
    (let ((isearch-string "xyz")
          (messaged nil))
      (cl-letf (((symbol-function 'message) (lambda (&rest _) (setq messaged t))))
        (kuro--copy-search-next))
      (should messaged))))

(ert-deftest kuro-copy-test-search-prev-calls-fallback-when-no-pattern ()
  "`kuro--copy-search-prev' calls `isearch-backward' when `isearch-string' is empty."
  (let ((isearch-string "")
        (fallback-called nil))
    (cl-letf (((symbol-function 'isearch-backward)
               (lambda () (interactive) (setq fallback-called t))))
      (kuro--copy-search-prev))
    (should fallback-called)))

(ert-deftest kuro-copy-test-search-prev-moves-to-match ()
  "`kuro--copy-search-prev' moves point backward to the previous occurrence."
  (with-temp-buffer
    (insert "abc def abc")
    (goto-char (point-max))
    (let ((isearch-string "abc"))
      (kuro--copy-search-prev))
    (should (= (point) 9))))

(ert-deftest kuro-copy-test-search-prev-messages-when-not-found ()
  "`kuro--copy-search-prev' messages when the pattern is nowhere in the buffer."
  (with-temp-buffer
    (insert "abc def")
    (goto-char (point-max))
    (let ((isearch-string "xyz")
          (messaged nil))
      (cl-letf (((symbol-function 'message) (lambda (&rest _) (setq messaged t))))
        (kuro--copy-search-prev))
      (should messaged))))

(ert-deftest kuro-copy-test-search-word-forward-messages-when-no-word ()
  "`kuro--copy-search-word-forward' messages when no word is at point."
  (with-temp-buffer
    (insert "   ")
    (goto-char (point-min))
    (let ((messaged nil))
      (cl-letf (((symbol-function 'message) (lambda (&rest _) (setq messaged t))))
        (kuro--copy-search-word-forward))
      (should messaged))))

(ert-deftest kuro-copy-test-search-word-forward-sets-isearch-string ()
  "`kuro--copy-search-word-forward' sets `isearch-string' to the word at point."
  (with-temp-buffer
    (insert "hello world")
    (goto-char (point-min))
    (let ((isearch-string nil))
      (cl-letf (((symbol-function 'kuro--copy-search-next) #'ignore))
        (kuro--copy-search-word-forward))
      (should (equal isearch-string "hello")))))

(provide 'kuro-copy-mode-adv-test-3)

;;; kuro-copy-mode-adv-test-3.el ends here
