// Property-based tests for CSI cursor-positioning sequences.
// Inherited from csi.rs: `use super::*`, `term!`, `assert_cursor!` macros.

use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(500))]

    #[test]
    // CLAMP: CUP row parameter is clamped to screen bounds
    fn prop_cup_row_clamped(r in 0u16..=500u16) {
        let rows: u16 = 24;
        let mut term = crate::TerminalCore::new(rows, 80);
        term.advance(format!("\x1b[{};1H", r + 1).as_bytes());
        let expected = (r as usize).min((rows - 1) as usize);
        prop_assert_eq!(
            term.screen.cursor.row, expected,
            "CUP row {} must clamp to {}", r, expected
        );
    }

    #[test]
    // CLAMP: CUP col parameter is clamped to screen bounds
    fn prop_cup_col_clamped(c in 0u16..=500u16) {
        let cols: u16 = 80;
        let mut term = crate::TerminalCore::new(24, cols);
        term.advance(format!("\x1b[1;{}H", c + 1).as_bytes());
        let expected = (c as usize).min((cols - 1) as usize);
        prop_assert_eq!(
            term.screen.cursor.col, expected,
            "CUP col {} must clamp to {}", c, expected
        );
    }

    #[test]
    // BOUNDARY: cursor up never moves above row 0
    fn prop_cursor_up_no_overflow(n in 0u16..=300u16) {
        let mut term = crate::TerminalCore::new(24, 80);
        term.screen.move_cursor(0, 0);
        term.advance(format!("\x1b[{n}A").as_bytes());
        prop_assert_eq!(term.screen.cursor.row, 0, "cursor up from row 0 must stay at 0");
    }

    #[test]
    // BOUNDARY: cursor down from last row never exceeds last row
    fn prop_cursor_down_no_overflow(n in 0u16..=300u16) {
        let rows: usize = 24;
        let mut term = crate::TerminalCore::new(rows as u16, 80);
        term.screen.move_cursor(rows - 1, 0);
        term.advance(format!("\x1b[{n}B").as_bytes());
        prop_assert!(
            term.screen.cursor.row < rows,
            "cursor down from last row must not exceed bounds"
        );
    }

    #[test]
    // BOUNDARY: cursor right never exceeds last column
    fn prop_cursor_right_in_bounds(n in 0u16..=300u16) {
        let mut term = crate::TerminalCore::new(24, 80);
        term.advance(format!("\x1b[{n}C").as_bytes());
        prop_assert!(term.screen.cursor.col < 80, "cursor.col must be < 80");
    }

    #[test]
    // BOUNDARY: cursor left from col 0 stays at col 0
    fn prop_cursor_left_in_bounds(n in 0u16..=300u16) {
        let mut term = crate::TerminalCore::new(24, 80);
        term.screen.move_cursor(0, 0);
        term.advance(format!("\x1b[{n}D").as_bytes());
        prop_assert_eq!(term.screen.cursor.col, 0, "cursor left from col 0 must stay at 0");
    }
}
