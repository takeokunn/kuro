use crate::grid::dirty_set::DirtySet;
use crate::grid::screen::Screen;
use proptest::prelude::*;

use super::tests_support::*;

#[test]
fn mark_dirty_range_marks_half_open_range() {
    let mut screen = screen();
    screen.mark_dirty_range(3, 7);

    for row in 3..7 {
        assert!(screen.dirty_set.contains(row), "row {row} should be dirty");
    }
    assert!(!screen.dirty_set.contains(2));
    assert!(!screen.dirty_set.contains(7));
}

#[test]
fn mark_dirty_range_empty_range_marks_nothing() {
    let mut screen = screen();
    screen.mark_dirty_range(5, 5);
    assert!(screen.dirty_set.is_empty());
}

#[test]
fn mark_all_dirty_sets_full_dirty_flag() {
    let mut screen = screen();
    assert!(!screen.is_full_dirty());
    screen.mark_all_dirty();
    assert!(screen.is_full_dirty());
}

#[test]
fn take_dirty_lines_full_dirty_returns_all_rows_and_clears() {
    let mut screen = Screen::new(6, COLS);
    screen.mark_all_dirty();

    assert_eq!(screen.take_dirty_lines(), all_rows(6));
    assert!(!screen.is_full_dirty());
    assert!(screen.dirty_set.is_empty());
}

#[test]
fn take_dirty_lines_partial_drains_and_clears() {
    let mut screen = screen();
    screen.dirty_set.insert(2);
    screen.dirty_set.insert(7);

    assert_eq!(screen.take_dirty_lines(), vec![2, 7]);
    assert!(screen.dirty_set.is_empty());
}

#[test]
fn clear_dirty_resets_both_full_dirty_and_set() {
    let mut screen = screen();
    screen.mark_all_dirty();
    screen.dirty_set.insert(5);
    screen.clear_dirty();

    assert!(!screen.is_full_dirty());
    assert!(screen.dirty_set.is_empty());
}

#[test]
fn mark_line_dirty_sets_both_set_and_line_flag() {
    let mut screen = screen();
    screen.mark_line_dirty(3);

    assert!(screen.dirty_set.contains(3));
    assert!(screen.lines[3].is_dirty);
    assert!(!screen.dirty_set.contains(4));
    assert!(!screen.lines[4].is_dirty);
}

#[test]
fn is_full_dirty_reflects_alternate_screen_when_active() {
    let mut screen = screen();
    assert!(!screen.is_full_dirty());

    screen.switch_to_alternate();
    assert!(screen.is_alternate_screen_active());
    assert!(screen.is_full_dirty());

    let _ = screen.take_dirty_lines();
    assert!(!screen.is_full_dirty());

    screen.mark_all_dirty();
    assert!(screen.is_full_dirty());

    screen.switch_to_primary();
    assert!(!screen.is_alternate_screen_active());
    assert!(screen.is_full_dirty());
}

#[test]
fn attach_combining_marks_row_in_dirty_set() {
    let mut screen = clean_screen();
    screen.attach_combining(0, 0, '\u{0301}');
    assert_dirty_rows(&mut screen, &[0]);
}

#[test]
fn attach_combining_out_of_bounds_does_not_panic() {
    let mut screen = screen();
    screen.attach_combining(999, 0, '\u{0301}');
    screen.attach_combining(0, 999, '\u{0301}');
    screen.attach_combining(999, 999, '\u{0301}');
}

#[test]
fn mark_line_dirty_sets_line_flag_and_dirty_row() {
    let mut screen = clean_screen();
    if let Some(line) = screen.get_line_mut(5) {
        line.is_dirty = false;
    }

    screen.mark_line_dirty(5);

    assert!(screen.get_line(5).unwrap().is_dirty);
    assert_dirty_rows(&mut screen, &[5]);
}

#[test]
fn mark_line_dirty_drains_after_take() {
    let mut screen = clean_screen();
    screen.mark_line_dirty(3);
    assert_drained(&mut screen);
}

#[test]
fn mark_line_dirty_multiple_rows_are_reported_once_each() {
    let mut screen = clean_screen();
    for row in [1, 10, 23, 10] {
        screen.mark_line_dirty(row);
    }

    assert_dirty_rows_unordered(&mut screen, &[1, 10, 23]);
}

#[test]
fn clear_dirty_resets_primary_and_allows_new_dirty_rows() {
    let mut screen = screen();
    screen.mark_all_dirty();
    screen.clear_dirty();

    assert!(!screen.is_full_dirty());
    assert_dirty_rows(&mut screen, &[]);

    screen.mark_line_dirty(5);
    assert_dirty_rows(&mut screen, &[5]);
}

#[test]
fn clear_dirty_resets_alternate_screen() {
    let mut screen = screen();
    screen.switch_to_alternate();
    screen.mark_all_dirty();
    assert!(screen.is_full_dirty());

    screen.clear_dirty();

    assert!(!screen.is_full_dirty());
    assert_dirty_rows(&mut screen, &[]);
}

#[test]
fn mark_all_dirty_returns_sorted_rows_and_drains() {
    let mut screen = clean_screen();
    screen.mark_all_dirty();
    assert_eq!(screen.take_dirty_lines(), all_rows(ROWS));
    assert!(screen.take_dirty_lines().is_empty());
}

#[test]
fn take_dirty_lines_into_full_dirty_fills_all_rows_and_drains() {
    let mut screen = Screen::new(4, COLS);
    screen.mark_all_dirty();
    let mut out = Vec::new();

    screen.take_dirty_lines_into(&mut out);
    assert_eq!(out, all_rows(4));

    screen.take_dirty_lines_into(&mut out);
    assert!(out.is_empty());
}

#[test]
fn take_dirty_lines_into_partial_dirty_clears_then_fills_output() {
    let mut screen = Screen::new(8, COLS);
    let _ = screen.take_dirty_lines();
    screen.mark_line_dirty(2);
    screen.mark_line_dirty(5);
    let mut out = vec![99];

    screen.take_dirty_lines_into(&mut out);
    out.sort_unstable();

    assert_eq!(out, vec![2, 5]);
}

#[test]
fn take_dirty_lines_into_clears_after_call() {
    let mut screen = Screen::new(4, COLS);
    screen.mark_all_dirty();
    let mut out = Vec::new();

    screen.take_dirty_lines_into(&mut out);
    assert_eq!(out.len(), 4);

    screen.take_dirty_lines_into(&mut out);
    assert!(out.is_empty());
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(500))]

    #[test]
    fn prop_mark_line_dirty_sets_flag_and_dirty_row(row in 0usize..usize::from(ROWS)) {
        let mut screen = clean_screen();
        screen.mark_line_dirty(row);

        prop_assert!(screen.get_line(row).unwrap().is_dirty);
        prop_assert!(screen.take_dirty_lines().contains(&row));
    }

    #[test]
    fn prop_mark_all_dirty_count(rows in 4u16..=30u16, cols in 10u16..=100u16) {
        let mut screen = Screen::new(rows, cols);
        let _ = screen.take_dirty_lines();

        screen.mark_all_dirty();

        prop_assert_eq!(screen.take_dirty_lines(), all_rows(rows));
    }

    #[test]
    fn prop_attach_combining_in_bounds_marks_row(
        row in 0usize..usize::from(ROWS),
        col in 0usize..usize::from(COLS),
    ) {
        let mut screen = clean_screen();
        screen.attach_combining(row, col, '\u{0301}');

        prop_assert_eq!(screen.rows(), ROWS);
        prop_assert!(screen.take_dirty_lines().contains(&row));
    }

    #[test]
    fn prop_mark_all_dirty_contains_every_row(rows in 4u16..=20u16) {
        let mut screen = Screen::new(rows, COLS);
        let _ = screen.take_dirty_lines();

        screen.mark_all_dirty();
        let dirty = screen.take_dirty_lines();

        for expected_row in 0..usize::from(rows) {
            prop_assert!(dirty.contains(&expected_row));
        }
    }
}
