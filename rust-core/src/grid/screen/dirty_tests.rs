#[test]
fn mark_dirty_range_marks_correct_rows() {
    let mut screen = Screen::new(24, 80);
    screen.mark_dirty_range(3, 7); // marks rows 3,4,5,6 (half-open)
    for row in 3..7 {
        assert!(screen.dirty_set.contains(row), "row {row} should be dirty");
    }
    // Rows outside the range must not be dirty
    assert!(!screen.dirty_set.contains(2));
    assert!(!screen.dirty_set.contains(7));
}

#[test]
fn mark_dirty_range_empty_range_marks_nothing() {
    let mut screen = Screen::new(24, 80);
    screen.mark_dirty_range(5, 5); // empty range
    assert!(screen.dirty_set.is_empty());
}

#[test]
fn mark_all_dirty_sets_full_dirty_flag() {
    let mut screen = Screen::new(24, 80);
    assert!(!screen.is_full_dirty());
    screen.mark_all_dirty();
    assert!(screen.is_full_dirty());
}

#[test]
fn take_dirty_lines_full_dirty_returns_all_rows_and_clears() {
    let mut screen = Screen::new(6, 80);
    screen.mark_all_dirty();
    let dirty = screen.take_dirty_lines();
    assert_eq!(dirty, vec![0, 1, 2, 3, 4, 5]);
    // After take, full_dirty must be cleared and dirty_set empty.
    assert!(!screen.is_full_dirty());
    assert!(screen.dirty_set.is_empty());
}

#[test]
fn take_dirty_lines_partial_drains_and_clears() {
    let mut screen = Screen::new(24, 80);
    screen.dirty_set.insert(2);
    screen.dirty_set.insert(7);
    let dirty = screen.take_dirty_lines();
    assert_eq!(dirty, vec![2, 7]);
    // Dirty set must be empty after drain.
    assert!(screen.dirty_set.is_empty());
}

#[test]
fn clear_dirty_resets_both_full_dirty_and_set() {
    let mut screen = Screen::new(24, 80);
    screen.mark_all_dirty();
    screen.dirty_set.insert(5);
    screen.clear_dirty();
    assert!(!screen.is_full_dirty());
    assert!(screen.dirty_set.is_empty());
}

#[test]
fn mark_line_dirty_sets_both_set_and_line_flag() {
    let mut screen = Screen::new(24, 80);
    screen.mark_line_dirty(3);
    assert!(screen.dirty_set.contains(3));
    assert!(screen.lines[3].is_dirty);
    // Other rows must not be affected.
    assert!(!screen.dirty_set.contains(4));
    assert!(!screen.lines[4].is_dirty);
}

#[test]
fn is_full_dirty_reflects_alternate_screen_when_active() {
    let mut screen = Screen::new(24, 80);
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

// ── PBT tests (merged from tests/unit/grid/screen/dirty.rs) ─────────

use proptest::prelude::*;

fn make_screen() -> Screen {
    Screen::new(24, 80)
}

#[test]
fn pbt_attach_combining_marks_row_in_dirty_set() {
    let mut s = make_screen();
    let _ = s.take_dirty_lines();
    s.attach_combining(0, 0, '\u{0301}');
    let dirty = s.take_dirty_lines();
    assert!(dirty.contains(&0));
}

#[test]
fn pbt_attach_combining_oob_row_no_panic() {
    let mut s = make_screen();
    s.attach_combining(999, 0, '\u{0301}');
}

#[test]
fn pbt_attach_combining_oob_col_no_panic() {
    let mut s = make_screen();
    s.attach_combining(0, 999, '\u{0301}');
}

#[test]
fn pbt_attach_combining_oob_both_no_panic() {
    let mut s = make_screen();
    s.attach_combining(999, 999, '\u{0301}');
}

#[test]
fn pbt_mark_line_dirty_sets_line_flag() {
    let mut s = make_screen();
    if let Some(line) = s.get_line_mut(5) {
        line.is_dirty = false;
    }
    s.mark_line_dirty(5);
    assert!(s.get_line(5).unwrap().is_dirty);
}

#[test]
fn pbt_mark_line_dirty_appears_in_dirty_set() {
    let mut s = make_screen();
    let _ = s.take_dirty_lines();
    s.mark_line_dirty(7);
    let dirty = s.take_dirty_lines();
    assert!(dirty.contains(&7));
}

#[test]
fn pbt_mark_line_dirty_drain_on_take() {
    let mut s = make_screen();
    s.mark_line_dirty(3);
    let first = s.take_dirty_lines();
    assert!(first.contains(&3));
    let second = s.take_dirty_lines();
    assert!(!second.contains(&3));
}

#[test]
fn pbt_mark_line_dirty_multiple_rows() {
    let mut s = make_screen();
    let _ = s.take_dirty_lines();
    s.mark_line_dirty(1);
    s.mark_line_dirty(10);
    s.mark_line_dirty(23);
    let dirty = s.take_dirty_lines();
    assert!(dirty.contains(&1));
    assert!(dirty.contains(&10));
    assert!(dirty.contains(&23));
}

#[test]
fn pbt_mark_line_dirty_idempotent() {
    let mut s = make_screen();
    let _ = s.take_dirty_lines();
    s.mark_line_dirty(4);
    s.mark_line_dirty(4);
    let dirty = s.take_dirty_lines();
    assert!(dirty.contains(&4));
}

#[test]
fn pbt_clear_dirty_resets_full_dirty() {
    let mut s = make_screen();
    s.mark_all_dirty();
    assert!(s.is_full_dirty());
    s.clear_dirty();
    assert!(!s.is_full_dirty());
}

#[test]
fn pbt_clear_dirty_empties_dirty_set() {
    let mut s = make_screen();
    s.mark_line_dirty(3);
    s.mark_line_dirty(7);
    s.clear_dirty();
    let dirty = s.take_dirty_lines();
    assert!(dirty.is_empty());
}

#[test]
fn pbt_clear_dirty_then_mark_line_dirty_works() {
    let mut s = make_screen();
    s.mark_all_dirty();
    s.clear_dirty();
    s.mark_line_dirty(5);
    let dirty = s.take_dirty_lines();
    assert_eq!(dirty, vec![5]);
}

#[test]
fn pbt_clear_dirty_on_alternate_screen() {
    let mut s = make_screen();
    s.switch_to_alternate();
    s.mark_all_dirty();
    assert!(s.is_full_dirty());
    s.clear_dirty();
    assert!(!s.is_full_dirty());
    let dirty = s.take_dirty_lines();
    assert!(dirty.is_empty());
}

#[test]
fn pbt_mark_all_dirty_returns_all_rows() {
    let mut s = make_screen();
    let _ = s.take_dirty_lines();
    s.mark_all_dirty();
    let dirty = s.take_dirty_lines();
    assert_eq!(dirty.len(), 24);
}

#[test]
fn pbt_mark_all_dirty_result_sorted() {
    let mut s = make_screen();
    let _ = s.take_dirty_lines();
    s.mark_all_dirty();
    let dirty = s.take_dirty_lines();
    let expected: Vec<usize> = (0..24).collect();
    assert_eq!(dirty, expected);
}

#[test]
fn pbt_mark_all_dirty_drain_on_take() {
    let mut s = make_screen();
    s.mark_all_dirty();
    let first = s.take_dirty_lines();
    assert_eq!(first.len(), 24);
    let second = s.take_dirty_lines();
    assert!(second.is_empty());
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(500))]

    #[test]
    fn prop_mark_line_dirty_no_panic(row in 0usize..24usize) {
        let mut s = Screen::new(24, 80);
        s.mark_line_dirty(row);
        prop_assert!(s.get_line(row).unwrap().is_dirty);
    }

    #[test]
    fn prop_mark_line_dirty_in_dirty_set(row in 0usize..24usize) {
        let mut s = Screen::new(24, 80);
        let _ = s.take_dirty_lines();
        s.mark_line_dirty(row);
        let dirty = s.take_dirty_lines();
        prop_assert!(dirty.contains(&row));
    }

    #[test]
    fn prop_mark_all_dirty_count(rows in 4u16..=30u16, cols in 10u16..=100u16) {
        let mut s = Screen::new(rows, cols);
        let _ = s.take_dirty_lines();
        s.mark_all_dirty();
        let dirty = s.take_dirty_lines();
        prop_assert_eq!(dirty.len(), rows as usize);
    }

    #[test]
    fn prop_attach_combining_in_bounds_no_panic(
        row in 0usize..24usize,
        col in 0usize..80usize,
    ) {
        let mut s = Screen::new(24, 80);
        s.attach_combining(row, col, '\u{0301}');
        prop_assert_eq!(s.rows(), 24u16);
    }

    #[test]
    fn prop_attach_combining_row_in_dirty_set(
        row in 0usize..24usize,
        col in 0usize..80usize,
    ) {
        let mut s = Screen::new(24, 80);
        let _ = s.take_dirty_lines();
        s.attach_combining(row, col, '\u{0301}');
        let dirty = s.take_dirty_lines();
        prop_assert!(dirty.contains(&row));
    }

    #[test]
    fn prop_mark_all_dirty_contains_every_row(rows in 4u16..=20u16) {
        let mut s = Screen::new(rows, 80);
        let _ = s.take_dirty_lines();
        s.mark_all_dirty();
        let dirty = s.take_dirty_lines();
        for expected_row in 0..rows as usize {
            prop_assert!(dirty.contains(&expected_row));
        }
    }
}
