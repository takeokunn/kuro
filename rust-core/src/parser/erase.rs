//! Erase operations (ED and EL sequences)
//!
//! All erase operations implement BCE (Background Color Erase) per the VT220
//! specification: erased cells receive the current SGR background color, not
//! the default background.

#[path = "erase_support.rs"]
mod support;

use crate::grid::Line;
use crate::types::cell::CellWidth;
use crate::types::color::Color;
use crate::types::Cell;

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
            for r in (row + 1)..usize::from(term.screen.rows()) {
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
            for r in 0..usize::from(term.screen.rows()) {
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
    support::handle_decera(term, params);
}

/// DECFRA — Fill Rectangular Area (CSI Pch ; Pt ; Pl ; Pb ; Pr $ x)
///
/// Fills the rectangle with character code `Pch` using the current SGR attributes.
/// `Pch` is the first parameter (character code 0-127); the remaining four are
/// top;left;bottom;right (1-indexed), clamped to screen dimensions.
pub fn handle_decfra(term: &mut crate::TerminalCore, params: &vte::Params) {
    support::handle_decfra(term, params);
}

/// DECCRA — Copy Rectangular Area (CSI Pt;Pl;Pb;Pr;Pp;Pt2;Pl2;Pp2 $ v)
///
/// Copies the source rectangle (Pt, Pl, Pb, Pr; 1-indexed, page Pp ignored)
/// to the destination starting at (Pt2, Pl2; 1-indexed, page Pp2 ignored).
/// A temporary buffer handles overlapping source and destination rectangles.
pub fn handle_deccra(term: &mut crate::TerminalCore, params: &vte::Params) {
    support::handle_deccra(term, params);
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
    support::handle_deccara(term, params);
}

#[cfg(test)]
#[path = "tests/erase.rs"]
mod tests;
