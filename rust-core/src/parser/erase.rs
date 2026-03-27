//! Erase operations (ED and EL sequences)
//!
//! All erase operations implement BCE (Background Color Erase) per the VT220
//! specification: erased cells receive the current SGR background color, not
//! the default background.

use crate::types::cell::CellWidth;
use crate::types::Cell;

/// Handle erase sequences
///
/// This module implements:
/// - ED (CSI J): Erase in Display
/// - EL (CSI K): Erase in Line
pub fn handle_erase(term: &mut crate::TerminalCore, params: &vte::Params, c: char) {
    match c {
        'J' => csi_ed(term, params), // ED - Erase Display
        'K' => csi_el(term, params), // EL - Erase Line
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

#[cfg(test)]
#[path = "tests/erase.rs"]
mod tests;
