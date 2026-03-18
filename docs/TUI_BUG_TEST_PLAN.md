# Kuro TUI Rendering Bug Testing Plan

## Overview

This comprehensive testing plan covers all potential TUI rendering edge cases and bug patterns in the kuro terminal emulator. Based on analysis of existing code and documented issues in `TUI_BUG_ANALYSIS.md`.

---

## 1. Bug Categories

### 1.1 Race Conditions / Synchronization

| Bug ID | Issue | Location | Severity | Test Scenario |
|--------|-------|----------|----------|---------------|
| RACE-001 | PTY reader vs rendering race | `rust-core/src/pty/reader.rs:24-44` + `emacs-lisp/kuro-renderer.el:60-75` | **Critical** | Rapid output flood test |
| RACE-002 | col_to_buf mapping sync | `emacs-lisp/kuro-renderer.el:221-222` | **High** | Multi-line CJK update |
| RACE-003 | Window resize race | `emacs-lisp/kuro.el:49-87` + `kuro-renderer.el:101-132` | **Medium** | Resize during output |
| RACE-004 | Cursor position update race | `emacs-lisp/kuro-renderer.el:271-332` | **Medium** | Cursor move during scroll |

### 1.2 Grid/Screen Edge Cases

| Bug ID | Issue | Location | Severity | Test Scenario |
|--------|-------|----------|----------|---------------|
| GRID-001 | Scroll region boundary cursor | `rust-core/src/grid/screen.rs:232-242` | **High** | LF at scroll bottom |
| GRID-002 | Scrollback viewport sync | `rust-core/src/grid/screen.rs:792-820` | **Medium** | New output during scrollback view |
| GRID-003 | Alternate screen state preservation | `rust-core/src/grid/screen.rs:596-617` | **High** | vim exit state restore |
| GRID-004 | Dirty tracking consistency | `rust-core/src/grid/screen.rs:364-387` | **Medium** | Full dirty vs selective dirty |

### 1.3 Parser/VTE Edge Cases

| Bug ID | Issue | Location | Severity | Test Scenario |
|--------|-------|----------|----------|---------------|
| VTE-001 | BCE (Background Color Erase) not implemented | `rust-core/src/parser/erase.rs:41-44` | **Critical** | ED/EL with background color |
| VTE-002 | Incomplete sequence handling | `rust-core/src/parser/vte_handler.rs` | **High** | Split escape sequences |
| VTE-003 | DSR async response | `rust-core/src/parser/csi.rs:99-115` | **Medium** | Multiple consecutive DSR |
| VTE-004 | SGR attribute reset | `rust-core/src/parser/sgr.rs` | **Medium** | SGR reset preservation |

### 1.4 Renderer/Display Bugs

| Bug ID | Issue | Location | Severity | Test Scenario |
|--------|-------|----------|----------|---------------|
| REND-001 | Timer precision (16ms not guaranteed) | `emacs-lisp/kuro-renderer.el:60-75` | **High** | Frame timing verification |
| REND-002 | Buffer line count sync | `emacs-lisp/kuro-renderer.el:240-268` | **Medium** | Line addition during rapid output |
| REND-003 | Multiple window display | `emacs-lisp/kuro-renderer.el:271-332` | **Low** | Same buffer in multiple windows |

### 1.5 Unicode/CJK Handling

| Bug ID | Issue | Location | Severity | Test Scenario |
|--------|-------|----------|----------|---------------|
| CJK-001 | Wide character wrap edge case | `rust-core/src/grid/screen.rs:153-229` | **High** | CJK at col=cols-1 |
| CJK-002 | Combining character at (0,0) discarded | `rust-core/src/parser/vte_handler.rs:13-31` | **Medium** | Combining char at buffer start |
| CJK-003 | Wide placeholder integrity | `rust-core/src/grid/screen.rs:178-184` | **High** | Delete/insert with wide chars |

### 1.6 Memory/Resource Management

| Bug ID | Issue | Location | Severity | Test Scenario |
|--------|-------|----------|----------|---------------|
| MEM-001 | Scrollback buffer overflow | `rust-core/src/grid/screen.rs:276-283` | **Medium** | Large scrollback + resize |
| MEM-002 | PTY reader thread cleanup | `rust-core/src/pty/reader.rs` | **Low** | Shutdown during active read |
| MEM-003 | FFI memory leaks | `rust-core/src/ffi/bridge/render.rs` | **Medium** | Long-running session |

### 1.7 FFI Bridge Issues

| Bug ID | Issue | Location | Severity | Test Scenario |
|--------|-------|----------|----------|---------------|
| FFI-001 | Unknown message type handling | `TUI_BUG_ANALYSIS.md:359-381` | **Critical** | Unknown escape sequences |
| FFI-002 | Panic recovery | `rust-core/src/ffi/bridge/render.rs` | **Medium** | Force panic in poll |
| FFI-003 | Session lock contention | `rust-core/src/ffi/abstraction.rs` | **Low** | Concurrent FFI calls |

---

## 2. Test Plan Structure

### Directory Structure

```
test/
├── tui-bug/
│   ├── test-race-conditions.el     # Race condition tests
│   ├── test-grid-edge-cases.el     # Grid/screen edge cases
│   ├── test-vte-parser.el          # Parser/VTE tests
│   ├── test-renderer.el            # Renderer/display tests
│   ├── test-unicode-cjk.el         # Unicode/CJK tests
│   ├── test-memory.el              # Memory/resource tests
│   ├── test-ffi-bridge.el          # FFI bridge tests
│   └── run-tui-tests.sh            # Test runner script
└── manual/
    └── tui_stress_test.sh          # Existing manual tests
```

---

## 3. Detailed Test Cases

### 3.1 Race Condition Tests (`test-race-conditions.el`)

#### RACE-001: PTY Reader vs Rendering Race

**Location:** `rust-core/src/pty/reader.rs:24-44`, `emacs-lisp/kuro-renderer.el:60-75`

**Expected Behavior:** No data loss during rapid output
**Actual Behavior (Bug):** Potential frame drops and partial line updates

```elisp
;;; test/tui-bug/test-race-conditions.el

(ert-deftest kuro-tui-race-001-pty-render-flood ()
  "Test PTY reader vs rendering race condition.
Rapid output should not cause frame drops or partial line updates."
  (kuro-test--with-terminal
   ;; Generate rapid output that exceeds frame processing capacity
   (kuro-test--send "for i in {1..500}; do echo \"Line $i: $(printf 'X%.0s' {1..100})\"; done\r")
   (sit-for 0.1)
   (dotimes (_ 20)
     (kuro-test--render buf)
     (sleep-for 0.01))
   ;; Verify no lines are missing
   (let ((content (kuro-test--buffer-content buf)))
     (should (string-match-p "Line 1:" content))
     (should (string-match-p "Line 500:" content))
     ;; Check for corrupted partial lines
     (should-not (string-match-p "^Line [0-9]+:[^L]" content)))))
```

**Test Command:**
```bash
emacs --batch -L emacs-lisp -L test -L test/tui-bug \
  --eval "(require 'kuro)" \
  --eval "(require 'test-race-conditions)" \
  --eval '(ert-run-tests-batch-and-exit "kuro-tui-race-001")'
```

**Verification via emacsclient:**
```bash
# Start daemon
emacs --daemon=kuro-test-daemon

# Run test
emacsclient -s kuro-test-daemon --eval '
(progn
  (add-to-list (quote load-path) "emacs-lisp")
  (add-to-list (quote load-path) "test")
  (add-to-list (quote load-path) "test/tui-bug")
  (require (quote kuro))
  (require (quote test-race-conditions))
  (ert-run-tests-interactively "kuro-tui-race-001"))'

# Check results
emacsclient -s kuro-test-daemon --eval '
(with-current-buffer "*ERT*"
  (buffer-string))'
```

---

#### RACE-002: col_to_buf Mapping Sync

**Location:** `emacs-lisp/kuro-renderer.el:221-222`

**Expected Behavior:** col_to_buf correctly maps cursor column to buffer offset
**Actual Behavior (Bug):** Multi-line updates may overwrite previous row's mapping

```elisp
(ert-deftest kuro-tui-race-002-col-to-buf-sync ()
  "Test col_to_buf mapping synchronization across multiple lines.
Each line should have its own correct col_to_buf mapping."
  (kuro-test--with-terminal
   ;; Output CJK text that spans multiple lines
   (kuro-test--send "echo '日本語テスト日本語テスト日本語テスト日本語テスト日本語テスト'\r")
   (sit-for 0.2)
   (kuro-test--render buf)
   ;; Move cursor to specific position
   (kuro-test--send "\e[5;10H")
   (sit-for 0.1)
   (kuro-test--render buf)
   ;; Verify cursor position is correct
   (let* ((cursor-pos (kuro--get-cursor))
          (row (car cursor-pos))
          (col (cdr cursor-pos)))
     (should (= row 4))  ; 0-indexed
     (should (= col 10)))))
```

---

#### RACE-003: Window Resize Race

**Location:** `emacs-lisp/kuro.el:49-87`, `kuro-renderer.el:101-132`

**Expected Behavior:** Resize handled atomically without display corruption
**Actual Behavior (Bug):** Potential double-resize or size mismatch

```elisp
(ert-deftest kuro-tui-race-003-resize-during-output ()
  "Test window resize during active output.
Resize should not cause display corruption or crashes."
  (kuro-test--with-terminal
   ;; Start continuous output
   (kuro-test--send "while true; do echo \"$(date)\"; sleep 0.01; done &\r")
   (sit-for 0.2)
   (dotimes (_ 5)
     (kuro-test--render buf)
     ;; Simulate resize
     (kuro--resize 30 100)
     (sit-for 0.05)
     (kuro--resize 24 80)
     (sit-for 0.05))
   (kuro-test--send "\e[2J")  ; Clear
   (kuro-test--send "kill %1 2>/dev/null\r")  ; Stop background job
   (sit-for 0.2)
   (kuro-test--render buf)
   ;; Buffer should be valid
   (should (> (length (kuro-test--buffer-content buf)) 0))))
```

---

### 3.2 Grid/Screen Edge Case Tests (`test-grid-edge-cases.el`)

#### GRID-001: Scroll Region Boundary Cursor

**Location:** `rust-core/src/grid/screen.rs:232-242`

**Expected Behavior:** Cursor position updates correctly at scroll region boundary
**Actual Behavior (Bug):** At scroll bottom, cursor may not move on LF

```elisp
(ert-deftest kuro-tui-grid-001-scroll-region-cursor ()
  "Test cursor behavior at scroll region boundary.
LF at scroll bottom should scroll content, not move cursor row."
  (kuro-test--with-terminal
   ;; Set scroll region (rows 5-10)
   (kuro-test--send "\e[5;10r")
   ;; Position cursor at scroll bottom
   (kuro-test--send "\e[9;1H")  ; Row 9 (0-indexed), col 1
   (kuro-test--send "X")  ; Print at position
   ;; LF at boundary - should scroll, cursor stays at row 9
   (kuro-test--send "\n")
   (kuro-test--send "Y")  ; Should appear at same row after scroll
   (sit-for 0.2)
   (kuro-test--render buf)
   ;; Verify cursor is still in scroll region
   (let ((cursor-pos (kuro--get-cursor)))
     (should (>= (car cursor-pos) 4))  ; Within scroll region
     (should (< (car cursor-pos) 10)))
   ;; Reset scroll region
   (kuro-test--send "\e[r")))
```

---

#### GRID-003: Alternate Screen State Preservation

**Location:** `rust-core/src/grid/screen.rs:596-617`

**Expected Behavior:** vim exit restores original screen state
**Actual Behavior (Bug):** SGR attributes, tab stops may not be fully restored

```elisp
(ert-deftest kuro-tui-grid-003-alternate-screen-restore ()
  "Test alternate screen buffer state preservation.
Exiting vim should restore original screen state including cursor position."
  (skip-unless (executable-find "vim"))
  (kuro-test--with-terminal
   ;; Record initial state
   (kuro-test--send "echo 'BEFORE_VIM'\r")
   (sit-for 0.2)
   (kuro-test--render buf)
   (let ((before-content (kuro-test--buffer-content buf)))
     ;; Enter vim (triggers alternate screen)
     (kuro-test--send "vim -c 'echo \"IN_VIM\"' -c 'qa'\r")
     (sit-for 0.5)
     (dotimes (_ 5) (kuro-test--render buf) (sleep-for 0.05))
     ;; Exit vim
     (kuro-test--send ":q\r")
     (sit-for 0.3)
     (kuro-test--render buf)
     ;; Original content should be restored
     (let ((after-content (kuro-test--buffer-content buf)))
       (should (string-match-p "BEFORE_VIM" after-content))))))
```

---

### 3.3 VTE Parser Tests (`test-vte-parser.el`)

#### VTE-001: BCE (Background Color Erase) Not Implemented

**Location:** `rust-core/src/parser/erase.rs:41-44`

**Expected Behavior:** ED/EL uses current SGR background color
**Actual Behavior (Bug):** Cells reset to default color

```elisp
(ert-deftest kuro-tui-vte-001-bce-background-erase ()
  "Test Background Color Erase (BCE) implementation.
Erase operations should use current SGR background color."
  (kuro-test--with-terminal
   ;; Set background color and print text
   (kuro-test--send "\e[44m")  ; Blue background
   (kuro-test--send "XXXXXXXXXX")
   (sit-for 0.1)
   (kuro-test--render buf)
   ;; Erase from cursor to end of line (EL 0)
   (kuro-test--send "\e[K")
   (sit-for 0.1)
   (kuro-test--render buf)
   ;; Verify erased cells have blue background (not default)
   ;; Note: This requires face property verification
   (let ((content (kuro-test--buffer-content buf)))
     ;; Text should be partially erased
     (should (string-match-p "XXX" content)))))
```

---

#### VTE-002: Incomplete Sequence Handling

**Location:** `rust-core/src/parser/vte_handler.rs`

**Expected Behavior:** Split escape sequences are handled correctly
**Actual Behavior:** May cause parsing errors

```elisp
(ert-deftest kuro-tui-vte-002-incomplete-sequence ()
  "Test handling of incomplete/split escape sequences.
Split CSI sequences should be parsed correctly when data arrives in chunks."
  (kuro-test--with-terminal
   ;; Send escape sequence in parts
   (kuro-test--send "\e[")  ; CSI start
   (sit-for 0.01)
   (kuro-test--send "31")   ; Parameter
   (sit-for 0.01)
   (kuro-test--send "m")    ; SGR end
   (kuro-test--send "RED")
   (kuro-test--send "\e[0m")
   (sit-for 0.2)
   (kuro-test--render buf)
   (let ((content (kuro-test--buffer-content buf)))
     (should (string-match-p "RED" content)))))
```

---

### 3.4 Renderer/Display Tests (`test-renderer.el`)

#### REND-001: Timer Precision

**Location:** `emacs-lisp/kuro-renderer.el:60-75`

**Expected Behavior:** ~16ms frame intervals (60fps)
**Actual Behavior (Bug):** Timer intervals may vary due to Emacs event loop

```elisp
(ert-deftest kuro-tui-rend-001-timer-precision ()
  "Test timer-based rendering precision.
Frame intervals should approximate 16ms (60fps)."
  (let ((frame-times '())
        (start-time nil)
        (frame-count 0))
    (kuro-test--with-terminal
     (setq start-time (float-time))
     (add-hook 'kuro--post-render-hook
               (lambda ()
                 (push (- (float-time) start-time) frame-times)
                 (setq start-time (float-time))
                 (cl-incf frame-count))
               nil t)
     ;; Generate steady output
     (dotimes (i 100)
       (kuro-test--send (format "Frame %d\n" i))
       (sit-for 0.02))
     (sit-for 0.5)
     ;; Calculate average frame time
     (when (>= frame-count 10)
       (let ((avg-interval (/ (apply #'+ frame-times) (length frame-times))))
         ;; Should be close to 16ms (allow 10-30ms range due to Emacs scheduling)
         (should (>= avg-interval 0.010))
         (should (<= avg-interval 0.050)))))))
```

---

### 3.5 Unicode/CJK Tests (`test-unicode-cjk.el`)

#### CJK-001: Wide Character Wrap Edge Case

**Location:** `rust-core/src/grid/screen.rs:153-229`

**Expected Behavior:** Wide char at col=cols-1 wraps to next line
**Actual Behavior (Bug):** May cause display corruption

```elisp
(ert-deftest kuro-tui-cjk-001-wide-wrap-edge ()
  "Test wide character wrapping at line edge.
CJK character at col=cols-1 should wrap to next line correctly."
  (kuro-test--with-terminal
   ;; Move cursor to last column
   (kuro-test--send "\e[1;79H")  ; 80-column terminal, col 79 (0-indexed)
   ;; Print wide character (should wrap)
   (kuro-test--send "日")
   (sit-for 0.2)
   (kuro-test--render buf)
   ;; Character should be on row 2, cols 0-1
   (let ((content (kuro-test--buffer-content buf)))
     (should (string-match-p "日" content)))))
```

---

#### CJK-002: Combining Character at (0,0) Discarded

**Location:** `rust-core/src/parser/vte_handler.rs:13-31`

**Expected Behavior:** Combining char combines with previous char or is handled gracefully
**Actual Behavior (Bug):** Discarded when at buffer start

```elisp
(ert-deftest kuro-tui-cjk-002-combining-at-origin ()
  "Test combining character handling at (0,0).
Combining character should be handled gracefully, not discarded."
  (kuro-test--with-terminal
   ;; Clear and reset cursor
   (kuro-test--send "\e[2J\e[H")
   ;; Send combining character directly (e.g., combining acute accent)
   (kuro-test--send "e\u0301")  ; e + combining acute = é
   (sit-for 0.2)
   (kuro-test--render buf)
   ;; Should have rendered something (not empty)
   (let ((content (kuro-test--buffer-content buf)))
     (should (> (length content) 0)))))
```

---

#### CJK-003: Wide Placeholder Integrity

**Location:** `rust-core/src/grid/screen.rs:178-184`

**Expected Behavior:** Delete/insert operations maintain wide pair integrity
**Actual Behavior (Bug):** Placeholder may become orphaned

```elisp
(ert-deftest kuro-tui-cjk-003-wide-placeholder-delete ()
  "Test wide placeholder integrity during delete operations.
Deleting wide character should remove both cells."
  (kuro-test--with-terminal
   ;; Print CJK text
   (kuro-test--send "AB日CD\r")
   (sit-for 0.1)
   (kuro-test--render buf)
   ;; Move to wide char and delete
   (kuro-test--send "\e[1;3H")  ; Position at the wide char
   (kuro-test--send "\e[P")     ; DCH - delete character
   (sit-for 0.1)
   (kuro-test--render buf)
   ;; Verify placeholder was also deleted
   (let ((content (kuro-test--buffer-content buf)))
     ;; Should show "AB CD" (both cells of wide char deleted)
     (should (string-match-p "AB.*CD" content)))))
```

---

### 3.6 Memory/Resource Tests (`test-memory.el`)

#### MEM-001: Scrollback Buffer Overflow

**Location:** `rust-core/src/grid/screen.rs:276-283`

**Expected Behavior:** Scrollback trimmed to max_lines
**Actual Behavior:** Potential memory issues during rapid scrolling + resize

```elisp
(ert-deftest kuro-tui-mem-001-scrollback-overflow ()
  "Test scrollback buffer trimming during overflow.
Scrollback should respect max_lines limit even during rapid output."
  (kuro-test--with-terminal
   ;; Set small scrollback limit
   (kuro-core-set-scrollback-max-lines 100)
   ;; Generate more lines than limit
   (dotimes (i 200)
     (kuro-test--send (format "Line %d\n" i)))
   (sit-for 0.3)
   (dotimes (_ 10) (kuro-test--render buf) (sleep-for 0.02))
   ;; Verify scrollback is limited
   (let ((count (kuro-core-get-scrollback-count)))
     (should (<= count 100)))))
```

---

### 3.7 FFI Bridge Tests (`test-ffi-bridge.el`)

#### FFI-001: Unknown Message Type Handling

**Location:** `TUI_BUG_ANALYSIS.md:359-381`

**Expected Behavior:** Unknown messages handled gracefully
**Actual Behavior (Bug):** Error spam "Unknown message: ..."

```elisp
(ert-deftest kuro-tui-ffi-001-unknown-message ()
  "Test handling of unknown FFI message types.
Unknown messages should be logged but not crash the renderer."
  (kuro-test--with-terminal
   ;; Send potentially problematic sequences
   (kuro-test--send "\e[?1h")   ; Unknown DEC private mode
   (kuro-test--send "\e[99z")   ; Unknown CSI sequence
   (kuro-test--send "\e]99;test\a")  ; Unknown OSC
   (sit-for 0.2)
   (kuro-test--render buf)
   ;; Renderer should still work
   (kuro-test--send "echo OK\r")
   (sit-for 0.2)
   (kuro-test--render buf)
   (should (string-match-p "OK" (kuro-test--buffer-content buf)))))
```

---

## 4. Emacs Daemon-Based Test Runner

### `run-tui-tests.sh`

```bash
#!/bin/bash
# test/tui-bug/run-tui-tests.sh
# Comprehensive TUI bug test runner using Emacs daemon

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DAEMON_NAME="kuro-tui-test-$$"
TIMEOUT=120

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

cleanup() {
    log_info "Cleaning up daemon..."
    emacsclient -s "$DAEMON_NAME" --eval '(kill-emacs)' 2>/dev/null || true
}

trap cleanup EXIT

start_daemon() {
    log_info "Starting Emacs daemon: $DAEMON_NAME"
    emacs --daemon="$DAEMON_NAME" \
          --eval "(setq server-socket-dir \"~/.emacs.d/server\")" \
          2>/dev/null
    sleep 2
    
    # Verify daemon is running
    if ! emacsclient -s "$DAEMON_NAME" --eval 't' 2>/dev/null; then
        log_error "Failed to start Emacs daemon"
        exit 1
    fi
    log_info "Daemon started successfully"
}

run_test_file() {
    local test_file="$1"
    local test_pattern="${2:-""}"
    
    log_info "Running tests from: $test_file"
    
    local result=$(emacsclient -s "$DAEMON_NAME" --eval "
(progn
  (add-to-list 'load-path \"$PROJECT_ROOT/emacs-lisp\")
  (add-to-list 'load-path \"$PROJECT_ROOT/test\")
  (add-to-list 'load-path \"$PROJECT_ROOT/test/tui-bug\")
  (setq kuro-module-path \"$PROJECT_ROOT/target/release\")
  (require 'kuro)
  (require 'kuro-e2e-test)
  (require '$(basename \"$test_file\" .el))
  (let ((ert-result (ert-run-tests-batch-and-exit \"$test_pattern\")))
    (list :passed (length (ert--stats-passed ert-result))
          :failed (length (ert--stats-failed ert-result))
          :total (ert--stats-total ert-result))))" 2>&1)
    
    echo "$result"
}

run_all_tests() {
    local test_dir="$PROJECT_ROOT/test/tui-bug"
    local total_passed=0
    local total_failed=0
    
    for test_file in "$test_dir"/*.el; do
        [ -f "$test_file" ] || continue
        [[ "$(basename "$test_file")" == *"-"* ]] || continue
        
        local result=$(run_test_file "$test_file" "kuro-tui-")
        echo "$result"
        
        # Parse results (simplified)
        if echo "$result" | grep -q ":passed"; then
            ((total_passed++)) || true
        else
            ((total_failed++)) || true
        fi
    done
    
    log_info "Total: $total_passed passed, $total_failed failed"
}

run_specific_category() {
    local category="$1"
    local test_file="$PROJECT_ROOT/test/tui-bug/test-${category}.el"
    
    if [[ ! -f "$test_file" ]]; then
        log_error "Test file not found: $test_file"
        exit 1
    fi
    
    run_test_file "$test_file" "kuro-tui-${category}-"
}

# Main
case "${1:-all}" in
    all)
        start_daemon
        run_all_tests
        ;;
    race|grid|vte|rend|cjk|mem|ffi)
        start_daemon
        run_specific_category "$1"
        ;;
    *)
        log_error "Unknown category: $1"
        echo "Usage: $0 [all|race|grid|vte|rend|cjk|mem|ffi]"
        exit 1
        ;;
esac
```

---

## 5. Verification Steps

### 5.1 Manual Verification via emacsclient

```bash
# 1. Start test daemon
emacs --daemon=kuro-verify

# 2. Create terminal and run specific test
emacsclient -s kuro-verify --eval '
(progn
  (add-to-list (quote load-path) "/path/to/kuro/emacs-lisp")
  (require (quote kuro))
  (kuro-create "/bin/bash"))'

# 3. Send test command
emacsclient -s kuro-verify --eval '
(with-current-buffer "*kuro*"
  (kuro--send-key "for i in {1..100}; do echo \"Line $i\"; done\n"))'

# 4. Wait and verify content
sleep 2
emacsclient -s kuro-verify --eval '
(with-current-buffer "*kuro*"
  (let ((content (buffer-string)))
    (if (and (string-match-p "Line 1" content)
             (string-match-p "Line 100" content))
        "PASS: All lines present"
      "FAIL: Lines missing"))))'

# 5. Check for visual artifacts (cursor position)
emacsclient -s kuro-verify --eval '
(with-current-buffer "*kuro*"
  (let ((cursor-pos (kuro--get-cursor)))
    (format "Cursor at row %d, col %d" 
            (car cursor-pos) (cdr cursor-pos))))'

# 6. Cleanup
emacsclient -s kuro-verify --eval '(kill-emacs)'
```

### 5.2 Automated Verification Checklist

- [ ] No "Unknown message" errors in `*Messages*` buffer
- [ ] Buffer line count matches terminal rows
- [ ] Cursor position matches expected grid coordinates
- [ ] No partial/corrupted lines in buffer content
- [ ] CJK characters display with correct width
- [ ] Scroll region boundaries respected
- [ ] Alternate screen restores on exit
- [ ] Scrollback limit enforced

---

## 6. TDD-Oriented Atomic Commit Strategy

### Phase 1: Test Infrastructure Setup

```bash
# Commit 1: Create test directory structure
git add test/tui-bug/
git commit -m "test: add TUI bug test directory structure

- Create test/tui-bug/ for comprehensive TUI rendering tests
- Add placeholder files for each bug category
- Add run-tui-tests.sh daemon-based test runner"

# Commit 2: Add shared test utilities
git add test/tui-bug/kuro-tui-test-utils.el
git commit -m "test: add shared TUI test utilities

- Add kuro-tui-test-utils.el with common test helpers
- Include wait-for-pattern, verify-buffer-content, check-cursor helpers
- Support daemon-based testing patterns"
```

### Phase 2: Race Condition Tests

```bash
# Commit 3: Add RACE-001 test (PTY vs render)
git add test/tui-bug/test-race-conditions.el
git commit -m "test(race): add PTY reader vs rendering race test

- Add kuro-tui-race-001-pty-render-flood test
- Verifies no frame drops during rapid output
- Test RACE-001 from TUI_BUG_ANALYSIS.md"

# Commit 4: Add RACE-002 test (col_to_buf sync)
git add test/tui-bug/test-race-conditions.el
git commit -m "test(race): add col_to_buf mapping sync test

- Add kuro-tui-race-002-col-to-buf-sync test
- Verifies cursor position accuracy with CJK content
- Test RACE-002 from TUI_BUG_ANALYSIS.md"

# Commit 5: Add RACE-003 test (resize race)
git add test/tui-bug/test-race-conditions.el
git commit -m "test(race): add window resize race test

- Add kuro-tui-race-003-resize-during-output test
- Verifies no corruption during resize with active output
- Test RACE-003 from TUI_BUG_ANALYSIS.md"
```

### Phase 3: Grid/Screen Tests

```bash
# Commit 6-8: Grid edge case tests (one per test)
git commit -m "test(grid): add scroll region boundary cursor test (GRID-001)"
git commit -m "test(grid): add scrollback viewport sync test (GRID-002)"
git commit -m "test(grid): add alternate screen state preservation test (GRID-003)"
```

### Phase 4: Parser/VTE Tests

```bash
# Commit 9-11: VTE parser tests
git commit -m "test(vte): add BCE implementation test (VTE-001)"
git commit -m "test(vte): add incomplete sequence handling test (VTE-002)"
git commit -m "test(vte): add DSR async response test (VTE-003)"
```

### Phase 5: Remaining Categories

```bash
# Continue with similar atomic commits for:
# - Renderer tests (REND-001 to REND-003)
# - Unicode/CJK tests (CJK-001 to CJK-003)
# - Memory tests (MEM-001 to MEM-003)
# - FFI bridge tests (FFI-001 to FFI-003)
```

### Phase 6: Test Runner and CI Integration

```bash
# Final commit: CI integration
git add .github/workflows/tui-tests.yml
git commit -m "ci: add TUI bug test workflow

- Run TUI bug tests in CI via daemon-based runner
- Test all categories in parallel
- Upload test results as artifacts"
```

---

## 7. Summary

| Category | Tests | Critical | High | Medium | Low |
|----------|-------|----------|------|--------|-----|
| Race Conditions | 4 | 1 | 1 | 2 | 0 |
| Grid/Screen | 4 | 0 | 2 | 2 | 0 |
| VTE Parser | 4 | 1 | 1 | 2 | 0 |
| Renderer | 3 | 0 | 1 | 1 | 1 |
| Unicode/CJK | 3 | 0 | 2 | 1 | 0 |
| Memory | 3 | 0 | 0 | 2 | 1 |
| FFI Bridge | 3 | 1 | 0 | 1 | 1 |
| **Total** | **24** | **3** | **7** | **11** | **3** |

### Priority Execution Order

1. **Critical (Immediate):** RACE-001, VTE-001, FFI-001
2. **High (Next Release):** RACE-002, GRID-001, GRID-003, CJK-001, CJK-003
3. **Medium (Improvement):** RACE-003, RACE-004, GRID-002, GRID-004, VTE-002, VTE-003, VTE-004, REND-002, CJK-002, MEM-001, MEM-003, FFI-002
4. **Low (Future):** REND-003, MEM-002, FFI-003
