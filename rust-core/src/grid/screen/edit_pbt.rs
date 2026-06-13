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


include!("edit_pbt2.rs");
