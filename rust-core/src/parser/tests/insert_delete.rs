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

include!("insert_delete_basic.rs");
include!("insert_delete_edge_cases.rs");
