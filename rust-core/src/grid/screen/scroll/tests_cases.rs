use super::tests_support::*;
use crate::types::color::Color;
use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    fn prop_scroll_up_no_panic(n in 0usize..50usize) {
        let mut screen = screen();
        screen.scroll_up(n, Color::Default);
        assert_size_is_stable(&screen);
    }

    #[test]
    fn prop_scroll_down_no_panic(n in 0usize..50usize) {
        let mut screen = screen();
        screen.scroll_down(n, Color::Default);
        assert_size_is_stable(&screen);
    }

    #[test]
    fn prop_scroll_up_preserves_line_count(n in 0usize..50usize) {
        let mut screen = screen();
        let rows_before = screen.rows();
        screen.scroll_up(n, Color::Default);
        prop_assert_eq!(screen.rows(), rows_before);
    }

    #[test]
    fn prop_scroll_down_preserves_line_count(n in 0usize..50usize) {
        let mut screen = screen();
        let rows_before = screen.rows();
        screen.scroll_down(n, Color::Default);
        prop_assert_eq!(screen.rows(), rows_before);
    }

    #[test]
    fn prop_full_screen_scroll_up_marks_only_exposed_rows_dirty(n in 1usize..10usize) {
        let mut screen = screen();
        prop_assert_eq!(screen.get_scroll_region().top, 0);
        prop_assert_eq!(screen.get_scroll_region().bottom, ROWS as usize);
        screen.scroll_up(n, Color::Default);
        // The viewport shift is transmitted via pending_scroll_up; only the
        // blank rows exposed at the bottom need a repaint.
        prop_assert_eq!(dirty_count_after(screen), n);
    }

    #[test]
    fn prop_full_screen_scroll_up_accumulates_pending_events(n in 1usize..10usize) {
        let mut screen = screen();
        screen.scroll_up(n, Color::Default);
        prop_assert_eq!(screen.consume_scroll_events(), (n as u32, 0));
    }

    #[test]
    fn prop_full_screen_scroll_down_marks_only_exposed_rows_dirty(n in 1usize..10usize) {
        let mut screen = screen();
        screen.scroll_down(n, Color::Default);
        prop_assert_eq!(dirty_count_after(screen), n);
    }

    #[test]
    fn prop_full_screen_scroll_down_accumulates_pending_events(n in 1usize..10usize) {
        let mut screen = screen();
        screen.scroll_down(n, Color::Default);
        prop_assert_eq!(screen.consume_scroll_events(), (0, n as u32));
    }

    #[test]
    fn prop_consume_scroll_events_resets(n in 0usize..20usize) {
        let mut screen = screen();
        screen.scroll_up(n, Color::Default);
        let (_, second) = consume_twice(&mut screen);
        prop_assert_eq!(second, (0, 0));
    }

    #[test]
    fn prop_consume_scroll_events_idempotent(
        n_up in 0usize..15usize,
        n_down in 0usize..15usize,
    ) {
        let mut screen = screen();
        screen.scroll_up(n_up, Color::Default);
        screen.scroll_down(n_down, Color::Default);
        screen.consume_scroll_events();

        for _ in 0..3 {
            prop_assert_eq!(screen.consume_scroll_events(), (0, 0));
        }
    }

    #[test]
    fn prop_set_scroll_region_stores_values(
        top in 0usize..12usize,
        bottom in 13usize..24usize,
    ) {
        let mut screen = screen();
        screen.set_scroll_region(top, bottom);
        let region = screen.get_scroll_region();
        prop_assert_eq!(region.top, top);
        prop_assert_eq!(region.bottom, bottom);
    }

    #[test]
    fn prop_scroll_up_over_rows_no_panic(n in ROWS as usize..100usize) {
        let mut screen = screen();
        screen.scroll_up(n, Color::Default);
        prop_assert_eq!(screen.rows(), ROWS);
    }

    #[test]
    fn prop_scroll_up_cursor_row_in_bounds(n in 0usize..50usize) {
        let mut screen = screen();
        screen.move_cursor(LAST_ROW, 0);
        screen.scroll_up(n, Color::Default);
        prop_assert!(screen.cursor().row < screen.rows() as usize);
    }

    #[test]
    fn prop_scroll_up_grows_scrollback(n in 1usize..25usize) {
        let mut screen = screen();
        let before = screen.scrollback_line_count;
        screen.scroll_up(n, Color::Default);
        let added = n.min(screen.rows() as usize);
        prop_assert_eq!(screen.scrollback_line_count, before + added);
    }
}

#[test]
fn scroll_up_adds_blank_line_at_bottom() {
    let mut screen = screen();
    put_char(&mut screen, LAST_ROW, 0, 'Z');
    assert_eq!(screen.get_cell(LAST_ROW, 0).unwrap().char(), 'Z');

    screen.scroll_up(1, Color::Default);

    assert_eq!(screen.get_cell(LAST_ROW, 0).unwrap().char(), ' ');
}

#[test]
fn scroll_down_adds_blank_line_at_top() {
    let mut screen = screen();
    put_char(&mut screen, 0, 0, 'A');

    screen.scroll_down(1, Color::Default);

    assert_eq!(screen.get_cell(0, 0).unwrap().char(), ' ');
}

#[test]
fn consume_scroll_events_returns_accumulated_full_screen_scroll_up() {
    let mut screen = screen();
    screen.scroll_up(5, Color::Default);

    assert_eq!(screen.consume_scroll_events(), (5, 0));
}

/// Opposite-direction scrolls cannot be replayed from aggregate counters
/// (the blank-row edge depends on the order), so an interleave degrades to
/// a full repaint with both counters discarded.
#[test]
fn consume_scroll_events_opposite_directions_degrade_to_full_dirty() {
    let mut screen = screen();
    screen.scroll_up(2, Color::Default);
    screen.scroll_down(1, Color::Default);

    assert_eq!(screen.consume_scroll_events(), (0, 0));
    assert!(screen.is_full_dirty());
}

/// Same-direction scrolls accumulate additively across calls.
#[test]
fn consume_scroll_events_same_direction_accumulates() {
    let mut screen = screen();
    screen.scroll_up(2, Color::Default);
    screen.scroll_up(3, Color::Default);

    assert_eq!(screen.consume_scroll_events(), (5, 0));
    assert!(!screen.is_full_dirty());
}

#[test]
fn consume_scroll_events_second_call_is_zero_zero() {
    let mut screen = screen();
    screen.scroll_up(3, Color::Default);

    let (_, second) = consume_twice(&mut screen);

    assert_eq!(second, (0, 0));
}

#[test]
fn set_scroll_region_roundtrips() {
    let mut screen = screen();
    screen.set_scroll_region(5, 18);

    let region = screen.get_scroll_region();

    assert_eq!(region.top, 5);
    assert_eq!(region.bottom, 18);
}

#[test]
fn scroll_up_zero_is_noop() {
    let mut screen = screen();
    put_char(&mut screen, 0, 0, 'Q');

    screen.scroll_up(0, Color::Default);

    assert_eq!(screen.get_cell(0, 0).unwrap().char(), 'Q');
}

#[test]
fn scroll_region_scroll_up_does_not_affect_outside_rows() {
    let mut screen = screen();
    put_char(&mut screen, 0, 0, 'S');
    put_char(&mut screen, LAST_ROW, 0, 'E');
    set_middle_region(&mut screen);

    screen.scroll_up(1, Color::Default);

    assert_eq!(screen.get_cell(0, 0).unwrap().char(), 'S');
    assert_eq!(screen.get_cell(LAST_ROW, 0).unwrap().char(), 'E');
}

/// Regression: a huge scroll count on a *partial* scroll region must be clamped
/// to the region height. Before the fix the partial path looped `for _ in 0..n`
/// with the raw vte param (up to 65535+), heap-allocating a blank line and doing
/// a VecDeque remove+insert each iteration — an amplification DoS that froze the
/// synchronous module call. Clamping keeps the result identical (the region is
/// fully blanked) while bounding the work. This test would hang pre-fix.
#[test]
fn partial_region_scroll_up_clamps_huge_count() {
    let mut screen = screen();
    put_char(&mut screen, 0, 0, 'S'); // outside region (above)
    put_char(&mut screen, 10, 0, 'X'); // inside region
    put_char(&mut screen, LAST_ROW, 0, 'E'); // outside region (below)
    set_middle_region(&mut screen); // region rows 10..20

    screen.scroll_up(1_000_000, Color::Default);

    // Region fully blanked, outside rows untouched, geometry stable.
    assert_eq!(screen.get_cell(10, 0).unwrap().char(), ' ');
    assert_eq!(screen.get_cell(0, 0).unwrap().char(), 'S');
    assert_eq!(screen.get_cell(LAST_ROW, 0).unwrap().char(), 'E');
    assert_size_is_stable(&screen);
}

/// Regression: same clamp for `scroll_down` on a partial region.
#[test]
fn partial_region_scroll_down_clamps_huge_count() {
    let mut screen = screen();
    put_char(&mut screen, 0, 0, 'S');
    put_char(&mut screen, 15, 0, 'X');
    put_char(&mut screen, LAST_ROW, 0, 'E');
    set_middle_region(&mut screen);

    screen.scroll_down(1_000_000, Color::Default);

    assert_eq!(screen.get_cell(15, 0).unwrap().char(), ' ');
    assert_eq!(screen.get_cell(0, 0).unwrap().char(), 'S');
    assert_eq!(screen.get_cell(LAST_ROW, 0).unwrap().char(), 'E');
    assert_size_is_stable(&screen);
}

#[test]
fn full_screen_scroll_up_marks_exposed_bottom_row_dirty() {
    let mut screen = screen();
    assert_eq!(screen.take_dirty_lines().len(), 0);

    screen.scroll_up(1, Color::Default);

    // Only the newly exposed blank bottom row is dirty; the viewport shift
    // itself travels via pending_scroll_up (see consume_scroll_events).
    assert_eq!(screen.take_dirty_lines(), vec![ROWS as usize - 1]);
}

#[test]
fn scroll_dirty_rows_cleared_by_take_dirty_lines() {
    let mut screen = screen();
    screen.scroll_up(1, Color::Default);

    assert_eq!(screen.take_dirty_lines().len(), 1);
    assert!(screen.take_dirty_lines().is_empty());
}
