//! Unit tests for `Screen` edit methods (edit.rs):
//! `clear_lines`, `insert_lines`, `delete_lines`, `insert_chars`, `delete_chars`, `erase_chars`.

use crate::grid::screen::Screen;
use crate::types::cell::SgrAttributes;
use proptest::prelude::*;

fn make_screen() -> Screen {
    Screen::new(24, 80)
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

    assert_eq!(
        s.get_cell(2, 0).unwrap().char(),
        ' ',
        "clear_lines must blank the target row"
    );
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
    assert_eq!(s.get_cell(0, 0).unwrap().char(), ' ');
    // Old row 0 ('A') shifted to row 1
    assert_eq!(s.get_cell(1, 0).unwrap().char(), 'A');
    // Old row 1 ('B') shifted to row 2
    assert_eq!(s.get_cell(2, 0).unwrap().char(), 'B');
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
    assert_eq!(s.get_cell(0, 0).unwrap().char(), 'B');
    // Old row 2 ('C') moves to row 1
    assert_eq!(s.get_cell(1, 0).unwrap().char(), 'C');
    // Bottom row of scroll region becomes blank
    assert_eq!(s.get_cell(23, 0).unwrap().char(), ' ');
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
    assert_eq!(s.get_cell(0, 0).unwrap().char(), ' ');
    assert_eq!(s.get_cell(0, 1).unwrap().char(), 'A');
    assert_eq!(s.get_cell(0, 2).unwrap().char(), 'B');
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
    assert_eq!(s.get_cell(0, 0).unwrap().char(), 'B');
    assert_eq!(s.get_cell(0, 1).unwrap().char(), 'C');
    assert_eq!(s.get_cell(0, 79).unwrap().char(), ' ');
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
