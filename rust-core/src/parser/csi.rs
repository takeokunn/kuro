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
        let row = term.screen.cursor.row + 1; // Convert to 1-indexed
        let col = term.screen.cursor.col + 1;
        let response = format!("\x1b[{};{}R", row, col);
        term.pending_responses.push(response.into_bytes());
    }
}

/// VPA - Vertical Position Absolute (CSI d)
///
/// Move cursor to the specified row (1-indexed).
/// Column position is unchanged.
fn csi_vpa(term: &mut crate::TerminalCore, params: &vte::Params) {
    // VPA takes a 1-indexed row parameter
    let row = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .saturating_sub(1); // Convert to 0-indexed

    // Move cursor to absolute row, keep current column
    term.screen
        .move_cursor(row as usize, term.screen.cursor.col);
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
        .move_cursor(term.screen.cursor.row, col as usize);
}

/// HVP - Horizontal and Vertical Position (CSI f)
///
/// Move cursor to the specified row and column (1-indexed).
/// This is functionally identical to CUP (CSI H).
fn csi_hvp(term: &mut crate::TerminalCore, params: &vte::Params) {
    // HVP takes row, column parameters (both 1-indexed)
    let row = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .saturating_sub(1); // Convert to 0-indexed
    let col = params
        .iter()
        .nth(1)
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .saturating_sub(1); // Convert to 0-indexed

    // Move cursor to absolute position
    term.screen.move_cursor(row as usize, col as usize);
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
        let params = vte::Params::default();
        csi_vpa(&mut term, &params);

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

        // Try to move beyond screen bounds
        let params = vte::Params::default();
        csi_vpa(&mut term, &params);

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
        let params = vte::Params::default();
        csi_cha(&mut term, &params);

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

        // Try to move beyond screen bounds
        let params = vte::Params::default();
        csi_cha(&mut term, &params);

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
        let params = vte::Params::default();
        csi_hvp(&mut term, &params);

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

        // Start at (0, 0)
        // Move cursor to row only (column defaults to 1)
        let params = vte::Params::default();
        csi_hvp(&mut term, &params);

        // Should move to (4, 0) (row=5, col=1 in 1-indexed)
        assert_eq!(term.screen.cursor.row, 4);
        assert_eq!(term.screen.cursor.col, 0);
    }

    #[test]
    fn test_hvp_bounds() {
        let mut term = crate::TerminalCore::new(10, 50);

        // Try to move beyond screen bounds
        let params = vte::Params::default();
        csi_hvp(&mut term, &params);

        // Should clamp to screen boundaries
        assert_eq!(term.screen.cursor.row, 9); // 10 rows max
        assert_eq!(term.screen.cursor.col, 49); // 50 cols max
    }
}
