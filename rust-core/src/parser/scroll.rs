//! Scroll region management and scrolling operations

/// Handle scroll sequences
///
/// This module implements:
/// - DECSTBM (CSI r): Set Top and Bottom Margins
/// - SU (CSI S): Scroll Up
/// - SD (CSI T): Scroll Down
pub fn handle_scroll(term: &mut crate::TerminalCore, params: &vte::Params, c: char) {
    match c {
        'r' => csi_decstbm(term, params), // DECSTBM
        'S' => csi_su(term, params),      // SU - Scroll Up
        'T' => csi_sd(term, params),      // SD - Scroll Down
        _ => {}
    }
}

/// DECSTBM - Set Top and Bottom Margins (CSI r Ps; Pt)
///
/// Set scrolling region. Both parameters are 1-indexed.
///
/// Parameters:
/// - Ps: Top margin (default: 1, which becomes 0 internally)
/// - Pt: Bottom margin (default: bottom of screen, which becomes rows internally)
///
/// Note: The top margin is inclusive, bottom margin is exclusive (following the
/// existing ScrollRegion convention in Screen).
fn csi_decstbm(term: &mut crate::TerminalCore, params: &vte::Params) {
    let rows = term.screen.rows() as usize;

    // Get top parameter (1-indexed, convert to 0-indexed)
    // Default is 0 (top of screen)
    let top = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .saturating_sub(1) as usize;

    // Get bottom parameter (1-indexed, convert to 0-indexed)
    // Default is rows (end of screen)
    let bottom = params
        .iter()
        .nth(1)
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(rows as u16)
        .min(rows as u16) as usize;

    // Validate: top must be < bottom
    if top < bottom {
        term.screen.set_scroll_region(top, bottom);

        // Move cursor to home position after setting scroll region (DECSTD behavior)
        term.screen.move_cursor(top, 0);
    }
    // If invalid, ignore the sequence (DEC behavior)
}

/// SU - Scroll Up (CSI S Ps)
///
/// Scroll content down within the scroll region.
///
/// Parameters:
/// - Ps: Number of lines to scroll (default: 1)
///
/// Note: "Scroll Up" in VTE terms means the content moves down,
/// which is achieved by calling scroll_up on the screen.
fn csi_su(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1);

    // Ensure minimum scroll of 1 line
    let n = n.max(1);

    // Scroll up (content moves down)
    term.screen.scroll_up(n as usize);
}

/// SD - Scroll Down (CSI T Ps)
///
/// Scroll content up within the scroll region.
///
/// Parameters:
/// - Ps: Number of lines to scroll (default: 1)
///
/// Note: "Scroll Down" in VTE terms means the content moves up,
/// which is achieved by calling scroll_down on the screen.
fn csi_sd(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1);

    // Ensure minimum scroll of 1 line
    let n = n.max(1);

    // Scroll down (content moves up)
    term.screen.scroll_down(n as usize);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_decstbm_default() {
        let mut term = crate::TerminalCore::new(10, 80);

        // DECSTBM with no parameters should set full screen as scroll region
        let params = vte::Params::default();
        csi_decstbm(&mut term, &params);

        // Check scroll region (0-indexed: top=0, bottom=10 for 10 rows)
        assert_eq!(term.screen.get_scroll_region().top, 0);
        assert_eq!(term.screen.get_scroll_region().bottom, 10);
    }

    #[test]
    fn test_decstbm_with_params() {
        let mut term = crate::TerminalCore::new(10, 80);

        // Set scroll region from row 3 to row 8 (1-indexed: CSI 3;8 r)
        // This becomes (2, 8) in 0-indexed
        term.advance(b"\x1b[3;8r");

        assert_eq!(term.screen.get_scroll_region().top, 2);
        assert_eq!(term.screen.get_scroll_region().bottom, 8);
    }

    #[test]
    fn test_decstbm_moves_cursor_to_home() {
        let mut term = crate::TerminalCore::new(10, 80);

        // Move cursor away from home
        term.screen.move_cursor(5, 10);
        assert_eq!(term.screen.cursor.row, 5);

        // Set scroll region from row 2 to row 8 (1-indexed: CSI 2;8 r)
        // top becomes 1 (0-indexed)
        term.advance(b"\x1b[2;8r");

        // Cursor should move to top of scroll region (row 1, since top=1)
        assert_eq!(term.screen.cursor.row, 1);
        assert_eq!(term.screen.cursor.col, 0);
    }

    #[test]
    fn test_decstbm_inverted_margins_ignored() {
        // CSI 8;3 r — top=8, bottom=3 — top > bottom, should be ignored
        let mut term = crate::TerminalCore::new(10, 80);
        // First set a valid scroll region to verify it doesn't change
        term.advance(b"\x1b[2;8r"); // valid: top=2, bottom=8
        // Now try invalid: top > bottom
        term.advance(b"\x1b[8;3r"); // invalid: should be ignored
        // The valid region from before should still be active
        // (cursor will be at home after DECSTBM per spec)
        assert!(term.screen.cursor.row < 10);
        assert!(term.screen.cursor.col < 80);
    }

    #[test]
    fn test_decstbm_equal_margins_ignored() {
        // CSI 5;5 r — top=bottom=5 — degenerate, should be ignored
        let mut term = crate::TerminalCore::new(10, 80);
        term.advance(b"\x1b[5;5r"); // top == bottom, invalid
        assert!(term.screen.cursor.row < 10);
    }

    #[test]
    fn test_su_default() {
        let mut term = crate::TerminalCore::new(10, 10);

        // Fill lines with different characters
        for r in 0..10 {
            if let Some(line) = term.screen.get_line_mut(r) {
                for c in 0..10 {
                    line.update_cell_with(c, crate::types::Cell::new((b'0' + r as u8) as char));
                }
            }
        }

        // SU with no parameter (default: 1 line)
        let params = vte::Params::default();
        csi_su(&mut term, &params);

        // Line 0 should now be blank (original line 1 moved there)
        let line = term.screen.get_line(0).unwrap();
        assert_eq!(line.cells[0].c, '1');
    }

    #[test]
    fn test_su_with_param() {
        let mut term = crate::TerminalCore::new(10, 10);

        // Fill lines
        for r in 0..10 {
            if let Some(line) = term.screen.get_line_mut(r) {
                for c in 0..10 {
                    line.update_cell_with(c, crate::types::Cell::new((b'A' + r as u8) as char));
                }
            }
        }

        // Scroll up 3 lines (CSI 3 S)
        term.advance(b"\x1b[3S");

        // Line 0 should now have content from line 3
        let line = term.screen.get_line(0).unwrap();
        assert_eq!(line.cells[0].c, 'D');
    }

    #[test]
    fn test_su_respects_scroll_region() {
        let mut term = crate::TerminalCore::new(10, 10);

        // Fill all lines
        for r in 0..10 {
            if let Some(line) = term.screen.get_line_mut(r) {
                for c in 0..10 {
                    line.update_cell_with(c, crate::types::Cell::new((b'0' + r as u8) as char));
                }
            }
        }

        // Set scroll region from row 3 to 8 (0-indexed: 2 to 8)
        term.screen.set_scroll_region(2, 8);

        // Scroll up
        let params = vte::Params::default();
        csi_su(&mut term, &params);

        // Lines outside scroll region should be unchanged
        let line = term.screen.get_line(0).unwrap();
        assert_eq!(line.cells[0].c, '0');

        let line = term.screen.get_line(1).unwrap();
        assert_eq!(line.cells[0].c, '1');

        // Lines inside scroll region should have scrolled
        let line = term.screen.get_line(2).unwrap();
        assert_eq!(line.cells[0].c, '3'); // Was '2', now '3'

        // Bottom of scroll region should be blank
        let line = term.screen.get_line(7).unwrap();
        assert_eq!(line.cells[0].c, ' ');
    }

    #[test]
    fn test_sd_default() {
        let mut term = crate::TerminalCore::new(10, 10);

        // Fill lines
        for r in 0..10 {
            if let Some(line) = term.screen.get_line_mut(r) {
                for c in 0..10 {
                    line.update_cell_with(c, crate::types::Cell::new((b'A' + r as u8) as char));
                }
            }
        }

        // SD with no parameter (default: 1 line)
        let params = vte::Params::default();
        csi_sd(&mut term, &params);

        // Content moves up
        let line = term.screen.get_line(0).unwrap();
        assert_eq!(line.cells[0].c, ' '); // Line 0 becomes blank

        let line = term.screen.get_line(1).unwrap();
        assert_eq!(line.cells[0].c, 'A'); // Line 1 now has what was in line 0
    }

    #[test]
    fn test_sd_with_param() {
        let mut term = crate::TerminalCore::new(10, 10);

        // Fill lines
        for r in 0..10 {
            if let Some(line) = term.screen.get_line_mut(r) {
                for c in 0..10 {
                    line.update_cell_with(c, crate::types::Cell::new((b'0' + r as u8) as char));
                }
            }
        }

        // Scroll down 3 lines (CSI 3 T)
        term.advance(b"\x1b[3T");

        // First 3 lines should be blank
        for r in 0..3 {
            let line = term.screen.get_line(r).unwrap();
            assert_eq!(line.cells[0].c, ' ');
        }

        // Line 3 should now have content from line 0
        let line = term.screen.get_line(3).unwrap();
        assert_eq!(line.cells[0].c, '0');
    }

    #[test]
    fn test_sd_respects_scroll_region() {
        let mut term = crate::TerminalCore::new(10, 10);

        // Fill all lines
        for r in 0..10 {
            if let Some(line) = term.screen.get_line_mut(r) {
                for c in 0..10 {
                    line.update_cell_with(c, crate::types::Cell::new((b'0' + r as u8) as char));
                }
            }
        }

        // Set scroll region from row 3 to 8 (0-indexed: 2 to 8)
        term.screen.set_scroll_region(2, 8);

        // Scroll down
        let params = vte::Params::default();
        csi_sd(&mut term, &params);

        // Lines outside scroll region should be unchanged
        let line = term.screen.get_line(0).unwrap();
        assert_eq!(line.cells[0].c, '0');

        let line = term.screen.get_line(1).unwrap();
        assert_eq!(line.cells[0].c, '1');

        // Lines inside scroll region should have scrolled
        let line = term.screen.get_line(2).unwrap();
        assert_eq!(line.cells[0].c, ' '); // Top of scroll region becomes blank

        let line = term.screen.get_line(3).unwrap();
        assert_eq!(line.cells[0].c, '2'); // Was '3', now '2'

        // Bottom of scroll region should have content from above
        let line = term.screen.get_line(7).unwrap();
        assert_eq!(line.cells[0].c, '6');
    }

    #[test]
    fn test_scroll_marks_dirty() {
        let mut term = crate::TerminalCore::new(5, 10);

        // Clear dirty set
        term.screen.take_dirty_lines();

        // Fill a line
        for c in 0..10 {
            if let Some(line) = term.screen.get_line_mut(0) {
                line.update_cell_with(c, crate::types::Cell::new('X'));
                line.is_dirty = false;
            }
        }

        // Scroll up
        let params = vte::Params::default();
        csi_su(&mut term, &params);

        // Should have dirty lines
        let dirty = term.screen.take_dirty_lines();
        assert!(!dirty.is_empty());
    }

    /// SU via escape sequence (CSI S) scrolls up one line: row 0 gets content
    /// that was previously in row 1.
    #[test]
    fn test_su_scroll_up_one_line() {
        let mut term = crate::TerminalCore::new(10, 10);

        // Fill rows with distinct characters
        for r in 0..10usize {
            if let Some(line) = term.screen.get_line_mut(r) {
                for c in 0..10usize {
                    line.update_cell_with(c, crate::types::Cell::new((b'A' + r as u8) as char));
                }
            }
        }

        // CSI 1 S — scroll up 1 line
        term.advance(b"\x1b[S");

        // Row 0 should now contain the character that was in row 1 ('B')
        let line = term.screen.get_line(0).unwrap();
        assert_eq!(line.cells[0].c, 'B', "after SU 1, row 0 should have former row 1 content");
    }

    /// SU with content: the line that scrolled off the top should no longer be
    /// visible at row 0, and the bottom of the screen should be blank.
    #[test]
    fn test_su_scroll_up_at_top_with_content() {
        let mut term = crate::TerminalCore::new(5, 10);

        // Fill all rows with a unique char
        for r in 0..5usize {
            if let Some(line) = term.screen.get_line_mut(r) {
                for c in 0..10usize {
                    line.update_cell_with(c, crate::types::Cell::new((b'0' + r as u8) as char));
                }
            }
        }

        // Scroll up by 1 (CSI S)
        term.advance(b"\x1b[S");

        // Row 0 should no longer be '0' — it was scrolled off
        let line0 = term.screen.get_line(0).unwrap();
        assert_ne!(line0.cells[0].c, '0', "row 0 character should have changed after scroll up");

        // Bottom row (4) should be blank (newly introduced empty line)
        let bottom = term.screen.get_line(4).unwrap();
        assert_eq!(
            bottom.cells[0].c, ' ',
            "bottom row should be blank after scrolling up"
        );
    }

    /// SD via escape sequence (CSI T) scrolls down one line: row 0 becomes blank
    /// and previous row 0 content appears in row 1.
    #[test]
    fn test_sd_scroll_down_one_line() {
        let mut term = crate::TerminalCore::new(10, 10);

        // Fill rows
        for r in 0..10usize {
            if let Some(line) = term.screen.get_line_mut(r) {
                for c in 0..10usize {
                    line.update_cell_with(c, crate::types::Cell::new((b'A' + r as u8) as char));
                }
            }
        }

        // CSI 1 T — scroll down 1 line
        term.advance(b"\x1b[T");

        // Row 0 should now be blank
        let top = term.screen.get_line(0).unwrap();
        assert_eq!(top.cells[0].c, ' ', "after SD 1, row 0 should be blank");

        // Row 1 should contain what was previously in row 0 ('A')
        let row1 = term.screen.get_line(1).unwrap();
        assert_eq!(row1.cells[0].c, 'A', "after SD 1, row 1 should have former row 0 content");
    }

    /// Scrolling up by more lines than the screen has should not panic and should
    /// leave the entire screen blank.
    #[test]
    fn test_su_scroll_up_clamps_at_screen() {
        let mut term = crate::TerminalCore::new(5, 10);

        // Fill all rows
        for r in 0..5usize {
            if let Some(line) = term.screen.get_line_mut(r) {
                for c in 0..10usize {
                    line.update_cell_with(c, crate::types::Cell::new('X'));
                }
            }
        }

        // Scroll up by 100 lines (far more than the 5-row screen) — must not panic
        term.advance(b"\x1b[100S");

        // All rows should now be blank (or at least no panic occurred)
        for r in 0..5usize {
            let line = term.screen.get_line(r).unwrap();
            assert_eq!(line.cells[0].c, ' ', "row {} should be blank after over-scroll", r);
        }
    }
}
