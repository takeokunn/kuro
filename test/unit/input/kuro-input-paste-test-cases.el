;;; kuro-input-paste-test-cases.el --- Paste test case data  -*- lexical-binding: t; -*-

;;; Code:

(defconst kuro-paste-test--sanitize-cases
  '((kuro-input-paste--sanitize-clean-string-unchanged
     "kuro--sanitize-paste leaves strings containing no ESC bytes unchanged."
     "hello world"
     "hello world")
    (kuro-input-paste--sanitize-strips-single-esc
     "kuro--sanitize-paste removes a single ESC (0x1B) byte."
     (concat "hello" (string #x1b) "world")
     "helloworld")
    (kuro-input-paste--sanitize-strips-multiple-esc
     "kuro--sanitize-paste removes all ESC bytes from the input."
     (concat (string #x1b) "a" (string #x1b) "b" (string #x1b) "c")
     "abc")
    (kuro-input-paste--sanitize-leading-esc
     "kuro--sanitize-paste removes a leading ESC byte."
     (concat (string #x1b) "text")
     "text")
    (kuro-input-paste--sanitize-trailing-esc
     "kuro--sanitize-paste removes a trailing ESC byte."
     (concat "text" (string #x1b))
     "text")
    (kuro-input-paste--sanitize-only-esc-bytes
     "kuro--sanitize-paste returns empty string when input is all ESC bytes."
     (concat (string #x1b) (string #x1b) (string #x1b))
     "")
    (kuro-input-paste--sanitize-empty-input
     "kuro--sanitize-paste handles an empty string without error."
     ""
     "")
    (kuro-input-paste--sanitize-long-input-no-truncation
     "kuro--sanitize-paste passes through long input without truncation."
     (apply #'concat (make-list 100 "abcdefghij"))
     (apply #'concat (make-list 100 "abcdefghij")))
    (kuro-input-paste--sanitize-newlines-preserved
     "kuro--sanitize-paste preserves newline characters."
     "line1\nline2\nline3"
     "line1\nline2\nline3")
    (kuro-input-paste--sanitize-tabs-preserved
     "kuro--sanitize-paste preserves tab characters."
     "col1\tcol2"
     "col1\tcol2")
    (kuro-input-paste--sanitize-injection-sequence-neutralized
     "kuro--sanitize-paste neutralizes a bracketed paste escape injection attempt."
     (concat "evil" (string #x1b) "[201~injection")
     "evil[201~injection")
    (kuro-input-paste--sanitize-c1-csi-injection-neutralized
     "kuro--sanitize-paste neutralizes 8-bit C1 CSI injection."
     (concat "evil" (string #x9b) "201~injection")
     "evil201~injection")
    (kuro-input-paste--sanitize-mixed-esc-and-c1
     "kuro--sanitize-paste strips both ESC and C1 CSI bytes from the same string."
     (concat "a" (string #x1b) "b" (string #x9b) "c")
     "abc")
    (kuro-input-paste--sanitize-only-c1-bytes
     "kuro--sanitize-paste returns empty string when input is all C1 CSI bytes."
     (concat (string #x9b) (string #x9b) (string #x9b))
     "")
    (kuro-input-paste--sanitize-preserves-unicode
     "kuro--sanitize-paste preserves multibyte Unicode characters."
     "日本語テスト"
     "日本語テスト")
    (kuro-input-paste--sanitize-esc-between-unicode
     "kuro--sanitize-paste strips ESC bytes interspersed with Unicode."
     (concat "日本" (string #x1b) "語")
     "日本語")
    (kuro-input-paste--sanitize-long-string-with-c1
     "kuro--sanitize-paste handles a long string with C1 CSI bytes mixed in."
     (let ((clean (make-string 50 ?a))
           (c1 (string #x9b)))
       (concat clean c1 clean c1 clean c1 clean))
     (make-string 200 ?a))
    (kuro-input-paste--sanitize-preserves-cr-lf
     "kuro--sanitize-paste preserves CR and LF characters."
     "line1\r\nline2\rline3\n"
     "line1\r\nline2\rline3\n")
    (kuro-input-paste--sanitize-consecutive-esc-and-c1
     "kuro--sanitize-paste strips multiple consecutive ESC and C1 bytes."
     (concat (string #x1b) (string #x1b) (string #x9b) (string #x9b)
             "text" (string #x1b) (string #x9b))
     "text")
    (kuro-input-paste--sanitize-does-not-strip-del
     "kuro--sanitize-paste does not strip DEL."
     (concat "a" (string #x7f) "b")
     (concat "a" (string #x7f) "b"))
    (kuro-input-paste--sanitize-null-byte-preserved
     "kuro--sanitize-paste preserves NUL bytes."
     (concat "a" (string 0) "b")
     (concat "a" (string 0) "b"))
    (kuro-input-paste--sanitize-c1-then-injection-sequence
     "kuro--sanitize-paste neutralizes 8-bit injection attempt via C1 CSI + 201~ ."
     (concat "evil" (string #x9b) "201~injection")
     "evil201~injection")))

(defconst kuro-paste-test--yank-arg-cases
  '((kuro-input-paste--yank-with-numeric-arg
     "kuro--yank with numeric arg 2 retrieves the second kill-ring entry."
     ("first" "second")
     2
     ("first"))
    (kuro-input-paste--yank-arg-1-fetches-most-recent
     "kuro--yank with numeric arg 1 fetches the most recent kill-ring entry."
     ("first-entry")
     1
     ("first-entry"))
    (kuro-input-paste--yank-arg-3-fetches-third-entry
     "kuro--yank with numeric arg 3 fetches the third kill-ring entry."
     ("entry-a" "entry-b" "entry-c")
     3
     ("entry-a"))
    (kuro-input-paste--yank-no-arg-fetches-most-recent
     "kuro--yank with no arg (nil) fetches the most recent kill-ring entry."
     ("top-of-ring")
     nil
     ("top-of-ring"))))

(defconst kuro-paste-test--yank-send-cases
  '((kuro-input-paste--yank-plain-sends-text-directly
     "kuro--yank sends text directly when bracketed paste mode is off."
     "clipboard text"
     nil
     (list :expected '("clipboard text")))
    (kuro-input-paste--yank-plain-preserves-content
     "kuro--yank in plain mode sends content verbatim (no wrapping or sanitization)."
     (concat "raw" (string #x1b) "content")
     nil
     (list :expected (list (concat "raw" (string #x1b) "content"))))
    (kuro-input-paste--yank-bracketed-wraps-with-sequences
     "kuro--yank wraps content with ESC[200~ and ESC[201~ in bracketed paste mode."
     "pasted text"
     t
     (list :wrapped (list :contains "pasted text")))
    (kuro-input-paste--yank-bracketed-sanitizes-esc
     "kuro--yank strips ESC from clipboard content in bracketed paste mode."
     (concat "evil" (string #x1b) "[201~injection")
     t
     (list :wrapped (list :content-lacks (string #x1b))))
    (kuro-input-paste--yank-bracketed-empty-kill
     "kuro--yank with empty kill-ring entry still wraps correctly."
     ""
     t
     (list :expected (list (concat kuro--paste-open kuro--paste-close))))))

(defconst kuro-paste-test--yank-pop-send-cases
  '((kuro-input-paste--yank-pop-wraps-in-bracketed-mode
     "kuro--yank-pop wraps content with bracketed paste sequences when mode is on."
     "pop text"
     kuro--yank
     t
     0
     (list :wrapped nil))
    (kuro-input-paste--yank-pop-plain-sends-directly
     "kuro--yank-pop sends content directly when bracketed paste mode is off."
     "pop plain"
     kuro--yank
     nil
     0
     (list :expected '("pop plain")))))

(defconst kuro-paste-test--yank-pop-error-cases
  '((kuro-input-paste--yank-pop-errors-when-not-after-yank
     "kuro--yank-pop signals user-error when previous command was not a yank."
     self-insert-command
     nil
     nil
     user-error)))

(defconst kuro-paste-test--buffer-local-cases
  '((kuro-input-paste--bracketed-paste-mode-is-buffer-local
     "kuro--bracketed-paste-mode is buffer-local (isolated per buffer)."
     kuro--bracketed-paste-mode
     t
     nil)
    (kuro-input-paste--keyboard-flags-is-buffer-local
     "kuro--keyboard-flags is buffer-local (isolated per buffer)."
     kuro--keyboard-flags
     7
     0)))

(defconst kuro-paste-test--sequence-cases
  '((kuro-input-paste--paste-open-is-correct-sequence
     "kuro--paste-open is exactly ESC[200~ (DEC mode 2004 open bracket)."
     (equal kuro--paste-open "\e[200~"))
    (kuro-input-paste--paste-close-is-correct-sequence
     "kuro--paste-close is exactly ESC[201~ (DEC mode 2004 close bracket)."
     (equal kuro--paste-close "\e[201~"))
    (kuro-input-paste--paste-open-starts-with-esc
     "kuro--paste-open starts with ESC (0x1B)."
     (= (aref kuro--paste-open 0) #x1b))
    (kuro-input-paste--paste-close-starts-with-esc
     "kuro--paste-close starts with ESC (0x1B)."
     (= (aref kuro--paste-close 0) #x1b))
    (kuro-input-paste--paste-sequences-are-distinct
     "kuro--paste-open and kuro--paste-close are different strings."
     (not (equal kuro--paste-open kuro--paste-close)))))

(defconst kuro-paste-test--send-paste-or-raw-cases
  '((kuro-input-paste--send-paste-or-raw-plain-mode
     "kuro--send-paste-or-raw sends text verbatim when bracketed paste is off."
     "hello"
     nil
     (list :expected '("hello")))
    (kuro-input-paste--send-paste-or-raw-bracketed-mode-wraps
     "kuro--send-paste-or-raw wraps text with open/close sequences when mode is on."
     "world"
     t
     (list :wrapped (list :contains "world")))
    (kuro-input-paste--send-paste-or-raw-bracketed-mode-sanitizes
     "kuro--send-paste-or-raw sanitizes ESC from text in bracketed mode."
     (concat "a" (string #x1b) "b")
     t
     (list :wrapped (list :content-lacks (string #x1b))))
    (kuro-input-paste--send-paste-or-raw-plain-preserves-esc
     "kuro--send-paste-or-raw does NOT sanitize in plain mode; ESC passes through."
     (concat "a" (string #x1b) "b")
     nil
     (list :expected (list (concat "a" (string #x1b) "b"))))
    (kuro-input-paste--send-paste-or-raw-bracketed-long-string
     "kuro--send-paste-or-raw does not truncate long strings in bracketed mode."
     (make-string 10000 ?x)
     t
     (list :payload-length (+ (length kuro--paste-open)
                              10000
                              (length kuro--paste-close))))
    (kuro-input-paste--paste-newlines-sent-verbatim
     "kuro--send-paste-or-raw sends newlines verbatim in plain mode (no \\r substitution)."
     "line1\nline2\nline3"
     nil
     (list :expected '("line1\nline2\nline3")))
    (kuro-input-paste--paste-bracketed-wraps-multiline
     "kuro--send-paste-or-raw in bracketed mode wraps multi-line text correctly."
     "line1\nline2"
     t
     (list :wrapped (list :contains "line1\nline2")))
    (kuro-input-paste--paste-nul-byte-preserved-in-plain-mode
     "NUL (\\x00) bytes pass through kuro--send-paste-or-raw in plain mode unchanged."
     (concat "a" (string 0) "b")
     nil
     (list :expected (list (concat "a" (string 0) "b"))))
    (kuro-input-paste--paste-esc-stripped-in-bracketed-mode
     "ESC bytes are stripped from content inside the bracketed paste wrapper."
     (concat "a" (string #x1b) "b")
     t
     (list :wrapped (list :content-lacks (string #x1b))))
    (kuro-input-paste--paste-unicode-preserved-in-bracketed-mode
     "Unicode characters survive kuro--sanitize-paste and bracketed wrapping."
     "日本語テスト"
     t
     (list :wrapped (list :contains "日本語テスト")))
    (kuro-input-paste--send-paste-or-raw-empty-bracketed
     "kuro--send-paste-or-raw with empty string in bracketed mode sends open+close."
     ""
     t
     (list :expected (list (concat kuro--paste-open kuro--paste-close))))))

(defconst kuro-paste-test--yank-render-cases
  '((kuro-input-paste--yank-calls-schedule-render
     "kuro--yank calls kuro--schedule-immediate-render after sending."
     "text")))

(defconst kuro-paste-test--yank-pop-last-command-cases
  '((kuro-input-paste--yank-pop-accepts-yank-as-last-cmd
     "kuro--yank-pop accepts `yank' (not just kuro--yank) as previous command."
     "entry"
     yank
     nil
     0
     (list :expected '("entry")))
    (kuro-input-paste--yank-pop-accepts-kuro-yank-pop-as-last-cmd
     "kuro--yank-pop accepts kuro--yank-pop itself as a valid previous command."
     "entry2"
     kuro--yank-pop
     nil
     0
     (list :expected '("entry2")))
    (kuro-input-paste--yank-pop-sanitizes-c1-in-bracketed-mode
     "kuro--yank-pop strips C1 CSI from content when bracketed paste mode is active."
     (concat "evil" (string #x9b) "201~payload")
     kuro--yank
     t
     0
     (list :wrapped (list :content-lacks (string #x9b))))
    (kuro-input-paste--yank-pop-plain-no-wrapping
     "kuro--yank-pop in plain mode sends the raw text without any bracket sequences."
     "unwrapped"
     yank
     nil
     0
     (list :expected '("unwrapped")))
    (kuro-input-paste--yank-pop-uses-current-kill-text
     "kuro--yank-pop retrieves text from the kill ring and sends it."
     "kill-pop-text"
     kuro--yank
     nil
     0
     (list :expected '("kill-pop-text")))))

(defconst kuro-paste-test--yank-extra-cases
  '((kuro-input-paste--yank-calls-send-key-exactly-once
     "kuro--yank calls kuro--send-key exactly once per invocation."
     "single-call"
     t
     (list :wrapped nil))
    (kuro-input-paste--yank-dispatches-to-send-paste-or-raw
     "kuro--yank ends up calling kuro--send-key exactly once per call."
     "dispatch-check"
     nil
     (list :expected '("dispatch-check")))
    (kuro-input-paste--yank-empty-string-sends-empty-brackets
     "kuro--yank with empty kill-ring entry sends just the open+close sequences."
     ""
     t
     (list :expected (list (concat kuro--paste-open kuro--paste-close))))
    (kuro-input-paste--yank-multiline-correct-wrapping
     "kuro--yank with multi-line kill content wraps exactly once with open+close."
     "first\nsecond\nthird"
     t
     (list :wrapped nil))))

(defconst kuro-paste-test--extra-error-cases
  '((kuro-input-paste--yank-pop-errors-on-unrelated-last-command
     "kuro--yank-pop rejects last-command values other than yank/kuro--yank/kuro--yank-pop."
     forward-char
     nil
     nil
     user-error)))

(defconst kuro-paste-test--initial-value-cases
  '((kuro-input-paste--keyboard-flags-initial-value-is-zero
     "kuro--keyboard-flags has an initial value of 0 in a fresh buffer."
     kuro--keyboard-flags
     0)))

(defconst kuro-paste-test--sequence-structure-cases
  '((kuro-input-paste--bracketed-sequence-open-close-structure
     "Bracketed paste sequence has open=ESC[200~ and close=ESC[201~ structure."
     ((equal kuro--paste-open  "\e[200~")
      (equal kuro--paste-close "\e[201~")
      (string-prefix-p "\e[" kuro--paste-open)
      (string-suffix-p "~" kuro--paste-open)
      (string-prefix-p "\e[" kuro--paste-close)
      (string-suffix-p "~" kuro--paste-close)))))

(provide 'kuro-input-paste-test-cases)
;;; kuro-input-paste-test-cases.el ends here
