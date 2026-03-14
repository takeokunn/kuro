//! Integration tests for TerminalCore — exercise full advance() pipelines.
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
