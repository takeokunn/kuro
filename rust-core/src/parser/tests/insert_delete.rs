//! Property-based and example-based tests for `insert_delete` parsing.
//!
//! Module under test: `parser/insert_delete.rs`
//! Tier: T3 — `ProptestConfig::with_cases(256)`

// Test helpers convert between usize/u16/i64 for grid coordinates; values are
// bounded by terminal dimensions (≤ 65535 rows/cols) so truncation is safe.
#![expect(
    clippy::cast_possible_truncation,
    reason = "test coordinate casts bounded by terminal dimensions (≤ 65535)"
)]
// These macros are defined here for future test invocations; suppress the
// unused_macros lint rather than removing the definitions prematurely.
#![allow(unused_macros)]

use super::*;

// ── Helpers ───────────────────────────────────────────────────────────────────

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

/// Fill rows 0..`n` with sequential characters starting from `base`:
/// row 0 → base, row 1 → base+1, etc.
macro_rules! fill_rows_seq {
    ($term:expr, rows $n:expr, base $base:expr) => {{
        for r in 0..$n {
            fill_line(&mut $term, r, ($base as u8 + r as u8) as char);
        }
    }};
}

/// Assert that rows 0..`n` still hold the characters written by
/// `fill_rows_seq!(term, rows n, base BASE)`.  Use after noop operations.
macro_rules! assert_rows_seq_unchanged {
    ($term:expr, rows $n:expr, base $base:expr) => {{
        for r in 0..$n {
            let expected = ($base as u8 + r as u8) as char;
            assert_eq!(
                char_at(&$term, r, 0),
                expected,
                "row {r} should be unchanged (expected {expected:?})"
            );
        }
    }};
}

/// Generate a pair of noop tests (one for IL, one for DL) for a cursor placed
/// either above or below the active scroll region.
///
/// Syntax:
/// ```text
/// test_noop_outside_scroll_region!(
///     il_name, dl_name,
///     region (top, bottom),
///     cursor row,
/// )
/// ```
macro_rules! test_noop_outside_scroll_region {
    (
        $il_name:ident, $dl_name:ident,
        region ($top:expr, $bottom:expr),
        cursor $cursor_row:expr,
    ) => {
        #[test]
        fn $il_name() {
            let mut term = crate::TerminalCore::new(10, 10);
            fill_rows_seq!(term, rows 10, base b'0');
            term.screen.set_scroll_region($top, $bottom);
            term.screen.move_cursor($cursor_row, 0);
            let params = vte::Params::default();
            csi_il(&mut term, &params);
            assert_rows_seq_unchanged!(term, rows 10, base b'0');
        }

        #[test]
        fn $dl_name() {
            let mut term = crate::TerminalCore::new(10, 10);
            fill_rows_seq!(term, rows 10, base b'0');
            term.screen.set_scroll_region($top, $bottom);
            term.screen.move_cursor($cursor_row, 0);
            let params = vte::Params::default();
            csi_dl(&mut term, &params);
            assert_rows_seq_unchanged!(term, rows 10, base b'0');
        }
    };
}

/// Generate a dirty-tracking test for either IL or DL.
///
/// Syntax:
/// ```text
/// test_dirty_tracking!(fn_name, csi_fn, rows, cursor_row, expected_dirty: [r1, r2, ...])
/// ```
macro_rules! test_dirty_tracking {
    ($name:ident, $csi_fn:ident, rows $rows:expr, cursor $crow:expr, dirty [$($d:expr),+]) => {
        #[test]
        fn $name() {
            let mut term = crate::TerminalCore::new($rows, 10);
            term.screen.take_dirty_lines();
            term.screen.move_cursor($crow, 0);
            let params = vte::Params::default();
            $csi_fn(&mut term, &params);
            let dirty = term.screen.take_dirty_lines();
            $(assert!(dirty.contains(&$d), "expected dirty row {}", $d);)+
        }
    };
}

/// Generate a pair of large-count-clamp tests (one for IL, one for DL) that
/// verify: when the count exceeds the remaining rows in the region, the
/// operation clamps gracefully (no panic) and blanks exactly the rows from the
/// cursor to the region bottom.
///
/// Syntax:
/// ```text
/// test_line_op_large_count!(
///     il_name, dl_name,
///     rows ROWS, cursor CURSOR, seq_char SEQ_CHAR,
///     untouched_above ROW_ABOVE,
///     blanked_range (BLANK_START, BLANK_END),
/// )
/// ```
macro_rules! test_line_op_large_count {
    (
        $il_name:ident, $dl_name:ident,
        rows $rows:expr, cursor $cursor:expr, seq_char $base:expr,
        untouched_above $above:expr,
        blanked_range ($blank_start:expr, $blank_end:expr),
    ) => {
        #[test]
        fn $il_name() {
            let mut term = crate::TerminalCore::new($rows, 10);
            fill_rows_seq!(term, rows $rows, base $base);
            term.screen.move_cursor($cursor, 0);
            term.advance(b"\x1b[100L"); // IL 100 — far more than remaining rows
            // Row above cursor must be untouched
            assert_eq!(char_at(&term, $above, 0), ($base as u8 + $above as u8) as char);
            // Rows from cursor to region bottom must all be blank
            for r in $blank_start..$blank_end {
                assert_eq!(char_at(&term, r, 0), ' ', "row {r} must be blank after IL 100");
            }
        }

        #[test]
        fn $dl_name() {
            let mut term = crate::TerminalCore::new($rows, 10);
            fill_rows_seq!(term, rows $rows, base $base);
            term.screen.move_cursor($cursor, 0);
            term.advance(b"\x1b[100M"); // DL 100 — far more than remaining rows
            // Row above cursor must be untouched
            assert_eq!(char_at(&term, $above, 0), ($base as u8 + $above as u8) as char);
            // Rows from cursor to region bottom must all be blank
            for r in $blank_start..$blank_end {
                assert_eq!(char_at(&term, r, 0), ' ', "row {r} must be blank after DL 100");
            }
        }
    };
}

/// Generate a pair of right-margin clip tests (one for ICH, one for DCH) that
/// verify: when count would exceed the right margin from the cursor position,
/// the operation clamps and the line width is preserved.
///
/// Syntax:
/// ```text
/// test_char_op_clips!(
///     ich_name, dch_name,
///     cols COLS, cursor_col CURSOR_COL,
///     ich_seq BICH, dch_seq BDCH,
///     blanked_cols [C1, C2, ...],
/// )
/// ```
macro_rules! test_char_op_clips {
    (
        $ich_name:ident, $dch_name:ident,
        cols $cols:expr, cursor_col $cursor:expr,
        ich_seq $ich_seq:expr, dch_seq $dch_seq:expr,
        blanked_cols [$($bc:expr),+],
    ) => {
        #[test]
        fn $ich_name() {
            let mut term = crate::TerminalCore::new(5, $cols);
            fill_line(&mut term, 0, 'A');
            term.screen.move_cursor(0, $cursor);
            term.advance($ich_seq);
            $(assert_eq!(char_at(&term, 0, $bc), ' ', "ICH: col {}", $bc);)+
            assert_eq!(term.screen.get_line(0).unwrap().cells.len(), $cols);
        }

        #[test]
        fn $dch_name() {
            let mut term = crate::TerminalCore::new(5, $cols);
            fill_line(&mut term, 0, 'A');
            term.screen.move_cursor(0, $cursor);
            term.advance($dch_seq);
            $(assert_eq!(char_at(&term, 0, $bc), ' ', "DCH: col {}", $bc);)+
            assert_eq!(term.screen.get_line(0).unwrap().cells.len(), $cols);
        }
    };
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
    fill_rows_seq!(term, rows 10, base b'0');
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

test_noop_outside_scroll_region!(
    test_il_noop_when_cursor_above_scroll_region,
    test_dl_noop_when_cursor_above_scroll_region,
    region (3, 8),
    cursor 1,
);

test_noop_outside_scroll_region!(
    test_il_noop_when_cursor_below_scroll_region,
    test_dl_noop_when_cursor_below_scroll_region,
    region (2, 6),
    cursor 8,
);

test_dirty_tracking!(
    test_il_dirty_tracking,
    csi_il,
    rows 5, cursor 1,
    dirty [1, 2, 4]
);

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
    fill_rows_seq!(term, rows 10, base b'0');
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

test_dirty_tracking!(
    test_dl_dirty_tracking,
    csi_dl,
    rows 5, cursor 1,
    dirty [1, 4]
);

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

// IL/DL large-count clamp: count > remaining rows must clamp, not panic.
// Cursor at row 7; default scroll region bottom = 10; remaining = 3.
test_line_op_large_count!(
    test_il_count_larger_than_remaining_rows_clamps,
    test_dl_count_larger_than_remaining_rows_clamps,
    rows 10, cursor 7, seq_char b'0',
    untouched_above 6,
    blanked_range (7, 10),
);

#[test]
fn test_ich_at_column_zero() {
    // ICH 1 at column 0 should insert a blank at col 0 and shift everything right.
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'A');
    term.screen.move_cursor(0, 0);

    term.advance(b"\x1b[@"); // ICH 1

    assert_eq!(char_at(&term, 0, 0), ' '); // inserted blank
    assert_eq!(char_at(&term, 0, 1), 'A'); // original col 0 shifted right
    assert_eq!(
        term.screen.get_line(0).unwrap().cells.len(),
        10,
        "line width must be preserved"
    );
}

#[test]
fn test_dch_at_last_column() {
    // DCH 1 at the last column should delete that cell and fill with blank at right end.
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'A');
    // Put a distinct char at the last col
    if let Some(line) = term.screen.get_line_mut(0) {
        line.update_cell_with(9, crate::types::Cell::new('Z'));
    }
    term.screen.move_cursor(0, 9); // last column

    term.advance(b"\x1b[P"); // DCH 1

    assert_eq!(char_at(&term, 0, 9), ' '); // deleted cell becomes blank
    assert_eq!(
        term.screen.get_line(0).unwrap().cells.len(),
        10,
        "line width must be preserved"
    );
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

// ICH/DCH clip to right margin: count exceeds remaining cols → blanks only the
// reachable cols, line width preserved.
// Cursor at col 8 on a 10-col terminal; 2 cols remain (8 and 9).
test_char_op_clips!(
    test_ich_clips_to_right_margin,
    test_dch_clips_to_right_margin_macro,
    cols 10, cursor_col 8,
    ich_seq b"\x1b[5@",
    dch_seq b"\x1b[5P",
    blanked_cols [8, 9],
);

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
            cell.grapheme = compact_str::CompactString::new(((b'0' + i as u8) as char).to_string());
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

// ── New edge-case tests ───────────────────────────────────────────────────────

/// IL at row 0 (top of screen, no scroll region): inserts blank at row 0,
/// existing content shifts down, last row is lost.
#[test]
fn test_il_at_top_row_shifts_content_down() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_rows_seq!(term, rows 5, base b'A');
    term.screen.move_cursor(0, 0);

    let params = vte::Params::default();
    csi_il(&mut term, &params); // IL 1

    assert_eq!(char_at(&term, 0, 0), ' '); // new blank at top
    assert_eq!(char_at(&term, 1, 0), 'A'); // former row 0 shifted to row 1
    assert_eq!(char_at(&term, 2, 0), 'B'); // former row 1 shifted to row 2
    assert_eq!(char_at(&term, 4, 0), 'D'); // former row 3 shifted to row 4
}

/// DL at the last row of the scroll region: deletes that row and fills
/// the bottom of the region with blank.
#[test]
fn test_dl_at_last_row_of_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows_seq!(term, rows 10, base b'0');
    // scroll region: rows 0..5 (0-indexed top=0, bottom=5)
    term.screen.set_scroll_region(0, 5);
    term.screen.move_cursor(4, 0); // last row inside region

    let params = vte::Params::default();
    csi_dl(&mut term, &params); // DL 1

    // Row 4 was '4'; it is deleted, row 5 (bottom of region) becomes blank
    assert_eq!(char_at(&term, 4, 0), ' ');
    // Rows outside region (5..10) are untouched
    for r in 5..10 {
        let ch = (b'0' + r as u8) as char;
        assert_eq!(
            char_at(&term, r, 0),
            ch,
            "row {r} below region must be unchanged"
        );
    }
}

/// ICH 0 is treated as ICH 1 (parameter 0 → default 1).
#[test]
fn test_ich_zero_param_treated_as_one() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'A');
    term.screen.move_cursor(0, 3);

    term.advance(b"\x1b[0@"); // CSI 0 @ → treated as 1

    assert_eq!(char_at(&term, 0, 3), ' '); // blank inserted
    assert_eq!(char_at(&term, 0, 4), 'A'); // shifted right
}

/// DCH 0 is treated as DCH 1.
#[test]
fn test_dch_zero_param_treated_as_one() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'A');
    // Put a distinct char at col 3
    if let Some(line) = term.screen.get_line_mut(0) {
        line.update_cell_with(3, crate::types::Cell::new('Z'));
    }
    term.screen.move_cursor(0, 3);

    term.advance(b"\x1b[0P"); // CSI 0 P → treated as 1

    // 'Z' at col 3 is deleted; col 3 now holds 'A' (from col 4)
    assert_eq!(char_at(&term, 0, 3), 'A');
    assert_eq!(char_at(&term, 0, 9), ' '); // blank at right end
}

/// ECH 0 is treated as ECH 1.
#[test]
fn test_ech_zero_param_treated_as_one() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'B');
    term.screen.move_cursor(0, 5);

    term.advance(b"\x1b[0X"); // CSI 0 X → treated as 1

    assert_eq!(char_at(&term, 0, 5), ' '); // erased
    assert_eq!(char_at(&term, 0, 6), 'B'); // right neighbor untouched
    assert_eq!(char_at(&term, 0, 4), 'B'); // left neighbor untouched
                                           // Cursor must not move
    assert_eq!(term.screen.cursor().col, 5);
}

/// IL with count exactly equal to the remaining rows in the region blanks
/// all of them and does not panic.
#[test]
fn test_il_count_exact_remaining_rows() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_rows_seq!(term, rows 5, base b'A');
    // default scroll region: 0..5
    term.screen.move_cursor(2, 0); // remaining rows = 5 - 2 = 3

    term.advance(b"\x1b[3L"); // insert exactly 3 lines

    // Rows 0..2 untouched
    assert_eq!(char_at(&term, 0, 0), 'A');
    assert_eq!(char_at(&term, 1, 0), 'B');
    // Rows 2..5 are now blank (3 blanks inserted, 3 originals scrolled off)
    assert_eq!(char_at(&term, 2, 0), ' ');
    assert_eq!(char_at(&term, 3, 0), ' ');
    assert_eq!(char_at(&term, 4, 0), ' ');
}

/// DL with count equal to the remaining rows in the region blanks them
/// and does not panic.
#[test]
fn test_dl_count_exact_remaining_rows() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_rows_seq!(term, rows 5, base b'0');
    // default scroll region: 0..5
    term.screen.move_cursor(2, 0); // remaining rows = 5 - 2 = 3

    term.advance(b"\x1b[3M"); // delete exactly 3 lines

    // Rows 0..2 untouched
    assert_eq!(char_at(&term, 0, 0), '0');
    assert_eq!(char_at(&term, 1, 0), '1');
    // Rows 2..5 are now blank
    assert_eq!(char_at(&term, 2, 0), ' ');
    assert_eq!(char_at(&term, 3, 0), ' ');
    assert_eq!(char_at(&term, 4, 0), ' ');
}

// ── Additional edge-case tests ────────────────────────────────────────────────

/// IL with cursor above the scroll region (using a region that starts at row 4,
/// cursor at row 2): the scroll region must be completely unaffected.
/// This variant uses a wider margin (cursor is 2 rows above the region top)
/// to complement the existing test that places the cursor 2 rows above top=3.
#[test]
fn test_il_cursor_above_scroll_region_is_noop() {
    let mut term = crate::TerminalCore::new(24, 80);
    // Fill rows with distinct content
    fill_rows_seq!(term, rows 10, base b'A');
    // Scroll region: 1-indexed CSI 5;20 r → 0-indexed top=4, bottom=20
    term.advance(b"\x1b[5;20r");
    // Cursor is now at (0,0) after DECSTBM; move it to row 2 (above region top=4)
    term.screen.move_cursor(2, 0);
    assert_eq!(term.screen.cursor().row, 2);

    // IL 1: cursor is above the scroll region top → no-op
    term.advance(b"\x1b[L");

    // Rows that were inside the scroll region must be untouched
    // (rows 4-9 in our filled content have chars 'E'..'J')
    assert_eq!(
        char_at(&term, 4, 0),
        'E',
        "row 4 (region top) must be unchanged when cursor is above region"
    );
    assert_eq!(
        char_at(&term, 5, 0),
        'F',
        "row 5 must be unchanged when IL is a noop"
    );
    assert_eq!(
        char_at(&term, 6, 0),
        'G',
        "row 6 must be unchanged when IL is a noop"
    );
}

/// DL with cursor below the scroll region (region rows 3-10 in 1-indexed,
/// cursor at row 12): the scroll region must not be affected.
#[test]
fn test_dl_cursor_below_scroll_region_is_noop() {
    let mut term = crate::TerminalCore::new(24, 80);
    fill_rows_seq!(term, rows 15, base b'0');
    // Scroll region: 1-indexed CSI 3;10 r → 0-indexed top=2, bottom=10
    term.advance(b"\x1b[3;10r");
    // Move cursor to row 12, which is below the region end (0-indexed bottom=10)
    term.screen.move_cursor(12, 0);
    assert_eq!(term.screen.cursor().row, 12);

    // DL 1: cursor is below the scroll region → no-op
    term.advance(b"\x1b[M");

    // Rows inside the scroll region must be untouched
    assert_eq!(
        char_at(&term, 2, 0),
        '2',
        "row 2 (region top) must be unchanged when cursor is below region"
    );
    assert_eq!(
        char_at(&term, 5, 0),
        '5',
        "row 5 must be unchanged when DL is a noop"
    );
    assert_eq!(
        char_at(&term, 9, 0),
        '9',
        "row 9 (last in region) must be unchanged when DL is a noop"
    );
}

/// ICH at the last column (col 79 on an 80-col terminal): inserting characters
/// at the last column inserts a blank there, pushing the existing char off screen.
/// Columns to the LEFT of the cursor are NOT affected by ICH.
/// Cursor stays at column 79.
#[test]
fn test_ich_at_last_column() {
    let mut term = crate::TerminalCore::new(5, 80);
    fill_line(&mut term, 0, 'A');
    // Put distinct chars at cols 77, 78, 79
    if let Some(line) = term.screen.get_line_mut(0) {
        line.update_cell_with(77, crate::types::Cell::new('W'));
        line.update_cell_with(78, crate::types::Cell::new('Y'));
        line.update_cell_with(79, crate::types::Cell::new('Z'));
    }
    // Move cursor to last column (col 79)
    term.screen.move_cursor(0, 79);
    assert_eq!(term.screen.cursor().col, 79);

    // ICH 2 at the last column: blanks inserted starting at col 79.
    // ICH only affects cols >= cursor; col 79 is the last, so only col 79 is blanked.
    // The original 'Z' at col 79 is pushed off screen.
    term.advance(b"\x1b[2@");

    // Col 79 (cursor position) must be blank — the inserted blank
    assert_eq!(
        char_at(&term, 0, 79),
        ' ',
        "col 79 must be blank after ICH 2 at last column"
    );
    // Cols 78 and 77 are to the LEFT of the cursor and must be untouched
    assert_eq!(
        char_at(&term, 0, 78),
        'Y',
        "col 78 (left of cursor) must be untouched by ICH"
    );
    assert_eq!(
        char_at(&term, 0, 77),
        'W',
        "col 77 (left of cursor) must be untouched by ICH"
    );
    // Cursor must remain at col 79
    assert_eq!(term.screen.cursor().col, 79, "ICH must not move the cursor");
    // Line width must be preserved
    assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 80);
}

/// DCH with a count much larger than the remaining columns (from col 5, count=200
/// on a 10-col terminal): no panic, and the line from col 5 onward becomes spaces.
#[test]
fn test_dch_more_than_columns_is_noop_with_spaces() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'X');
    term.screen.move_cursor(0, 5);

    // DCH 200: far more than the 5 remaining columns (10 - 5)
    term.advance(b"\x1b[200P");

    // Columns 0..5 (before cursor) must be untouched
    for col in 0..5 {
        assert_eq!(
            char_at(&term, 0, col),
            'X',
            "col {col} (before cursor) must be untouched after DCH 200"
        );
    }
    // Columns 5..10 must all be space (deleted and filled with blanks)
    for col in 5..10 {
        assert_eq!(
            char_at(&term, 0, col),
            ' ',
            "col {col} must be blank after DCH 200"
        );
    }
    // No panic and line width preserved
    assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 10);
}

/// ECH at a position where cells have a non-default background color set via SGR:
/// erased cells become space characters AND carry the current SGR background color.
/// This complements test_ech_uses_sgr_background by also verifying the character is space.
#[test]
fn test_ech_clears_to_default_background() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'Q');

    // Set a non-default background color (SGR 42 = green background)
    term.advance(b"\x1b[42m");
    term.screen.move_cursor(0, 4);

    // ECH 3: erase 3 characters starting at col 4
    term.advance(b"\x1b[3X");

    // Erased cells must be space
    assert_eq!(
        char_at(&term, 0, 4),
        ' ',
        "erased cell at col 4 must be space"
    );
    assert_eq!(
        char_at(&term, 0, 5),
        ' ',
        "erased cell at col 5 must be space"
    );
    assert_eq!(
        char_at(&term, 0, 6),
        ' ',
        "erased cell at col 6 must be space"
    );
    // Erased cells must carry the current SGR background (not Color::Default)
    let cell4 = term.screen.get_cell(0, 4).unwrap();
    assert_ne!(
        cell4.attrs.background,
        crate::Color::Default,
        "erased cell must carry SGR background color (not Color::Default)"
    );
    // Cells outside the erased range must be untouched
    assert_eq!(
        char_at(&term, 0, 3),
        'Q',
        "col 3 (before erased range) must be untouched"
    );
    assert_eq!(
        char_at(&term, 0, 7),
        'Q',
        "col 7 (after erased range) must be untouched"
    );
    // Cursor must not move
    assert_eq!(term.screen.cursor().col, 4, "ECH must not move the cursor");
}

// ── New edge-case tests (Round 29+) ───────────────────────────────────────────

/// IL at the boundary row that is exactly the scroll region top: the cursor IS
/// inside the region (it equals top), so the operation should NOT be a noop.
/// One blank line is inserted at the cursor row and content shifts down within the region.
#[test]
fn test_il_cursor_at_scroll_region_top_is_not_noop() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows_seq!(term, rows 10, base b'0');
    // Scroll region: top=3, bottom=8
    term.screen.set_scroll_region(3, 8);
    // Move cursor to exactly the region top (row 3)
    term.screen.move_cursor(3, 0);

    let params = vte::Params::default();
    csi_il(&mut term, &params); // IL 1

    // Row 3 (cursor) should now be blank (newly inserted)
    assert_eq!(
        char_at(&term, 3, 0),
        ' ',
        "row 3 (region top) must have a blank inserted"
    );
    // Original row 3 ('3') should have shifted to row 4
    assert_eq!(
        char_at(&term, 4, 0),
        '3',
        "former row 3 should shift down to row 4"
    );
    // Rows above region must be untouched
    assert_eq!(
        char_at(&term, 2, 0),
        '2',
        "row 2 above region must be unchanged"
    );
    // Rows below region must be untouched
    assert_eq!(
        char_at(&term, 8, 0),
        '8',
        "row 8 below region must be unchanged"
    );
}

/// DL with 2 lines starting at the first row of a custom scroll region: the two
/// deleted rows' successors shift up, and the bottom two rows of the region become blank.
#[test]
fn test_dl_multi_line_partial_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows_seq!(term, rows 10, base b'A');
    // Scroll region: top=2, bottom=7 (0-indexed, exclusive bottom)
    term.screen.set_scroll_region(2, 7);
    // Cursor at region top
    term.screen.move_cursor(2, 0);

    term.advance(b"\x1b[2M"); // DL 2

    // Rows 2 and 3 are deleted; rows 4,5,6 shift up to 2,3,4
    assert_eq!(
        char_at(&term, 2, 0),
        'E',
        "row 2 should now be former row 4 ('E')"
    );
    assert_eq!(
        char_at(&term, 3, 0),
        'F',
        "row 3 should now be former row 5 ('F')"
    );
    assert_eq!(
        char_at(&term, 4, 0),
        'G',
        "row 4 should now be former row 6 ('G')"
    );
    // Bottom 2 rows of the region (rows 5,6) become blank
    assert_eq!(char_at(&term, 5, 0), ' ', "row 5 (blanked) should be space");
    assert_eq!(char_at(&term, 6, 0), ' ', "row 6 (blanked) should be space");
    // Rows outside the region are untouched
    assert_eq!(
        char_at(&term, 1, 0),
        'B',
        "row 1 above region must be unchanged"
    );
    assert_eq!(
        char_at(&term, 7, 0),
        'H',
        "row 7 below region must be unchanged"
    );
}

/// ICH does NOT affect rows other than the cursor row — sibling rows must remain
/// unchanged even when multiple rows share the same fill character.
#[test]
fn test_ich_only_modifies_cursor_row() {
    let mut term = crate::TerminalCore::new(5, 10);
    for r in 0..5 {
        fill_line(&mut term, r, 'X');
    }
    term.screen.move_cursor(2, 3); // cursor on row 2

    let params = vte::Params::default();
    csi_ich(&mut term, &params); // ICH 1

    // Row 2: col 3 becomes blank, col 4 gets 'X'
    assert_eq!(char_at(&term, 2, 3), ' ');
    assert_eq!(char_at(&term, 2, 4), 'X');
    // All other rows must still start with 'X' at col 0 (untouched by ICH)
    for r in [0, 1, 3, 4] {
        assert_eq!(
            char_at(&term, r, 0),
            'X',
            "row {r} must be untouched by ICH on row 2"
        );
    }
}

/// ECH at column 0 erases only the specified count starting at col 0,
/// and does not affect other rows or columns beyond the count.
#[test]
fn test_ech_at_column_zero() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'M');
    fill_line(&mut term, 1, 'M'); // other row with same content
    term.screen.move_cursor(0, 0);

    term.advance(b"\x1b[2X"); // ECH 2: erase cols 0 and 1 on row 0

    // Cols 0 and 1 on row 0 become space
    assert_eq!(char_at(&term, 0, 0), ' ', "col 0 must be erased");
    assert_eq!(char_at(&term, 0, 1), ' ', "col 1 must be erased");
    // Col 2 onward on row 0 must be untouched
    assert_eq!(char_at(&term, 0, 2), 'M', "col 2 must be untouched");
    // Row 1 must be completely untouched
    assert_eq!(
        char_at(&term, 1, 0),
        'M',
        "row 1 col 0 must be untouched by ECH on row 0"
    );
    // Cursor must not have moved
    assert_eq!(term.screen.cursor().col, 0, "ECH must not move the cursor");
}

// ── IL/DL blank-line character and line-count invariants ─────────────────────
//
// NOTE: IL and DL use `Line::new()` for inserted blank lines, which always
// produces cells with `Color::Default` background — they do NOT propagate the
// current SGR background (no BCE). This is distinct from SU/SD (scroll_up /
// scroll_down) which accept an explicit background argument.

/// IL inserts a blank line (space character, default background) at the cursor
/// row. Even when a non-default SGR background is active, the inserted line
/// uses the default background because IL does not apply BCE.
#[test]
fn test_il_blank_line_has_default_background() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_rows_seq!(term, rows 5, base b'A');

    term.advance(b"\x1b[46m"); // SGR 46 = cyan background (active but not used by IL)
    term.screen.move_cursor(1, 0);

    let params = vte::Params::default();
    csi_il(&mut term, &params); // IL 1

    let cell = term.screen.get_cell(1, 0).unwrap();
    assert_eq!(cell.char(), ' ', "IL blank line must be space");
    // IL does NOT propagate the SGR background — it uses Color::Default
    assert_eq!(
        cell.attrs.background,
        crate::Color::Default,
        "IL blank line must have Color::Default background (no BCE)"
    );
    assert_eq!(char_at(&term, 2, 0), 'B', "former row 1 must shift to row 2");
}

/// DL fills the bottom of the scroll region with blank lines (space character,
/// default background). Even when a non-default SGR background is active, DL
/// uses the default background because it does not apply BCE.
#[test]
fn test_dl_blank_line_has_default_background() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_rows_seq!(term, rows 5, base b'0');

    term.advance(b"\x1b[45m"); // SGR 45 = magenta background (active but not used by DL)
    term.screen.move_cursor(1, 0);

    let params = vte::Params::default();
    csi_dl(&mut term, &params); // DL 1

    let cell = term.screen.get_cell(4, 0).unwrap();
    assert_eq!(cell.char(), ' ', "DL trailing blank line must be space");
    // DL does NOT propagate the SGR background — it uses Color::Default
    assert_eq!(
        cell.attrs.background,
        crate::Color::Default,
        "DL blank line must have Color::Default background (no BCE)"
    );
}

/// ECH dirty tracking is isolated to the cursor row — sibling rows must not
/// be marked dirty.
#[test]
fn test_ech_dirty_is_isolated_to_cursor_row() {
    let mut term = crate::TerminalCore::new(5, 10);
    for r in 0..5 {
        fill_line(&mut term, r, 'Q');
    }
    term.screen.take_dirty_lines();

    term.screen.move_cursor(2, 3);
    term.advance(b"\x1b[2X"); // ECH 2

    let dirty = term.screen.take_dirty_lines();
    assert!(dirty.contains(&2), "ECH must mark cursor row 2 dirty");
    for r in [0usize, 1, 3, 4] {
        assert!(
            !dirty.contains(&r),
            "row {r} must not be marked dirty by ECH on row 2"
        );
    }
}

/// IL at the last row of the scroll region: the inserted blank pushes the
/// existing content off-screen, leaving the last row blank.
#[test]
fn test_il_at_region_bottom_minus_one() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_rows_seq!(term, rows 5, base b'A');
    term.screen.move_cursor(4, 0);

    let params = vte::Params::default();
    csi_il(&mut term, &params); // IL 1

    assert_eq!(char_at(&term, 4, 0), ' ', "row 4 must be blank after IL at last row");
    assert_eq!(char_at(&term, 0, 0), 'A');
    assert_eq!(char_at(&term, 1, 0), 'B');
    assert_eq!(char_at(&term, 3, 0), 'D');
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

    #[test]
    // INVARIANT: ECH (CSI n X) never panics; line width and cursor col preserved
    fn prop_ech_no_panic_preserves_width_and_cursor(
        n in 0u16..=100u16,
        col in 0usize..20usize,
    ) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.screen.move_cursor(0, col);
        term.advance(format!("\x1b[{n}X").as_bytes());
        prop_assert_eq!(
            term.screen.get_line(0).unwrap().cells.len(), 20,
            "line width must be preserved after ECH"
        );
        prop_assert_eq!(term.screen.cursor().col, col, "ECH must not move the cursor");
    }

    #[test]
    // INVARIANT: ICH then DCH with equal count at same column preserves line width
    fn prop_ich_dch_preserves_line_width(
        n in 1u16..=10u16,
        col in 0usize..10usize,
    ) {
        let mut term = crate::TerminalCore::new(5, 20);
        term.screen.move_cursor(0, col);
        term.advance(format!("\x1b[{n}@").as_bytes()); // ICH n
        term.screen.move_cursor(0, col);
        term.advance(format!("\x1b[{n}P").as_bytes()); // DCH n
        prop_assert_eq!(
            term.screen.get_line(0).unwrap().cells.len(), 20,
            "line width must be preserved after ICH+DCH"
        );
    }
}

// ── New tests (Round 34) ──────────────────────────────────────────────────────

// DCH at column 0 shifts the entire row left: col 0 is deleted, col 1
// moves to col 0, and the last column becomes blank.
#[test]
fn test_dch_at_column_zero_shifts_row_left() {
    let mut term = crate::TerminalCore::new(5, 10);
    // Fill row 0 with '0'..'9'
    if let Some(line) = term.screen.get_line_mut(0) {
        for (i, cell) in line.cells.iter_mut().enumerate() {
            cell.grapheme =
                compact_str::CompactString::new(((b'0' + i as u8) as char).to_string());
        }
    }
    term.screen.move_cursor(0, 0);

    let params = vte::Params::default();
    csi_dch(&mut term, &params); // DCH 1

    // '0' deleted; '1' now at col 0, '2' at col 1, etc.
    assert_eq!(char_at(&term, 0, 0), '1', "col 0 must hold former col 1");
    assert_eq!(char_at(&term, 0, 1), '2', "col 1 must hold former col 2");
    assert_eq!(char_at(&term, 0, 8), '9', "col 8 must hold former col 9");
    assert_eq!(char_at(&term, 0, 9), ' ', "last col must be blank");
    assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 10);
}

// ICH at column 0 shifts the entire row right: a blank is inserted at col 0
// and all existing chars shift right; the original last char falls off.
#[test]
fn test_ich_at_column_zero_shifts_entire_row_right() {
    let mut term = crate::TerminalCore::new(5, 10);
    // Fill row 0 with '0'..'9'
    if let Some(line) = term.screen.get_line_mut(0) {
        for (i, cell) in line.cells.iter_mut().enumerate() {
            cell.grapheme =
                compact_str::CompactString::new(((b'0' + i as u8) as char).to_string());
        }
    }
    term.screen.move_cursor(0, 0);

    let params = vte::Params::default();
    csi_ich(&mut term, &params); // ICH 1

    assert_eq!(char_at(&term, 0, 0), ' ', "col 0 must be blank (inserted)");
    assert_eq!(char_at(&term, 0, 1), '0', "col 1 must hold former col 0");
    // '9' at col 9 is pushed off; col 9 holds '8'
    assert_eq!(
        char_at(&term, 0, 9),
        '8',
        "col 9 must hold former col 8 ('9' falls off)"
    );
    assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 10);
}

// IL inside a scroll region shifts content down within the region boundary.
// Content above and below the region must be unaffected.
#[test]
fn test_il_inside_scroll_region_shifts_content_down() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows_seq!(term, rows 10, base b'A');
    // Set scroll region: rows 2..7 (0-indexed top=2, bottom=7)
    term.screen.set_scroll_region(2, 7);
    term.screen.move_cursor(3, 0); // cursor inside region

    let params = vte::Params::default();
    csi_il(&mut term, &params); // IL 1

    // Content above the region: untouched
    assert_eq!(char_at(&term, 0, 0), 'A', "row 0 above region unchanged");
    assert_eq!(char_at(&term, 1, 0), 'B', "row 1 above region unchanged");
    assert_eq!(
        char_at(&term, 2, 0),
        'C',
        "row 2 (region top, above cursor) unchanged"
    );
    // Blank inserted at cursor row
    assert_eq!(char_at(&term, 3, 0), ' ', "row 3 must be blank (inserted)");
    // Former row 3 shifted down
    assert_eq!(char_at(&term, 4, 0), 'D', "row 4 must hold former row 3");
    // Content below the region: untouched
    assert_eq!(char_at(&term, 7, 0), 'H', "row 7 below region unchanged");
}

// IL at the bottom row of the scroll region: the content at that row is
// pushed off, leaving the bottom row blank. Rows outside the region untouched.
#[test]
fn test_il_at_bottom_of_scroll_region_pushes_off() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows_seq!(term, rows 10, base b'0');
    // Scroll region: rows 2..6 (0-indexed exclusive bottom=6)
    term.screen.set_scroll_region(2, 6);
    term.screen.move_cursor(5, 0); // last row of region (bottom-1)

    let params = vte::Params::default();
    csi_il(&mut term, &params); // IL 1

    // Row 5 was '5'; after IL it's blank (content pushed off)
    assert_eq!(
        char_at(&term, 5, 0),
        ' ',
        "bottom row of region must be blank"
    );
    // Rows above the cursor inside the region: unchanged
    assert_eq!(
        char_at(&term, 2, 0),
        '2',
        "row 2 inside region but above cursor: unchanged"
    );
    // Rows outside the region: unchanged
    assert_eq!(char_at(&term, 6, 0), '6', "row 6 below region unchanged");
    assert_eq!(char_at(&term, 9, 0), '9', "row 9 unchanged");
}

// DL inside a scroll region: the deleted row causes rows below it (inside the
// region) to shift up, and the region bottom is filled with blank.
#[test]
fn test_dl_inside_scroll_region_shifts_content_up() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows_seq!(term, rows 10, base b'A');
    // Scroll region: rows 3..8 (0-indexed top=3, bottom=8 exclusive)
    term.screen.set_scroll_region(3, 8);
    term.screen.move_cursor(4, 0); // inside region

    let params = vte::Params::default();
    csi_dl(&mut term, &params); // DL 1

    // Row 4 ('E') deleted; row 5 ('F') shifts to row 4
    assert_eq!(
        char_at(&term, 4, 0),
        'F',
        "row 4 must hold former row 5 after DL"
    );
    assert_eq!(char_at(&term, 5, 0), 'G', "row 5 must hold former row 6");
    // Bottom of region (row 7) is now blank
    assert_eq!(
        char_at(&term, 7, 0),
        ' ',
        "region bottom must be blank after DL"
    );
    // Rows outside region: unchanged
    assert_eq!(char_at(&term, 2, 0), 'C', "row 2 above region unchanged");
    assert_eq!(char_at(&term, 8, 0), 'I', "row 8 below region unchanged");
}

// DL at the bottom row of the scroll region: deleting the last region row
// produces a blank there; rows above it inside the region are untouched.
#[test]
fn test_dl_at_bottom_of_scroll_region_clears_last_row() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows_seq!(term, rows 10, base b'0');
    // Scroll region: rows 1..5 (0-indexed top=1, bottom=5 exclusive)
    term.screen.set_scroll_region(1, 5);
    term.screen.move_cursor(4, 0); // last row inside region

    let params = vte::Params::default();
    csi_dl(&mut term, &params); // DL 1

    // Row 4 was the last in the region; it becomes blank
    assert_eq!(
        char_at(&term, 4, 0),
        ' ',
        "last region row must be blank after DL"
    );
    // Rows 1..4 inside region above cursor: unchanged
    assert_eq!(char_at(&term, 1, 0), '1', "row 1 inside region unchanged");
    assert_eq!(char_at(&term, 3, 0), '3', "row 3 inside region unchanged");
    // Rows outside the region: unchanged
    assert_eq!(char_at(&term, 0, 0), '0', "row 0 above region unchanged");
    assert_eq!(char_at(&term, 5, 0), '5', "row 5 below region unchanged");
}

// SU (CSI S) with the primary screen advances scrollback: after scrolling up
// by N lines the scrollback line count must increase.
#[test]
fn test_su_increases_scrollback_count() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'X');
    fill_line(&mut term, 1, 'Y');

    // Scrollback starts at 0
    assert_eq!(
        term.screen.scrollback_line_count, 0,
        "scrollback must be empty initially"
    );

    // SU 2: scrolls up 2 lines; the top 2 rows ('X', 'Y') go into scrollback
    term.advance(b"\x1b[2S");

    assert!(
        term.screen.scrollback_line_count > 0,
        "scrollback_line_count must be > 0 after SU"
    );
}

// SD (CSI T) shifts visible content down; row 0 becomes blank and former
// row 0 content appears at row 1.  Scrollback count is not affected by SD.
#[test]
fn test_sd_shifts_content_into_visible_area() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_rows_seq!(term, rows 5, base b'A');

    let before_scrollback = term.screen.scrollback_line_count;

    // SD 1: top row becomes blank, former row 0 ('A') appears at row 1
    term.advance(b"\x1b[T");

    assert_eq!(
        char_at(&term, 0, 0),
        ' ',
        "SD: row 0 must be blank after scroll down"
    );
    assert_eq!(
        char_at(&term, 1, 0),
        'A',
        "SD: row 1 must hold former row 0 content"
    );
    assert_eq!(
        term.screen.scrollback_line_count,
        before_scrollback,
        "SD must not change scrollback count"
    );
}

// ICH multiple characters: inserting 3 blanks at col 2 shifts cols 2..9 right
// by 3; the last 3 chars at cols 7..9 are pushed off.
#[test]
fn test_ich_multi_char_insert() {
    let mut term = crate::TerminalCore::new(5, 10);
    // Fill row 0 with 'A'..'J'
    if let Some(line) = term.screen.get_line_mut(0) {
        for (i, cell) in line.cells.iter_mut().enumerate() {
            cell.grapheme =
                compact_str::CompactString::new(((b'A' + i as u8) as char).to_string());
        }
    }
    term.screen.move_cursor(0, 2);

    term.advance(b"\x1b[3@"); // ICH 3

    // Cols 0 and 1 (left of cursor): untouched
    assert_eq!(char_at(&term, 0, 0), 'A', "col 0 untouched");
    assert_eq!(char_at(&term, 0, 1), 'B', "col 1 untouched");
    // 3 blanks inserted at cols 2, 3, 4
    assert_eq!(char_at(&term, 0, 2), ' ', "col 2 blank (inserted)");
    assert_eq!(char_at(&term, 0, 3), ' ', "col 3 blank (inserted)");
    assert_eq!(char_at(&term, 0, 4), ' ', "col 4 blank (inserted)");
    // Former col 2 ('C') shifted to col 5
    assert_eq!(char_at(&term, 0, 5), 'C', "col 5 holds former col 2");
    // Cols 7..10: former cols 5,6 and one more; last 3 cols pushed off
    assert_eq!(
        char_at(&term, 0, 9),
        'G',
        "col 9 holds former col 6 (H,I,J pushed off)"
    );
    assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 10);
}

// DCH with count exceeding the columns from cursor to right margin: all cols
// from cursor to end become blank; no panic; line width preserved.
#[test]
fn test_dch_count_exceeds_remaining_cols() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'Z');
    term.screen.move_cursor(0, 3); // 7 cols remain (3..10)

    term.advance(b"\x1b[100P"); // DCH 100: clamped to 7

    // Cols 0..3 (before cursor): unchanged
    for col in 0..3 {
        assert_eq!(
            char_at(&term, 0, col),
            'Z',
            "col {col} before cursor must be unchanged"
        );
    }
    // Cols 3..10: blank
    for col in 3..10 {
        assert_eq!(
            char_at(&term, 0, col),
            ' ',
            "col {col} must be blank after DCH 100"
        );
    }
    assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 10);
}
