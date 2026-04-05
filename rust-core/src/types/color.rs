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
/// `#[repr(u8)]` with explicit discriminants enables zero-cost `as u8` casts
/// for FFI color encoding, replacing a 16-arm match with a single instruction.
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

    #[test]
    fn test_color_default_is_default_variant() {
        assert_eq!(Color::default(), Color::Default);
        assert_eq!(Color::Default, Color::Default);
    }

    #[test]
    fn test_color_rgb_stores_components() {
        let c = Color::Rgb(10, 20, 30);
        assert_eq!(c, Color::Rgb(10, 20, 30));
        if let Color::Rgb(r, g, b) = c {
            assert_eq!(r, 10);
            assert_eq!(g, 20);
            assert_eq!(b, 30);
        } else {
            panic!("expected Color::Rgb");
        }
    }

    #[test]
    fn test_color_named_stores_variant() {
        let c = Color::Named(NamedColor::Red);
        assert_eq!(c, Color::Named(NamedColor::Red));
        assert_ne!(c, Color::Named(NamedColor::Blue));
    }

    #[test]
    fn test_color_indexed_stores_index() {
        let c = Color::Indexed(42);
        assert_eq!(c, Color::Indexed(42));
        assert_ne!(c, Color::Indexed(43));
    }

    #[test]
    fn test_color_rgb_white_roundtrip() {
        let white = Color::Rgb(255, 255, 255);
        assert_eq!(white.to_rgb(), (255, 255, 255));
    }

    #[test]
    fn test_color_rgb_black_roundtrip() {
        let black = Color::Rgb(0, 0, 0);
        assert_eq!(black.to_rgb(), (0, 0, 0));
    }

    #[test]
    fn test_color_named_black_vs_red_unequal() {
        // NamedColor::Black = 0, NamedColor::Red = 1
        assert_ne!(
            Color::Named(NamedColor::Black),
            Color::Named(NamedColor::Red)
        );
    }

    #[test]
    fn test_color_default_equals_itself() {
        let a = Color::Default;
        let b = Color::Default;
        assert_eq!(a, b);
    }

    // -------------------------------------------------------------------------
    // Merged from tests/unit/types/color.rs
    // -------------------------------------------------------------------------

    #[test]
    // MONOTONICITY: For grayscale ramp indices 232-254, the luminance value
    // (r == g == b) must strictly increase with the index.
    fn test_grayscale_monotone() {
        for i in 232u8..=254u8 {
            let (r_lo, _, _) = Color::Indexed(i).to_rgb();
            let (r_hi, _, _) = Color::Indexed(i + 1).to_rgb();
            assert!(
                r_lo < r_hi,
                "grayscale ramp must be strictly increasing: idx={i} gave r={r_lo}, idx={} gave r={r_hi}",
                i + 1
            );
        }
    }

    #[test]
    // DISTINCTNESS: Color::Default is NOT equal to Color::Rgb(0,0,0).
    fn test_default_is_distinct_from_rgb() {
        assert_ne!(
            Color::Default.to_rgb(),
            Color::Rgb(0, 0, 0).to_rgb(),
            "Color::Default (-> white) must differ from true black"
        );
        assert_eq!(
            Color::Default.to_rgb(),
            (255, 255, 255),
            "Color::Default.to_rgb() must return (255,255,255)"
        );
        assert_ne!(Color::Default, Color::Rgb(255, 255, 255));
    }

    #[test]
    // UNIQUENESS: All 16 NamedColor variants have distinct to_rgb() values.
    fn test_named_colors_have_unique_rgb_values() {
        use std::collections::HashSet;
        let all_named = [
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
        let rgb_values: HashSet<(u8, u8, u8)> = all_named.iter().map(NamedColor::to_rgb).collect();
        assert_eq!(
            rgb_values.len(),
            16,
            "all 16 named colors must produce distinct RGB triples"
        );
    }

    #[test]
    // SPOT-CHECK: Verify specific known RGB values for a sample of named colors.
    fn test_named_color_rgb_spot_checks() {
        assert_eq!(NamedColor::Black.to_rgb(), (0, 0, 0));
        assert_eq!(NamedColor::BrightRed.to_rgb(), (255, 0, 0));
        assert_eq!(NamedColor::BrightGreen.to_rgb(), (0, 255, 0));
        assert_eq!(NamedColor::BrightBlue.to_rgb(), (0, 0, 255));
        assert_eq!(NamedColor::BrightWhite.to_rgb(), (255, 255, 255));
    }

    #[test]
    // SPOT-CHECK: Grayscale boundary values.
    fn test_grayscale_boundary_values() {
        assert_eq!(Color::Indexed(232).to_rgb(), (8, 8, 8));
        assert_eq!(Color::Indexed(255).to_rgb(), (238, 238, 238));
    }

    #[test]
    // INVARIANT: Base named colors (Black..White) must have indices 0-7;
    // bright variants (BrightBlack..BrightWhite) must have indices 8-15.
    fn test_named_color_order() {
        assert_eq!(NamedColor::Black as u8, 0);
        assert_eq!(NamedColor::Red as u8, 1);
        assert_eq!(NamedColor::Green as u8, 2);
        assert_eq!(NamedColor::Yellow as u8, 3);
        assert_eq!(NamedColor::Blue as u8, 4);
        assert_eq!(NamedColor::Magenta as u8, 5);
        assert_eq!(NamedColor::Cyan as u8, 6);
        assert_eq!(NamedColor::White as u8, 7);
        assert_eq!(NamedColor::BrightBlack as u8, 8);
        assert_eq!(NamedColor::BrightRed as u8, 9);
        assert_eq!(NamedColor::BrightGreen as u8, 10);
        assert_eq!(NamedColor::BrightYellow as u8, 11);
        assert_eq!(NamedColor::BrightBlue as u8, 12);
        assert_eq!(NamedColor::BrightMagenta as u8, 13);
        assert_eq!(NamedColor::BrightCyan as u8, 14);
        assert_eq!(NamedColor::BrightWhite as u8, 15);
    }

    #[test]
    // EQUALITY: Color::Rgb(r,g,b) derives PartialEq.
    fn test_rgb_color_equality() {
        assert_eq!(Color::Rgb(10, 20, 30), Color::Rgb(10, 20, 30));
        assert_ne!(Color::Rgb(10, 20, 30), Color::Rgb(10, 20, 31));
        assert_ne!(Color::Rgb(10, 20, 30), Color::Rgb(10, 21, 30));
        assert_ne!(Color::Rgb(10, 20, 30), Color::Rgb(11, 20, 30));
    }

    #[test]
    // EQUALITY: Color::Indexed(n) derives PartialEq.
    fn test_color_indexed_equality() {
        assert_eq!(Color::Indexed(42), Color::Indexed(42));
        assert_ne!(Color::Indexed(42), Color::Indexed(43));
        assert_ne!(Color::Indexed(0), Color::Indexed(255));
    }

    #[test]
    // DISTINCTNESS: Color::Default, Color::Rgb, and Color::Indexed are distinct
    // enum variants.
    fn test_color_variants_not_equal_to_each_other() {
        assert_ne!(Color::Default, Color::Rgb(255, 255, 255));
        assert_ne!(Color::Default, Color::Indexed(0));
        assert_ne!(Color::Rgb(0, 0, 0), Color::Indexed(0));
        assert_ne!(Color::Rgb(203, 204, 205), Color::Indexed(7));
    }

    #[test]
    // FORMULA: The 6x6x6 cube red ramp.
    fn test_cube_red_ramp() {
        let cases: &[(u8, u8)] = &[
            (16, 0),
            (52, 51),
            (88, 102),
            (124, 153),
            (160, 204),
            (196, 255),
        ];
        for &(idx, expected_r) in cases {
            let (r, g, b) = Color::Indexed(idx).to_rgb();
            assert_eq!(r, expected_r, "idx={idx}: expected r={expected_r}");
            assert_eq!(g, 0, "idx={idx}: expected g=0");
            assert_eq!(b, 0, "idx={idx}: expected b=0");
        }
    }

    #[test]
    // FORMULA: The 6x6x6 cube green ramp.
    fn test_cube_green_ramp() {
        let cases: &[(u8, u8)] = &[
            (16, 0),
            (22, 51),
            (28, 102),
            (34, 153),
            (40, 204),
            (46, 255),
        ];
        for &(idx, expected_g) in cases {
            let (r, g, b) = Color::Indexed(idx).to_rgb();
            assert_eq!(r, 0, "idx={idx}: expected r=0");
            assert_eq!(g, expected_g, "idx={idx}: expected g={expected_g}");
            assert_eq!(b, 0, "idx={idx}: expected b=0");
        }
    }

    #[test]
    // INVARIANT: NamedColor::Black is standard terminal color 0.
    fn test_named_black_is_idx_0() {
        assert_eq!(NamedColor::Black as u8, 0);
        assert_eq!(NamedColor::Black.to_rgb(), (0, 0, 0));
        assert_eq!(Color::Indexed(0).to_rgb(), (0, 0, 0));
    }

    // PBT merged from tests/unit/types/color.rs
    proptest! {
        #![proptest_config(ProptestConfig::with_cases(1000))]

        #[test]
        // ROUNDTRIP: Color::Rgb(r,g,b).to_rgb() must return exactly (r,g,b)
        fn prop_rgb_identity(r in 0u8..=255u8, g in 0u8..=255u8, b in 0u8..=255u8) {
            prop_assert_eq!(Color::Rgb(r, g, b).to_rgb(), (r, g, b));
        }

        #[test]
        // INVARIANT: Color::Indexed(idx).to_rgb() never panics for any idx.
        fn prop_rgb_values_in_range(idx in 0u8..=255u8) {
            let color = Color::Indexed(idx);
            let _ = color.to_rgb();
        }

        #[test]
        // FORMULA: For indices 16-231 the colour cube formula must hold.
        fn prop_cube_formula(idx in 16u8..=231u8) {
            let (r, g, b) = Color::Indexed(idx).to_rgb();
            let n = idx - 16;
            let expected_r = (n / 36) * 51;
            let expected_g = ((n / 6) % 6) * 51;
            let expected_b = (n % 6) * 51;
            prop_assert_eq!(r, expected_r, "red component mismatch for idx={}", idx);
            prop_assert_eq!(g, expected_g, "green component mismatch for idx={}", idx);
            prop_assert_eq!(b, expected_b, "blue component mismatch for idx={}", idx);
        }
    }

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(256))]

        #[test]
        // INVARIANT: NamedColor as u8 must be consistent and in 0..=15.
        fn prop_named_to_indexed_consistent(idx in 0u8..=15u8) {
            let all_named = [
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
            let named = all_named[idx as usize];
            let raw = named as u8;
            prop_assert_eq!(raw, idx, "NamedColor at slot {} must cast to {}", idx, idx);
            prop_assert!(raw <= 15, "NamedColor index must be <= 15, got {}", raw);
        }

        #[test]
        // PANIC SAFETY: Color::Indexed(n).to_rgb() for indices 0-15 must never panic.
        fn prop_all_system_color_indices_have_rgb(idx in 0u8..=15u8) {
            let _ = Color::Indexed(idx).to_rgb();
        }
    }
}
