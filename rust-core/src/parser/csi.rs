//! CSI (Control Sequence Introducer) cursor positioning sequences

use crate::types::cursor::CursorShape;

/// Handle CSI cursor positioning sequences
///
/// This module implements:
/// - CUP (CSI H): Cursor Position (row;col)
/// - CUU (CSI A): Cursor Up
/// - CUD (CSI B): Cursor Down
/// - CUF (CSI C): Cursor Forward (right)
/// - CUB (CSI D): Cursor Back (left)
/// - CNL (CSI E): Cursor Next Line (down N, column 0)
/// - CPL (CSI F): Cursor Previous Line (up N, column 0)
/// - VPA (CSI d): Vertical Position Absolute
/// - CHA (CSI G): Character Position Absolute
/// - HVP (CSI f): Horizontal and Vertical Position (same as CUP)
/// - DSR (CSI n): Device Status Report (cursor position query)
///
/// Note: cursor boundary clamping uses screen bounds (rows-1 / 0), not
/// scroll-region margins. This matches CUU/CUD behaviour in this codebase.
#[inline]
pub fn handle_csi_cursor(term: &mut crate::TerminalCore, params: &vte::Params, c: char) {
    match c {
        'H' => csi_cup(term, params), // CUP - Cursor Position
        'A' => csi_cuu(term, params), // CUU - Cursor Up
        'B' => csi_cud(term, params), // CUD - Cursor Down
        'C' => csi_cuf(term, params), // CUF - Cursor Forward
        'D' => csi_cub(term, params), // CUB - Cursor Back
        'E' => csi_cnl(term, params), // CNL - Cursor Next Line
        'F' => csi_cpl(term, params), // CPL - Cursor Previous Line
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
#[inline]
fn csi_cup(term: &mut crate::TerminalCore, params: &vte::Params) {
    csi_hvp(term, params);
}

/// CUU - Cursor Up (CSI A)
///
/// Move cursor up by N rows (default 1). Stops at top of screen.
#[inline]
fn csi_cuu(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = i32::from(params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .max(1));

    term.screen.move_cursor_by(-n, 0);
}

/// CUD - Cursor Down (CSI B)
///
/// Move cursor down by N rows (default 1). Stops at bottom of screen.
#[inline]
fn csi_cud(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = i32::from(params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .max(1));

    term.screen.move_cursor_by(n, 0);
}

/// CUF - Cursor Forward (CSI C)
///
/// Move cursor right by N columns (default 1). Stops at right margin.
#[inline]
fn csi_cuf(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = i32::from(params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .max(1));

    term.screen.move_cursor_by(0, n);
}

/// CUB - Cursor Back (CSI D)
///
/// Move cursor left by N columns (default 1). Stops at left margin.
#[inline]
fn csi_cub(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = i32::from(params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .max(1));

    term.screen.move_cursor_by(0, -n);
}

/// CNL - Cursor Next Line (CSI E)
///
/// Move cursor down by N rows (default 1) and to column 0.
/// Does not cause scrolling (unlike LF, which scrolls at the scroll region's bottom margin).
/// Stops at the bottom of the screen (screen boundary, not scroll region).
#[inline]
fn csi_cnl(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = i32::from(params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .max(1));

    term.screen.move_cursor_by(n, 0);
    let row = term.screen.cursor().row;
    term.screen.move_cursor(row, 0);
}

/// CPL - Cursor Previous Line (CSI F)
///
/// Move cursor up by N rows (default 1) and to column 0.
/// Used by progress-bar libraries (e.g. nix) to overwrite previous output lines.
/// Stops at the top of the screen (screen boundary, not scroll region).
#[inline]
fn csi_cpl(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = i32::from(params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .max(1));

    term.screen.move_cursor_by(-n, 0);
    let row = term.screen.cursor().row;
    term.screen.move_cursor(row, 0);
}

/// DSR - Device Status Report (CSI n)
///
/// Param 6: respond with current cursor position as ESC[row;colR (1-indexed).
#[inline]
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
        let response = format!("\x1b[{row};{col}R");
        term.meta.pending_responses.push(response.into_bytes());
    }
}

/// VPA - Vertical Position Absolute (CSI d)
///
/// Move cursor to the specified row (1-indexed).
/// Column position is unchanged.
/// When DECOM (origin mode) is active, row is relative to scroll region top.
#[inline]
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
#[inline]
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
#[inline]
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

/// DECSCUSR - Set Cursor Style (CSI Ps SP q)
///
/// Maps the `Ps` parameter to a [`CursorShape`]:
///   0 / 1 → `BlinkingBlock` (default)
///   2     → `SteadyBlock`
///   3     → `BlinkingUnderline`
///   4     → `SteadyUnderline`
///   5     → `BlinkingBar`
///   6     → `SteadyBar`
///   _     → `BlinkingBlock` (fallback for unrecognised values)
#[inline]
pub fn handle_decscusr(term: &mut crate::TerminalCore, params: &vte::Params) {
    let ps = params
        .iter()
        .next()
        .and_then(|p| p.first().copied())
        .unwrap_or(0);
    term.dec_modes.cursor_shape =
        CursorShape::try_from(i64::from(ps)).unwrap_or(CursorShape::BlinkingBlock);
}

#[cfg(test)]
#[path = "tests/csi.rs"]
mod tests;
