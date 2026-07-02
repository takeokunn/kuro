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
    let _ = handle_csi_cursor_relative_dispatch(term, params, c)
        || handle_csi_cursor_absolute_dispatch(term, params, c)
        || handle_csi_cursor_report_dispatch(term, params, c);
}

#[inline]
fn handle_csi_cursor_relative_dispatch(
    term: &mut crate::TerminalCore,
    params: &vte::Params,
    c: char,
) -> bool {
    match c {
        'A' => csi_cuu(term, params), // CUU - Cursor Up
        'B' => csi_cud(term, params), // CUD - Cursor Down
        'C' => csi_cuf(term, params), // CUF - Cursor Forward
        'D' => csi_cub(term, params), // CUB - Cursor Back
        'a' => csi_cuf(term, params), // HPR - Horizontal Position Relative (≡ CUF)
        'e' => csi_cud(term, params), // VPR - Vertical Position Relative (≡ CUD)
        _ => return false,
    }

    true
}

#[inline]
fn handle_csi_cursor_absolute_dispatch(
    term: &mut crate::TerminalCore,
    params: &vte::Params,
    c: char,
) -> bool {
    match c {
        'H' => csi_cup(term, params),       // CUP - Cursor Position
        'E' => csi_cnl(term, params),       // CNL - Cursor Next Line
        'F' => csi_cpl(term, params),       // CPL - Cursor Previous Line
        'd' => csi_vpa(term, params),       // VPA - Vertical Position Absolute
        'G' | '`' => csi_cha(term, params), // CHA / HPA — both move to absolute column
        'f' => csi_hvp(term, params),       // HVP - Horizontal and Vertical Position
        _ => return false,
    }

    true
}

#[inline]
fn handle_csi_cursor_report_dispatch(
    term: &mut crate::TerminalCore,
    params: &vte::Params,
    c: char,
) -> bool {
    match c {
        'n' => csi_dsr(term, params), // DSR - Device Status Report
        _ => return false,
    }

    true
}

/// Extract the first CSI parameter as `i32`, defaulting to 1 if absent or zero.
macro_rules! csi_param1 {
    ($params:expr) => {
        i32::from(
            $params
                .iter()
                .next()
                .and_then(|p| p.iter().next())
                .copied()
                .unwrap_or(1)
                .max(1),
        )
    };
}

fn xtwinops_param1(params: &vte::Params) -> u16 {
    params
        .iter()
        .next()
        .and_then(|p| p.first().copied())
        .unwrap_or(0)
}

pub(crate) fn build_xtwinops_size_report(op: u16, rows: usize, cols: usize) -> Option<Vec<u8>> {
    match op {
        14 => Some(b"\x1b[4;0;0t".to_vec()),
        // XTWINOPS 16 — report cell size in pixels: `CSI 6 ; height ; width t`.
        // Emacs-hosted core owns no pixels, so report the documented default cell
        // size (height;width = 16;8 points) to satisfy size-probing applications.
        16 => Some(b"\x1b[6;16;8t".to_vec()),
        18 => Some(format!("\x1b[8;{rows};{cols}t").into_bytes()),
        19 => Some(format!("\x1b[9;{rows};{cols}t").into_bytes()),
        _ => None,
    }
}

fn apply_xtwinops_title_stack(term: &mut crate::TerminalCore, op: u16) {
    match op {
        // XTPUSHTITLE — save current title; second param selects what to save:
        //   0 = icon+window title, 1 = icon, 2 = window title. We treat all as window title.
        22 => term.meta.title_stack.push(term.meta.title.clone()),
        // XTPOPTITLE — restore title from stack; same sub-param semantics as above.
        23 => {
            if let Some(saved) = term.meta.title_stack.pop() {
                term.meta.set_title(saved);
            }
        }
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
    let n = csi_param1!(params);
    term.screen.move_cursor_by(-n, 0);
}

/// CUD - Cursor Down (CSI B)
///
/// Move cursor down by N rows (default 1). Stops at bottom of screen.
#[inline]
fn csi_cud(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = csi_param1!(params);
    term.screen.move_cursor_by(n, 0);
}

/// CUF - Cursor Forward (CSI C)
///
/// Move cursor right by N columns (default 1). Stops at right margin.
#[inline]
fn csi_cuf(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = csi_param1!(params);
    term.screen.move_cursor_by(0, n);
}

/// CUB - Cursor Back (CSI D)
///
/// Move cursor left by N columns (default 1). Stops at left margin.
#[inline]
fn csi_cub(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = csi_param1!(params);
    term.screen.move_cursor_by(0, -n);
}

/// CNL - Cursor Next Line (CSI E)
///
/// Move cursor down by N rows (default 1) and to column 0.
/// Does not cause scrolling (unlike LF, which scrolls at the scroll region's bottom margin).
/// Stops at the bottom of the screen (screen boundary, not scroll region).
#[inline]
fn csi_cnl(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = csi_param1!(params);
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
    let n = csi_param1!(params);
    term.screen.move_cursor_by(-n, 0);
    let row = term.screen.cursor().row;
    term.screen.move_cursor(row, 0);
}

/// DSR - Device Status Report (CSI n)
///
/// Param 5: operating-status query — respond `CSI 0 n` ("ready, no
///          malfunction"). Programs use this to probe terminal liveness.
/// Param 6: respond with current cursor position as `ESC[row;colR`
///          (1-indexed); this is CPR (Cursor Position Report).
///
/// Any other parameter is a silent no-op.
#[inline]
fn csi_dsr(term: &mut crate::TerminalCore, params: &vte::Params) {
    let code = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(0);

    match code {
        5 => {
            // Operating status: terminal is ready / no malfunction.
            term.meta.pending_responses.push(b"\x1b[0n".to_vec());
        }
        6 => {
            let row = term.screen.cursor().row + 1; // Convert to 1-indexed
            let col = term.screen.cursor().col + 1;
            let response = format!("\x1b[{row};{col}R");
            term.meta.pending_responses.push(response.into_bytes());
        }
        _ => {}
    }
}

fn csi_param_zero_based(params: &vte::Params, index: usize) -> usize {
    params
        .iter()
        .nth(index)
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .saturating_sub(1) as usize
}

fn csi_origin_row(term: &crate::TerminalCore, row: usize) -> usize {
    if term.dec_modes.origin_mode {
        let scroll_region = term.screen.get_scroll_region();
        (scroll_region.top + row).min(scroll_region.bottom.saturating_sub(1))
    } else {
        row
    }
}

fn csi_vpa(term: &mut crate::TerminalCore, params: &vte::Params) {
    let row = csi_param_zero_based(params, 0);
    let target_row = csi_origin_row(term, row);

    // Move cursor to absolute row, keep current column
    term.screen
        .move_cursor(target_row, term.screen.cursor().col);
}

fn csi_cha(term: &mut crate::TerminalCore, params: &vte::Params) {
    let col = csi_param_zero_based(params, 0);

    // Move cursor to absolute column, keep current row
    term.screen.move_cursor(term.screen.cursor().row, col);
}

fn csi_hvp(term: &mut crate::TerminalCore, params: &vte::Params) {
    let row = csi_param_zero_based(params, 0);
    let col = csi_param_zero_based(params, 1);
    let target_row = csi_origin_row(term, row);

    // Move cursor to absolute position
    term.screen.move_cursor(target_row, col);
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

/// Handle XTWINOPS window manipulation (`CSI Ps ; ... t`).
///
/// Only the *size-report* queries are answered.  Window-manipulation ops
/// Window manipulation operations other than size queries and title stack
/// (resize/move/iconify/raise/lower; `Ps` 1–10) and host-revealing reports
/// (window position `Ps` 13, icon/window title `Ps` 20/21) are deliberately
/// ignored as a security measure: a terminal embedded in Emacs must never let
/// applications move, resize, or interrogate the host window
/// (cf. xterm's `allowWindowOps`, disabled by default in many emulators).
///
/// Answered queries (`height` = rows, `width` = cols; pixels are unknown for a
/// cell-based core and so reported as 0):
/// - `Ps` 14 → `CSI 4 ; 0 ; 0 t`        (text-area size in pixels)
/// - `Ps` 18 → `CSI 8 ; rows ; cols t`  (text-area size in characters)
/// - `Ps` 19 → `CSI 9 ; rows ; cols t`  (screen size in characters)
///
/// Title stack operations (safe — no host window interrogation):
/// - `Ps` 22 → XTPUSHTITLE: push current window title onto internal stack
/// - `Ps` 23 → XTPOPTITLE: pop window title from stack and apply it
#[inline]
pub fn handle_xtwinops(term: &mut crate::TerminalCore, params: &vte::Params) {
    let op = xtwinops_param1(params);
    let rows = term.screen.rows();
    let cols = term.screen.cols();
    if let Some(response) = build_xtwinops_size_report(op, rows.into(), cols.into()) {
        term.meta.pending_responses.push(response);
        return;
    }
    apply_xtwinops_title_stack(term, op);
}

/// DECREQTPARM — Request Terminal Parameters (CSI Ps x).
///
/// Per the VT100 spec, only `Ps = 0` or `Ps = 1` produce a report (DECREPTPARM):
/// `CSI <sol> ; 1 ; 1 ; 128 ; 128 ; 1 ; 0 x` where `sol` is 2 (for request 0) or
/// 3 (for request 1). Fields are: parity=none, nbits=8, xspeed/rspeed=38400,
/// clock-multiplier=1, flags=0 — the standard "no special settings" report that
/// xterm emits. Any other `Ps` value is ignored (VT100 behavior).
#[inline]
pub fn handle_decreqtparm(term: &mut crate::TerminalCore, params: &vte::Params) {
    let req = params
        .iter()
        .next()
        .and_then(|p| p.first().copied())
        .unwrap_or(0);
    let sol = match req {
        0 => 2,
        1 => 3,
        _ => return, // other values produce no report
    };
    let response = format!("\x1b[{sol};1;1;128;128;1;0x");
    term.meta.pending_responses.push(response.into_bytes());
}

#[cfg(test)]
#[path = "tests/csi.rs"]
mod tests;
