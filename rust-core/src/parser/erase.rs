//! Erase operations (ED and EL sequences)

/// Handle erase sequences
///
/// This module implements:
/// - ED (CSI J): Erase in Display
/// - EL (CSI K): Erase in Line
pub fn handle_erase(term: &mut crate::TerminalCore, params: &vte::Params, c: char) {
    match c {
        'J' => csi_ed(term, params), // ED - Erase Display
        'K' => csi_el(term, params), // EL - Erase Line
        _ => {}
    }
}

/// ED - Erase Display (CSI J Ps)
///
/// Erase parts of the display.
///
/// Parameters:
/// - Ps = 0 (default): Erase from cursor to end of screen
/// - Ps = 1: Erase from start of screen to cursor (including cursor)
/// - Ps = 2: Erase entire screen
/// - Ps = 3: Erase entire screen and scrollback buffer
fn csi_ed(term: &mut crate::TerminalCore, params: &vte::Params) {
    let mode = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(0);

    let row = term.screen.cursor().row;
    let col = term.screen.cursor().col;

    match mode {
        0 => {
            // Erase from cursor to end of screen
            // First, erase from cursor to end of current line
            if let Some(line) = term.screen.get_line_mut(row) {
                for c in col..line.cells.len() {
                    line.cells[c] = Default::default();
                }
            }
            term.screen.mark_line_dirty(row);

            // Then erase all lines below
            for r in (row + 1)..term.screen.rows() as usize {
                if let Some(line) = term.screen.get_line_mut(r) {
                    line.clear();
                }
                term.screen.mark_line_dirty(r);
            }
        }
        1 => {
            // Erase from start of screen to cursor (including cursor)
            // First, erase all lines above
            for r in 0..row {
                if let Some(line) = term.screen.get_line_mut(r) {
                    line.clear();
                }
                term.screen.mark_line_dirty(r);
            }

            // Then erase from start of cursor line to cursor
            if let Some(line) = term.screen.get_line_mut(row) {
                for c in 0..=col {
                    line.cells[c] = Default::default();
                }
            }
            term.screen.mark_line_dirty(row);
        }
        2 | 3 => {
            // Erase entire screen
            for r in 0..term.screen.rows() as usize {
                if let Some(line) = term.screen.get_line_mut(r) {
                    line.clear();
                }
            }
            term.screen.mark_all_dirty();
            term.screen.active_graphics_mut().clear_all_placements();

            // Mode 3 also clears scrollback buffer
            if mode == 3 {
                term.screen.clear_scrollback();
            }
        }
        _ => {}
    }
}

/// EL - Erase Line (CSI K Ps)
///
/// Erase parts of the current line.
///
/// Parameters:
/// - Ps = 0 (default): Erase from cursor to end of line
/// - Ps = 1: Erase from start of line to cursor (including cursor)
/// - Ps = 2: Erase entire line
fn csi_el(term: &mut crate::TerminalCore, params: &vte::Params) {
    let mode = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(0);

    let col = term.screen.cursor().col;
    let row = term.screen.cursor().row;

    if let Some(line) = term.screen.get_line_mut(row) {
        match mode {
            0 => {
                // Erase from cursor to end of line
                for c in col..line.cells.len() {
                    line.cells[c] = Default::default();
                }
            }
            1 => {
                // Erase from start of line to cursor (including cursor)
                for c in 0..=col {
                    line.cells[c] = Default::default();
                }
            }
            2 => {
                // Erase entire line
                line.clear();
            }
            _ => {}
        }
    }
    term.screen.mark_line_dirty(row);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::{Cell, Color, NamedColor, SgrAttributes};

    #[test]
    fn test_ed_default() {
        let mut term = crate::TerminalCore::new(5, 20);

        // Fill screen with 'X'
        for r in 0..5 {
            for c in 0..20 {
                if let Some(line) = term.screen.get_line_mut(r) {
                    line.update_cell_with(c, Cell::new('X'));
                }
            }
        }

        // Move cursor to row 2, col 5
        term.screen.move_cursor(2, 5);

        // ED with no parameter (default: mode 0)
        let params = vte::Params::default();
        csi_ed(&mut term, &params);

        // Check that cursor line from col 5+ is cleared
        let line = term.screen.get_line(2).unwrap();
        for c in 0..5 {
            assert_eq!(line.cells[c].c, 'X', "Column {} should still be 'X'", c);
        }
        for c in 5..20 {
            assert_eq!(line.cells[c].c, ' ', "Column {} should be cleared", c);
        }

        // Check that all lines below are cleared
        for r in 3..5 {
            let line = term.screen.get_line(r).unwrap();
            for c in 0..20 {
                assert_eq!(
                    line.cells[c].c, ' ',
                    "Row {} column {} should be cleared",
                    r, c
                );
            }
        }

        // Lines above should still have 'X'
        for r in 0..2 {
            let line = term.screen.get_line(r).unwrap();
            for c in 0..20 {
                assert_eq!(
                    line.cells[c].c, 'X',
                    "Row {} column {} should still be 'X'",
                    r, c
                );
            }
        }
    }

    #[test]
    fn test_ed_mode0() {
        let mut term = crate::TerminalCore::new(3, 10);

        // Fill screen
        for r in 0..3 {
            for c in 0..10 {
                if let Some(line) = term.screen.get_line_mut(r) {
                    line.update_cell_with(c, Cell::new('A'));
                }
            }
        }

        // Move cursor to (1, 5)
        term.screen.move_cursor(1, 5);

        // ED mode 0: cursor to end
        let params = vte::Params::default();
        csi_ed(&mut term, &params);

        // Row 0 should be unchanged
        let line = term.screen.get_line(0).unwrap();
        assert_eq!(line.cells[0].c, 'A');

        // Row 1, cols 0-4 unchanged, cols 5-9 cleared
        let line = term.screen.get_line(1).unwrap();
        assert_eq!(line.cells[4].c, 'A');
        assert_eq!(line.cells[5].c, ' ');

        // Row 2 should be completely cleared
        let line = term.screen.get_line(2).unwrap();
        assert_eq!(line.cells[0].c, ' ');
    }

    #[test]
    fn test_ed_mode1() {
        let mut term = crate::TerminalCore::new(3, 10);

        // Fill screen
        for r in 0..3 {
            for c in 0..10 {
                if let Some(line) = term.screen.get_line_mut(r) {
                    line.update_cell_with(c, Cell::new('B'));
                }
            }
        }

        // Move cursor to (1, 5)
        term.screen.move_cursor(1, 5);

        // ED mode 1: start to cursor (CSI 1 J)
        term.advance(b"\x1b[1J");

        // Row 0 should be cleared
        let line = term.screen.get_line(0).unwrap();
        assert_eq!(line.cells[0].c, ' ');

        // Row 1, cols 0-5 cleared, cols 6-9 unchanged
        let line = term.screen.get_line(1).unwrap();
        assert_eq!(line.cells[5].c, ' ');
        assert_eq!(line.cells[6].c, 'B');

        // Row 2 should be unchanged
        let line = term.screen.get_line(2).unwrap();
        assert_eq!(line.cells[0].c, 'B');
    }

    #[test]
    fn test_ed_mode2() {
        let mut term = crate::TerminalCore::new(3, 10);

        // Fill screen
        for r in 0..3 {
            for c in 0..10 {
                if let Some(line) = term.screen.get_line_mut(r) {
                    line.update_cell_with(c, Cell::new('C'));
                }
            }
        }

        // ED mode 2: entire screen
        let params = vte::Params::default();
        csi_ed(&mut term, &params);

        // All rows should be cleared
        for r in 0..3 {
            let line = term.screen.get_line(r).unwrap();
            for c in 0..10 {
                assert_eq!(
                    line.cells[c].c, ' ',
                    "Row {} col {} should be cleared",
                    r, c
                );
            }
        }
    }

    #[test]
    fn test_ed_mode3_clears_scrollback() {
        let mut term = crate::TerminalCore::new(5, 10);

        // Add lines to scrollback
        for _ in 0..5 {
            term.screen.scroll_up(1);
        }

        assert_eq!(term.screen.scrollback_line_count, 5);

        // ED mode 3: entire screen and scrollback (CSI 3 J)
        term.advance(b"\x1b[3J");

        // Scrollback should be cleared
        assert_eq!(term.screen.scrollback_line_count, 0);
    }

    #[test]
    fn test_el_default() {
        let mut term = crate::TerminalCore::new(5, 20);

        // Fill a line with 'Y'
        let row = 2;
        for c in 0..20 {
            if let Some(line) = term.screen.get_line_mut(row) {
                line.update_cell_with(c, Cell::new('Y'));
            }
        }

        // Move cursor to row 2, col 5
        term.screen.move_cursor(row, 5);

        // EL with no parameter (default: mode 0)
        let params = vte::Params::default();
        csi_el(&mut term, &params);

        // Check line
        let line = term.screen.get_line(row).unwrap();
        for c in 0..5 {
            assert_eq!(line.cells[c].c, 'Y', "Column {} should still be 'Y'", c);
        }
        for c in 5..20 {
            assert_eq!(line.cells[c].c, ' ', "Column {} should be cleared", c);
        }
    }

    #[test]
    fn test_el_mode0() {
        let mut term = crate::TerminalCore::new(5, 10);

        let row = 2;
        for c in 0..10 {
            if let Some(line) = term.screen.get_line_mut(row) {
                line.update_cell_with(c, Cell::new('Z'));
            }
        }

        term.screen.move_cursor(row, 3);

        // EL mode 0: cursor to end
        let params = vte::Params::default();
        csi_el(&mut term, &params);

        let line = term.screen.get_line(row).unwrap();
        assert_eq!(line.cells[2].c, 'Z');
        assert_eq!(line.cells[3].c, ' ');
    }

    #[test]
    fn test_el_mode1() {
        let mut term = crate::TerminalCore::new(5, 10);

        let row = 2;
        for c in 0..10 {
            if let Some(line) = term.screen.get_line_mut(row) {
                line.update_cell_with(c, Cell::new('W'));
            }
        }

        term.screen.move_cursor(row, 5);

        // EL mode 1: start to cursor (CSI 1 K)
        term.advance(b"\x1b[1K");

        let line = term.screen.get_line(row).unwrap();
        assert_eq!(line.cells[5].c, ' ');
        assert_eq!(line.cells[6].c, 'W');
    }

    #[test]
    fn test_el_mode2() {
        let mut term = crate::TerminalCore::new(5, 10);

        let row = 2;
        for c in 0..10 {
            if let Some(line) = term.screen.get_line_mut(row) {
                line.update_cell_with(c, Cell::new('V'));
            }
        }

        term.screen.move_cursor(row, 5);

        // EL mode 2: entire line (CSI 2 K)
        term.advance(b"\x1b[2K");

        let line = term.screen.get_line(row).unwrap();
        for c in 0..10 {
            assert_eq!(line.cells[c].c, ' ', "Column {} should be cleared", c);
        }
    }

    #[test]
    fn test_erase_preserves_default_colors() {
        let mut term = crate::TerminalCore::new(5, 10);

        // Set non-default foreground color
        let mut attrs = SgrAttributes::default();
        attrs.foreground = Color::Named(NamedColor::Red);
        term.current_attrs = attrs;

        // Print character with red color
        term.screen.print('A', attrs, true);

        // Move cursor back
        term.screen.move_cursor(0, 0);

        // Erase the line
        let params = vte::Params::default();
        csi_el(&mut term, &params);

        // Erased cell should have default colors
        let line = term.screen.get_line(0).unwrap();
        assert_eq!(line.cells[0].c, ' ');
        assert_eq!(line.cells[0].attrs.foreground, Color::Default);
        assert_eq!(line.cells[0].attrs.background, Color::Default);
    }

    #[test]
    fn test_erase_marks_dirty() {
        let mut term = crate::TerminalCore::new(5, 10);

        // Take initial dirty lines
        let dirty1 = term.screen.take_dirty_lines();
        assert_eq!(dirty1.len(), 0);

        // Fill a line
        let row = 2;
        for c in 0..10 {
            if let Some(line) = term.screen.get_line_mut(row) {
                line.update_cell_with(c, Cell::new('T'));
                line.is_dirty = false;
            }
        }

        // Erase the line
        term.screen.move_cursor(row, 0);
        let params = vte::Params::default();
        csi_el(&mut term, &params);

        // Line should be marked dirty
        let line = term.screen.get_line(row).unwrap();
        assert!(line.is_dirty);

        // Also test ED
        term.screen.move_cursor(0, 0);
        let params = vte::Params::default();
        csi_ed(&mut term, &params);

        // All lines should be dirty
        let dirty = term.screen.take_dirty_lines();
        assert!(dirty.len() > 0);
    }
}
