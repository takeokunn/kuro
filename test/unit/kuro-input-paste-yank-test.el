;;; kuro-input-paste-ext-test.el --- Tests for kuro-input-paste (Groups 9-12)  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;;; Commentary:

;; ERT tests for kuro-input-paste.el (continued from kuro-input-paste-test.el).
;; Covers kuro--yank-pop edge cases, combined ESC/C1 sanitize edge cases,
;; additional yank/yank-pop dispatch cases, and bracketed paste invariants.
;; Pure Elisp tests — no Rust dynamic module required.
;; kuro--send-key and kuro--schedule-immediate-render are stubbed via cl-letf.
;; Split from kuro-input-paste-test.el at the Group 9 boundary.

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

;;; Group 9: kuro--yank-pop edge cases

(ert-deftest kuro-input-paste--yank-pop-accepts-yank-as-last-cmd ()
  "kuro--yank-pop accepts `yank' (not just kuro--yank) as previous command."
  (let ((kill-ring nil))
    (with-temp-buffer
      (kill-new "entry")
      (let ((last-command 'yank)
            (kuro--bracketed-paste-mode nil))
        ;; Should not signal an error
        (let ((sent (kuro-paste-test--capture-sent (kuro--yank-pop 0))))
          (should (equal sent '("entry"))))))))

(ert-deftest kuro-input-paste--yank-pop-accepts-kuro-yank-pop-as-last-cmd ()
  "kuro--yank-pop accepts kuro--yank-pop itself as a valid previous command."
  (let ((kill-ring nil))
    (with-temp-buffer
      (kill-new "entry2")
      (let ((last-command 'kuro--yank-pop)
            (kuro--bracketed-paste-mode nil))
        (let ((sent (kuro-paste-test--capture-sent (kuro--yank-pop 0))))
          (should (equal sent '("entry2"))))))))

;;; Group 10: kuro--sanitize-paste — combined ESC and C1 CSI edge cases

(ert-deftest kuro-input-paste--sanitize-mixed-esc-and-c1 ()
  "kuro--sanitize-paste strips both ESC and C1 CSI bytes from the same string."
  (let ((esc (string #x1b))
        (c1  (string #x9b)))
    (should (equal (kuro--sanitize-paste (concat "a" esc "b" c1 "c"))
                   "abc"))))

(ert-deftest kuro-input-paste--sanitize-only-c1-bytes ()
  "kuro--sanitize-paste returns empty string when input is all C1 CSI bytes."
  (let ((c1 (string #x9b)))
    (should (equal (kuro--sanitize-paste (concat c1 c1 c1)) ""))))

(ert-deftest kuro-input-paste--sanitize-preserves-unicode ()
  "kuro--sanitize-paste preserves multibyte Unicode characters."
  (should (equal (kuro--sanitize-paste "日本語テスト") "日本語テスト")))

(ert-deftest kuro-input-paste--sanitize-esc-between-unicode ()
  "kuro--sanitize-paste strips ESC bytes interspersed with Unicode."
  (let ((esc (string #x1b)))
    (should (equal (kuro--sanitize-paste (concat "日本" esc "語"))
                   "日本語"))))

(ert-deftest kuro-input-paste--sanitize-long-string-with-c1 ()
  "kuro--sanitize-paste handles a long string with C1 CSI bytes mixed in."
  (let* ((c1 (string #x9b))
         (clean (make-string 50 ?a))
         (dirty (concat clean c1 clean c1 clean c1 clean))
         (expected (make-string 200 ?a)))
    (should (equal (kuro--sanitize-paste dirty) expected))))

(ert-deftest kuro-input-paste--sanitize-preserves-cr-lf ()
  "kuro--sanitize-paste preserves CR and LF characters."
  (should (equal (kuro--sanitize-paste "line1\r\nline2\rline3\n")
                 "line1\r\nline2\rline3\n")))

(ert-deftest kuro-input-paste--sanitize-consecutive-esc-and-c1 ()
  "kuro--sanitize-paste strips multiple consecutive ESC and C1 bytes."
  (let ((esc (string #x1b))
        (c1  (string #x9b)))
    (should (equal (kuro--sanitize-paste (concat esc esc c1 c1 "text" esc c1))
                   "text"))))

(ert-deftest kuro-input-paste--sanitize-does-not-strip-del ()
  "kuro--sanitize-paste does not strip DEL (0x7F) — only ESC (0x1B) and C1 (0x9B)."
  (let ((del (string #x7f)))
    (should (equal (kuro--sanitize-paste (concat "a" del "b")) (concat "a" del "b")))))

(ert-deftest kuro-input-paste--sanitize-null-byte-preserved ()
  "kuro--sanitize-paste preserves NUL bytes (only ESC and C1 CSI are stripped)."
  (let ((nul (string 0)))
    (should (equal (kuro--sanitize-paste (concat "a" nul "b")) (concat "a" nul "b")))))

(ert-deftest kuro-input-paste--sanitize-c1-then-injection-sequence ()
  "kuro--sanitize-paste neutralizes 8-bit injection attempt via C1 CSI + 201~ ."
  (let* ((c1 (string #x9b))
         (payload (concat "evil" c1 "201~injection")))
    (should (equal (kuro--sanitize-paste payload) "evil201~injection"))))


;;; Group 11: kuro--yank and kuro--yank-pop additional dispatch cases

(ert-deftest kuro-input-paste--yank-arg-1-fetches-most-recent ()
  "kuro--yank with numeric arg 1 fetches the most recent kill-ring entry."
  (let ((kill-ring nil))
    (with-temp-buffer
      (kill-new "first-entry")
      (let ((kuro--bracketed-paste-mode nil)
            (sent (kuro-paste-test--capture-sent (kuro--yank 1))))
        ;; arg=1 → n=(1- 1)=0 → current-kill 0 = "first-entry"
        (should (equal sent '("first-entry")))))))

(ert-deftest kuro-input-paste--yank-arg-3-fetches-third-entry ()
  "kuro--yank with numeric arg 3 fetches the third kill-ring entry."
  (let ((kill-ring nil))
    (with-temp-buffer
      (kill-new "entry-a")
      (kill-new "entry-b")
      (kill-new "entry-c")
      ;; kill-ring: ("entry-c" "entry-b" "entry-a"), indices 0/1/2
      ;; arg=3 → n=(1- 3)=2 → current-kill 2 = "entry-a"
      (let ((kuro--bracketed-paste-mode nil)
            (sent (kuro-paste-test--capture-sent (kuro--yank 3))))
        (should (equal sent '("entry-a")))))))

(ert-deftest kuro-input-paste--yank-no-arg-fetches-most-recent ()
  "kuro--yank with no arg (nil) fetches the most recent kill-ring entry."
  (let ((kill-ring nil))
    (with-temp-buffer
      (kill-new "top-of-ring")
      (let ((kuro--bracketed-paste-mode nil)
            (sent (kuro-paste-test--capture-sent (kuro--yank nil))))
        ;; nil arg → n=0 → current-kill 0 = "top-of-ring"
        (should (equal sent '("top-of-ring")))))))

(ert-deftest kuro-input-paste--yank-pop-sanitizes-c1-in-bracketed-mode ()
  "kuro--yank-pop strips C1 CSI from content when bracketed paste mode is active."
  (let ((kill-ring nil)
        (c1 (string #x9b)))
    (with-temp-buffer
      (kill-new (concat "evil" c1 "201~payload"))
      (let ((last-command 'kuro--yank)
            (kuro--bracketed-paste-mode t))
        (let* ((sent (kuro-paste-test--capture-sent (kuro--yank-pop 0)))
               (payload (car sent))
               (inner-start (length kuro--paste-open))
               (inner-end (- (length payload) (length kuro--paste-close)))
               (inner (substring payload inner-start inner-end)))
          (should (string-prefix-p kuro--paste-open payload))
          (should (string-suffix-p kuro--paste-close payload))
          ;; C1 byte must not appear in the inner content
          (should-not (string-match-p (regexp-quote c1) inner)))))))

(ert-deftest kuro-input-paste--yank-calls-send-key-exactly-once ()
  "kuro--yank calls kuro--send-key exactly once per invocation."
  (let ((kill-ring nil))
    (with-temp-buffer
      (kill-new "single-call")
      (let ((kuro--bracketed-paste-mode t)
            (sent (kuro-paste-test--capture-sent (kuro--yank))))
        (should (= (length sent) 1))))))

(ert-deftest kuro-input-paste--yank-pop-errors-on-unrelated-last-command ()
  "kuro--yank-pop rejects last-command values other than yank/kuro--yank/kuro--yank-pop."
  (let ((last-command 'forward-char)
        (kuro--bracketed-paste-mode nil))
    (should-error (kuro--yank-pop) :type 'user-error)))

(ert-deftest kuro-input-paste--send-paste-or-raw-bracketed-long-string ()
  "kuro--send-paste-or-raw does not truncate long strings in bracketed mode."
  (with-temp-buffer
    (let* ((long-text (make-string 10000 ?x))
           (kuro--bracketed-paste-mode t)
           (captured nil))
      (cl-letf (((symbol-function 'kuro--send-key)
                 (lambda (s) (setq captured s))))
        (kuro--send-paste-or-raw long-text))
      (should (= (length captured)
                 (+ (length kuro--paste-open)
                    (length long-text)
                    (length kuro--paste-close)))))))

(ert-deftest kuro-input-paste--yank-pop-plain-no-wrapping ()
  "kuro--yank-pop in plain mode sends the raw text without any bracket sequences."
  (let ((kill-ring nil))
    (with-temp-buffer
      (kill-new "unwrapped")
      (let ((last-command 'yank)
            (kuro--bracketed-paste-mode nil))
        (let ((sent (kuro-paste-test--capture-sent (kuro--yank-pop 0))))
          (should (equal (car sent) "unwrapped"))
          (should-not (string-prefix-p kuro--paste-open (car sent))))))))

(ert-deftest kuro-input-paste--keyboard-flags-initial-value-is-zero ()
  "kuro--keyboard-flags has an initial value of 0 in a fresh buffer."
  (with-temp-buffer
    (should (= kuro--keyboard-flags 0))))

;;; Group 12: kuro--paste-text, bracketed sequences, and dispatch invariants

(defmacro kuro-paste-test--capture-sent-in-buffer (&rest body)
  "Execute BODY in a fresh temp buffer with send stubbed; return sent list."
  `(with-temp-buffer
     (let ((sent nil))
       (cl-letf (((symbol-function 'kuro--send-key)
                  (lambda (s) (push s sent)))
                 ((symbol-function 'kuro--schedule-immediate-render)
                  (lambda () nil)))
         ,@body)
       (nreverse sent))))

(ert-deftest kuro-input-paste--bracketed-sequence-open-close-structure ()
  "Bracketed paste sequence has open=ESC[200~ and close=ESC[201~ structure."
  ;; Verify constants themselves form the expected VT sequences.
  (should (equal kuro--paste-open  "\e[200~"))
  (should (equal kuro--paste-close "\e[201~"))
  (should (string-prefix-p "\e[" kuro--paste-open))
  (should (string-suffix-p "~" kuro--paste-open))
  (should (string-prefix-p "\e[" kuro--paste-close))
  (should (string-suffix-p "~" kuro--paste-close)))

(ert-deftest kuro-input-paste--paste-newlines-sent-verbatim ()
  "kuro--send-paste-or-raw sends newlines verbatim in plain mode (no \\r substitution)."
  (let ((sent (kuro-paste-test--capture-sent-in-buffer
               (setq-local kuro--bracketed-paste-mode nil)
               (kuro--send-paste-or-raw "line1\nline2\nline3"))))
    (should (equal sent '("line1\nline2\nline3")))))

(ert-deftest kuro-input-paste--paste-bracketed-wraps-multiline ()
  "kuro--send-paste-or-raw in bracketed mode wraps multi-line text correctly."
  (let ((sent (kuro-paste-test--capture-sent-in-buffer
               (setq-local kuro--bracketed-paste-mode t)
               (kuro--send-paste-or-raw "line1\nline2"))))
    (should (= (length sent) 1))
    (let ((payload (car sent)))
      (should (string-prefix-p kuro--paste-open payload))
      (should (string-suffix-p kuro--paste-close payload))
      (should (string-match-p "line1\nline2" payload)))))

(ert-deftest kuro-input-paste--paste-nul-byte-preserved-in-plain-mode ()
  "NUL (\\x00) bytes pass through kuro--send-paste-or-raw in plain mode unchanged."
  (let* ((nul (string 0))
         (text (concat "a" nul "b"))
         (sent (kuro-paste-test--capture-sent-in-buffer
                (setq-local kuro--bracketed-paste-mode nil)
                (kuro--send-paste-or-raw text))))
    (should (equal (car sent) text))))

(ert-deftest kuro-input-paste--paste-esc-stripped-in-bracketed-mode ()
  "ESC bytes are stripped from content inside the bracketed paste wrapper."
  (let* ((esc (string #x1b))
         (sent (kuro-paste-test--capture-sent-in-buffer
                (setq-local kuro--bracketed-paste-mode t)
                (kuro--send-paste-or-raw (concat "a" esc "b"))))
         (payload (car sent))
         (inner-start (length kuro--paste-open))
         (inner-end (- (length payload) (length kuro--paste-close)))
         (inner (substring payload inner-start inner-end)))
    (should-not (string-match-p (regexp-quote esc) inner))))

(ert-deftest kuro-input-paste--paste-unicode-preserved-in-bracketed-mode ()
  "Unicode characters survive kuro--sanitize-paste and bracketed wrapping."
  (let ((sent (kuro-paste-test--capture-sent-in-buffer
               (setq-local kuro--bracketed-paste-mode t)
               (kuro--send-paste-or-raw "日本語テスト"))))
    (should (string-match-p "日本語テスト" (car sent)))))

(ert-deftest kuro-input-paste--yank-dispatches-to-send-paste-or-raw ()
  "kuro--yank ends up calling kuro--send-key exactly once per call."
  (let ((kill-ring nil))
    (with-temp-buffer
      (kill-new "dispatch-check")
      (let ((kuro--bracketed-paste-mode nil)
            (count 0))
        (cl-letf (((symbol-function 'kuro--send-key)
                   (lambda (_s) (cl-incf count)))
                  ((symbol-function 'kuro--schedule-immediate-render)
                   (lambda () nil)))
          (kuro--yank))
        (should (= count 1))))))

(ert-deftest kuro-input-paste--yank-empty-string-sends-empty-brackets ()
  "kuro--yank with empty kill-ring entry sends just the open+close sequences."
  (let ((kill-ring nil))
    (with-temp-buffer
      (kill-new "")
      (let* ((kuro--bracketed-paste-mode t)
             (sent (kuro-paste-test--capture-sent (kuro--yank))))
        (should (equal (car sent)
                       (concat kuro--paste-open kuro--paste-close)))))))

(ert-deftest kuro-input-paste--yank-multiline-correct-wrapping ()
  "kuro--yank with multi-line kill content wraps exactly once with open+close."
  (let ((kill-ring nil))
    (with-temp-buffer
      (kill-new "first\nsecond\nthird")
      (let* ((kuro--bracketed-paste-mode t)
             (sent (kuro-paste-test--capture-sent (kuro--yank))))
        (should (= (length sent) 1))
        (should (string-prefix-p kuro--paste-open (car sent)))
        (should (string-suffix-p kuro--paste-close (car sent)))))))

(ert-deftest kuro-input-paste--yank-pop-uses-current-kill-text ()
  "kuro--yank-pop retrieves text from the kill ring and sends it."
  (let ((kill-ring nil))
    (with-temp-buffer
      (kill-new "kill-pop-text")
      (let ((last-command 'kuro--yank)
            (kuro--bracketed-paste-mode nil))
        (let ((sent (kuro-paste-test--capture-sent (kuro--yank-pop 0))))
          (should (equal (car sent) "kill-pop-text")))))))

(ert-deftest kuro-input-paste--send-paste-or-raw-empty-bracketed ()
  "kuro--send-paste-or-raw with empty string in bracketed mode sends open+close."
  (let ((sent (kuro-paste-test--capture-sent-in-buffer
               (setq-local kuro--bracketed-paste-mode t)
               (kuro--send-paste-or-raw ""))))
    (should (equal (car sent)
                   (concat kuro--paste-open kuro--paste-close)))))

(provide 'kuro-input-paste-ext-test)
;;; kuro-input-paste-ext-test.el ends here
