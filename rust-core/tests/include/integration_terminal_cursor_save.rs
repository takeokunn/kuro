use super::*;

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

/// OSC 8 hyperlink round-trip: set a URI, verify `osc_data().hyperlink_uri()` is set;
/// then close the hyperlink and verify the URI is cleared.
/// Also verifies that cells printed while a hyperlink is active carry the URI.
#[test]
fn test_osc8_hyperlink_round_trip() {
    let mut term = TerminalCore::new(24, 80);

    // Open hyperlink with id=foo and a URI
    term.advance(b"\x1b]8;id=foo;https://example.com\x07");
    let uri = term
        .osc_data()
        .hyperlink_uri()
        .expect("hyperlink URI must be set after OSC 8 open");
    assert_eq!(uri, "https://example.com", "URI must match the sent value");

    // Print text while hyperlink is active — cells must carry the URI
    term.advance(b"click here");
    for col in 0..10 {
        let cell = term.get_cell(0, col).expect("cell must exist");
        assert_eq!(
            cell.hyperlink_id(),
            Some("https://example.com"),
            "cell at col {col} must have hyperlink URI"
        );
    }

    // Close hyperlink (empty URI)
    term.advance(b"\x1b]8;;\x07");
    assert!(
        term.osc_data().hyperlink_uri().is_none(),
        "hyperlink URI must be None after OSC 8 close"
    );

    // Text printed after close must NOT have a hyperlink
    term.advance(b"plain");
    for col in 10..15 {
        let cell = term.get_cell(0, col).expect("cell must exist");
        assert_eq!(
            cell.hyperlink_id(),
            None,
            "cell at col {col} must not have hyperlink after close"
        );
    }
}

/// `take_title` semantics: after reading title via `title()` + `title_dirty()`,
/// a full reset clears the dirty flag; a second check returns no dirty title.
///
/// The `TerminalCore` public API exposes `title()` + `title_dirty()`.
/// This test pins the consume-once semantics: dirty is true exactly until reset.
#[path = "integration_terminal_cursor_save_part2.rs"]
mod part2;
