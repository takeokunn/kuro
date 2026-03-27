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
    let rgb_values: HashSet<(u8, u8, u8)> = all_named
        .iter()
        .map(crate::types::color::NamedColor::to_rgb)
        .collect();
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

// -------------------------------------------------------------------------
// New tests (Round 34B)
// -------------------------------------------------------------------------

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    // INVARIANT: `NamedColor as u8` (via repr(u8)) must be consistent and
    // lie in the 0..=15 range for all 16 variants.  This mirrors the SGR
    // processing that casts NamedColor directly to a palette index.
    fn prop_named_to_indexed_consistent(idx in 0u8..=15u8) {
        // Reconstruct a NamedColor from its known discriminant and verify
        // the cast round-trips correctly.
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
    // PANIC SAFETY: Color::Indexed(n).to_rgb() for indices 0-15 must never
    // panic.  Documented explicitly as a guarantee for the system-color region.
    fn prop_all_system_color_indices_have_rgb(idx in 0u8..=15u8) {
        // No panic is the only invariant — the exact RGB values are
        // verified by example tests.
        let _ = Color::Indexed(idx).to_rgb();
    }
}

#[test]
// INVARIANT: Base named colors (Black..White) must have indices 0-7;
// bright variants (BrightBlack..BrightWhite) must have indices 8-15.
// Verified via repr(u8) cast.
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
// EQUALITY: Color::Rgb(r,g,b) derives PartialEq — same components must
// compare equal; differing components must compare not-equal.
fn test_rgb_color_equality() {
    assert_eq!(Color::Rgb(10, 20, 30), Color::Rgb(10, 20, 30));
    assert_ne!(Color::Rgb(10, 20, 30), Color::Rgb(10, 20, 31));
    assert_ne!(Color::Rgb(10, 20, 30), Color::Rgb(10, 21, 30));
    assert_ne!(Color::Rgb(10, 20, 30), Color::Rgb(11, 20, 30));
}

#[test]
// EQUALITY: Color::Indexed(n) derives PartialEq — same index equals itself;
// different indices are not equal.
fn test_color_indexed_equality() {
    assert_eq!(Color::Indexed(42), Color::Indexed(42));
    assert_ne!(Color::Indexed(42), Color::Indexed(43));
    assert_ne!(Color::Indexed(0), Color::Indexed(255));
}

#[test]
// DISTINCTNESS: Color::Default, Color::Rgb, and Color::Indexed are distinct
// enum variants and must not compare equal to each other, even when
// to_rgb() might return identical values.
fn test_color_variants_not_equal_to_each_other() {
    // Default vs Rgb: both to_rgb() → (255,255,255) but variants differ
    assert_ne!(Color::Default, Color::Rgb(255, 255, 255));
    // Default vs Indexed
    assert_ne!(Color::Default, Color::Indexed(0));
    // Rgb vs Indexed
    assert_ne!(Color::Rgb(0, 0, 0), Color::Indexed(0));
    assert_ne!(Color::Rgb(203, 204, 205), Color::Indexed(7));
}

#[test]
// FORMULA: The 6x6x6 cube red ramp.  Indices 16,52,88,124,160,196 fix
// g=b=0 and step r through 0,51,102,153,204,255 (multiples of 51).
// n = idx-16; r = (n/36)*51.  For these indices n = 0,36,72,108,144,180
// so r/51 = 0,1,2,3,4,5.
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
// FORMULA: The 6x6x6 cube green ramp.  Indices 16,22,28,34,40,46 fix
// r=b=0 and step g through 0,51,102,153,204,255.
// n = idx-16; g = ((n/6)%6)*51.  For these indices n=0,6,12,18,24,30
// so (n/6)%6 = 0,1,2,3,4,5.
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
// INVARIANT: NamedColor::Black is standard terminal color 0 — its repr(u8)
// discriminant is 0, its to_rgb() returns (0,0,0), and Color::Indexed(0)
// maps to the same RGB triple.
fn test_named_black_is_idx_0() {
    assert_eq!(NamedColor::Black as u8, 0);
    assert_eq!(NamedColor::Black.to_rgb(), (0, 0, 0));
    // Color::Indexed(0) resolves via the system-color branch to Black
    assert_eq!(Color::Indexed(0).to_rgb(), (0, 0, 0));
}
