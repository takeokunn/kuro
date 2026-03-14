//! CSI (Control Sequence Introducer) cursor positioning sequences

/// Handle CSI cursor positioning sequences
///
/// This module implements:
/// - CUP (CSI H): Cursor Position (row;col)
/// - CUU (CSI A): Cursor Up
/// - CUD (CSI B): Cursor Down
/// - CUF (CSI C): Cursor Forward (right)
/// - CUB (CSI D): Cursor Back (left)
/// - VPA (CSI d): Vertical Position Absolute
/// - CHA (CSI G): Character Position Absolute
/// - HVP (CSI f): Horizontal and Vertical Position (same as CUP)
/// - DSR (CSI n): Device Status Report (cursor position query)
pub fn handle_csi_cursor(term: &mut crate::TerminalCore, params: &vte::Params, c: char) {
    match c {
        'H' => csi_cup(term, params), // CUP - Cursor Position
        'A' => csi_cuu(term, params), // CUU - Cursor Up
        'B' => csi_cud(term, params), // CUD - Cursor Down
        'C' => csi_cuf(term, params), // CUF - Cursor Forward
        'D' => csi_cub(term, params), // CUB - Cursor Back
        'd' => csi_vpa(term, params), // VPA - Vertical Position Absolute
        'G' => csi_cha(term, params), // CHA - Character Position Absolute
        'f' => csi_hvp(term, params), // HVP - Horizontal and Vertical Position
        'n' => csi_dsr(term, params), // DSR - Device Status Report
        _ => {}
    }
}

/// CUP - Cursor Position (CSI H)
///
/// Move cursor to the specified row and column (1-indexed).
/// Functionally identical to HVP (CSI f).
fn csi_cup(term: &mut crate::TerminalCore, params: &vte::Params) {
    csi_hvp(term, params);
}

/// CUU - Cursor Up (CSI A)
///
/// Move cursor up by N rows (default 1). Stops at top of screen.
fn csi_cuu(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .max(1) as i32;

    term.screen.move_cursor_by(-n, 0);
}

/// CUD - Cursor Down (CSI B)
///
/// Move cursor down by N rows (default 1). Stops at bottom of screen.
fn csi_cud(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .max(1) as i32;

    term.screen.move_cursor_by(n, 0);
}

/// CUF - Cursor Forward (CSI C)
///
/// Move cursor right by N columns (default 1). Stops at right margin.
fn csi_cuf(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .max(1) as i32;

    term.screen.move_cursor_by(0, n);
}

/// CUB - Cursor Back (CSI D)
///
/// Move cursor left by N columns (default 1). Stops at left margin.
fn csi_cub(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .max(1) as i32;

    term.screen.move_cursor_by(0, -n);
}

/// DSR - Device Status Report (CSI n)
///
/// Param 6: respond with current cursor position as ESC[row;colR (1-indexed).
fn csi_dsr(term: &mut crate::TerminalCore, params: &vte::Params) {
    let code = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(0);

    if code == 6 {
        let row = term.screen.cursor().row + 1; // Convert to 1-indexed
        let col = term.screen.cursor().col + 1;
        let response = format!("\x1b[{};{}R", row, col);
        term.pending_responses.push(response.into_bytes());
    }
}

/// VPA - Vertical Position Absolute (CSI d)
///
/// Move cursor to the specified row (1-indexed).
/// Column position is unchanged.
/// When DECOM (origin mode) is active, row is relative to scroll region top.
fn csi_vpa(term: &mut crate::TerminalCore, params: &vte::Params) {
    // VPA takes a 1-indexed row parameter
    let row = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .saturating_sub(1) as usize; // Convert to 0-indexed

    let target_row = if term.dec_modes.origin_mode {
        // In origin mode, row is relative to scroll region top
        let scroll_top = term.screen.get_scroll_region().top;
        let scroll_bottom = term.screen.get_scroll_region().bottom;
        (scroll_top + row).min(scroll_bottom.saturating_sub(1))
    } else {
        row
    };

    // Move cursor to absolute row, keep current column
    term.screen
        .move_cursor(target_row, term.screen.cursor().col);
}

/// CHA - Character Position Absolute (CSI G)
///
/// Move cursor to the specified column (1-indexed).
/// Row position is unchanged.
fn csi_cha(term: &mut crate::TerminalCore, params: &vte::Params) {
    // CHA takes a 1-indexed column parameter
    let col = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .saturating_sub(1); // Convert to 0-indexed

    // Move cursor to absolute column, keep current row
    term.screen
        .move_cursor(term.screen.cursor().row, col as usize);
}

/// HVP - Horizontal and Vertical Position (CSI f)
///
/// Move cursor to the specified row and column (1-indexed).
/// This is functionally identical to CUP (CSI H).
/// When DECOM (origin mode) is active, coordinates are relative to scroll region.
fn csi_hvp(term: &mut crate::TerminalCore, params: &vte::Params) {
    // HVP takes row, column parameters (both 1-indexed)
    let row = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .saturating_sub(1) as usize; // Convert to 0-indexed
    let col = params
        .iter()
        .nth(1)
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .saturating_sub(1) as usize; // Convert to 0-indexed

    let (target_row, target_col) = if term.dec_modes.origin_mode {
        // In origin mode, coordinates are relative to scroll region
        let scroll_top = term.screen.get_scroll_region().top;
        let scroll_bottom = term.screen.get_scroll_region().bottom;
        let abs_row = (scroll_top + row).min(scroll_bottom.saturating_sub(1));
        (abs_row, col)
    } else {
        (row, col)
    };

    // Move cursor to absolute position
    term.screen.move_cursor(target_row, target_col);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_vpa_move_cursor() {
        let mut term = crate::TerminalCore::new(24, 80);

        // Start at (0, 0)
        assert_eq!(term.screen.cursor.row, 0);
        assert_eq!(term.screen.cursor.col, 0);

        // Move cursor to row 5 (1-indexed: CSI 5 d)
        term.advance(b"\x1b[5d");

        // Should move to row 4 (0-indexed), column unchanged
        assert_eq!(term.screen.cursor.row, 4);
        assert_eq!(term.screen.cursor.col, 0);
    }

    #[test]
    fn test_vpa_default() {
        let mut term = crate::TerminalCore::new(24, 80);

        // Move cursor to row 10
        term.screen.move_cursor(9, 0);
        assert_eq!(term.screen.cursor.row, 9);

        // VPA with no parameter defaults to row 1
        let params = vte::Params::default();
        csi_vpa(&mut term, &params);

        // Should move to row 0 (1-indexed: 1)
        assert_eq!(term.screen.cursor.row, 0);
    }

    #[test]
    fn test_vpa_bounds() {
        let mut term = crate::TerminalCore::new(10, 80);

        // Try to move beyond screen bounds (CSI 100 d)
        term.advance(b"\x1b[100d");

        // Should clamp to screen boundary (row 9 for 10 rows)
        assert_eq!(term.screen.cursor.row, 9);
    }

    #[test]
    fn test_cha_move_cursor() {
        let mut term = crate::TerminalCore::new(24, 80);

        // Start at (0, 0)
        assert_eq!(term.screen.cursor.row, 0);
        assert_eq!(term.screen.cursor.col, 0);

        // Move cursor to column 20 (1-indexed: CSI 20 G)
        term.advance(b"\x1b[20G");

        // Should move to column 19 (0-indexed), row unchanged
        assert_eq!(term.screen.cursor.row, 0);
        assert_eq!(term.screen.cursor.col, 19);
    }

    #[test]
    fn test_cha_default() {
        let mut term = crate::TerminalCore::new(24, 80);

        // Move cursor to column 30
        term.screen.move_cursor(0, 29);
        assert_eq!(term.screen.cursor.col, 29);

        // CHA with no parameter defaults to column 1
        let params = vte::Params::default();
        csi_cha(&mut term, &params);

        // Should move to column 0 (1-indexed: 1)
        assert_eq!(term.screen.cursor.col, 0);
    }

    #[test]
    fn test_cha_bounds() {
        let mut term = crate::TerminalCore::new(24, 50);

        // Try to move beyond screen bounds (CSI 100 G)
        term.advance(b"\x1b[100G");

        // Should clamp to screen boundary (col 49 for 50 cols)
        assert_eq!(term.screen.cursor.col, 49);
    }

    #[test]
    fn test_hvp_move_cursor() {
        let mut term = crate::TerminalCore::new(24, 80);

        // Start at (0, 0)
        assert_eq!(term.screen.cursor.row, 0);
        assert_eq!(term.screen.cursor.col, 0);

        // Move cursor to (row=10, col=30) (1-indexed: CSI 10;30 f)
        term.advance(b"\x1b[10;30f");

        // Should move to (9, 29) (0-indexed)
        assert_eq!(term.screen.cursor.row, 9);
        assert_eq!(term.screen.cursor.col, 29);
    }

    #[test]
    fn test_hvp_default() {
        let mut term = crate::TerminalCore::new(24, 80);

        // Move cursor to (15, 40)
        term.screen.move_cursor(14, 39);

        // HVP with no parameters defaults to (1, 1)
        let params = vte::Params::default();
        csi_hvp(&mut term, &params);

        // Should move to (0, 0) (1-indexed: 1,1)
        assert_eq!(term.screen.cursor.row, 0);
        assert_eq!(term.screen.cursor.col, 0);
    }

    #[test]
    fn test_hvp_partial_params() {
        let mut term = crate::TerminalCore::new(24, 80);

        // Move cursor to row 5 only (column defaults to 1): CSI 5 f
        term.advance(b"\x1b[5f");

        // Should move to (4, 0) (row=5, col=1 in 1-indexed)
        assert_eq!(term.screen.cursor.row, 4);
        assert_eq!(term.screen.cursor.col, 0);
    }

    #[test]
    fn test_hvp_bounds() {
        let mut term = crate::TerminalCore::new(10, 50);

        // Try to move beyond screen bounds (CSI 100;100 f)
        term.advance(b"\x1b[100;100f");

        // Should clamp to screen boundaries
        assert_eq!(term.screen.cursor.row, 9); // 10 rows max
        assert_eq!(term.screen.cursor.col, 49); // 50 cols max
    }

    // --- CUU (Cursor Up) tests ---

    #[test]
    fn test_cuu_move_cursor_up() {
        let mut term = crate::TerminalCore::new(24, 80);

        // Move cursor to row 5 (0-indexed) via CUP: CSI 6;1H (1-indexed)
        term.advance(b"\x1b[6;1H");
        assert_eq!(term.screen.cursor.row, 5);
        assert_eq!(term.screen.cursor.col, 0);

        // CUU 3: move up 3 rows (CSI 3 A)
        term.advance(b"\x1b[3A");

        // Should land at row 2 (0-indexed)
        assert_eq!(term.screen.cursor.row, 2);
        assert_eq!(term.screen.cursor.col, 0);
    }

    #[test]
    fn test_cuu_default() {
        let mut term = crate::TerminalCore::new(24, 80);

        // Move cursor to row 4 (0-indexed)
        term.screen.move_cursor(4, 0);
        assert_eq!(term.screen.cursor.row, 4);

        // CUU with no parameter defaults to 1: CSI A
        let params = vte::Params::default();
        csi_cuu(&mut term, &params);

        // Should move up 1 row to row 3
        assert_eq!(term.screen.cursor.row, 3);
        assert_eq!(term.screen.cursor.col, 0);
    }

    #[test]
    fn test_cuu_clamps_at_top() {
        let mut term = crate::TerminalCore::new(24, 80);

        // Cursor starts at row 0 (top)
        assert_eq!(term.screen.cursor.row, 0);

        // CUU 5 from row 0: should clamp to row 0
        term.advance(b"\x1b[5A");

        assert_eq!(term.screen.cursor.row, 0);
    }

    // --- CUD (Cursor Down) tests ---

    #[test]
    fn test_cud_move_cursor_down() {
        let mut term = crate::TerminalCore::new(24, 80);

        // Cursor starts at row 0
        assert_eq!(term.screen.cursor.row, 0);

        // CUD 4: move down 4 rows (CSI 4 B)
        term.advance(b"\x1b[4B");

        // Should land at row 4 (0-indexed)
        assert_eq!(term.screen.cursor.row, 4);
        assert_eq!(term.screen.cursor.col, 0);
    }

    #[test]
    fn test_cud_default() {
        let mut term = crate::TerminalCore::new(24, 80);

        // Move cursor to row 3 (0-indexed)
        term.screen.move_cursor(3, 0);
        assert_eq!(term.screen.cursor.row, 3);

        // CUD with no parameter defaults to 1: CSI B
        let params = vte::Params::default();
        csi_cud(&mut term, &params);

        // Should move down 1 row to row 4
        assert_eq!(term.screen.cursor.row, 4);
        assert_eq!(term.screen.cursor.col, 0);
    }

    #[test]
    fn test_cud_clamps_at_bottom() {
        let mut term = crate::TerminalCore::new(10, 80);

        // Move cursor to last row (row 9, 0-indexed)
        term.screen.move_cursor(9, 0);
        assert_eq!(term.screen.cursor.row, 9);

        // CUD 5 from last row: should clamp to last row
        term.advance(b"\x1b[5B");

        assert_eq!(term.screen.cursor.row, 9);
    }

    // --- CUF (Cursor Forward / Right) tests ---

    #[test]
    fn test_cuf_move_cursor_right() {
        let mut term = crate::TerminalCore::new(24, 80);

        // Cursor starts at col 0
        assert_eq!(term.screen.cursor.col, 0);

        // CUF 10: move right 10 columns (CSI 10 C)
        term.advance(b"\x1b[10C");

        // Should land at col 10 (0-indexed)
        assert_eq!(term.screen.cursor.row, 0);
        assert_eq!(term.screen.cursor.col, 10);
    }

    #[test]
    fn test_cuf_default() {
        let mut term = crate::TerminalCore::new(24, 80);

        // Move cursor to col 5 (0-indexed)
        term.screen.move_cursor(0, 5);
        assert_eq!(term.screen.cursor.col, 5);

        // CUF with no parameter defaults to 1: CSI C
        let params = vte::Params::default();
        csi_cuf(&mut term, &params);

        // Should move right 1 column to col 6
        assert_eq!(term.screen.cursor.row, 0);
        assert_eq!(term.screen.cursor.col, 6);
    }

    #[test]
    fn test_cuf_clamps_at_right_margin() {
        let mut term = crate::TerminalCore::new(24, 50);

        // Move cursor to last col (col 49, 0-indexed)
        term.screen.move_cursor(0, 49);
        assert_eq!(term.screen.cursor.col, 49);

        // CUF 5 from last col: should clamp to last col
        term.advance(b"\x1b[5C");

        assert_eq!(term.screen.cursor.col, 49);
    }

    // --- CUB (Cursor Back / Left) tests ---

    #[test]
    fn test_cub_move_cursor_left() {
        let mut term = crate::TerminalCore::new(24, 80);

        // Move cursor to col 15 (0-indexed)
        term.screen.move_cursor(0, 15);
        assert_eq!(term.screen.cursor.col, 15);

        // CUB 7: move left 7 columns (CSI 7 D)
        term.advance(b"\x1b[7D");

        // Should land at col 8 (0-indexed)
        assert_eq!(term.screen.cursor.row, 0);
        assert_eq!(term.screen.cursor.col, 8);
    }

    #[test]
    fn test_cub_default() {
        let mut term = crate::TerminalCore::new(24, 80);

        // Move cursor to col 10 (0-indexed)
        term.screen.move_cursor(0, 10);
        assert_eq!(term.screen.cursor.col, 10);

        // CUB with no parameter defaults to 1: CSI D
        let params = vte::Params::default();
        csi_cub(&mut term, &params);

        // Should move left 1 column to col 9
        assert_eq!(term.screen.cursor.row, 0);
        assert_eq!(term.screen.cursor.col, 9);
    }

    #[test]
    fn test_cub_clamps_at_left_margin() {
        let mut term = crate::TerminalCore::new(24, 80);

        // Cursor starts at col 0 (left margin)
        assert_eq!(term.screen.cursor.col, 0);

        // CUB 5 from col 0: should clamp to col 0
        term.advance(b"\x1b[5D");

        assert_eq!(term.screen.cursor.col, 0);
    }

    // --- CUP (Cursor Position) tests ---

    #[test]
    fn test_cup_absolute_position() {
        let mut term = crate::TerminalCore::new(24, 80);

        // Start at (0, 0)
        assert_eq!(term.screen.cursor.row, 0);
        assert_eq!(term.screen.cursor.col, 0);

        // CUP to (row=8, col=25) in 1-indexed: CSI 8;25H
        term.advance(b"\x1b[8;25H");

        // Should move to (7, 24) in 0-indexed
        assert_eq!(term.screen.cursor.row, 7);
        assert_eq!(term.screen.cursor.col, 24);
    }

    #[test]
    fn test_cup_default() {
        let mut term = crate::TerminalCore::new(24, 80);

        // Move cursor to an arbitrary position first
        term.screen.move_cursor(10, 30);
        assert_eq!(term.screen.cursor.row, 10);
        assert_eq!(term.screen.cursor.col, 30);

        // CUP with no parameters defaults to (1, 1): CSI H
        term.advance(b"\x1b[H");

        // Should move to (0, 0) in 0-indexed (row=1, col=1 in 1-indexed)
        assert_eq!(term.screen.cursor.row, 0);
        assert_eq!(term.screen.cursor.col, 0);
    }

    #[test]
    fn test_cup_bounds() {
        let mut term = crate::TerminalCore::new(10, 50);

        // CUP beyond screen bounds: CSI 100;100H
        term.advance(b"\x1b[100;100H");

        // Should clamp to screen boundaries
        assert_eq!(term.screen.cursor.row, 9); // 10 rows max
        assert_eq!(term.screen.cursor.col, 49); // 50 cols max
    }
}
