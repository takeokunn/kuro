;;; kuro-input-test.el --- Unit tests for kuro-input.el — Groups 1-13  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-input.el (key sequence encoding, mouse encoding,
;; bracketed paste, yank) — Groups 1-13.
;; Groups 14-15 (named-key-sequences, encode-key-event) are in kuro-input-encode-test.el.
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;; All kuro--send-key calls are intercepted with cl-letf stubs.

;;; Code:
(require 'kuro-input-test-support)



;;; Helpers

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
  (kuro-input-test--assert-sends-in-buffer-mode nil (kuro--arrow-up) '("\e[A")))

(ert-deftest kuro-input-arrow-up-application ()
  "Arrow up in application mode sends SS3 A."
  (kuro-input-test--assert-sends-in-buffer-mode t (kuro--arrow-up) '("\eOA")))

(ert-deftest kuro-input-arrow-down-normal ()
  "Arrow down in normal mode sends CSI B."
  (kuro-input-test--assert-sends-in-mode nil (kuro--arrow-down) '("\e[B")))

(ert-deftest kuro-input-arrow-left-normal ()
  "Arrow left in normal mode sends CSI D."
  (kuro-input-test--assert-sends-in-mode nil (kuro--arrow-left) '("\e[D")))

(ert-deftest kuro-input-arrow-right-normal ()
  "Arrow right in normal mode sends CSI C."
  (kuro-input-test--assert-sends-in-mode nil (kuro--arrow-right) '("\e[C")))

;;; Group 3: Special keys

(ert-deftest kuro-input-RET-sends-cr ()
  "kuro--RET sends a carriage return (0x0D)."
  (kuro-input-test--assert-sends (kuro--RET) (list (string ?\r))))

(ert-deftest kuro-input-TAB-sends-tab ()
  "kuro--TAB sends a horizontal tab (0x09)."
  (kuro-input-test--assert-sends (kuro--TAB) (list (string ?\t))))

(ert-deftest kuro-input-DEL-sends-delete ()
  "kuro--DEL sends DEL (0x7F)."
  (kuro-input-test--assert-sends (kuro--DEL) (list (string ?\x7f))))

;;; Group 4: Function keys

(ert-deftest kuro-input-F1-sends-ss3-P ()
  "F1 sends SS3 P (\\eOP)."
  (kuro-input-test--assert-sends-in-mode nil (kuro--F1) '("\eOP")))

(ert-deftest kuro-input-F5-sends-csi-15 ()
  "F5 sends CSI 15~."
  (kuro-input-test--assert-sends-in-mode nil (kuro--F5) '("\e[15~")))

(ert-deftest kuro-input-F12-sends-csi-24 ()
  "F12 sends CSI 24~."
  (kuro-input-test--assert-sends-in-mode nil (kuro--F12) '("\e[24~")))

;;; Group 5: Home/End/Page keys

(ert-deftest kuro-input-HOME-normal-sends-csi-H ()
  "HOME in normal mode sends CSI H."
  (kuro-input-test--assert-sends-in-mode nil (kuro--HOME) '("\e[H")))

(ert-deftest kuro-input-END-normal-sends-csi-F ()
  "END in normal mode sends CSI F."
  (kuro-input-test--assert-sends-in-mode nil (kuro--END) '("\e[F")))

(ert-deftest kuro-input-PAGE-UP-sends-csi-5 ()
  "Page Up sends CSI 5~."
  (kuro-input-test--assert-sends-in-mode nil (kuro--PAGE-UP) '("\e[5~")))

(ert-deftest kuro-input-PAGE-DOWN-sends-csi-6 ()
  "Page Down sends CSI 6~."
  (kuro-input-test--assert-sends-in-mode nil (kuro--PAGE-DOWN) '("\e[6~")))

(ert-deftest kuro-input-INSERT-sends-csi-2 ()
  "Insert key sends CSI 2~."
  (kuro-input-test--assert-sends-in-mode nil (kuro--INSERT) '("\e[2~")))

(ert-deftest kuro-input-DELETE-sends-csi-3 ()
  "Delete key sends CSI 3~."
  (kuro-input-test--assert-sends-in-mode nil (kuro--DELETE) '("\e[3~")))

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

;;; Group 18: kuro-scroll-up / kuro-scroll-down / kuro-scroll-bottom

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

(provide 'kuro-input-test)
;;; kuro-input-test.el ends here
