//! Insert and delete operations for VTE compliance
//!
//! This module implements:
//! - IL  (CSI Ps L): Insert Lines
//! - DL  (CSI Ps M): Delete Lines
//! - ICH (CSI Ps @): Insert Characters
//! - DCH (CSI Ps P): Delete Characters
//! - ECH (CSI Ps X): Erase Characters

/// Dispatch IL / DL / ICH / DCH / ECH sequences
pub fn handle_insert_delete(term: &mut crate::TerminalCore, params: &vte::Params, c: char) {
    match c {
        'L' => csi_il(term, params),
        'M' => csi_dl(term, params),
        '@' => csi_ich(term, params),
        'P' => csi_dch(term, params),
        'X' => csi_ech(term, params),
        _ => {}
    }
}

/// Extract the first parameter, defaulting to 1 (minimum 1).
fn get_param(params: &vte::Params) -> usize {
    params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .max(1) as usize
}

/// IL — Insert Lines (CSI Ps L)
fn csi_il(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = get_param(params);
    term.screen.insert_lines(n);
}

/// DL — Delete Lines (CSI Ps M)
fn csi_dl(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = get_param(params);
    term.screen.delete_lines(n);
}

/// ICH — Insert Characters (CSI Ps @)
fn csi_ich(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = get_param(params);
    let attrs = term.current_attrs;
    term.screen.insert_chars(n, attrs);
}

/// DCH — Delete Characters (CSI Ps P)
fn csi_dch(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = get_param(params);
    term.screen.delete_chars(n);
}

/// ECH — Erase Characters (CSI Ps X)
fn csi_ech(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = get_param(params);
    let attrs = term.current_attrs;
    term.screen.erase_chars(n, attrs);
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Fill every cell in `row` with character `c`
    fn fill_line(term: &mut crate::TerminalCore, row: usize, c: char) {
        if let Some(line) = term.screen.get_line_mut(row) {
            for cell in &mut line.cells {
                cell.c = c;
            }
        }
    }

    /// Return the character at (row, col), or ' ' if out of bounds
    fn char_at(term: &crate::TerminalCore, row: usize, col: usize) -> char {
        term.screen.get_cell(row, col).map(|c| c.c).unwrap_or(' ')
    }

    // ── IL (Insert Lines) ──────────────────────────────────────────────────

    #[test]
    fn test_il_basic() {
        let mut term = crate::TerminalCore::new(10, 10);
        for r in 0..5 {
            fill_line(&mut term, r, (b'A' + r as u8) as char);
        }
        term.screen.move_cursor(2, 0);

        let params = vte::Params::default();
        csi_il(&mut term, &params); // IL 1

        assert_eq!(char_at(&term, 2, 0), ' '); // newly inserted blank
        assert_eq!(char_at(&term, 3, 0), 'C'); // original row 2 shifted down
        assert_eq!(char_at(&term, 4, 0), 'D'); // original row 3 shifted down
    }

    #[test]
    fn test_il_default_param_is_one() {
        let mut term = crate::TerminalCore::new(5, 10);
        fill_line(&mut term, 0, 'A');
        fill_line(&mut term, 1, 'B');
        term.screen.move_cursor(0, 0);

        let params = vte::Params::default();
        csi_il(&mut term, &params);

        assert_eq!(char_at(&term, 0, 0), ' '); // new blank
        assert_eq!(char_at(&term, 1, 0), 'A'); // shifted
        assert_eq!(char_at(&term, 2, 0), 'B'); // shifted
    }

    #[test]
    fn test_il_respects_scroll_region() {
        let mut term = crate::TerminalCore::new(10, 10);
        for r in 0..10 {
            fill_line(&mut term, r, (b'0' + r as u8) as char);
        }
        // scroll region rows [2, 7)
        term.screen.set_scroll_region(2, 7);
        term.screen.move_cursor(3, 0);

        term.advance(b"\x1b[2L"); // IL 2

        // Above scroll region: untouched
        assert_eq!(char_at(&term, 0, 0), '0');
        assert_eq!(char_at(&term, 1, 0), '1');
        assert_eq!(char_at(&term, 2, 0), '2'); // cursor was below this row
                                               // Two blank lines inserted at row 3
        assert_eq!(char_at(&term, 3, 0), ' ');
        assert_eq!(char_at(&term, 4, 0), ' ');
        // Original rows 3,4 shifted to 5,6
        assert_eq!(char_at(&term, 5, 0), '3');
        assert_eq!(char_at(&term, 6, 0), '4');
        // Below scroll region: untouched
        assert_eq!(char_at(&term, 7, 0), '7');
        assert_eq!(char_at(&term, 9, 0), '9');
    }

    #[test]
    fn test_il_noop_when_cursor_above_scroll_region() {
        let mut term = crate::TerminalCore::new(10, 10);
        for r in 0..10 {
            fill_line(&mut term, r, (b'0' + r as u8) as char);
        }
        term.screen.set_scroll_region(3, 8);
        term.screen.move_cursor(1, 0); // above top=3

        let params = vte::Params::default();
        csi_il(&mut term, &params);

        for r in 0..10 {
            assert_eq!(char_at(&term, r, 0), (b'0' + r as u8) as char);
        }
    }

    #[test]
    fn test_il_noop_when_cursor_below_scroll_region() {
        let mut term = crate::TerminalCore::new(10, 10);
        for r in 0..10 {
            fill_line(&mut term, r, (b'0' + r as u8) as char);
        }
        term.screen.set_scroll_region(2, 6);
        term.screen.move_cursor(8, 0); // at or below bottom=6

        let params = vte::Params::default();
        csi_il(&mut term, &params);

        for r in 0..10 {
            assert_eq!(char_at(&term, r, 0), (b'0' + r as u8) as char);
        }
    }

    #[test]
    fn test_il_dirty_tracking() {
        let mut term = crate::TerminalCore::new(5, 10);
        term.screen.take_dirty_lines();
        term.screen.move_cursor(1, 0);

        let params = vte::Params::default();
        csi_il(&mut term, &params);

        let dirty = term.screen.take_dirty_lines();
        assert!(dirty.contains(&1));
        assert!(dirty.contains(&2));
        assert!(dirty.contains(&4));
    }

    #[test]
    fn test_il_integration_via_advance() {
        let mut term = crate::TerminalCore::new(10, 10);
        fill_line(&mut term, 0, 'A');
        fill_line(&mut term, 1, 'B');
        fill_line(&mut term, 2, 'C');
        term.screen.move_cursor(1, 0);

        term.advance(b"\x1b[L"); // CSI L (default 1)

        assert_eq!(char_at(&term, 1, 0), ' ');
        assert_eq!(char_at(&term, 2, 0), 'B');
        assert_eq!(char_at(&term, 3, 0), 'C');
    }

    // ── DL (Delete Lines) ──────────────────────────────────────────────────

    #[test]
    fn test_dl_basic() {
        let mut term = crate::TerminalCore::new(10, 10);
        for r in 0..5 {
            fill_line(&mut term, r, (b'A' + r as u8) as char);
        }
        term.screen.move_cursor(1, 0);

        let params = vte::Params::default();
        csi_dl(&mut term, &params); // DL 1

        // 'B' (row 1) is deleted; 'C' shifts up
        assert_eq!(char_at(&term, 1, 0), 'C');
        assert_eq!(char_at(&term, 2, 0), 'D');
        assert_eq!(char_at(&term, 9, 0), ' '); // blank filled at bottom
    }

    #[test]
    fn test_dl_respects_scroll_region() {
        let mut term = crate::TerminalCore::new(10, 10);
        for r in 0..10 {
            fill_line(&mut term, r, (b'0' + r as u8) as char);
        }
        // scroll region rows [2, 7)
        term.screen.set_scroll_region(2, 7);
        term.screen.move_cursor(3, 0);

        term.advance(b"\x1b[2M"); // DL 2

        // Above region: untouched
        assert_eq!(char_at(&term, 0, 0), '0');
        assert_eq!(char_at(&term, 1, 0), '1');
        assert_eq!(char_at(&term, 2, 0), '2');
        // Rows 3,4 deleted; original row 5 shifts to 3
        assert_eq!(char_at(&term, 3, 0), '5');
        assert_eq!(char_at(&term, 4, 0), '6');
        // Bottom of region filled with blanks
        assert_eq!(char_at(&term, 5, 0), ' ');
        assert_eq!(char_at(&term, 6, 0), ' ');
        // Below region: untouched
        assert_eq!(char_at(&term, 7, 0), '7');
    }

    #[test]
    fn test_dl_noop_when_cursor_above_scroll_region() {
        let mut term = crate::TerminalCore::new(10, 10);
        for r in 0..10 {
            fill_line(&mut term, r, (b'0' + r as u8) as char);
        }
        term.screen.set_scroll_region(3, 8);
        term.screen.move_cursor(1, 0); // above top=3

        let params = vte::Params::default();
        csi_dl(&mut term, &params);

        for r in 0..10 {
            assert_eq!(char_at(&term, r, 0), (b'0' + r as u8) as char);
        }
    }

    #[test]
    fn test_dl_noop_when_cursor_below_scroll_region() {
        let mut term = crate::TerminalCore::new(10, 10);
        for r in 0..10 {
            fill_line(&mut term, r, (b'0' + r as u8) as char);
        }
        term.screen.set_scroll_region(2, 6);
        term.screen.move_cursor(8, 0); // at or below bottom=6

        let params = vte::Params::default();
        csi_dl(&mut term, &params);

        for r in 0..10 {
            assert_eq!(char_at(&term, r, 0), (b'0' + r as u8) as char);
        }
    }

    #[test]
    fn test_dl_dirty_tracking() {
        let mut term = crate::TerminalCore::new(5, 10);
        term.screen.take_dirty_lines();
        term.screen.move_cursor(1, 0);

        let params = vte::Params::default();
        csi_dl(&mut term, &params);

        let dirty = term.screen.take_dirty_lines();
        assert!(dirty.contains(&1));
        assert!(dirty.contains(&4));
    }

    // ── ICH (Insert Characters) ────────────────────────────────────────────

    #[test]
    fn test_ich_basic() {
        let mut term = crate::TerminalCore::new(5, 10);
        fill_line(&mut term, 0, 'A');
        term.screen.move_cursor(0, 2);

        let params = vte::Params::default();
        csi_ich(&mut term, &params); // ICH 1

        assert_eq!(char_at(&term, 0, 1), 'A'); // left of cursor: untouched
        assert_eq!(char_at(&term, 0, 2), ' '); // inserted blank
        assert_eq!(char_at(&term, 0, 3), 'A'); // original col 2 shifted right
        assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 10); // width preserved
    }

    #[test]
    fn test_ich_clips_to_right_margin() {
        let mut term = crate::TerminalCore::new(5, 10);
        fill_line(&mut term, 0, 'A');
        term.screen.move_cursor(0, 8); // 2 cols from right margin

        term.advance(b"\x1b[5@"); // ICH 5: clamped to 2

        assert_eq!(char_at(&term, 0, 8), ' ');
        assert_eq!(char_at(&term, 0, 9), ' ');
        assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 10);
    }

    #[test]
    fn test_ich_dirty_tracking() {
        let mut term = crate::TerminalCore::new(5, 10);
        term.screen.take_dirty_lines();
        term.screen.move_cursor(2, 3);

        term.advance(b"\x1b[@"); // ICH 1

        let dirty = term.screen.take_dirty_lines();
        assert!(dirty.contains(&2));
    }

    // ── DCH (Delete Characters) ────────────────────────────────────────────

    #[test]
    fn test_dch_basic() {
        let mut term = crate::TerminalCore::new(5, 10);
        // Fill row 0 with '0'..'9'
        if let Some(line) = term.screen.get_line_mut(0) {
            for (i, cell) in line.cells.iter_mut().enumerate() {
                cell.c = (b'0' + i as u8) as char;
            }
        }
        term.screen.move_cursor(0, 2);

        let params = vte::Params::default();
        csi_dch(&mut term, &params); // DCH 1

        assert_eq!(char_at(&term, 0, 2), '3'); // '3' shifted left to col 2
        assert_eq!(char_at(&term, 0, 9), ' '); // blank fills right end
        assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 10);
    }

    #[test]
    fn test_dch_clips_to_right_margin() {
        let mut term = crate::TerminalCore::new(5, 10);
        fill_line(&mut term, 0, 'A');
        term.screen.move_cursor(0, 8); // 2 cols from right

        term.advance(b"\x1b[10P"); // DCH 10: clamped to 2

        assert_eq!(char_at(&term, 0, 8), ' ');
        assert_eq!(char_at(&term, 0, 9), ' ');
        assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 10);
    }

    #[test]
    fn test_dch_dirty_tracking() {
        let mut term = crate::TerminalCore::new(5, 10);
        term.screen.take_dirty_lines();
        term.screen.move_cursor(3, 1);

        term.advance(b"\x1b[P"); // DCH 1

        let dirty = term.screen.take_dirty_lines();
        assert!(dirty.contains(&3));
    }

    // ── ECH (Erase Characters) ─────────────────────────────────────────────

    #[test]
    fn test_ech_basic() {
        let mut term = crate::TerminalCore::new(5, 10);
        fill_line(&mut term, 0, 'A');
        term.screen.move_cursor(0, 3);

        let params = vte::Params::default();
        csi_ech(&mut term, &params); // ECH 1

        assert_eq!(char_at(&term, 0, 2), 'A'); // left: untouched
        assert_eq!(char_at(&term, 0, 3), ' '); // erased
        assert_eq!(char_at(&term, 0, 4), 'A'); // right: untouched
                                               // Cursor must NOT move
        assert_eq!(term.screen.cursor().col, 3);
    }

    #[test]
    fn test_ech_clips_to_right_margin() {
        let mut term = crate::TerminalCore::new(5, 10);
        fill_line(&mut term, 0, 'A');
        term.screen.move_cursor(0, 8);

        term.advance(b"\x1b[20X"); // ECH 20: clamped to cols 8-9

        assert_eq!(char_at(&term, 0, 7), 'A'); // left: untouched
        assert_eq!(char_at(&term, 0, 8), ' '); // erased
        assert_eq!(char_at(&term, 0, 9), ' '); // erased
    }

    #[test]
    fn test_ech_uses_sgr_background() {
        let mut term = crate::TerminalCore::new(5, 10);
        fill_line(&mut term, 0, 'A');
        term.advance(b"\x1b[41m"); // SGR 41: red background
        term.screen.move_cursor(0, 2);

        term.advance(b"\x1b[3X"); // ECH 3

        let cell = term.screen.get_cell(0, 2).unwrap();
        assert_eq!(cell.c, ' ');
        // Erased cell must carry the current SGR background (not the default)
        assert_ne!(cell.attrs.background, crate::Color::Default);
    }

    #[test]
    fn test_ech_dirty_tracking() {
        let mut term = crate::TerminalCore::new(5, 10);
        fill_line(&mut term, 1, 'A');
        term.screen.take_dirty_lines();
        term.screen.move_cursor(1, 0);

        term.advance(b"\x1b[X"); // ECH 1

        let dirty = term.screen.take_dirty_lines();
        assert!(dirty.contains(&1));
    }
}
