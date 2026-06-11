//! Erase operations (ED and EL sequences)
//!
//! All erase operations implement BCE (Background Color Erase) per the VT220
//! specification: erased cells receive the current SGR background color, not
//! the default background.

use crate::types::cell::CellWidth;
use crate::types::Cell;

/// Handle erase sequences (ED and EL, optionally selective with `?` intermediate)
///
/// This module implements:
/// - ED (CSI J): Erase in Display
/// - EL (CSI K): Erase in Line
/// - DECSED (CSI ? J): Selective Erase Display (treated as ED — no protection tracking)
/// - DECSEL (CSI ? K): Selective Erase Line (treated as EL — no protection tracking)
pub fn handle_erase(term: &mut crate::TerminalCore, params: &vte::Params, c: char) {
    match c {
        'J' => csi_ed(term, params), // ED / DECSED
        'K' => csi_el(term, params), // EL / DECSEL
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
    // BCE: erased cells inherit the current SGR background color
    let bg = term.current_attrs.background;

    match mode {
        0 => {
            // Erase from cursor to end of screen
            // First, erase from cursor to end of current line
            if let Some(line) = term.screen.get_line_mut(row) {
                // Wide pair safety: if start lands on a Wide placeholder, also erase its Full partner
                let erase_start = if col > 0
                    && col < line.cells.len()
                    && line.cells[col].width == CellWidth::Wide
                {
                    col - 1
                } else {
                    col
                };
                let mut blank = Cell::default();
                blank.attrs.background = bg;
                line.cells[erase_start..].fill(blank);
                line.version = line.version.wrapping_add(1);
            }
            term.screen.mark_line_dirty(row);

            // Then erase all lines below
            for r in (row + 1)..term.screen.rows() as usize {
                if let Some(line) = term.screen.get_line_mut(r) {
                    line.clear_with_bg(bg);
                }
                term.screen.mark_line_dirty(r);
            }
        }
        1 => {
            // Erase from start of screen to cursor (including cursor)
            // First, erase all lines above
            for r in 0..row {
                if let Some(line) = term.screen.get_line_mut(r) {
                    line.clear_with_bg(bg);
                }
                term.screen.mark_line_dirty(r);
            }

            // Then erase from start of cursor line to cursor
            if let Some(line) = term.screen.get_line_mut(row) {
                // Wide pair safety: if end lands on a Full cell, also erase its Wide partner
                let erase_end =
                    if col + 1 < line.cells.len() && line.cells[col].width == CellWidth::Full {
                        col + 2
                    } else {
                        col + 1
                    };
                let mut blank = Cell::default();
                blank.attrs.background = bg;
                line.cells[..erase_end].fill(blank);
                line.version = line.version.wrapping_add(1);
            }
            term.screen.mark_line_dirty(row);
        }
        2 | 3 => {
            // Erase entire screen
            for r in 0..term.screen.rows() as usize {
                if let Some(line) = term.screen.get_line_mut(r) {
                    line.clear_with_bg(bg);
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
    // BCE: erased cells inherit the current SGR background color
    let bg = term.current_attrs.background;

    if let Some(line) = term.screen.get_line_mut(row) {
        match mode {
            0 => {
                // Erase from cursor to end of line
                // Wide pair safety: if start lands on a Wide placeholder, also erase its Full partner
                let erase_start = if col > 0
                    && col < line.cells.len()
                    && line.cells[col].width == CellWidth::Wide
                {
                    col - 1
                } else {
                    col
                };
                let mut blank = Cell::default();
                blank.attrs.background = bg;
                line.cells[erase_start..].fill(blank);
                line.version = line.version.wrapping_add(1);
            }
            1 => {
                // Erase from start of line to cursor (including cursor)
                // Wide pair safety: if end lands on a Full cell, also erase its Wide partner
                let erase_end =
                    if col + 1 < line.cells.len() && line.cells[col].width == CellWidth::Full {
                        col + 2
                    } else {
                        col + 1
                    };
                let mut blank = Cell::default();
                blank.attrs.background = bg;
                line.cells[..erase_end].fill(blank);
                line.version = line.version.wrapping_add(1);
            }
            2 => {
                // Erase entire line
                line.clear_with_bg(bg);
            }
            _ => {}
        }
    }
    term.screen.mark_line_dirty(row);
}

/// DECERA — Erase Rectangular Area (CSI Pt ; Pl ; Pb ; Pr $ z)
///
/// Fills the rectangle bounded by rows `Pt`–`Pb` and columns `Pl`–`Pr` (all
/// 1-indexed) with space characters using the current SGR background color.
/// Out-of-bounds coordinates are clamped to the screen dimensions.
pub fn handle_decera(term: &mut crate::TerminalCore, params: &vte::Params) {
    let [top, left, bottom, right] = extract_rect_params(params, term);
    let bg = term.current_attrs.background;
    let mut blank = Cell::default();
    blank.attrs.background = bg;
    for row in top..bottom {
        if let Some(line) = term.screen.get_line_mut(row) {
            for col in left..right.min(line.cells.len()) {
                line.cells[col] = blank.clone();
            }
        }
        term.screen.mark_line_dirty(row);
    }
}

/// DECFRA — Fill Rectangular Area (CSI Pch ; Pt ; Pl ; Pb ; Pr $ x)
///
/// Fills the rectangle with character code `Pch` using the current SGR attributes.
/// `Pch` is the first parameter (character code 0-127); the remaining four are
/// top;left;bottom;right (1-indexed), clamped to screen dimensions.
pub fn handle_decfra(term: &mut crate::TerminalCore, params: &vte::Params) {
    let mut iter = params.iter();
    let ch_code = iter
        .next()
        .and_then(|p| p.first())
        .copied()
        .unwrap_or(0x20);
    let fill_char = char::from_u32(u32::from(ch_code)).unwrap_or(' ');

    // Rebuild a 4-element params view for the rectangle coordinates.
    // Re-parse the last 4 params manually since we already consumed the first.
    let rest: Vec<u16> = iter
        .filter_map(|p| p.first().copied())
        .collect();
    let rows = term.screen.rows() as usize;
    let cols = term.screen.cols() as usize;
    let top    = rest.first().copied().unwrap_or(1).max(1) as usize - 1;
    let left   = rest.get(1).copied().unwrap_or(1).max(1) as usize - 1;
    let bottom = (rest.get(2).copied().unwrap_or(rows as u16) as usize).min(rows);
    let right  = (rest.get(3).copied().unwrap_or(cols as u16) as usize).min(cols);

    let attrs = term.current_attrs;
    let fill = Cell::with_attrs(fill_char, attrs);
    for row in top..bottom {
        if let Some(line) = term.screen.get_line_mut(row) {
            for col in left..right.min(line.cells.len()) {
                line.cells[col] = fill.clone();
            }
        }
        term.screen.mark_line_dirty(row);
    }
}

/// Extract the rectangle parameters (top, left, bottom, right) from params.
/// All values are 1-indexed in the wire format; returned as 0-indexed row/col ranges
/// clamped to current screen dimensions. Returns `[top, left, bottom, right]` where
/// `top..bottom` and `left..right` form exclusive ranges suitable for iteration.
#[inline]
fn extract_rect_params(params: &vte::Params, term: &crate::TerminalCore) -> [usize; 4] {
    let rows = term.screen.rows() as usize;
    let cols = term.screen.cols() as usize;
    let mut iter = params.iter().filter_map(|p| p.first().copied());
    let top    = iter.next().unwrap_or(1).max(1) as usize - 1;
    let left   = iter.next().unwrap_or(1).max(1) as usize - 1;
    let bottom = (iter.next().unwrap_or(rows as u16) as usize).min(rows);
    let right  = (iter.next().unwrap_or(cols as u16) as usize).min(cols);
    [top, left, bottom, right]
}

/// DECCRA — Copy Rectangular Area (CSI Pt;Pl;Pb;Pr;Pp;Pt2;Pl2;Pp2 $ v)
///
/// Copies the source rectangle (Pt, Pl, Pb, Pr; 1-indexed, page Pp ignored)
/// to the destination starting at (Pt2, Pl2; 1-indexed, page Pp2 ignored).
/// A temporary buffer handles overlapping source and destination rectangles.
pub fn handle_deccra(term: &mut crate::TerminalCore, params: &vte::Params) {
    let rows = term.screen.rows() as usize;
    let cols = term.screen.cols() as usize;
    let mut iter = params.iter().filter_map(|p| p.first().copied());
    let src_top    = iter.next().unwrap_or(1).max(1) as usize - 1;
    let src_left   = iter.next().unwrap_or(1).max(1) as usize - 1;
    let src_bottom = (iter.next().unwrap_or(rows as u16) as usize).min(rows);
    let src_right  = (iter.next().unwrap_or(cols as u16) as usize).min(cols);
    let _src_page  = iter.next(); // single-page terminal, page ignored
    let dst_top    = iter.next().unwrap_or(1).max(1) as usize - 1;
    let dst_left   = iter.next().unwrap_or(1).max(1) as usize - 1;

    let rect_rows = src_bottom.saturating_sub(src_top);
    let rect_cols = src_right.saturating_sub(src_left);
    if rect_rows == 0 || rect_cols == 0 {
        return;
    }

    // Read source into a temp buffer (handles overlapping src/dst)
    let mut buf: Vec<Vec<Cell>> = Vec::with_capacity(rect_rows);
    for r in src_top..src_bottom {
        let mut row_buf = Vec::with_capacity(rect_cols);
        for c in src_left..src_right {
            row_buf.push(term.screen.get_cell(r, c).cloned().unwrap_or_default());
        }
        buf.push(row_buf);
    }

    // Write to destination
    for (ri, row_buf) in buf.iter().enumerate() {
        let dst_row = dst_top + ri;
        if dst_row >= rows {
            break;
        }
        for (ci, cell) in row_buf.iter().enumerate() {
            let dst_col = dst_left + ci;
            if dst_col >= cols {
                break;
            }
            if let Some(dst_cell) = term.screen.get_cell_mut(dst_row, dst_col) {
                *dst_cell = cell.clone();
            }
        }
        term.screen.mark_line_dirty(dst_row);
    }
}

/// DECCARA — Change Attributes in Rectangular Area (CSI Pt;Pl;Pb;Pr;Ps... $ r)
///
/// Applies the SGR attributes specified by `Ps...` (the parameter groups after
/// the four rectangle coordinates) to every cell in the rectangle.  The SGR
/// processing begins from a default (reset) attribute state, as specified by
/// the DEC standard — only the attributes explicitly named in `Ps...` are set
/// on each cell; unspecified attributes are reset to their defaults.
///
/// Coordinates are 1-indexed on the wire and clamped to screen dimensions.
pub fn handle_deccara(term: &mut crate::TerminalCore, params: &vte::Params) {
    const MAX_GROUPS: usize = 32;
    let rows = term.screen.rows() as usize;
    let cols = term.screen.cols() as usize;

    let mut group_buf: [&[u16]; MAX_GROUPS] = [&[]; MAX_GROUPS];
    let mut n = 0;
    for g in params {
        if n < MAX_GROUPS {
            group_buf[n] = g;
            n += 1;
        }
    }
    let groups = &group_buf[..n];

    let top    = (groups.first().and_then(|g| g.first()).copied().unwrap_or(1).max(1) as usize) - 1;
    let left   = (groups.get(1).and_then(|g| g.first()).copied().unwrap_or(1).max(1) as usize) - 1;
    let bottom = (groups.get(2).and_then(|g| g.first()).copied().unwrap_or(rows as u16) as usize).min(rows);
    let right  = (groups.get(3).and_then(|g| g.first()).copied().unwrap_or(cols as u16) as usize).min(cols);

    if top >= bottom || left >= right {
        return;
    }

    let sgr_groups = if groups.len() > 4 { &groups[4..] } else { &[][..] };
    let mut attrs = crate::types::cell::SgrAttributes::default();
    crate::parser::sgr::apply_sgr_attrs(&mut attrs, sgr_groups);

    for row in top..bottom {
        if let Some(line) = term.screen.get_line_mut(row) {
            for col in left..right.min(line.cells.len()) {
                line.cells[col].attrs = attrs;
            }
            line.mark_dirty_and_bump();
        }
        term.screen.mark_line_dirty(row);
    }
}

#[cfg(test)]
#[path = "tests/erase.rs"]
mod tests;
