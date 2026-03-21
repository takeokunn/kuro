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
            0..=15 => {
                // Standard colors
                let named = match idx {
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
mod tests {
    use super::*;
    use proptest::prelude::*;

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

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(256))]
        #[test]
        // INVARIANT: Color::Indexed(n).to_rgb() never panics for any n in 0..=255
        // and always returns a valid (r, g, b) triple (complete 256-color table)
        fn prop_indexed_to_rgb_complete(idx in 0u8..=255u8) {
            let color = Color::Indexed(idx);
            let (r, g, b) = color.to_rgb();
            // Values are always valid u8 — this documents the guarantee
            let _ = (r, g, b);
        }
    }

    // Verify the three color regions explicitly
    #[test]
    fn test_indexed_system_colors_0_to_15() {
        // System colors 0-15 have defined mappings
        for idx in 0u8..=15u8 {
            let color = Color::Indexed(idx);
            // Must not panic — every index has a defined mapping
            let (r, g, b) = color.to_rgb();
            let _ = (r, g, b);
        }
    }

    #[test]
    fn test_indexed_6x6x6_cube_16_to_231() {
        // 6x6x6 color cube: formula is v = idx-16, r=v/36, g=(v%36)/6, b=v%6, each * 51
        for idx in 16u8..=231u8 {
            let color = Color::Indexed(idx);
            let (r, g, b) = color.to_rgb();
            let _ = (r, g, b);
        }
        // Verify max value: idx=231 => n=215, r=5*51=255, g=5*51=255, b=5*51=255
        let (r, g, b) = Color::Indexed(231).to_rgb();
        assert_eq!(r, 255);
        assert_eq!(g, 255);
        assert_eq!(b, 255);
    }

    #[test]
    fn test_indexed_grayscale_232_to_255() {
        // Grayscale: v = (idx-232)*10 + 8
        for idx in 232u8..=255u8 {
            let color = Color::Indexed(idx);
            let (r, g, b) = color.to_rgb();
            let _ = (r, g, b);
        }
        // Verify: idx=232 => (0)*10+8=8, idx=255 => (23)*10+8=238
        let (r232, _, _) = Color::Indexed(232).to_rgb();
        assert_eq!(r232, 8);
        let (r255, _, _) = Color::Indexed(255).to_rgb();
        assert_eq!(r255, 238);
    }
}
