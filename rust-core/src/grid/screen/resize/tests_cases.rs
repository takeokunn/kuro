use super::tests_support::make_screen;
use super::*;
use crate::types::cell::SgrAttributes;
use proptest::prelude::*;

#[test]
fn resize_updates_rows_and_cols() {
    let mut s = make_screen();
    s.resize(10, 40);
    assert_eq!(s.rows(), 10);
    assert_eq!(s.cols(), 40);
}

#[test]
fn resize_larger_grows_line_count() {
    let mut s = Screen::new(5, 20);
    s.resize(10, 20);
    assert_eq!(s.rows() as usize, 10);
    assert!(s.get_line(9).is_some());
}

#[test]
fn resize_smaller_shrinks_line_count() {
    let mut s = make_screen();
    s.resize(5, 40);
    assert_eq!(s.rows(), 5);
    assert!(s.get_line(5).is_none());
}

#[test]
fn resize_clamps_cursor_row_when_shrinking() {
    let mut s = make_screen();
    s.move_cursor(23, 0);
    s.resize(10, 80);
    assert!(s.cursor().row < 10);
}

#[test]
fn resize_clamps_cursor_col_when_shrinking() {
    let mut s = make_screen();
    s.move_cursor(0, 79);
    s.resize(24, 30);
    assert!(s.cursor().col < 30);
}

#[test]
fn resize_clears_pending_wrap() {
    let mut s = make_screen();
    s.move_cursor(0, 79);
    s.print('X', SgrAttributes::default(), false);
    s.resize(24, 80);
    assert!(!s.cursor().pending_wrap);
}

#[test]
fn resize_to_1x1_does_not_panic() {
    let mut s = make_screen();
    s.move_cursor(23, 79);
    s.resize(1, 1);
    assert_eq!(s.rows(), 1);
    assert_eq!(s.cols(), 1);
    assert_eq!(s.cursor().row, 0);
    assert_eq!(s.cursor().col, 0);
}

#[test]
fn resize_preserves_content_within_new_bounds() {
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    s.print('A', attrs, true);
    s.move_cursor(1, 1);
    s.print('B', attrs, true);
    s.resize(20, 60);
    assert_cell_char!(s, 0, 0, 'A', "cell (0,0) must survive resize");
    assert_cell_char!(s, 1, 1, 'B', "cell (1,1) must survive resize");
}

#[test]
fn resize_while_alternate_active_updates_both_screens() {
    let mut s = Screen::new(10, 10);
    s.switch_to_alternate();
    s.resize(20, 40);
    assert_eq!(s.rows(), 20);
    assert_eq!(s.cols(), 40);
    s.switch_to_primary();
    assert_eq!(s.rows(), 20);
    assert_eq!(s.cols(), 40);
}

#[test]
fn resize_marks_all_dirty() {
    let mut s = make_screen();
    let _ = s.take_dirty_lines();
    s.resize(30, 100);
    assert!(s.is_full_dirty());
    let dirty = s.take_dirty_lines();
    assert_eq!(dirty.len(), 30);
}

#[test]
fn resize_same_dimensions_marks_dirty() {
    let mut s = make_screen();
    let _ = s.take_dirty_lines();
    s.resize(24, 80);
    assert!(s.is_full_dirty());
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(500))]

    #[test]
    fn prop_resize_updates_dimensions(r in 1u16..=200u16, c in 1u16..=200u16) {
        let mut s = make_screen();
        s.resize(r, c);
        prop_assert_eq!(s.rows(), r);
        prop_assert_eq!(s.cols(), c);
    }

    #[test]
    fn prop_resize_no_panic(r in 1u16..=200u16, c in 1u16..=200u16) {
        let mut s = make_screen();
        s.resize(r, c);
        prop_assert!(s.rows() == r && s.cols() == c);
    }

    #[test]
    fn prop_resize_clamps_cursor_row(new_rows in 1u16..=200u16) {
        let mut s = make_screen();
        s.move_cursor(23, 0);
        s.resize(new_rows, 80);
        prop_assert!(s.cursor().row <= (new_rows - 1) as usize);
    }

    #[test]
    fn prop_resize_clamps_cursor_col(new_cols in 1u16..=200u16) {
        let mut s = make_screen();
        s.move_cursor(0, 79);
        s.resize(24, new_cols);
        prop_assert!(s.cursor().col <= (new_cols - 1) as usize);
    }

    #[test]
    fn prop_resize_clears_pending_wrap(r in 1u16..=200u16, c in 1u16..=200u16) {
        let mut s = make_screen();
        s.cursor_mut().pending_wrap = true;
        s.resize(r, c);
        prop_assert!(!s.cursor().pending_wrap);
    }

    #[test]
    fn prop_resize_line_count_correct(r in 1u16..=100u16, c in 1u16..=100u16) {
        let mut s = make_screen();
        s.resize(r, c);
        prop_assert!(s.get_line((r - 1) as usize).is_some());
        prop_assert!(s.get_line(r as usize).is_none());
    }

    #[test]
    fn prop_resize_preserves_content_within_bounds(
        new_rows in 1u16..=50u16,
        new_cols in 1u16..=50u16,
    ) {
        let mut s = make_screen();
        s.move_cursor(0, 0);
        s.print('K', SgrAttributes::default(), true);
        s.resize(new_rows, new_cols);
        prop_assert_eq!(s.get_cell(0, 0).unwrap().char(), 'K');
    }

    #[test]
    fn prop_resize_marks_all_dirty(r in 1u16..=200u16, c in 1u16..=200u16) {
        let mut s = make_screen();
        let _ = s.take_dirty_lines();
        s.resize(r, c);
        prop_assert!(s.is_full_dirty());
        let dirty = s.take_dirty_lines();
        prop_assert_eq!(dirty.len(), r as usize);
    }
}
