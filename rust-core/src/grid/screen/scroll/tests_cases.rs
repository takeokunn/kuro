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
    fn prop_full_screen_scroll_up_sets_full_dirty(n in 1usize..10usize) {
        let mut screen = screen();
        prop_assert_eq!(screen.get_scroll_region().top, 0);
        prop_assert_eq!(screen.get_scroll_region().bottom, ROWS as usize);
        screen.scroll_up(n, Color::Default);
        prop_assert_eq!(dirty_count_after(screen), ROWS as usize);
    }

    #[test]
    fn prop_full_screen_scroll_down_sets_full_dirty(n in 1usize..10usize) {
        let mut screen = screen();
        screen.scroll_down(n, Color::Default);
        prop_assert_eq!(dirty_count_after(screen), ROWS as usize);
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
fn consume_scroll_events_returns_zero_zero() {
    let mut screen = screen();
    screen.scroll_up(5, Color::Default);

    assert_eq!(screen.consume_scroll_events(), (0, 0));
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

#[test]
fn full_dirty_is_set_after_full_screen_scroll_up() {
    let mut screen = screen();
    assert_eq!(screen.take_dirty_lines().len(), 0);

    screen.scroll_up(1, Color::Default);

    assert_eq!(screen.take_dirty_lines().len(), ROWS as usize);
}

#[test]
fn full_dirty_cleared_by_take_dirty_lines() {
    let mut screen = screen();
    screen.scroll_up(1, Color::Default);

    assert_eq!(screen.take_dirty_lines().len(), ROWS as usize);
    assert!(screen.take_dirty_lines().is_empty());
}
