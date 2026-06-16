//! Shared helpers, macros, and nested cases for insert/delete parser tests.

// Test helpers convert between usize/u16/i64 for grid coordinates; values are
// bounded by terminal dimensions (≤ 65535 rows/cols) so truncation is safe.
#![expect(
    clippy::cast_possible_truncation,
    reason = "test coordinate casts bounded by terminal dimensions (≤ 65535)"
)]
#![allow(unused_macros)]

use super::*;
use super::support::{char_at, fill_line};

// ── Helpers ───────────────────────────────────────────────────────────────────

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
            assert_eq!(char_at(&term, $above, 0), ($base as u8 + $above as u8) as char);
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
            assert_eq!(char_at(&term, $above, 0), ($base as u8 + $above as u8) as char);
            for r in $blank_start..$blank_end {
                assert_eq!(char_at(&term, r, 0), ' ', "row {r} must be blank after DL 100");
            }
        }
    };
}

/// Generate a pair of right-margin clip tests (one for ICH, one for DCH) that
/// verify: when count would exceed the right margin from the cursor position,
/// the operation clamps and the line width is preserved.
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

/// Generate a dirty-tracking test for a character-column operation (ICH/DCH/ECH).
macro_rules! test_char_dirty_tracking {
    ($name:ident, seq $seq:expr, rows $rows:expr, cursor ($crow:expr, $ccol:expr), dirty_row $dirty:expr) => {
        #[test]
        fn $name() {
            let mut term = crate::TerminalCore::new($rows, 10);
            term.screen.take_dirty_lines();
            term.screen.move_cursor($crow, $ccol);
            term.advance($seq);
            let dirty = term.screen.take_dirty_lines();
            assert!(
                dirty.contains(&$dirty),
                "expected row {} to be dirty",
                $dirty
            );
        }
    };
}

#[path = "insert_delete/basic.rs"]
mod basic;

#[path = "insert_delete/basic_ech.rs"]
mod basic_ech;

#[path = "insert_delete/edge_cases.rs"]
mod edge_cases;

#[path = "insert_delete/edge_cases2.rs"]
mod edge_cases2;

#[path = "insert_delete/proptest.rs"]
mod pbt;

#[path = "insert_delete/decic_decdc.rs"]
mod decic_decdc;
