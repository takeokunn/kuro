//! Color representations and conversions

const SYSTEM_COLOR_MAX: u8 = 15;
const COLOR_CUBE_BASE: u8 = 16;
const COLOR_CUBE_LAST: u8 = 231;
const COLOR_CUBE_SIZE: u8 = 6;
const COLOR_CUBE_STEP: u8 = 51;
const GRAYSCALE_BASE: u8 = 232;
const GRAYSCALE_STEP: u8 = 10;
const GRAYSCALE_OFFSET: u8 = 8;

/// Named ANSI colors (standard 16-color palette)
///
/// Explicit discriminants document the terminal palette indices.  Use
/// [`NamedColor::index`] at FFI boundaries instead of casting the discriminant.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum NamedColor {
    /// Black color (index 0)
    Black = 0,
    /// Red color (index 1)
    Red = 1,
    /// Green color (index 2)
    Green = 2,
    /// Yellow color (index 3)
    Yellow = 3,
    /// Blue color (index 4)
    Blue = 4,
    /// Magenta color (index 5)
    Magenta = 5,
    /// Cyan color (index 6)
    Cyan = 6,
    /// White color (index 7)
    White = 7,
    /// Bright black color (index 8)
    BrightBlack = 8,
    /// Bright red color (index 9)
    BrightRed = 9,
    /// Bright green color (index 10)
    BrightGreen = 10,
    /// Bright yellow color (index 11)
    BrightYellow = 11,
    /// Bright blue color (index 12)
    BrightBlue = 12,
    /// Bright magenta color (index 13)
    BrightMagenta = 13,
    /// Bright cyan color (index 14)
    BrightCyan = 14,
    /// Bright white color (index 15)
    BrightWhite = 15,
}

/// Terminal color representation
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash)]
pub enum Color {
    /// Named color from standard palette
    Named(NamedColor),
    /// Indexed color (256-color palette)
    Indexed(u8),
    /// RGB truecolor
    Rgb(u8, u8, u8),
    /// Default foreground/background
    #[default]
    Default,
}

impl Color {
    /// Convert color to RGB triple
    #[must_use]
    pub const fn to_rgb(&self) -> (u8, u8, u8) {
        match self {
            Self::Named(named) => named.to_rgb(),
            Self::Indexed(idx) => Self::indexed_to_rgb(*idx),
            Self::Rgb(r, g, b) => (*r, *g, *b),
            Self::Default => (255, 255, 255),
        }
    }

    /// Convert 256-color palette index to RGB
    const fn indexed_to_rgb(idx: u8) -> (u8, u8, u8) {
        match idx {
            0..=SYSTEM_COLOR_MAX => Self::system_color_from_index(idx).to_rgb(),
            COLOR_CUBE_BASE..=COLOR_CUBE_LAST => Self::color_cube_rgb(idx - COLOR_CUBE_BASE),
            GRAYSCALE_BASE..=u8::MAX => Self::grayscale_rgb(idx - GRAYSCALE_BASE),
        }
    }

    const fn system_color_from_index(idx: u8) -> NamedColor {
        match idx {
            1 => NamedColor::Red,
            2 => NamedColor::Green,
            3 => NamedColor::Yellow,
            4 => NamedColor::Blue,
            5 => NamedColor::Magenta,
            6 => NamedColor::Cyan,
            7 => NamedColor::White,
            8 => NamedColor::BrightBlack,
            9 => NamedColor::BrightRed,
            10 => NamedColor::BrightGreen,
            11 => NamedColor::BrightYellow,
            12 => NamedColor::BrightBlue,
            13 => NamedColor::BrightMagenta,
            14 => NamedColor::BrightCyan,
            15 => NamedColor::BrightWhite,
            _ => NamedColor::Black,
        }
    }

    const fn color_cube_rgb(offset: u8) -> (u8, u8, u8) {
        let red = (offset / (COLOR_CUBE_SIZE * COLOR_CUBE_SIZE)) * COLOR_CUBE_STEP;
        let green = ((offset / COLOR_CUBE_SIZE) % COLOR_CUBE_SIZE) * COLOR_CUBE_STEP;
        let blue = (offset % COLOR_CUBE_SIZE) * COLOR_CUBE_STEP;
        (red, green, blue)
    }

    const fn grayscale_rgb(offset: u8) -> (u8, u8, u8) {
        let value = offset * GRAYSCALE_STEP + GRAYSCALE_OFFSET;
        (value, value, value)
    }
}

impl NamedColor {
    /// Return the 16-color palette index used by terminal protocols and FFI.
    #[inline]
    #[must_use]
    pub const fn index(self) -> u8 {
        match self {
            Self::Black => 0,
            Self::Red => 1,
            Self::Green => 2,
            Self::Yellow => 3,
            Self::Blue => 4,
            Self::Magenta => 5,
            Self::Cyan => 6,
            Self::White => 7,
            Self::BrightBlack => 8,
            Self::BrightRed => 9,
            Self::BrightGreen => 10,
            Self::BrightYellow => 11,
            Self::BrightBlue => 12,
            Self::BrightMagenta => 13,
            Self::BrightCyan => 14,
            Self::BrightWhite => 15,
        }
    }

    /// Get RGB values for named color
    #[must_use]
    pub const fn to_rgb(&self) -> (u8, u8, u8) {
        match self {
            Self::Black => (0, 0, 0),
            Self::Red => (194, 54, 33),
            Self::Green => (37, 188, 36),
            Self::Yellow => (173, 173, 39),
            Self::Blue => (73, 46, 225),
            Self::Magenta => (211, 56, 211),
            Self::Cyan => (51, 187, 200),
            Self::White => (203, 204, 205),
            Self::BrightBlack => (128, 128, 128),
            Self::BrightRed => (255, 0, 0),
            Self::BrightGreen => (0, 255, 0),
            Self::BrightYellow => (255, 255, 0),
            Self::BrightBlue => (0, 0, 255),
            Self::BrightMagenta => (255, 0, 255),
            Self::BrightCyan => (0, 255, 255),
            Self::BrightWhite => (255, 255, 255),
        }
    }
}

#[cfg(test)]
#[path = "color/tests.rs"]
mod tests;
