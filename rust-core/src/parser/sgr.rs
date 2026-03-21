//! SGR (Select Graphic Rendition) parameter parsing

use crate::types::cell::{SgrFlags, UnderlineStyle};
use crate::types::{Color, NamedColor};

/// Maximum number of SGR parameter groups in a single CSI sequence.
///
/// `vte::Params` caps at `MAX_PARAMS = 32` groups, so a fixed-size stack array
/// of this length is sufficient to collect all groups without allocation.
const SGR_MAX_PARAMS: usize = 32;

/// Sub-parameter index for the color mode selector in a colon-form SGR extended color sequence.
///
/// In `CSI 38 : mode : ... m`, the sub-parameters are `[38, mode, ...]`.
/// Index 0 is the base param (`38` for foreground, `48` for background, `58` for underline).
/// Index 1 is the mode: `2` = RGB, `5` = 256-color indexed.
const COLOR_MODE_IDX: usize = 1;
/// Sub-parameter index for the palette index in 256-color indexed mode (`mode = 5`).
///
/// In `CSI 38 : 5 : n m`, `n` is the 256-color palette entry (0-255).
const COLOR_INDEX_IDX: usize = 2;
/// Sub-parameter index for the red RGB component.
const RGB_RED_IDX: usize = 2;
/// Sub-parameter index for the green RGB component.
const RGB_GREEN_IDX: usize = 3;
/// Sub-parameter index for the blue RGB component.
const RGB_BLUE_IDX: usize = 4;

/// Map a named-color parameter offset (0–7) to a `Color::Named` variant.
/// `offset = param - base` where base is 30 or 40.
#[inline]
const fn named_color_from_offset(offset: u16) -> Color {
    match offset {
        0 => Color::Named(NamedColor::Black),
        1 => Color::Named(NamedColor::Red),
        2 => Color::Named(NamedColor::Green),
        3 => Color::Named(NamedColor::Yellow),
        4 => Color::Named(NamedColor::Blue),
        5 => Color::Named(NamedColor::Magenta),
        6 => Color::Named(NamedColor::Cyan),
        7 => Color::Named(NamedColor::White),
        _ => Color::Default,
    }
}

/// Map a bright named-color parameter offset (0–7) to a `Color::Named` bright variant.
/// `offset = param - base` where base is 90 (foreground) or 100 (background).
#[inline]
const fn bright_named_color_from_offset(offset: u16) -> Color {
    match offset {
        0 => Color::Named(NamedColor::BrightBlack),
        1 => Color::Named(NamedColor::BrightRed),
        2 => Color::Named(NamedColor::BrightGreen),
        3 => Color::Named(NamedColor::BrightYellow),
        4 => Color::Named(NamedColor::BrightBlue),
        5 => Color::Named(NamedColor::BrightMagenta),
        6 => Color::Named(NamedColor::BrightCyan),
        7 => Color::Named(NamedColor::BrightWhite),
        _ => Color::Default,
    }
}

/// Handle SGR (Select Graphic Rendition) — CSI 'm' sequences only.
///
/// All other CSI sequences (cursor movement, erase, scroll) are handled
/// by their dedicated modules (`parser::csi`, `parser::erase`, `parser::scroll`).
pub fn handle_sgr(term: &mut crate::TerminalCore, params: &vte::Params) {
    // Collect all param groups into a fixed stack array for index-based cross-group consumption.
    // This handles both forms of extended color sequences:
    //   Semicolon form: \e[38;5;196m  → groups [[38], [5], [196]] (3 separate groups)
    //   Colon form:     \e[38:5:196m  → groups [[38, 5, 196]] (1 group, 3 sub-params)
    // vte::Params caps at MAX_PARAMS = 32 groups, so a fixed array is sufficient.
    let mut group_buf: [&[u16]; SGR_MAX_PARAMS] = [&[]; SGR_MAX_PARAMS];
    let mut group_count = 0;
    for group in params {
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
            1 => term.current_attrs.flags.insert(SgrFlags::BOLD),
            2 => term.current_attrs.flags.insert(SgrFlags::DIM),
            3 => term.current_attrs.flags.insert(SgrFlags::ITALIC),
            4 => {
                // SGR 4 with no sub-params = straight underline; sub-params handled below
                if group.len() > 1 {
                    // 4:0 = none, 4:1 = straight, 4:2 = double, 4:3 = curly, 4:4 = dotted, 4:5 = dashed
                    term.current_attrs.underline_style = match group[1] {
                        0 => UnderlineStyle::None,
                        2 => UnderlineStyle::Double,
                        3 => UnderlineStyle::Curly,
                        4 => UnderlineStyle::Dotted,
                        5 => UnderlineStyle::Dashed,
                        _ => UnderlineStyle::Straight,
                    };
                } else {
                    term.current_attrs.underline_style = UnderlineStyle::Straight;
                }
            }
            5 => term.current_attrs.flags.insert(SgrFlags::BLINK_SLOW),
            6 => term.current_attrs.flags.insert(SgrFlags::BLINK_FAST),
            7 => term.current_attrs.flags.insert(SgrFlags::INVERSE),
            8 => term.current_attrs.flags.insert(SgrFlags::HIDDEN),
            9 => term.current_attrs.flags.insert(SgrFlags::STRIKETHROUGH),
            22 => {
                term.current_attrs.flags.remove(SgrFlags::BOLD);
                term.current_attrs.flags.remove(SgrFlags::DIM);
            }
            23 => term.current_attrs.flags.remove(SgrFlags::ITALIC),
            24 => term.current_attrs.underline_style = UnderlineStyle::None,
            25 => {
                term.current_attrs.flags.remove(SgrFlags::BLINK_SLOW);
                term.current_attrs.flags.remove(SgrFlags::BLINK_FAST);
            }
            21 => term.current_attrs.underline_style = UnderlineStyle::Double, // SGR 21: double underline
            27 => term.current_attrs.flags.remove(SgrFlags::INVERSE),
            28 => term.current_attrs.flags.remove(SgrFlags::HIDDEN),
            29 => term.current_attrs.flags.remove(SgrFlags::STRIKETHROUGH),

            // Foreground colors
            30..=37 => {
                term.current_attrs.foreground = named_color_from_offset(param - 30);
            }
            38 => parse_extended_color(term, groups, &mut i, group, true),
            39 => term.current_attrs.foreground = Color::Default,

            // Background colors
            40..=47 => {
                term.current_attrs.background = named_color_from_offset(param - 40);
            }
            48 => parse_extended_color(term, groups, &mut i, group, false),
            49 => term.current_attrs.background = Color::Default,

            // Underline color (SGR 58/59)
            58 => parse_underline_color(term, groups, &mut i, group),
            59 => term.current_attrs.underline_color = Color::Default,

            // Bright foreground (90-97)
            90..=97 => {
                term.current_attrs.foreground = bright_named_color_from_offset(param - 90);
            }

            // Bright background (100-107)
            100..=107 => {
                term.current_attrs.background = bright_named_color_from_offset(param - 100);
            }

            _ => {}
        }
    }
}

/// Extract the next sub-parameter group's first byte, advancing `i`.
/// Returns `0` if the group is absent or empty — a missing RGB component
/// defaults to 0 (black channel), producing the least-surprising degraded
/// color for a truncated truecolor sequence like `\e[38;2;255;128m` (missing blue).
/// Values > 255 are truncated to the low 8 bits (xterm-compatible behavior).
#[inline]
#[expect(
    clippy::cast_possible_truncation,
    reason = "VTE sub-params are u16; RGB values 0-255 fit; out-of-range values truncate to low 8 bits (xterm-compatible)"
)]
fn next_component(groups: &[&[u16]], i: &mut usize) -> u8 {
    if *i < groups.len() && !groups[*i].is_empty() {
        let v = groups[*i][0] as u8;
        *i += 1;
        v
    } else {
        0
    }
}

/// Shared color parser for `38`/`48`/`58` SGR sequences.
///
/// Handles two structural forms produced by the VTE parser:
///
/// **Colon form** (`38:5:196`): All sub-params are in `current_group` as
/// `[38, 5, 196]`.  The mode and color values are read directly from the
/// sub-parameter slots via the named index constants.
///
/// **Semicolon form** (`38;5;196`): Each value arrives as a separate group:
/// `[[38], [5], [196]]`.  After `38` is consumed, subsequent groups are
/// consumed by advancing `i` through `groups`.
///
/// Returns `None` if the sequence is malformed.
#[inline]
fn parse_color_from_subparams(
    groups: &[&[u16]],
    i: &mut usize,
    current_group: &[u16],
) -> Option<Color> {
    if current_group.len() > 1 {
        // Colon form: sub-params are already in current_group.
        match current_group.get(COLOR_MODE_IDX).copied() {
            Some(5) => {
                // 256-color indexed: XX:5:n
                #[expect(
                    clippy::cast_possible_truncation,
                    reason = "palette index 0-255 from u16 sub-param; values > 255 truncate (xterm-compatible)"
                )]
                let n = current_group.get(COLOR_INDEX_IDX).copied()? as u8;
                Some(Color::Indexed(n))
            }
            Some(2) => {
                // TrueColor RGB: XX:2:r:g:b
                #[expect(
                    clippy::cast_possible_truncation,
                    reason = "RGB components 0-255 from u16 sub-params; values > 255 truncate (xterm-compatible)"
                )]
                let (r, g, b) = (
                    current_group.get(RGB_RED_IDX).copied().unwrap_or(0) as u8,
                    current_group.get(RGB_GREEN_IDX).copied().unwrap_or(0) as u8,
                    current_group.get(RGB_BLUE_IDX).copied().unwrap_or(0) as u8,
                );
                Some(Color::Rgb(r, g, b))
            }
            _ => None,
        }
    } else {
        // Semicolon form: consume subsequent groups from `groups` via index `i`.
        if *i >= groups.len() || groups[*i].is_empty() {
            return None;
        }
        let mode = groups[*i][0];
        *i += 1;

        match mode {
            5 => {
                // mode == 5: indexed color — a missing palette index cannot default to 0
                // (which would silently render as black), so we return None instead.
                // Contrast with mode == 2 (RGB) where missing components default to 0
                // via `next_component` (producing black channel, not black color).
                // 256-color indexed: XX;5;n
                if *i < groups.len() && !groups[*i].is_empty() {
                    #[expect(
                        clippy::cast_possible_truncation,
                        reason = "palette index 0-255; values > 255 truncate (xterm-compatible)"
                    )]
                    let n = groups[*i][0] as u8;
                    *i += 1;
                    Some(Color::Indexed(n))
                } else {
                    None
                }
            }
            2 => {
                // TrueColor RGB: XX;2;r;g;b
                let r = next_component(groups, i);
                let g = next_component(groups, i);
                let b = next_component(groups, i);
                Some(Color::Rgb(r, g, b))
            }
            _ => None,
        }
    }
}

/// Parse extended color (256-color or truecolor) from SGR 38/48 parameters.
///
/// `foreground` — `true` sets `current_attrs.foreground` (SGR 38),
/// `false` sets `current_attrs.background` (SGR 48).
#[inline]
fn parse_extended_color(
    term: &mut crate::TerminalCore,
    groups: &[&[u16]],
    i: &mut usize,
    current_group: &[u16],
    foreground: bool,
) {
    if let Some(color) = parse_color_from_subparams(groups, i, current_group) {
        if foreground {
            term.current_attrs.foreground = color;
        } else {
            term.current_attrs.background = color;
        }
    }
}

/// Parse underline color from SGR 58 parameters (same structure as extended color).
#[inline]
fn parse_underline_color(
    term: &mut crate::TerminalCore,
    groups: &[&[u16]],
    i: &mut usize,
    current_group: &[u16],
) {
    if let Some(color) = parse_color_from_subparams(groups, i, current_group) {
        term.current_attrs.underline_color = color;
    }
}

#[cfg(test)]
#[path = "tests/sgr.rs"]
mod tests;
