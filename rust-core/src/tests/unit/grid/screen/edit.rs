//! Unit tests for `Screen` edit methods (edit.rs):
//! `clear_lines`, `insert_lines`, `delete_lines`, `insert_chars`, `delete_chars`, `erase_chars`.

use super::{assert_cell_char, make_screen};
use crate::grid::screen::Screen;
use crate::types::cell::SgrAttributes;
use proptest::prelude::*;

/// Generates a `#[test]` asserting that the operation leaves row count unchanged.
/// Usage: `assert_preserves_row_count!(test_name, method(args))`
macro_rules! assert_preserves_row_count {
    ($name:ident, $method:ident ( $($arg:expr),* )) => {
        #[test]
        fn $name() {
            let mut s = make_screen();
            let rows_before = s.rows() as usize;
            s.move_cursor(0, 0);
            s.$method($($arg),*);
            assert_eq!(s.rows() as usize, rows_before);
        }
    };
}

/// Generates a `#[test]` asserting that the operation leaves line width (80) unchanged.
/// Usage: `assert_line_width_unchanged!(test_name, method(args))`
macro_rules! assert_line_width_unchanged {
    ($name:ident, $method:ident ( $($arg:expr),* )) => {
        #[test]
        fn $name() {
            let mut s = make_screen();
            s.move_cursor(0, 0);
            s.$method($($arg),*);
            assert_eq!(s.get_line(0).unwrap().cells.len(), 80);
        }
    };
}

/// Generates a `#[test]` asserting that an operation whose cursor falls outside the
/// scroll region [5, 10) is a no-op for the cell at (`$row`, 0).
/// Usage: `assert_outside_scroll_noop!(test_name, $row, $ch, method(args))`
macro_rules! assert_outside_scroll_noop {
    ($name:ident, $row:expr, $ch:expr, $method:ident ( $($arg:expr),* )) => {
        #[test]
        fn $name() {
            let mut s = make_screen();
            s.set_scroll_region(5, 10);
            s.move_cursor($row, 0);
            s.print($ch, SgrAttributes::default(), true);
            s.move_cursor($row, 0);
            s.$method($($arg),*);
            assert_eq!(s.get_cell($row, 0).unwrap().char(), $ch);
        }
    };
}

/// Generates a `#[test]` asserting that passing count `0` to an operation is a no-op.
/// The cell at (0, 0) must retain `$ch` after the operation.
/// Usage: `assert_count_zero_noop!(test_name, $ch, method(0))`
macro_rules! assert_count_zero_noop {
    ($name:ident, $ch:expr, $method:ident ( $($arg:expr),* )) => {
        #[test]
        fn $name() {
            let mut s = make_screen();
            s.move_cursor(0, 0);
            s.print($ch, SgrAttributes::default(), true);
            s.move_cursor(0, 0);
            s.$method($($arg),*);
            assert_eq!(s.get_cell(0, 0).unwrap().char(), $ch);
        }
    };
}

// ---------------------------------------------------------------------------
// clear_lines
// ---------------------------------------------------------------------------

#[test]
fn clear_lines_zeroes_range() {
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    // Write a char to row 2
    s.move_cursor(2, 0);
    s.print('Z', attrs, true);
    assert_eq!(s.get_cell(2, 0).unwrap().char(), 'Z');

    s.clear_lines(2, 3);

    assert_cell_char!(s, 2, 0, ' ', "clear_lines must blank the target row");
}

#[test]
fn clear_lines_empty_range_is_noop() {
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    s.print('A', attrs, true);

    // start == end → no-op
    s.clear_lines(0, 0);

    assert_eq!(s.get_cell(0, 0).unwrap().char(), 'A');
}

#[test]
fn clear_lines_clamped_end_beyond_rows() {
    // end > rows must not panic
    let mut s = make_screen();
    s.clear_lines(0, 9999);
    // All cells become blank — spot-check row 0
    assert_eq!(s.get_cell(0, 0).unwrap().char(), ' ');
}

// ---------------------------------------------------------------------------
// insert_lines (IL — CSI Ps L)
// ---------------------------------------------------------------------------

#[test]
fn insert_lines_shifts_content_down() {
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    // Print 'A' at row 0, 'B' at row 1
    s.move_cursor(0, 0);
    s.print('A', attrs, true);
    s.move_cursor(1, 0);
    s.print('B', attrs, true);

    // Insert 1 blank line at row 0
    s.move_cursor(0, 0);
    s.insert_lines(1);

    // Row 0 must now be blank
    assert_cell_char!(s, 0, 0, ' ');
    // Old row 0 ('A') shifted to row 1
    assert_cell_char!(s, 1, 0, 'A');
    // Old row 1 ('B') shifted to row 2
    assert_cell_char!(s, 2, 0, 'B');
}

assert_count_zero_noop!(insert_lines_count_zero_is_noop, 'X', insert_lines(0));
assert_outside_scroll_noop!(
    insert_lines_outside_scroll_region_is_noop,
    3,
    'Q',
    insert_lines(1)
);
assert_preserves_row_count!(insert_lines_preserves_line_count, insert_lines(5));

// ---------------------------------------------------------------------------
// delete_lines (DL — CSI Ps M)
// ---------------------------------------------------------------------------

#[test]
fn delete_lines_scrolls_content_up() {
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    // Row 0: 'A', Row 1: 'B', Row 2: 'C'
    s.move_cursor(0, 0);
    s.print('A', attrs, true);
    s.move_cursor(1, 0);
    s.print('B', attrs, true);
    s.move_cursor(2, 0);
    s.print('C', attrs, true);

    // Delete 1 line at row 0
    s.move_cursor(0, 0);
    s.delete_lines(1);

    // Old row 1 ('B') moves to row 0
    assert_cell_char!(s, 0, 0, 'B');
    // Old row 2 ('C') moves to row 1
    assert_cell_char!(s, 1, 0, 'C');
    // Bottom row of scroll region becomes blank
    assert_cell_char!(s, 23, 0, ' ');
}

assert_outside_scroll_noop!(
    delete_lines_outside_scroll_region_is_noop,
    2,
    'W',
    delete_lines(1)
);
assert_preserves_row_count!(delete_lines_preserves_line_count, delete_lines(3));

// ---------------------------------------------------------------------------
// insert_chars (ICH — CSI Ps @)
// ---------------------------------------------------------------------------

#[test]
fn insert_chars_shifts_right() {
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    // Print "AB" at cols 0-1
    s.move_cursor(0, 0);
    s.print('A', attrs, true);
    s.print('B', attrs, true);

    // Insert 1 blank at col 0
    s.move_cursor(0, 0);
    s.insert_chars(1, attrs);

    // Col 0 is now blank; 'A' shifted to col 1, 'B' to col 2
    assert_cell_char!(s, 0, 0, ' ');
    assert_cell_char!(s, 0, 1, 'A');
    assert_cell_char!(s, 0, 2, 'B');
}

assert_line_width_unchanged!(
    insert_chars_does_not_change_line_width,
    insert_chars(5, SgrAttributes::default())
);

#[test]
fn insert_chars_count_larger_than_remaining_clamps() {
    // insert_chars with count > cols should not panic
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    s.insert_chars(9999, attrs);
    // Line must still have exactly 80 cells
    assert_eq!(s.get_line(0).unwrap().cells.len(), 80);
}

// ---------------------------------------------------------------------------
// delete_chars (DCH — CSI Ps P)
// ---------------------------------------------------------------------------

#[test]
fn delete_chars_shifts_left_and_pads_right() {
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    // Print "ABC" at cols 0-2
    s.move_cursor(0, 0);
    s.print('A', attrs, true);
    s.print('B', attrs, true);
    s.print('C', attrs, true);

    // Delete 1 char at col 0
    s.move_cursor(0, 0);
    s.delete_chars(1);

    // 'B' and 'C' shift left; last column becomes blank
    assert_cell_char!(s, 0, 0, 'B');
    assert_cell_char!(s, 0, 1, 'C');
    assert_cell_char!(s, 0, 79, ' ');
}

assert_line_width_unchanged!(delete_chars_does_not_change_line_width, delete_chars(10));
assert_count_zero_noop!(delete_chars_count_zero_is_noop, 'X', delete_chars(0));

// ---------------------------------------------------------------------------
// erase_chars (ECH — CSI Ps X)
// ---------------------------------------------------------------------------

#[test]
fn erase_chars_blanks_cells_in_place() {
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    // Print "ABCD"
    s.move_cursor(0, 0);
    for ch in ['A', 'B', 'C', 'D'] {
        s.print(ch, attrs, true);
    }

    // Erase 2 chars at col 1 (erases 'B' and 'C')
    s.move_cursor(0, 1);
    s.erase_chars(2, attrs);

    assert_eq!(
        s.get_cell(0, 0).unwrap().char(),
        'A',
        "col 0 must be untouched"
    );
    assert_eq!(
        s.get_cell(0, 1).unwrap().char(),
        ' ',
        "col 1 must be erased"
    );
    assert_eq!(
        s.get_cell(0, 2).unwrap().char(),
        ' ',
        "col 2 must be erased"
    );
    assert_eq!(
        s.get_cell(0, 3).unwrap().char(),
        'D',
        "col 3 must be untouched"
    );
}

#[test]
fn erase_chars_cursor_does_not_move() {
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 5);
    s.erase_chars(3, attrs);
    assert_eq!(s.cursor().col, 5, "erase_chars must not move the cursor");
}

#[test]
fn erase_chars_clamped_at_right_margin() {
    // erase_chars(n) where n would go past the right margin must not panic
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 78);
    s.erase_chars(9999, attrs);
    // Cols 78 and 79 become blank; everything else unchanged
    assert_eq!(s.get_cell(0, 78).unwrap().char(), ' ');
    assert_eq!(s.get_cell(0, 79).unwrap().char(), ' ');
}

// ---------------------------------------------------------------------------
// PBT
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// insert_lines — multi-count and clamping
// ---------------------------------------------------------------------------

#[test]
fn insert_lines_count_greater_than_one_shifts_multiple_rows() {
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    // Row 0: 'A', Row 1: 'B', Row 2: 'C'
    s.move_cursor(0, 0);
    s.print('A', attrs, true);
    s.move_cursor(1, 0);
    s.print('B', attrs, true);
    s.move_cursor(2, 0);
    s.print('C', attrs, true);

    // Insert 2 blank lines at row 0
    s.move_cursor(0, 0);
    s.insert_lines(2);

    // Rows 0 and 1 are now blank
    assert_cell_char!(s, 0, 0, ' ');
    assert_cell_char!(s, 1, 0, ' ');
    // Old rows 0/1/2 shifted to rows 2/3/4
    assert_cell_char!(s, 2, 0, 'A');
    assert_cell_char!(s, 3, 0, 'B');
    assert_cell_char!(s, 4, 0, 'C');
}

include!("edit_insert_lines.rs");
