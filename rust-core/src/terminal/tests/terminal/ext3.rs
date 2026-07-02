use super::super::make_term;

// Direct unit tests for `TerminalCore::stamp_hyperlink_on_last_n_cells`.
//
// The function is normally called from `flush_print_buf` (ASCII run path) and
// from `apc::advance_with_apc` (APC/Kitty path).  These tests exercise the
// edge cases that integration tests do not reach directly.

/// `stamp_hyperlink_on_last_n_cells(0)` is a no-op — no cells are mutated.
#[test]
fn test_stamp_hyperlink_n_zero_is_noop() {
    let mut term = make_term();
    // Activate hyperlink first.
    term.advance(b"\x1b]8;;https://example.com\x07");
    // Confirm hyperlink is active.
    assert!(term.osc_data.hyperlink.uri.is_some());
    // Print one character so the cell would normally be stamped.
    term.advance(b"X");
    // Force-call with n=0 — the cell already has a hyperlink from the print,
    // but calling with 0 must not crash.
    term.stamp_hyperlink_on_last_n_cells(0); // must not panic
}

/// When no hyperlink URI is active, `stamp_hyperlink_on_last_n_cells` is a no-op.
#[test]
fn test_stamp_hyperlink_no_uri_is_noop() {
    let mut term = make_term();
    // No hyperlink set — URI is None.
    assert!(term.osc_data.hyperlink.uri.is_none());
    // Must not panic; no cells should be mutated (they're already None).
    term.stamp_hyperlink_on_last_n_cells(5);
    // Cell 0 should have no hyperlink ID.
    assert_eq!(
        term.screen.get_cell(0, 0).map(|c| c.hyperlink_id()),
        Some(None),
        "cell must have no hyperlink when URI is inactive"
    );
}

/// Printing a short string with an active hyperlink stamps every cell.
#[test]
fn test_stamp_hyperlink_via_ascii_flush_stamps_each_cell() {
    let mut term = make_term();
    term.advance(b"\x1b]8;;https://abc.test\x07");
    term.advance(b"hello"); // 5 chars, cells 0-4 on row 0
    for col in 0..5_usize {
        assert_eq!(
            term.screen.get_cell(0, col).and_then(|c| c.hyperlink_id()),
            Some("https://abc.test"),
            "col {col} must carry the hyperlink URI"
        );
    }
    // Cell 5 (not printed) must have no hyperlink.
    assert_eq!(
        term.screen.get_cell(0, 5).and_then(|c| c.hyperlink_id()),
        None,
        "col 5 (not printed) must not have a hyperlink"
    );
}

/// Printing exactly enough characters to fill row 0 and spill into row 1
/// causes `stamp_hyperlink_on_last_n_cells` to walk backward across the line
/// boundary.
#[test]
fn test_stamp_hyperlink_spans_row_boundary() {
    // Use a narrow terminal so the line boundary is easy to provoke.
    let mut term = crate::TerminalCore::new(24, 10);
    term.advance(b"\x1b]8;;https://row-boundary.test\x07");
    // Print 12 characters: 10 fill row 0, 2 overflow to row 1.
    term.advance(b"0123456789AB"); // row 0: 0-9, row 1: A B
                                   // Row 1 cells 0 and 1 must have the hyperlink.
    for col in 0..2_usize {
        assert_eq!(
            term.screen.get_cell(1, col).and_then(|c| c.hyperlink_id()),
            Some("https://row-boundary.test"),
            "row 1 col {col} must carry the hyperlink URI"
        );
    }
    // Row 0 cells 0-9 must also have the hyperlink.
    for col in 0..10_usize {
        assert_eq!(
            term.screen.get_cell(0, col).and_then(|c| c.hyperlink_id()),
            Some("https://row-boundary.test"),
            "row 0 col {col} must carry the hyperlink URI"
        );
    }
}

/// After closing the hyperlink (empty URI), newly printed text gets no stamp.
#[test]
fn test_stamp_hyperlink_stops_after_close() {
    let mut term = make_term();
    term.advance(b"\x1b]8;;https://open.test\x07");
    term.advance(b"ON");
    // Close hyperlink.
    term.advance(b"\x1b]8;;\x07");
    term.advance(b"OFF");
    // "OFF" cells must have no hyperlink.
    for col in 2..5_usize {
        assert_eq!(
            term.screen.get_cell(0, col).and_then(|c| c.hyperlink_id()),
            None,
            "col {col} must not have a hyperlink after OSC 8 close"
        );
    }
}
