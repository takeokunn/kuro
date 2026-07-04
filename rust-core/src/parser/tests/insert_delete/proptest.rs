use super::support::fill_line;
use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    // PANIC SAFETY: IL (CSI n L) never panics; row count is preserved.
    fn prop_il_no_panic(n in 0u16..=100u16, row in 0usize..10usize) {
        let mut term = crate::TerminalCore::new(10, 20);
        for r in 0..10usize {
            if let Some(line) = term.screen.get_line_mut(r) {
                let ch = (b'0' + r as u8) as char;
                let cols = line.cells.len();
                for c in 0..cols {
                    line.update_cell_with(c, crate::types::Cell::new(ch));
                }
            }
        }
        term.screen.move_cursor(row, 0);
        term.advance(format!("\x1b[{n}L").as_bytes());

        prop_assert_eq!(term.screen.rows() as usize, 10);
        prop_assert!(term.screen.cursor().row < 10);
        prop_assert!(term.screen.cursor().col < 20);
    }

    #[test]
    // PANIC SAFETY: DL (CSI n M) never panics; row count is preserved.
    fn prop_dl_no_panic(n in 0u16..=100u16, row in 0usize..10usize) {
        let mut term = crate::TerminalCore::new(10, 20);
        for r in 0..10usize {
            if let Some(line) = term.screen.get_line_mut(r) {
                let ch = (b'A' + r as u8) as char;
                let cols = line.cells.len();
                for c in 0..cols {
                    line.update_cell_with(c, crate::types::Cell::new(ch));
                }
            }
        }
        term.screen.move_cursor(row, 0);
        term.advance(format!("\x1b[{n}M").as_bytes());

        prop_assert_eq!(term.screen.rows() as usize, 10);
        prop_assert!(term.screen.cursor().row < 10);
        prop_assert!(term.screen.cursor().col < 20);
    }

    #[test]
    // PANIC SAFETY: ICH (CSI n @) never panics; line width is preserved.
    fn prop_ich_no_panic(n in 0u16..=100u16, col in 0usize..20usize) {
        let mut term = crate::TerminalCore::new(10, 20);
        fill_line(&mut term, 0, 'X');
        term.screen.move_cursor(0, col);
        term.advance(format!("\x1b[{n}@").as_bytes());

        prop_assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 20);
        prop_assert!(term.screen.cursor().row < 10);
        prop_assert!(term.screen.cursor().col < 20);
    }

    #[test]
    // PANIC SAFETY: DCH (CSI n P) never panics; line width is preserved.
    fn prop_dch_no_panic(n in 0u16..=100u16, col in 0usize..20usize) {
        let mut term = crate::TerminalCore::new(10, 20);
        fill_line(&mut term, 0, 'X');
        term.screen.move_cursor(0, col);
        term.advance(format!("\x1b[{n}P").as_bytes());

        prop_assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 20);
        prop_assert!(term.screen.cursor().row < 10);
        prop_assert!(term.screen.cursor().col < 20);
    }

    #[test]
    // INVARIANT: IL followed by DL with the same count keeps the row count stable.
    fn prop_il_dl_preserves_row_count(n in 1u16..=8u16) {
        let mut term = crate::TerminalCore::new(10, 20);
        for r in 0..10usize {
            if let Some(line) = term.screen.get_line_mut(r) {
                let ch = (b'0' + r as u8) as char;
                let cols = line.cells.len();
                for c in 0..cols {
                    line.update_cell_with(c, crate::types::Cell::new(ch));
                }
            }
        }
        term.screen.move_cursor(3, 0);
        term.advance(format!("\x1b[{n}L").as_bytes());
        term.advance(format!("\x1b[{n}M").as_bytes());

        prop_assert_eq!(term.screen.rows() as usize, 10);
        prop_assert!(term.screen.cursor().row < 10);
        prop_assert!(term.screen.cursor().col < 20);
    }

    #[test]
    // INVARIANT: ECH (CSI n X) never panics; line width and cursor col are preserved.
    fn prop_ech_no_panic_preserves_width_and_cursor(
        n in 0u16..=100u16,
        row in 0usize..10usize,
        col in 0usize..20usize,
    ) {
        let mut term = crate::TerminalCore::new(10, 20);
        fill_line(&mut term, row, 'Q');
        term.screen.move_cursor(row, col);
        term.advance(format!("\x1b[{n}X").as_bytes());

        prop_assert_eq!(term.screen.get_line(row).unwrap().cells.len(), 20);
        prop_assert_eq!(term.screen.cursor().row, row);
        prop_assert_eq!(term.screen.cursor().col, col);
    }

    #[test]
    // INVARIANT: ICH followed by DCH with the same count keeps the line width stable.
    fn prop_ich_dch_preserves_line_width(
        n in 1u16..=8u16,
        col in 0usize..20usize,
    ) {
        let mut term = crate::TerminalCore::new(10, 20);
        fill_line(&mut term, 0, 'Z');
        term.screen.move_cursor(0, col);
        term.advance(format!("\x1b[{n}@").as_bytes());
        term.screen.move_cursor(0, col);
        term.advance(format!("\x1b[{n}P").as_bytes());

        prop_assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 20);
        prop_assert!(term.screen.cursor().row < 10);
        prop_assert!(term.screen.cursor().col < 20);
    }
}
