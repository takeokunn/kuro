;;; kuro-input-ext3-test.el --- Unit tests for kuro-input.el (Groups 10-17)  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-input.el (key sequence encoding, mouse encoding,
;; bracketed paste, yank).
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;; All kuro--send-key calls are intercepted with cl-letf stubs.
;;
;; This file contains Groups 10-17 (keymap bindings, ctrl/meta byte sending,
;; send-special, self-insert, ctrl-alt-modified).
;; Groups 1-9 are in kuro-input-test.el.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-input)

;; Ensure kuro--keymap is populated before Groups 10-13 run their lookup-key tests.
;; kuro--keymap is nil until kuro--build-keymap is called explicitly; the keymap
;; is not built at require time (it is normally built during kuro-mode activation).
(when (fboundp 'kuro--build-keymap)
  (kuro--build-keymap))

;;; Helper

(defmacro kuro-input-test--capture-sent (&rest body)
  "Execute BODY with kuro--send-key stubbed; return list of sent strings."
  `(let ((sent nil)
         (kuro--initialized t))
     (cl-letf (((symbol-function 'kuro--send-key)
                (lambda (s) (push s sent))))
       ,@body)
     (nreverse sent)))

;;; Group 10: Regression — Ctrl+letter keybindings are registered with correct descriptors
;;
;; Root cause of the C-b/C-f/C-e bug:
;;   (vector (list 'control ?b)) is NOT equivalent to (kbd "C-b") in GUI Emacs.
;;   The vector form is invisible to the event dispatcher; global-map bindings
;;   (backward-char, forward-char, etc.) win instead.  We must use (kbd "C-x")
;;   descriptors.  These tests verify that lookup-key on kuro--keymap resolves
;;   every critical Ctrl+letter to a non-nil (our PTY-forwarding) binding.
;;
;; Note: keys in `kuro-keymap-exceptions' (default: C-c C-x C-u C-g C-h C-l
;;   M-x M-o C-y M-y) are intentionally NOT bound in kuro--keymap so they fall
;;   through to the Emacs global keymap.  The tests below reflect this.

(defun kuro-input-test--keymap-bound-p (key)
  "Return non-nil if KEY is bound in kuro--keymap."
  (let ((binding (lookup-key kuro--keymap (kbd key))))
    (and binding (not (numberp binding)))))  ; numberp = key sequence prefix

(defmacro kuro-input-test--with-empty-exceptions (&rest body)
  "Run BODY with `kuro--keymap' temporarily rebuilt without any exceptions.
Saves and restores `kuro--keymap' via `unwind-protect' (which wraps the
build call too) so the test leaves the global keymap in its original state
regardless of whether the build or BODY signals an error."
  `(let ((orig-keymap kuro--keymap))
     (unwind-protect
         (progn
           ;; Rebuild inside a nested let so kuro-keymap-exceptions reverts
           ;; after the let exits, before unwind-protect cleanup runs.
           (let ((kuro-keymap-exceptions nil))
             (kuro--build-keymap))
           ,@body)
       ;; Restore the original keymap directly.
       (setq kuro--keymap orig-keymap))))

(ert-deftest kuro-input-keymap-c-a-bound ()
  "C-a (readline: beginning-of-line) is bound in kuro--keymap."
  (should (kuro-input-test--keymap-bound-p "C-a")))

(ert-deftest kuro-input-keymap-c-b-bound ()
  "C-b (readline: backward-char) is bound in kuro--keymap.
Regression: was missing, causing global-map backward-char to shadow it."
  (should (kuro-input-test--keymap-bound-p "C-b")))

(ert-deftest kuro-input-keymap-c-d-bound ()
  "C-d (readline: delete-char / EOF) is bound in kuro--keymap."
  (should (kuro-input-test--keymap-bound-p "C-d")))

(ert-deftest kuro-input-keymap-c-e-bound ()
  "C-e (readline: end-of-line) is bound in kuro--keymap.
Regression: was missing, causing C-e to have no effect in bash."
  (should (kuro-input-test--keymap-bound-p "C-e")))

(ert-deftest kuro-input-keymap-c-f-bound ()
  "C-f (readline: forward-char) is bound in kuro--keymap.
Regression: was missing, causing global-map forward-char to shadow it."
  (should (kuro-input-test--keymap-bound-p "C-f")))

(ert-deftest kuro-input-keymap-c-k-bound ()
  "C-k (readline: kill-line) is bound in kuro--keymap."
  (should (kuro-input-test--keymap-bound-p "C-k")))

(ert-deftest kuro-input-keymap-c-l-not-bound-by-default ()
  "C-l is NOT bound in kuro--keymap by default (it is in kuro-keymap-exceptions).
C-l falls through to the Emacs global keymap (recenter-top-bottom)."
  (should-not (kuro-input-test--keymap-bound-p "C-l")))

(ert-deftest kuro-input-keymap-c-l-bound-without-exceptions ()
  "C-l IS bound in kuro--keymap when kuro-keymap-exceptions is empty."
  (kuro-input-test--with-empty-exceptions
   (should (kuro-input-test--keymap-bound-p "C-l"))))

(ert-deftest kuro-input-keymap-c-n-bound ()
  "C-n (readline: next-history) is bound in kuro--keymap."
  (should (kuro-input-test--keymap-bound-p "C-n")))

(ert-deftest kuro-input-keymap-c-p-bound ()
  "C-p (readline: previous-history) is bound in kuro--keymap."
  (should (kuro-input-test--keymap-bound-p "C-p")))

(ert-deftest kuro-input-keymap-c-r-bound ()
  "C-r (readline: reverse-search-history) is bound in kuro--keymap."
  (should (kuro-input-test--keymap-bound-p "C-r")))

(ert-deftest kuro-input-keymap-c-s-bound ()
  "C-s (readline: forward-search-history) is bound in kuro--keymap."
  (should (kuro-input-test--keymap-bound-p "C-s")))

(ert-deftest kuro-input-keymap-c-t-bound ()
  "C-t (readline: transpose-chars) is bound in kuro--keymap."
  (should (kuro-input-test--keymap-bound-p "C-t")))

(ert-deftest kuro-input-keymap-c-u-not-bound-by-default ()
  "C-u is NOT bound in kuro--keymap by default (it is in kuro-keymap-exceptions).
C-u falls through to the Emacs global keymap (universal-argument)."
  (should-not (kuro-input-test--keymap-bound-p "C-u")))

(ert-deftest kuro-input-keymap-c-u-bound-without-exceptions ()
  "C-u IS bound in kuro--keymap when kuro-keymap-exceptions is empty."
  (kuro-input-test--with-empty-exceptions
   (should (kuro-input-test--keymap-bound-p "C-u"))))

(ert-deftest kuro-input-keymap-c-w-bound ()
  "C-w (readline: unix-word-rubout) is bound in kuro--keymap."
  (should (kuro-input-test--keymap-bound-p "C-w")))

(ert-deftest kuro-input-keymap-c-x-not-bound-by-default ()
  "C-x is NOT bound in kuro--keymap by default (it is in kuro-keymap-exceptions).
C-x falls through to the Emacs global keymap (C-x prefix)."
  (should-not (kuro-input-test--keymap-bound-p "C-x")))

(ert-deftest kuro-input-keymap-c-x-bound-without-exceptions ()
  "C-x IS bound in kuro--keymap when kuro-keymap-exceptions is empty."
  (kuro-input-test--with-empty-exceptions
   (should (kuro-input-test--keymap-bound-p "C-x"))))

(ert-deftest kuro-input-keymap-c-z-bound ()
  "C-z (SIGTSTP) is bound in kuro--keymap."
  (should (kuro-input-test--keymap-bound-p "C-z")))

(ert-deftest kuro-input-keymap-m-x-not-bound-by-default ()
  "M-x is NOT bound in kuro--keymap by default (it is in kuro-keymap-exceptions).
M-x falls through to execute-extended-command."
  (should-not (kuro-input-test--keymap-bound-p "M-x")))

(ert-deftest kuro-input-keymap-m-x-bound-without-exceptions ()
  "M-x IS bound (sends ESC+x to PTY) when kuro-keymap-exceptions is empty."
  (kuro-input-test--with-empty-exceptions
   (should (kuro-input-test--keymap-bound-p "M-x"))))

;;; Group 11: Regression — Alt/Meta keybindings use correct (kbd) descriptors
;;
;; (vector (list 'meta ?b)) is NOT equivalent to (kbd "M-b") in GUI Emacs.

(ert-deftest kuro-input-keymap-m-b-bound ()
  "M-b (readline: backward-word) is bound in kuro--keymap."
  (should (kuro-input-test--keymap-bound-p "M-b")))

(ert-deftest kuro-input-keymap-m-f-bound ()
  "M-f (readline: forward-word) is bound in kuro--keymap."
  (should (kuro-input-test--keymap-bound-p "M-f")))

(ert-deftest kuro-input-keymap-m-d-bound ()
  "M-d (readline: delete-word) is bound in kuro--keymap."
  (should (kuro-input-test--keymap-bound-p "M-d")))

(ert-deftest kuro-input-keymap-m-dot-bound ()
  "M-. (readline: yank-last-arg) is bound in kuro--keymap."
  (should (kuro-input-test--keymap-bound-p "M-.")))

(ert-deftest kuro-input-keymap-m-r-bound ()
  "M-r (readline: revert-line) is bound in kuro--keymap."
  (should (kuro-input-test--keymap-bound-p "M-r")))

(ert-deftest kuro-input-keymap-m-u-bound ()
  "M-u (readline: upcase-word) is bound in kuro--keymap."
  (should (kuro-input-test--keymap-bound-p "M-u")))

;;; Group 12: Ctrl+letter sends correct control bytes to PTY
;;
;; Keys that are in kuro-keymap-exceptions by default (C-l=12, C-u=21) are
;; tested using kuro-input-test--with-empty-exceptions so the binding exists.

(defmacro kuro-input-test--ctrl-sends (key expected-byte)
  "Assert that KEY (kbd string) in kuro--keymap sends EXPECTED-BYTE to the PTY."
  `(ert-deftest ,(intern (format "kuro-input-ctrl-%d-sends-byte" expected-byte)) ()
     ,(format "Pressing %s sends control byte %d (^%c) to the PTY." key expected-byte
              (+ expected-byte 64))
     (let* ((binding (lookup-key kuro--keymap (kbd ,key)))
            (sent nil))
       (should (functionp binding))
       (cl-letf (((symbol-function 'kuro--send-key)
                  (lambda (s) (push s sent)))
                 ((symbol-function 'kuro--schedule-immediate-render)
                  (lambda () nil)))
         (funcall binding))
       (should (equal sent (list (string ,expected-byte)))))))

(defmacro kuro-input-test--ctrl-sends-no-exc (key expected-byte)
  "Like `kuro-input-test--ctrl-sends' but runs with empty exceptions."
  `(ert-deftest ,(intern (format "kuro-input-ctrl-%d-sends-byte-no-exc" expected-byte)) ()
     ,(format "Pressing %s sends control byte %d (^%c) to PTY (exceptions cleared)."
              key expected-byte (+ expected-byte 64))
     (kuro-input-test--with-empty-exceptions
      (let* ((binding (lookup-key kuro--keymap (kbd ,key)))
             (sent nil))
        (should (functionp binding))
        (cl-letf (((symbol-function 'kuro--send-key)
                   (lambda (s) (push s sent)))
                  ((symbol-function 'kuro--schedule-immediate-render)
                   (lambda () nil)))
          (funcall binding))
        (should (equal sent (list (string ,expected-byte))))))))

(kuro-input-test--ctrl-sends "C-a" 1)
(kuro-input-test--ctrl-sends "C-b" 2)
(kuro-input-test--ctrl-sends "C-d" 4)
(kuro-input-test--ctrl-sends "C-e" 5)
(kuro-input-test--ctrl-sends "C-f" 6)
(kuro-input-test--ctrl-sends "C-k" 11)
;; C-l (12) is in kuro-keymap-exceptions by default; test with empty exceptions.
(kuro-input-test--ctrl-sends-no-exc "C-l" 12)
(kuro-input-test--ctrl-sends "C-n" 14)
(kuro-input-test--ctrl-sends "C-p" 16)
(kuro-input-test--ctrl-sends "C-r" 18)
(kuro-input-test--ctrl-sends "C-t" 20)
;; C-u (21) is in kuro-keymap-exceptions by default; test with empty exceptions.
(kuro-input-test--ctrl-sends-no-exc "C-u" 21)
(kuro-input-test--ctrl-sends "C-w" 23)
(kuro-input-test--ctrl-sends "C-z" 26)

;;; Group 13: Alt+letter sends correct ESC+char sequences to PTY

(defmacro kuro-input-test--meta-sends (key expected-char)
  "Assert that KEY (kbd string) in kuro--keymap sends ESC+EXPECTED-CHAR to PTY."
  `(ert-deftest ,(intern (format "kuro-input-meta-%c-sends-esc-seq" expected-char)) ()
     ,(format "Pressing %s sends ESC + %c (readline Alt prefix) to the PTY." key expected-char)
     (let* ((binding (lookup-key kuro--keymap (kbd ,key)))
            (sent nil))
       (should (functionp binding))
       (cl-letf (((symbol-function 'kuro--send-key)
                  (lambda (s) (push s sent)))
                 ((symbol-function 'kuro--schedule-immediate-render)
                  (lambda () nil)))
         (funcall binding))
       (should (equal sent (list (string ?\e ,expected-char)))))))

(kuro-input-test--meta-sends "M-b" ?b)
(kuro-input-test--meta-sends "M-f" ?f)
(kuro-input-test--meta-sends "M-d" ?d)
(kuro-input-test--meta-sends "M-r" ?r)
(kuro-input-test--meta-sends "M-u" ?u)
(kuro-input-test--meta-sends "M-l" ?l)

;;; Group 14: kuro--send-meta-backspace sends correct ESC+DEL sequence

(ert-deftest kuro-send-meta-backspace-sends-correct-sequence ()
  "kuro--send-meta-backspace sends ESC+DEL (readline backward-kill-word)."
  (let ((sent nil))
    (cl-letf (((symbol-function 'kuro--send-key)
               (lambda (key) (push key sent)))
              ((symbol-function 'kuro--schedule-immediate-render)
               (lambda () nil)))
      (kuro--send-meta-backspace)
      (should (equal sent (list (string ?\e ?\x7f)))))))

;;; Group 15: kuro--send-special

(ert-deftest kuro-input-send-special-sends-byte ()
  "kuro--send-special sends the given byte as a single-char string to the PTY."
  (let ((sent (kuro-input-test--capture-sent
               (kuro--send-special ?\C-c))))
    (should (equal sent (list (string ?\C-c))))))

(ert-deftest kuro-input-send-special-sends-escape ()
  "kuro--send-special sends ESC (0x1B) correctly."
  (let ((sent (kuro-input-test--capture-sent
               (kuro--send-special ?\e))))
    (should (equal sent (list (string ?\e))))))

(ert-deftest kuro-input-send-special-delegates-to-send-key-regardless-of-init ()
  "kuro--send-special always delegates to kuro--send-key regardless of kuro--initialized."
  (let ((sent nil)
        (kuro--initialized nil))
    (cl-letf (((symbol-function 'kuro--send-key)
               (lambda (s) (push s sent)))
              ((symbol-function 'kuro--schedule-immediate-render)
               (lambda () nil)))
      ;; kuro--send-special does not guard on kuro--initialized itself;
      ;; the guard is inside kuro--send-key (the real FFI wrapper).
      ;; We verify the byte is still passed through to kuro--send-key
      ;; (the guard is in the stub layer, not in kuro--send-special).
      ;; This test confirms kuro--send-special always calls kuro--send-key.
      (kuro--send-special ?a)
      (should (equal sent (list (string ?a)))))))

;;; Group 16: kuro--self-insert

(ert-deftest kuro-input-self-insert-sends-char ()
  "kuro--self-insert sends last-command-event as a UTF-8 string."
  (let ((last-command-event ?a))
    (let ((sent (kuro-input-test--capture-sent
                 (kuro--self-insert))))
      (should (equal sent (list "a"))))))

(ert-deftest kuro-input-self-insert-sends-space ()
  "kuro--self-insert sends SPC correctly."
  (let ((last-command-event ?\s))
    (let ((sent (kuro-input-test--capture-sent
                 (kuro--self-insert))))
      (should (equal sent (list " "))))))

(ert-deftest kuro-input-self-insert-sends-multibyte-char ()
  "kuro--self-insert sends a multibyte (non-ASCII) character."
  (let ((last-command-event ?あ))
    (let ((sent (kuro-input-test--capture-sent
                 (kuro--self-insert))))
      (should (equal sent (list (string ?あ)))))))

(ert-deftest kuro-input-self-insert-noop-for-non-character ()
  "kuro--self-insert is a no-op when last-command-event is not a character."
  (let ((last-command-event 'mouse-1))
    (let ((sent (kuro-input-test--capture-sent
                 (kuro--self-insert))))
      (should (null sent)))))

;;; Group 17: kuro--ctrl-alt-modified

(ert-deftest kuro-input-ctrl-alt-modified-sends-esc-ctrl-byte ()
  "kuro--ctrl-alt-modified sends ESC followed by the ctrl byte (char & 31)."
  ;; char=?a (97), 97 & 31 = 1 (^A), so sequence is ESC + ^A
  (let ((sent (kuro-input-test--capture-sent
               (kuro--ctrl-alt-modified ?a 0))))
    (should (equal sent (list (concat (string ?\e) (string (logand ?a 31))))))))

(ert-deftest kuro-input-ctrl-alt-modified-sends-esc-ctrl-c ()
  "kuro--ctrl-alt-modified for 'c' sends ESC + ^C (Ctrl+C = 3)."
  (let ((sent (kuro-input-test--capture-sent
               (kuro--ctrl-alt-modified ?c 0))))
    (should (equal sent (list (string ?\e ?\C-c))))))

(ert-deftest kuro-input-ctrl-alt-modified-ignores-modifier-arg ()
  "kuro--ctrl-alt-modified ignores the MODIFIER argument (always ESC+ctrl-byte)."
  (let ((sent-no-mod (kuro-input-test--capture-sent
                      (kuro--ctrl-alt-modified ?b 0)))
        (sent-with-mod (kuro-input-test--capture-sent
                        (kuro--ctrl-alt-modified ?b 7))))
    (should (equal sent-no-mod sent-with-mod))))

(provide 'kuro-input-ext3-test)

;;; kuro-input-ext3-test.el ends here
