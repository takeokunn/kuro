//! Property-based and example-based tests for `insert_delete` parsing.
//!
//! Module under test: `parser/insert_delete.rs`
//! Tier: T3 — `ProptestConfig::with_cases(256)`

// Test helpers convert between usize/u16/i64 for grid coordinates; values are
// bounded by terminal dimensions (≤ 65535 rows/cols) so truncation is safe.
#![expect(clippy::cast_possible_truncation, reason = "test coordinate casts bounded by terminal dimensions (≤ 65535)")]

use super::*;

/// Fill every cell in `row` with character `c`
fn fill_line(term: &mut crate::TerminalCore, row: usize, c: char) {
    let cols = term.screen.cols() as usize;
    if let Some(line) = term.screen.get_line_mut(row) {
        for col in 0..cols {
            line.update_cell_with(col, crate::types::Cell::new(c));
        }
    }
}

/// Return the character at (row, col), or ' ' if out of bounds
fn char_at(term: &crate::TerminalCore, row: usize, col: usize) -> char {
    term.screen
        .get_cell(row, col)
        .map_or(' ', crate::types::cell::Cell::char)
}

// ── IL (Insert Lines) ──────────────────────────────────────────────────

#[test]
fn test_il_basic() {
    let mut term = crate::TerminalCore::new(10, 10);
    for r in 0..5 {
        fill_line(&mut term, r, (b'A' + r as u8) as char);
    }
    term.screen.move_cursor(2, 0);

    let params = vte::Params::default();
    csi_il(&mut term, &params); // IL 1

    assert_eq!(char_at(&term, 2, 0), ' '); // newly inserted blank
    assert_eq!(char_at(&term, 3, 0), 'C'); // original row 2 shifted down
    assert_eq!(char_at(&term, 4, 0), 'D'); // original row 3 shifted down
}

#[test]
fn test_il_default_param_is_one() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'A');
    fill_line(&mut term, 1, 'B');
    term.screen.move_cursor(0, 0);

    let params = vte::Params::default();
    csi_il(&mut term, &params);

    assert_eq!(char_at(&term, 0, 0), ' '); // new blank
    assert_eq!(char_at(&term, 1, 0), 'A'); // shifted
    assert_eq!(char_at(&term, 2, 0), 'B'); // shifted
}

#[test]
fn test_il_respects_scroll_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    for r in 0..10 {
        fill_line(&mut term, r, (b'0' + r as u8) as char);
    }
    // scroll region rows [2, 7)
    term.screen.set_scroll_region(2, 7);
    term.screen.move_cursor(3, 0);

    term.advance(b"\x1b[2L"); // IL 2

    // Above scroll region: untouched
    assert_eq!(char_at(&term, 0, 0), '0');
    assert_eq!(char_at(&term, 1, 0), '1');
    assert_eq!(char_at(&term, 2, 0), '2'); // cursor was below this row
                                           // Two blank lines inserted at row 3
    assert_eq!(char_at(&term, 3, 0), ' ');
    assert_eq!(char_at(&term, 4, 0), ' ');
    // Original rows 3,4 shifted to 5,6
    assert_eq!(char_at(&term, 5, 0), '3');
    assert_eq!(char_at(&term, 6, 0), '4');
    // Below scroll region: untouched
    assert_eq!(char_at(&term, 7, 0), '7');
    assert_eq!(char_at(&term, 9, 0), '9');
}

#[test]
fn test_il_noop_when_cursor_above_scroll_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    for r in 0..10 {
        fill_line(&mut term, r, (b'0' + r as u8) as char);
    }
    term.screen.set_scroll_region(3, 8);
    term.screen.move_cursor(1, 0); // above top=3

    let params = vte::Params::default();
    csi_il(&mut term, &params);

    for r in 0..10 {
        assert_eq!(char_at(&term, r, 0), (b'0' + r as u8) as char);
    }
}

#[test]
fn test_il_noop_when_cursor_below_scroll_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    for r in 0..10 {
        fill_line(&mut term, r, (b'0' + r as u8) as char);
    }
    term.screen.set_scroll_region(2, 6);
    term.screen.move_cursor(8, 0); // at or below bottom=6

    let params = vte::Params::default();
    csi_il(&mut term, &params);

    for r in 0..10 {
        assert_eq!(char_at(&term, r, 0), (b'0' + r as u8) as char);
    }
}

#[test]
fn test_il_dirty_tracking() {
    let mut term = crate::TerminalCore::new(5, 10);
    term.screen.take_dirty_lines();
    term.screen.move_cursor(1, 0);

    let params = vte::Params::default();
    csi_il(&mut term, &params);

    let dirty = term.screen.take_dirty_lines();
    assert!(dirty.contains(&1));
    assert!(dirty.contains(&2));
    assert!(dirty.contains(&4));
}

#[test]
fn test_il_integration_via_advance() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_line(&mut term, 0, 'A');
    fill_line(&mut term, 1, 'B');
    fill_line(&mut term, 2, 'C');
    term.screen.move_cursor(1, 0);

    term.advance(b"\x1b[L"); // CSI L (default 1)

    assert_eq!(char_at(&term, 1, 0), ' ');
    assert_eq!(char_at(&term, 2, 0), 'B');
    assert_eq!(char_at(&term, 3, 0), 'C');
}

// ── DL (Delete Lines) ──────────────────────────────────────────────────

#[test]
fn test_dl_basic() {
    let mut term = crate::TerminalCore::new(10, 10);
    for r in 0..5 {
        fill_line(&mut term, r, (b'A' + r as u8) as char);
    }
    term.screen.move_cursor(1, 0);

    let params = vte::Params::default();
    csi_dl(&mut term, &params); // DL 1

    // 'B' (row 1) is deleted; 'C' shifts up
    assert_eq!(char_at(&term, 1, 0), 'C');
    assert_eq!(char_at(&term, 2, 0), 'D');
    assert_eq!(char_at(&term, 9, 0), ' '); // blank filled at bottom
}

#[test]
fn test_dl_respects_scroll_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    for r in 0..10 {
        fill_line(&mut term, r, (b'0' + r as u8) as char);
    }
    // scroll region rows [2, 7)
    term.screen.set_scroll_region(2, 7);
    term.screen.move_cursor(3, 0);

    term.advance(b"\x1b[2M"); // DL 2

    // Above region: untouched
    assert_eq!(char_at(&term, 0, 0), '0');
    assert_eq!(char_at(&term, 1, 0), '1');
    assert_eq!(char_at(&term, 2, 0), '2');
    // Rows 3,4 deleted; original row 5 shifts to 3
    assert_eq!(char_at(&term, 3, 0), '5');
    assert_eq!(char_at(&term, 4, 0), '6');
    // Bottom of region filled with blanks
    assert_eq!(char_at(&term, 5, 0), ' ');
    assert_eq!(char_at(&term, 6, 0), ' ');
    // Below region: untouched
    assert_eq!(char_at(&term, 7, 0), '7');
}

#[test]
fn test_dl_noop_when_cursor_above_scroll_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    for r in 0..10 {
        fill_line(&mut term, r, (b'0' + r as u8) as char);
    }
    term.screen.set_scroll_region(3, 8);
    term.screen.move_cursor(1, 0); // above top=3

    let params = vte::Params::default();
    csi_dl(&mut term, &params);

    for r in 0..10 {
        assert_eq!(char_at(&term, r, 0), (b'0' + r as u8) as char);
    }
}

#[test]
fn test_dl_noop_when_cursor_below_scroll_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    for r in 0..10 {
        fill_line(&mut term, r, (b'0' + r as u8) as char);
    }
    term.screen.set_scroll_region(2, 6);
    term.screen.move_cursor(8, 0); // at or below bottom=6

    let params = vte::Params::default();
    csi_dl(&mut term, &params);

    for r in 0..10 {
        assert_eq!(char_at(&term, r, 0), (b'0' + r as u8) as char);
    }
}

#[test]
fn test_dl_dirty_tracking() {
    let mut term = crate::TerminalCore::new(5, 10);
    term.screen.take_dirty_lines();
    term.screen.move_cursor(1, 0);

    let params = vte::Params::default();
    csi_dl(&mut term, &params);

    let dirty = term.screen.take_dirty_lines();
    assert!(dirty.contains(&1));
    assert!(dirty.contains(&4));
}

// ── IL/DL zero-count and large-count guard tests ──────────────────────

#[test]
fn test_il_zero_count_is_noop() {
    // IL with explicit 0 is promoted to 1 by get_param() (.max(1)).
    // But CSI 0 L actually inserts 1 line (the standard "0 = default = 1" rule).
    // Verify it inserts exactly one blank line (not zero, not a panic).
    let mut term = crate::TerminalCore::new(10, 10);
    fill_line(&mut term, 0, 'A');
    fill_line(&mut term, 1, 'B');
    term.screen.move_cursor(0, 0);

    term.advance(b"\x1b[0L"); // CSI 0 L — treated as 1

    // One blank line must have been inserted at row 0; 'A' shifts to row 1.
    assert_eq!(char_at(&term, 0, 0), ' ');
    assert_eq!(char_at(&term, 1, 0), 'A');
    assert_eq!(char_at(&term, 2, 0), 'B');
}

#[test]
fn test_dl_zero_count_is_noop() {
    // DL with explicit 0 → promoted to 1 by get_param().
    let mut term = crate::TerminalCore::new(10, 10);
    fill_line(&mut term, 0, 'A');
    fill_line(&mut term, 1, 'B');
    term.screen.move_cursor(0, 0);

    term.advance(b"\x1b[0M"); // CSI 0 M — treated as 1

    // One line deleted; 'B' shifts up to row 0.
    assert_eq!(char_at(&term, 0, 0), 'B');
    assert_eq!(char_at(&term, 9, 0), ' ');
}

#[test]
fn test_il_count_larger_than_remaining_rows_clamps() {
    // IL with count larger than (scroll_bottom - cursor_row) must clamp and not panic.
    let mut term = crate::TerminalCore::new(10, 10);
    for r in 0..10 {
        fill_line(&mut term, r, (b'0' + r as u8) as char);
    }
    // Cursor at row 7; default scroll region bottom = 10.
    // Remaining rows = 10 - 7 = 3; request 100 → clamped to 3.
    term.screen.move_cursor(7, 0);

    term.advance(b"\x1b[100L");

    // Rows 7..10 should all be blank; rows above are untouched.
    assert_eq!(char_at(&term, 6, 0), '6'); // untouched above
    assert_eq!(char_at(&term, 7, 0), ' ');
    assert_eq!(char_at(&term, 8, 0), ' ');
    assert_eq!(char_at(&term, 9, 0), ' ');
}

// ── clear_lines tests ──────────────────────────────────────────────────

#[test]
fn test_clear_lines_basic() {
    // clear_lines(start, end) should blank rows [start, end).
    let mut term = crate::TerminalCore::new(10, 10);
    for r in 0..10 {
        fill_line(&mut term, r, (b'A' + r as u8) as char);
    }

    term.screen.clear_lines(2, 5); // clear rows 2, 3, 4

    // Rows below and above the range are untouched.
    assert_eq!(char_at(&term, 1, 0), 'B');
    assert_eq!(char_at(&term, 2, 0), ' ');
    assert_eq!(char_at(&term, 3, 0), ' ');
    assert_eq!(char_at(&term, 4, 0), ' ');
    assert_eq!(char_at(&term, 5, 0), 'F');
}

#[test]
fn test_clear_lines_start_equals_end_is_noop() {
    // clear_lines(n, n) must be a no-op (empty range).
    let mut term = crate::TerminalCore::new(10, 10);
    for r in 0..10 {
        fill_line(&mut term, r, 'X');
    }

    term.screen.clear_lines(3, 3); // empty range

    // All rows must still have 'X'.
    for r in 0..10 {
        assert_eq!(char_at(&term, r, 0), 'X', "row {r} should be untouched");
    }
}

#[test]
fn test_clear_lines_start_greater_than_end_is_noop() {
    // clear_lines(5, 2) — start > end; must be a no-op (guarded by start < end check).
    let mut term = crate::TerminalCore::new(10, 10);
    for r in 0..10 {
        fill_line(&mut term, r, 'Z');
    }

    term.screen.clear_lines(5, 2); // inverted range

    for r in 0..10 {
        assert_eq!(char_at(&term, r, 0), 'Z', "row {r} should be untouched");
    }
}

// ── ICH (Insert Characters) ────────────────────────────────────────────

#[test]
fn test_ich_basic() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'A');
    term.screen.move_cursor(0, 2);

    let params = vte::Params::default();
    csi_ich(&mut term, &params); // ICH 1

    assert_eq!(char_at(&term, 0, 1), 'A'); // left of cursor: untouched
    assert_eq!(char_at(&term, 0, 2), ' '); // inserted blank
    assert_eq!(char_at(&term, 0, 3), 'A'); // original col 2 shifted right
    assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 10); // width preserved
}

#[test]
fn test_ich_clips_to_right_margin() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'A');
    term.screen.move_cursor(0, 8); // 2 cols from right margin

    term.advance(b"\x1b[5@"); // ICH 5: clamped to 2

    assert_eq!(char_at(&term, 0, 8), ' ');
    assert_eq!(char_at(&term, 0, 9), ' ');
    assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 10);
}

#[test]
fn test_ich_dirty_tracking() {
    let mut term = crate::TerminalCore::new(5, 10);
    term.screen.take_dirty_lines();
    term.screen.move_cursor(2, 3);

    term.advance(b"\x1b[@"); // ICH 1

    let dirty = term.screen.take_dirty_lines();
    assert!(dirty.contains(&2));
}

// ── DCH (Delete Characters) ────────────────────────────────────────────

#[test]
fn test_dch_basic() {
    let mut term = crate::TerminalCore::new(5, 10);
    // Fill row 0 with '0'..'9'
    if let Some(line) = term.screen.get_line_mut(0) {
        for (i, cell) in line.cells.iter_mut().enumerate() {
            cell.grapheme =
                compact_str::CompactString::new(((b'0' + i as u8) as char).to_string());
        }
    }
    term.screen.move_cursor(0, 2);

    let params = vte::Params::default();
    csi_dch(&mut term, &params); // DCH 1

    assert_eq!(char_at(&term, 0, 2), '3'); // '3' shifted left to col 2
    assert_eq!(char_at(&term, 0, 9), ' '); // blank fills right end
    assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 10);
}

#[test]
fn test_dch_clips_to_right_margin() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'A');
    term.screen.move_cursor(0, 8); // 2 cols from right

    term.advance(b"\x1b[10P"); // DCH 10: clamped to 2

    assert_eq!(char_at(&term, 0, 8), ' ');
    assert_eq!(char_at(&term, 0, 9), ' ');
    assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 10);
}

#[test]
fn test_dch_dirty_tracking() {
    let mut term = crate::TerminalCore::new(5, 10);
    term.screen.take_dirty_lines();
    term.screen.move_cursor(3, 1);

    term.advance(b"\x1b[P"); // DCH 1

    let dirty = term.screen.take_dirty_lines();
    assert!(dirty.contains(&3));
}

// ── ECH (Erase Characters) ─────────────────────────────────────────────

#[test]
fn test_ech_basic() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'A');
    term.screen.move_cursor(0, 3);

    let params = vte::Params::default();
    csi_ech(&mut term, &params); // ECH 1

    assert_eq!(char_at(&term, 0, 2), 'A'); // left: untouched
    assert_eq!(char_at(&term, 0, 3), ' '); // erased
    assert_eq!(char_at(&term, 0, 4), 'A'); // right: untouched
                                           // Cursor must NOT move
    assert_eq!(term.screen.cursor().col, 3);
}

#[test]
fn test_ech_clips_to_right_margin() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'A');
    term.screen.move_cursor(0, 8);

    term.advance(b"\x1b[20X"); // ECH 20: clamped to cols 8-9

    assert_eq!(char_at(&term, 0, 7), 'A'); // left: untouched
    assert_eq!(char_at(&term, 0, 8), ' '); // erased
    assert_eq!(char_at(&term, 0, 9), ' '); // erased
}

#[test]
fn test_ech_uses_sgr_background() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'A');
    term.advance(b"\x1b[41m"); // SGR 41: red background
    term.screen.move_cursor(0, 2);

    term.advance(b"\x1b[3X"); // ECH 3

    let cell = term.screen.get_cell(0, 2).unwrap();
    assert_eq!(cell.char(), ' ');
    // Erased cell must carry the current SGR background (not the default)
    assert_ne!(cell.attrs.background, crate::Color::Default);
}

#[test]
fn test_ech_dirty_tracking() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 1, 'A');
    term.screen.take_dirty_lines();
    term.screen.move_cursor(1, 0);

    term.advance(b"\x1b[X"); // ECH 1

    let dirty = term.screen.take_dirty_lines();
    assert!(dirty.contains(&1));
}

use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    // PANIC SAFETY: IL (CSI n L) never panics; row count preserved
    fn prop_il_no_panic(n in 0u16..=100u16, row in 0usize..10usize) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.screen.move_cursor(row, 0);
        term.advance(format!("\x1b[{n}L").as_bytes());
        prop_assert_eq!(term.screen.rows() as usize, 10, "rows must be unchanged after IL");
    }

    #[test]
    // PANIC SAFETY: DL (CSI n M) never panics; row count preserved
    fn prop_dl_no_panic(n in 0u16..=100u16, row in 0usize..10usize) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.screen.move_cursor(row, 0);
        term.advance(format!("\x1b[{n}M").as_bytes());
        prop_assert_eq!(term.screen.rows() as usize, 10, "rows must be unchanged after DL");
    }

    #[test]
    // PANIC SAFETY: ICH (CSI n @) never panics; line width preserved
    fn prop_ich_no_panic(n in 0u16..=100u16, col in 0usize..20usize) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.screen.move_cursor(0, col);
        term.advance(format!("\x1b[{n}@").as_bytes());
        prop_assert_eq!(
            term.screen.get_line(0).unwrap().cells.len(), 20,
            "line width must be preserved after ICH"
        );
    }

    #[test]
    // PANIC SAFETY: DCH (CSI n P) never panics; line width preserved
    fn prop_dch_no_panic(n in 0u16..=100u16, col in 0usize..20usize) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.screen.move_cursor(0, col);
        term.advance(format!("\x1b[{n}P").as_bytes());
        prop_assert_eq!(
            term.screen.get_line(0).unwrap().cells.len(), 20,
            "line width must be preserved after DCH"
        );
    }

    #[test]
    // INVARIANT: IL + DL cancel out — row count stays the same
    fn prop_il_dl_preserves_row_count(n in 1u16..=8u16) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.advance(format!("\x1b[{n}L").as_bytes());
        term.advance(format!("\x1b[{n}M").as_bytes());
        prop_assert_eq!(term.screen.rows() as usize, 10);
    }
}
