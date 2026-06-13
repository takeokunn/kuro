use super::*;
use crate::types::cell::SgrAttributes;
use crate::types::color::Color;
use proptest::prelude::*;

fn make_screen() -> Screen {
    Screen::new(24, 80)
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    fn prop_scroll_up_no_panic(n in 0usize..50usize) {
        let mut screen = make_screen();
        screen.scroll_up(n, Color::Default);
        prop_assert_eq!(screen.rows(), 24);
        prop_assert_eq!(screen.cols(), 80);
    }

    #[test]
    fn prop_scroll_down_no_panic(n in 0usize..50usize) {
        let mut screen = make_screen();
        screen.scroll_down(n, Color::Default);
        prop_assert_eq!(screen.rows(), 24);
        prop_assert_eq!(screen.cols(), 80);
    }

    #[test]
    fn prop_scroll_up_preserves_line_count(n in 0usize..50usize) {
        let mut screen = make_screen();
        let rows_before = screen.rows() as usize;
        screen.scroll_up(n, Color::Default);
        prop_assert_eq!(screen.rows() as usize, rows_before);
    }

    #[test]
    fn prop_scroll_down_preserves_line_count(n in 0usize..50usize) {
        let mut screen = make_screen();
        let rows_before = screen.rows() as usize;
        screen.scroll_down(n, Color::Default);
        prop_assert_eq!(screen.rows() as usize, rows_before);
    }

    #[test]
    fn prop_full_screen_scroll_up_sets_full_dirty(n in 1usize..10usize) {
        let mut screen = make_screen();
        prop_assert_eq!(screen.get_scroll_region().top, 0);
        prop_assert_eq!(screen.get_scroll_region().bottom, 24);
        screen.scroll_up(n, Color::Default);
        let dirty = screen.take_dirty_lines();
        prop_assert_eq!(dirty.len(), 24);
    }

    #[test]
    fn prop_full_screen_scroll_down_sets_full_dirty(n in 1usize..10usize) {
        let mut screen = make_screen();
        screen.scroll_down(n, Color::Default);
        let dirty = screen.take_dirty_lines();
        prop_assert_eq!(dirty.len(), 24);
    }

    #[test]
    fn prop_consume_scroll_events_resets(n in 0usize..20usize) {
        let mut screen = make_screen();
        screen.scroll_up(n, Color::Default);
        let _ = screen.consume_scroll_events();
        let (up2, down2) = screen.consume_scroll_events();
        prop_assert_eq!(up2, 0);
        prop_assert_eq!(down2, 0);
    }

    #[test]
    fn prop_consume_scroll_events_idempotent(
        n_up in 0usize..15usize,
        n_down in 0usize..15usize,
    ) {
        let mut screen = make_screen();
        screen.scroll_up(n_up, Color::Default);
        screen.scroll_down(n_down, Color::Default);
        screen.consume_scroll_events();
        for _ in 0..3 {
            let (up, down) = screen.consume_scroll_events();
            prop_assert_eq!(up, 0);
            prop_assert_eq!(down, 0);
        }
    }

    #[test]
    fn prop_set_scroll_region_stores_values(
        top in 0usize..12usize,
        bottom in 13usize..24usize,
    ) {
        let mut screen = make_screen();
        screen.set_scroll_region(top, bottom);
        let region = screen.get_scroll_region();
        prop_assert_eq!(region.top, top);
        prop_assert_eq!(region.bottom, bottom);
    }

    #[test]
    fn prop_scroll_up_over_rows_no_panic(n in 24usize..100usize) {
        let mut screen = make_screen();
        screen.scroll_up(n, Color::Default);
        prop_assert_eq!(screen.rows() as usize, 24);
    }

    #[test]
    fn prop_scroll_up_cursor_row_in_bounds(n in 0usize..50usize) {
        let mut screen = make_screen();
        screen.move_cursor(23, 0);
        screen.scroll_up(n, Color::Default);
        prop_assert!(screen.cursor().row < screen.rows() as usize);
    }

    #[test]
    fn prop_scroll_up_grows_scrollback(n in 1usize..25usize) {
        let mut screen = make_screen();
        let before = screen.scrollback_line_count;
        screen.scroll_up(n, Color::Default);
        let added = n.min(screen.rows() as usize);
        prop_assert_eq!(screen.scrollback_line_count, before + added);
    }
}

#[test]
fn test_scroll_up_one_blank_line_at_bottom() {
    let mut screen = make_screen();
    let attrs = SgrAttributes::default();
    screen.move_cursor(23, 0);
    for _ in 0..80 {
        screen.print('Z', attrs, false);
    }
    assert_eq!(screen.get_cell(23, 0).unwrap().char(), 'Z');
    screen.scroll_up(1, Color::Default);
    assert_eq!(screen.get_cell(23, 0).unwrap().char(), ' ');
}

#[test]
fn test_scroll_down_one_blank_line_at_top() {
    let mut screen = make_screen();
    let attrs = SgrAttributes::default();
    screen.move_cursor(0, 0);
    screen.print('A', attrs, false);
    screen.scroll_down(1, Color::Default);
    assert_eq!(screen.get_cell(0, 0).unwrap().char(), ' ');
}

#[test]
fn test_consume_scroll_events_returns_zero_zero() {
    let mut screen = make_screen();
    screen.scroll_up(5, Color::Default);
    let (up, down) = screen.consume_scroll_events();
    assert_eq!(up, 0);
    assert_eq!(down, 0);
}

#[test]
fn test_consume_scroll_events_second_call_always_zero() {
    let mut screen = make_screen();
    screen.scroll_up(3, Color::Default);
    screen.consume_scroll_events();
    let (up, down) = screen.consume_scroll_events();
    assert_eq!(up, 0);
    assert_eq!(down, 0);
}

#[test]
fn test_set_scroll_region_and_get_roundtrip() {
    let mut screen = make_screen();
    screen.set_scroll_region(5, 18);
    let region = screen.get_scroll_region();
    assert_eq!(region.top, 5);
    assert_eq!(region.bottom, 18);
}

#[test]
fn test_scroll_up_zero_is_noop() {
    let mut screen = make_screen();
    let attrs = SgrAttributes::default();
    screen.move_cursor(0, 0);
    screen.print('Q', attrs, false);
    screen.scroll_up(0, Color::Default);
    assert_eq!(screen.get_cell(0, 0).unwrap().char(), 'Q');
}

#[test]
fn test_scroll_region_scroll_up_does_not_affect_outside_rows() {
    let mut screen = make_screen();
    let attrs = SgrAttributes::default();
    screen.move_cursor(0, 0);
    screen.print('S', attrs, false);
    screen.move_cursor(23, 0);
    screen.print('E', attrs, false);
    screen.set_scroll_region(10, 20);
    screen.scroll_up(1, Color::Default);
    assert_eq!(screen.get_cell(0, 0).unwrap().char(), 'S');
    assert_eq!(screen.get_cell(23, 0).unwrap().char(), 'E');
}

#[test]
fn test_full_dirty_is_set_after_full_screen_scroll_up() {
    let mut screen = make_screen();
    assert_eq!(screen.take_dirty_lines().len(), 0);
    screen.scroll_up(1, Color::Default);
    let dirty = screen.take_dirty_lines();
    assert_eq!(dirty.len(), 24);
}

#[test]
fn test_full_dirty_cleared_by_take_dirty_lines() {
    let mut screen = make_screen();
    screen.scroll_up(1, Color::Default);
    let dirty = screen.take_dirty_lines();
    assert_eq!(dirty.len(), 24);
    let dirty2 = screen.take_dirty_lines();
    assert!(dirty2.is_empty());
}
