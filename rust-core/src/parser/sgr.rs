//! SGR (Select Graphic Rendition) parameter parsing

use crate::types::{Color, NamedColor};

/// Handle CSI (Control Sequence Introducer) sequences
pub fn handle_csi(
    term: &mut crate::TerminalCore,
    params: &vte::Params,
    intermediates: &[u8],
    c: char,
) {
    match c {
        // Cursor movement
        'A' => csi_cuu(term, params),       // Cursor Up
        'B' => csi_cud(term, params),       // Cursor Down
        'C' => csi_cuf(term, params),       // Cursor Forward
        'D' => csi_cub(term, params),       // Cursor Back
        'H' | 'f' => csi_cup(term, params), // Cursor Position
        'J' => csi_ed(term, params),        // Erase Display
        'K' => csi_el(term, params),        // Erase Line
        'm' => csi_sgr(term, params),       // Select Graphic Rendition
        'r' => csi_decstbm(term, params),   // Set Scroll Region
        _ => {}
    }

    let _ = intermediates;
}

/// CUU - Cursor Up
fn csi_cuu(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1);
    term.screen.move_cursor_by(-((n as i32).max(1)), 0);
}

/// CUD - Cursor Down
fn csi_cud(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1);
    term.screen.move_cursor_by((n as i32).max(1), 0);
}

/// CUF - Cursor Forward
fn csi_cuf(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1);
    term.screen.move_cursor_by(0, (n as i32).max(1));
}

/// CUB - Cursor Backward
fn csi_cub(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1);
    term.screen.move_cursor_by(0, -((n as i32).max(1)));
}

/// CUP - Cursor Position
fn csi_cup(term: &mut crate::TerminalCore, params: &vte::Params) {
    let row = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .saturating_sub(1);
    let col = params
        .iter()
        .nth(1)
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .saturating_sub(1);
    term.screen.move_cursor(row as usize, col as usize);
}

/// ED - Erase Display
fn csi_ed(term: &mut crate::TerminalCore, params: &vte::Params) {
    let mode = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(0);

    match mode {
        0 => {
            // Erase from cursor to end of screen
            let row = term.screen.cursor.row;
            for r in row..term.screen.rows() as usize {
                if let Some(line) = term.screen.get_line_mut(r) {
                    line.clear();
                }
            }
        }
        1 => {
            // Erase from start of screen to cursor
            let row = term.screen.cursor.row;
            for r in 0..=row {
                if let Some(line) = term.screen.get_line_mut(r) {
                    line.clear();
                }
            }
        }
        2 | 3 => {
            // Erase entire screen
            term.screen.clear_lines(0, term.screen.rows() as usize);
        }
        _ => {}
    }
}

/// EL - Erase Line
fn csi_el(term: &mut crate::TerminalCore, params: &vte::Params) {
    let mode = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(0);
    let col = term.screen.cursor.col;
    let row = term.screen.cursor.row;

    if let Some(line) = term.screen.get_line_mut(row) {
        match mode {
            0 => {
                // Erase from cursor to end of line
                for c in col..line.cells.len() {
                    line.cells[c] = Default::default();
                }
            }
            1 => {
                // Erase from start of line to cursor
                for c in 0..=col {
                    line.cells[c] = Default::default();
                }
            }
            2 => {
                // Erase entire line
                line.clear();
            }
            _ => {}
        }
        line.is_dirty = true;
    }
}

/// SGR - Select Graphic Rendition
fn csi_sgr(term: &mut crate::TerminalCore, params: &vte::Params) {
    let has_params = params.iter().next().is_some();

    if !has_params {
        term.current_attrs.reset();
        return;
    }

    for param_group in params {
        let mut iter = param_group.iter().peekable();

        while let Some(&param) = iter.next() {
            match param {
                0 => term.current_attrs.reset(),
                1 => term.current_attrs.bold = true,
                2 => term.current_attrs.dim = true,
                3 => term.current_attrs.italic = true,
                4 => term.current_attrs.underline = true,
                5 => term.current_attrs.blink_slow = true,
                6 => term.current_attrs.blink_fast = true,
                7 => term.current_attrs.inverse = true,
                8 => term.current_attrs.hidden = true,
                9 => term.current_attrs.strikethrough = true,
                22 => {
                    term.current_attrs.bold = false;
                    term.current_attrs.dim = false;
                }
                23 => term.current_attrs.italic = false,
                24 => term.current_attrs.underline = false,
                25 => {
                    term.current_attrs.blink_slow = false;
                    term.current_attrs.blink_fast = false;
                }
                27 => term.current_attrs.inverse = false,
                28 => term.current_attrs.hidden = false,
                29 => term.current_attrs.strikethrough = false,

                // Foreground colors
                30..=37 => {
                    let color = match param {
                        30 => NamedColor::Black,
                        31 => NamedColor::Red,
                        32 => NamedColor::Green,
                        33 => NamedColor::Yellow,
                        34 => NamedColor::Blue,
                        35 => NamedColor::Magenta,
                        36 => NamedColor::Cyan,
                        37 => NamedColor::White,
                        _ => NamedColor::White,
                    };
                    term.current_attrs.foreground = Color::Named(color);
                }
                38 => parse_extended_color(term, &mut iter, true),
                39 => term.current_attrs.foreground = Color::Default,

                // Background colors
                40..=47 => {
                    let color = match param {
                        40 => NamedColor::Black,
                        41 => NamedColor::Red,
                        42 => NamedColor::Green,
                        43 => NamedColor::Yellow,
                        44 => NamedColor::Blue,
                        45 => NamedColor::Magenta,
                        46 => NamedColor::Cyan,
                        47 => NamedColor::White,
                        _ => NamedColor::Black,
                    };
                    term.current_attrs.background = Color::Named(color);
                }
                48 => parse_extended_color(term, &mut iter, false),
                49 => term.current_attrs.background = Color::Default,

                // Bright foreground (90-97)
                90..=97 => {
                    let color = match param {
                        90 => NamedColor::BrightBlack,
                        91 => NamedColor::BrightRed,
                        92 => NamedColor::BrightGreen,
                        93 => NamedColor::BrightYellow,
                        94 => NamedColor::BrightBlue,
                        95 => NamedColor::BrightMagenta,
                        96 => NamedColor::BrightCyan,
                        97 => NamedColor::BrightWhite,
                        _ => NamedColor::BrightWhite,
                    };
                    term.current_attrs.foreground = Color::Named(color);
                }

                // Bright background (100-107)
                100..=107 => {
                    let color = match param {
                        100 => NamedColor::BrightBlack,
                        101 => NamedColor::BrightRed,
                        102 => NamedColor::BrightGreen,
                        103 => NamedColor::BrightYellow,
                        104 => NamedColor::BrightBlue,
                        105 => NamedColor::BrightMagenta,
                        106 => NamedColor::BrightCyan,
                        107 => NamedColor::BrightWhite,
                        _ => NamedColor::BrightBlack,
                    };
                    term.current_attrs.background = Color::Named(color);
                }

                _ => {}
            }
        }
    }
}

/// Parse extended color (256-color or truecolor)
fn parse_extended_color<'a>(
    term: &mut crate::TerminalCore,
    iter: &mut std::iter::Peekable<impl Iterator<Item = &'a u16>>,
    foreground: bool,
) {
    let color = match iter.next() {
        Some(&5) => {
            // 256-color mode: 38;5;n or 48;5;n
            if let Some(&n) = iter.next() {
                Color::Indexed(n as u8)
            } else {
                return;
            }
        }
        Some(&2) => {
            // Truecolor mode: 38;2;r;g;b or 48;2;r;g;b
            let r = iter.next().map(|&v| v as u8).unwrap_or(0);
            let g = iter.next().map(|&v| v as u8).unwrap_or(0);
            let b = iter.next().map(|&v| v as u8).unwrap_or(0);
            Color::Rgb(r, g, b)
        }
        _ => return,
    };

    if foreground {
        term.current_attrs.foreground = color;
    } else {
        term.current_attrs.background = color;
    }
}

/// DECSTBM - Set Top and Bottom Margins (scroll region)
fn csi_decstbm(term: &mut crate::TerminalCore, params: &vte::Params) {
    let top = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(0)
        .saturating_sub(1);
    let bottom = params
        .iter()
        .nth(1)
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(term.screen.rows());

    term.screen.set_scroll_region(top as usize, bottom as usize);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sgr_reset() {
        let mut term = crate::TerminalCore::new(24, 80);
        term.current_attrs.bold = true;
        term.current_attrs.italic = true;

        let params = vte::Params::default();
        csi_sgr(&mut term, &params);

        assert!(!term.current_attrs.bold);
        assert!(!term.current_attrs.italic);
    }
}
