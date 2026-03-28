;;; kuro-input-paste-test.el --- Tests for kuro-input-paste  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;;; Commentary:

;; ERT tests for kuro-input-paste.el.
;; Covers kuro--sanitize-paste (ESC and C1 CSI injection prevention) and
;; kuro--yank / kuro--yank-pop (bracketed paste wrapping).
;; Pure Elisp tests — no Rust dynamic module required.
;; kuro--send-key and kuro--schedule-immediate-render are stubbed via cl-letf.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; kuro-input-paste requires kuro-ffi at load time.  Stub the symbols it
;; uses so the file loads in a batch/test environment without the module.
(unless (fboundp 'kuro--send-key)
  (defalias 'kuro--send-key (lambda (_data) nil)))
(unless (fboundp 'kuro--schedule-immediate-render)
  (defalias 'kuro--schedule-immediate-render (lambda () nil)))

(require 'kuro-input-paste)

;;; Helper

(defmacro kuro-paste-test--capture-sent (&rest body)
  "Execute BODY with kuro--send-key and kuro--schedule-immediate-render stubbed.
Returns a list of strings passed to kuro--send-key, in call order."
  `(let ((sent nil))
     (cl-letf (((symbol-function 'kuro--send-key)
                (lambda (s) (push s sent)))
               ((symbol-function 'kuro--schedule-immediate-render)
                (lambda () nil)))
       ,@body)
     (nreverse sent)))

;;; Group 1: kuro--sanitize-paste — basic behaviour

(ert-deftest kuro-input-paste--sanitize-clean-string-unchanged ()
  "kuro--sanitize-paste leaves strings containing no ESC bytes unchanged."
  (should (equal (kuro--sanitize-paste "hello world") "hello world")))

(ert-deftest kuro-input-paste--sanitize-strips-single-esc ()
  "kuro--sanitize-paste removes a single ESC (0x1B) byte."
  (let ((esc (string #x1b)))
    (should (equal (kuro--sanitize-paste (concat "hello" esc "world"))
                   "helloworld"))))

(ert-deftest kuro-input-paste--sanitize-strips-multiple-esc ()
  "kuro--sanitize-paste removes all ESC bytes from the input."
  (let ((esc (string #x1b)))
    (should (equal (kuro--sanitize-paste (concat esc "a" esc "b" esc "c"))
                   "abc"))))

(ert-deftest kuro-input-paste--sanitize-leading-esc ()
  "kuro--sanitize-paste removes a leading ESC byte."
  (let ((esc (string #x1b)))
    (should (equal (kuro--sanitize-paste (concat esc "text")) "text"))))

(ert-deftest kuro-input-paste--sanitize-trailing-esc ()
  "kuro--sanitize-paste removes a trailing ESC byte."
  (let ((esc (string #x1b)))
    (should (equal (kuro--sanitize-paste (concat "text" esc)) "text"))))

(ert-deftest kuro-input-paste--sanitize-only-esc-bytes ()
  "kuro--sanitize-paste returns empty string when input is all ESC bytes."
  (let ((esc (string #x1b)))
    (should (equal (kuro--sanitize-paste (concat esc esc esc)) ""))))

(ert-deftest kuro-input-paste--sanitize-empty-input ()
  "kuro--sanitize-paste handles an empty string without error."
  (should (equal (kuro--sanitize-paste "") "")))

(ert-deftest kuro-input-paste--sanitize-long-input-no-truncation ()
  "kuro--sanitize-paste passes through long input without truncation."
  (let* ((chunk "abcdefghij")
         (long-str (apply #'concat (make-list 100 chunk))))
    (should (equal (kuro--sanitize-paste long-str) long-str))))

(ert-deftest kuro-input-paste--sanitize-newlines-preserved ()
  "kuro--sanitize-paste preserves newline characters."
  (should (equal (kuro--sanitize-paste "line1\nline2\nline3")
                 "line1\nline2\nline3")))

(ert-deftest kuro-input-paste--sanitize-tabs-preserved ()
  "kuro--sanitize-paste preserves tab characters."
  (should (equal (kuro--sanitize-paste "col1\tcol2") "col1\tcol2")))

(ert-deftest kuro-input-paste--sanitize-injection-sequence-neutralized ()
  "kuro--sanitize-paste neutralizes a bracketed paste escape injection attempt.
Clipboard content ESC[201~ would prematurely close the paste bracket;
sanitization removes the ESC so [201~ is treated as literal text."
  (let* ((esc (string #x1b))
         (payload (concat "evil" esc "[201~injection")))
    (should (equal (kuro--sanitize-paste payload) "evil[201~injection"))))

(ert-deftest kuro-input-paste--sanitize-c1-csi-injection-neutralized ()
  "kuro--sanitize-paste neutralizes 8-bit C1 CSI injection (\\x9b201~).
On 8-bit terminals \\x9b is equivalent to ESC[ and would close the paste bracket."
  (let* ((c1-csi (string #x9b))
         (payload (concat "evil" c1-csi "201~injection")))
    (should (equal (kuro--sanitize-paste payload) "evil201~injection"))))

;;; Group 2: kuro--yank — plain mode (bracketed paste off)

(ert-deftest kuro-input-paste--yank-plain-sends-text-directly ()
  "kuro--yank sends text directly when bracketed paste mode is off."
  (let ((kill-ring nil))
    (with-temp-buffer
      (kill-new "clipboard text")
      (let ((kuro--bracketed-paste-mode nil)
            (sent (kuro-paste-test--capture-sent (kuro--yank))))
        (should (equal sent '("clipboard text")))))))

(ert-deftest kuro-input-paste--yank-plain-preserves-content ()
  "kuro--yank in plain mode sends content verbatim (no wrapping or sanitization)."
  (let ((kill-ring nil)
        (esc (string #x1b)))
    (with-temp-buffer
      ;; Even with ESC in content, plain mode sends it as-is.
      (kill-new (concat "raw" esc "content"))
      (let ((kuro--bracketed-paste-mode nil)
            (sent (kuro-paste-test--capture-sent (kuro--yank))))
        (should (equal sent (list (concat "raw" esc "content"))))))))

;;; Group 3: kuro--yank — bracketed paste mode

(ert-deftest kuro-input-paste--yank-bracketed-wraps-with-sequences ()
  "kuro--yank wraps content with ESC[200~ and ESC[201~ in bracketed paste mode."
  (let ((kill-ring nil))
    (with-temp-buffer
      (kill-new "pasted text")
      (let* ((kuro--bracketed-paste-mode t)
             (sent (kuro-paste-test--capture-sent (kuro--yank))))
        (should (= (length sent) 1))
        (let ((payload (car sent)))
          (should (string-prefix-p "\e[200~" payload))
          (should (string-suffix-p "\e[201~" payload))
          (should (string-match-p "pasted text" payload)))))))

(ert-deftest kuro-input-paste--yank-bracketed-sanitizes-esc ()
  "kuro--yank strips ESC from clipboard content in bracketed paste mode.
The wrap sequences ESC[200~/ESC[201~ are intact; the user ESC is gone."
  (let ((kill-ring nil)
        (esc (string #x1b)))
    (with-temp-buffer
      (kill-new (concat "evil" esc "[201~injection"))
      (let* ((kuro--bracketed-paste-mode t)
             (sent (kuro-paste-test--capture-sent (kuro--yank))))
        (should (= (length sent) 1))
        (let* ((payload (car sent))
               (open-len (length (concat esc "[200~")))
               (close-len (length (concat esc "[201~")))
               (content (substring payload open-len
                                   (- (length payload) close-len))))
          ;; Outer brackets intact.
          (should (string-prefix-p (concat esc "[200~") payload))
          (should (string-suffix-p (concat esc "[201~") payload))
          ;; User content must not contain ESC.
          (should-not (string-match-p (regexp-quote esc) content)))))))

(ert-deftest kuro-input-paste--yank-bracketed-empty-kill ()
  "kuro--yank with empty kill-ring entry still wraps correctly."
  (let ((kill-ring nil))
    (with-temp-buffer
      (kill-new "")
      (let* ((kuro--bracketed-paste-mode t)
             (sent (kuro-paste-test--capture-sent (kuro--yank))))
        (should (= (length sent) 1))
        (should (equal (car sent) "\e[200~\e[201~"))))))

;;; Group 4: kuro--yank-pop — bracketed paste mode

(ert-deftest kuro-input-paste--yank-pop-wraps-in-bracketed-mode ()
  "kuro--yank-pop wraps content with bracketed paste sequences when mode is on."
  (let ((kill-ring nil))
    (with-temp-buffer
      (kill-new "pop text")
      ;; last-command must be bound BEFORE calling kuro--yank-pop.
      ;; Use nested let so last-command is in scope when the call runs.
      (let ((last-command 'kuro--yank)
            (kuro--bracketed-paste-mode t))
        (let ((sent (kuro-paste-test--capture-sent (kuro--yank-pop 0))))
          (should (= (length sent) 1))
          (let ((payload (car sent)))
            (should (string-prefix-p "\e[200~" payload))
            (should (string-suffix-p "\e[201~" payload))))))))

(ert-deftest kuro-input-paste--yank-pop-plain-sends-directly ()
  "kuro--yank-pop sends content directly when bracketed paste mode is off."
  (let ((kill-ring nil))
    (with-temp-buffer
      (kill-new "pop plain")
      (let ((last-command 'kuro--yank)
            (kuro--bracketed-paste-mode nil))
        (let ((sent (kuro-paste-test--capture-sent (kuro--yank-pop 0))))
          (should (equal sent '("pop plain"))))))))

(ert-deftest kuro-input-paste--yank-pop-errors-when-not-after-yank ()
  "kuro--yank-pop signals user-error when previous command was not a yank."
  (let ((last-command 'self-insert-command)
        (kuro--bracketed-paste-mode nil))
    (should-error (kuro--yank-pop) :type 'user-error)))

;;; Group 5: Buffer-local state isolation

(ert-deftest kuro-input-paste--bracketed-paste-mode-is-buffer-local ()
  "kuro--bracketed-paste-mode is buffer-local (isolated per buffer)."
  (let ((buf1 (get-buffer-create " *kuro-paste-test-1*"))
        (buf2 (get-buffer-create " *kuro-paste-test-2*")))
    (unwind-protect
        (progn
          (with-current-buffer buf1 (setq-local kuro--bracketed-paste-mode t))
          (with-current-buffer buf2 (setq-local kuro--bracketed-paste-mode nil))
          (should (with-current-buffer buf1 kuro--bracketed-paste-mode))
          (should-not (with-current-buffer buf2 kuro--bracketed-paste-mode)))
      (kill-buffer buf1)
      (kill-buffer buf2))))

(ert-deftest kuro-input-paste--keyboard-flags-is-buffer-local ()
  "kuro--keyboard-flags is buffer-local (isolated per buffer)."
  (let ((buf1 (get-buffer-create " *kuro-paste-flags-1*"))
        (buf2 (get-buffer-create " *kuro-paste-flags-2*")))
    (unwind-protect
        (progn
          (with-current-buffer buf1 (setq-local kuro--keyboard-flags 7))
          (with-current-buffer buf2 (setq-local kuro--keyboard-flags 0))
          (should (= (with-current-buffer buf1 kuro--keyboard-flags) 7))
          (should (= (with-current-buffer buf2 kuro--keyboard-flags) 0)))
      (kill-buffer buf1)
      (kill-buffer buf2))))

;;; Group 6: kuro--paste-open and kuro--paste-close defconst values

(ert-deftest kuro-input-paste--paste-open-is-correct-sequence ()
  "kuro--paste-open is exactly ESC[200~ (DEC mode 2004 open bracket)."
  (should (equal kuro--paste-open "\e[200~")))

(ert-deftest kuro-input-paste--paste-close-is-correct-sequence ()
  "kuro--paste-close is exactly ESC[201~ (DEC mode 2004 close bracket)."
  (should (equal kuro--paste-close "\e[201~")))

(ert-deftest kuro-input-paste--paste-open-starts-with-esc ()
  "kuro--paste-open starts with ESC (0x1B)."
  (should (= (aref kuro--paste-open 0) #x1B)))

(ert-deftest kuro-input-paste--paste-close-starts-with-esc ()
  "kuro--paste-close starts with ESC (0x1B)."
  (should (= (aref kuro--paste-close 0) #x1B)))

(ert-deftest kuro-input-paste--paste-sequences-are-distinct ()
  "kuro--paste-open and kuro--paste-close are different strings."
  (should-not (equal kuro--paste-open kuro--paste-close)))

;;; Group 7: kuro--send-paste-or-raw dispatch

(ert-deftest kuro-input-paste--send-paste-or-raw-plain-mode ()
  "kuro--send-paste-or-raw sends text verbatim when bracketed paste is off."
  (with-temp-buffer
    (let ((kuro--bracketed-paste-mode nil)
          (captured nil))
      (cl-letf (((symbol-function 'kuro--send-key)
                 (lambda (s) (setq captured s))))
        (kuro--send-paste-or-raw "hello"))
      (should (equal captured "hello")))))

(ert-deftest kuro-input-paste--send-paste-or-raw-bracketed-mode-wraps ()
  "kuro--send-paste-or-raw wraps text with open/close sequences when mode is on."
  (with-temp-buffer
    (let ((kuro--bracketed-paste-mode t)
          (captured nil))
      (cl-letf (((symbol-function 'kuro--send-key)
                 (lambda (s) (setq captured s))))
        (kuro--send-paste-or-raw "world"))
      (should (string-prefix-p kuro--paste-open captured))
      (should (string-suffix-p kuro--paste-close captured))
      (should (string-match-p "world" captured)))))

(ert-deftest kuro-input-paste--send-paste-or-raw-bracketed-mode-sanitizes ()
  "kuro--send-paste-or-raw sanitizes ESC from text in bracketed mode."
  (with-temp-buffer
    (let ((kuro--bracketed-paste-mode t)
          (esc (string #x1b))
          (captured nil))
      (cl-letf (((symbol-function 'kuro--send-key)
                 (lambda (s) (setq captured s))))
        (kuro--send-paste-or-raw (concat "a" esc "b")))
      ;; The inner content must not contain ESC (only the bracket sequences do)
      (let* ((inner-start (length kuro--paste-open))
             (inner-end (- (length captured) (length kuro--paste-close)))
             (inner (substring captured inner-start inner-end)))
        (should-not (string-match-p (regexp-quote esc) inner))))))

(ert-deftest kuro-input-paste--send-paste-or-raw-plain-preserves-esc ()
  "kuro--send-paste-or-raw does NOT sanitize in plain mode — ESC passes through."
  (with-temp-buffer
    (let ((kuro--bracketed-paste-mode nil)
          (esc (string #x1b))
          (captured nil))
      (cl-letf (((symbol-function 'kuro--send-key)
                 (lambda (s) (setq captured s))))
        (kuro--send-paste-or-raw (concat "a" esc "b")))
      (should (string= captured (concat "a" esc "b"))))))

;;; Group 8: kuro--yank dispatch

(ert-deftest kuro-input-paste--yank-calls-schedule-render ()
  "kuro--yank calls kuro--schedule-immediate-render after sending."
  (let ((kill-ring nil)
        (render-called nil))
    (with-temp-buffer
      (kill-new "text")
      (let ((kuro--bracketed-paste-mode nil))
        (cl-letf (((symbol-function 'kuro--send-key)
                   (lambda (_s) nil))
                  ((symbol-function 'kuro--schedule-immediate-render)
                   (lambda () (setq render-called t))))
          (kuro--yank)))
      (should render-called))))

(ert-deftest kuro-input-paste--yank-with-numeric-arg ()
  "kuro--yank with numeric arg 2 retrieves the second kill-ring entry."
  (let ((kill-ring nil))
    (with-temp-buffer
      (kill-new "first")
      (kill-new "second")
      ;; kill-ring is now ("second" "first"), current-kill 1 → "first"
      (let ((kuro--bracketed-paste-mode nil)
            (sent (kuro-paste-test--capture-sent (kuro--yank 2))))
        ;; arg=2 → n=(1- 2)=1 → current-kill 1 = "first"
        (should (equal sent '("first")))))))

(provide 'kuro-input-paste-test)
;;; kuro-input-paste-test.el ends here
