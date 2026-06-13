// ── PBT tests (merged from tests/unit/grid/screen/cursor.rs) ────────

use proptest::prelude::*;

fn make_screen() -> Screen {
    Screen::new(24, 80)
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(500))]

    #[test]
    fn prop_move_cursor_clamps_row(row in 0usize..200usize, col in 0usize..80usize) {
        let mut screen = make_screen();
        screen.move_cursor(row, col);
        prop_assert!(screen.cursor().row < screen.rows() as usize);
    }

    #[test]
    fn prop_move_cursor_clamps_col(row in 0usize..24usize, col in 0usize..200usize) {
        let mut screen = make_screen();
        screen.move_cursor(row, col);
        prop_assert!(screen.cursor().col < screen.cols() as usize);
    }

    #[test]
    fn prop_move_cursor_clears_pending_wrap(row in 0usize..200usize, col in 0usize..200usize) {
        let mut screen = make_screen();
        screen.cursor.pending_wrap = true;
        screen.move_cursor(row, col);
        prop_assert!(!screen.cursor().pending_wrap);
    }

    #[test]
    fn prop_move_cursor_by_no_panic(row_offset in i32::MIN..=i32::MAX, col_offset in i32::MIN..=i32::MAX) {
        let mut screen = make_screen();
        screen.move_cursor_by(row_offset, col_offset);
        prop_assert!(screen.cursor().row < screen.rows() as usize);
        prop_assert!(screen.cursor().col < screen.cols() as usize);
    }

    #[test]
    fn prop_move_cursor_by_clears_pending_wrap(
        row_offset in -50i32..50i32,
        col_offset in -50i32..50i32,
    ) {
        let mut screen = make_screen();
        screen.cursor.pending_wrap = true;
        screen.move_cursor_by(row_offset, col_offset);
        prop_assert!(!screen.cursor().pending_wrap);
    }

    #[test]
    fn prop_carriage_return_col_zero(start_col in 0usize..80usize) {
        let mut screen = make_screen();
        screen.move_cursor(0, start_col);
        screen.carriage_return();
        prop_assert_eq!(screen.cursor().col, 0);
    }

    #[test]
    fn prop_backspace_saturating(start_col in 0usize..80usize) {
        let mut screen = make_screen();
        screen.move_cursor(0, start_col);
        for _ in 0..100 { screen.backspace(); }
        prop_assert_eq!(screen.cursor().col, 0);
    }

    #[test]
    fn prop_tab_advances_to_stop(start_col in 0usize..79usize) {
        let mut screen = make_screen();
        let cols = screen.cols() as usize;
        screen.move_cursor(0, start_col);
        screen.tab();
        let new_col = screen.cursor().col;
        let expected = ((start_col / 8) + 1) * 8;
        let expected_clamped = expected.min(cols - 1);
        prop_assert_eq!(new_col, expected_clamped);
    }

    #[test]
    fn prop_backspace_clears_pending_wrap(start_col in 0usize..80usize) {
        let mut screen = make_screen();
        screen.move_cursor(0, start_col);
        screen.cursor.pending_wrap = true;
        screen.backspace();
        prop_assert!(!screen.cursor().pending_wrap);
    }

    #[test]
    fn prop_carriage_return_clears_pending_wrap(start_col in 0usize..80usize) {
        let mut screen = make_screen();
        screen.move_cursor(0, start_col);
        screen.cursor.pending_wrap = true;
        screen.carriage_return();
        prop_assert!(!screen.cursor().pending_wrap);
    }

    #[test]
    fn prop_tab_clears_pending_wrap(start_col in 0usize..79usize) {
        let mut screen = make_screen();
        screen.move_cursor(0, start_col);
        screen.cursor.pending_wrap = true;
        screen.tab();
        prop_assert!(!screen.cursor().pending_wrap);
    }

    #[test]
    fn prop_move_cursor_exact_clamped_value(row in 0usize..200usize, col in 0usize..200usize) {
        let mut screen = make_screen();
        let rows = screen.rows() as usize;
        let cols = screen.cols() as usize;
        screen.move_cursor(row, col);
        prop_assert_eq!(screen.cursor().row, row.min(rows - 1));
        prop_assert_eq!(screen.cursor().col, col.min(cols - 1));
    }
}

include!("cursor_pbt2.rs");
