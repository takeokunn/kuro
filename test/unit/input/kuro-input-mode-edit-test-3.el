;;; kuro-input-mode-edit-test-3.el --- kuro-input-mode-edit-test (part 3)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-input-mode-test-support)

;;; Group 42 — kuro--line-unix-word-rubout (C-w)

(ert-deftest kuro-input-mode-test-unix-word-rubout-kills-last-word ()
  "`kuro--line-unix-word-rubout' kills from point back to the nearest whitespace."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-buffer "git push" kuro--line-point 8)
    (kuro--line-unix-word-rubout)
    (should (string= kuro--line-buffer "git "))
    (should (= kuro--line-point 4))))

(ert-deftest kuro-input-mode-test-unix-word-rubout-kills-path-with-hyphen ()
  "`kuro--line-unix-word-rubout' treats hyphens as part of the word (no split)."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-buffer "--verbose" kuro--line-point 9)
    (kuro--line-unix-word-rubout)
    (should (string= kuro--line-buffer ""))
    (should (= kuro--line-point 0))))

(ert-deftest kuro-input-mode-test-unix-word-rubout-skips-leading-whitespace ()
  "`kuro--line-unix-word-rubout' strips trailing whitespace before killing the word."
  (kuro-input-mode-test--with-edit
    (setq kuro--line-buffer "git  " kuro--line-point 5)
    (kuro--line-unix-word-rubout)
    (should (string= kuro--line-buffer ""))
    (should (= kuro--line-point 0))))

;;; Group 43 — kuro--def-line-word-case macro + upcase/downcase/capitalize

(ert-deftest kuro-input-mode-test-def-line-word-case-macroexpands-to-defun ()
  "`kuro--def-line-word-case' single-step expands to a `defun' with `(interactive)'."
  (let ((exp (macroexpand-1
              '(kuro--def-line-word-case kuro-test--wc-dummy "doc" (upcase (substring s start end))))))
    (should (eq (car exp) 'defun))
    (should (member '(interactive) (cddr exp)))))

(defconst kuro-input-mode-edit-test--word-case-table
  '((kuro-input-mode-test-upcase-word-upcases-next-word
     kuro--line-upcase-word "hello world" "HELLO world")
    (kuro-input-mode-test-downcase-word-downcases-next-word
     kuro--line-downcase-word "HELLO world" "hello world")
    (kuro-input-mode-test-capitalize-word-capitalizes-next-word
     kuro--line-capitalize-word "hello world" "Hello world"))
  "Table of (test-name fn initial expected) for word-case transform tests.")

(defmacro kuro-input-mode-edit-test--def-word-case (test-name fn initial expected)
  "Define a word-case transform test: call FN with INITIAL and assert EXPECTED."
  `(ert-deftest ,test-name ()
     ,(format "`%s' transforms \"%s\" → \"%s\" from point 0." fn initial expected)
     (kuro-input-mode-test--with-edit
       (setq kuro--line-buffer ,initial kuro--line-point 0)
       (,fn)
       (should (string= kuro--line-buffer ,expected)))))

(kuro-input-mode-edit-test--def-word-case
 kuro-input-mode-test-upcase-word-upcases-next-word
 kuro--line-upcase-word "hello world" "HELLO world")

(kuro-input-mode-edit-test--def-word-case
 kuro-input-mode-test-downcase-word-downcases-next-word
 kuro--line-downcase-word "HELLO world" "hello world")

(kuro-input-mode-edit-test--def-word-case
 kuro-input-mode-test-capitalize-word-capitalizes-next-word
 kuro--line-capitalize-word "hello world" "Hello world")

(ert-deftest kuro-input-mode-test-word-case-table-all-pass ()
  "Invariant: all entries in `kuro-input-mode-edit-test--word-case-table' transform correctly."
  (dolist (entry kuro-input-mode-edit-test--word-case-table)
    (pcase-let ((`(,_name ,fn ,initial ,expected) entry))
      (kuro-input-mode-test--with-edit
        (setq kuro--line-buffer initial kuro--line-point 0)
        (funcall fn)
        (should (string= kuro--line-buffer expected))))))

;;; Group 44 — kuro-line-edit-send / kuro-line-edit-discard edge cases

(ert-deftest kuro-input-mode-test-line-edit-send-errors-on-dead-source ()
  "`kuro-line-edit-send' signals `user-error' when the source buffer is dead."
  (let ((edit-buf (get-buffer-create "*kuro-edit-send-dead-test*")))
    (unwind-protect
        (with-current-buffer edit-buf
          (kuro-line-edit-mode)
          (insert "some text")
          (setq kuro--line-edit-source-buffer
                (let ((b (get-buffer-create "*kuro-dead-source*")))
                  (kill-buffer b)
                  b))
          (should-error (kuro-line-edit-send) :type 'user-error))
      (when (buffer-live-p edit-buf)
        (kill-buffer edit-buf)))))

(ert-deftest kuro-input-mode-test-line-edit-send-outside-edit-mode-errors ()
  "`kuro-line-edit-send' signals `user-error' when not in `kuro-line-edit-mode'."
  (with-temp-buffer
    (should-error (kuro-line-edit-send) :type 'user-error)))

(ert-deftest kuro-input-mode-test-line-edit-discard-dead-source-kills-buffer ()
  "`kuro-line-edit-discard' kills the edit buffer even when the source is dead."
  (let ((edit-buf (get-buffer-create "*kuro-edit-discard-dead-test*")))
    (unwind-protect
        (progn
          (with-current-buffer edit-buf
            (kuro-line-edit-mode)
            (setq kuro--line-edit-original "orig")
            (setq kuro--line-edit-source-buffer
                  (let ((b (get-buffer-create "*kuro-dead-src*")))
                    (kill-buffer b)
                    b))
            (cl-letf (((symbol-function 'message) #'ignore))
              (kuro-line-edit-discard)))
          (should-not (buffer-live-p edit-buf)))
      (when (buffer-live-p edit-buf)
        (kill-buffer edit-buf)))))

(ert-deftest kuro-input-mode-test-line-edit-discard-outside-edit-mode-ok ()
  "`kuro-line-edit-discard' runs even outside `kuro-line-edit-mode' — it kills the buffer."
  (let ((edit-buf (get-buffer-create "*kuro-edit-discard-mode-test*")))
    (unwind-protect
        (progn
          (with-current-buffer edit-buf
            (setq kuro--line-edit-original nil)
            (setq kuro--line-edit-source-buffer nil)
            (cl-letf (((symbol-function 'message) #'ignore))
              (kuro-line-edit-discard)))
          (should-not (buffer-live-p edit-buf)))
      (when (buffer-live-p edit-buf)
        (kill-buffer edit-buf)))))

(provide 'kuro-input-mode-edit-test-3)

;;; kuro-input-mode-edit-test-3.el ends here
