// ── Dirty tracking ────────────────────────────────────────────────────────────

#[test]
fn test_scroll_marks_dirty() {
    let mut term = crate::TerminalCore::new(5, 10);

    // Clear dirty set
    term.screen.take_dirty_lines();

    // Fill a line
    for c in 0..10 {
        if let Some(line) = term.screen.get_line_mut(0) {
            line.update_cell_with(c, crate::types::Cell::new('X'));
            line.is_dirty = false;
        }
    }

    // Scroll up
    let params = vte::Params::default();
    csi_su(&mut term, &params);

    // Should have dirty lines
    let dirty = term.screen.take_dirty_lines();
    assert!(!dirty.is_empty());
}

// ── SU edge cases ─────────────────────────────────────────────────────────────

/// SU via escape sequence (CSI S) scrolls up one line: row 0 gets content
/// that was previously in row 1.
#[test]
fn test_su_scroll_up_one_line() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'A');

    // CSI 1 S — scroll up 1 line
    term.advance(b"\x1b[S");

    // Row 0 should now contain the character that was in row 1 ('B')
    assert_eq!(
        term.screen.get_line(0).unwrap().cells[0].char(),
        'B',
        "after SU 1, row 0 should have former row 1 content"
    );
}

/// SU with content: the line that scrolled off the top should no longer be
/// visible at row 0, and the bottom of the screen should be blank.
#[test]
fn test_su_scroll_up_at_top_with_content() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_rows!(term, rows 5, base b'0');

    // Scroll up by 1 (CSI S)
    term.advance(b"\x1b[S");

    // Row 0 should no longer be '0' — it was scrolled off
    assert_ne!(
        term.screen.get_line(0).unwrap().cells[0].char(),
        '0',
        "row 0 character should have changed after scroll up"
    );

    // Bottom row (4) should be blank (newly introduced empty line)
    assert_eq!(
        term.screen.get_line(4).unwrap().cells[0].char(),
        ' ',
        "bottom row should be blank after scrolling up"
    );
}

/// SD via escape sequence (CSI T) scrolls down one line: row 0 becomes blank
/// and previous row 0 content appears in row 1.
#[test]
fn test_sd_scroll_down_one_line() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'A');

    // CSI 1 T — scroll down 1 line
    term.advance(b"\x1b[T");

    // Row 0 should now be blank
    assert_eq!(
        term.screen.get_line(0).unwrap().cells[0].char(),
        ' ',
        "after SD 1, row 0 should be blank"
    );

    // Row 1 should contain what was previously in row 0 ('A')
    assert_eq!(
        term.screen.get_line(1).unwrap().cells[0].char(),
        'A',
        "after SD 1, row 1 should have former row 0 content"
    );
}

/// RI (ESC M) moves the cursor up one row when not at the top of the scroll region.
#[test]
fn test_ri_moves_cursor_up_when_not_at_region_top() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Place cursor at row 5 (0-indexed), which is not the scroll region top (0).
    term.screen.move_cursor(5, 10);
    assert_eq!(term.screen.cursor.row, 5);
    assert_eq!(term.screen.cursor.col, 10);

    // Send ESC M (Reverse Index)
    term.advance(b"\x1bM");

    // Cursor should have moved up by one row; column unchanged.
    assert_eq!(term.screen.cursor.row, 4, "RI must move cursor up one row");
    assert_eq!(
        term.screen.cursor.col, 10,
        "RI must not change cursor column"
    );
}

/// RI (ESC M) at the top of the scroll region scrolls content down by one line
/// instead of moving the cursor, leaving it at the scroll region top.
#[test]
fn test_ri_scrolls_at_scroll_region_top() {
    let mut term = crate::TerminalCore::new(10, 10);

    // Set scroll region rows 3–7 (1-indexed CSI 3;7 r → 0-indexed top=2, bottom=7)
    term.advance(b"\x1b[3;7r");
    assert_eq!(term.screen.get_scroll_region().top, 2);

    // Fill rows 2–6 (the scroll region body) with distinct characters
    for r in 2..7usize {
        if let Some(line) = term.screen.get_line_mut(r) {
            for c in 0..10usize {
                line.update_cell_with(c, crate::types::Cell::new((b'A' + (r - 2) as u8) as char));
            }
        }
    }
    // Row 2='A', row 3='B', row 4='C', row 5='D', row 6='E'

    // Position cursor at the top of the scroll region (row 2)
    term.screen.move_cursor(2, 0);

    // Send ESC M — at scroll top, so content must scroll down
    term.advance(b"\x1bM");

    // Cursor must remain at the scroll region top (row 2)
    assert_eq!(
        term.screen.cursor.row, 2,
        "RI at scroll top must keep cursor at region top"
    );

    // Row 2 (scroll top) must now be blank (newly inserted line)
    assert_eq!(
        term.screen.get_line(2).unwrap().cells[0].char(),
        ' ',
        "RI at scroll top must insert a blank line at the top of the region"
    );

    // Row 3 must now contain what was previously in row 2 ('A')
    assert_eq!(
        term.screen.get_line(3).unwrap().cells[0].char(),
        'A',
        "RI must push former row 2 content down to row 3"
    );

    // Row 4 must now contain what was previously in row 3 ('B')
    assert_eq!(
        term.screen.get_line(4).unwrap().cells[0].char(),
        'B',
        "RI must push former row 3 content down to row 4"
    );
}

/// Scrolling up by more lines than the screen has should not panic and should
/// leave the entire screen blank.
#[test]
fn test_su_scroll_up_clamps_at_screen() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_rows!(term, rows 5, char 'X');

    // Scroll up by 100 lines (far more than the 5-row screen) — must not panic
    term.advance(b"\x1b[100S");

    // All rows should now be blank (or at least no panic occurred)
    for r in 0..5usize {
        assert_eq!(
            term.screen.get_line(r).unwrap().cells[0].char(),
            ' ',
            "row {r} should be blank after over-scroll"
        );
    }
}

#[test]
fn test_decstbm_inverted_margins_no_panic() {
    // \x1b[10;5r — DECSTBM with top=10 > bottom=5 (inverted)
    // Should not panic; scroll operations with inverted region are no-ops
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[10;5r");
    // Attempt scrolls — should not panic
    term.advance(b"\x1b[S"); // Scroll up
    term.advance(b"\x1b[T"); // Scroll down
}

/// When origin_mode (DECOM) is on, DECSTBM must move the cursor to the top
/// of the scroll region rather than to absolute (0, 0).
#[test]
fn test_decstbm_with_origin_mode_moves_cursor_to_region_top() {
    let mut term = crate::TerminalCore::new(24, 80);
    // Enable DECOM (origin mode): CSI ? 6 h
    term.advance(b"\x1b[?6h");
    assert!(
        term.dec_modes.origin_mode,
        "origin_mode must be set by CSI ? 6 h"
    );

    // Move cursor away from home first
    term.screen.move_cursor(10, 20);

    // DECSTBM: CSI 3;8 r → 0-indexed top=2, bottom=8
    term.advance(b"\x1b[3;8r");

    // With DECOM on, cursor must go to the scroll region top (row 2), not (0, 0).
    assert_eq!(
        term.screen.cursor().row,
        2,
        "DECSTBM with DECOM on must move cursor to scroll region top"
    );
    assert_eq!(
        term.screen.cursor().col,
        0,
        "DECSTBM must always reset cursor column to 0"
    );
}

/// RI (ESC M) when cursor is at row 0 but row 0 is NOT the scroll region top
/// should move the cursor up by one line only if row > 0.  At row 0 with a
/// non-zero scroll-region top the cursor cannot move up, so it stays at row 0.
#[test]
fn test_ri_at_row_zero_not_scroll_region_top_stays_at_zero() {
    let mut term = crate::TerminalCore::new(10, 10);
    // Set scroll region: 0-indexed top=3, bottom=8 (CSI 4;8 r)
    term.advance(b"\x1b[4;8r");
    // Cursor goes to (0, 0) after DECSTBM
    assert_eq!(term.screen.cursor().row, 0);

    // RI at row=0: cursor_row (0) != scroll_top (3), and cursor_row is NOT > 0.
    // The else-if branch requires cursor_row > 0, so no move happens.
    term.advance(b"\x1bM");
    assert_eq!(
        term.screen.cursor().row,
        0,
        "RI at absolute row 0 (below scroll-region top) must keep cursor at row 0"
    );
}
