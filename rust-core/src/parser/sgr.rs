//! SGR (Select Graphic Rendition) parameter parsing

use crate::types::cell::{SgrAttributes, SgrFlags, UnderlineStyle};
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

/// Generate a `const fn` that maps an offset (0–7) to a `Color::Named` variant.
///
/// Both `named_color_from_offset` and `bright_named_color_from_offset` share identical
/// structure: 8 literal arms mapping an offset to a `NamedColor` variant, with a
/// `_ => Color::Default` fallback.  The macro eliminates the structural duplication
/// while keeping each generated function independently inlineable.
macro_rules! color_mapper {
    ($fn_name:ident, [ $( $i:literal => $color:ident ),* $(,)? ]) => {
        #[inline]
        const fn $fn_name(offset: u16) -> Color {
            match offset {
                $( $i => Color::Named(NamedColor::$color), )*
                _ => Color::Default,
            }
        }
    };
}

// Map a named-color parameter offset (0–7) to a `Color::Named` variant.
// `offset = param - base` where base is 30 or 40.
color_mapper!(named_color_from_offset, [
    0 => Black,
    1 => Red,
    2 => Green,
    3 => Yellow,
    4 => Blue,
    5 => Magenta,
    6 => Cyan,
    7 => White,
]);

// Map a bright named-color parameter offset (0–7) to a `Color::Named` bright variant.
// `offset = param - base` where base is 90 (foreground) or 100 (background).
color_mapper!(bright_named_color_from_offset, [
    0 => BrightBlack,
    1 => BrightRed,
    2 => BrightGreen,
    3 => BrightYellow,
    4 => BrightBlue,
    5 => BrightMagenta,
    6 => BrightCyan,
    7 => BrightWhite,
]);

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

            // Overline (SGR 53/55)
            53 => term.current_attrs.overline = true,
            55 => term.current_attrs.overline = false,

            // Superscript / subscript (SGR 73/74/75)
            // 73 = superscript on, 74 = cancel both, 75 = subscript on
            73 => { term.current_attrs.superscript = true;  term.current_attrs.subscript = false; }
            74 => { term.current_attrs.superscript = false; term.current_attrs.subscript = false; }
            75 => { term.current_attrs.subscript = true;    term.current_attrs.superscript = false; }

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

/// Apply pre-parsed SGR parameter groups directly to `attrs`.
///
/// Same inner logic as [`handle_sgr`] but operates on a bare [`SgrAttributes`]
/// instead of a full [`TerminalCore`].  Used by
/// [`handle_deccara`][crate::parser::erase::handle_deccara] to apply SGR
/// parameters to cells in a rectangular area without a `TerminalCore` borrow.
///
/// `groups` is a slice of sub-parameter slices as produced by iterating
/// [`vte::Params`] and collecting into a `[&[u16]; N]` array.
#[inline]
pub(crate) fn apply_sgr_attrs(attrs: &mut SgrAttributes, groups: &[&[u16]]) {
    if groups.is_empty() {
        attrs.reset();
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
            0 => attrs.reset(),
            1 => attrs.flags.insert(SgrFlags::BOLD),
            2 => attrs.flags.insert(SgrFlags::DIM),
            3 => attrs.flags.insert(SgrFlags::ITALIC),
            4 => {
                if group.len() > 1 {
                    attrs.underline_style = match group[1] {
                        0 => UnderlineStyle::None,
                        2 => UnderlineStyle::Double,
                        3 => UnderlineStyle::Curly,
                        4 => UnderlineStyle::Dotted,
                        5 => UnderlineStyle::Dashed,
                        _ => UnderlineStyle::Straight,
                    };
                } else {
                    attrs.underline_style = UnderlineStyle::Straight;
                }
            }
            5  => attrs.flags.insert(SgrFlags::BLINK_SLOW),
            6  => attrs.flags.insert(SgrFlags::BLINK_FAST),
            7  => attrs.flags.insert(SgrFlags::INVERSE),
            8  => attrs.flags.insert(SgrFlags::HIDDEN),
            9  => attrs.flags.insert(SgrFlags::STRIKETHROUGH),
            21 => attrs.underline_style = UnderlineStyle::Double,
            22 => {
                attrs.flags.remove(SgrFlags::BOLD);
                attrs.flags.remove(SgrFlags::DIM);
            }
            23 => attrs.flags.remove(SgrFlags::ITALIC),
            24 => attrs.underline_style = UnderlineStyle::None,
            25 => {
                attrs.flags.remove(SgrFlags::BLINK_SLOW);
                attrs.flags.remove(SgrFlags::BLINK_FAST);
            }
            27 => attrs.flags.remove(SgrFlags::INVERSE),
            28 => attrs.flags.remove(SgrFlags::HIDDEN),
            29 => attrs.flags.remove(SgrFlags::STRIKETHROUGH),
            30..=37  => attrs.foreground = named_color_from_offset(param - 30),
            38 => {
                if let Some(c) = parse_color_from_subparams(groups, &mut i, group) {
                    attrs.foreground = c;
                }
            }
            39 => attrs.foreground = Color::Default,
            40..=47  => attrs.background = named_color_from_offset(param - 40),
            48 => {
                if let Some(c) = parse_color_from_subparams(groups, &mut i, group) {
                    attrs.background = c;
                }
            }
            49 => attrs.background = Color::Default,
            53 => attrs.overline = true,
            55 => attrs.overline = false,
            58 => {
                if let Some(c) = parse_color_from_subparams(groups, &mut i, group) {
                    attrs.underline_color = c;
                }
            }
            59  => attrs.underline_color = Color::Default,
            73  => { attrs.superscript = true;  attrs.subscript = false; }
            74  => { attrs.superscript = false; attrs.subscript = false; }
            75  => { attrs.subscript = true;    attrs.superscript = false; }
            90..=97   => attrs.foreground = bright_named_color_from_offset(param - 90),
            100..=107 => attrs.background = bright_named_color_from_offset(param - 100),
            _ => {}
        }
    }
}

/// Serialize `attrs` back into an SGR parameter string for DECRQSS (`DCS $ q m`).
///
/// Begins with `0` (reset) and appends a parameter for each active attribute,
/// matching the xterm convention (so the default rendition serializes to `0`).
/// Every emitted form round-trips through this module's own parser — semicolon
/// form for the 38/48/58 extended colors, `4:n` for styled underlines — so a
/// client that re-applies the reported string recreates the exact rendition.
pub(crate) fn serialize_sgr(attrs: &SgrAttributes) -> String {
    use std::fmt::Write as _;

    let mut out = String::from("0");
    let f = attrs.flags;
    if f.contains(SgrFlags::BOLD) {
        out.push_str(";1");
    }
    if f.contains(SgrFlags::DIM) {
        out.push_str(";2");
    }
    if f.contains(SgrFlags::ITALIC) {
        out.push_str(";3");
    }
    match attrs.underline_style {
        UnderlineStyle::None => {}
        UnderlineStyle::Straight => out.push_str(";4"),
        UnderlineStyle::Double => out.push_str(";4:2"),
        UnderlineStyle::Curly => out.push_str(";4:3"),
        UnderlineStyle::Dotted => out.push_str(";4:4"),
        UnderlineStyle::Dashed => out.push_str(";4:5"),
    }
    if f.contains(SgrFlags::BLINK_SLOW) {
        out.push_str(";5");
    }
    if f.contains(SgrFlags::BLINK_FAST) {
        out.push_str(";6");
    }
    if f.contains(SgrFlags::INVERSE) {
        out.push_str(";7");
    }
    if f.contains(SgrFlags::HIDDEN) {
        out.push_str(";8");
    }
    if f.contains(SgrFlags::STRIKETHROUGH) {
        out.push_str(";9");
    }
    append_sgr_color(&mut out, attrs.foreground, 30, 90, 38);
    append_sgr_color(&mut out, attrs.background, 40, 100, 48);
    // Underline color: only indexed (58;5;n) or RGB (58;2;r;g;b) — the parser
    // never produces a named underline color, so that variant is unreachable.
    match attrs.underline_color {
        Color::Indexed(n) => {
            let _ = write!(out, ";58;5;{n}");
        }
        Color::Rgb(r, g, b) => {
            let _ = write!(out, ";58;2;{r};{g};{b}");
        }
        Color::Default | Color::Named(_) => {}
    }
    out
}

/// Append one foreground/background color to an SGR string.
///
/// `base`/`bright_base` are the named-color SGR bases (30/90 for fg, 40/100 for
/// bg) and `ext` is the extended-color introducer (38 fg, 48 bg).
fn append_sgr_color(out: &mut String, color: Color, base: u8, bright_base: u8, ext: u8) {
    use std::fmt::Write as _;
    match color {
        Color::Default => {}
        Color::Named(n) => {
            let idx = n as u8;
            let code = if idx < 8 {
                base + idx
            } else {
                bright_base + (idx - 8)
            };
            let _ = write!(out, ";{code}");
        }
        Color::Indexed(i) => {
            let _ = write!(out, ";{ext};5;{i}");
        }
        Color::Rgb(r, g, b) => {
            let _ = write!(out, ";{ext};2;{r};{g};{b}");
        }
    }
}

#[cfg(test)]
#[path = "tests/sgr.rs"]
mod tests;
