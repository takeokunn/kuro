//! Color representations and conversions

use serde::{Deserialize, Serialize};

/// Named ANSI colors (standard 16-color palette)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum NamedColor {
    /// Black color (index 0)
    Black,
    /// Red color (index 1)
    Red,
    /// Green color (index 2)
    Green,
    /// Yellow color (index 3)
    Yellow,
    /// Blue color (index 4)
    Blue,
    /// Magenta color (index 5)
    Magenta,
    /// Cyan color (index 6)
    Cyan,
    /// White color (index 7)
    White,
    /// Bright black color (index 8)
    BrightBlack,
    /// Bright red color (index 9)
    BrightRed,
    /// Bright green color (index 10)
    BrightGreen,
    /// Bright yellow color (index 11)
    BrightYellow,
    /// Bright blue color (index 12)
    BrightBlue,
    /// Bright magenta color (index 13)
    BrightMagenta,
    /// Bright cyan color (index 14)
    BrightCyan,
    /// Bright white color (index 15)
    BrightWhite,
}

/// Terminal color representation
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
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
    pub fn to_rgb(&self) -> (u8, u8, u8) {
        match self {
            Color::Named(named) => named.to_rgb(),
            Color::Indexed(idx) => Self::indexed_to_rgb(*idx),
            Color::Rgb(r, g, b) => (*r, *g, *b),
            Color::Default => (255, 255, 255),
        }
    }

    /// Convert 256-color palette index to RGB
    fn indexed_to_rgb(idx: u8) -> (u8, u8, u8) {
        match idx {
            0..=15 => {
                // Standard colors
                let named = match idx {
                    0 => NamedColor::Black,
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
                };
                named.to_rgb()
            }
            16..=231 => {
                // 6x6x6 color cube
                let n = idx - 16;
                let r = (n / 36) * 51;
                let g = ((n / 6) % 6) * 51;
                let b = (n % 6) * 51;
                (r, g, b)
            }
            232..=255 => {
                // Grayscale ramp
                let n = idx - 232;
                let v = n * 10 + 8;
                (v, v, v)
            }
        }
    }
}

impl NamedColor {
    /// Get RGB values for named color
    pub fn to_rgb(&self) -> (u8, u8, u8) {
        match self {
            NamedColor::Black => (0, 0, 0),
            NamedColor::Red => (194, 54, 33),
            NamedColor::Green => (37, 188, 36),
            NamedColor::Yellow => (173, 173, 39),
            NamedColor::Blue => (73, 46, 225),
            NamedColor::Magenta => (211, 56, 211),
            NamedColor::Cyan => (51, 187, 200),
            NamedColor::White => (203, 204, 205),
            NamedColor::BrightBlack => (128, 128, 128),
            NamedColor::BrightRed => (255, 0, 0),
            NamedColor::BrightGreen => (0, 255, 0),
            NamedColor::BrightYellow => (255, 255, 0),
            NamedColor::BrightBlue => (0, 0, 255),
            NamedColor::BrightMagenta => (255, 0, 255),
            NamedColor::BrightCyan => (0, 255, 255),
            NamedColor::BrightWhite => (255, 255, 255),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_named_to_rgb() {
        assert_eq!(NamedColor::Black.to_rgb(), (0, 0, 0));
        assert_eq!(NamedColor::White.to_rgb(), (203, 204, 205));
        assert_eq!(NamedColor::Red.to_rgb(), (194, 54, 33));
    }

    #[test]
    fn test_indexed_to_rgb() {
        // Test standard colors
        assert_eq!(Color::Indexed(0).to_rgb(), (0, 0, 0));
        assert_eq!(Color::Indexed(7).to_rgb(), (203, 204, 205));

        // Test color cube
        assert_eq!(Color::Indexed(16).to_rgb(), (0, 0, 0));
        assert_eq!(Color::Indexed(17).to_rgb(), (0, 0, 51));

        // Test grayscale
        assert_eq!(Color::Indexed(232).to_rgb(), (8, 8, 8));
        assert_eq!(Color::Indexed(255).to_rgb(), (238, 238, 238));
    }

    #[test]
    fn test_rgb_roundtrip() {
        assert_eq!(Color::Rgb(255, 128, 0).to_rgb(), (255, 128, 0));
    }

    #[test]
    fn test_color_default() {
        assert_eq!(Color::default(), Color::Default);
    }
}
