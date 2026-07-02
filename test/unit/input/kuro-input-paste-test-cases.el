;;; kuro-input-paste-test-cases.el --- Paste test case data  -*- lexical-binding: t; -*-

;;; Code:

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
    (kuro-input-paste--yank-raw-prefix-4-fetches-fourth-entry
     "kuro--yank accepts Emacs raw prefix list values."
     ("entry-1" "entry-2" "entry-3" "entry-4")
     '(4)
     ("entry-1"))
    (kuro-input-paste--yank-no-arg-fetches-most-recent
     "kuro--yank with no arg (nil) fetches the most recent kill-ring entry."
     ("top-of-ring")
     nil
     ("top-of-ring"))))

(defconst kuro-paste-test--yank-error-cases
  '((kuro-input-paste--yank-rejects-zero-arg
     "kuro--yank rejects zero because yank indices are one-based at the command boundary."
     ("only-entry")
     0
     user-error)
    (kuro-input-paste--yank-rejects-negative-arg
     "kuro--yank rejects negative prefix values before kill-ring lookup."
     ("only-entry")
     -1
     user-error)
    (kuro-input-paste--yank-rejects-string-arg
     "kuro--yank rejects non-prefix programmatic arguments before kill-ring lookup."
     ("only-entry")
     "1"
     wrong-type-argument)))

(defconst kuro-paste-test--yank-send-cases
  '((kuro-input-paste--yank-plain-sends-text-directly
     "kuro--yank sends text to `kuro--send-paste'."
     "clipboard text"
     nil
     (list :expected '("clipboard text")))
    (kuro-input-paste--yank-plain-preserves-content
     "kuro--yank passes escape-containing content verbatim to Rust."
     (concat "raw" (string #x1b) "content")
     nil
     (list :expected (list (concat "raw" (string #x1b) "content"))))
    (kuro-input-paste--yank-bracketed-cache-is-ignored
     "kuro--yank ignores the cached bracketed paste mode and delegates to Rust."
     "pasted text"
     t
     (list :expected '("pasted text")))
    (kuro-input-paste--yank-bracketed-cache-preserves-esc
     "kuro--yank leaves escape sanitization to the Rust paste boundary."
     (concat "evil" (string #x1b) "[201~injection")
     t
     (list :expected (list (concat "evil" (string #x1b) "[201~injection"))))
    (kuro-input-paste--yank-bracketed-empty-kill
     "kuro--yank sends an empty kill-ring entry as an empty paste payload."
     ""
     t
     (list :expected '("")))))

(defconst kuro-paste-test--yank-pop-send-cases
  '((kuro-input-paste--yank-pop-bracketed-cache-is-ignored
     "kuro--yank-pop ignores cached bracketed paste mode and delegates to Rust."
     "pop text"
     kuro--yank
     t
     0
     (list :expected '("pop text")))
    (kuro-input-paste--yank-pop-plain-sends-directly
     "kuro--yank-pop sends content through `kuro--send-paste'."
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

(defconst kuro-paste-test--send-paste-or-raw-cases
  '((kuro-input-paste--send-paste-or-raw-plain-mode
     "kuro--send-paste-or-raw delegates text to `kuro--send-paste'."
     "hello"
     nil
     (list :expected '("hello")))
    (kuro-input-paste--send-paste-or-raw-bracketed-cache-is-ignored
     "kuro--send-paste-or-raw ignores cached bracketed paste mode."
     "world"
     t
     (list :expected '("world")))
    (kuro-input-paste--send-paste-or-raw-bracketed-cache-preserves-esc
     "kuro--send-paste-or-raw leaves escape sanitization to Rust."
     (concat "a" (string #x1b) "b")
     t
     (list :expected (list (concat "a" (string #x1b) "b"))))
    (kuro-input-paste--send-paste-or-raw-plain-preserves-esc
     "kuro--send-paste-or-raw passes ESC bytes through to Rust."
     (concat "a" (string #x1b) "b")
     nil
     (list :expected (list (concat "a" (string #x1b) "b"))))
    (kuro-input-paste--send-paste-or-raw-bracketed-long-string
     "kuro--send-paste-or-raw does not truncate long strings."
     (make-string 10000 ?x)
     t
     (list :expected (list (make-string 10000 ?x))))
    (kuro-input-paste--paste-newlines-sent-verbatim
     "kuro--send-paste-or-raw sends newlines verbatim."
     "line1\nline2\nline3"
     nil
     (list :expected '("line1\nline2\nline3")))
    (kuro-input-paste--paste-bracketed-cache-preserves-multiline
     "kuro--send-paste-or-raw passes multi-line text verbatim to Rust."
     "line1\nline2"
     t
     (list :expected '("line1\nline2")))
    (kuro-input-paste--paste-nul-byte-preserved-in-plain-mode
     "NUL (\\x00) bytes pass through kuro--send-paste-or-raw unchanged."
     (concat "a" (string 0) "b")
     nil
     (list :expected (list (concat "a" (string 0) "b"))))
    (kuro-input-paste--paste-esc-preserved-for-rust-boundary
     "ESC bytes pass through to the Rust paste boundary."
     (concat "a" (string #x1b) "b")
     t
     (list :expected (list (concat "a" (string #x1b) "b"))))
    (kuro-input-paste--paste-unicode-preserved-in-bracketed-mode
     "Unicode characters pass through to the Rust paste boundary."
     "日本語テスト"
     t
     (list :expected '("日本語テスト")))
    (kuro-input-paste--send-paste-or-raw-empty-bracketed
     "kuro--send-paste-or-raw sends an empty string as an empty paste payload."
     ""
     t
     (list :expected '("")))))

(defconst kuro-paste-test--yank-render-cases
  '((kuro-input-paste--yank-calls-schedule-render
     "kuro--yank calls kuro--schedule-immediate-render after sending."
     "text")))

(defconst kuro-paste-test--yank-pop-render-cases
  '((kuro-input-paste--yank-pop-calls-schedule-render
     "kuro--yank-pop calls kuro--schedule-immediate-render after sending."
     "text"
     kuro--yank
     0)))

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
    (kuro-input-paste--yank-pop-bracketed-cache-preserves-c1
     "kuro--yank-pop leaves C1 CSI sanitization to the Rust paste boundary."
     (concat "evil" (string #x9b) "201~payload")
     kuro--yank
     t
     0
     (list :expected (list (concat "evil" (string #x9b) "201~payload"))))
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
  '((kuro-input-paste--yank-calls-send-paste-exactly-once
     "kuro--yank calls `kuro--send-paste' exactly once per invocation."
     "single-call"
     t
     (list :expected '("single-call")))
    (kuro-input-paste--yank-dispatches-to-send-paste-or-raw
     "kuro--yank dispatches through the paste boundary exactly once per call."
     "dispatch-check"
     nil
     (list :expected '("dispatch-check")))
    (kuro-input-paste--yank-empty-string-sends-empty-paste
     "kuro--yank with empty kill-ring entry sends an empty paste payload."
     ""
     t
     (list :expected '("")))
    (kuro-input-paste--yank-multiline-passes-verbatim
     "kuro--yank with multi-line kill content delegates the verbatim payload to Rust."
     "first\nsecond\nthird"
     t
     (list :expected '("first\nsecond\nthird")))))

(defconst kuro-paste-test--extra-error-cases
  '((kuro-input-paste--yank-pop-errors-on-unrelated-last-command
     "kuro--yank-pop rejects last-command values other than yank/kuro--yank/kuro--yank-pop."
     forward-char
     nil
     nil
     user-error)
    (kuro-input-paste--yank-pop-rejects-string-arg
     "kuro--yank-pop rejects non-prefix programmatic arguments before kill-ring lookup."
     kuro--yank
     nil
     "1"
     wrong-type-argument)))

(defconst kuro-paste-test--initial-value-cases
  '((kuro-input-paste--keyboard-flags-initial-value-is-zero
     "kuro--keyboard-flags has an initial value of 0 in a fresh buffer."
     kuro--keyboard-flags
     0)))

(provide 'kuro-input-paste-test-cases)
;;; kuro-input-paste-test-cases.el ends here
