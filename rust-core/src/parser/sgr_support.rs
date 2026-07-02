use crate::types::cell::SgrAttributes;
use crate::types::Color;

use super::{bright_named_color_from_offset, named_color_from_offset};

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

#[derive(Copy, Clone)]
struct SgrColorByte(u8);

impl SgrColorByte {
    #[inline]
    fn from_param(value: u16) -> Option<Self> {
        u8::try_from(value).ok().map(Self)
    }
}

impl From<SgrColorByte> for u8 {
    #[inline]
    fn from(value: SgrColorByte) -> Self {
        value.0
    }
}

#[derive(Copy, Clone)]
struct SgrRgb {
    red: SgrColorByte,
    green: SgrColorByte,
    blue: SgrColorByte,
}

impl SgrRgb {
    #[inline]
    fn from_params(red: u16, green: u16, blue: u16) -> Option<Self> {
        Some(Self {
            red: SgrColorByte::from_param(red)?,
            green: SgrColorByte::from_param(green)?,
            blue: SgrColorByte::from_param(blue)?,
        })
    }
}

impl From<SgrRgb> for Color {
    #[inline]
    fn from(value: SgrRgb) -> Self {
        Self::Rgb(value.red.into(), value.green.into(), value.blue.into())
    }
}

#[derive(Copy, Clone)]
pub(super) enum SgrColorTarget {
    Foreground,
    Background,
    Underline,
}

const NAMED_SGR_COLOR_GROUPS: &[(u16, u16, SgrColorTarget, bool)] = &[
    (30, 37, SgrColorTarget::Foreground, false),
    (40, 47, SgrColorTarget::Background, false),
    (90, 97, SgrColorTarget::Foreground, true),
    (100, 107, SgrColorTarget::Background, true),
];

#[inline]
fn next_required_param(groups: &[&[u16]], i: &mut usize) -> Option<u16> {
    if *i < groups.len() && !groups[*i].is_empty() {
        let value = groups[*i][0];
        *i += 1;
        Some(value)
    } else {
        None
    }
}

#[inline]
fn parse_colon_indexed_color(current_group: &[u16]) -> Option<Color> {
    let index = current_group.get(COLOR_INDEX_IDX).copied()?;
    Some(Color::Indexed(SgrColorByte::from_param(index)?.into()))
}

#[inline]
fn parse_colon_rgb_color(current_group: &[u16]) -> Option<Color> {
    let red = current_group.get(RGB_RED_IDX).copied()?;
    let green = current_group.get(RGB_GREEN_IDX).copied()?;
    let blue = current_group.get(RGB_BLUE_IDX).copied()?;
    SgrRgb::from_params(red, green, blue).map(Color::from)
}

#[inline]
fn parse_colon_form_color(current_group: &[u16]) -> Option<Color> {
    match current_group.get(COLOR_MODE_IDX).copied() {
        Some(5) => parse_colon_indexed_color(current_group),
        Some(2) => parse_colon_rgb_color(current_group),
        _ => None,
    }
}

#[inline]
fn parse_semicolon_indexed_color(groups: &[&[u16]], i: &mut usize) -> Option<Color> {
    if *i < groups.len() && !groups[*i].is_empty() {
        let index = groups[*i][0];
        *i += 1;
        Some(Color::Indexed(SgrColorByte::from_param(index)?.into()))
    } else {
        None
    }
}

#[inline]
fn parse_semicolon_rgb_color(groups: &[&[u16]], i: &mut usize) -> Option<Color> {
    let red = next_required_param(groups, i)?;
    let green = next_required_param(groups, i)?;
    let blue = next_required_param(groups, i)?;
    SgrRgb::from_params(red, green, blue).map(Color::from)
}

#[inline]
fn parse_semicolon_form_color(groups: &[&[u16]], i: &mut usize) -> Option<Color> {
    if *i >= groups.len() || groups[*i].is_empty() {
        return None;
    }

    let mode = groups[*i][0];
    *i += 1;

    match mode {
        5 => parse_semicolon_indexed_color(groups, i),
        2 => parse_semicolon_rgb_color(groups, i),
        _ => None,
    }
}

/// Shared color parser for `38`/`48`/`58` SGR sequences.
///
/// Handles two structural forms produced by the VTE parser:
///
/// **Colon form** (`38:5:196`): All sub-params are in `current_group` as
/// `[38, 5, 196]`. The mode and color values are read directly from the
/// sub-parameter slots via the named index constants.
///
/// **Semicolon form** (`38;5;196`): Each value arrives as a separate group:
/// `[[38], [5], [196]]`. After `38` is consumed, subsequent groups are
/// consumed by advancing `i` through `groups`.
///
/// Returns `None` if the sequence is malformed.
#[inline]
pub(super) fn parse_color_from_subparams(
    groups: &[&[u16]],
    i: &mut usize,
    current_group: &[u16],
) -> Option<Color> {
    if current_group.len() > 1 {
        parse_colon_form_color(current_group)
    } else {
        parse_semicolon_form_color(groups, i)
    }
}

#[inline]
pub(super) fn apply_sgr_color(attrs: &mut SgrAttributes, target: SgrColorTarget, color: Color) {
    match target {
        SgrColorTarget::Foreground => attrs.foreground = color,
        SgrColorTarget::Background => attrs.background = color,
        SgrColorTarget::Underline => attrs.underline_color = color,
    }
}

#[inline]
fn apply_named_sgr_color(
    attrs: &mut SgrAttributes,
    target: SgrColorTarget,
    offset: u16,
    bright: bool,
) {
    let color = if bright {
        bright_named_color_from_offset(offset)
    } else {
        named_color_from_offset(offset)
    };
    apply_sgr_color(attrs, target, color);
}

#[inline]
pub(super) fn apply_named_sgr_color_group(attrs: &mut SgrAttributes, param: u16) -> bool {
    for &(start, end, target, bright) in NAMED_SGR_COLOR_GROUPS {
        if (start..=end).contains(&param) {
            apply_named_sgr_color(attrs, target, param - start, bright);
            return true;
        }
    }
    false
}

#[inline]
pub(super) fn apply_extended_sgr_color(
    attrs: &mut SgrAttributes,
    target: SgrColorTarget,
    groups: &[&[u16]],
    i: &mut usize,
    group: &[u16],
) {
    if let Some(color) = parse_color_from_subparams(groups, i, group) {
        apply_sgr_color(attrs, target, color);
    }
}
