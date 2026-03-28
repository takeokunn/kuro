//! Integration tests for `TerminalCore` — exercise full `advance()` pipelines.
//! These tests run without any Emacs runtime.

use kuro_core::TerminalCore;

// === Basic terminal operations ===

#[test]
fn test_integration_print_and_cursor_advance() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"Hello");
    assert_eq!(term.cursor_col(), 5);
    assert_eq!(term.cursor_row(), 0);
}

#[test]
fn test_integration_newline_moves_cursor_down() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"line1\nline2");
    assert_eq!(term.cursor_row(), 1);
}

#[test]
fn test_integration_carriage_return_moves_to_col_zero() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"hello\r");
    assert_eq!(term.cursor_col(), 0);
}

#[test]
fn test_integration_sgr_bold_sets_current_attrs() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[1m");
    assert!(term.current_bold(), "Bold should be set after \\x1b[1m");
}

#[test]
fn test_integration_sgr_reset_clears_attrs() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[1m");
    assert!(term.current_bold());
    term.advance(b"\x1b[0m");
    assert!(
        !term.current_bold(),
        "Bold should be cleared after \\x1b[0m"
    );
}

#[test]
fn test_integration_sgr_italic() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[3m");
    assert!(term.current_italic());
}

#[test]
fn test_integration_sgr_underline() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[4m");
    assert!(term.current_underline());
}

#[test]
fn test_integration_cursor_movement_up() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[10;1H"); // move to row 10, col 1 (1-indexed → 0-indexed: row=9, col=0)
    term.advance(b"\x1b[3A"); // cursor up 3
    assert_eq!(term.cursor_row(), 6); // 9 - 3 = 6
}

#[test]
fn test_integration_cursor_movement_home() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[10;40H");
    term.advance(b"\x1b[H");
    assert_eq!(term.cursor_row(), 0);
    assert_eq!(term.cursor_col(), 0);
}

#[test]
fn test_integration_resize_cursor_stays_in_bounds() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[20;70H"); // move near bottom-right
    term.resize(10, 40); // shrink terminal
    assert!(
        term.cursor_row() < 10,
        "cursor row must be < 10 after resize"
    );
    assert!(
        term.cursor_col() < 40,
        "cursor col must be < 40 after resize"
    );
}

#[test]
fn test_integration_resize_dimensions_update() {
    let mut term = TerminalCore::new(24, 80);
    term.resize(10, 40);
    assert_eq!(term.rows(), 10);
    assert_eq!(term.cols(), 40);
}

#[test]
fn test_integration_erase_display() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"Hello");
    term.advance(b"\x1b[2J"); // erase entire display
                              // cursor position may vary, but must remain in bounds
    assert!(term.cursor_row() < 24);
    assert!(term.cursor_col() < 80);
}

#[test]
fn test_integration_erase_display_clears_cells() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"Hello");
    // Verify content was printed
    let cell_before = term.get_cell(0, 0);
    assert!(cell_before.is_some());
    // Erase entire display
    term.advance(b"\x1b[2J");
    // Verify cells are now blank (space or empty)
    let cell_after = term.get_cell(0, 0);
    if let Some(c) = cell_after {
        assert_eq!(c.char(), ' ', "Cell should be space after erase display");
    }
    assert!(term.cursor_row() < 24);
    assert!(term.cursor_col() < 80);
}

#[test]
fn test_integration_erase_line() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"Hello");
    term.advance(b"\x1b[2K"); // erase entire line
    assert!(term.cursor_row() < 24);
}

#[test]
fn test_integration_erase_line_clears_cells() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"Hello");
    term.advance(b"\x1b[2K"); // erase entire line
    let cell = term.get_cell(0, 0);
    if let Some(c) = cell {
        assert_eq!(c.char(), ' ', "Cell should be space after erase line");
    }
}

#[test]
fn test_integration_scroll_region_set() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[5;20r"); // set scroll region rows 5-20
                                 // must not panic
    assert!(term.cursor_row() < 24);
}

#[test]
fn test_integration_multiple_advances_are_composable() {
    let mut term = TerminalCore::new(24, 80);
    // Split an SGR sequence across two advance() calls
    term.advance(b"\x1b[");
    term.advance(b"1m");
    assert!(term.current_bold(), "Bold set by split SGR sequence");
}

#[test]
fn test_integration_arbitrary_bytes_no_panic() {
    let mut term = TerminalCore::new(24, 80);
    // Control characters that should be silently ignored or handled
    term.advance(b"\x00\x01\x02\x03\x04\x05\x06\x07");
    term.advance(b"\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1c\x1d\x1e\x1f");
    // Must not panic
    assert!(term.cursor_row() < 24);
}

#[test]
fn test_integration_print_content_stored_in_cell() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"Hello");
    let cell = term.get_cell(0, 0).expect("cell at (0,0) should exist");
    assert_eq!(cell.char(), 'H');
}

#[test]
fn test_integration_default_dimensions() {
    let term = TerminalCore::new(24, 80);
    assert_eq!(term.rows(), 24);
    assert_eq!(term.cols(), 80);
    assert_eq!(term.cursor_row(), 0);
    assert_eq!(term.cursor_col(), 0);
}

#[test]
fn test_integration_crlf_sequence() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"line1\r\nline2");
    assert_eq!(term.cursor_row(), 1);
    assert_eq!(term.cursor_col(), 5);
}

#[test]
fn test_integration_multiple_lines() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"a\nb\nc\nd");
    assert_eq!(term.cursor_row(), 3);
}

#[test]
fn test_integration_advance_empty_no_panic() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(&[]);
    assert_eq!(term.cursor_row(), 0);
    assert_eq!(term.cursor_col(), 0);
}

#[test]
fn test_integration_line_wrap_at_right_margin() {
    // Printing past the last column should wrap to next line
    let mut term = TerminalCore::new(24, 80);
    // Print 81 characters — should wrap after 80
    let long_line: Vec<u8> = b"A".repeat(81);
    term.advance(&long_line);
    // After 81 'A's: cursor should be on row 1, col 1
    assert_eq!(term.cursor_row(), 1, "Should have wrapped to row 1");
    assert_eq!(term.cursor_col(), 1, "Cursor should be at col 1 after wrap");
    // Verify the wrapped character landed on row 1
    let wrapped_cell = term.get_cell(1, 0);
    assert!(
        wrapped_cell.is_some(),
        "Row 1 col 0 should have content after wrap"
    );
}

#[test]
fn test_integration_wide_char_occupies_two_cells() {
    // CJK character '中' (U+4E2D) is width-2 and should occupy two cells
    let mut term = TerminalCore::new(24, 80);
    term.advance("中".as_bytes());
    // After printing a wide char, cursor should advance by 2
    assert_eq!(term.cursor_col(), 2, "Wide char should advance cursor by 2");
}

// === Scrollback buffer tests ===

#[test]
fn test_scrollback_count_after_overflow() {
    // A 3-row terminal; printing 4 lines forces the first into scrollback
    let mut term = TerminalCore::new(3, 20);
    term.advance(b"line1\nline2\nline3\nline4");
    assert!(
        term.scrollback_line_count() >= 1,
        "At least one line should be in scrollback after overflow, got {}",
        term.scrollback_line_count()
    );
}

#[test]
fn test_scrollback_content_first_line() {
    // Verify that the first scrolled-off line contains the correct characters
    let mut term = TerminalCore::new(3, 20);
    // Write exactly 3 full lines then one more to force a scroll
    term.advance(b"AAAA\nBBBB\nCCCC\nDDDD");
    let lines = term.scrollback_chars(10);
    assert!(
        !lines.is_empty(),
        "scrollback_chars should return at least one line"
    );
    // The most-recent scrolled line (index 0 = most recent) should contain 'A's
    let first_scrolled: String = lines[0].iter().collect();
    assert!(
        first_scrolled.starts_with("AAAA"),
        "Most recent scrollback line should start with 'AAAA', got: {:?}",
        &first_scrolled[..first_scrolled.len().min(10)]
    );
}

#[test]
fn test_scrollback_max_lines_respected() {
    // Requesting fewer lines than available returns only the requested count
    let mut term = TerminalCore::new(2, 10);
    // 5 newlines on a 2-row terminal forces 3 lines to scrollback
    term.advance(b"1\n2\n3\n4\n5\n6");
    let full = term.scrollback_chars(100);
    let partial = term.scrollback_chars(1);
    assert_eq!(
        partial.len(),
        1,
        "scrollback_chars(1) should return exactly 1 line"
    );
    assert!(
        full.len() > partial.len(),
        "Full fetch should return more lines than partial"
    );
}

// -----------------------------------------------------------------------------
// REGRESSION TESTS — SPC cursor movement
//
// Bug: encode_line() trimmed trailing spaces before passing the line text to
// Emacs.  kuro--update-cursor computes the buffer position as:
//
//   (min (+ line-start col) line-end)
//
// After trimming, `line-end` was shorter than the cursor column when the
// cursor was inside trailing whitespace, so the visual cursor was clamped
// to the last non-space character.  Symptom: pressing SPC at a bash prompt
// did not move the cursor.
//
// The fix: remove trailing-space trimming from encode_line and get_dirty_lines.
// The tests below pin the correct behaviour at the TerminalCore level so that
// any future regression is caught before it reaches the Emacs render layer.
// -----------------------------------------------------------------------------

/// A single SPC byte must advance the cursor one column to the right.
///
/// This is the minimal reproduction of the original bug:
///   1. kuro sends 0x20 to the PTY.
///   2. The shell echoes 0x20 back.
///   3. VTE calls screen.print(' ') → `cursor_col` += 1.
///
/// If `encode_line` trimmed the space away, the Emacs buffer line became empty,
/// causing kuro--update-cursor to clamp the cursor back to col 0.
#[test]
fn test_spc_advances_cursor_rightward() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b" ");
    assert_eq!(
        term.cursor_col(),
        1,
        "cursor col must be 1 after a single SPC — \
         regression: trailing-space trimming must not discard the echoed space"
    );
    // The cell at column 0 must contain a space, not a default/empty cell.
    let cell = term.get_cell(0, 0).expect("cell (0,0) must exist");
    assert_eq!(
        cell.char(),
        ' ',
        "cell (0,0) must be ' ' after advancing through a space"
    );
}

/// After text followed by a trailing space, cursor lands after the space.
///
/// Simulates the typical bash readline echo of "echo hello ":
///   - 10 chars of "echo hello"
///   - 1 trailing space typed by the user
///
/// The cursor must land at col 11, not col 10 (the trimmed position).
#[test]
fn test_cursor_lands_after_trailing_space() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"echo hello ");
    assert_eq!(
        term.cursor_col(),
        11,
        "cursor col must be 11 after 'echo hello ' \
         (10 non-space chars + 1 trailing space)"
    );
}

/// Multiple consecutive spaces must each advance the cursor.
#[test]
fn test_multiple_trailing_spaces_advance_cursor() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"AB   "); // 2 non-space + 3 trailing spaces
    assert_eq!(
        term.cursor_col(),
        5,
        "cursor col must be 5 after 'AB   ' (2 chars + 3 trailing spaces)"
    );
}

/// Backspace after a space must move the cursor back.
///
/// Guards the cursor movement round-trip:
///   SPC → cursor right, BS → cursor left.
/// If SPC didn't advance the cursor, BS from the wrong position would
/// compound the error.
#[test]
fn test_backspace_after_space_moves_cursor_left() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"A "); // 'A' at col 0, space at col 1 → cursor at 2
    assert_eq!(term.cursor_col(), 2, "cursor must be at col 2 after 'A '");
    term.advance(b"\x08"); // BS → cursor back to col 1
    assert_eq!(
        term.cursor_col(),
        1,
        "cursor must be at col 1 after backspace"
    );
}

/// C-b (0x02), C-f (0x06), C-e (0x05) must NOT write printable characters.
///
/// These bytes are C0 control characters handled by VTE's `execute` callback,
/// not `print`.  If they leaked into the cell grid as printable glyphs, it
/// would mean the PTY is echoing them as the two-char sequences "^B"/"^F"/"^E"
/// (ECHOCTL mode), which indicates readline is in dumb-terminal mode due to
/// the PTY window size being 0×0 at shell startup.
///
/// At the `TerminalCore` level these bytes are not printable, so cells stay
/// empty and the cursor stays at col 0.
#[test]
fn test_control_chars_do_not_print_visible_glyphs() {
    let mut term = TerminalCore::new(24, 80);
    // Feed raw C-b, C-f, C-e (as the terminal core would see them from the PTY
    // when readline is operating correctly and does NOT echo them as ^X).
    term.advance(&[0x02, 0x06, 0x05]);
    assert_eq!(
        term.cursor_col(),
        0,
        "C-b/C-f/C-e must not advance the cursor — they are control chars, not printable"
    );
    // All cells on row 0 must be default (space) — no "^B", "^F", "^E" glyphs.
    for col in 0..5 {
        let cell = term.get_cell(0, col).expect("cell must exist");
        assert_eq!(
            cell.char(),
            ' ',
            "cell (0,{col}) must be a space — control chars must not write glyphs"
        );
    }
}

// === soft_reset vs reset ===

/// `soft_reset` clears SGR attributes but preserves screen content.
///
/// DECSTR (CSI ! p) is used by applications after a session recovery:
/// they want to clear mode state without erasing what's on screen.
#[test]
fn test_soft_reset_clears_sgr_preserves_content() {
    let mut term = TerminalCore::new(24, 80);
    // Write text and set bold+italic
    term.advance(b"\x1b[1;3mHello");
    assert!(term.current_bold(), "bold must be set before soft_reset");
    assert!(
        term.current_italic(),
        "italic must be set before soft_reset"
    );

    term.soft_reset();

    // SGR attributes must be cleared
    assert!(!term.current_bold(), "bold must be clear after soft_reset");
    assert!(
        !term.current_italic(),
        "italic must be clear after soft_reset"
    );

    // Screen content must be preserved — 'H' at (0,0)
    let cell = term.get_cell(0, 0).expect("cell (0,0) must exist");
    assert_eq!(cell.char(), 'H', "soft_reset must not erase screen content");
}

/// `soft_reset` moves cursor to home and keeps cursor visible.
#[test]
fn test_soft_reset_homes_cursor_and_keeps_visible() {
    let mut term = TerminalCore::new(24, 80);
    // Hide cursor and move away from home
    term.advance(b"\x1b[?25l"); // DECTCEM off
    term.advance(b"\x1b[10;20H"); // move cursor
    assert!(
        !term.cursor_visible(),
        "cursor should be hidden before soft_reset"
    );

    term.soft_reset();

    assert_eq!(term.cursor_row(), 0, "soft_reset must home the cursor row");
    assert_eq!(term.cursor_col(), 0, "soft_reset must home the cursor col");
    assert!(
        term.cursor_visible(),
        "soft_reset must restore cursor visibility"
    );
}

/// `reset` (RIS - ESC c) clears the title, resets to primary screen, and
/// resets tab stops to the default 8-column grid.
#[test]
fn test_reset_clears_title_and_resets_state() {
    let mut term = TerminalCore::new(24, 80);
    // Set a title via OSC 2
    term.advance(b"\x1b]2;my-title\x07");
    assert_eq!(term.title(), "my-title", "title must be set before reset");

    // Switch to alternate screen and write something
    term.advance(b"\x1b[?1049h"); // enter alt screen
    term.advance(b"altcontent");
    assert!(
        term.is_alternate_screen_active(),
        "must be on alt screen before reset"
    );

    term.reset();

    // Must be back on primary screen
    assert!(
        !term.is_alternate_screen_active(),
        "reset must switch back to primary screen"
    );
    // Title must be cleared
    assert_eq!(term.title(), "", "reset must clear the title");
    // Cursor must be at home
    assert_eq!(term.cursor_row(), 0);
    assert_eq!(term.cursor_col(), 0);
}

// === Title dirty flag lifecycle ===

/// Title dirty flag is set on OSC 2 and remains set until it is consumed via reset.
#[test]
fn test_title_dirty_set_then_cleared_by_reset() {
    let mut term = TerminalCore::new(24, 80);
    assert!(!term.title_dirty(), "title_dirty must start false");

    term.advance(b"\x1b]2;test-title\x07");
    assert!(term.title_dirty(), "title_dirty must be true after OSC 2");
    assert_eq!(term.title(), "test-title");

    // A full reset clears title_dirty
    term.reset();
    assert!(!term.title_dirty(), "title_dirty must be false after reset");
    assert_eq!(term.title(), "");
}

/// A second OSC 2 after the first re-sets title_dirty to true.
#[test]
fn test_title_dirty_resets_on_second_osc2() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b]2;first\x07");
    assert!(term.title_dirty());

    // Simulate consuming the dirty flag (as the render cycle would)
    // by using reset (cheapest way to clear title_dirty in integration tests)
    term.reset();
    assert!(!term.title_dirty());

    // A new OSC 2 must re-set the flag
    term.advance(b"\x1b]2;second\x07");
    assert!(
        term.title_dirty(),
        "title_dirty must be true after second OSC 2"
    );
    assert_eq!(term.title(), "second");
}

// === Tab stop initialization after resize ===

/// After a resize that grows the terminal, new default tab stops appear at
/// every 8th column in the expanded region.
#[test]
fn test_tab_stops_available_after_resize_grow() {
    let mut term = TerminalCore::new(24, 16); // only cols 8 is a tab stop
                                              // Tab from col 0 should land on col 8
    term.advance(b"\t");
    assert_eq!(
        term.cursor_col(),
        8,
        "tab should land on col 8 in 16-col terminal"
    );

    // Resize to 32 cols — col 24 is now a new default tab stop
    term.resize(24, 32);
    // Move cursor to col 8 (a known stop) then tab; should jump to col 16
    term.advance(b"\x1b[1;9H"); // move to row 0, col 9 (0-indexed: row=0, col=8)
    term.advance(b"\t");
    assert_eq!(
        term.cursor_col(),
        16,
        "tab from col 8 should land on col 16 after resize to 32 cols"
    );
}

include!("include/integration_terminal_cursor_save.rs");
