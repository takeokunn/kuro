use super::tests_support::*;
use crate::types::color::Color;
use crate::Screen;
use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    fn prop_viewport_scroll_up_bounded(
        scrollback_lines in 1usize..50usize,
        scroll_n in 0usize..200usize,
    ) {
        let mut screen = screen_with_scrollback(scrollback_lines);
        screen.viewport_scroll_up(scroll_n);
        prop_assert!(screen.scroll_offset() <= screen.scrollback_line_count);
    }

    #[test]
    fn prop_viewport_scroll_down_bounded(
        scrollback_lines in 1usize..50usize,
        scroll_up_n in 1usize..40usize,
        scroll_down_n in 0usize..200usize,
    ) {
        let mut screen = screen_with_scrollback(scrollback_lines);
        let clamp = scroll_up_n.min(screen.scrollback_line_count);
        screen.viewport_scroll_up(clamp);
        screen.viewport_scroll_down(scroll_down_n);
        prop_assert!(screen.scroll_offset() <= screen.scrollback_line_count);
    }

    #[test]
    fn prop_scroll_dirty_set_on_viewport_scroll(
        scrollback_lines in 1usize..50usize,
        n in 1usize..10usize,
    ) {
        let mut screen = screen_with_scrollback(scrollback_lines);
        screen.clear_scroll_dirty();
        prop_assume!(screen.scroll_offset() == 0);
        screen.viewport_scroll_up(n);
        if screen.scrollback_line_count > 0 {
            prop_assert!(screen.is_scroll_dirty());
        }
    }

    #[test]
    fn prop_set_scrollback_max_trims(
        initial_lines in 10usize..30usize,
        new_max in 1usize..9usize,
    ) {
        let mut screen = screen_with_scrollback(initial_lines);
        prop_assume!(screen.scrollback_line_count > new_max);
        screen.set_scrollback_max_lines(new_max);
        prop_assert!(screen.scrollback_line_count <= new_max);
        prop_assert!(screen.scrollback_buffer.len() <= new_max);
    }

    #[test]
    fn prop_clear_scrollback_empties(count in 0usize..40usize) {
        let mut screen = screen_with_scrollback(count);
        screen.clear_scrollback();
        prop_assert_eq!(screen.scrollback_line_count, 0);
        prop_assert!(screen.scrollback_buffer.is_empty());
    }

    #[test]
    fn prop_alternate_screen_viewport_scroll_up_noop(
        scrollback_lines in 0usize..30usize,
        n in 1usize..20usize,
    ) {
        let mut screen = screen_with_scrollback(scrollback_lines);
        screen.switch_to_alternate();
        let offset_before = screen.scroll_offset();
        screen.clear_scroll_dirty();
        screen.viewport_scroll_up(n);
        prop_assert_eq!(screen.scroll_offset(), offset_before);
        prop_assert!(!screen.is_scroll_dirty());
    }

    #[test]
    fn prop_alternate_screen_viewport_scroll_down_noop(
        scrollback_lines in 0usize..30usize,
        n in 1usize..20usize,
    ) {
        let mut screen = screen_with_scrollback(scrollback_lines);
        screen.switch_to_alternate();
        let offset_before = screen.scroll_offset();
        screen.clear_scroll_dirty();
        screen.viewport_scroll_down(n);
        prop_assert_eq!(screen.scroll_offset(), offset_before);
    }

    #[test]
    fn prop_viewport_scroll_up_exact_offset(
        scrollback_lines in 1usize..50usize,
        n in 0usize..100usize,
    ) {
        let mut screen = screen_with_scrollback(scrollback_lines);
        screen.viewport_scroll_up(n);
        let expected = n.min(screen.scrollback_line_count);
        prop_assert_eq!(screen.scroll_offset(), expected);
    }

    #[test]
    fn prop_viewport_scroll_down_to_zero(
        scrollback_lines in 1usize..50usize,
        n in 1usize..30usize,
    ) {
        let mut screen = screen_with_scrollback(scrollback_lines);
        let up_n = n.min(screen.scrollback_line_count);
        screen.viewport_scroll_up(up_n);
        let offset = screen.scroll_offset();
        screen.viewport_scroll_down(offset);
        prop_assert_eq!(screen.scroll_offset(), 0);
    }

    #[test]
    fn prop_scrollback_grows_monotonically(
        steps in 1usize..30usize,
        max_lines in 5usize..20usize,
    ) {
        let mut screen = make_screen();
        screen.set_scrollback_max_lines(max_lines);
        let mut prev = screen.scrollback_line_count;
        for _ in 0..steps {
            screen.scroll_up(1, Color::Default);
            let curr = screen.scrollback_line_count;
            prop_assert!(curr >= prev);
            prop_assert!(curr <= max_lines);
            prev = curr;
        }
    }
}

#[test]
fn viewport_scroll_cases_update_offset() {
    let cases = [(20, 10, 10, 0), (10, 9999, 0, 10), (20, 5, 9999, 0)];

    for (scrollback_lines, up, down, expected_offset) in cases {
        let mut screen = screen_with_scrollback(scrollback_lines);
        screen.viewport_scroll_up(up);
        if down > 0 {
            screen.viewport_scroll_down(down);
        }

        assert_eq!(screen.scroll_offset(), expected_offset);
    }
}

#[test]
fn clear_scrollback_empties_buffer_but_keeps_offset() {
    let mut screen = screen_with_scrollback(20);
    screen.viewport_scroll_up(10);
    let offset_before = screen.scroll_offset();

    screen.clear_scrollback();

    assert_eq!(screen.scrollback_line_count, 0);
    assert!(screen.scrollback_buffer.is_empty());
    assert_eq!(screen.scroll_offset(), offset_before);
}

#[test]
fn scroll_dirty_flag_starts_clear_and_can_be_reset() {
    let mut screen = screen_with_scrollback(5);
    assert!(!make_screen().is_scroll_dirty());

    screen.viewport_scroll_up(3);
    assert!(screen.is_scroll_dirty());
    screen.clear_scroll_dirty();
    assert!(!screen.is_scroll_dirty());
}

#[test]
fn viewport_scroll_up_noop_at_max_no_dirty() {
    let mut screen = screen_with_scrollback(10);
    screen.viewport_scroll_up(10);
    screen.clear_scroll_dirty();

    screen.viewport_scroll_up(1);

    assert!(!screen.is_scroll_dirty());
}

#[test]
fn viewport_scroll_down_to_zero_marks_full_view_dirty() {
    let mut screen = screen_with_scrollback(20);
    screen.viewport_scroll_up(10);
    let _ = screen.take_dirty_lines();

    screen.viewport_scroll_down(10);

    assert_eq!(screen.take_dirty_lines().len(), DEFAULT_ROWS);
}

#[test]
fn viewport_scroll_down_partial_sets_scroll_dirty() {
    let mut screen = screen_with_scrollback(30);
    screen.viewport_scroll_up(20);
    let _ = screen.take_dirty_lines();
    screen.clear_scroll_dirty();

    screen.viewport_scroll_down(5);

    assert_eq!(screen.scroll_offset(), 15);
    assert!(screen.is_scroll_dirty());
    assert!(screen.take_dirty_lines().len() < DEFAULT_ROWS);
}

#[test]
fn scroll_offset_starts_at_zero() {
    assert_eq!(make_screen().scroll_offset(), 0);
}

#[test]
fn scrollback_limit_cases_trim_or_preserve() {
    let cases = [(10, 3, 3), (5, 100, 5), (15, 0, 0)];

    for (initial_lines, new_max, expected_lines) in cases {
        let mut screen = screen_with_scrollback(initial_lines);

        screen.set_scrollback_max_lines(new_max);

        assert_eq!(screen.scrollback_line_count, expected_lines);
        assert_eq!(screen.scrollback_buffer.len(), expected_lines);
    }
}

#[test]
fn get_scrollback_lines_cases_respect_limit() {
    let cases = [(20, 5, 5), (10, 0, 0), (5, 999, 5)];

    for (scrollback_lines, limit, expected_len) in cases {
        let screen = screen_with_scrollback(scrollback_lines);

        assert_eq!(screen.get_scrollback_lines(limit).len(), expected_len);
    }
}

#[test]
fn get_scrollback_lines_returns_most_recent_first() {
    let screen = screen_with_labeled_scrollback(5, DEFAULT_COLS, &['1', '2', '3']);

    assert_eq!(
        scrollback_chars(&screen, 3),
        vec![Some('3'), Some('2'), Some('1')]
    );
}

#[test]
fn scrollback_evicts_oldest_lines_at_max() {
    let mut screen = screen_with_labeled_scrollback(5, 10, &['1', '2', '3', '4']);
    screen.set_scrollback_max_lines(3);

    assert_eq!(screen.scrollback_line_count, 3);
    assert_eq!(
        scrollback_chars(&screen, 3),
        vec![Some('4'), Some('3'), Some('2')]
    );
}

#[test]
fn viewport_line_cases_map_offsets() {
    let cases = [
        (0, 0, 0, false),
        (0, 0, DEFAULT_ROWS - 1, false),
        (30, 10, DEFAULT_ROWS - 1, true),
        (30, 10, 0, false),
        (5, 5, 0, false),
    ];

    for (scrollback_lines, up, row, expected_some) in cases {
        let mut screen = screen_with_scrollback(scrollback_lines);
        if up > 0 {
            screen.viewport_scroll_up(up);
        }

        assert_eq!(
            screen.get_scrollback_viewport_line(row).is_some(),
            expected_some
        );
    }
}

#[test]
fn get_scrollback_viewport_line_at_full_offset_bottom_row() {
    let mut screen = new_screen(5, 10);
    for _ in 0..5 {
        screen.scroll_up(1, Color::Default);
    }
    screen.viewport_scroll_up(5);

    assert!(screen.get_scrollback_viewport_line(4).is_some());
    assert!(screen.get_scrollback_viewport_line(3).is_none());
}

#[test]
fn alternate_screen_scroll_up_does_not_create_scrollback() {
    let mut screen = make_screen();
    screen.switch_to_alternate();
    for _ in 0..5 {
        screen.scroll_up(1, Color::Default);
    }
    screen.switch_to_primary();

    assert_eq!(screen.scrollback_line_count, 0);
}

assert_scroll_zero_noop!(
    viewport_scroll_up_zero_is_noop,
    |_: &mut Screen| {},
    viewport_scroll_up
);
assert_scroll_zero_noop!(
    viewport_scroll_down_zero_is_noop,
    |s: &mut Screen| {
        s.viewport_scroll_up(5);
    },
    viewport_scroll_down
);

#[test]
fn scrollback_count_cases_track_pushes() {
    let cases = [
        (DEFAULT_ROWS, DEFAULT_COLS, None, 0, 0),
        (DEFAULT_ROWS, DEFAULT_COLS, None, 1, 1),
        (5, 10, Some(4), 4, 4),
    ];

    for (rows, cols, max_lines, pushes, expected_count) in cases {
        let mut screen = new_screen(rows, cols);
        if let Some(max_lines) = max_lines {
            screen.set_scrollback_max_lines(max_lines);
        }

        for _ in 0..pushes {
            screen.scroll_up(1, Color::Default);
        }

        assert_eq!(screen.scrollback_line_count, expected_count);
        assert_eq!(screen.scrollback_buffer.len(), expected_count);
    }
}
