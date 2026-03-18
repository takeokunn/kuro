#!/usr/bin/env bash
# Kuro TUI Test Script
# This script tests various terminal escape sequences to find rendering bugs

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((TESTS_PASSED++))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((TESTS_FAILED++))
}

section() {
    echo ""
    echo -e "${YELLOW}=== $1 ===${NC}"
}

# Wait for user to observe
wait_observation() {
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# --------------------------------------------
# Test 1: Basic Output
# --------------------------------------------
section "Basic Output Tests"

echo "Test 1.1: Simple text output"
echo "Hello, World!"
sleep 0.5
pass "Simple text output"

echo "Test 1.2: Multi-line output"
printf "Line 1\nLine 2\nLine 3\n"
sleep 0.5
pass "Multi-line output"

echo "Test 1.3: Long line (should wrap)"
printf '%100s\n' | tr ' ' 'X'
sleep 0.5
pass "Long line wrap"

# --------------------------------------------
# Test 2: Cursor Movement
# --------------------------------------------
section "Cursor Movement Tests"

echo "Test 2.1: Cursor positioning (CUP)"
printf "\e[5;10H"
printf "X at (5,10)"
sleep 0.5
pass "CUP positioning"

echo "Test 2.2: Cursor up (CUU)"
printf "\e[10;1H"
printf "Start"
printf "\e[3A"
printf "Up3"
sleep 0.5
pass "Cursor up"

echo "Test 2.3: Cursor down (CUD)"
printf "\e[1;1H"
printf "Start"
printf "\e[3B"
printf "Down3"
sleep 0.5
pass "Cursor down"

echo "Test 2.4: Cursor forward (CUF)"
printf "\e[15;1H"
printf "A"
printf "\e[5C"
printf "B"
sleep 0.5
pass "Cursor forward"

echo "Test 2.5: Cursor back (CUB)"
printf "\e[15;20H"
printf "A"
printf "\e[5D"
printf "B"
sleep 0.5
pass "Cursor back"

# --------------------------------------------
# Test 3: Erase Operations
# --------------------------------------------
section "Erase Operations"

echo "Test 3.1: Erase to end of line (EL0)"
printf "\e[1;1H"
printf "XXXXXXXXXX"
printf "\e[1;5H"
printf "\e[K"  # Should erase from col 5 to end
sleep 0.5
pass "EL mode 0"

echo "Test 3.2: Erase from start of line (EL1)"
printf "\e[3;1H"
printf "XXXXXXXXXX"
printf "\e[3;6H"
printf "\e[1K"  # Should erase from start to col 6
sleep 0.5
pass "EL mode 1"

echo "Test 3.3: Erase entire line (EL2)"
printf "\e[5;1H"
printf "XXXXXXXXXX"
printf "\e[5;1H"
printf "\e[2K"
sleep 0.5
pass "EL mode 2"

echo "Test 3.4: Erase to end of screen (ED0)"
printf "\e[7;1H"
printf "Clear from here down...\e[J"
sleep 0.5
pass "ED mode 0"

# --------------------------------------------
# Test 4: Scroll Region
# --------------------------------------------
section "Scroll Region Tests"

echo "Test 4.1: DECSTBM - Set scroll region"
printf "\e[3;8r"  # Region rows 3-8
printf "\e[3;1H"
for i in {1..10}; do
    printf "Scroll region line %d\n" "$i"
    sleep 0.1
done
printf "\e[r"  # Reset scroll region
sleep 0.5
pass "DECSTBM scroll region"

# --------------------------------------------
# Test 5: SGR (Colors/Attributes)
# --------------------------------------------
section "SGR Attributes Tests"

echo "Test 5.1: Bold"
printf "\e[1mBold text\e[0m Normal\n"
sleep 0.3
pass "Bold"

echo "Test 5.2: Italic"
printf "\e[3mItalic text\e[0m Normal\n"
sleep 0.3
pass "Italic"

echo "Test 5.3: Underline"
printf "\e[4mUnderline\e[0m Normal\n"
sleep 0.3
pass "Underline"

echo "Test 5.4: Strikethrough"
printf "\e[9mStrikethrough\e[0m Normal\n"
sleep 0.3
pass "Strikethrough"

echo "Test 5.5: 16 colors"
printf "\e[30mBlack\e[0m "
printf "\e[31mRed\e[0m "
printf "\e[32mGreen\e[0m "
printf "\e[33mYellow\e[0m "
printf "\e[34mBlue\e[0m "
printf "\e[35mMagenta\e[0m "
printf "\e[36mCyan\e[0m "
printf "\e[37mWhite\e[0m\n"
sleep 0.3
pass "16 colors"

echo "Test 5.6: 256 colors"
for i in 0 1 2 16 17 124 125 196 197 208 231 232 233 244 255; do
    printf "\e[38;5;%dm█" "$i"
done
printf "\e[0m\n"
sleep 0.3
pass "256 colors"

echo "Test 5.7: True color"
printf "\e[38;2;255;0;0mRed\e[0m "
printf "\e[38;2;0;255;0mGreen\e[0m "
printf "\e[38;2;0;0;255mBlue\e[0m\n"
sleep 0.3
pass "True color"

# --------------------------------------------
# Test 6: Unicode/CJK
# --------------------------------------------
section "Unicode/CJK Tests"

echo "Test 6.1: Japanese (Hiragana)"
echo "あいうえお かきくけこ さしすせそ"
sleep 0.3
pass "Japanese hiragana"

echo "Test 6.2: Japanese (Kanji)"
echo "日本語 東京 漢字 漢字検定"
sleep 0.3
pass "Japanese kanji"

echo "Test 6.3: Chinese (Simplified)"
echo "中文 简体 北京 上海"
sleep 0.3
pass "Chinese simplified"

echo "Test 6.4: Korean (Hangul)"
echo "한글 한국어 서울 부산"
sleep 0.3
pass "Korean hangul"

echo "Test 6.5: Emoji"
echo "🎉 🎊 🎁 🎨 👍 👎 ❤️ 💔"
sleep 0.3
pass "Emoji"

echo "Test 6.6: Combining characters"
echo "é (e + combining acute) café naïve"
sleep 0.3
pass "Combining characters"

echo "Test 6.7: CJK at line end (wrap test)"
echo "日本語テスト日本語テスト日本語テスト日本語テスト日本語テスト日本語テスト日本語テスト"
sleep 0.3
pass "CJK wrap"

# --------------------------------------------
# Test 7: Insert/Delete Operations
# --------------------------------------------
section "Insert/Delete Operations"

echo "Test 7.1: Insert characters (ICH)"
printf "\e[5;1H"
printf "ABCDEFGHIJ"
printf "\e[5;5H"
printf "\e[3@"  # Insert 3 blanks at col 5
sleep 0.5
pass "Insert characters"

echo "Test 7.2: Delete characters (DCH)"
printf "\e[6;1H"
printf "ABCDEFGHIJ"
printf "\e[6;5H"
printf "\e[3P"  # Delete 3 chars at col 5
sleep 0.5
pass "Delete characters"

echo "Test 7.3: Insert lines (IL)"
printf "\e[8;1H"
printf "Line 1\nLine 2\nLine 3\nLine 4"
printf "\e[9;1H"
printf "\e[2L"  # Insert 2 blank lines
sleep 0.5
pass "Insert lines"

echo "Test 7.4: Delete lines (DL)"
printf "\e[13;1H"
printf "Line A\nLine B\nLine C\nLine D"
printf "\e[14;1H"
printf "\e[2M"  # Delete 2 lines
sleep 0.5
pass "Delete lines"

# --------------------------------------------
# Test 8: Tab Handling
# --------------------------------------------
section "Tab Handling Tests"

echo "Test 8.1: Horizontal tab"
printf "A\tB\tC\tD\n"
sleep 0.3
pass "Horizontal tab"

echo "Test 8.2: Tab with CJK"
printf "日本語\tABC\t日本語\n"
sleep 0.3
pass "Tab with CJK"

# --------------------------------------------
# Test 9: Alternate Screen Buffer
# --------------------------------------------
section "Alternate Screen Buffer Tests"

echo "Test 9.1: Switch to alternate screen"
printf "\e[?1049h"  # Enter alternate screen
sleep 0.3
printf "Alternate screen content\n"
sleep 0.5
printf "\e[?1049l"  # Exit alternate screen
echo "Back to primary screen"
sleep 0.3
pass "Alternate screen buffer"

# --------------------------------------------
# Test 10: Rapid Output Stress Test
# --------------------------------------------
section "Rapid Output Stress Tests"

echo "Test 10.1: Rapid line output (100 lines)"
for i in {1..100}; do
    printf "Rapid line %03d\n" "$i"
done
sleep 1
pass "Rapid 100 lines"

echo "Test 10.2: Rapid cursor movement"
for i in {1..50}; do
    printf "\e[%d;%dHX" "$((RANDOM % 20 + 1))" "$((RANDOM % 70 + 1))"
done
sleep 0.5
pass "Rapid cursor movement"

echo "Test 10.3: Rapid color changes"
for i in {0..255}; do
    printf "\e[38;5;%dm█" "$i"
done
printf "\e[0m\n"
sleep 0.5
pass "Rapid color changes"

# --------------------------------------------
# Test 11: Edge Cases
# --------------------------------------------
section "Edge Case Tests"

echo "Test 11.1: Cursor at (0,0) with backspace"
printf "\e[1;1H"
printf "A"
printf "\e[D"  # Cursor left - should stay at col 0
printf "B"
sleep 0.3
pass "Backspace at col 0"

echo "Test 11.2: Cursor at (1, cols) with forward"
printf "\e[1;80H"  # Assuming 80 cols
printf "\e[C"  # Cursor right - should stay at last col
sleep 0.3
pass "Forward at last column"

echo "Test 11.3: Empty lines"
printf "\n\n\n\n\n"
sleep 0.3
pass "Empty lines"

# --------------------------------------------
# Summary
# --------------------------------------------
section "Test Summary"
echo ""
echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"
echo ""

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
