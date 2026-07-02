//! SGR (Select Graphic Rendition) parameter parsing

use crate::types::cell::{SgrAttributes, SgrFlags, UnderlineStyle};
use crate::types::{Color, NamedColor};

#[path = "sgr_support.rs"]
mod support;
use support::{
    apply_extended_sgr_color, apply_named_sgr_color_group, apply_sgr_color, SgrColorTarget,
};

/// Maximum number of SGR parameter groups in a single CSI sequence.
///
/// `vte::Params` caps at `MAX_PARAMS = 32` groups, so a fixed-size stack array
/// of this length is sufficient to collect all groups without allocation.
const SGR_MAX_PARAMS: usize = 32;

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
///
/// Collects `params` into a fixed-size stack array and delegates to
/// `apply_sgr_attrs`, which owns the full dispatch table.  The two entry
/// points exist because `apply_sgr_attrs` operates on a bare `SgrAttributes`
/// (needed by DECCARA) while this function is called from the VTE parser
/// with a `TerminalCore` borrow.
pub fn handle_sgr(term: &mut crate::TerminalCore, params: &vte::Params) {
    let (group_buf, group_count) = collect_param_groups(params);
    apply_sgr_attrs(&mut term.current_attrs, &group_buf[..group_count]);
}

/// Collect all `vte::Params` groups into a fixed stack array.
///
/// `vte::Params` caps the number of parameter groups, so a fixed array is
/// sufficient and avoids heap allocation. The returned slice range preserves
/// the original group order for cross-group parsing.
pub(crate) fn collect_param_groups<'a>(
    params: &'a vte::Params,
) -> ([&'a [u16]; SGR_MAX_PARAMS], usize) {
    let mut group_buf: [&'a [u16]; SGR_MAX_PARAMS] = [&[]; SGR_MAX_PARAMS];
    let mut group_count = 0;

    for group in params {
        if group_count == SGR_MAX_PARAMS {
            break;
        }
        group_buf[group_count] = group;
        group_count += 1;
    }

    (group_buf, group_count)
}

/// Extract the next sub-parameter group's first byte, advancing `i`.
/// Returns `0` if the group is absent or empty — a missing RGB component
/// defaults to 0 (black channel), producing the least-surprising degraded
/// color for a truncated truecolor sequence like `\e[38;2;255;128m` (missing blue).
/// Values > 255 are truncated to the low 8 bits (xterm-compatible behavior).
#[inline]
fn apply_underline_style(attrs: &mut SgrAttributes, group: &[u16]) {
    attrs.underline_style = if group.len() > 1 {
        match group[1] {
            0 => UnderlineStyle::None,
            2 => UnderlineStyle::Double,
            3 => UnderlineStyle::Curly,
            4 => UnderlineStyle::Dotted,
            5 => UnderlineStyle::Dashed,
            _ => UnderlineStyle::Straight,
        }
    } else {
        UnderlineStyle::Straight
    };
}

#[inline]
fn remove_sgr_flags(attrs: &mut SgrAttributes, flags: &[SgrFlags]) {
    for flag in flags {
        attrs.flags.remove(*flag);
    }
}

#[inline]
fn set_sgr_script(attrs: &mut SgrAttributes, superscript: bool, subscript: bool) {
    attrs.superscript = superscript;
    attrs.subscript = subscript;
}

#[inline]
fn apply_sgr_flag_group(attrs: &mut SgrAttributes, param: u16) -> bool {
    match param {
        0 => {
            attrs.reset();
            true
        }
        1 => {
            attrs.flags.insert(SgrFlags::BOLD);
            true
        }
        2 => {
            attrs.flags.insert(SgrFlags::DIM);
            true
        }
        3 => {
            attrs.flags.insert(SgrFlags::ITALIC);
            true
        }
        5 => {
            attrs.flags.insert(SgrFlags::BLINK_SLOW);
            true
        }
        6 => {
            attrs.flags.insert(SgrFlags::BLINK_FAST);
            true
        }
        7 => {
            attrs.flags.insert(SgrFlags::INVERSE);
            true
        }
        8 => {
            attrs.flags.insert(SgrFlags::HIDDEN);
            true
        }
        9 => {
            attrs.flags.insert(SgrFlags::STRIKETHROUGH);
            true
        }
        _ => false,
    }
}

#[inline]
fn apply_sgr_style_group(attrs: &mut SgrAttributes, param: u16) -> bool {
    match param {
        21 => {
            attrs.underline_style = UnderlineStyle::Double;
            true
        }
        22 => {
            remove_sgr_flags(attrs, &[SgrFlags::BOLD, SgrFlags::DIM]);
            true
        }
        23 => {
            attrs.flags.remove(SgrFlags::ITALIC);
            true
        }
        24 => {
            attrs.underline_style = UnderlineStyle::None;
            true
        }
        25 => {
            remove_sgr_flags(attrs, &[SgrFlags::BLINK_SLOW, SgrFlags::BLINK_FAST]);
            true
        }
        27 => {
            attrs.flags.remove(SgrFlags::INVERSE);
            true
        }
        28 => {
            attrs.flags.remove(SgrFlags::HIDDEN);
            true
        }
        29 => {
            attrs.flags.remove(SgrFlags::STRIKETHROUGH);
            true
        }
        53 => {
            attrs.overline = true;
            true
        }
        55 => {
            attrs.overline = false;
            true
        }
        73 => {
            set_sgr_script(attrs, true, false);
            true
        }
        74 => {
            set_sgr_script(attrs, false, false);
            true
        }
        75 => {
            set_sgr_script(attrs, false, true);
            true
        }
        _ => false,
    }
}

#[inline]
fn apply_sgr_underline_group(attrs: &mut SgrAttributes, param: u16, group: &[u16]) -> bool {
    if param != 4 {
        return false;
    }

    apply_underline_style(attrs, group);
    true
}

#[inline]
fn apply_sgr_color_group(
    attrs: &mut SgrAttributes,
    groups: &[&[u16]],
    i: &mut usize,
    group: &[u16],
    param: u16,
) -> bool {
    if apply_named_sgr_color_group(attrs, param) {
        return true;
    }

    match param {
        38 => {
            apply_extended_sgr_color(attrs, SgrColorTarget::Foreground, groups, i, group);
            true
        }
        39 => {
            apply_sgr_color(attrs, SgrColorTarget::Foreground, Color::Default);
            true
        }
        48 => {
            apply_extended_sgr_color(attrs, SgrColorTarget::Background, groups, i, group);
            true
        }
        49 => {
            apply_sgr_color(attrs, SgrColorTarget::Background, Color::Default);
            true
        }
        58 => {
            apply_extended_sgr_color(attrs, SgrColorTarget::Underline, groups, i, group);
            true
        }
        59 => {
            apply_sgr_color(attrs, SgrColorTarget::Underline, Color::Default);
            true
        }
        _ => false,
    }
}

#[inline]
fn apply_sgr_group(attrs: &mut SgrAttributes, groups: &[&[u16]], i: &mut usize, group: &[u16]) {
    let param = group[0];
    let _ = apply_sgr_flag_group(attrs, param)
        || apply_sgr_underline_group(attrs, param, group)
        || apply_sgr_style_group(attrs, param)
        || apply_sgr_color_group(attrs, groups, i, group, param);
}

#[inline]
fn next_sgr_group<'a>(groups: &'a [&'a [u16]], i: &mut usize) -> Option<&'a [u16]> {
    while *i < groups.len() {
        let group = groups[*i];
        *i += 1;
        if !group.is_empty() {
            return Some(group);
        }
    }
    None
}

/// Apply pre-parsed SGR parameter groups directly to `attrs`.
///
/// This is the single authoritative SGR dispatch table, shared by both
/// [`handle_sgr`] (VTE parser path, via `term.current_attrs`) and
/// [`handle_deccara`][crate::parser::erase::handle_deccara] (rectangular-area
/// attribute change, direct `SgrAttributes` borrow).
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
    while let Some(group) = next_sgr_group(groups, &mut i) {
        apply_sgr_group(attrs, groups, &mut i, group);
    }
}

#[path = "sgr_serialize.rs"]
mod serialize;

pub(crate) use serialize::serialize_sgr;

#[cfg(test)]
#[path = "tests/sgr.rs"]
mod tests;
