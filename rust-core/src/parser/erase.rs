//! Erase operations (ED and EL sequences)
//!
//! All erase operations implement BCE (Background Color Erase) per the VT220
//! specification: erased cells receive the current SGR background color, not
//! the default background.

use crate::types::cell::CellWidth;
use crate::types::color::Color;
use crate::types::Cell;
use crate::grid::Line;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct Rect {
    top: usize,
    left: usize,
    bottom: usize,
    right: usize,
}

impl Rect {
    fn from_params(params: &vte::Params, rows: usize, cols: usize) -> Self {
        let mut iter = params.iter().filter_map(|p| p.first().copied());
        Self::from_iter(&mut iter, rows, cols)
    }

    fn from_iter(iter: &mut impl Iterator<Item = u16>, rows: usize, cols: usize) -> Self {
        let top = iter.next().unwrap_or(1).max(1) as usize - 1;
        let left = iter.next().unwrap_or(1).max(1) as usize - 1;
        let bottom = (iter.next().unwrap_or(rows as u16) as usize).min(rows);
        let right = (iter.next().unwrap_or(cols as u16) as usize).min(cols);
        Self {
            top,
            left,
            bottom,
            right,
        }
    }

    fn is_empty(self) -> bool {
        self.top >= self.bottom || self.left >= self.right
    }
}

fn erase_mode(params: &vte::Params) -> u16 {
    params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(0)
}

fn blank_cell_with_bg(bg: Color) -> Cell {
    let mut blank = Cell::default();
    blank.attrs.background = bg;
    blank
}

#[inline]
fn erase_line_range_with_bg(line: &mut Line, start: usize, end: usize, bg: Color) {
    if start >= end {
        return;
    }

    line.cells[start..end].fill(blank_cell_with_bg(bg));
    line.mark_dirty_and_bump();
}

#[inline]
fn clear_line_with_bg_and_mark_dirty(term: &mut crate::TerminalCore, row: usize, bg: Color) {
    if let Some(line) = term.screen.get_line_mut(row) {
        line.clear_with_bg(bg);
    }
    term.screen.mark_line_dirty(row);
}

#[inline]
fn erase_current_line_suffix(term: &mut crate::TerminalCore, row: usize, start: usize, bg: Color) {
    if let Some(line) = term.screen.get_line_mut(row) {
        let end = line.cells.len();
        erase_line_range_with_bg(line, start, end, bg);
    }
    term.screen.mark_line_dirty(row);
}

#[inline]
fn erase_current_line_prefix(term: &mut crate::TerminalCore, row: usize, end: usize, bg: Color) {
    if let Some(line) = term.screen.get_line_mut(row) {
        erase_line_range_with_bg(line, 0, end, bg);
    }
    term.screen.mark_line_dirty(row);
}

#[inline]
fn erase_current_line_suffix_if_present(
    term: &mut crate::TerminalCore,
    row: usize,
    col: usize,
    bg: Color,
) -> bool {
    let start = match term.screen.get_line(row) {
        Some(line) => erase_start_col(&line.cells, col),
        None => return false,
    };
    erase_current_line_suffix(term, row, start, bg);
    true
}

#[inline]
fn erase_current_line_prefix_if_present(
    term: &mut crate::TerminalCore,
    row: usize,
    col: usize,
    bg: Color,
) -> bool {
    let end = match term.screen.get_line(row) {
        Some(line) => erase_end_col(&line.cells, col),
        None => return false,
    };
    erase_current_line_prefix(term, row, end, bg);
    true
}

fn erase_start_col(cells: &[Cell], col: usize) -> usize {
    if col > 0 && col < cells.len() && cells[col].width == CellWidth::Wide {
        col - 1
    } else {
        col
    }
}

fn erase_end_col(cells: &[Cell], col: usize) -> usize {
    if col + 1 < cells.len() && cells[col].width == CellWidth::Full {
        col + 2
    } else {
        col + 1
    }
}

fn apply_rect_cells<F>(
    term: &mut crate::TerminalCore,
    rect: Rect,
    mut apply: F,
    bump_version: bool,
) where
    F: FnMut(&mut Cell),
{
    if rect.is_empty() {
        return;
    }

    let rows = term.screen.rows() as usize;
    let cols = term.screen.cols() as usize;
    let bottom = rect.bottom.min(rows);
    let right = rect.right.min(cols);
    if rect.top >= bottom || rect.left >= right {
        return;
    }

    for row in rect.top..bottom {
        if let Some(line) = term.screen.get_line_mut(row) {
            for col in rect.left..right.min(line.cells.len()) {
                apply(&mut line.cells[col]);
            }
            if bump_version {
                line.mark_dirty_and_bump();
            }
        }
        term.screen.mark_line_dirty(row);
    }
}

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
    let mode = erase_mode(params);

    let row = term.screen.cursor().row;
    let col = term.screen.cursor().col;
    // BCE: erased cells inherit the current SGR background color
    let bg = term.current_attrs.background;

    match mode {
        0 => {
            // Erase from cursor to end of screen
            // First, erase from cursor to end of current line
            if !erase_current_line_suffix_if_present(term, row, col, bg) {
                term.screen.mark_line_dirty(row);
            }

            // Then erase all lines below
            for r in (row + 1)..term.screen.rows() as usize {
                clear_line_with_bg_and_mark_dirty(term, r, bg);
            }
        }
        1 => {
            // Erase from start of screen to cursor (including cursor)
            // First, erase all lines above
            for r in 0..row {
                clear_line_with_bg_and_mark_dirty(term, r, bg);
            }

            // Then erase from start of cursor line to cursor
            if !erase_current_line_prefix_if_present(term, row, col, bg) {
                term.screen.mark_line_dirty(row);
            }
        }
        2 | 3 => {
            // Erase entire screen
            for r in 0..term.screen.rows() as usize {
                clear_line_with_bg_and_mark_dirty(term, r, bg);
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
    let mode = erase_mode(params);

    let col = term.screen.cursor().col;
    let row = term.screen.cursor().row;
    // BCE: erased cells inherit the current SGR background color
    let bg = term.current_attrs.background;

    match mode {
        0 => {
            // Erase from cursor to end of line
            // Wide pair safety: if start lands on a Wide placeholder, also erase its Full partner
            let erase_start = if let Some(line) = term.screen.get_line(row) {
                erase_start_col(&line.cells, col)
            } else {
                col
            };
            erase_current_line_suffix(term, row, erase_start, bg);
        }
        1 => {
            // Erase from start of line to cursor (including cursor)
            // Wide pair safety: if end lands on a Full cell, also erase its Wide partner
            let erase_end = if let Some(line) = term.screen.get_line(row) {
                erase_end_col(&line.cells, col)
            } else {
                col
            };
            erase_current_line_prefix(term, row, erase_end, bg);
        }
        2 => {
            // Erase entire line
            clear_line_with_bg_and_mark_dirty(term, row, bg);
        }
        _ => {}
    }
}

/// DECERA — Erase Rectangular Area (CSI Pt ; Pl ; Pb ; Pr $ z)
///
/// Fills the rectangle bounded by rows `Pt`–`Pb` and columns `Pl`–`Pr` (all
/// 1-indexed) with space characters using the current SGR background color.
/// Out-of-bounds coordinates are clamped to the screen dimensions.
pub fn handle_decera(term: &mut crate::TerminalCore, params: &vte::Params) {
    let rect = Rect::from_params(params, term.screen.rows() as usize, term.screen.cols() as usize);
    let bg = term.current_attrs.background;
    let blank = blank_cell_with_bg(bg);
    apply_rect_cells(term, rect, |cell| *cell = blank.clone(), false);
}

/// DECFRA — Fill Rectangular Area (CSI Pch ; Pt ; Pl ; Pb ; Pr $ x)
///
/// Fills the rectangle with character code `Pch` using the current SGR attributes.
/// `Pch` is the first parameter (character code 0-127); the remaining four are
/// top;left;bottom;right (1-indexed), clamped to screen dimensions.
pub fn handle_decfra(term: &mut crate::TerminalCore, params: &vte::Params) {
    let mut iter = params.iter();
    let ch_code = iter.next().and_then(|p| p.first()).copied().unwrap_or(0x20);
    let fill_char = char::from_u32(u32::from(ch_code)).unwrap_or(' ');

    let rect = Rect::from_iter(&mut iter.filter_map(|p| p.first().copied()), term.screen.rows() as usize, term.screen.cols() as usize);

    let attrs = term.current_attrs;
    let fill = Cell::with_attrs(fill_char, attrs);
    apply_rect_cells(term, rect, |cell| *cell = fill.clone(), false);
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
    let src = Rect::from_iter(&mut iter, rows, cols);
    let _src_page = iter.next(); // single-page terminal, page ignored
    let dst_top = iter.next().unwrap_or(1).max(1) as usize - 1;
    let dst_left = iter.next().unwrap_or(1).max(1) as usize - 1;

    let rect_rows = src.bottom.saturating_sub(src.top);
    let rect_cols = src.right.saturating_sub(src.left);
    if rect_rows == 0 || rect_cols == 0 {
        return;
    }

    // Read source into a temp buffer (handles overlapping src/dst)
    let mut buf: Vec<Vec<Cell>> = Vec::with_capacity(rect_rows);
    for r in src.top..src.bottom {
        let mut row_buf = Vec::with_capacity(rect_cols);
        for c in src.left..src.right {
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

    let rect = Rect {
        top: (groups
            .first()
            .and_then(|g| g.first())
            .copied()
            .unwrap_or(1)
            .max(1) as usize)
            - 1,
        left: (groups
            .get(1)
            .and_then(|g| g.first())
            .copied()
            .unwrap_or(1)
            .max(1) as usize)
            - 1,
        bottom: (groups
            .get(2)
            .and_then(|g| g.first())
            .copied()
            .unwrap_or(rows as u16) as usize)
            .min(rows),
        right: (groups
            .get(3)
            .and_then(|g| g.first())
            .copied()
            .unwrap_or(cols as u16) as usize)
            .min(cols),
    };

    if rect.is_empty() {
        return;
    }

    let sgr_groups = if groups.len() > 4 {
        &groups[4..]
    } else {
        &[][..]
    };
    let mut attrs = crate::types::cell::SgrAttributes::default();
    crate::parser::sgr::apply_sgr_attrs(&mut attrs, sgr_groups);

    for row in rect.top..rect.bottom {
        if let Some(line) = term.screen.get_line_mut(row) {
            for col in rect.left..rect.right.min(line.cells.len()) {
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
