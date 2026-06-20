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

fn blank_cell_with_background(background: crate::Color) -> crate::types::Cell {
    let mut blank = crate::types::Cell::default();
    blank.attrs.background = background;
    blank
}

fn shift_cells_right(
    line: &mut crate::grid::Line,
    cursor_col: usize,
    shift: usize,
    blank: &crate::types::Cell,
) {
    let len = line.cells.len();
    if cursor_col < len {
        let shift = shift.min(len - cursor_col);
        line.cells[cursor_col..].rotate_right(shift);
        let fill_end = cursor_col + shift;
        line.cells[cursor_col..fill_end].fill(blank.clone());
    }
}

fn shift_cells_left(
    line: &mut crate::grid::Line,
    cursor_col: usize,
    shift: usize,
    blank: &crate::types::Cell,
) {
    let len = line.cells.len();
    if cursor_col < len {
        let shift = shift.min(len - cursor_col);
        line.cells[cursor_col..].rotate_left(shift);
        let fill_start = len - shift;
        line.cells[fill_start..].fill(blank.clone());
    }
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

fn for_each_scroll_region_line_mut<F>(term: &mut crate::TerminalCore, mut f: F)
where
    F: FnMut(usize, &mut crate::grid::Line),
{
    let region = term.screen.get_scroll_region();
    for row in region.top..region.bottom {
        if let Some(line) = term.screen.get_line_mut(row) {
            f(row, line);
        }
        term.screen.mark_line_dirty(row);
    }
}

/// DECIC — Insert Columns (VT500 private mode)
///
/// Inserts blank cells from the cursor position across the scroll region and
/// shifts existing cells to the right.
pub fn handle_decic(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = get_param(params);
    let cursor_col = term.screen.cursor().col;
    let cols = term.screen.cols() as usize;
    let shift = n.min(cols.saturating_sub(cursor_col));
    if shift == 0 {
        return;
    }
    let blank = blank_cell_with_background(term.current_attrs.background);
    for_each_scroll_region_line_mut(term, |_, line| {
        shift_cells_right(line, cursor_col, shift, &blank);
    });
}

/// DECDC — Delete Columns (VT500 private mode)
///
/// Deletes cells from the cursor position across the scroll region and shifts
/// the remaining cells to the left.
pub fn handle_decdc(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = get_param(params);
    let cursor_col = term.screen.cursor().col;
    let blank = blank_cell_with_background(term.current_attrs.background);
    for_each_scroll_region_line_mut(term, |_, line| {
        shift_cells_left(line, cursor_col, n, &blank);
    });
}

#[cfg(test)]
#[path = "tests/insert_delete.rs"]
mod tests;
