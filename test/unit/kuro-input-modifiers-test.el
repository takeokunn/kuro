;;; kuro-input-ext2-test.el --- Unit tests for kuro-input.el (Groups 23-30)  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-input.el — send-ctrl/meta, scroll sentinel/FFI adoption,
;; HOME/END application-cursor, send-next-key, buffer-local vars, Kitty extended
;; modifiers, scroll-aware-ctrl-v/meta-v, send-char and def-special-key.
;; Split from kuro-input-ext-test.el at the Group 23 boundary.
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.

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

(defmacro kuro-input-ext2-test--with-scroll-stubs (scroll-up-fn scroll-down-fn
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

(ert-deftest kuro-input-scroll-up-adopts-ffi-offset ()
  "kuro-scroll-up stores the value returned by kuro--get-scroll-offset (non-nil case)."
  (kuro-input-ext2-test--with-scroll-stubs
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
  (kuro-input-ext2-test--with-scroll-stubs
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

;;; Group 26: kuro-send-next-key — dispatch via kuro--encode-key-event

(ert-deftest kuro-input-send-next-key-dispatches-supported-event ()
  "kuro-send-next-key sends the encoded string when the key is supported."
  (let ((sent nil))
    (cl-letf (((symbol-function 'read-event)
               (lambda () ?a))
              ((symbol-function 'kuro--send-key)
               (lambda (s) (push s sent)))
              ((symbol-function 'kuro--schedule-immediate-render)
               (lambda () nil))
              ((symbol-function 'message) #'ignore))
      (kuro-send-next-key)
      ;; Plain 'a' with no modifiers encodes as "a"
      (should (equal sent (list "a"))))))

(ert-deftest kuro-input-send-next-key-shows-message-for-unsupported-event ()
  "kuro-send-next-key shows a message and does not call kuro--send-key for unsupported keys."
  (let ((sent nil)
        (msg nil))
    (cl-letf (((symbol-function 'read-event)
               ;; Return a synthetic event whose basic-type is an unknown symbol
               (lambda () 'f99))
              ((symbol-function 'kuro--encode-key-event)
               (lambda (_ev) nil))
              ((symbol-function 'kuro--send-key)
               (lambda (s) (push s sent)))
              ((symbol-function 'message)
               (lambda (fmt &rest _args)
                 (setq msg fmt)))
              ((symbol-function 'kuro--schedule-immediate-render)
               (lambda () nil)))
      (kuro-send-next-key)
      (should (null sent))
      (should (stringp msg)))))

(ert-deftest kuro-input-send-next-key-ctrl-char-encodes-control-byte ()
  "kuro-send-next-key with a Ctrl+letter event sends the control byte."
  (let ((sent nil))
    (cl-letf (((symbol-function 'read-event)
               (lambda () ?\C-c))
              ((symbol-function 'kuro--send-key)
               (lambda (s) (push s sent)))
              ((symbol-function 'kuro--schedule-immediate-render)
               (lambda () nil))
              ((symbol-function 'message) #'ignore))
      (kuro-send-next-key)
      ;; ?\C-c = 3; encoded as (string (logand ?c 31)) = (string 3)
      (should (equal sent (list (string (logand ?c 31))))))))

;;; Group 27: kuro--app-keypad-mode and kuro--pending-render-timer — buffer-local vars

(ert-deftest kuro-input-app-keypad-mode-is-buffer-local ()
  "kuro--app-keypad-mode is buffer-local (each kuro buffer manages its own state)."
  (let ((buf1 (get-buffer-create " *kuro-input-kpd-1*"))
        (buf2 (get-buffer-create " *kuro-input-kpd-2*")))
    (unwind-protect
        (progn
          (with-current-buffer buf1 (setq kuro--app-keypad-mode t))
          (with-current-buffer buf2 (setq kuro--app-keypad-mode nil))
          (should (with-current-buffer buf1 kuro--app-keypad-mode))
          (should-not (with-current-buffer buf2 kuro--app-keypad-mode)))
      (kill-buffer buf1)
      (kill-buffer buf2))))

(ert-deftest kuro-input-pending-render-timer-is-buffer-local ()
  "kuro--pending-render-timer is buffer-local."
  (let ((buf1 (get-buffer-create " *kuro-input-timer-1*"))
        (buf2 (get-buffer-create " *kuro-input-timer-2*")))
    (unwind-protect
        (progn
          (with-current-buffer buf1 (setq kuro--pending-render-timer 'fake-timer))
          (with-current-buffer buf2 (setq kuro--pending-render-timer nil))
          (should (eq (with-current-buffer buf1 kuro--pending-render-timer) 'fake-timer))
          (should (null (with-current-buffer buf2 kuro--pending-render-timer))))
      (kill-buffer buf1)
      (kill-buffer buf2))))

(ert-deftest kuro-input-application-cursor-keys-mode-is-buffer-local ()
  "kuro--application-cursor-keys-mode is buffer-local."
  (let ((buf1 (get-buffer-create " *kuro-input-ackm-1*"))
        (buf2 (get-buffer-create " *kuro-input-ackm-2*")))
    (unwind-protect
        (progn
          (with-current-buffer buf1 (setq kuro--application-cursor-keys-mode t))
          (with-current-buffer buf2 (setq kuro--application-cursor-keys-mode nil))
          (should (with-current-buffer buf1 kuro--application-cursor-keys-mode))
          (should-not (with-current-buffer buf2 kuro--application-cursor-keys-mode)))
      (kill-buffer buf1)
      (kill-buffer buf2))))

;;; Group 28: kuro--encode-kitty-key — extended modifier bitmasks

(ert-deftest kuro-input-encode-kitty-key-super-modifier ()
  "kuro--encode-kitty-key with super (bitmask 8) produces modifier param 9."
  ;; super=8 → wire = 8 + kuro--kitty-modifier-offset (1) = 9
  (should (equal (kuro--encode-kitty-key 65 8) "\e[65;9u")))

(ert-deftest kuro-input-encode-kitty-key-hyper-modifier ()
  "kuro--encode-kitty-key with hyper (bitmask 16) produces modifier param 17."
  (should (equal (kuro--encode-kitty-key 65 16) "\e[65;17u")))

(ert-deftest kuro-input-encode-kitty-key-meta-modifier ()
  "kuro--encode-kitty-key with meta (bitmask 32) produces modifier param 33."
  (should (equal (kuro--encode-kitty-key 65 32) "\e[65;33u")))

(ert-deftest kuro-input-encode-kitty-key-shift-ctrl-combination ()
  "kuro--encode-kitty-key with shift+ctrl (bitmask 5) produces modifier param 6."
  ;; shift=1, ctrl=4 → bitmask=5 → wire = 5 + 1 = 6
  (should (equal (kuro--encode-kitty-key 65 5) "\e[65;6u")))

(ert-deftest kuro-input-encode-kitty-key-unicode-codepoint ()
  "kuro--encode-kitty-key encodes a non-ASCII Unicode codepoint correctly."
  ;; U+3042 (HIRAGANA LETTER A) with no modifiers
  (should (equal (kuro--encode-kitty-key #x3042 0) "\e[12354u")))

(ert-deftest kuro-input-encode-kitty-key-space-codepoint ()
  "kuro--encode-kitty-key with space codepoint (32) and no modifiers."
  (should (equal (kuro--encode-kitty-key 32 0) "\e[32u")))

(ert-deftest kuro-input-encode-kitty-key-all-modifiers-combined ()
  "kuro--encode-kitty-key with all common modifiers (shift+alt+ctrl = 7) produces param 8."
  ;; shift=1, alt=2, ctrl=4 → bitmask=7 → wire = 7 + 1 = 8
  (should (equal (kuro--encode-kitty-key 65 7) "\e[65;8u")))

;;; Group 29: kuro--scroll-aware-ctrl-v and kuro--scroll-aware-meta-v

(ert-deftest kuro-input-scroll-aware-ctrl-v-at-live-sends-ctrl-byte ()
  "kuro--scroll-aware-ctrl-v sends ctrl byte 22 when scroll-offset is 0."
  (let ((kuro--scroll-offset 0)
        sent)
    (cl-letf (((symbol-function 'kuro--send-ctrl)
               (lambda (byte) (setq sent byte)))
              ((symbol-function 'kuro-scroll-down) (lambda () (error "must not scroll"))))
      (kuro--scroll-aware-ctrl-v)
      (should (= sent 22)))))

(ert-deftest kuro-input-scroll-aware-ctrl-v-in-scrollback-scrolls-down ()
  "kuro--scroll-aware-ctrl-v calls kuro-scroll-down when scroll-offset > 0."
  (let ((kuro--scroll-offset 5)
        scrolled)
    (cl-letf (((symbol-function 'kuro-scroll-down) (lambda () (setq scrolled t)))
              ((symbol-function 'kuro--send-ctrl) (lambda (_) (error "must not send"))))
      (kuro--scroll-aware-ctrl-v)
      (should scrolled))))

(ert-deftest kuro-input-scroll-aware-meta-v-at-live-sends-esc-v ()
  "kuro--scroll-aware-meta-v sends ESC+v when scroll-offset is 0."
  (let ((kuro--scroll-offset 0)
        sent)
    (cl-letf (((symbol-function 'kuro--send-meta)
               (lambda (char) (setq sent char)))
              ((symbol-function 'kuro-scroll-up) (lambda () (error "must not scroll"))))
      (kuro--scroll-aware-meta-v)
      (should (= sent ?v)))))

(ert-deftest kuro-input-scroll-aware-meta-v-in-scrollback-scrolls-up ()
  "kuro--scroll-aware-meta-v calls kuro-scroll-up when scroll-offset > 0."
  (let ((kuro--scroll-offset 3)
        scrolled)
    (cl-letf (((symbol-function 'kuro-scroll-up) (lambda () (setq scrolled t)))
              ((symbol-function 'kuro--send-meta) (lambda (_) (error "must not send"))))
      (kuro--scroll-aware-meta-v)
      (should scrolled))))

;;; Group 30: kuro--send-char and kuro--def-special-key

(ert-deftest kuro-input-send-char-calls-send-key-with-string ()
  "kuro--send-char passes (string char) to kuro--send-key."
  (let ((sent nil))
    (cl-letf (((symbol-function 'kuro--send-key)
               (lambda (s) (setq sent s))))
      (kuro--send-char ?A)
      (should (equal sent "A")))))

(ert-deftest kuro-input-send-char-unicode-codepoint ()
  "kuro--send-char encodes a unicode codepoint correctly."
  (let ((sent nil))
    (cl-letf (((symbol-function 'kuro--send-key)
               (lambda (s) (setq sent s))))
      (kuro--send-char ?€)
      (should (equal sent "€")))))

(ert-deftest kuro-input-def-special-key-macro-generates-command ()
  "kuro--def-special-key generates an interactive command that calls kuro--send-special."
  (should (fboundp 'kuro--RET))
  (should (fboundp 'kuro--TAB))
  (should (fboundp 'kuro--DEL))
  (should (commandp 'kuro--RET))
  (should (commandp 'kuro--TAB))
  (should (commandp 'kuro--DEL)))

(ert-deftest kuro-input-ret-sends-carriage-return ()
  "kuro--RET sends \\r to the PTY."
  (let ((sent nil))
    (cl-letf (((symbol-function 'kuro--send-key)
               (lambda (s) (setq sent s)))
              ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
      (kuro--RET)
      (should (equal sent "\r")))))

(ert-deftest kuro-input-del-sends-backspace-byte ()
  "kuro--DEL sends \\x7f to the PTY."
  (let ((sent nil))
    (cl-letf (((symbol-function 'kuro--send-key)
               (lambda (s) (setq sent s)))
              ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
      (kuro--DEL)
      (should (equal sent "\x7f")))))

(provide 'kuro-input-ext2-test)

;;; kuro-input-ext2-test.el ends here
