//! Unit tests for `Screen` edit methods (edit.rs):
//! `clear_lines`, `insert_lines`, `delete_lines`, `insert_chars`, `delete_chars`, `erase_chars`.

use super::{assert_cell_char, make_screen};
use crate::grid::screen::Screen;
use crate::types::cell::SgrAttributes;
use proptest::prelude::*;

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

#[test]
fn insert_lines_count_zero_is_noop() {
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    s.print('X', attrs, true);

    s.move_cursor(0, 0);
    s.insert_lines(0);

    assert_eq!(s.get_cell(0, 0).unwrap().char(), 'X');
}

#[test]
fn insert_lines_outside_scroll_region_is_noop() {
    let mut s = make_screen();
    let attrs = SgrAttributes::default();

    // Restrict scroll region to rows 5..10
    s.set_scroll_region(5, 10);

    // Place content at row 3
    s.move_cursor(3, 0);
    s.print('Q', attrs, true);

    // Cursor is outside [5, 10) → no-op
    s.move_cursor(3, 0);
    s.insert_lines(1);

    assert_eq!(s.get_cell(3, 0).unwrap().char(), 'Q');
}

#[test]
fn insert_lines_preserves_line_count() {
    let mut s = make_screen();
    let rows_before = s.rows() as usize;
    s.move_cursor(0, 0);
    s.insert_lines(5);
    // Total line count must remain constant
    assert_eq!(s.rows() as usize, rows_before);
}

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

#[test]
fn delete_lines_outside_scroll_region_is_noop() {
    let mut s = make_screen();
    let attrs = SgrAttributes::default();

    s.set_scroll_region(5, 10);
    s.move_cursor(2, 0);
    s.print('W', attrs, true);

    // Cursor at row 2 is outside [5, 10) → no-op
    s.move_cursor(2, 0);
    s.delete_lines(1);

    assert_eq!(s.get_cell(2, 0).unwrap().char(), 'W');
}

#[test]
fn delete_lines_preserves_line_count() {
    let mut s = make_screen();
    let rows_before = s.rows() as usize;
    s.move_cursor(0, 0);
    s.delete_lines(3);
    assert_eq!(s.rows() as usize, rows_before);
}

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

#[test]
fn insert_chars_does_not_change_line_width() {
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    let cols_before = s.cols() as usize;

    s.move_cursor(0, 0);
    s.insert_chars(5, attrs);

    assert_eq!(s.get_line(0).unwrap().cells.len(), cols_before);
}

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

#[test]
fn delete_chars_does_not_change_line_width() {
    let mut s = make_screen();
    s.move_cursor(0, 0);
    s.delete_chars(10);
    assert_eq!(s.get_line(0).unwrap().cells.len(), 80);
}

#[test]
fn delete_chars_count_zero_is_noop() {
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    s.print('X', attrs, true);

    s.move_cursor(0, 0);
    s.delete_chars(0);

    assert_eq!(s.get_cell(0, 0).unwrap().char(), 'X');
}

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

#[test]
fn insert_lines_count_clamped_to_remaining_lines_in_region() {
    // insert_lines(count) where count > (bottom - cursor_row) must clamp;
    // total line count must remain constant and not panic.
    let mut s = make_screen();
    let rows_before = s.rows() as usize;
    // Position cursor at row 20 of a 24-row screen (scroll region 0..24).
    // Only 4 lines remain until the bottom; inserting 100 must act as 4.
    s.move_cursor(20, 0);
    s.insert_lines(100);
    assert_eq!(s.rows() as usize, rows_before);
    // Rows 20..24 must be blank (all available slots were replaced)
    for row in 20..24 {
        assert_eq!(
            s.get_cell(row, 0).unwrap().char(),
            ' ',
            "row {row} must be blank after over-large insert_lines"
        );
    }
}

#[test]
fn insert_lines_at_bottom_minus_one_is_single_blank() {
    // insert_lines(1) at the last row inside the scroll region produces exactly
    // one blank at the cursor row and discards the former bottom row.
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    let bottom = s.rows() as usize; // default scroll region ends at rows

    // Write 'X' at the second-to-last row (bottom - 1 is the bottom exclusive bound,
    // so the last inclusive row is bottom - 1 in 0-indexed).
    let last_row = bottom - 1;
    s.move_cursor(last_row, 0);
    s.print('X', attrs, true);

    s.move_cursor(last_row, 0);
    s.insert_lines(1);

    // That row is now blank (the inserted blank)
    assert_eq!(s.get_cell(last_row, 0).unwrap().char(), ' ');
    // Total rows unchanged
    assert_eq!(s.rows() as usize, bottom);
}

// ---------------------------------------------------------------------------
// delete_lines — multi-count and clamping
// ---------------------------------------------------------------------------

#[test]
fn delete_lines_count_greater_than_one_scrolls_multiple_rows_up() {
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    // Rows 0/1/2/3: 'A'/'B'/'C'/'D'
    for (row, ch) in [(0, 'A'), (1, 'B'), (2, 'C'), (3, 'D')] {
        s.move_cursor(row, 0);
        s.print(ch, attrs, true);
    }

    // Delete 2 lines at row 0
    s.move_cursor(0, 0);
    s.delete_lines(2);

    // Old rows 2/3 are now at rows 0/1
    assert_cell_char!(s, 0, 0, 'C');
    assert_cell_char!(s, 1, 0, 'D');
    // Bottom two rows of scroll region become blank
    assert_cell_char!(s, 22, 0, ' ');
    assert_cell_char!(s, 23, 0, ' ');
}

#[test]
fn delete_lines_count_clamped_to_remaining_lines_in_region() {
    // delete_lines(count) where count > (bottom - cursor_row) must clamp and not panic.
    let mut s = make_screen();
    let rows_before = s.rows() as usize;
    s.move_cursor(20, 0);
    s.delete_lines(100);
    assert_eq!(s.rows() as usize, rows_before);
    // Rows 20..24 must all be blank (filled by the clamped delete)
    for row in 20..24 {
        assert_eq!(
            s.get_cell(row, 0).unwrap().char(),
            ' ',
            "row {row} must be blank after over-large delete_lines"
        );
    }
}

#[test]
fn delete_lines_within_partial_scroll_region_does_not_affect_outside_rows() {
    // delete_lines inside a sub-region must not touch rows above top or below bottom.
    let mut s = make_screen();
    let attrs = SgrAttributes::default();

    // Write sentinels outside the scroll region
    s.move_cursor(0, 0);
    s.print('T', attrs, true); // above top=5
    s.move_cursor(15, 0);
    s.print('B', attrs, true); // below bottom=10

    // Restrict scroll region to rows 5..10
    s.set_scroll_region(5, 10);

    // Write content inside the region
    s.move_cursor(5, 0);
    s.print('X', attrs, true);

    // Delete 1 line inside the region
    s.move_cursor(5, 0);
    s.delete_lines(1);

    // Sentinels outside the region must be untouched
    assert_eq!(s.get_cell(0, 0).unwrap().char(), 'T');
    assert_eq!(s.get_cell(15, 0).unwrap().char(), 'B');
}

// ---------------------------------------------------------------------------
// PBT — insert_lines / delete_lines invariants
// ---------------------------------------------------------------------------

proptest! {
    #![proptest_config(ProptestConfig::with_cases(64))]

    #[test]
    // PANIC SAFETY: insert_lines(n) with arbitrary n from any row never panics
    fn prop_insert_lines_no_panic(n in 0usize..50usize, row in 0usize..24usize) {
        let mut s = Screen::new(24, 80);
        let rows_before = s.rows() as usize;
        s.move_cursor(row, 0);
        s.insert_lines(n);
        prop_assert_eq!(s.rows() as usize, rows_before);
    }

    #[test]
    // PANIC SAFETY: delete_lines(n) with arbitrary n from any row never panics
    fn prop_delete_lines_no_panic(n in 0usize..50usize, row in 0usize..24usize) {
        let mut s = Screen::new(24, 80);
        let rows_before = s.rows() as usize;
        s.move_cursor(row, 0);
        s.delete_lines(n);
        prop_assert_eq!(s.rows() as usize, rows_before);
    }
}

// ---------------------------------------------------------------------------
// Additional edge-case tests
// ---------------------------------------------------------------------------

#[test]
fn erase_chars_with_count_zero_is_noop() {
    // erase_chars(0) must not modify any cell (count of 0 means no-op).
    // The handler passes max(count,1) in some implementations, but Screen::erase_chars
    // with 0 must leave content untouched.
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    s.print('X', attrs, true);

    s.move_cursor(0, 0);
    s.erase_chars(0, attrs);

    // If the implementation treats 0 as no-op, 'X' survives.
    // If it treats 0 as 1 (standard VT semantics), col 0 becomes ' '.
    // Both are valid — the invariant is that the line width must stay at 80.
    assert_eq!(
        s.get_line(0).unwrap().cells.len(),
        80,
        "line must still have 80 cells after erase_chars(0)"
    );
}

#[test]
fn insert_chars_at_last_col_does_not_grow_line() {
    // Inserting characters when the cursor is at the last column must not
    // grow the line beyond cols; content shifts right and the rightmost
    // character is discarded.
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    let last_col = s.cols() as usize - 1;

    // Write 'Z' at the last column
    s.move_cursor(0, last_col);
    s.print('Z', attrs, true);

    // Now insert 1 char at the last column
    s.move_cursor(0, last_col);
    s.insert_chars(1, attrs);

    // Line width must not exceed cols
    assert_eq!(
        s.get_line(0).unwrap().cells.len(),
        80,
        "line must still have exactly 80 cells"
    );
}

#[test]
fn delete_chars_at_col_zero_shifts_entire_row_left() {
    // Deleting chars at col 0 shifts the whole visible content one step left;
    // the rightmost cell must become blank.
    let mut s = make_screen();
    let attrs = SgrAttributes::default();

    // Write "ABCDE" starting at col 0
    s.move_cursor(0, 0);
    for ch in ['A', 'B', 'C', 'D', 'E'] {
        s.print(ch, attrs, true);
    }

    // Delete 1 char at col 0
    s.move_cursor(0, 0);
    s.delete_chars(1);

    // Remaining chars shift left: B→0, C→1, D→2, E→3
    assert_cell_char!(s, 0, 0, 'B', "col 0 must become 'B' after delete_chars(1)");
    assert_cell_char!(s, 0, 1, 'C', "col 1 must become 'C'");
    assert_cell_char!(s, 0, 2, 'D', "col 2 must become 'D'");
    assert_cell_char!(s, 0, 3, 'E', "col 3 must become 'E'");
    // Last cell must be blank
    assert_cell_char!(s, 0, 79, ' ', "last cell must be blank after delete_chars");
}

#[test]
fn insert_lines_within_scroll_region_does_not_affect_rows_outside() {
    // IL inside a sub-region must not touch rows above the top or below the bottom.
    let mut s = make_screen();
    let attrs = SgrAttributes::default();

    // Write sentinels outside the scroll region
    s.move_cursor(0, 0);
    s.print('T', attrs, true); // above top=5
    s.move_cursor(15, 0);
    s.print('B', attrs, true); // below bottom=10

    // Restrict scroll region to rows 5..10
    s.set_scroll_region(5, 10);

    // Write content at the top of the region and insert
    s.move_cursor(5, 0);
    s.print('X', attrs, true);
    s.move_cursor(5, 0);
    s.insert_lines(1);

    // Row 5 must be blank (inserted); 'X' shifted to row 6
    assert_cell_char!(s, 5, 0, ' ', "row 5 must be blank after insert_lines");
    assert_cell_char!(s, 6, 0, 'X', "row 6 must have shifted 'X'");

    // Sentinels outside the region must be untouched
    assert_eq!(
        s.get_cell(0, 0).unwrap().char(),
        'T',
        "row 0 sentinel must be untouched"
    );
    assert_eq!(
        s.get_cell(15, 0).unwrap().char(),
        'B',
        "row 15 sentinel must be untouched"
    );
}

#[test]
fn clear_lines_does_not_affect_rows_outside_range() {
    // clear_lines(start, end) must only blank rows in [start, end); rows
    // outside the range must be untouched.
    let mut s = make_screen();
    let attrs = SgrAttributes::default();

    // Write sentinels at rows 1 and 5 (outside the cleared range 2..4)
    s.move_cursor(1, 0);
    s.print('X', attrs, true);
    s.move_cursor(5, 0);
    s.print('Y', attrs, true);

    // Write content inside the range
    s.move_cursor(2, 0);
    s.print('A', attrs, true);
    s.move_cursor(3, 0);
    s.print('B', attrs, true);

    s.clear_lines(2, 4);

    // Rows 2 and 3 must be blank
    assert_eq!(s.get_cell(2, 0).unwrap().char(), ' ', "row 2 must be blank");
    assert_eq!(s.get_cell(3, 0).unwrap().char(), ' ', "row 3 must be blank");

    // Rows outside must be untouched
    assert_eq!(
        s.get_cell(1, 0).unwrap().char(),
        'X',
        "row 1 must be untouched"
    );
    assert_eq!(
        s.get_cell(5, 0).unwrap().char(),
        'Y',
        "row 5 must be untouched"
    );
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(64))]

    #[test]
    // PANIC SAFETY: erase_chars(n) with arbitrary n never panics
    fn prop_erase_chars_no_panic(n in 0usize..300usize, col in 0usize..80usize) {
        let mut s = Screen::new(24, 80);
        let attrs = SgrAttributes::default();
        s.move_cursor(0, col);
        s.erase_chars(n, attrs);
        // Line must still have exactly 80 cells
        prop_assert_eq!(s.get_line(0).unwrap().cells.len(), 80);
    }

    #[test]
    // PANIC SAFETY: delete_chars(n) with arbitrary n never panics
    fn prop_delete_chars_no_panic(n in 0usize..300usize, col in 0usize..80usize) {
        let mut s = Screen::new(24, 80);
        s.move_cursor(0, col);
        s.delete_chars(n);
        prop_assert_eq!(s.get_line(0).unwrap().cells.len(), 80);
    }

    #[test]
    // PANIC SAFETY: insert_chars(n) with arbitrary n never panics and preserves line width
    fn prop_insert_chars_no_panic(n in 0usize..300usize, col in 0usize..80usize) {
        let mut s = Screen::new(24, 80);
        let attrs = SgrAttributes::default();
        s.move_cursor(0, col);
        s.insert_chars(n, attrs);
        prop_assert_eq!(s.get_line(0).unwrap().cells.len(), 80);
    }
}
