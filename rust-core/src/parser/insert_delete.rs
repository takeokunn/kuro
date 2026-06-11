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

/// DECIC — Insert Column(s) (CSI Ps ' })
///
/// Inserts `Ps` blank columns at the cursor column in every row within the
/// current scroll region. Existing content shifts right; columns that shift
/// past the right margin are discarded.
pub fn handle_decic(term: &mut crate::TerminalCore, params: &vte::Params) {
    use crate::types::Cell;
    let n = get_param(params);
    let cursor_col = term.screen.cursor().col;
    let cols = term.screen.cols() as usize;
    let bg = term.current_attrs.background;
    let region = term.screen.get_scroll_region();
    let shift = n.min(cols.saturating_sub(cursor_col));
    if shift == 0 {
        return;
    }
    let mut blank = Cell::default();
    blank.attrs.background = bg;
    for row in region.top..region.bottom {
        if let Some(line) = term.screen.get_line_mut(row) {
            let len = line.cells.len();
            if cursor_col < len {
                line.cells[cursor_col..].rotate_right(shift.min(len - cursor_col));
                let fill_end = (cursor_col + shift).min(len);
                line.cells[cursor_col..fill_end].fill(blank.clone());
            }
        }
        term.screen.mark_line_dirty(row);
    }
}

/// DECDC — Delete Column(s) (CSI Ps ' ~)
///
/// Deletes `Ps` columns starting at the cursor column in every row within the
/// current scroll region. Content to the right of the deleted columns shifts
/// left; blank columns fill the right end of each row.
pub fn handle_decdc(term: &mut crate::TerminalCore, params: &vte::Params) {
    use crate::types::Cell;
    let n = get_param(params);
    let cursor_col = term.screen.cursor().col;
    let bg = term.current_attrs.background;
    let region = term.screen.get_scroll_region();
    let mut blank = Cell::default();
    blank.attrs.background = bg;
    for row in region.top..region.bottom {
        if let Some(line) = term.screen.get_line_mut(row) {
            let len = line.cells.len();
            if cursor_col < len {
                let shift = n.min(len - cursor_col);
                line.cells[cursor_col..].rotate_left(shift);
                let fill_start = len - shift;
                line.cells[fill_start..].fill(blank.clone());
            }
        }
        term.screen.mark_line_dirty(row);
    }
}

#[cfg(test)]
#[path = "tests/insert_delete.rs"]
mod tests;
