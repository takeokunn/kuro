//! Scroll region management and scrolling operations

/// RI — Reverse Index (ESC M)
///
/// Moves the cursor up one line. If the cursor is at the top of the scroll
/// region, scrolls the region down by one line instead.
#[inline]
pub fn handle_ri(term: &mut crate::TerminalCore) {
    let cursor_row = term.screen.cursor().row;
    let scroll_top = term.screen.get_scroll_region().top;
    if cursor_row == scroll_top {
        term.screen.scroll_down(1, term.current_attrs.background);
    } else if cursor_row > 0 {
        term.screen
            .move_cursor(cursor_row - 1, term.screen.cursor().col);
    }
}

/// Handle scroll sequences
///
/// This module implements:
/// - DECSTBM (CSI r): Set Top and Bottom Margins
/// - SU (CSI S): Scroll Up
/// - SD (CSI T): Scroll Down
pub fn handle_scroll(term: &mut crate::TerminalCore, params: &vte::Params, c: char) {
    match c {
        'r' => csi_decstbm(term, params), // DECSTBM
        'S' => csi_su(term, params),      // SU - Scroll Up
        'T' | '^' => csi_sd(term, params), // SD - Scroll Down (^ = MINTTY alternate)
        _ => {}
    }
}

/// DECSTBM - Set Top and Bottom Margins (CSI r Ps; Pt)
///
/// Set scrolling region. Both parameters are 1-indexed.
///
/// Parameters:
/// - Ps: Top margin (default: 1, which becomes 0 internally)
/// - Pt: Bottom margin (default: bottom of screen, which becomes rows internally)
///
/// Note: The top margin is inclusive, bottom margin is exclusive (following the
/// existing `ScrollRegion` convention in Screen).
#[expect(
    clippy::cast_possible_truncation,
    reason = "rows = screen.rows() which is u16; usize→u16 round-trip is lossless"
)]
fn csi_decstbm(term: &mut crate::TerminalCore, params: &vte::Params) {
    let rows = term.screen.rows() as usize;

    // Get top parameter (1-indexed, convert to 0-indexed)
    // Default is 0 (top of screen)
    let top = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .saturating_sub(1) as usize;

    // Get bottom parameter (1-indexed, convert to 0-indexed)
    // Default is rows (end of screen)
    let bottom = params
        .iter()
        .nth(1)
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(rows as u16)
        .min(rows as u16) as usize;

    // Validate: top must be < bottom
    if top < bottom {
        term.screen.set_scroll_region(top, bottom);

        // Move cursor to home position after setting scroll region.
        // Per DEC VT510: DECOM off → absolute (0,0); DECOM on → scroll region top.
        if term.dec_modes.origin_mode {
            term.screen.move_cursor(top, 0);
        } else {
            term.screen.move_cursor(0, 0);
        }
    }
    // If invalid, ignore the sequence (DEC behavior)
}

fn csi_su(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1);

    // Ensure minimum scroll of 1 line
    let n = n.max(1);

    // Scroll up (content moves down), applying BCE background to new blank lines
    term.screen
        .scroll_up(n as usize, term.current_attrs.background);
}

fn csi_sd(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1);

    // Ensure minimum scroll of 1 line
    let n = n.max(1);

    // Scroll down (content moves up), applying BCE background to new blank lines
    term.screen
        .scroll_down(n as usize, term.current_attrs.background);
}

/// SL — Scroll Left (CSI Ps SP @)
///
/// Shifts each row in the scroll region left by `Ps` columns. Columns shifted
/// off the left edge are discarded; `Ps` blank columns appear at the right.
pub fn handle_sl(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .max(1) as usize;

    let bg = term.current_attrs.background;
    let region = term.screen.get_scroll_region();
    let cols = term.screen.cols() as usize;
    let shift = n.min(cols);
    let mut blank = crate::types::Cell::default();
    blank.attrs.background = bg;

    for row in region.top..region.bottom {
        if let Some(line) = term.screen.get_line_mut(row) {
            let len = line.cells.len();
            if shift < len {
                line.cells.rotate_left(shift);
                line.cells[len - shift..].fill(blank.clone());
            } else {
                line.cells.fill(blank.clone());
            }
        }
        term.screen.mark_line_dirty(row);
    }
}

/// SR — Scroll Right (CSI Ps SP A)
///
/// Shifts each row in the scroll region right by `Ps` columns. Columns shifted
/// off the right edge are discarded; `Ps` blank columns appear at the left.
pub fn handle_sr(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .max(1) as usize;

    let bg = term.current_attrs.background;
    let region = term.screen.get_scroll_region();
    let cols = term.screen.cols() as usize;
    let shift = n.min(cols);
    let mut blank = crate::types::Cell::default();
    blank.attrs.background = bg;

    for row in region.top..region.bottom {
        if let Some(line) = term.screen.get_line_mut(row) {
            let len = line.cells.len();
            if shift < len {
                line.cells.rotate_right(shift);
                line.cells[..shift].fill(blank.clone());
            } else {
                line.cells.fill(blank.clone());
            }
        }
        term.screen.mark_line_dirty(row);
    }
}

#[cfg(test)]
#[path = "tests/scroll.rs"]
mod tests;
