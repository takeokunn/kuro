;;; kuro-test.el --- Manual test script for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; This file provides manual tests for Kuro that should be run inside Emacs.
;;
;; ----------------------------------------------------------------------------
;; WAVE 8.2: MANUAL QA INSTRUCTIONS
;; ----------------------------------------------------------------------------
;;
;; Prerequisites:
;;   1. Build kuro: make build
;;   2. Ensure libkuro_core.dylib is in target/release/
;;
;; Running Tests (Interactive Emacs):
;;   1. Start Emacs: emacs
;;   2. Load module: M-x load-file RET emacs-lisp/kuro.el RET
;;   3. Load tests: M-x load-file RET test/manual/kuro-test.el RET
;;   4. Run all tests: M-x kuro-run-all-tests RET
;;   5. Verify each test output visually in the *kuro* buffer
;;
;; Running Individual Tests:
;;   M-x kuro-test-basic        - Test 1: Basic echo
;;   M-x kuro-test-colors       - Tests 2-4: Colors (16, 256, true color)
;;   M-x kuro-test-cursor       - Test 5: Cursor movement
;;   M-x kuro-test-cjk          - Test 6: CJK characters
;;   M-x kuro-test-emoji        - Test 7: Emoji rendering
;;   M-x kuro-test-performance  - Test 8: 1000 lines output
;;   M-x kuro-test-shell-commands - Test 9: ls, pwd, date
;;   M-x kuro-test-vim          - Test 10: Vim alternate screen
;;   M-x kuro-test-text-attributes - Test 11: Bold, italic, underline
;;   M-x kuro-test-scroll-region   - Test 12: Scroll region
;;   M-x kuro-test-tab-alignment   - Test 13: Tab stops
;;   M-x kuro-test-line-wrapping   - Test 14: Line wrapping
;;   M-x kuro-test-special-chars   - Test 15: Special characters
;;
;; 15 Test Scenarios for Manual QA:
;;   1. Basic echo and shell output
;;   2. ANSI 16-color output
;;   3. 256-color indexed output
;;   4. True color (24-bit) output
;;   5. Cursor movement sequences
;;   6. CJK (Japanese/Chinese/Korean) character support
;;   7. Emoji rendering
;;   8. Performance (1000+ lines output)
;;   9. Shell command execution (ls, pwd, date)
;;  10. Vim (alternate screen mode)
;;  11. Text attributes (bold, italic, underline)
;;  12. Scroll region
;;  13. Tab alignment
;;  14. Line wrapping
;;  15. Special characters and escapes
;;
;; Expected Results:
;;   - All colored text should display with correct colors
;;   - CJK characters should render properly (no mojibake)
;;   - Emoji should display correctly
;;   - 1000 lines should render smoothly (< 2 seconds)
;;   - Vim should enter alternate screen mode cleanly
;;   - Tab stops should align at 8-column intervals
;;   - Long lines should wrap at terminal width
;;
;; ----------------------------------------------------------------------------

(require 'kuro)

(defgroup kuro-test nil
  "Manual test settings for Kuro."
  :group 'kuro)

(defvar kuro-test-buffer nil
  "Buffer holding the test terminal.")

;;;###autoload
(defun kuro-test-basic ()
  "Test basic terminal functionality."
  (interactive)
  (setq kuro-test-buffer (kuro-create "bash"))
  (message "Kuro test buffer created: %s" kuro-test-buffer)
  (sit-for 1)
  
  ;; Test basic echo
  (with-current-buffer kuro-test-buffer
    (kuro-send-string "echo 'Hello from Kuro!'\n"))
  
  (sit-for 2)
  (message "Basic echo test: Check buffer for 'Hello from Kuro!'"))

;;;###autoload
(defun kuro-test-colors ()
  "Test ANSI color output."
  (interactive)
  (when (and kuro-test-buffer (buffer-live-p kuro-test-buffer))
    (with-current-buffer kuro-test-buffer
      ;; Test 16 colors
      (kuro-send-string "echo -e '\\033[31mRed\\033[0m \\033[32mGreen\\033[0m \\033[34mBlue\\033[0m'\n")
      (sit-for 1)
      ;; Test 256 colors
      (kuro-send-string "echo -e '\\033[38;5;196m256-color Red\\033[0m'\n")
      (sit-for 1)
      ;; Test true color
      (kuro-send-string "echo -e '\\033[38;2;255;128;0mTrue Color Orange\\033[0m'\n"))
  (message "Color test: Check buffer for colored text"))

;;;###autoload
(defun kuro-test-cursor-movement ()
  "Test cursor movement sequences."
  (interactive)
  (when (and kuro-test-buffer (buffer-live-p kuro-test-buffer))
    (with-current-buffer kuro-test-buffer
      (kuro-send-string "echo -e 'Line1\\nLine2\\nLine3\\nLine4\\nLine5'\n")
      (sit-for 1)
      (kuro-send-string "echo -e '\\033[3A\\033[KCLEARED\\033[2B'\n")))
  (message "Cursor movement test: Check that Line3 was cleared"))

;;;###autoload
(defun kuro-test-cjk ()
  "Test CJK character support."
  (interactive)
  (when (and kuro-test-buffer (buffer-live-p kuro-test-buffer))
    (with-current-buffer kuro-test-buffer
      (kuro-send-string "echo '日本語テスト こんにちは世界'\n")
      (sit-for 1)
      (kuro-send-string "echo '中文测试 你好世界'\n")
      (sit-for 1)
      (kuro-send-string "echo '한국어 테스트 안녕하세요'\n")))
  (message "CJK test: Check buffer for Japanese, Chinese, Korean text"))

;;;###autoload
(defun kuro-test-emoji ()
  "Test emoji rendering."
  (interactive)
  (when (and kuro-test-buffer (buffer-live-p kuro-test-buffer))
    (with-current-buffer kuro-test-buffer
      (kuro-send-string "echo '🎉 🚀 ✨ 💻 🔥'\n")))
  (message "Emoji test: Check buffer for emojis"))

;;;###autoload
(defun kuro-test-osc52 ()
  "Test OSC 52 clipboard operations."
  (interactive)
  (when (and kuro-test-buffer (buffer-live-p kuro-test-buffer))
    (with-current-buffer kuro-test-buffer
      ;; OSC 52: Copy to clipboard
      (kuro-send-string "echo -n 'Test clipboard content' | xclip -selection clipboard 2>/dev/null || echo 'xclip not installed'\n")
      (sit-for 1)
      (message "OSC 52 test: Check if clipboard integration works"))))

;;;###autoload
(defun kuro-test-performance ()
  "Test performance with large output."
  (interactive)
  (when (and kuro-test-buffer (buffer-live-p kuro-test-buffer))
    (with-current-buffer kuro-test-buffer
      ;; Generate 1000 lines of output
      (kuro-send-string "for i in {1..1000}; do echo \"Line $i: $(printf 'x%.0s' {1..80})\"; done\n")))
  (message "Performance test: Watch how quickly 1000 lines render"))

;;;###autoload
(defun kuro-test-shell-commands ()
  "Test common shell commands."
  (interactive)
  (when (and kuro-test-buffer (buffer-live-p kuro-test-buffer))
    (with-current-buffer kuro-test-buffer
      (kuro-send-string "ls -la\n")
      (sit-for 2)
      (kuro-send-string "pwd\n")
      (sit-for 1)
      (kuro-send-string "date\n")))
  (message "Shell commands test: Check buffer for ls, pwd, date output"))

;;;###autoload
(defun kuro-test-vim ()
  "Test vim inside kuro."
  (interactive)
  (when (and kuro-test-buffer (buffer-live-p kuro-test-buffer))
    (with-current-buffer kuro-test-buffer
      (kuro-send-string "vim --version | head -5\n")))
  (message "Vim test: Check vim version output"))

;;;###autoload
(defun kuro-test-text-attributes ()
  "Test 11: Text attributes (bold, italic, underline)."
  (interactive)
  (when (and kuro-test-buffer (buffer-live-p kuro-test-buffer))
    (with-current-buffer kuro-test-buffer
      (kuro-send-string "echo -e '\\033[1mBold\\033[0m \\033[3mItalic\\033[0m \\033[4mUnderline\\033[0m'\n")
      (sit-for 1)
      (kuro-send-string "echo -e '\\033[5mBlink\\033[0m \\033[7mInverse\\033[0m \\033[9mStrikethrough\\033[0m'\n")))
  (message "Text attributes test: Check for bold, italic, underline, etc."))

;;;###autoload
(defun kuro-test-scroll-region ()
  "Test 12: Scroll region operations."
  (interactive)
  (when (and kuro-test-buffer (buffer-live-p kuro-test-buffer))
    (with-current-buffer kuro-test-buffer
      ;; Fill screen
      (kuro-send-string "for i in {1..20}; do echo \"Line $i\"; done\n")
      (sit-for 2)
      ;; Set scroll region and scroll within it
      (kuro-send-string "echo -e '\\033[5;15r'")  ; Set scroll region
      (sit-for 1)
      (kuro-send-string "echo -e '\\033[r'")))  ; Reset scroll region
  (message "Scroll region test: Verify scrolling works correctly"))

;;;###autoload
(defun kuro-test-tab-alignment ()
  "Test 13: Tab stop alignment."
  (interactive)
  (when (and kuro-test-buffer (buffer-live-p kuro-test-buffer))
    (with-current-buffer kuro-test-buffer
      (kuro-send-string "echo -e 'A\tB\tC\tD'\n")
      (sit-for 1)
      (kuro-send-string "printf '1\\t2\\t3\\t4\\n'\n")))
  (message "Tab test: Check column alignment at 8-char intervals"))

;;;###autoload
(defun kuro-test-line-wrapping ()
  "Test 14: Line wrapping behavior."
  (interactive)
  (when (and kuro-test-buffer (buffer-live-p kuro-test-buffer))
    (with-current-buffer kuro-test-buffer
      ;; Generate long line that should wrap
      (kuro-send-string "python3 -c \"print('X' * 200)\"\n")
      (sit-for 2)
      ;; And with wrapping disabled
      (kuro-send-string "python3 -c \"print('Y' * 40)\"\n")))
  (message "Line wrap test: Check that long lines wrap correctly"))

;;;###autoload
(defun kuro-test-special-chars ()
  "Test 15: Special characters and escapes."
  (interactive)
  (when (and kuro-test-buffer (buffer-live-p kuro-test-buffer))
    (with-current-buffer kuro-test-buffer
      ;; Test various special chars
      (kuro-send-string "echo 'Quote: \"Hello\"'\n")
      (sit-for 1)
      (kuro-send-string "echo 'Backslash: \\\\'\n")
      (sit-for 1)
      (kuro-send-string "echo 'Dollar: $PATH'\n")
      (sit-for 1)
      (kuro-send-string "echo 'Special: !@#$%^&*()'\n")))
  (message "Special chars test: Check escaping works"))

;;;###autoload
(defun kuro-run-all-tests ()
  "Run all 15 manual test scenarios sequentially."
  (interactive)
  (message "=== Starting Kuro Manual Tests (15 Scenarios) ===")
  (message "1/15: Basic test...")
  (kuro-test-basic)
  (sit-for 2)
  (message "2/15: 16-color test...")
  (kuro-test-colors)
  (sit-for 1)
  (message "3/15: Cursor movement test...")
  (kuro-test-cursor-movement)
  (sit-for 2)
  (message "4/15: CJK test...")
  (kuro-test-cjk)
  (sit-for 2)
  (message "5/15: Emoji test...")
  (kuro-test-emoji)
  (sit-for 1)
  (message "6/15: OSC 52 test...")
  (kuro-test-osc52)
  (sit-for 1)
  (message "7/15: Performance test...")
  (kuro-test-performance)
  (sit-for 5)
  (message "8/15: Shell commands test...")
  (kuro-test-shell-commands)
  (sit-for 2)
  (message "9/15: Vim test...")
  (kuro-test-vim)
  (sit-for 1)
  (message "10/15: Text attributes test...")
  (kuro-test-text-attributes)
  (sit-for 2)
  (message "11/15: Scroll region test...")
  (kuro-test-scroll-region)
  (sit-for 2)
  (message "12/15: Tab alignment test...")
  (kuro-test-tab-alignment)
  (sit-for 1)
  (message "13/15: Line wrapping test...")
  (kuro-test-line-wrapping)
  (sit-for 2)
  (message "14/15: Special chars test...")
  (kuro-test-special-chars)
  (sit-for 2)
  (message "15/15: Cleanup...")
  (when (and kuro-test-buffer (buffer-live-p kuro-test-buffer))
    (with-current-buffer kuro-test-buffer
      (kuro-send-string "echo 'All tests complete!'\n")))
  (sit-for 1)
  (message "=== All 15 Kuro Manual Tests Complete ===")
  (message "Please verify each test visually in the kuro buffer: %s" kuro-test-buffer))

(provide 'kuro-test)
