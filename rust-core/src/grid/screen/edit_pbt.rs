// ── PBT tests (merged from tests/unit/grid/screen/edit.rs) ──────────

use proptest::prelude::*;

fn make_screen_pbt() -> Screen {
    Screen::new(24, 80)
}

macro_rules! assert_cell_char_pbt {
    ($screen:expr, $row:expr, $col:expr, $expected:expr) => {
        assert_eq!(
            $screen.get_cell($row, $col).unwrap().char(),
            $expected,
            "expected cell ({}, {}) = {:?}",
            $row,
            $col,
            $expected
        )
    };
    ($screen:expr, $row:expr, $col:expr, $expected:expr, $msg:expr) => {
        assert_eq!(
            $screen.get_cell($row, $col).unwrap().char(),
            $expected,
            $msg
        )
    };
}

macro_rules! assert_preserves_row_count_pbt {
    ($name:ident, $method:ident ( $($arg:expr),* )) => {
        #[test]
        fn $name() {
            let mut s = make_screen_pbt();
            let rows_before = s.rows() as usize;
            s.move_cursor(0, 0);
            s.$method($($arg),*);
            assert_eq!(s.rows() as usize, rows_before);
        }
    };
}

macro_rules! assert_line_width_unchanged_pbt {
    ($name:ident, $method:ident ( $($arg:expr),* )) => {
        #[test]
        fn $name() {
            let mut s = make_screen_pbt();
            s.move_cursor(0, 0);
            s.$method($($arg),*);
            assert_eq!(s.get_line(0).unwrap().cells.len(), 80);
        }
    };
}

macro_rules! assert_outside_scroll_noop_pbt {
    ($name:ident, $row:expr, $ch:expr, $method:ident ( $($arg:expr),* )) => {
        #[test]
        fn $name() {
            let mut s = make_screen_pbt();
            s.set_scroll_region(5, 10);
            s.move_cursor($row, 0);
            s.print($ch, SgrAttributes::default(), true);
            s.move_cursor($row, 0);
            s.$method($($arg),*);
            assert_eq!(s.get_cell($row, 0).unwrap().char(), $ch);
        }
    };
}

macro_rules! assert_count_zero_noop_pbt {
    ($name:ident, $ch:expr, $method:ident ( $($arg:expr),* )) => {
        #[test]
        fn $name() {
            let mut s = make_screen_pbt();
            s.move_cursor(0, 0);
            s.print($ch, SgrAttributes::default(), true);
            s.move_cursor(0, 0);
            s.$method($($arg),*);
            assert_eq!(s.get_cell(0, 0).unwrap().char(), $ch);
        }
    };
}

#[test]
fn pbt_clear_lines_zeroes_range() {
    let mut s = make_screen_pbt();
    s.move_cursor(2, 0);
    s.print('Z', SgrAttributes::default(), true);
    s.clear_lines(2, 3);
    assert_cell_char_pbt!(s, 2, 0, ' ');
}

#[test]
fn pbt_clear_lines_empty_range_is_noop() {
    let mut s = make_screen_pbt();
    s.move_cursor(0, 0);
    s.print('A', SgrAttributes::default(), true);
    s.clear_lines(0, 0);
    assert_eq!(s.get_cell(0, 0).unwrap().char(), 'A');
}

#[test]
fn pbt_clear_lines_clamped_end_beyond_rows() {
    let mut s = make_screen_pbt();
    s.clear_lines(0, 9999);
    assert_eq!(s.get_cell(0, 0).unwrap().char(), ' ');
}

#[test]
fn pbt_insert_lines_shifts_content_down() {
    let mut s = make_screen_pbt();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    s.print('A', attrs, true);
    s.move_cursor(1, 0);
    s.print('B', attrs, true);
    s.move_cursor(0, 0);
    s.insert_lines(1);
    assert_cell_char_pbt!(s, 0, 0, ' ');
    assert_cell_char_pbt!(s, 1, 0, 'A');
    assert_cell_char_pbt!(s, 2, 0, 'B');
}

assert_count_zero_noop_pbt!(pbt_insert_lines_count_zero_is_noop, 'X', insert_lines(0));
assert_outside_scroll_noop_pbt!(
    pbt_insert_lines_outside_scroll_region_is_noop,
    3,
    'Q',
    insert_lines(1)
);
assert_preserves_row_count_pbt!(pbt_insert_lines_preserves_line_count, insert_lines(5));

#[test]
fn pbt_delete_lines_scrolls_content_up() {
    let mut s = make_screen_pbt();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    s.print('A', attrs, true);
    s.move_cursor(1, 0);
    s.print('B', attrs, true);
    s.move_cursor(2, 0);
    s.print('C', attrs, true);
    s.move_cursor(0, 0);
    s.delete_lines(1);
    assert_cell_char_pbt!(s, 0, 0, 'B');
    assert_cell_char_pbt!(s, 1, 0, 'C');
    assert_cell_char_pbt!(s, 23, 0, ' ');
}

assert_outside_scroll_noop_pbt!(
    pbt_delete_lines_outside_scroll_region_is_noop,
    2,
    'W',
    delete_lines(1)
);
assert_preserves_row_count_pbt!(pbt_delete_lines_preserves_line_count, delete_lines(3));

#[test]
fn pbt_insert_chars_shifts_right() {
    let mut s = make_screen_pbt();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    s.print('A', attrs, true);
    s.print('B', attrs, true);
    s.move_cursor(0, 0);
    s.insert_chars(1, attrs);
    assert_cell_char_pbt!(s, 0, 0, ' ');
    assert_cell_char_pbt!(s, 0, 1, 'A');
    assert_cell_char_pbt!(s, 0, 2, 'B');
}

assert_line_width_unchanged_pbt!(
    pbt_insert_chars_does_not_change_line_width,
    insert_chars(5, SgrAttributes::default())
);

#[test]
fn pbt_insert_chars_count_larger_than_remaining_clamps() {
    let mut s = make_screen_pbt();
    s.move_cursor(0, 0);
    s.insert_chars(9999, SgrAttributes::default());
    assert_eq!(s.get_line(0).unwrap().cells.len(), 80);
}

#[test]
fn pbt_delete_chars_shifts_left_and_pads_right() {
    let mut s = make_screen_pbt();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    s.print('A', attrs, true);
    s.print('B', attrs, true);
    s.print('C', attrs, true);
    s.move_cursor(0, 0);
    s.delete_chars(1);
    assert_cell_char_pbt!(s, 0, 0, 'B');
    assert_cell_char_pbt!(s, 0, 1, 'C');
    assert_cell_char_pbt!(s, 0, 79, ' ');
}

assert_line_width_unchanged_pbt!(
    pbt_delete_chars_does_not_change_line_width,
    delete_chars(10)
);
assert_count_zero_noop_pbt!(pbt_delete_chars_count_zero_is_noop, 'X', delete_chars(0));

#[test]
fn pbt_erase_chars_blanks_cells_in_place() {
    let mut s = make_screen_pbt();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    for ch in ['A', 'B', 'C', 'D'] {
        s.print(ch, attrs, true);
    }
    s.move_cursor(0, 1);
    s.erase_chars(2, attrs);
    assert_eq!(s.get_cell(0, 0).unwrap().char(), 'A');
    assert_eq!(s.get_cell(0, 1).unwrap().char(), ' ');
    assert_eq!(s.get_cell(0, 2).unwrap().char(), ' ');
    assert_eq!(s.get_cell(0, 3).unwrap().char(), 'D');
}

#[test]
fn pbt_erase_chars_cursor_does_not_move() {
    let mut s = make_screen_pbt();
    s.move_cursor(0, 5);
    s.erase_chars(3, SgrAttributes::default());
    assert_eq!(s.cursor().col, 5);
}

#[test]
fn pbt_erase_chars_clamped_at_right_margin() {
    let mut s = make_screen_pbt();
    s.move_cursor(0, 78);
    s.erase_chars(9999, SgrAttributes::default());
    assert_eq!(s.get_cell(0, 78).unwrap().char(), ' ');
    assert_eq!(s.get_cell(0, 79).unwrap().char(), ' ');
}

#[test]
fn pbt_insert_lines_count_greater_than_one() {
    let mut s = make_screen_pbt();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    s.print('A', attrs, true);
    s.move_cursor(1, 0);
    s.print('B', attrs, true);
    s.move_cursor(2, 0);
    s.print('C', attrs, true);
    s.move_cursor(0, 0);
    s.insert_lines(2);
    assert_cell_char_pbt!(s, 0, 0, ' ');
    assert_cell_char_pbt!(s, 1, 0, ' ');
    assert_cell_char_pbt!(s, 2, 0, 'A');
    assert_cell_char_pbt!(s, 3, 0, 'B');
    assert_cell_char_pbt!(s, 4, 0, 'C');
}

#[test]
fn pbt_insert_lines_count_clamped_to_remaining() {
    let mut s = make_screen_pbt();
    let rows_before = s.rows() as usize;
    s.move_cursor(20, 0);
    s.insert_lines(100);
    assert_eq!(s.rows() as usize, rows_before);
    for row in 20..24 {
        assert_eq!(s.get_cell(row, 0).unwrap().char(), ' ');
    }
}

#[test]
fn pbt_insert_lines_at_bottom_minus_one() {
    let mut s = make_screen_pbt();
    let attrs = SgrAttributes::default();
    let last_row = s.rows() as usize - 1;
    s.move_cursor(last_row, 0);
    s.print('X', attrs, true);
    s.move_cursor(last_row, 0);
    s.insert_lines(1);
    assert_eq!(s.get_cell(last_row, 0).unwrap().char(), ' ');
}

#[test]
fn pbt_delete_lines_count_greater_than_one() {
    let mut s = make_screen_pbt();
    let attrs = SgrAttributes::default();
    for (row, ch) in [(0, 'A'), (1, 'B'), (2, 'C'), (3, 'D')] {
        s.move_cursor(row, 0);
        s.print(ch, attrs, true);
    }
    s.move_cursor(0, 0);
    s.delete_lines(2);
    assert_cell_char_pbt!(s, 0, 0, 'C');
    assert_cell_char_pbt!(s, 1, 0, 'D');
    assert_cell_char_pbt!(s, 22, 0, ' ');
    assert_cell_char_pbt!(s, 23, 0, ' ');
}

#[test]
fn pbt_delete_lines_count_clamped_to_remaining() {
    let mut s = make_screen_pbt();
    let rows_before = s.rows() as usize;
    s.move_cursor(20, 0);
    s.delete_lines(100);
    assert_eq!(s.rows() as usize, rows_before);
    for row in 20..24 {
        assert_eq!(s.get_cell(row, 0).unwrap().char(), ' ');
    }
}

#[test]
fn pbt_delete_lines_within_partial_scroll_region() {
    let mut s = make_screen_pbt();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    s.print('T', attrs, true);
    s.move_cursor(15, 0);
    s.print('B', attrs, true);
    s.set_scroll_region(5, 10);
    s.move_cursor(5, 0);
    s.print('X', attrs, true);
    s.move_cursor(5, 0);
    s.delete_lines(1);
    assert_eq!(s.get_cell(0, 0).unwrap().char(), 'T');
    assert_eq!(s.get_cell(15, 0).unwrap().char(), 'B');
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(64))]

    #[test]
    fn prop_insert_lines_no_panic(n in 0usize..50usize, row in 0usize..24usize) {
        let mut s = Screen::new(24, 80);
        let rows_before = s.rows() as usize;
        s.move_cursor(row, 0);
        s.insert_lines(n);
        prop_assert_eq!(s.rows() as usize, rows_before);
    }

    #[test]
    fn prop_delete_lines_no_panic(n in 0usize..50usize, row in 0usize..24usize) {
        let mut s = Screen::new(24, 80);
        let rows_before = s.rows() as usize;
        s.move_cursor(row, 0);
        s.delete_lines(n);
        prop_assert_eq!(s.rows() as usize, rows_before);
    }
}

#[test]
fn pbt_erase_chars_with_count_zero_preserves_width() {
    let mut s = make_screen_pbt();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    s.print('X', attrs, true);
    s.move_cursor(0, 0);
    s.erase_chars(0, attrs);
    assert_eq!(s.get_line(0).unwrap().cells.len(), 80);
}

#[test]
fn pbt_insert_chars_at_last_col_does_not_grow_line() {
    let mut s = make_screen_pbt();
    let attrs = SgrAttributes::default();
    let last_col = s.cols() as usize - 1;
    s.move_cursor(0, last_col);
    s.print('Z', attrs, true);
    s.move_cursor(0, last_col);
    s.insert_chars(1, attrs);
    assert_eq!(s.get_line(0).unwrap().cells.len(), 80);
}

#[test]
fn pbt_delete_chars_at_col_zero_shifts_entire_row_left() {
    let mut s = make_screen_pbt();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    for ch in ['A', 'B', 'C', 'D', 'E'] {
        s.print(ch, attrs, true);
    }
    s.move_cursor(0, 0);
    s.delete_chars(1);
    assert_cell_char_pbt!(s, 0, 0, 'B');
    assert_cell_char_pbt!(s, 0, 1, 'C');
    assert_cell_char_pbt!(s, 0, 2, 'D');
    assert_cell_char_pbt!(s, 0, 3, 'E');
    assert_cell_char_pbt!(s, 0, 79, ' ');
}

#[test]
fn pbt_insert_lines_within_scroll_region_does_not_affect_rows_outside() {
    let mut s = make_screen_pbt();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    s.print('T', attrs, true);
    s.move_cursor(15, 0);
    s.print('B', attrs, true);
    s.set_scroll_region(5, 10);
    s.move_cursor(5, 0);
    s.print('X', attrs, true);
    s.move_cursor(5, 0);
    s.insert_lines(1);
    assert_cell_char_pbt!(s, 5, 0, ' ');
    assert_cell_char_pbt!(s, 6, 0, 'X');
    assert_eq!(s.get_cell(0, 0).unwrap().char(), 'T');
    assert_eq!(s.get_cell(15, 0).unwrap().char(), 'B');
}

#[test]
fn pbt_clear_lines_does_not_affect_rows_outside_range() {
    let mut s = make_screen_pbt();
    let attrs = SgrAttributes::default();
    s.move_cursor(1, 0);
    s.print('X', attrs, true);
    s.move_cursor(5, 0);
    s.print('Y', attrs, true);
    s.move_cursor(2, 0);
    s.print('A', attrs, true);
    s.move_cursor(3, 0);
    s.print('B', attrs, true);
    s.clear_lines(2, 4);
    assert_eq!(s.get_cell(2, 0).unwrap().char(), ' ');
    assert_eq!(s.get_cell(3, 0).unwrap().char(), ' ');
    assert_eq!(s.get_cell(1, 0).unwrap().char(), 'X');
    assert_eq!(s.get_cell(5, 0).unwrap().char(), 'Y');
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(64))]

    #[test]
    fn prop_erase_chars_no_panic(n in 0usize..300usize, col in 0usize..80usize) {
        let mut s = Screen::new(24, 80);
        s.move_cursor(0, col);
        s.erase_chars(n, SgrAttributes::default());
        prop_assert_eq!(s.get_line(0).unwrap().cells.len(), 80);
    }

    #[test]
    fn prop_delete_chars_no_panic(n in 0usize..300usize, col in 0usize..80usize) {
        let mut s = Screen::new(24, 80);
        s.move_cursor(0, col);
        s.delete_chars(n);
        prop_assert_eq!(s.get_line(0).unwrap().cells.len(), 80);
    }

    #[test]
    fn prop_insert_chars_no_panic(n in 0usize..300usize, col in 0usize..80usize) {
        let mut s = Screen::new(24, 80);
        s.move_cursor(0, col);
        s.insert_chars(n, SgrAttributes::default());
        prop_assert_eq!(s.get_line(0).unwrap().cells.len(), 80);
    }
}
