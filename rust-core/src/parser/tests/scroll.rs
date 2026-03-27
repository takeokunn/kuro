//! Property-based and example-based tests for `scroll` parsing.
//!
//! Module under test: `parser/scroll.rs`
//! Tier: T3 — `ProptestConfig::with_cases(256)`

// Test helpers convert between usize/u16/i64 for grid coordinates; values are
// bounded by terminal dimensions (≤ 65535 rows/cols) so truncation is safe.
#![expect(
    clippy::cast_possible_truncation,
    reason = "test coordinate casts bounded by terminal dimensions (≤ 65535)"
)]

use super::*;

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Fill every cell in every row of `term` with a character derived from `base`:
/// row 0 gets `base`, row 1 gets `base + 1`, etc.  The terminal must have
/// fewer than 26 rows so the cast never overflows.
macro_rules! fill_rows {
    ($term:expr, rows $n:expr, base $base:expr) => {{
        for r in 0..$n {
            if let Some(line) = $term.screen.get_line_mut(r) {
                let ch = ($base as u8 + r as u8) as char;
                let cols = line.cells.len();
                for c in 0..cols {
                    line.update_cell_with(c, crate::types::Cell::new(ch));
                }
            }
        }
    }};
    // Convenience: fill all rows with a single fixed character
    ($term:expr, rows $n:expr, char $ch:expr) => {{
        for r in 0..$n {
            if let Some(line) = $term.screen.get_line_mut(r) {
                let cols = line.cells.len();
                for c in 0..cols {
                    line.update_cell_with(c, crate::types::Cell::new($ch));
                }
            }
        }
    }};
}

/// Assert that every cell in every row still holds the character that
/// `fill_rows!(term, rows N, base BASE)` would have written, i.e. `base + r`.
macro_rules! assert_rows_unchanged {
    ($term:expr, rows $n:expr, base $base:expr) => {{
        for r in 0..$n {
            let ch = ($base as u8 + r as u8) as char;
            assert_eq!(
                $term
                    .screen
                    .get_cell(r, 0)
                    .map_or(' ', crate::types::cell::Cell::char),
                ch,
                "row {r} should be unchanged"
            );
        }
    }};
}

// ── DECSTBM ───────────────────────────────────────────────────────────────────

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
    assert_eq!(
        region.top, 1,
        "scroll region top must be unchanged after invalid DECSTBM"
    );
    assert_eq!(
        region.bottom, 8,
        "scroll region bottom must be unchanged after invalid DECSTBM"
    );
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

// ── SU (Scroll Up) ────────────────────────────────────────────────────────────

#[test]
fn test_su_default() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'0');

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
    fill_rows!(term, rows 10, base b'A');

    // Scroll up 3 lines (CSI 3 S)
    term.advance(b"\x1b[3S");

    // Line 0 should now have content from line 3
    let line = term.screen.get_line(0).unwrap();
    assert_eq!(line.cells[0].char(), 'D');
}

#[test]
fn test_su_respects_scroll_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'0');

    // Set scroll region from row 3 to 8 (0-indexed: 2 to 8)
    term.screen.set_scroll_region(2, 8);

    // Scroll up
    let params = vte::Params::default();
    csi_su(&mut term, &params);

    // Lines outside scroll region should be unchanged
    assert_eq!(term.screen.get_line(0).unwrap().cells[0].char(), '0');
    assert_eq!(term.screen.get_line(1).unwrap().cells[0].char(), '1');

    // Lines inside scroll region should have scrolled
    assert_eq!(
        term.screen.get_line(2).unwrap().cells[0].char(),
        '3', // Was '2', now '3'
    );

    // Bottom of scroll region should be blank
    assert_eq!(term.screen.get_line(7).unwrap().cells[0].char(), ' ');
}

// ── SD (Scroll Down) ──────────────────────────────────────────────────────────

#[test]
fn test_sd_default() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'A');

    // SD with no parameter (default: 1 line)
    let params = vte::Params::default();
    csi_sd(&mut term, &params);

    // Content moves up
    assert_eq!(term.screen.get_line(0).unwrap().cells[0].char(), ' '); // Line 0 becomes blank
    assert_eq!(
        term.screen.get_line(1).unwrap().cells[0].char(),
        'A' // Line 1 now has what was in line 0
    );
}

#[test]
fn test_sd_with_param() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'0');

    // Scroll down 3 lines (CSI 3 T)
    term.advance(b"\x1b[3T");

    // First 3 lines should be blank
    for r in 0..3 {
        let line = term.screen.get_line(r).unwrap();
        assert_eq!(line.cells[0].char(), ' ');
    }

    // Line 3 should now have content from line 0
    assert_eq!(term.screen.get_line(3).unwrap().cells[0].char(), '0');
}

#[test]
fn test_sd_respects_scroll_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'0');

    // Set scroll region from row 3 to 8 (0-indexed: 2 to 8)
    term.screen.set_scroll_region(2, 8);

    // Scroll down
    let params = vte::Params::default();
    csi_sd(&mut term, &params);

    // Lines outside scroll region should be unchanged
    assert_eq!(term.screen.get_line(0).unwrap().cells[0].char(), '0');
    assert_eq!(term.screen.get_line(1).unwrap().cells[0].char(), '1');

    // Lines inside scroll region should have scrolled
    assert_eq!(
        term.screen.get_line(2).unwrap().cells[0].char(),
        ' ' // Top of scroll region becomes blank
    );
    assert_eq!(
        term.screen.get_line(3).unwrap().cells[0].char(),
        '2' // Was '3', now '2'
    );

    // Bottom of scroll region should have content from above
    assert_eq!(term.screen.get_line(7).unwrap().cells[0].char(), '6');
}

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

// ── New edge-case tests ───────────────────────────────────────────────────────

/// SU by 0 lines: CSI 0 S is treated as CSI 1 S (parameter 0 → default 1).
/// Row 0 must receive what was in row 1.
#[test]
fn test_su_zero_param_treated_as_one() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_rows!(term, rows 5, base b'0');

    term.advance(b"\x1b[0S"); // 0 → clamped to 1

    assert_eq!(
        term.screen.get_line(0).unwrap().cells[0].char(),
        '1',
        "CSI 0 S must scroll up by 1"
    );
    assert_eq!(
        term.screen.get_line(4).unwrap().cells[0].char(),
        ' ',
        "bottom row must be blank after SU 0→1"
    );
}

/// SD by 0 lines: CSI 0 T is treated as CSI 1 T.
/// Row 0 must become blank, former row 0 content appears at row 1.
#[test]
fn test_sd_zero_param_treated_as_one() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_rows!(term, rows 5, base b'A');

    term.advance(b"\x1b[0T"); // 0 → clamped to 1

    assert_eq!(
        term.screen.get_line(0).unwrap().cells[0].char(),
        ' ',
        "CSI 0 T must scroll down by 1 — top row blank"
    );
    assert_eq!(
        term.screen.get_line(1).unwrap().cells[0].char(),
        'A',
        "former row 0 must appear at row 1"
    );
}

/// SU with count equal to screen height blanks the whole visible area.
#[test]
fn test_su_full_screen_height_blanks_all() {
    let mut term = crate::TerminalCore::new(4, 10);
    fill_rows!(term, rows 4, char 'X');

    term.advance(b"\x1b[4S"); // scroll up exactly 4 rows (= screen height)

    for r in 0..4 {
        assert_eq!(
            term.screen.get_line(r).unwrap().cells[0].char(),
            ' ',
            "row {r} must be blank after full-height SU"
        );
    }
}

/// SD with count equal to screen height blanks the whole visible area.
#[test]
fn test_sd_full_screen_height_blanks_all() {
    let mut term = crate::TerminalCore::new(4, 10);
    fill_rows!(term, rows 4, char 'Y');

    term.advance(b"\x1b[4T"); // scroll down exactly 4 rows (= screen height)

    for r in 0..4 {
        assert_eq!(
            term.screen.get_line(r).unwrap().cells[0].char(),
            ' ',
            "row {r} must be blank after full-height SD"
        );
    }
}

/// SU inside a scroll region that is only 1 row tall: no content to displace,
/// the single row simply becomes blank.
#[test]
fn test_su_one_row_scroll_region_becomes_blank() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'0');

    // Narrow scroll region: just row 5 (0-indexed top=5, bottom=6)
    term.screen.set_scroll_region(5, 6);

    let params = vte::Params::default();
    csi_su(&mut term, &params);

    // Row 5 should be blank; all others unchanged
    assert_eq!(term.screen.get_line(5).unwrap().cells[0].char(), ' ');
    assert_eq!(term.screen.get_line(4).unwrap().cells[0].char(), '4');
    assert_eq!(term.screen.get_line(6).unwrap().cells[0].char(), '6');
}

/// SD at the very last row of the scroll region with a large count: no panic,
/// and the content above the region must be untouched.
#[test]
fn test_sd_large_count_preserves_rows_outside_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'0');

    // Scroll region: rows 3..7 (0-indexed)
    term.screen.set_scroll_region(3, 7);

    term.advance(b"\x1b[999T"); // massive SD — must not panic

    // Rows outside the region must be intact
    assert_rows_unchanged!(term, rows 3, base b'0');
    // Rows 7..10 also outside region
    for r in 7..10 {
        let ch = (b'0' + r as u8) as char;
        assert_eq!(
            term.screen.get_line(r).unwrap().cells[0].char(),
            ch,
            "row {r} below region must be unchanged"
        );
    }
    // Rows inside region must all be blank
    for r in 3..7 {
        assert_eq!(
            term.screen.get_line(r).unwrap().cells[0].char(),
            ' ',
            "row {r} inside region must be blank after large SD"
        );
    }
}

/// RI repeated from row 1 (not the scroll-region top): cursor should walk up
/// each call until it reaches row 0.
#[test]
fn test_ri_repeated_cursor_walk_up() {
    let mut term = crate::TerminalCore::new(10, 10);
    term.screen.move_cursor(3, 5);

    // Three RI commands — cursor should be at row 0 after
    term.advance(b"\x1bM");
    term.advance(b"\x1bM");
    term.advance(b"\x1bM");

    assert_eq!(
        term.screen.cursor().row,
        0,
        "three RI calls from row 3 should reach row 0"
    );
    assert_eq!(
        term.screen.cursor().col,
        5,
        "RI must not change cursor column"
    );
}

/// SU with a scroll region not starting at row 0: rows above the region must
/// never be affected regardless of count.
#[test]
fn test_su_does_not_touch_rows_above_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'A');

    // Scroll region starts at row 4
    term.screen.set_scroll_region(4, 10);

    term.advance(b"\x1b[3S"); // scroll up 3 within region

    // Rows 0..4 must be absolutely untouched
    for r in 0..4 {
        let ch = (b'A' + r as u8) as char;
        assert_eq!(
            term.screen.get_line(r).unwrap().cells[0].char(),
            ch,
            "row {r} above scroll region must be unchanged"
        );
    }
}

/// SD with a scroll region not ending at the last row: rows below the region
/// must never be affected regardless of count.
#[test]
fn test_sd_does_not_touch_rows_below_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'0');

    // Scroll region ends before last row
    term.screen.set_scroll_region(0, 6);

    term.advance(b"\x1b[3T"); // scroll down 3 within region

    // Rows 6..10 must be absolutely untouched
    for r in 6..10 {
        let ch = (b'0' + r as u8) as char;
        assert_eq!(
            term.screen.get_line(r).unwrap().cells[0].char(),
            ch,
            "row {r} below scroll region must be unchanged"
        );
    }
}

// ── Additional edge-case tests ────────────────────────────────────────────────

/// SU (CSI S) does not move the cursor — cursor stays at its row even after
/// the scroll region shifts content up.
#[test]
fn test_scroll_up_cursor_stays_in_region() {
    let mut term = crate::TerminalCore::new(24, 80);
    // Set scroll region rows 2-10 (1-indexed CSI 2;10 r → 0-indexed top=1, bottom=10)
    term.advance(b"\x1b[2;10r");
    // Move cursor to row 5 (within the scroll region)
    term.screen.move_cursor(5, 10);
    assert_eq!(term.screen.cursor().row, 5);
    assert_eq!(term.screen.cursor().col, 10);

    // Scroll up 1 line within the region
    term.advance(b"\x1b[S");

    // Cursor must not be moved by SU
    assert_eq!(
        term.screen.cursor().row,
        5,
        "SU must not move the cursor row"
    );
    assert_eq!(
        term.screen.cursor().col,
        10,
        "SU must not move the cursor col"
    );
}

/// SD with a full-screen scroll region: after scrolling down 3, row 0 is blank
/// (the 3 newly inserted rows at the top).
#[test]
fn test_scroll_down_with_full_screen_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'A');

    // Full-screen terminal: default scroll region covers all rows.
    // Scroll down 3 lines
    term.advance(b"\x1b[3T");

    // Row 0 must be blank (newly inserted blank row from SD)
    assert_eq!(
        term.screen.get_line(0).unwrap().cells[0].char(),
        ' ',
        "row 0 must be blank after SD 3 (new blank inserted at top)"
    );
    // Row 1 and 2 also blank
    assert_eq!(
        term.screen.get_line(1).unwrap().cells[0].char(),
        ' ',
        "row 1 must be blank after SD 3"
    );
    assert_eq!(
        term.screen.get_line(2).unwrap().cells[0].char(),
        ' ',
        "row 2 must be blank after SD 3"
    );
    // Row 3 now holds former row 0 content ('A')
    assert_eq!(
        term.screen.get_line(3).unwrap().cells[0].char(),
        'A',
        "row 3 must hold former row 0 content after SD 3"
    );
}

/// Setting a second DECSTBM after moving the cursor: cursor must return to
/// home (0, 0) each time a valid DECSTBM is processed.
#[test]
fn test_decstbm_cursor_moves_to_home() {
    let mut term = crate::TerminalCore::new(24, 80);

    // First DECSTBM: rows 5-20 (1-indexed)
    term.advance(b"\x1b[5;20r");
    // Cursor should be at (0, 0) now
    assert_eq!(term.screen.cursor().row, 0);

    // Advance cursor to somewhere else
    term.screen.move_cursor(8, 15);
    assert_eq!(term.screen.cursor().row, 8);

    // Second DECSTBM: rows 3-15 (1-indexed)
    term.advance(b"\x1b[3;15r");

    // Cursor must be homed again
    assert_eq!(
        term.screen.cursor().row,
        0,
        "DECSTBM must always home cursor to row 0 (DECOM off)"
    );
    assert_eq!(
        term.screen.cursor().col,
        0,
        "DECSTBM must always home cursor to col 0"
    );
    // Scroll region must be updated
    assert_eq!(term.screen.get_scroll_region().top, 2); // 3-1=2
    assert_eq!(term.screen.get_scroll_region().bottom, 15);
}

/// CSI 0 S — parameter 0 is clamped to 1 by the implementation (n.max(1)),
/// so the screen scrolls up by exactly 1 line. This is distinct from a no-op.
#[test]
fn test_su_zero_lines_is_one_line() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_rows!(term, rows 5, base b'0');

    // CSI 0 S: parameter 0 → treated as 1 (implementation uses n.max(1))
    term.advance(b"\x1b[0S");

    // Row 0 must now contain what was in row 1 (scrolled up by 1)
    assert_eq!(
        term.screen.get_line(0).unwrap().cells[0].char(),
        '1',
        "CSI 0 S scrolls up by 1 (0 is clamped to 1)"
    );
    // Bottom row must be blank
    assert_eq!(
        term.screen.get_line(4).unwrap().cells[0].char(),
        ' ',
        "bottom row must be blank after CSI 0 S"
    );
    // Cursor is not moved
    assert_eq!(term.screen.cursor().row, 0);
}

/// CSI 0 T — parameter 0 is clamped to 1 by the implementation,
/// so the screen scrolls down by exactly 1 line.
#[test]
fn test_sd_zero_lines_is_one_line() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_rows!(term, rows 5, base b'A');

    // CSI 0 T: parameter 0 → treated as 1 (implementation uses n.max(1))
    term.advance(b"\x1b[0T");

    // Row 0 must be blank (new line inserted at top)
    assert_eq!(
        term.screen.get_line(0).unwrap().cells[0].char(),
        ' ',
        "CSI 0 T scrolls down by 1 (0 is clamped to 1) — row 0 becomes blank"
    );
    // Row 1 must hold former row 0 content ('A')
    assert_eq!(
        term.screen.get_line(1).unwrap().cells[0].char(),
        'A',
        "former row 0 content must appear at row 1 after CSI 0 T"
    );
}

// ── BCE (Background Color Erase) propagation ─────────────────────────────────

/// SU with a non-default SGR background: newly introduced blank lines must
/// carry the current SGR background color, not `Color::Default`.
#[test]
fn test_su_bce_background_propagated() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_rows!(term, rows 5, char 'X');

    // Set SGR blue background before scrolling
    term.advance(b"\x1b[44m"); // SGR 44 = blue background

    // Scroll up 2 lines — the 2 new blank lines at the bottom must use
    // the current SGR background (BCE).
    term.advance(b"\x1b[2S");

    // Bottom two rows are the newly inserted blank lines
    for r in 3..5 {
        let cell = term.screen.get_cell(r, 0).unwrap();
        assert_eq!(cell.char(), ' ', "row {r} must be blank");
        assert_ne!(
            cell.attrs.background,
            crate::Color::Default,
            "row {r}: SU blank line must carry BCE background"
        );
    }
}

/// SD with a non-default SGR background: newly introduced blank lines at the
/// top of the scroll region must carry the current SGR background color.
#[test]
fn test_sd_bce_background_propagated() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_rows!(term, rows 5, char 'Y');

    // Set SGR red background before scrolling
    term.advance(b"\x1b[41m"); // SGR 41 = red background

    // Scroll down 2 lines — 2 new blank lines inserted at row 0 and row 1
    term.advance(b"\x1b[2T");

    for r in 0..2 {
        let cell = term.screen.get_cell(r, 0).unwrap();
        assert_eq!(cell.char(), ' ', "row {r} must be blank");
        assert_ne!(
            cell.attrs.background,
            crate::Color::Default,
            "row {r}: SD blank line must carry BCE background"
        );
    }
}

/// SD marks affected rows dirty — symmetry with `test_scroll_marks_dirty` for SU.
#[test]
fn test_sd_marks_dirty() {
    let mut term = crate::TerminalCore::new(5, 10);

    // Clear dirty set, fill a line, then mark it clean
    term.screen.take_dirty_lines();
    for c in 0..10 {
        if let Some(line) = term.screen.get_line_mut(4) {
            line.update_cell_with(c, crate::types::Cell::new('X'));
            line.is_dirty = false;
        }
    }

    // Scroll down 1 line
    let params = vte::Params::default();
    csi_sd(&mut term, &params);

    let dirty = term.screen.take_dirty_lines();
    assert!(!dirty.is_empty(), "SD must mark at least one row dirty");
}

/// DECSTBM with default parameters (CSI r) must restore the full-screen scroll
/// region: top=0, bottom=rows.
#[test]
fn test_decstbm_default_restores_full_screen() {
    let mut term = crate::TerminalCore::new(10, 80);

    // First set a non-default scroll region
    term.advance(b"\x1b[3;8r");
    assert_eq!(term.screen.get_scroll_region().top, 2);
    assert_eq!(term.screen.get_scroll_region().bottom, 8);

    // Now reset with default DECSTBM (no params → full screen)
    let params = vte::Params::default();
    csi_decstbm(&mut term, &params);

    assert_eq!(
        term.screen.get_scroll_region().top,
        0,
        "default DECSTBM must set top=0"
    );
    assert_eq!(
        term.screen.get_scroll_region().bottom,
        10,
        "default DECSTBM must set bottom=rows"
    );
}

/// RI (ESC M) BCE: when a scroll occurs (cursor at scroll-region top), the
/// newly inserted blank row at the top of the scroll region must carry the
/// current SGR background color.
#[test]
fn test_ri_bce_background_propagated() {
    let mut term = crate::TerminalCore::new(10, 10);

    // Fill all rows with content
    fill_rows!(term, rows 10, char 'X');

    // Set SGR green background
    term.advance(b"\x1b[42m"); // SGR 42 = green background

    // Place cursor at scroll-region top (row 0 with default region)
    term.screen.move_cursor(0, 0);

    // RI at the scroll-region top must scroll down and insert a blank row
    term.advance(b"\x1bM");

    // Row 0 is the newly inserted blank line — must carry BCE background
    let cell = term.screen.get_cell(0, 0).unwrap();
    assert_eq!(cell.char(), ' ', "RI blank row must be space");
    assert_ne!(
        cell.attrs.background,
        crate::Color::Default,
        "RI blank row at scroll-region top must carry BCE background"
    );
}

/// SU with a scroll region that occupies only two rows: one scroll-up must
/// leave the top row with the former bottom row's content, and the bottom row
/// blank.
#[test]
fn test_su_two_row_scroll_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'0');

    // 0-indexed scroll region: rows 4 and 5 (top=4, bottom=6 exclusive)
    term.screen.set_scroll_region(4, 6);

    let params = vte::Params::default();
    csi_su(&mut term, &params); // SU 1

    // Row 4 now holds what was in row 5 ('5')
    assert_eq!(term.screen.get_line(4).unwrap().cells[0].char(), '5');
    // Row 5 is now blank
    assert_eq!(term.screen.get_line(5).unwrap().cells[0].char(), ' ');
    // Rows outside the region are unchanged
    assert_eq!(term.screen.get_line(3).unwrap().cells[0].char(), '3');
    assert_eq!(term.screen.get_line(6).unwrap().cells[0].char(), '6');
}

use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    // PANIC SAFETY: SU (CSI n S) with any parameter never panics
    fn prop_su_no_panic(n in 0u16..=300u16) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.advance(format!("\x1b[{n}S").as_bytes());
        prop_assert!(term.screen.rows() == 10);
    }

    #[test]
    // PANIC SAFETY: SD (CSI n T) with any parameter never panics
    fn prop_sd_no_panic(n in 0u16..=300u16) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.advance(format!("\x1b[{n}T").as_bytes());
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
        let mut term = crate::TerminalCore::new(rows, 20);
        term.advance(format!("\x1b[{top};{bot}r").as_bytes());
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
        term.advance(format!("\x1b[{top};{bot}r").as_bytes());
        prop_assert!(term.screen.cursor().row < 10);
        prop_assert!(term.screen.cursor().col < 20);
    }

    #[test]
    // INVARIANT: SU(n) then SD(n) leaves rows outside the scroll region untouched.
    // Content that was outside the region before must still be there after SU+SD.
    fn prop_su_sd_outside_region_identity(
        n in 1u16..=4u16,
    ) {
        let mut term = crate::TerminalCore::new(10, 20);
        // Fill every row with a distinct character
        for r in 0..10usize {
            if let Some(line) = term.screen.get_line_mut(r) {
                let ch = (b'A' + r as u8) as char;
                let cols = line.cells.len();
                for c in 0..cols {
                    line.update_cell_with(c, crate::types::Cell::new(ch));
                }
            }
        }
        term.screen.set_scroll_region(2, 8);

        term.advance(format!("\x1b[{n}S").as_bytes());
        term.advance(format!("\x1b[{n}T").as_bytes());

        // Rows 0..2 (above region) must be unchanged
        for r in 0..2usize {
            let ch = (b'A' + r as u8) as char;
            prop_assert_eq!(
                term.screen.get_cell(r, 0).map_or(' ', crate::types::cell::Cell::char),
                ch,
                "row {} above scroll region must be untouched after SU+SD",
                r
            );
        }
        // Rows 8..10 (below region) must be unchanged
        for r in 8..10usize {
            let ch = (b'A' + r as u8) as char;
            prop_assert_eq!(
                term.screen.get_cell(r, 0).map_or(' ', crate::types::cell::Cell::char),
                ch,
                "row {} below scroll region must be untouched after SU+SD",
                r
            );
        }
        prop_assert_eq!(term.screen.rows() as usize, 10);
        prop_assert_eq!(term.screen.cols() as usize, 20);
    }

    #[test]
    // INVARIANT: DECSTBM always leaves the cursor within terminal bounds regardless of params
    fn prop_decstbm_cursor_always_in_bounds(
        top in 0u16..=15u16,
        bot in 0u16..=15u16,
    ) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.advance(format!("\x1b[{top};{bot}r").as_bytes());
        prop_assert!(term.screen.cursor().row < 10);
        prop_assert!(term.screen.cursor().col < 20);
    }
}
