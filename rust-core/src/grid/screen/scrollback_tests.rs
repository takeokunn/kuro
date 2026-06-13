    use super::*;
    use crate::types::cell::SgrAttributes;
    use crate::types::color::Color;
    use proptest::prelude::*;

    fn make_screen() -> Screen {
        Screen::new(24, 80)
    }

    fn screen_with_scrollback(count: usize) -> Screen {
        let mut screen = Screen::new(24, 80);
        for _ in 0..count {
            screen.scroll_up(1, Color::Default);
        }
        screen
    }

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
    fn test_viewport_scroll_to_live_view() {
        let mut screen = screen_with_scrollback(20);
        screen.viewport_scroll_up(10);
        assert_eq!(screen.scroll_offset(), 10);
        screen.viewport_scroll_down(10);
        assert_eq!(screen.scroll_offset(), 0);
    }

    #[test]
    fn test_viewport_scroll_up_clamps_at_scrollback_count() {
        let mut screen = screen_with_scrollback(10);
        screen.viewport_scroll_up(9999);
        assert_eq!(screen.scroll_offset(), screen.scrollback_line_count);
    }

    #[test]
    fn test_viewport_scroll_down_saturates_at_zero() {
        let mut screen = screen_with_scrollback(20);
        screen.viewport_scroll_up(5);
        screen.viewport_scroll_down(9999);
        assert_eq!(screen.scroll_offset(), 0);
    }

    #[test]
    fn test_clear_scrollback_resets_offset() {
        let mut screen = screen_with_scrollback(20);
        screen.viewport_scroll_up(10);
        screen.clear_scrollback();
        assert_eq!(screen.scrollback_line_count, 0);
        assert!(screen.scrollback_buffer.is_empty());
    }

    #[test]
    fn test_is_scroll_dirty_false_initially() {
        let screen = make_screen();
        assert!(!screen.is_scroll_dirty());
    }

    #[test]
    fn test_clear_scroll_dirty_resets_flag() {
        let mut screen = screen_with_scrollback(5);
        screen.viewport_scroll_up(3);
        assert!(screen.is_scroll_dirty());
        screen.clear_scroll_dirty();
        assert!(!screen.is_scroll_dirty());
    }

    #[test]
    fn test_viewport_scroll_up_noop_at_max_no_dirty() {
        let mut screen = screen_with_scrollback(10);
        screen.viewport_scroll_up(10);
        screen.clear_scroll_dirty();
        screen.viewport_scroll_up(1);
        assert!(!screen.is_scroll_dirty());
    }

    #[test]
    fn test_viewport_scroll_down_to_zero_sets_full_dirty() {
        let mut screen = screen_with_scrollback(20);
        screen.viewport_scroll_up(10);
        let _ = screen.take_dirty_lines();
        screen.viewport_scroll_down(10);
        let dirty = screen.take_dirty_lines();
        assert_eq!(dirty.len(), 24);
    }

    #[test]
    fn test_scroll_offset_accessor_returns_zero_initially() {
        let screen = make_screen();
        assert_eq!(screen.scroll_offset(), 0);
    }

    #[test]
    fn test_set_scrollback_max_lines_trims_immediately() {
        let mut screen = screen_with_scrollback(10);
        assert_eq!(screen.scrollback_line_count, 10);
        screen.set_scrollback_max_lines(3);
        assert_eq!(screen.scrollback_line_count, 3);
        assert_eq!(screen.scrollback_buffer.len(), 3);
    }


    include!("scrollback_tests2.rs");
