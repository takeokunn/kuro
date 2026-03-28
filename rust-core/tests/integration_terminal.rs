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

// === flush_print_buf (ASCII batch write) ===

/// Flushing an ASCII buffer of multi-byte printable text must update all cells.
///
/// `flush_print_buf` is triggered when a non-ASCII character is printed — the
/// test exercises that path by printing ASCII followed by a Unicode code point.
#[test]
fn test_flush_print_buf_multibyte_sequence() {
    let mut term = TerminalCore::new(24, 80);
    // "AB" are buffered in print_buf; printing the wide char '中' triggers a flush
    // followed by the wide-char print itself.
    term.advance("AB中".as_bytes());

    // 'A' at col 0
    let a = term.get_cell(0, 0).expect("cell (0,0) must exist");
    assert_eq!(a.char(), 'A', "first ASCII char must be in cell 0");

    // 'B' at col 1
    let b = term.get_cell(0, 1).expect("cell (0,1) must exist");
    assert_eq!(b.char(), 'B', "second ASCII char must be in cell 1");

    // '中' (width-2) at col 2 — cursor must now be at col 4
    assert_eq!(
        term.cursor_col(),
        4,
        "cursor after AB + wide-char '中' must be at col 4"
    );
}

// === save_cursor / restore_cursor (DECSC / DECRC) ===

/// DECSC (ESC 7) and DECRC (ESC 8) must round-trip both position and SGR.
#[test]
fn test_save_restore_cursor_position_and_attrs() {
    let mut term = TerminalCore::new(24, 80);
    // Move to a specific position and set bold
    term.advance(b"\x1b[5;10H"); // row=4, col=9 (0-indexed)
    term.advance(b"\x1b[1m"); // bold on
    assert!(term.current_bold());

    // Save cursor
    term.save_cursor();

    // Move away and clear bold
    term.advance(b"\x1b[1;1H"); // home
    term.advance(b"\x1b[0m"); // reset SGR
    assert!(!term.current_bold());
    assert_eq!(term.cursor_row(), 0);
    assert_eq!(term.cursor_col(), 0);

    // Restore cursor — position and bold should come back
    term.restore_cursor();
    assert_eq!(term.cursor_row(), 4, "restored row must be 4");
    assert_eq!(term.cursor_col(), 9, "restored col must be 9");
    assert!(term.current_bold(), "bold must be restored after DECRC");
}

/// A restore without a prior save must not move the cursor or panic.
#[test]
fn test_restore_cursor_without_prior_save_is_noop() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[5;10H"); // row=4, col=9
    let row_before = term.cursor_row();
    let col_before = term.cursor_col();

    // No save — restore should be a no-op (saved_cursor is None by default)
    term.restore_cursor();

    assert_eq!(
        term.cursor_row(),
        row_before,
        "restore without save must not change row"
    );
    assert_eq!(
        term.cursor_col(),
        col_before,
        "restore without save must not change col"
    );
}

// === Additional coverage: idempotency, resize no-op, wrap, hyperlink, dirty flags ===

/// `soft_reset` called twice must not panic and must leave the terminal
/// in the same state as a single call.
#[test]
fn test_soft_reset_is_idempotent() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[1;3mHello");
    assert!(term.current_bold());

    // First call
    term.soft_reset();
    assert!(!term.current_bold(), "bold cleared after first soft_reset");
    let row1 = term.cursor_row();
    let col1 = term.cursor_col();

    // Second call — must not panic; state already at reset values
    term.soft_reset();
    assert!(
        !term.current_bold(),
        "bold still clear after second soft_reset"
    );
    assert_eq!(
        term.cursor_row(),
        row1,
        "second soft_reset must not move cursor row"
    );
    assert_eq!(
        term.cursor_col(),
        col1,
        "second soft_reset must not move cursor col"
    );
}

/// `resize` with the same dimensions must be a no-op: no panic, rows/cols unchanged.
#[test]
fn test_resize_same_dimensions_is_noop() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[5;10H"); // position cursor away from home
    let row_before = term.cursor_row();
    let col_before = term.cursor_col();

    // Resize to the same size — must not panic
    term.resize(24, 80);

    assert_eq!(term.rows(), 24, "rows must stay 24 after same-size resize");
    assert_eq!(term.cols(), 80, "cols must stay 80 after same-size resize");
    // Cursor must remain in bounds (may or may not have moved, but must be valid)
    assert!(term.cursor_row() < 24, "cursor row must be in bounds");
    assert!(term.cursor_col() < 80, "cursor col must be in bounds");
    // In practice the cursor should not have moved
    assert_eq!(
        term.cursor_row(),
        row_before,
        "cursor row must be unchanged after same-size resize"
    );
    assert_eq!(
        term.cursor_col(),
        col_before,
        "cursor col must be unchanged after same-size resize"
    );
}

/// Printing enough characters to fill a row must wrap to the next line.
///
/// This exercises the DECAWM pending-wrap path: on a 10-col terminal,
/// printing 11 'X' characters must leave the last character on row 1.
#[test]
fn test_cursor_wraps_at_column_boundary() {
    let mut term = TerminalCore::new(10, 10);
    // 10 chars fill row 0; the 11th must wrap to row 1 col 0
    term.advance(b"XXXXXXXXXX"); // fills row 0, pending wrap
    term.advance(b"Y"); // triggers wrap; 'Y' lands at (1, 0)
    assert_eq!(term.cursor_row(), 1, "cursor must be on row 1 after wrap");
    assert_eq!(
        term.cursor_col(),
        1,
        "cursor must be at col 1 after wrapping and printing 'Y'"
    );
    let cell = term.get_cell(1, 0).expect("cell (1,0) must exist");
    assert_eq!(cell.char(), 'Y', "'Y' must have wrapped to row 1, col 0");
}

/// After a resize to 40 columns the default tab stops must be at 1, 9, 17, 25, 33.
///
/// Tab stops are initialised to every 8th column (cols 0, 8, 16, 24, 32 in 0-indexed
/// terms).  Starting at col 0 and pressing Tab once should land at col 8; starting at
/// col 8 should land at col 16, and so on.
#[test]
fn test_tab_stops_after_resize_40_cols() {
    let mut term = TerminalCore::new(24, 80);
    term.resize(24, 40);

    // From col 0 → should reach col 8
    term.advance(b"\x1b[1;1H"); // home
    term.advance(b"\t");
    assert_eq!(
        term.cursor_col(),
        8,
        "tab from col 0 should land at col 8 in 40-col terminal"
    );

    // From col 8 → should reach col 16
    term.advance(b"\t");
    assert_eq!(term.cursor_col(), 16, "second tab should land at col 16");

    // From col 16 → should reach col 24
    term.advance(b"\t");
    assert_eq!(term.cursor_col(), 24, "third tab should land at col 24");

    // From col 24 → should reach col 32
    term.advance(b"\t");
    assert_eq!(term.cursor_col(), 32, "fourth tab should land at col 32");
}

/// `flush_print_buf` with a multi-character ASCII buffer must write all characters.
///
/// Accumulate several ASCII characters; flushing must write every one to the grid.
/// We trigger the flush by printing a non-ASCII Unicode character after the ASCII run.
#[test]
fn test_flush_print_buf_multi_char_buffer() {
    let mut term = TerminalCore::new(24, 80);
    // "HELLO" (5 ASCII chars) followed by '★' (U+2605, non-ASCII) triggers flush
    term.advance("HELLO★".as_bytes());

    // Verify each ASCII cell
    for (idx, expected) in b"HELLO".iter().enumerate() {
        let cell = term
            .get_cell(0, idx)
            .unwrap_or_else(|| panic!("cell (0,{idx}) must exist"));
        assert_eq!(
            cell.char(),
            char::from(*expected),
            "cell (0,{idx}) must contain '{}'",
            char::from(*expected)
        );
    }
    // Cursor must be past 'HELLO' (5 cols) plus the width of '★' (1 col) = col 6
    assert_eq!(
        term.cursor_col(),
        6,
        "cursor must be at col 6 after 'HELLO★'"
    );
}

/// OSC 8 hyperlink round-trip: set a URI, verify `osc_data().hyperlink.uri` is set;
/// then close the hyperlink and verify the URI is cleared.
///
/// Note: The terminal core stores the active hyperlink URI in `osc_data.hyperlink`
/// but does not stamp `hyperlink_id` onto individual grid cells at print time.
/// Compliance is verified at the `osc_data` level.
#[test]
fn test_osc8_hyperlink_round_trip() {
    let mut term = TerminalCore::new(24, 80);

    // Open hyperlink with id=foo and a URI
    term.advance(b"\x1b]8;id=foo;https://example.com\x07");
    let uri = term
        .osc_data()
        .hyperlink
        .uri
        .as_deref()
        .expect("hyperlink URI must be set after OSC 8 open");
    assert_eq!(uri, "https://example.com", "URI must match the sent value");

    // Close hyperlink (empty URI)
    term.advance(b"\x1b]8;;\x07");
    assert!(
        term.osc_data().hyperlink.uri.is_none(),
        "hyperlink URI must be None after OSC 8 close"
    );
}

/// `take_title` semantics: after reading title via `title()` + `title_dirty()`,
/// a full reset clears the dirty flag; a second check returns no dirty title.
///
/// The `TerminalCore` public API exposes `title()` + `title_dirty()`.
/// This test pins the consume-once semantics: dirty is true exactly until reset.
#[test]
fn test_title_dirty_flag_clears_after_reset() {
    let mut term = TerminalCore::new(24, 80);

    // Set a title
    term.advance(b"\x1b]2;my-title\x07");
    assert!(term.title_dirty(), "title_dirty must be true after OSC 2");
    assert_eq!(term.title(), "my-title");

    // reset() clears the dirty flag
    term.reset();
    assert!(
        !term.title_dirty(),
        "title_dirty must be false after reset()"
    );
    assert_eq!(term.title(), "", "title must be empty after reset()");

    // Calling again (no new OSC 2) — dirty must still be false
    assert!(
        !term.title_dirty(),
        "title_dirty must remain false without a new OSC 2"
    );
}

/// Scrollback buffer is cleared by ED 3 (`CSI 3 J`), not by `reset()`.
///
/// `reset()` (RIS — ESC c) is a terminal-mode reset; it resets DEC modes,
/// SGR attributes, tab stops, and title state, but intentionally preserves
/// screen content (including scrollback) so that session output is not lost
/// on a mode-reset event.
///
/// To wipe scrollback the application must send `CSI 3 J` explicitly.
#[test]
fn test_scrollback_cleared_by_ed3_not_reset() {
    // Use a small terminal so we generate scrollback quickly
    let mut term = TerminalCore::new(3, 20);
    // Force lines into scrollback by overflowing the 3-row screen
    term.advance(b"line1\nline2\nline3\nline4\nline5");
    let scrollback_before = term.scrollback_line_count();
    assert!(
        scrollback_before > 0,
        "scrollback must be non-empty after overflow; got {scrollback_before}"
    );

    // Full reset (RIS) does NOT clear scrollback — screen content is preserved
    term.reset();
    assert!(
        term.scrollback_line_count() > 0,
        "reset() must NOT clear scrollback (got 0, expected > 0)"
    );

    // ED 3 (CSI 3 J) explicitly clears the scrollback buffer
    term.advance(b"\x1b[3J");
    assert_eq!(
        term.scrollback_line_count(),
        0,
        "CSI 3 J must clear scrollback to 0"
    );
}

/// `set_default_bg_color` (via OSC 11) persists across a `resize`.
///
/// After setting a custom default background via OSC 11 and then resizing
/// the terminal, `osc_data().default_bg` must still hold the colour.
#[test]
fn test_default_bg_color_persists_across_resize() {
    let mut term = TerminalCore::new(24, 80);

    // Set a custom default background colour via OSC 11 (xterm protocol)
    // Format: OSC 11 ; rgb:RRRR/GGGG/BBBB BEL
    term.advance(b"\x1b]11;rgb:ff/00/7f\x07");
    assert!(
        term.osc_data().default_bg.is_some(),
        "default_bg must be set after OSC 11"
    );
    let bg_before = term.osc_data().default_bg;

    // Resize — must not clear the custom colour
    term.resize(20, 60);

    assert_eq!(
        term.osc_data().default_bg,
        bg_before,
        "default_bg must persist across resize"
    );
}

/// DECSC / DECRC cursor position round-trip via ESC 7 / ESC 8.
///
/// Save position at (4, 9), move elsewhere, restore — cursor returns to (4, 9).
#[test]
fn test_decsc_decrc_cursor_position() {
    let mut term = TerminalCore::new(24, 80);

    // Position cursor at (row=4, col=9)
    term.advance(b"\x1b[5;10H"); // CUP 1-indexed → 0-indexed (4, 9)
    assert_eq!(term.cursor_row(), 4);
    assert_eq!(term.cursor_col(), 9);

    // Save cursor via ESC 7
    term.advance(b"\x1b7");

    // Move cursor to home
    term.advance(b"\x1b[H");
    assert_eq!(
        term.cursor_row(),
        0,
        "cursor must be at row 0 after CUP home"
    );
    assert_eq!(
        term.cursor_col(),
        0,
        "cursor must be at col 0 after CUP home"
    );

    // Restore cursor via ESC 8
    term.advance(b"\x1b8");
    assert_eq!(
        term.cursor_row(),
        4,
        "DECRC must restore cursor to saved row 4"
    );
    assert_eq!(
        term.cursor_col(),
        9,
        "DECRC must restore cursor to saved col 9"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Alternate screen cursor preservation
// ─────────────────────────────────────────────────────────────────────────────

/// Entering alternate screen (?1049h) saves the primary cursor; exiting (?1049l)
/// restores it, so the cursor returns to the position it had before entering.
#[test]
fn test_alt_screen_saves_and_restores_cursor() {
    let mut term = TerminalCore::new(24, 80);
    // Position cursor on primary screen
    term.advance(b"\x1b[6;15H"); // CUP → row 5, col 14 (0-indexed)
    assert_eq!(term.cursor_row(), 5);
    assert_eq!(term.cursor_col(), 14);

    // Enter alt screen — cursor should reset on alt screen
    term.advance(b"\x1b[?1049h");
    assert!(
        term.is_alternate_screen_active(),
        "must be on alt screen after ?1049h"
    );
    // Move around on alt screen
    term.advance(b"\x1b[3;3H");
    assert_eq!(term.cursor_row(), 2);

    // Exit alt screen — cursor must return to saved primary position
    term.advance(b"\x1b[?1049l");
    assert!(
        !term.is_alternate_screen_active(),
        "must be on primary screen after ?1049l"
    );
    assert_eq!(
        term.cursor_row(),
        5,
        "primary cursor row must be restored after leaving alt screen"
    );
    assert_eq!(
        term.cursor_col(),
        14,
        "primary cursor col must be restored after leaving alt screen"
    );
}

/// Content printed on the alternate screen must not appear on the primary screen
/// after returning.
#[test]
fn test_alt_screen_content_does_not_bleed_to_primary() {
    let mut term = TerminalCore::new(24, 80);
    // Put known content on primary screen
    term.advance(b"\x1b[1;1H");
    term.advance(b"PRIMARY");

    // Enter alt screen and write different content
    term.advance(b"\x1b[?1049h");
    term.advance(b"\x1b[1;1H");
    term.advance(b"ALTSCR");

    // Return to primary screen
    term.advance(b"\x1b[?1049l");

    // Primary screen row 0 must still start with 'P'
    let cell = term
        .get_cell(0, 0)
        .expect("cell (0,0) must exist on primary");
    assert_eq!(
        cell.char(),
        'P',
        "primary screen must not be overwritten by alt-screen content"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Erase-in-display (ED) modes 0 and 1
// ─────────────────────────────────────────────────────────────────────────────

/// ED 0 (CSI 0 J) erases from cursor to end of display.
#[test]
fn test_ed0_erases_from_cursor_to_end() {
    let mut term = TerminalCore::new(5, 10);
    // Write something on row 0 and row 1
    term.advance(b"AAAAAAAAAA"); // fills row 0
    term.advance(b"\nBBBBBBBBBB"); // fills row 1
                                   // Move cursor to row 0, col 5
    term.advance(b"\x1b[1;6H"); // 1-indexed → row 0, col 5
    term.advance(b"\x1b[0J"); // ED 0: erase from cursor to bottom
                              // col 0..4 on row 0 must still be 'A'
    for col in 0..5 {
        let cell = term.get_cell(0, col).expect("cell must exist");
        assert_eq!(cell.char(), 'A', "cell (0,{col}) must survive ED 0");
    }
    // col 5 onward on row 0 must be erased
    let erased = term.get_cell(0, 5).expect("cell (0,5) must exist");
    assert_eq!(erased.char(), ' ', "cell (0,5) must be erased by ED 0");
    // row 1 must be fully erased
    let r1 = term.get_cell(1, 0).expect("cell (1,0) must exist");
    assert_eq!(r1.char(), ' ', "row 1, col 0 must be erased by ED 0");
}

/// ED 1 (CSI 1 J) erases from beginning of display to cursor (inclusive).
#[test]
fn test_ed1_erases_from_start_to_cursor() {
    let mut term = TerminalCore::new(5, 10);
    // Write 'A' on row 0 and 'B' on row 1 (use CR+LF so 'B' starts at col 0)
    term.advance(b"AAAAAAAAAA");
    term.advance(b"\r\nBBBBBBBBBB");
    // Move cursor to row 1, col 4
    term.advance(b"\x1b[2;5H"); // 1-indexed → row 1, col 4
    term.advance(b"\x1b[1J"); // ED 1: erase from top to cursor
                              // row 0 must be fully erased
    let r0 = term.get_cell(0, 0).expect("cell (0,0) must exist");
    assert_eq!(r0.char(), ' ', "row 0 must be erased by ED 1");
    // row 1, cols 0–4 must be erased
    for col in 0..=4 {
        let cell = term.get_cell(1, col).expect("cell must exist");
        assert_eq!(cell.char(), ' ', "cell (1,{col}) must be erased by ED 1");
    }
    // row 1, cols 5–9 must still be 'B'
    let surviving = term.get_cell(1, 5).expect("cell (1,5) must exist");
    assert_eq!(surviving.char(), 'B', "cell (1,5) must survive ED 1");
}

// ─────────────────────────────────────────────────────────────────────────────
// Backspace at column 0 is a no-op
// ─────────────────────────────────────────────────────────────────────────────

/// BS (0x08) at column 0 must not move the cursor to a negative column.
#[test]
fn test_backspace_at_col_zero_is_noop() {
    let mut term = TerminalCore::new(24, 80);
    assert_eq!(term.cursor_col(), 0);
    term.advance(b"\x08"); // BS at col 0
    assert_eq!(
        term.cursor_col(),
        0,
        "BS at col 0 must not underflow cursor"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab at the last tab stop clamps at end of line
// ─────────────────────────────────────────────────────────────────────────────

/// On an 80-col terminal the last tab stop is col 72.  A HT from col 72
/// must not advance the cursor past col 79.
#[test]
fn test_tab_at_last_stop_stays_in_bounds() {
    let mut term = TerminalCore::new(24, 80);
    // Move to col 72 (the last standard tab stop on an 80-col terminal)
    term.advance(b"\x1b[1;73H"); // 1-indexed → row 0, col 72
    assert_eq!(term.cursor_col(), 72);
    term.advance(b"\t"); // HT: horizontal tab
    assert!(
        term.cursor_col() < 80,
        "tab from last stop must not push cursor past col 79; got {}",
        term.cursor_col()
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Resize: content on visible rows is preserved
// ─────────────────────────────────────────────────────────────────────────────

/// After a resize that grows the terminal, content on the first row must
/// still be readable via `get_cell`.
#[test]
fn test_resize_grow_preserves_visible_content() {
    let mut term = TerminalCore::new(10, 40);
    term.advance(b"\x1b[1;1H");
    term.advance(b"HELLO");
    term.resize(20, 80);
    // Row 0 content must survive the resize
    let h = term
        .get_cell(0, 0)
        .expect("cell (0,0) must exist after resize");
    assert_eq!(
        h.char(),
        'H',
        "cell (0,0) must still be 'H' after resize grow"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// CRLF vs LF
// ─────────────────────────────────────────────────────────────────────────────

/// A bare LF (0x0a) advances the row but does NOT reset the column.
#[test]
fn test_lf_advances_row_but_not_col() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"ABCDE"); // cursor at col 5
    assert_eq!(term.cursor_col(), 5);
    term.advance(b"\n"); // LF — row advances, col unchanged
    assert_eq!(term.cursor_row(), 1, "LF must advance row");
    assert_eq!(term.cursor_col(), 5, "LF must not reset col");
}

/// A CRLF pair advances the row AND resets the column to 0.
#[test]
fn test_crlf_advances_row_and_resets_col() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"ABCDE"); // cursor at col 5
    term.advance(b"\r\n"); // CR + LF
    assert_eq!(term.cursor_row(), 1, "CRLF must advance row");
    assert_eq!(term.cursor_col(), 0, "CRLF must reset col to 0");
}
