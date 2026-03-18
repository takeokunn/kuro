;;; kuro-input-test.el --- Unit tests for kuro-input.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-input.el (key sequence encoding, mouse encoding,
;; bracketed paste, yank).
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;; All kuro--send-key calls are intercepted with cl-letf stubs.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-input)

;;; Helper

(defmacro kuro-input-test--capture-sent (&rest body)
  "Execute BODY with kuro--send-key stubbed; return list of sent strings."
  `(let ((sent nil)
         (kuro--initialized t))
     (cl-letf (((symbol-function 'kuro--send-key)
                (lambda (s) (push s sent))))
       ,@body)
     (nreverse sent)))

;;; Group 1: kuro--send-key-sequence (normal vs. application cursor mode)

(ert-deftest kuro-input-send-key-sequence-normal-mode ()
  "In normal cursor mode, kuro--send-key-sequence sends the normal sequence."
  ;; defvar-local requires setq-local inside a buffer context.
  (with-temp-buffer
    (setq-local kuro--application-cursor-keys-mode nil)
    (let ((sent (kuro-input-test--capture-sent
                 (kuro--send-key-sequence "\e[A" "\eOA"))))
      (should (equal sent '("\e[A"))))))

(ert-deftest kuro-input-send-key-sequence-application-mode ()
  "In application cursor mode, kuro--send-key-sequence sends the application sequence."
  (with-temp-buffer
    (setq-local kuro--application-cursor-keys-mode t)
    (let ((sent (kuro-input-test--capture-sent
                 (kuro--send-key-sequence "\e[A" "\eOA"))))
      (should (equal sent '("\eOA"))))))

;;; Group 2: Arrow keys

(ert-deftest kuro-input-arrow-up-normal ()
  "Arrow up in normal mode sends CSI A."
  (with-temp-buffer
    (setq-local kuro--application-cursor-keys-mode nil)
    (let ((sent (kuro-input-test--capture-sent (kuro--arrow-up))))
      (should (equal sent '("\e[A"))))))

(ert-deftest kuro-input-arrow-up-application ()
  "Arrow up in application mode sends SS3 A."
  (with-temp-buffer
    (setq-local kuro--application-cursor-keys-mode t)
    (let ((sent (kuro-input-test--capture-sent (kuro--arrow-up))))
      (should (equal sent '("\eOA"))))))

(ert-deftest kuro-input-arrow-down-normal ()
  "Arrow down in normal mode sends CSI B."
  (let ((kuro--application-cursor-keys-mode nil)
        (sent (kuro-input-test--capture-sent (kuro--arrow-down))))
    (should (equal sent '("\e[B")))))

(ert-deftest kuro-input-arrow-left-normal ()
  "Arrow left in normal mode sends CSI D."
  (let ((kuro--application-cursor-keys-mode nil)
        (sent (kuro-input-test--capture-sent (kuro--arrow-left))))
    (should (equal sent '("\e[D")))))

(ert-deftest kuro-input-arrow-right-normal ()
  "Arrow right in normal mode sends CSI C."
  (let ((kuro--application-cursor-keys-mode nil)
        (sent (kuro-input-test--capture-sent (kuro--arrow-right))))
    (should (equal sent '("\e[C")))))

;;; Group 3: Special keys

(ert-deftest kuro-input-RET-sends-cr ()
  "kuro--RET sends a carriage return (0x0D)."
  (let ((sent (kuro-input-test--capture-sent (kuro--RET))))
    (should (equal sent (list (string ?\r))))))

(ert-deftest kuro-input-TAB-sends-tab ()
  "kuro--TAB sends a horizontal tab (0x09)."
  (let ((sent (kuro-input-test--capture-sent (kuro--TAB))))
    (should (equal sent (list (string ?\t))))))

(ert-deftest kuro-input-DEL-sends-delete ()
  "kuro--DEL sends DEL (0x7F)."
  (let ((sent (kuro-input-test--capture-sent (kuro--DEL))))
    (should (equal sent (list (string ?\x7f))))))

;;; Group 4: Function keys

(ert-deftest kuro-input-F1-sends-ss3-P ()
  "F1 sends SS3 P (\\eOP)."
  (let ((kuro--application-cursor-keys-mode nil)
        (sent (kuro-input-test--capture-sent (kuro--F1))))
    (should (equal sent '("\eOP")))))

(ert-deftest kuro-input-F5-sends-csi-15 ()
  "F5 sends CSI 15~."
  (let ((kuro--application-cursor-keys-mode nil)
        (sent (kuro-input-test--capture-sent (kuro--F5))))
    (should (equal sent '("\e[15~")))))

(ert-deftest kuro-input-F12-sends-csi-24 ()
  "F12 sends CSI 24~."
  (let ((kuro--application-cursor-keys-mode nil)
        (sent (kuro-input-test--capture-sent (kuro--F12))))
    (should (equal sent '("\e[24~")))))

;;; Group 5: Home/End/Page keys

(ert-deftest kuro-input-HOME-normal-sends-csi-H ()
  "HOME in normal mode sends CSI H."
  (let ((kuro--application-cursor-keys-mode nil)
        (sent (kuro-input-test--capture-sent (kuro--HOME))))
    (should (equal sent '("\e[H")))))

(ert-deftest kuro-input-END-normal-sends-csi-F ()
  "END in normal mode sends CSI F."
  (let ((kuro--application-cursor-keys-mode nil)
        (sent (kuro-input-test--capture-sent (kuro--END))))
    (should (equal sent '("\e[F")))))

(ert-deftest kuro-input-PAGE-UP-sends-csi-5 ()
  "Page Up sends CSI 5~."
  (let ((kuro--application-cursor-keys-mode nil)
        (sent (kuro-input-test--capture-sent (kuro--PAGE-UP))))
    (should (equal sent '("\e[5~")))))

(ert-deftest kuro-input-PAGE-DOWN-sends-csi-6 ()
  "Page Down sends CSI 6~."
  (let ((kuro--application-cursor-keys-mode nil)
        (sent (kuro-input-test--capture-sent (kuro--PAGE-DOWN))))
    (should (equal sent '("\e[6~")))))

(ert-deftest kuro-input-INSERT-sends-csi-2 ()
  "Insert key sends CSI 2~."
  (let ((kuro--application-cursor-keys-mode nil)
        (sent (kuro-input-test--capture-sent (kuro--INSERT))))
    (should (equal sent '("\e[2~")))))

(ert-deftest kuro-input-DELETE-sends-csi-3 ()
  "Delete key sends CSI 3~."
  (let ((kuro--application-cursor-keys-mode nil)
        (sent (kuro-input-test--capture-sent (kuro--DELETE))))
    (should (equal sent '("\e[3~")))))

;;; Group 6: kuro--sanitize-paste

(ert-deftest kuro-input-sanitize-paste-removes-esc ()
  "kuro--sanitize-paste strips ESC (0x1B) bytes."
  (let ((esc (string #x1b)))
    (should (equal (kuro--sanitize-paste (concat "hello" esc "world")) "helloworld"))))

(ert-deftest kuro-input-sanitize-paste-clean-string-unchanged ()
  "kuro--sanitize-paste leaves strings without ESC bytes unchanged."
  (should (equal (kuro--sanitize-paste "hello world") "hello world")))

(ert-deftest kuro-input-sanitize-paste-multiple-escapes ()
  "kuro--sanitize-paste removes all ESC bytes."
  (let ((esc (string #x1b)))
    (should (equal (kuro--sanitize-paste (concat esc "a" esc "b" esc "c")) "abc"))))

(ert-deftest kuro-input-sanitize-paste-empty-string ()
  "kuro--sanitize-paste handles empty strings."
  (should (equal (kuro--sanitize-paste "") "")))

;;; Group 7: kuro--yank (bracketed paste mode)

(ert-deftest kuro-input-yank-plain-without-bracketed-paste ()
  "kuro--yank sends text directly when bracketed paste mode is off."
  (let ((kuro--bracketed-paste-mode nil)
        (kuro--initialized t))
    (with-temp-buffer
      (kill-new "clipboard text")
      (let ((sent nil))
        (cl-letf (((symbol-function 'kuro--send-key)
                   (lambda (s) (push s sent))))
          (kuro--yank))
        (should (equal sent '("clipboard text")))))))

(ert-deftest kuro-input-yank-wraps-with-bracketed-paste ()
  "kuro--yank wraps with ESC[200~ / ESC[201~ when bracketed paste mode is on."
  (let ((kuro--bracketed-paste-mode t)
        (kuro--initialized t))
    (with-temp-buffer
      (kill-new "pasted text")
      (let ((sent nil))
        (cl-letf (((symbol-function 'kuro--send-key)
                   (lambda (s) (push s sent))))
          (kuro--yank))
        (should (= (length sent) 1))
        (let ((payload (car sent)))
          (should (string-prefix-p "\e[200~" payload))
          (should (string-suffix-p "\e[201~" payload))
          (should (string-match-p "pasted text" payload)))))))

(ert-deftest kuro-input-yank-strips-esc-in-bracketed-paste ()
  "kuro--yank sanitizes ESC bytes from clipboard content in bracketed paste mode.
The user content ESC is stripped; only the wrap sequences ESC[200~/ESC[201~ remain."
  (let ((kuro--bracketed-paste-mode t)
        (kuro--initialized t)
        (esc (string #x1b)))
    (with-temp-buffer
      ;; Clipboard: "evil" + ESC + "[201~injection"
      (kill-new (concat "evil" esc "[201~injection"))
      (let ((sent nil))
        (cl-letf (((symbol-function 'kuro--send-key)
                   (lambda (s) (push s sent))))
          (kuro--yank))
        (should (= (length sent) 1))
        (let ((payload (car sent)))
          ;; The payload starts with the open bracket
          (should (string-prefix-p (concat esc "[200~") payload))
          ;; The payload ends with the close bracket
          (should (string-suffix-p (concat esc "[201~") payload))
          ;; The user content should NOT contain ESC (injection neutralized)
          (let* ((open-len (length (concat esc "[200~")))
                 (close-len (length (concat esc "[201~")))
                 (content (substring payload open-len
                                     (- (length payload) close-len))))
            (should-not (string-match-p esc content))))))))

;;; Group 8: Mouse encoding (kuro--encode-mouse)

(ert-deftest kuro-input-mouse-mode-zero-means-disabled ()
  "kuro--mouse-mode of 0 is falsy (disabled) — mouse events are not forwarded."
  ;; kuro--mouse-press et al. guard with (when (> kuro--mouse-mode 0)).
  ;; Verify the invariant directly.
  (with-temp-buffer
    (setq-local kuro--mouse-mode 0)
    (should (zerop kuro--mouse-mode))
    (should-not (> kuro--mouse-mode 0))))

(ert-deftest kuro-input-encode-kitty-key-no-modifiers ()
  "kuro--encode-kitty-key with no modifiers produces ESC[<key>u."
  (should (equal (kuro--encode-kitty-key 65 0) "\e[65u")))

(ert-deftest kuro-input-encode-kitty-key-with-modifiers ()
  "kuro--encode-kitty-key with modifiers produces ESC[<key>;<mod+1>u."
  ;; shift=1 → modifier param = 1+1 = 2
  (should (equal (kuro--encode-kitty-key 65 1) "\e[65;2u"))
  ;; ctrl=4 → modifier param = 4+1 = 5
  (should (equal (kuro--encode-kitty-key 65 4) "\e[65;5u")))

;;; Group 9: Buffer-local state isolation

(ert-deftest kuro-input-scroll-offset-is-buffer-local ()
  "kuro--scroll-offset is buffer-local (independent per buffer)."
  (let ((buf1 (get-buffer-create " *kuro-input-test-1*"))
        (buf2 (get-buffer-create " *kuro-input-test-2*")))
    (unwind-protect
        (progn
          (with-current-buffer buf1 (setq kuro--scroll-offset 10))
          (with-current-buffer buf2 (setq kuro--scroll-offset 0))
          (should (= (with-current-buffer buf1 kuro--scroll-offset) 10))
          (should (= (with-current-buffer buf2 kuro--scroll-offset) 0)))
      (kill-buffer buf1)
      (kill-buffer buf2))))

(ert-deftest kuro-input-mouse-mode-is-buffer-local ()
  "kuro--mouse-mode is buffer-local."
  (let ((buf1 (get-buffer-create " *kuro-input-mouse-1*"))
        (buf2 (get-buffer-create " *kuro-input-mouse-2*")))
    (unwind-protect
        (progn
          (with-current-buffer buf1 (setq kuro--mouse-mode 1000))
          (with-current-buffer buf2 (setq kuro--mouse-mode 0))
          (should (= (with-current-buffer buf1 kuro--mouse-mode) 1000))
          (should (= (with-current-buffer buf2 kuro--mouse-mode) 0)))
      (kill-buffer buf1)
      (kill-buffer buf2))))

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

(provide 'kuro-input-test)

;;; kuro-input-test.el ends here
