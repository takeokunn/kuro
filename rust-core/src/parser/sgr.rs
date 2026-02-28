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
            let row = term.screen.cursor().row;
            for r in row..term.screen.rows() as usize {
                if let Some(line) = term.screen.get_line_mut(r) {
                    line.clear();
                }
            }
        }
        1 => {
            // Erase from start of screen to cursor
            let row = term.screen.cursor().row;
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
    let col = term.screen.cursor().col;
    let row = term.screen.cursor().row;

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
    // Collect all param groups into a fixed stack array for index-based cross-group consumption.
    // This handles both forms of extended color sequences:
    //   Semicolon form: \e[38;5;196m  → groups [[38], [5], [196]] (3 separate groups)
    //   Colon form:     \e[38:5:196m  → groups [[38, 5, 196]] (1 group, 3 sub-params)
    // vte::Params caps at MAX_PARAMS = 32 groups, so a fixed array is sufficient.
    let mut group_buf: [&[u16]; 32] = [&[]; 32];
    let mut group_count = 0;
    for group in params.iter() {
        group_buf[group_count] = group;
        group_count += 1;
    }
    let groups = &group_buf[..group_count];

    if groups.is_empty() {
        term.current_attrs.reset();
        return;
    }

    let mut i = 0;
    while i < groups.len() {
        let group = groups[i];
        if group.is_empty() {
            i += 1;
            continue;
        }
        let param = group[0];
        i += 1;

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
            38 => parse_extended_color(term, &groups, &mut i, group, true),
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
            48 => parse_extended_color(term, &groups, &mut i, group, false),
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

/// Parse extended color (256-color or truecolor) from SGR parameters.
///
/// Handles two structural forms produced by the VTE parser:
///
/// **Colon form** (`38:5:196`): All sub-params are in `current_group` as `[38, 5, 196]`.
/// The sub-params after the `38` are read directly from `current_group`.
///
/// **Semicolon form** (`38;5;196`): Each value arrives as a separate group:
/// `[[38], [5], [196]]`. After `38` is consumed, subsequent groups are consumed
/// by advancing `i` through `groups`.
///
/// `groups` - all param groups collected from `vte::Params`
/// `i` - mutable index into `groups`, already pointing past `current_group`
/// `current_group` - the group slice that contained the `38` or `48` value
/// `foreground` - true for foreground (38), false for background (48)
fn parse_extended_color(
    term: &mut crate::TerminalCore,
    groups: &[&[u16]],
    i: &mut usize,
    current_group: &[u16],
    foreground: bool,
) {
    let color = if current_group.len() > 1 {
        // Colon form: 38:5:196 or 38:2:r:g:b
        // Sub-params are already present in current_group at indices 1, 2, 3, 4
        match current_group.get(1).copied() {
            Some(5) => {
                // 256-color indexed: 38:5:n
                match current_group.get(2).copied() {
                    Some(n) => Color::Indexed(n as u8),
                    None => return,
                }
            }
            Some(2) => {
                // TrueColor RGB: 38:2:r:g:b
                let r = current_group.get(2).copied().unwrap_or(0) as u8;
                let g = current_group.get(3).copied().unwrap_or(0) as u8;
                let b = current_group.get(4).copied().unwrap_or(0) as u8;
                Color::Rgb(r, g, b)
            }
            _ => return,
        }
    } else {
        // Semicolon form: consume subsequent groups from `groups` via index `i`
        let mode = if *i < groups.len() && !groups[*i].is_empty() {
            let m = groups[*i][0];
            *i += 1;
            m
        } else {
            return;
        };

        match mode {
            5 => {
                // 256-color indexed: 38;5;n
                if *i < groups.len() && !groups[*i].is_empty() {
                    let n = groups[*i][0] as u8;
                    *i += 1;
                    Color::Indexed(n)
                } else {
                    return;
                }
            }
            2 => {
                // TrueColor RGB: 38;2;r;g;b
                let r = if *i < groups.len() && !groups[*i].is_empty() {
                    let v = groups[*i][0] as u8;
                    *i += 1;
                    v
                } else {
                    0
                };
                let g = if *i < groups.len() && !groups[*i].is_empty() {
                    let v = groups[*i][0] as u8;
                    *i += 1;
                    v
                } else {
                    0
                };
                let b = if *i < groups.len() && !groups[*i].is_empty() {
                    let v = groups[*i][0] as u8;
                    *i += 1;
                    v
                } else {
                    0
                };
                Color::Rgb(r, g, b)
            }
            _ => return,
        }
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

    #[test]
    fn test_sgr_256_color_fg() {
        // Semicolon form: \e[38;5;196m — three separate param groups
        let mut term = crate::TerminalCore::new(24, 80);
        term.advance(b"\x1b[38;5;196m");
        assert_eq!(term.current_attrs.foreground, crate::types::Color::Indexed(196));
    }

    #[test]
    fn test_sgr_256_color_bg() {
        // Semicolon form: \e[48;5;21m — three separate param groups
        let mut term = crate::TerminalCore::new(24, 80);
        term.advance(b"\x1b[48;5;21m");
        assert_eq!(term.current_attrs.background, crate::types::Color::Indexed(21));
    }

    #[test]
    fn test_sgr_truecolor_fg() {
        // Semicolon form: \e[38;2;255;0;0m — five separate param groups
        // Note: avoid Rgb(0,0,0) as it collides with Color::Default in encode_color
        let mut term = crate::TerminalCore::new(24, 80);
        term.advance(b"\x1b[38;2;255;0;0m");
        assert_eq!(term.current_attrs.foreground, crate::types::Color::Rgb(255, 0, 0));
    }

    #[test]
    fn test_sgr_truecolor_bg() {
        // Semicolon form: \e[48;2;0;128;255m — five separate param groups
        let mut term = crate::TerminalCore::new(24, 80);
        term.advance(b"\x1b[48;2;0;128;255m");
        assert_eq!(term.current_attrs.background, crate::types::Color::Rgb(0, 128, 255));
    }

    #[test]
    fn test_sgr_compound_256_with_attrs() {
        // Compound sequence: bold + 256-color FG + underline in one CSI
        // \e[1;38;5;196;4m — groups: [1], [38], [5], [196], [4]
        let mut term = crate::TerminalCore::new(24, 80);
        term.advance(b"\x1b[1;38;5;196;4m");
        assert!(term.current_attrs.bold, "bold should be set");
        assert!(term.current_attrs.underline, "underline should be set");
        assert_eq!(term.current_attrs.foreground, crate::types::Color::Indexed(196));
    }

    #[test]
    fn test_sgr_named_colors_regression() {
        // Regression: named color params (30-37, 40-47) must still work after refactor
        let mut term = crate::TerminalCore::new(24, 80);
        term.advance(b"\x1b[31m");
        assert_eq!(
            term.current_attrs.foreground,
            crate::types::Color::Named(crate::types::NamedColor::Red)
        );

        term.advance(b"\x1b[42m");
        assert_eq!(
            term.current_attrs.background,
            crate::types::Color::Named(crate::types::NamedColor::Green)
        );

        // Also verify bright variants (90-97, 100-107) after refactor
        term.advance(b"\x1b[91m");
        assert_eq!(
            term.current_attrs.foreground,
            crate::types::Color::Named(crate::types::NamedColor::BrightRed)
        );

        term.advance(b"\x1b[101m");
        assert_eq!(
            term.current_attrs.background,
            crate::types::Color::Named(crate::types::NamedColor::BrightRed)
        );
    }

    #[test]
    fn test_sgr_256_color_colon_form() {
        // Colon form: \e[38:5:196m — all sub-params in one group [38, 5, 196]
        // This exercises the current_group.len() > 1 branch in parse_extended_color
        let mut term = crate::TerminalCore::new(24, 80);
        term.advance(b"\x1b[38:5:196m");
        assert_eq!(term.current_attrs.foreground, crate::types::Color::Indexed(196));
    }

    #[test]
    fn test_sgr_truecolor_colon_form() {
        // Colon form: \e[38:2:255:0:128m — all sub-params in one group
        let mut term = crate::TerminalCore::new(24, 80);
        term.advance(b"\x1b[38:2:255:0:128m");
        assert_eq!(term.current_attrs.foreground, crate::types::Color::Rgb(255, 0, 128));
    }
}
