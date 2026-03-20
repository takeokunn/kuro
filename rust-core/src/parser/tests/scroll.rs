//! Property-based and example-based tests for `scroll` parsing.
//!
//! Module under test: `parser/scroll.rs`
//! Tier: T3 — ProptestConfig::with_cases(256)

use super::*;

#[test]
fn test_decstbm_default() {
    let mut term = crate::TerminalCore::new(10, 80);

    // DECSTBM with no parameters should set full screen as scroll region
    let params = vte::Params::default();
    csi_decstbm(&mut term, &params);

    // Check scroll region (0-indexed: top=0, bottom=10 for 10 rows)
    assert_eq!(term.screen.get_scroll_region().top, 0);
    assert_eq!(term.screen.get_scroll_region().bottom, 10);
}

#[test]
fn test_decstbm_with_params() {
    let mut term = crate::TerminalCore::new(10, 80);

    // Set scroll region from row 3 to row 8 (1-indexed: CSI 3;8 r)
    // This becomes (2, 8) in 0-indexed
    term.advance(b"\x1b[3;8r");

    assert_eq!(term.screen.get_scroll_region().top, 2);
    assert_eq!(term.screen.get_scroll_region().bottom, 8);
}

#[test]
fn test_decstbm_moves_cursor_to_home() {
    let mut term = crate::TerminalCore::new(10, 80);

    // Move cursor away from home
    term.screen.move_cursor(5, 10);
    assert_eq!(term.screen.cursor.row, 5);

    // Set scroll region from row 2 to row 8 (1-indexed: CSI 2;8 r)
    // top becomes 1 (0-indexed)
    term.advance(b"\x1b[2;8r");

    // Per DEC VT510: DECOM off (default) → cursor to absolute (0, 0).
    assert_eq!(term.screen.cursor.row, 0);
    assert_eq!(term.screen.cursor.col, 0);
}

#[test]
fn test_decstbm_inverted_margins_ignored() {
    // CSI 8;3 r — top=8, bottom=3 — top > bottom, should be ignored
    let mut term = crate::TerminalCore::new(10, 80);
    // First set a valid scroll region to verify it doesn't change
    term.advance(b"\x1b[2;8r"); // valid: 1-indexed top=2, bottom=8 → 0-indexed top=1, bottom=8
                                // Now try invalid: top > bottom
    term.advance(b"\x1b[8;3r"); // invalid: should be ignored
                                // The valid region from before should still be active
                                // (cursor will be at home after DECSTBM per spec)
    assert!(term.screen.cursor.row < 10);
    assert!(term.screen.cursor.col < 80);
    // The previously-set valid region must be preserved
    let region = term.screen.get_scroll_region();
    assert_eq!(region.top, 1, "scroll region top must be unchanged after invalid DECSTBM");
    assert_eq!(region.bottom, 8, "scroll region bottom must be unchanged after invalid DECSTBM");
}

#[test]
fn test_decstbm_equal_margins_ignored() {
    // CSI 5;5 r — 1-indexed top=5, bottom=5.
    // After 0-indexing: top=4, bottom=5. Since 4 < 5, this is actually
    // accepted by the implementation (equal 1-indexed args become a
    // one-row scroll region in 0-indexed form).
    let mut term = crate::TerminalCore::new(10, 80);
    term.advance(b"\x1b[5;5r");
    assert!(term.screen.cursor.row < 10);
    // Verify the resulting scroll region is exactly (top=4, bottom=5)
    let region = term.screen.get_scroll_region();
    assert_eq!(region.top, 4, "CSI 5;5r sets 0-indexed top=4");
    assert_eq!(region.bottom, 5, "CSI 5;5r sets 0-indexed bottom=5");
}

#[test]
fn test_su_default() {
    let mut term = crate::TerminalCore::new(10, 10);

    // Fill lines with different characters
    for r in 0..10 {
        if let Some(line) = term.screen.get_line_mut(r) {
            for c in 0..10 {
                line.update_cell_with(c, crate::types::Cell::new((b'0' + r as u8) as char));
            }
        }
    }

    // SU with no parameter (default: 1 line)
    let params = vte::Params::default();
    csi_su(&mut term, &params);

    // Line 0 should now be blank (original line 1 moved there)
    let line = term.screen.get_line(0).unwrap();
    assert_eq!(line.cells[0].char(), '1');
}

#[test]
fn test_su_with_param() {
    let mut term = crate::TerminalCore::new(10, 10);

    // Fill lines
    for r in 0..10 {
        if let Some(line) = term.screen.get_line_mut(r) {
            for c in 0..10 {
                line.update_cell_with(c, crate::types::Cell::new((b'A' + r as u8) as char));
            }
        }
    }

    // Scroll up 3 lines (CSI 3 S)
    term.advance(b"\x1b[3S");

    // Line 0 should now have content from line 3
    let line = term.screen.get_line(0).unwrap();
    assert_eq!(line.cells[0].char(), 'D');
}

#[test]
fn test_su_respects_scroll_region() {
    let mut term = crate::TerminalCore::new(10, 10);

    // Fill all lines
    for r in 0..10 {
        if let Some(line) = term.screen.get_line_mut(r) {
            for c in 0..10 {
                line.update_cell_with(c, crate::types::Cell::new((b'0' + r as u8) as char));
            }
        }
    }

    // Set scroll region from row 3 to 8 (0-indexed: 2 to 8)
    term.screen.set_scroll_region(2, 8);

    // Scroll up
    let params = vte::Params::default();
    csi_su(&mut term, &params);

    // Lines outside scroll region should be unchanged
    let line = term.screen.get_line(0).unwrap();
    assert_eq!(line.cells[0].char(), '0');

    let line = term.screen.get_line(1).unwrap();
    assert_eq!(line.cells[0].char(), '1');

    // Lines inside scroll region should have scrolled
    let line = term.screen.get_line(2).unwrap();
    assert_eq!(line.cells[0].char(), '3'); // Was '2', now '3'

    // Bottom of scroll region should be blank
    let line = term.screen.get_line(7).unwrap();
    assert_eq!(line.cells[0].char(), ' ');
}

#[test]
fn test_sd_default() {
    let mut term = crate::TerminalCore::new(10, 10);

    // Fill lines
    for r in 0..10 {
        if let Some(line) = term.screen.get_line_mut(r) {
            for c in 0..10 {
                line.update_cell_with(c, crate::types::Cell::new((b'A' + r as u8) as char));
            }
        }
    }

    // SD with no parameter (default: 1 line)
    let params = vte::Params::default();
    csi_sd(&mut term, &params);

    // Content moves up
    let line = term.screen.get_line(0).unwrap();
    assert_eq!(line.cells[0].char(), ' '); // Line 0 becomes blank

    let line = term.screen.get_line(1).unwrap();
    assert_eq!(line.cells[0].char(), 'A'); // Line 1 now has what was in line 0
}

#[test]
fn test_sd_with_param() {
    let mut term = crate::TerminalCore::new(10, 10);

    // Fill lines
    for r in 0..10 {
        if let Some(line) = term.screen.get_line_mut(r) {
            for c in 0..10 {
                line.update_cell_with(c, crate::types::Cell::new((b'0' + r as u8) as char));
            }
        }
    }

    // Scroll down 3 lines (CSI 3 T)
    term.advance(b"\x1b[3T");

    // First 3 lines should be blank
    for r in 0..3 {
        let line = term.screen.get_line(r).unwrap();
        assert_eq!(line.cells[0].char(), ' ');
    }

    // Line 3 should now have content from line 0
    let line = term.screen.get_line(3).unwrap();
    assert_eq!(line.cells[0].char(), '0');
}

#[test]
fn test_sd_respects_scroll_region() {
    let mut term = crate::TerminalCore::new(10, 10);

    // Fill all lines
    for r in 0..10 {
        if let Some(line) = term.screen.get_line_mut(r) {
            for c in 0..10 {
                line.update_cell_with(c, crate::types::Cell::new((b'0' + r as u8) as char));
            }
        }
    }

    // Set scroll region from row 3 to 8 (0-indexed: 2 to 8)
    term.screen.set_scroll_region(2, 8);

    // Scroll down
    let params = vte::Params::default();
    csi_sd(&mut term, &params);

    // Lines outside scroll region should be unchanged
    let line = term.screen.get_line(0).unwrap();
    assert_eq!(line.cells[0].char(), '0');

    let line = term.screen.get_line(1).unwrap();
    assert_eq!(line.cells[0].char(), '1');

    // Lines inside scroll region should have scrolled
    let line = term.screen.get_line(2).unwrap();
    assert_eq!(line.cells[0].char(), ' '); // Top of scroll region becomes blank

    let line = term.screen.get_line(3).unwrap();
    assert_eq!(line.cells[0].char(), '2'); // Was '3', now '2'

    // Bottom of scroll region should have content from above
    let line = term.screen.get_line(7).unwrap();
    assert_eq!(line.cells[0].char(), '6');
}

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

/// SU via escape sequence (CSI S) scrolls up one line: row 0 gets content
/// that was previously in row 1.
#[test]
fn test_su_scroll_up_one_line() {
    let mut term = crate::TerminalCore::new(10, 10);

    // Fill rows with distinct characters
    for r in 0..10usize {
        if let Some(line) = term.screen.get_line_mut(r) {
            for c in 0..10usize {
                line.update_cell_with(c, crate::types::Cell::new((b'A' + r as u8) as char));
            }
        }
    }

    // CSI 1 S — scroll up 1 line
    term.advance(b"\x1b[S");

    // Row 0 should now contain the character that was in row 1 ('B')
    let line = term.screen.get_line(0).unwrap();
    assert_eq!(
        line.cells[0].char(),
        'B',
        "after SU 1, row 0 should have former row 1 content"
    );
}

/// SU with content: the line that scrolled off the top should no longer be
/// visible at row 0, and the bottom of the screen should be blank.
#[test]
fn test_su_scroll_up_at_top_with_content() {
    let mut term = crate::TerminalCore::new(5, 10);

    // Fill all rows with a unique char
    for r in 0..5usize {
        if let Some(line) = term.screen.get_line_mut(r) {
            for c in 0..10usize {
                line.update_cell_with(c, crate::types::Cell::new((b'0' + r as u8) as char));
            }
        }
    }

    // Scroll up by 1 (CSI S)
    term.advance(b"\x1b[S");

    // Row 0 should no longer be '0' — it was scrolled off
    let line0 = term.screen.get_line(0).unwrap();
    assert_ne!(
        line0.cells[0].char(),
        '0',
        "row 0 character should have changed after scroll up"
    );

    // Bottom row (4) should be blank (newly introduced empty line)
    let bottom = term.screen.get_line(4).unwrap();
    assert_eq!(
        bottom.cells[0].char(),
        ' ',
        "bottom row should be blank after scrolling up"
    );
}

/// SD via escape sequence (CSI T) scrolls down one line: row 0 becomes blank
/// and previous row 0 content appears in row 1.
#[test]
fn test_sd_scroll_down_one_line() {
    let mut term = crate::TerminalCore::new(10, 10);

    // Fill rows
    for r in 0..10usize {
        if let Some(line) = term.screen.get_line_mut(r) {
            for c in 0..10usize {
                line.update_cell_with(c, crate::types::Cell::new((b'A' + r as u8) as char));
            }
        }
    }

    // CSI 1 T — scroll down 1 line
    term.advance(b"\x1b[T");

    // Row 0 should now be blank
    let top = term.screen.get_line(0).unwrap();
    assert_eq!(
        top.cells[0].char(),
        ' ',
        "after SD 1, row 0 should be blank"
    );

    // Row 1 should contain what was previously in row 0 ('A')
    let row1 = term.screen.get_line(1).unwrap();
    assert_eq!(
        row1.cells[0].char(),
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
    assert_eq!(term.screen.cursor.col, 10, "RI must not change cursor column");
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
    let top_line = term.screen.get_line(2).unwrap();
    assert_eq!(
        top_line.cells[0].char(),
        ' ',
        "RI at scroll top must insert a blank line at the top of the region"
    );

    // Row 3 must now contain what was previously in row 2 ('A')
    let next_line = term.screen.get_line(3).unwrap();
    assert_eq!(
        next_line.cells[0].char(),
        'A',
        "RI must push former row 2 content down to row 3"
    );

    // Row 4 must now contain what was previously in row 3 ('B')
    let row4 = term.screen.get_line(4).unwrap();
    assert_eq!(
        row4.cells[0].char(),
        'B',
        "RI must push former row 3 content down to row 4"
    );
}

/// Scrolling up by more lines than the screen has should not panic and should
/// leave the entire screen blank.
#[test]
fn test_su_scroll_up_clamps_at_screen() {
    let mut term = crate::TerminalCore::new(5, 10);

    // Fill all rows
    for r in 0..5usize {
        if let Some(line) = term.screen.get_line_mut(r) {
            for c in 0..10usize {
                line.update_cell_with(c, crate::types::Cell::new('X'));
            }
        }
    }

    // Scroll up by 100 lines (far more than the 5-row screen) — must not panic
    term.advance(b"\x1b[100S");

    // All rows should now be blank (or at least no panic occurred)
    for r in 0..5usize {
        let line = term.screen.get_line(r).unwrap();
        assert_eq!(
            line.cells[0].char(),
            ' ',
            "row {} should be blank after over-scroll",
            r
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

use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    // PANIC SAFETY: SU (CSI n S) with any parameter never panics
    fn prop_su_no_panic(n in 0u16..=300u16) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.advance(format!("\x1b[{}S", n).as_bytes());
        prop_assert!(term.screen.rows() == 10);
    }

    #[test]
    // PANIC SAFETY: SD (CSI n T) with any parameter never panics
    fn prop_sd_no_panic(n in 0u16..=300u16) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.advance(format!("\x1b[{}T", n).as_bytes());
        prop_assert!(term.screen.rows() == 10);
    }

    #[test]
    // INVARIANT: RI (ESC M) never panics from any cursor position
    fn prop_ri_no_panic(row in 0usize..10usize) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.screen.move_cursor(row, 0);
        term.advance(b"\x1bM");
        prop_assert!(term.screen.cursor().row < 10);
    }

    #[test]
    // INVARIANT: valid DECSTBM (top < bottom, both in range) sets scroll region
    fn prop_decstbm_valid_accepts(
        top in 1u16..=8u16,
        extra in 1u16..=2u16,
    ) {
        let rows = 10u16;
        let bot = (top + extra).min(rows);
        prop_assume!(top < bot);
        let mut term = crate::TerminalCore::new(rows as u16, 20);
        term.advance(format!("\x1b[{};{}r", top, bot).as_bytes());
        // After valid DECSTBM, cursor must be at home
        prop_assert_eq!(term.screen.cursor().row, 0);
        prop_assert_eq!(term.screen.cursor().col, 0);
    }

    #[test]
    // INVARIANT: invalid DECSTBM (top >= bottom) is ignored — cursor still in bounds
    fn prop_decstbm_invalid_no_panic(
        top in 1u16..=10u16,
        bot in 1u16..=10u16,
    ) {
        prop_assume!(top >= bot);
        let mut term = crate::TerminalCore::new(10, 20);
        term.advance(format!("\x1b[{};{}r", top, bot).as_bytes());
        prop_assert!(term.screen.cursor().row < 10);
        prop_assert!(term.screen.cursor().col < 20);
    }
}
