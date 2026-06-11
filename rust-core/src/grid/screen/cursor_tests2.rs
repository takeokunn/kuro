    // ── carriage_return ───────────────────────────────────────────────────────

    #[test]
    fn carriage_return_resets_col_to_zero() {
        let mut screen = Screen::new(10, 40);
        screen.move_cursor(3, 20);
        screen.carriage_return();
        assert_cursor!(screen, row 3, col 0);
    }

    #[test]
    fn carriage_return_clears_pending_wrap() {
        let mut screen = Screen::new(5, 5);
        screen.move_cursor(0, 4);
        screen.print('X', SgrAttributes::default(), true);
        assert!(screen.cursor.pending_wrap);
        screen.carriage_return();
        assert!(
            !screen.cursor.pending_wrap,
            "carriage_return must clear pending_wrap"
        );
    }

    // ── tab ───────────────────────────────────────────────────────────────────

    #[test]
    fn tab_advances_to_next_tab_stop() {
        let mut screen = Screen::new(5, 80);
        screen.tab();
        assert_eq!(screen.cursor().col, 8, "tab from col 0 must reach col 8");
    }

    #[test]
    fn tab_at_near_end_clamps_to_last_col() {
        let mut screen = Screen::new(5, 10);
        screen.move_cursor(0, 5);
        screen.tab(); // 5 → 8
        assert_eq!(screen.cursor().col, 8);
        screen.tab(); // 8 → 16 clamped to 9 (cols-1)
        assert_eq!(
            screen.cursor().col,
            9,
            "tab past last col must clamp to cols-1"
        );
    }

    // ── line_feed ─────────────────────────────────────────────────────────────

    #[test]
    fn line_feed_col_preserved_after_advance() {
        let mut screen = Screen::new(24, 80);
        screen.move_cursor(0, 40);
        screen.line_feed(Color::Default);
        assert_cursor!(screen, row 1, col 40);
    }

    #[test]
    fn line_feed_without_auto_wrap_stays_in_col() {
        let mut screen = Screen::new(5, 10);
        screen.move_cursor(0, 9);
        screen.print('Z', SgrAttributes::default(), false);
        assert_cursor!(screen, row 0, col 9);
        assert!(
            !screen.cursor.pending_wrap,
            "auto_wrap=false: no pending_wrap after last col"
        );
    }

    #[test]
    fn line_feed_with_auto_wrap_sets_pending_wrap() {
        let mut screen = Screen::new(5, 10);
        screen.move_cursor(0, 9);
        screen.print('Z', SgrAttributes::default(), true);
        assert!(
            screen.cursor.pending_wrap,
            "auto_wrap=true: pending_wrap must be set after printing at last col"
        );
    }

    // ── cursor getters ────────────────────────────────────────────────────────

    #[test]
    fn cursor_row_and_col_return_correct_values() {
        let mut screen = Screen::new(24, 80);
        screen.move_cursor(7, 13);
        assert_eq!(screen.cursor().row, 7, "cursor().row mismatch");
        assert_eq!(screen.cursor().col, 13, "cursor().col mismatch");
    }

    #[test]
    fn cursor_default_shape_is_blinking_block() {
        let screen = Screen::new(24, 80);
        assert_eq!(
            screen.cursor().shape,
            CursorShape::BlinkingBlock,
            "default cursor shape must be BlinkingBlock"
        );
    }

    // ── backspace ─────────────────────────────────────────────────────────────

    #[test]
    fn backspace_clears_pending_wrap() {
        let mut screen = Screen::new(5, 5);
        screen.move_cursor(0, 4);
        screen.print('X', SgrAttributes::default(), true);
        assert!(screen.cursor.pending_wrap);
        screen.backspace();
        assert!(
            !screen.cursor.pending_wrap,
            "backspace must clear pending_wrap"
        );
    }
