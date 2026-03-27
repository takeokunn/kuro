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
  (let ((kill-ring nil)
        (kuro--bracketed-paste-mode nil)
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
  (let ((kill-ring nil)
        (kuro--bracketed-paste-mode t)
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
  (let ((kill-ring nil)
        (kuro--bracketed-paste-mode t)
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

;;; Group 18: kuro-scroll-up / kuro-scroll-down / kuro-scroll-bottom

(defmacro kuro-input-test--with-scroll-stubs (scroll-up-fn scroll-down-fn
                                              get-offset-fn &rest body)
  "Run BODY with scroll FFI functions stubbed and kuro--initialized=t."
  (declare (indent 3))
  `(with-temp-buffer
     (setq-local kuro--initialized t
                 kuro--scroll-offset 0)
     (cl-letf (((symbol-function 'kuro--scroll-up)    ,scroll-up-fn)
               ((symbol-function 'kuro--scroll-down)  ,scroll-down-fn)
               ((symbol-function 'kuro--get-scroll-offset) ,get-offset-fn)
               ((symbol-function 'kuro--render-cycle) #'ignore))
       ,@body)))

(ert-deftest kuro-input-scroll-up-calls-ffi ()
  "kuro-scroll-up calls kuro--scroll-up with window-body-height lines."
  (let ((up-called-with nil))
    (kuro-input-test--with-scroll-stubs
        (lambda (n) (setq up-called-with n))
        #'ignore
        (lambda () nil)
      (cl-letf (((symbol-function 'window-body-height) (lambda () 24)))
        (kuro-scroll-up))
      (should (= up-called-with 24)))))

(ert-deftest kuro-input-scroll-up-noop-when-uninitialized ()
  "kuro-scroll-up does nothing when kuro--initialized is nil."
  (let ((up-called nil))
    (with-temp-buffer
      (setq-local kuro--initialized nil
                  kuro--scroll-offset 0)
      (cl-letf (((symbol-function 'kuro--scroll-up)
                 (lambda (_n) (setq up-called t))))
        (kuro-scroll-up))
      (should-not up-called))))

(ert-deftest kuro-input-scroll-down-calls-ffi ()
  "kuro-scroll-down calls kuro--scroll-down with window-body-height lines."
  (let ((down-called-with nil))
    (kuro-input-test--with-scroll-stubs
        #'ignore
        (lambda (n) (setq down-called-with n))
        (lambda () nil)
      (cl-letf (((symbol-function 'window-body-height) (lambda () 24)))
        (kuro-scroll-down))
      (should (= down-called-with 24)))))

(ert-deftest kuro-input-scroll-down-noop-when-uninitialized ()
  "kuro-scroll-down does nothing when kuro--initialized is nil."
  (let ((down-called nil))
    (with-temp-buffer
      (setq-local kuro--initialized nil
                  kuro--scroll-offset 5)
      (cl-letf (((symbol-function 'kuro--scroll-down)
                 (lambda (_n) (setq down-called t))))
        (kuro-scroll-down))
      (should-not down-called))))

(ert-deftest kuro-input-scroll-bottom-calls-ffi-with-sentinel ()
  "kuro-scroll-bottom calls kuro--scroll-down with the sentinel value."
  (let ((down-called-with nil))
    (kuro-input-test--with-scroll-stubs
        #'ignore
        (lambda (n) (setq down-called-with n))
        (lambda () 0)
      (kuro-scroll-bottom))
    (should (= down-called-with kuro--scroll-to-bottom-sentinel))))

(ert-deftest kuro-input-scroll-bottom-resets-offset ()
  "kuro-scroll-bottom resets kuro--scroll-offset to 0 (via kuro--get-scroll-offset)."
  (kuro-input-test--with-scroll-stubs
      #'ignore
      #'ignore
      (lambda () 0)
    (setq kuro--scroll-offset 42)
    (kuro-scroll-bottom)
    (should (= kuro--scroll-offset 0))))

(ert-deftest kuro-input-scroll-bottom-noop-when-uninitialized ()
  "kuro-scroll-bottom does nothing when kuro--initialized is nil."
  (let ((down-called nil))
    (with-temp-buffer
      (setq-local kuro--initialized nil
                  kuro--scroll-offset 10)
      (cl-letf (((symbol-function 'kuro--scroll-down)
                 (lambda (_n) (setq down-called t))))
        (kuro-scroll-bottom))
      (should-not down-called))))

;;; Group 14: kuro--named-key-sequences data table

(ert-deftest kuro-input-named-key-sequences-is-alist ()
  "kuro--named-key-sequences is a non-empty alist of (symbol . string) pairs."
  (should (consp kuro--named-key-sequences))
  (dolist (entry kuro--named-key-sequences)
    (should (symbolp (car entry)))
    (should (stringp (cdr entry)))))

(ert-deftest kuro-input-named-key-return-maps-to-cr ()
  "kuro--named-key-sequences maps `return' to carriage return."
  (should (equal (cdr (assq 'return kuro--named-key-sequences)) "\r")))

(ert-deftest kuro-input-named-key-tab-maps-to-ht ()
  "kuro--named-key-sequences maps `tab' to horizontal tab."
  (should (equal (cdr (assq 'tab kuro--named-key-sequences)) "\t")))

(ert-deftest kuro-input-named-key-backspace-maps-to-del ()
  "kuro--named-key-sequences maps `backspace' to DEL (\\x7f)."
  (should (equal (cdr (assq 'backspace kuro--named-key-sequences)) "\x7f")))

(ert-deftest kuro-input-named-key-escape-maps-to-esc ()
  "kuro--named-key-sequences maps `escape' to ESC (\\e)."
  (should (equal (cdr (assq 'escape kuro--named-key-sequences)) "\e")))

;;; Group 15: kuro--encode-key-event

(ert-deftest kuro-input-encode-key-ctrl-meta-char ()
  "Control+Meta+char encodes as ESC + control byte (C-M-a → ESC ^A)."
  ;; Simulate C-M-a: modifiers=(control meta), base=?a
  (let ((event (list 'C-M-a)))
    (cl-letf (((symbol-function 'event-modifiers)
               (lambda (_ev) '(control meta)))
              ((symbol-function 'event-basic-type)
               (lambda (_ev) ?a)))
      (should (equal (kuro--encode-key-event event)
                     (string ?\e (logand ?a 31)))))))

(ert-deftest kuro-input-encode-key-ctrl-char ()
  "Control+char encodes as a single control byte (C-a → ^A = \\x01)."
  (let ((event 'C-a))
    (cl-letf (((symbol-function 'event-modifiers)
               (lambda (_ev) '(control)))
              ((symbol-function 'event-basic-type)
               (lambda (_ev) ?a)))
      (should (equal (kuro--encode-key-event event)
                     (string (logand ?a 31)))))))

(ert-deftest kuro-input-encode-key-meta-char ()
  "Meta+char encodes as ESC + the base character (M-a → ESC a)."
  (let ((event 'M-a))
    (cl-letf (((symbol-function 'event-modifiers)
               (lambda (_ev) '(meta)))
              ((symbol-function 'event-basic-type)
               (lambda (_ev) ?a)))
      (should (equal (kuro--encode-key-event event)
                     (string ?\e ?a))))))

(ert-deftest kuro-input-encode-key-plain-char ()
  "Plain character encodes as itself."
  (cl-letf (((symbol-function 'event-modifiers) (lambda (_ev) nil))
            ((symbol-function 'event-basic-type) (lambda (_ev) ?z)))
    (should (equal (kuro--encode-key-event 'z) (string ?z)))))

(ert-deftest kuro-input-encode-key-return ()
  "Named key `return' encodes as carriage return."
  (cl-letf (((symbol-function 'event-modifiers) (lambda (_ev) nil))
            ((symbol-function 'event-basic-type) (lambda (_ev) 'return)))
    (should (equal (kuro--encode-key-event 'return) "\r"))))

(ert-deftest kuro-input-encode-key-tab ()
  "Named key `tab' encodes as horizontal tab."
  (cl-letf (((symbol-function 'event-modifiers) (lambda (_ev) nil))
            ((symbol-function 'event-basic-type) (lambda (_ev) 'tab)))
    (should (equal (kuro--encode-key-event 'tab) "\t"))))

(ert-deftest kuro-input-encode-key-backspace ()
  "Named key `backspace' encodes as DEL (\\x7f)."
  (cl-letf (((symbol-function 'event-modifiers) (lambda (_ev) nil))
            ((symbol-function 'event-basic-type) (lambda (_ev) 'backspace)))
    (should (equal (kuro--encode-key-event 'backspace) "\x7f"))))

(ert-deftest kuro-input-encode-key-escape ()
  "Named key `escape' encodes as ESC."
  (cl-letf (((symbol-function 'event-modifiers) (lambda (_ev) nil))
            ((symbol-function 'event-basic-type) (lambda (_ev) 'escape)))
    (should (equal (kuro--encode-key-event 'escape) "\e"))))

(ert-deftest kuro-input-encode-key-unsupported-returns-nil ()
  "An unrecognised key symbol encodes as nil."
  (cl-letf (((symbol-function 'event-modifiers) (lambda (_ev) nil))
            ((symbol-function 'event-basic-type) (lambda (_ev) 'f13)))
    (should-not (kuro--encode-key-event 'f13))))

;;; Group 19: kuro--schedule-immediate-render — timer coalescing and creation

(ert-deftest kuro-input-schedule-immediate-render-cancels-existing-timer ()
  "kuro--schedule-immediate-render cancels any existing pending-render-timer first.
If kuro--pending-render-timer is already a timer, cancel-timer must be called
before the new idle timer is created."
  (with-temp-buffer
    (let ((cancel-called-with nil)
          (fake-old (cons 'fake-timer nil)))
      (setq-local kuro--pending-render-timer fake-old)
      ;; Make timerp return t for our fake timer
      (cl-letf (((symbol-function 'timerp)
                 (lambda (x) (eq x fake-old)))
                ((symbol-function 'cancel-timer)
                 (lambda (x) (setq cancel-called-with x)))
                ((symbol-function 'run-with-idle-timer)
                 (lambda (_delay _repeat _fn) 'new-fake-timer)))
        (kuro--schedule-immediate-render)
        (should (eq cancel-called-with fake-old))))))

(ert-deftest kuro-input-schedule-immediate-render-sets-pending-timer ()
  "kuro--schedule-immediate-render stores the new timer in kuro--pending-render-timer."
  (with-temp-buffer
    (setq-local kuro--pending-render-timer nil)
    (cl-letf (((symbol-function 'timerp) (lambda (_x) nil))
              ((symbol-function 'run-with-idle-timer)
               (lambda (_delay _repeat _fn) 'created-timer)))
      (kuro--schedule-immediate-render)
      (should (eq kuro--pending-render-timer 'created-timer)))))

(ert-deftest kuro-input-schedule-immediate-render-uses-echo-delay ()
  "kuro--schedule-immediate-render passes kuro-input-echo-delay to run-with-idle-timer."
  (with-temp-buffer
    (setq-local kuro--pending-render-timer nil)
    (let ((kuro-input-echo-delay 0.042)
          (captured-delay nil))
      (cl-letf (((symbol-function 'timerp) (lambda (_x) nil))
                ((symbol-function 'run-with-idle-timer)
                 (lambda (delay _repeat _fn)
                   (setq captured-delay delay)
                   'fake)))
        (kuro--schedule-immediate-render)
        (should (= captured-delay 0.042))))))

;;; Group 20: kuro--encode-key-event — edge cases not yet covered

(ert-deftest kuro-input-encode-key-ctrl-non-char-base-returns-nil ()
  "kuro--encode-key-event returns nil when modifier is control but base is a symbol.
The control branch requires (characterp base); if base is e.g. 'f15 (non-char),
none of the character branches match and assq lookup also fails → nil."
  (cl-letf (((symbol-function 'event-modifiers)
             (lambda (_ev) '(control)))
            ((symbol-function 'event-basic-type)
             (lambda (_ev) 'f15)))
    (should-not (kuro--encode-key-event 'C-f15))))

(ert-deftest kuro-input-encode-key-meta-non-char-base-returns-nil ()
  "kuro--encode-key-event returns nil when modifier is meta but base is a symbol.
The meta branch requires (characterp base); non-character symbols fall through
all cond branches and produce nil."
  (cl-letf (((symbol-function 'event-modifiers)
             (lambda (_ev) '(meta)))
            ((symbol-function 'event-basic-type)
             (lambda (_ev) 'f15)))
    (should-not (kuro--encode-key-event 'M-f15))))

(ert-deftest kuro-input-encode-key-ctrl-meta-non-char-base-returns-nil ()
  "kuro--encode-key-event returns nil when both control+meta are set but base is a symbol."
  (cl-letf (((symbol-function 'event-modifiers)
             (lambda (_ev) '(control meta)))
            ((symbol-function 'event-basic-type)
             (lambda (_ev) 'home)))
    (should-not (kuro--encode-key-event 'C-M-home))))

;;; Group 21: kuro--kitty-modifier-offset constant and Kitty encoding invariants

(ert-deftest kuro-input-kitty-modifier-offset-value ()
  "kuro--kitty-modifier-offset is 1 (the +1 added to the wire modifier bitmask)."
  (should (= kuro--kitty-modifier-offset 1)))

(ert-deftest kuro-input-encode-kitty-key-shift-modifier ()
  "kuro--encode-kitty-key with shift (bitmask 1) produces modifier param 2."
  ;; shift=1 → wire = 1 + kuro--kitty-modifier-offset = 2
  (should (equal (kuro--encode-kitty-key 65 1) "\e[65;2u")))

(ert-deftest kuro-input-encode-kitty-key-all-common-modifiers ()
  "kuro--encode-kitty-key with ctrl+alt (bitmask 6) produces modifier param 7."
  ;; ctrl=4, alt=2 → bitmask = 6 → wire = 6 + 1 = 7
  (should (equal (kuro--encode-kitty-key 65 6) "\e[65;7u")))

;;; Group 22: scroll offset fallback (kuro--get-scroll-offset returns nil)

(ert-deftest kuro-input-scroll-up-offset-fallback-when-ffi-returns-nil ()
  "kuro-scroll-up uses (+ scroll-offset lines) when kuro--get-scroll-offset returns nil."
  (kuro-input-test--with-scroll-stubs
      #'ignore
      #'ignore
      (lambda () nil)            ; FFI returns nil → fallback arithmetic
    (setq kuro--scroll-offset 10)
    (cl-letf (((symbol-function 'window-body-height) (lambda () 5)))
      (kuro-scroll-up))
    ;; Fallback: 10 + 5 = 15
    (should (= kuro--scroll-offset 15))))

(ert-deftest kuro-input-scroll-down-offset-fallback-when-ffi-returns-nil ()
  "kuro-scroll-down uses max(0, scroll-offset - lines) when kuro--get-scroll-offset returns nil."
  (kuro-input-test--with-scroll-stubs
      #'ignore
      #'ignore
      (lambda () nil)            ; FFI returns nil → fallback arithmetic
    (setq kuro--scroll-offset 10)
    (cl-letf (((symbol-function 'window-body-height) (lambda () 3)))
      (kuro-scroll-down))
    ;; Fallback: max(0, 10 - 3) = 7
    (should (= kuro--scroll-offset 7))))

(ert-deftest kuro-input-scroll-down-offset-fallback-clamps-to-zero ()
  "kuro-scroll-down fallback clamps offset to 0 when lines > current offset."
  (kuro-input-test--with-scroll-stubs
      #'ignore
      #'ignore
      (lambda () nil)
    (setq kuro--scroll-offset 2)
    (cl-letf (((symbol-function 'window-body-height) (lambda () 10)))
      (kuro-scroll-down))
    ;; max(0, 2 - 10) = max(0, -8) = 0
    (should (= kuro--scroll-offset 0))))

;;; Group 23: kuro--send-ctrl and kuro--send-meta (kuro--def-key-sender generated fns)

(ert-deftest kuro-input-send-ctrl-sends-byte ()
  "kuro--send-ctrl sends the given control byte as a single-char string."
  (let ((sent nil))
    (cl-letf (((symbol-function 'kuro--send-key)
               (lambda (s) (push s sent)))
              ((symbol-function 'kuro--schedule-immediate-render)
               (lambda () nil)))
      (kuro--send-ctrl 1)   ; ^A
      (should (equal sent (list (string 1)))))))

(ert-deftest kuro-input-send-ctrl-sends-ctrl-c ()
  "kuro--send-ctrl with byte 3 sends the ETX (Ctrl+C) byte."
  (let ((sent nil))
    (cl-letf (((symbol-function 'kuro--send-key)
               (lambda (s) (push s sent)))
              ((symbol-function 'kuro--schedule-immediate-render)
               (lambda () nil)))
      (kuro--send-ctrl 3)
      (should (equal sent (list (string 3)))))))

(ert-deftest kuro-input-send-meta-sends-esc-plus-char ()
  "kuro--send-meta sends ESC followed by the given character."
  (let ((sent nil))
    (cl-letf (((symbol-function 'kuro--send-key)
               (lambda (s) (push s sent)))
              ((symbol-function 'kuro--schedule-immediate-render)
               (lambda () nil)))
      (kuro--send-meta ?b)
      (should (equal sent (list (string ?\e ?b)))))))

(ert-deftest kuro-input-send-meta-sends-esc-plus-f ()
  "kuro--send-meta ?f sends ESC f (readline forward-word)."
  (let ((sent nil))
    (cl-letf (((symbol-function 'kuro--send-key)
               (lambda (s) (push s sent)))
              ((symbol-function 'kuro--schedule-immediate-render)
               (lambda () nil)))
      (kuro--send-meta ?f)
      (should (equal sent (list (string ?\e ?f)))))))

(ert-deftest kuro-input-send-ctrl-schedules-render ()
  "kuro--send-ctrl calls kuro--schedule-immediate-render."
  (let ((render-called nil))
    (cl-letf (((symbol-function 'kuro--send-key) #'ignore)
              ((symbol-function 'kuro--schedule-immediate-render)
               (lambda () (setq render-called t))))
      (kuro--send-ctrl 1)
      (should render-called))))

(ert-deftest kuro-input-send-meta-schedules-render ()
  "kuro--send-meta calls kuro--schedule-immediate-render."
  (let ((render-called nil))
    (cl-letf (((symbol-function 'kuro--send-key) #'ignore)
              ((symbol-function 'kuro--schedule-immediate-render)
               (lambda () (setq render-called t))))
      (kuro--send-meta ?a)
      (should render-called))))

;;; Group 24: kuro--scroll-to-bottom-sentinel constant and FFI offset adoption

(ert-deftest kuro-input-scroll-to-bottom-sentinel-value ()
  "kuro--scroll-to-bottom-sentinel is a large positive integer used to scroll past all content."
  (should (integerp kuro--scroll-to-bottom-sentinel))
  (should (> kuro--scroll-to-bottom-sentinel 10000)))

(ert-deftest kuro-input-scroll-up-adopts-ffi-offset ()
  "kuro-scroll-up stores the value returned by kuro--get-scroll-offset (non-nil case)."
  (kuro-input-test--with-scroll-stubs
      #'ignore
      #'ignore
      (lambda () 37)           ; FFI returns the actual offset
    (setq kuro--scroll-offset 0)
    (cl-letf (((symbol-function 'window-body-height) (lambda () 10)))
      (kuro-scroll-up))
    ;; kuro--get-scroll-offset returned 37 → offset must be 37
    (should (= kuro--scroll-offset 37))))

(ert-deftest kuro-input-scroll-down-adopts-ffi-offset ()
  "kuro-scroll-down stores the value returned by kuro--get-scroll-offset (non-nil case)."
  (kuro-input-test--with-scroll-stubs
      #'ignore
      #'ignore
      (lambda () 5)            ; FFI returns the actual offset
    (setq kuro--scroll-offset 20)
    (cl-letf (((symbol-function 'window-body-height) (lambda () 10)))
      (kuro-scroll-down))
    ;; kuro--get-scroll-offset returned 5 → offset must be 5
    (should (= kuro--scroll-offset 5))))

;;; Group 25: HOME / END application-cursor-mode sequences

(ert-deftest kuro-input-HOME-application-sends-csi-1 ()
  "HOME in application cursor mode sends CSI 1~ (application variant)."
  (with-temp-buffer
    (setq-local kuro--application-cursor-keys-mode t)
    (let ((sent (kuro-input-test--capture-sent (kuro--HOME))))
      (should (equal sent '("\e[1~"))))))

(ert-deftest kuro-input-END-application-sends-csi-4 ()
  "END in application cursor mode sends CSI 4~ (application variant)."
  (with-temp-buffer
    (setq-local kuro--application-cursor-keys-mode t)
    (let ((sent (kuro-input-test--capture-sent (kuro--END))))
      (should (equal sent '("\e[4~"))))))

(provide 'kuro-input-test)

;;; kuro-input-test.el ends here
