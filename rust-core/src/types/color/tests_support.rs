use crate::types::color::NamedColor;
use crate::Color;

pub(crate) const ALL_NAMED_COLORS: [NamedColor; 16] = [
    NamedColor::Black,
    NamedColor::Red,
    NamedColor::Green,
    NamedColor::Yellow,
    NamedColor::Blue,
    NamedColor::Magenta,
    NamedColor::Cyan,
    NamedColor::White,
    NamedColor::BrightBlack,
    NamedColor::BrightRed,
    NamedColor::BrightGreen,
    NamedColor::BrightYellow,
    NamedColor::BrightBlue,
    NamedColor::BrightMagenta,
    NamedColor::BrightCyan,
    NamedColor::BrightWhite,
];

pub(crate) const CUBE_RED_CASES: &[(u8, u8)] = &[
    (16, 0),
    (52, 51),
    (88, 102),
    (124, 153),
    (160, 204),
    (196, 255),
];

pub(crate) const CUBE_GREEN_CASES: &[(u8, u8)] = &[
    (16, 0),
    (22, 51),
    (28, 102),
    (34, 153),
    (40, 204),
    (46, 255),
];

pub(crate) fn all_named_color_rgb_values() -> impl Iterator<Item = (u8, u8, u8)> {
    ALL_NAMED_COLORS.iter().copied().map(|color| color.to_rgb())
}

pub(crate) fn default_rgb() -> (u8, u8, u8) {
    Color::Default.to_rgb()
}
