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
        'T' => csi_sd(term, params),      // SD - Scroll Down
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
/// existing ScrollRegion convention in Screen).
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

        // Move cursor to home position after setting scroll region (DECSTD behavior)
        term.screen.move_cursor(top, 0);
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

#[cfg(test)]
#[path = "tests/scroll.rs"]
mod tests;
