;;; kuro-renderer-test-cases.el --- Shared renderer test cases  -*- lexical-binding: t; -*-

;;; Commentary:

;; Data tables used by renderer test-generating macros.

;;; Code:

(defconst kuro-renderer-test--apply-title-update-cases
  '((kuro-renderer-apply-title-update-renames-buffer
     "kuro--apply-title-update renames the buffer to *kuro: <title>* format."
     "vim"
     ((buffer-name "\\*kuro: vim\\*")))
    (kuro-renderer-apply-title-update-sanitizes-title
     "kuro--apply-title-update sanitizes the title (strips control chars)."
     (concat "bash" (string #x1b) "[31m")
     ((buffer-name "\\*kuro: bash\\[31m\\*")))
    (kuro-renderer-apply-title-update-noop-on-nil-title
     "kuro--apply-title-update does not rename when FFI returns nil."
     nil
     ((buffer-name-unchanged)))
    (kuro-renderer-apply-title-update-noop-on-empty-title
     "kuro--apply-title-update does not rename when FFI returns an empty string."
     ""
     ((buffer-name-unchanged)))
    (kuro-renderer-apply-title-update-sets-frame-name
     "kuro--apply-title-update sets the frame name via set-frame-parameter."
     "htop"
     ((frame-name "htop"))))
  "Cases for `kuro--apply-title-update'.")

(defconst kuro-renderer-test--update-tui-streaming-timer-cases
  '((kuro-renderer-update-tui-increments-frame-count-when-full-dirty
     "kuro--update-tui-streaming-timer increments kuro--tui-mode-frame-count on full-dirty frames."
     ((kuro--last-rows 24)
      (kuro--tui-mode-frame-count 0)
      (kuro--last-dirty-count 20))
     ((frame-count 1)))
    (kuro-renderer-update-tui-resets-count-when-below-threshold
     "kuro--update-tui-streaming-timer resets frame count when dirty-row fraction is below threshold."
     ((kuro--last-rows 24)
      (kuro--tui-mode-frame-count 3)
      (kuro--last-dirty-count 5))
     ((frame-count 0)))
    (kuro-renderer-update-tui-stops-idle-timer-at-threshold
     "kuro--update-tui-streaming-timer calls kuro--stop-stream-idle-timer when threshold is reached."
     ((kuro--last-rows 24)
      (kuro--tui-mode-frame-count (1- kuro--tui-mode-threshold))
      (kuro--last-dirty-count 20))
     ((stop-called t)
      (frame-count kuro--tui-mode-threshold)
      (tui-active t)
      (switch-rate kuro-tui-frame-rate)))
    (kuro-renderer-update-tui-restarts-idle-timer-on-tui-exit
     "kuro--update-tui-streaming-timer calls kuro--start-stream-idle-timer when leaving TUI mode."
     ((kuro--last-rows 24)
      (kuro--tui-mode-frame-count kuro--tui-mode-threshold)
      (kuro--tui-mode-active t)
      (kuro--last-dirty-count 5))
     ((start-called t)
      (frame-count 0)
      (tui-active nil)
      (switch-rate kuro-frame-rate)))
    (kuro-renderer-update-tui-noop-when-streaming-mode-disabled
     "kuro--update-tui-streaming-timer is a no-op when kuro-streaming-latency-mode is nil."
     ((kuro-streaming-latency-mode nil)
      (kuro--last-rows 24)
      (kuro--tui-mode-frame-count 0)
      (kuro--last-dirty-count 20))
     ((stop-called nil)
      (start-called nil)
      (switch-rate nil)
      (frame-count 0)))
    (kuro-renderer-update-tui-noop-when-last-rows-zero
     "kuro--update-tui-streaming-timer is a no-op when kuro--last-rows is 0."
     ((kuro--last-rows 0)
      (kuro--tui-mode-frame-count 0)
      (kuro--last-dirty-count 20))
     ((frame-count 0)))
    (kuro-renderer-update-tui-noop-on-zero-dirty
     "kuro--update-tui-streaming-timer handles zero dirty rows without error."
     ((kuro--last-rows 24)
      (kuro--tui-mode-frame-count 0)
      (kuro--last-dirty-count 0))
     ((frame-count 0))))
  "Cases for `kuro--update-tui-streaming-timer'.")

(defconst kuro-renderer-test--sanitize-title-base-cases
  '((kuro-renderer-sanitize-title-clean-ascii
     "Clean ASCII strings pass through unchanged."
     (("bash" "bash")
      ("vim - file.txt" "vim - file.txt")))
    (kuro-renderer-sanitize-title-strips-control-chars
     "Control characters (U+0000-U+001F, U+007F) are stripped."
     (((concat "a" (string 1) "b") "ab")
      ((concat "a" (string #x1f) "b") "ab")
      ((concat "a" (string #x7f) "b") "ab")
      ((concat "a" (string #x1b) "b") "ab")))
    (kuro-renderer-sanitize-title-strips-bidi-overrides
     "Unicode bidi override codepoints (U+202A-U+202E) are stripped."
     (((concat "a" "\u202e" "b") "ab")
      ((concat "a" "\u202a" "b") "ab")))
    (kuro-renderer-sanitize-title-strips-isolates
     "Unicode directional isolates (U+2066-U+2069) are stripped."
     (((concat "a" "\u2066" "b") "ab")
      ((concat "a" "\u2069" "b") "ab")))
    (kuro-renderer-sanitize-title-empty-string
     "Empty string remains empty."
     (("" "")))
    (kuro-renderer-sanitize-title-mixed-content
     "Normal chars around control chars: control chars stripped, rest preserved."
     (("vim\x00\x1b[31m file.txt" "vim[31m file.txt"))))
  "Base cases for `kuro--sanitize-title'.")

(defconst kuro-renderer-test--update-line-full-cases
  '((kuro-renderer-update-line-replaces-content
     "kuro--update-line-full replaces the text on the specified row."
     "original\nsecond\n"
     0
     "replaced"
     ((line-matches 0 "replaced\n")))
    (kuro-renderer-update-line-preserves-other-lines
     "kuro--update-line-full does not affect other rows."
     "line0\nline1\nline2\n"
     0
     "updated"
     ((line-matches 1 "line1\n")
      (line-matches 2 "line2\n")))
    (kuro-renderer-update-line-appends-newline
     "kuro--update-line-full always appends a newline after the text."
     "old\n"
     0
     "new"
     ((line-matches 0 "new\n")))
    (kuro-renderer-update-line-empty-text
     "kuro--update-line-full with empty string produces a lone newline on the row."
     "content\n"
     0
     ""
     ((line-matches 0 "\n")))
    (kuro-renderer-update-line-unicode
     "kuro--update-line-full handles multi-byte Unicode content correctly."
     "old\n"
     0
     "日本語テスト"
     ((line-matches 0 "日本語テスト\n")))
    (kuro-renderer-update-line-preserves-line-count
     "kuro--update-line-full preserves the total number of lines."
     "a\nb\nc\n"
     1
     "B"
     ((line-count 3)))
    (kuro-renderer-update-line-nil-text-is-noop
     "kuro--update-line-full with nil text is a no-op (guard clause)."
     "keep\n"
     0
     nil
     ((line-matches 0 "keep\n"))))
  "Base cases for `kuro--update-line-full'.")

(defconst kuro-renderer-test--reset-cursor-cache-cases
  '((kuro-renderer-reset-cursor-cache-clears-all-four-fields
     "kuro--reset-cursor-cache sets all four cursor cache vars to nil."
     ((kuro--last-cursor-row 5)
      (kuro--last-cursor-col 10)
      (kuro--last-cursor-visible t)
      (kuro--last-cursor-shape 'box))
     1)
    (kuro-renderer-reset-cursor-cache-idempotent
     "Calling kuro--reset-cursor-cache twice is safe and keeps all vars nil."
     ((kuro--last-cursor-row 3)
      (kuro--last-cursor-col 7)
      (kuro--last-cursor-visible t)
      (kuro--last-cursor-shape '(hbar . 2)))
     2)
    (kuro-renderer-reset-cursor-cache-already-nil-is-noop
     "kuro--reset-cursor-cache with all fields already nil does not error."
     ((kuro--last-cursor-row nil)
      (kuro--last-cursor-col nil)
      (kuro--last-cursor-visible nil)
      (kuro--last-cursor-shape nil))
     1))
  "Runtime cases for `kuro--reset-cursor-cache'.")

(defconst kuro-renderer-test--sanitize-title-edge-cases
  `((kuro-renderer-sanitize-title-strips-rlm
     "kuro--sanitize-title strips U+200F RIGHT-TO-LEFT MARK."
     ((,(concat "a" "\u200f" "b") "ab")))
    (kuro-renderer-sanitize-title-strips-null-byte
     "kuro--sanitize-title strips embedded null bytes (U+0000)."
     ((,(concat "a" (string 0) "b") "ab")))
    (kuro-renderer-sanitize-title-strips-tab
     "kuro--sanitize-title strips TAB (U+0009, a C0 control char)."
     ((,(concat "a" (string 9) "b") "ab")))
    (kuro-renderer-sanitize-title-all-bidi-overrides
     "kuro--sanitize-title strips the full U+202A-U+202E bidi override range."
     ,(mapcar (lambda (cp) (list (concat "x" (string cp) "y") "xy"))
              '(#x202a #x202b #x202c #x202d #x202e)))
    (kuro-renderer-sanitize-title-all-isolates
     "kuro--sanitize-title strips the full U+2066-U+2069 directional isolate range."
     ,(mapcar (lambda (cp) (list (concat "x" (string cp) "y") "xy"))
              '(#x2066 #x2067 #x2068 #x2069)))
    (kuro-renderer-sanitize-title-preserves-unicode-non-bidi
     "kuro--sanitize-title passes through harmless non-ASCII Unicode unchanged."
     (("日本語" "日本語")
      ("émoji 🎉" "émoji 🎉"))))
  "Input/expected cases for `kuro--sanitize-title' edge coverage.")

(provide 'kuro-renderer-test-cases)
;;; kuro-renderer-test-cases.el ends here
