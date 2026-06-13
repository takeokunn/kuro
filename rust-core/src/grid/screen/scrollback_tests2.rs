    #[test]
    fn test_set_scrollback_max_larger_than_current_no_trim() {
        let mut screen = screen_with_scrollback(5);
        screen.set_scrollback_max_lines(100);
        assert_eq!(screen.scrollback_line_count, 5);
    }

    #[test]
    fn test_get_scrollback_lines_order_most_recent_first() {
        let mut screen = Screen::new(5, 80);
        let attrs = SgrAttributes::default();
        for ch in ['1', '2', '3'] {
            screen.move_cursor(0, 0);
            screen.print(ch, attrs, false);
            screen.scroll_up(1, Color::Default);
        }
        let lines = screen.get_scrollback_lines(3);
        assert_eq!(lines.len(), 3);
        assert_eq!(
            lines[0].get_cell(0).map(crate::types::cell::Cell::char),
            Some('3')
        );
        assert_eq!(
            lines[1].get_cell(0).map(crate::types::cell::Cell::char),
            Some('2')
        );
        assert_eq!(
            lines[2].get_cell(0).map(crate::types::cell::Cell::char),
            Some('1')
        );
    }

    #[test]
    fn test_viewport_scroll_down_partial_sets_scroll_dirty() {
        let mut screen = screen_with_scrollback(30);
        screen.viewport_scroll_up(20);
        let _ = screen.take_dirty_lines();
        screen.clear_scroll_dirty();
        screen.viewport_scroll_down(5);
        assert_eq!(screen.scroll_offset(), 15);
        assert!(screen.is_scroll_dirty());
        let dirty = screen.take_dirty_lines();
        assert!(dirty.len() < 24);
    }

    // ── get_scrollback_viewport_line ────────────────────────────────────

    #[test]
    fn test_get_scrollback_viewport_line_empty_returns_none() {
        let screen = make_screen();
        assert!(screen.get_scrollback_viewport_line(0).is_none());
        assert!(screen.get_scrollback_viewport_line(23).is_none());
    }

    #[test]
    fn test_get_scrollback_viewport_line_scrolled_returns_some() {
        let mut screen = screen_with_scrollback(30);
        screen.viewport_scroll_up(10);
        assert!(screen.get_scrollback_viewport_line(23).is_some());
        assert!(screen.get_scrollback_viewport_line(0).is_none());
    }

    #[test]
    fn test_get_scrollback_viewport_line_out_of_range_returns_none() {
        let mut screen = screen_with_scrollback(5);
        screen.viewport_scroll_up(5);
        assert!(screen.get_scrollback_viewport_line(0).is_none());
    }

    #[test]
    fn test_alternate_screen_scroll_up_no_scrollback() {
        let mut screen = make_screen();
        screen.switch_to_alternate();
        for _ in 0..5 {
            screen.scroll_up(1, Color::Default);
        }
        screen.switch_to_primary();
        assert_eq!(screen.scrollback_line_count, 0);
    }

    #[test]
    fn test_scrollback_evicts_oldest_lines_at_max() {
        let mut screen = Screen::new(5, 10);
        screen.set_scrollback_max_lines(3);
        let attrs = SgrAttributes::default();
        for ch in ['1', '2', '3', '4'] {
            screen.move_cursor(0, 0);
            screen.print(ch, attrs, false);
            screen.scroll_up(1, Color::Default);
        }
        assert_eq!(screen.scrollback_line_count, 3);
        let lines = screen.get_scrollback_lines(3);
        assert_eq!(
            lines[0].get_cell(0).map(crate::types::cell::Cell::char),
            Some('4')
        );
        let has_1 = lines
            .iter()
            .any(|l| l.get_cell(0).map(crate::types::cell::Cell::char) == Some('1'));
        assert!(!has_1);
    }

    macro_rules! assert_scroll_zero_noop {
        ($name:ident, $setup:expr, $call:ident) => {
            #[test]
            fn $name() {
                let mut screen = screen_with_scrollback(10);
                $setup(&mut screen);
                screen.clear_scroll_dirty();
                let offset_before = screen.scroll_offset();
                screen.$call(0);
                assert_eq!(screen.scroll_offset(), offset_before);
                assert!(!screen.is_scroll_dirty());
            }
        };
    }

    assert_scroll_zero_noop!(
        test_viewport_scroll_up_zero_is_noop,
        |_: &mut Screen| {},
        viewport_scroll_up
    );
    assert_scroll_zero_noop!(
        test_viewport_scroll_down_zero_is_noop,
        |s: &mut Screen| {
            s.viewport_scroll_up(5);
        },
        viewport_scroll_down
    );

    #[test]
    fn test_set_scrollback_max_zero_clears_all() {
        let mut screen = screen_with_scrollback(15);
        screen.set_scrollback_max_lines(0);
        assert_eq!(screen.scrollback_line_count, 0);
        assert!(screen.scrollback_buffer.is_empty());
    }

    #[test]
    fn test_get_scrollback_lines_respects_limit() {
        let screen = screen_with_scrollback(20);
        let lines = screen.get_scrollback_lines(5);
        assert_eq!(lines.len(), 5);
    }

    #[test]
    fn test_get_scrollback_lines_zero_returns_empty() {
        let screen = screen_with_scrollback(10);
        let lines = screen.get_scrollback_lines(0);
        assert!(lines.is_empty());
    }

    #[test]
    fn test_get_scrollback_viewport_line_at_full_offset_bottom_row() {
        let mut screen = Screen::new(5, 10);
        screen.set_scrollback_max_lines(5);
        for _ in 0..5 {
            screen.scroll_up(1, Color::Default);
        }
        screen.viewport_scroll_up(5);
        assert!(screen.get_scrollback_viewport_line(4).is_some());
        assert!(screen.get_scrollback_viewport_line(3).is_none());
    }

    #[test]
    fn test_scrollback_empty_on_new_screen() {
        let s = make_screen();
        assert_eq!(s.scrollback_line_count, 0);
        assert!(s.scrollback_buffer.is_empty());
    }

    #[test]
    fn test_push_one_line_count_is_one() {
        let mut s = make_screen();
        s.scroll_up(1, Color::Default);
        assert_eq!(s.scrollback_line_count, 1);
        assert_eq!(s.scrollback_buffer.len(), 1);
    }

    #[test]
    fn test_push_up_to_max_count_equals_max() {
        let mut s = Screen::new(5, 10);
        s.set_scrollback_max_lines(4);
        for _ in 0..4 {
            s.scroll_up(1, Color::Default);
        }
        assert_eq!(s.scrollback_line_count, 4);
        assert_eq!(s.scrollback_buffer.len(), 4);
    }

    #[test]
    fn test_get_scrollback_lines_oldest_and_newest_order() {
        let mut s = Screen::new(5, 80);
        let attrs = SgrAttributes::default();
        for ch in ['1', '2', '3'] {
            s.move_cursor(0, 0);
            s.print(ch, attrs, false);
            s.scroll_up(1, Color::Default);
        }
        let lines = s.get_scrollback_lines(3);
        assert_eq!(
            lines[0].get_cell(0).map(crate::types::cell::Cell::char),
            Some('3')
        );
        assert_eq!(
            lines[2].get_cell(0).map(crate::types::cell::Cell::char),
            Some('1')
        );
    }

    #[test]
    fn test_get_scrollback_lines_request_more_than_available() {
        let s = screen_with_scrollback(5);
        let lines = s.get_scrollback_lines(999);
        assert_eq!(lines.len(), 5);
    }

    #[test]
    fn test_clear_scrollback_does_not_reset_scroll_offset() {
        let mut screen = screen_with_scrollback(20);
        screen.viewport_scroll_up(10);
        let offset_before = screen.scroll_offset();
        screen.clear_scrollback();
        assert_eq!(screen.scrollback_line_count, 0);
        assert_eq!(screen.scroll_offset(), offset_before);
    }
