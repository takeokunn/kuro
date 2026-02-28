//! VTE handler implementation

#[cfg(test)]
mod tests {
    use crate::TerminalCore;

    #[test]
    fn test_vte_print() {
        let mut term = TerminalCore::new(24, 80);
        term.advance(b"Hello");

        assert_eq!(term.screen.get_cell(0, 0).unwrap().c, 'H');
        assert_eq!(term.screen.get_cell(0, 1).unwrap().c, 'e');
        assert_eq!(term.screen.get_cell(0, 2).unwrap().c, 'l');
        assert_eq!(term.screen.get_cell(0, 3).unwrap().c, 'l');
        assert_eq!(term.screen.get_cell(0, 4).unwrap().c, 'o');
    }

    #[test]
    fn test_vte_sgr_bold() {
        let mut term = TerminalCore::new(24, 80);
        // Set bold, print text, then verify bold is active (no reset)
        term.advance(b"\x1b[1mBold");

        assert!(term.current_attrs.bold);
    }

    #[test]
    fn test_vte_cursor_movement() {
        let mut term = TerminalCore::new(24, 80);
        term.advance(b"ABC\x1b[2D");

        // Should move back 2 columns
        assert_eq!(term.screen.cursor.col, 1);
    }
}
