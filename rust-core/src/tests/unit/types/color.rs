//! Property-based tests for `crate::types::color` (Color, `NamedColor`)
//!
//! Tests in this file complement the embedded `#[cfg(test)]` tests in
//! `src/types/color.rs` and add property-based coverage for mathematical
//! invariants and boundary conditions.

use crate::types::color::{Color, NamedColor};
use proptest::prelude::*;

// -------------------------------------------------------------------------
// Property-based tests
// -------------------------------------------------------------------------

proptest! {
    #![proptest_config(ProptestConfig::with_cases(1000))]

    #[test]
    // ROUNDTRIP: Color::Rgb(r,g,b).to_rgb() must return exactly (r,g,b)
    // for all 8-bit component values.
    fn prop_rgb_identity(r in 0u8..=255u8, g in 0u8..=255u8, b in 0u8..=255u8) {
        prop_assert_eq!(Color::Rgb(r, g, b).to_rgb(), (r, g, b));
    }

    #[test]
    // INVARIANT: For any Color variant, all three components returned by
    // to_rgb() are valid u8 values (≤ 255).  This is automatically true for
    // u8 but documents the guarantee explicitly for indexed/named paths.
    fn prop_rgb_values_in_range(idx in 0u8..=255u8) {
        let color = Color::Indexed(idx);
        // Components are u8, so ≤ 255 is always true — the real invariant
        // is "no panic for every index value".
        let _ = color.to_rgb();
    }

    #[test]
    // FORMULA: For indices 16–231 the colour cube formula must hold.
    // n = idx - 16; r = (n/36)*51; g = ((n/6)%6)*51; b = (n%6)*51
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

// -------------------------------------------------------------------------
// Example-based tests (where proptest is awkward or PBT already exists)
// -------------------------------------------------------------------------

#[test]
// MONOTONICITY: For grayscale ramp indices 232–254, the luminance value
// (r == g == b) must strictly increase with the index.
// Uses an example-based loop because the range is tiny and exhaustive.
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
// DISTINCTNESS: Color::Default.to_rgb() returns (255,255,255) which is the
// same as BrightWhite; however Color::Default must be a distinct *variant*
// from Color::Rgb(255,255,255) even though their to_rgb() value coincides.
// More importantly: Color::Default is NOT equal to Color::Rgb(0,0,0).
fn test_default_is_distinct_from_rgb() {
    // to_rgb() values: Default → (255,255,255), Rgb(0,0,0) → (0,0,0)
    assert_ne!(
        Color::Default.to_rgb(),
        Color::Rgb(0, 0, 0).to_rgb(),
        "Color::Default (→ white) must differ from true black"
    );
    // Confirm the sentinel value documented in color.rs
    assert_eq!(
        Color::Default.to_rgb(),
        (255, 255, 255),
        "Color::Default.to_rgb() must return (255,255,255)"
    );
    // Variant identity: the enum values themselves are not equal
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
    let rgb_values: HashSet<(u8, u8, u8)> = all_named.iter().map(crate::types::color::NamedColor::to_rgb).collect();
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
// SPOT-CHECK: Grayscale boundary values must match the documented formula
// v = (idx - 232) * 10 + 8.  idx=232 → 8; idx=255 → 238.
fn test_grayscale_boundary_values() {
    assert_eq!(Color::Indexed(232).to_rgb(), (8, 8, 8));
    assert_eq!(Color::Indexed(255).to_rgb(), (238, 238, 238));
}
