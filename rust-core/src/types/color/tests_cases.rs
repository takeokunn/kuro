use std::collections::HashSet;

use crate::types::color::NamedColor;
use crate::Color;
use proptest::prelude::*;

use super::tests_support::*;

#[test]
fn test_named_to_rgb() {
    assert_eq!(NamedColor::Black.to_rgb(), (0, 0, 0));
    assert_eq!(NamedColor::White.to_rgb(), (203, 204, 205));
    assert_eq!(NamedColor::Red.to_rgb(), (194, 54, 33));
}

#[test]
fn test_indexed_to_rgb() {
    assert_eq!(Color::Indexed(0).to_rgb(), (0, 0, 0));
    assert_eq!(Color::Indexed(7).to_rgb(), (203, 204, 205));
    assert_eq!(Color::Indexed(16).to_rgb(), (0, 0, 0));
    assert_eq!(Color::Indexed(17).to_rgb(), (0, 0, 51));
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
    fn prop_indexed_to_rgb_complete(idx in 0u8..=255u8) {
        let color = Color::Indexed(idx);
        let (r, g, b) = color.to_rgb();
        let _ = (r, g, b);
    }
}

#[test]
fn test_indexed_system_colors_0_to_15() {
    for idx in 0u8..=15u8 {
        let color = Color::Indexed(idx);
        let (r, g, b) = color.to_rgb();
        let _ = (r, g, b);
    }
}

#[test]
fn test_indexed_6x6x6_cube_16_to_231() {
    for idx in 16u8..=231u8 {
        let color = Color::Indexed(idx);
        let (r, g, b) = color.to_rgb();
        let _ = (r, g, b);
    }

    let (r, g, b) = Color::Indexed(231).to_rgb();
    assert_eq!(r, 255);
    assert_eq!(g, 255);
    assert_eq!(b, 255);
}

#[test]
fn test_indexed_grayscale_232_to_255() {
    for idx in 232u8..=255u8 {
        let color = Color::Indexed(idx);
        let (r, g, b) = color.to_rgb();
        let _ = (r, g, b);
    }

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

#[test]
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
fn test_default_is_distinct_from_rgb() {
    assert_ne!(
        default_rgb(),
        Color::Rgb(0, 0, 0).to_rgb(),
        "Color::Default (-> white) must differ from true black"
    );
    assert_eq!(
        default_rgb(),
        (255, 255, 255),
        "Color::Default.to_rgb() must return (255,255,255)"
    );
    assert_ne!(Color::Default, Color::Rgb(255, 255, 255));
}

#[test]
fn test_named_colors_have_unique_rgb_values() {
    let rgb_values: HashSet<(u8, u8, u8)> = all_named_color_rgb_values().collect();
    assert_eq!(
        rgb_values.len(),
        16,
        "all 16 named colors must produce distinct RGB triples"
    );
}

#[test]
fn test_named_color_rgb_spot_checks() {
    assert_eq!(NamedColor::Black.to_rgb(), (0, 0, 0));
    assert_eq!(NamedColor::BrightRed.to_rgb(), (255, 0, 0));
    assert_eq!(NamedColor::BrightGreen.to_rgb(), (0, 255, 0));
    assert_eq!(NamedColor::BrightBlue.to_rgb(), (0, 0, 255));
    assert_eq!(NamedColor::BrightWhite.to_rgb(), (255, 255, 255));
}

#[test]
fn test_grayscale_boundary_values() {
    assert_eq!(Color::Indexed(232).to_rgb(), (8, 8, 8));
    assert_eq!(Color::Indexed(255).to_rgb(), (238, 238, 238));
}

#[test]
fn test_named_color_index() {
    assert_eq!(NamedColor::Black.index(), 0);
    assert_eq!(NamedColor::Red.index(), 1);
    assert_eq!(NamedColor::Green.index(), 2);
    assert_eq!(NamedColor::Yellow.index(), 3);
    assert_eq!(NamedColor::Blue.index(), 4);
    assert_eq!(NamedColor::Magenta.index(), 5);
    assert_eq!(NamedColor::Cyan.index(), 6);
    assert_eq!(NamedColor::White.index(), 7);
    assert_eq!(NamedColor::BrightBlack.index(), 8);
    assert_eq!(NamedColor::BrightRed.index(), 9);
    assert_eq!(NamedColor::BrightGreen.index(), 10);
    assert_eq!(NamedColor::BrightYellow.index(), 11);
    assert_eq!(NamedColor::BrightBlue.index(), 12);
    assert_eq!(NamedColor::BrightMagenta.index(), 13);
    assert_eq!(NamedColor::BrightCyan.index(), 14);
    assert_eq!(NamedColor::BrightWhite.index(), 15);
}

#[test]
fn test_rgb_color_equality() {
    assert_eq!(Color::Rgb(10, 20, 30), Color::Rgb(10, 20, 30));
    assert_ne!(Color::Rgb(10, 20, 30), Color::Rgb(10, 20, 31));
    assert_ne!(Color::Rgb(10, 20, 30), Color::Rgb(10, 21, 30));
    assert_ne!(Color::Rgb(10, 20, 30), Color::Rgb(11, 20, 30));
}

#[test]
fn test_color_indexed_equality() {
    assert_eq!(Color::Indexed(42), Color::Indexed(42));
    assert_ne!(Color::Indexed(42), Color::Indexed(43));
    assert_ne!(Color::Indexed(0), Color::Indexed(255));
}

#[test]
fn test_color_variants_not_equal_to_each_other() {
    assert_ne!(Color::Default, Color::Rgb(255, 255, 255));
    assert_ne!(Color::Default, Color::Indexed(0));
    assert_ne!(Color::Rgb(0, 0, 0), Color::Indexed(0));
    assert_ne!(Color::Rgb(203, 204, 205), Color::Indexed(7));
}

#[test]
fn test_cube_red_ramp() {
    for &(idx, expected_r) in CUBE_RED_CASES {
        let (r, g, b) = Color::Indexed(idx).to_rgb();
        assert_eq!(r, expected_r, "idx={idx}: expected r={expected_r}");
        assert_eq!(g, 0, "idx={idx}: expected g=0");
        assert_eq!(b, 0, "idx={idx}: expected b=0");
    }
}

#[test]
fn test_cube_green_ramp() {
    for &(idx, expected_g) in CUBE_GREEN_CASES {
        let (r, g, b) = Color::Indexed(idx).to_rgb();
        assert_eq!(r, 0, "idx={idx}: expected r=0");
        assert_eq!(g, expected_g, "idx={idx}: expected g={expected_g}");
        assert_eq!(b, 0, "idx={idx}: expected b=0");
    }
}

#[test]
fn test_named_black_is_idx_0() {
    assert_eq!(NamedColor::Black.index(), 0);
    assert_eq!(NamedColor::Black.to_rgb(), (0, 0, 0));
    assert_eq!(Color::Indexed(0).to_rgb(), (0, 0, 0));
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(1000))]

    #[test]
    fn prop_rgb_identity(r in 0u8..=255u8, g in 0u8..=255u8, b in 0u8..=255u8) {
        prop_assert_eq!(Color::Rgb(r, g, b).to_rgb(), (r, g, b));
    }

    #[test]
    fn prop_rgb_values_in_range(idx in 0u8..=255u8) {
        let color = Color::Indexed(idx);
        let _ = color.to_rgb();
    }

    #[test]
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
    fn prop_named_to_indexed_consistent(idx in 0u8..=15u8) {
        let named = ALL_NAMED_COLORS[usize::from(idx)];
        let raw = named.index();
        prop_assert_eq!(raw, idx, "NamedColor at slot {} must index to {}", idx, idx);
        prop_assert!(raw <= 15, "NamedColor index must be <= 15, got {}", raw);
    }

    #[test]
    fn prop_all_system_color_indices_have_rgb(idx in 0u8..=15u8) {
        let _ = Color::Indexed(idx).to_rgb();
    }
}
