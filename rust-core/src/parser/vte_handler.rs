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

    /// LF (0x0A) should advance the cursor to the next row.
    #[test]
    fn test_execute_lf() {
        let mut term = TerminalCore::new(24, 80);
        let row_before = term.screen.cursor.row;
        term.advance(b"\n");
        assert_eq!(
            term.screen.cursor.row,
            row_before + 1,
            "LF should move cursor down one row"
        );
    }

    /// CR (0x0D) should move the cursor to column 0 of the current row.
    #[test]
    fn test_execute_cr() {
        let mut term = TerminalCore::new(24, 80);
        // Move cursor to a non-zero column first
        term.advance(b"Hello");
        assert!(term.screen.cursor.col > 0, "cursor should be past col 0 after printing");
        term.advance(b"\r");
        assert_eq!(term.screen.cursor.col, 0, "CR should return cursor to column 0");
    }

    /// BS (0x08) at column 0 should not underflow — cursor stays at 0.
    #[test]
    fn test_execute_bs_at_start() {
        let mut term = TerminalCore::new(24, 80);
        // Cursor starts at (0, 0)
        assert_eq!(term.screen.cursor.col, 0);
        term.advance(b"\x08");
        assert_eq!(term.screen.cursor.col, 0, "BS at col 0 should keep cursor at 0");
    }

    /// HT (0x09) should move cursor right by at least one column to the next tab stop.
    #[test]
    fn test_execute_tab() {
        let mut term = TerminalCore::new(24, 80);
        // Cursor starts at column 0; default tab stop is at column 8
        let col_before = term.screen.cursor.col;
        term.advance(b"\t");
        assert!(
            term.screen.cursor.col > col_before,
            "HT should move cursor right by at least 1 column"
        );
    }
}
