//! Property-based and example-based tests for `sgr` parsing.
//!
//! Module under test: `parser/sgr.rs`
//! Tier: T2 — `ProptestConfig::with_cases(500)`

use super::*;
use crate::types::cell::SgrFlags;

/// Generate a turn-on / turn-off pair for an SGR flag attribute.
///
/// Pattern:
/// 1. Send `$on_seq` — assert `term.current_attrs.flags.contains(SgrFlags::$flag)` is true.
/// 2. Send `$on_seq` then `$off_seq` — assert the flag is false.
///
/// Usage:
/// ```text
/// test_sgr_flag!(on_name, off_name, on_seq, off_seq, FLAG, off_msg)
/// ```
/// `FLAG` is a `SgrFlags` variant identifier (e.g. `BOLD`, `ITALIC`).
macro_rules! test_sgr_flag {
    (
        $on_name:ident,
        $off_name:ident,
        $on_seq:expr,
        $off_seq:expr,
        $flag:ident,
        $off_msg:expr
    ) => {
        #[test]
        fn $on_name() {
            let mut term = crate::TerminalCore::new(24, 80);
            term.advance($on_seq);
            assert!(term.current_attrs.flags.contains(SgrFlags::$flag));
        }

        #[test]
        fn $off_name() {
            let mut term = crate::TerminalCore::new(24, 80);
            term.advance($on_seq);
            assert!(term.current_attrs.flags.contains(SgrFlags::$flag));
            term.advance($off_seq);
            assert!(
                !term.current_attrs.flags.contains(SgrFlags::$flag),
                $off_msg
            );
        }
    };
}

// Bold: SGR 1 on / SGR 22 off
test_sgr_flag!(
    test_sgr_bold_on,
    test_sgr_bold_turn_off_code_22,
    b"\x1b[1m",
    b"\x1b[22m",
    BOLD,
    "Bold should be off after CSI 22m"
);

// Italic: SGR 3 on / SGR 23 off
test_sgr_flag!(
    test_sgr_italic_on,
    test_sgr_italic_turn_off_code_23,
    b"\x1b[3m",
    b"\x1b[23m",
    ITALIC,
    "Italic should be off after CSI 23m"
);

// Inverse: SGR 7 on / SGR 27 off
test_sgr_flag!(
    test_sgr_inverse_on,
    test_sgr_inverse_turn_off_code_27,
    b"\x1b[7m",
    b"\x1b[27m",
    INVERSE,
    "Inverse should be off after CSI 27m"
);

// Hidden: SGR 8 on / SGR 28 off
test_sgr_flag!(
    test_sgr_hidden_on,
    test_sgr_hidden_turn_off_code_28,
    b"\x1b[8m",
    b"\x1b[28m",
    HIDDEN,
    "Hidden should be off after CSI 28m"
);

// Strikethrough: SGR 9 on / SGR 29 off
test_sgr_flag!(
    test_sgr_strikethrough_on,
    test_sgr_strikethrough_turn_off_code_29,
    b"\x1b[9m",
    b"\x1b[29m",
    STRIKETHROUGH,
    "Strikethrough should be off after CSI 29m"
);

// Underline uses the underline() accessor rather than a plain flag,
// so it is written out explicitly (the macro covers flag-based attrs only).
#[test]
fn test_sgr_underline_on() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[4m");
    assert!(term.current_attrs.underline());
}

#[test]
fn test_sgr_underline_turn_off_code_24() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[4m"); // underline on
    assert!(term.current_attrs.underline());
    term.advance(b"\x1b[24m"); // turn off underline
    assert!(
        !term.current_attrs.underline(),
        "Underline should be off after CSI 24m"
    );
}

#[test]
fn test_sgr_reset() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.current_attrs.flags.insert(SgrFlags::BOLD);
    term.current_attrs.flags.insert(SgrFlags::ITALIC);

    let params = vte::Params::default();
    handle_sgr(&mut term, &params);

    assert!(!term.current_attrs.flags.contains(SgrFlags::BOLD));
    assert!(!term.current_attrs.flags.contains(SgrFlags::ITALIC));
}

#[test]
fn test_sgr_256_color_fg() {
    // Semicolon form: \e[38;5;196m — three separate param groups
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[38;5;196m");
    assert_eq!(
        term.current_attrs.foreground,
        crate::types::Color::Indexed(196)
    );
}

#[test]
fn test_sgr_256_color_bg() {
    // Semicolon form: \e[48;5;21m — three separate param groups
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[48;5;21m");
    assert_eq!(
        term.current_attrs.background,
        crate::types::Color::Indexed(21)
    );
}

#[test]
fn test_sgr_truecolor_fg() {
    // Semicolon form: \e[38;2;255;0;0m — five separate param groups
    // Note: avoid Rgb(0,0,0) as it collides with Color::Default in encode_color
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[38;2;255;0;0m");
    assert_eq!(
        term.current_attrs.foreground,
        crate::types::Color::Rgb(255, 0, 0)
    );
}

#[test]
fn test_sgr_truecolor_bg() {
    // Semicolon form: \e[48;2;0;128;255m — five separate param groups
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[48;2;0;128;255m");
    assert_eq!(
        term.current_attrs.background,
        crate::types::Color::Rgb(0, 128, 255)
    );
}

#[test]
fn test_sgr_compound_256_with_attrs() {
    // Compound sequence: bold + 256-color FG + underline in one CSI
    // \e[1;38;5;196;4m — groups: [1], [38], [5], [196], [4]
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[1;38;5;196;4m");
    assert!(
        term.current_attrs.flags.contains(SgrFlags::BOLD),
        "bold should be set"
    );
    assert!(term.current_attrs.underline(), "underline should be set");
    assert_eq!(
        term.current_attrs.foreground,
        crate::types::Color::Indexed(196)
    );
}

#[test]
fn test_sgr_named_colors_regression() {
    // Regression: named color params (30-37, 40-47) must still work after refactor
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[31m");
    assert_eq!(
        term.current_attrs.foreground,
        crate::types::Color::Named(crate::types::NamedColor::Red)
    );

    term.advance(b"\x1b[42m");
    assert_eq!(
        term.current_attrs.background,
        crate::types::Color::Named(crate::types::NamedColor::Green)
    );

    // Also verify bright variants (90-97, 100-107) after refactor
    term.advance(b"\x1b[91m");
    assert_eq!(
        term.current_attrs.foreground,
        crate::types::Color::Named(crate::types::NamedColor::BrightRed)
    );

    term.advance(b"\x1b[101m");
    assert_eq!(
        term.current_attrs.background,
        crate::types::Color::Named(crate::types::NamedColor::BrightRed)
    );
}

#[test]
fn test_sgr_256_color_colon_form() {
    // Colon form: \e[38:5:196m — all sub-params in one group [38, 5, 196]
    // This exercises the current_group.len() > 1 branch in parse_extended_color
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[38:5:196m");
    assert_eq!(
        term.current_attrs.foreground,
        crate::types::Color::Indexed(196)
    );
}

#[test]
fn test_sgr_truecolor_colon_form() {
    // Colon form: \e[38:2:255:0:128m — all sub-params in one group
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[38:2:255:0:128m");
    assert_eq!(
        term.current_attrs.foreground,
        crate::types::Color::Rgb(255, 0, 128)
    );
}

#[test]
fn test_sgr_256color_missing_index_unchanged() {
    // \x1b[38;5m — 256-color with no index value
    // The foreground should remain unchanged (Color::Default) because
    // parse_extended_color returns early when the index group is absent
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[38;5m");
    // Should not panic, foreground stays Default
    assert!(
        matches!(term.current_attrs.foreground, crate::types::Color::Default),
        "Foreground should remain Default when 256-color index is missing"
    );
}

#[test]
fn test_sgr_truecolor_partial_rgb_defaults_to_zero() {
    // \x1b[38;2;255m — truecolor with only R component, G and B missing
    // Missing components default to 0 (see parse_extended_color unwrap_or(0))
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[38;2;255m");
    // Should not panic; R=255, G=0, B=0 (missing = 0)
    assert_eq!(
        term.current_attrs.foreground,
        crate::types::Color::Rgb(255, 0, 0),
        "Partial truecolor should fill missing components with 0"
    );
}

#[test]
fn test_sgr_truecolor_overflow_truncates_to_u8() {
    // \x1b[38;2;300;300;300m — values exceed u8 range
    // Values are truncated by `as u8` cast (300u16 as u8 == 44)
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[38;2;300;300;300m");
    // Should not panic; values are silently truncated via as u8
    assert!(
        matches!(
            term.current_attrs.foreground,
            crate::types::Color::Rgb(_, _, _)
        ),
        "Overflow truecolor should still produce an Rgb color (truncated)"
    );
    assert_eq!(
        term.current_attrs.foreground,
        crate::types::Color::Rgb(44, 44, 44),
        "300u16 as u8 == 44; each component should truncate to 44"
    );
}

#[test]
fn test_sgr_empty_sequence_resets_all() {
    // \x1b[m — empty SGR sequence resets all attributes
    let mut term = crate::TerminalCore::new(24, 80);
    // First set some attributes
    term.advance(b"\x1b[1;3;4m"); // bold, italic, underline
    assert!(
        term.current_attrs.flags.contains(SgrFlags::BOLD),
        "bold should be set before reset"
    );
    assert!(
        term.current_attrs.flags.contains(SgrFlags::ITALIC),
        "italic should be set before reset"
    );
    assert!(
        term.current_attrs.underline(),
        "underline should be set before reset"
    );
    // Now reset with empty sequence
    term.advance(b"\x1b[m");
    // All attributes should be reset
    assert!(
        !term.current_attrs.flags.contains(SgrFlags::BOLD),
        "bold should be reset"
    );
    assert!(
        !term.current_attrs.flags.contains(SgrFlags::ITALIC),
        "italic should be reset"
    );
    assert!(!term.current_attrs.underline(), "underline should be reset");
}

#[test]
fn test_sgr_unknown_code_no_panic() {
    // Test that unknown/unsupported SGR codes don't cause panics
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[999m"); // Unknown code
    term.advance(b"\x1b[38;9m"); // Invalid extended color mode
                                 // Should complete without panic
}

// ── Additional SGR coverage ───────────────────────────────────────────────────

#[test]
fn test_sgr_dim_on_off() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[2m"); // dim on
    assert!(
        term.current_attrs.flags.contains(SgrFlags::DIM),
        "SGR 2 must set DIM"
    );
    term.advance(b"\x1b[22m"); // dim+bold off
    assert!(
        !term.current_attrs.flags.contains(SgrFlags::DIM),
        "SGR 22 must clear DIM"
    );
}

#[test]
fn test_sgr_bold_and_dim_both_cleared_by_22() {
    // SGR 22 must clear both BOLD and DIM simultaneously.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[1m"); // bold on
    term.advance(b"\x1b[2m"); // dim on
    assert!(term.current_attrs.flags.contains(SgrFlags::BOLD));
    assert!(term.current_attrs.flags.contains(SgrFlags::DIM));
    term.advance(b"\x1b[22m");
    assert!(
        !term.current_attrs.flags.contains(SgrFlags::BOLD),
        "SGR 22 must clear BOLD"
    );
    assert!(
        !term.current_attrs.flags.contains(SgrFlags::DIM),
        "SGR 22 must clear DIM"
    );
}

// Blink slow: SGR 5 on / SGR 25 off
test_sgr_flag!(
    test_sgr_blink_slow_set,
    test_sgr_blink_turn_off_code_25_clears_slow,
    b"\x1b[5m",
    b"\x1b[25m",
    BLINK_SLOW,
    "blink_slow should be off after CSI 25m"
);

// Blink fast: SGR 6 on / SGR 25 off
test_sgr_flag!(
    test_sgr_blink_fast_set,
    test_sgr_blink_turn_off_code_25_clears_fast,
    b"\x1b[6m",
    b"\x1b[25m",
    BLINK_FAST,
    "blink_fast should be off after CSI 25m"
);

#[test]
fn test_sgr_21_sets_double_underline() {
    // SGR 21 sets double underline directly (not via sub-param).
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[21m");
    assert_eq!(
        term.current_attrs.underline_style,
        crate::types::cell::UnderlineStyle::Double,
        "SGR 21 must set Double underline"
    );
}

#[test]
fn test_sgr_4_subparam_styles() {
    use crate::types::cell::UnderlineStyle;
    let mut term = crate::TerminalCore::new(24, 80);

    // 4:0 = no underline
    term.advance(b"\x1b[4:0m");
    assert_eq!(term.current_attrs.underline_style, UnderlineStyle::None);

    // 4:2 = double underline
    term.advance(b"\x1b[4:2m");
    assert_eq!(term.current_attrs.underline_style, UnderlineStyle::Double);

    // 4:3 = curly underline
    term.advance(b"\x1b[4:3m");
    assert_eq!(term.current_attrs.underline_style, UnderlineStyle::Curly);

    // 4:4 = dotted underline
    term.advance(b"\x1b[4:4m");
    assert_eq!(term.current_attrs.underline_style, UnderlineStyle::Dotted);

    // 4:5 = dashed underline
    term.advance(b"\x1b[4:5m");
    assert_eq!(term.current_attrs.underline_style, UnderlineStyle::Dashed);
}

#[test]
fn test_sgr_4_subparam_1_is_straight() {
    // 4:1 = straight underline (fallback arm in match)
    use crate::types::cell::UnderlineStyle;
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[4:1m");
    assert_eq!(term.current_attrs.underline_style, UnderlineStyle::Straight);
}

/// Apply a single SGR sequence and assert a color field equals the expected value.
///
/// Usage:
/// ```text
/// test_sgr_color_field!(name, seq b"...", field, expected)
/// ```
macro_rules! test_sgr_color_field {
    ($name:ident, seq $seq:expr, $field:ident, $expected:expr) => {
        #[test]
        fn $name() {
            let mut term = crate::TerminalCore::new(24, 80);
            term.advance($seq);
            assert_eq!(term.current_attrs.$field, $expected);
        }
    };
}

// SGR 58;2;r;g;b sets underline color (truecolor, semicolon form).
test_sgr_color_field!(
    test_sgr_underline_color_semicolon_form,
    seq b"\x1b[58;2;255;128;0m",
    underline_color,
    crate::types::Color::Rgb(255, 128, 0)
);

// SGR 58:2:r:g:b sets underline color (truecolor, colon form).
test_sgr_color_field!(
    test_sgr_underline_color_colon_form,
    seq b"\x1b[58:2:0:200:100m",
    underline_color,
    crate::types::Color::Rgb(0, 200, 100)
);

#[test]
fn test_sgr_59_resets_underline_color() {
    // SGR 59 resets underline color to Default.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[58;2;255;0;255m");
    assert_ne!(
        term.current_attrs.underline_color,
        crate::types::Color::Default
    );
    term.advance(b"\x1b[59m");
    assert_eq!(
        term.current_attrs.underline_color,
        crate::types::Color::Default,
        "SGR 59 must reset underline_color to Default"
    );
}

// SGR 58;5;n sets underline color to indexed palette entry.
test_sgr_color_field!(
    test_sgr_underline_color_indexed_semicolon,
    seq b"\x1b[58;5;200m",
    underline_color,
    crate::types::Color::Indexed(200)
);

// Background 256-color in colon form: \e[48:5:21m
test_sgr_color_field!(
    test_sgr_bg_256_colon_form,
    seq b"\x1b[48:5:21m",
    background,
    crate::types::Color::Indexed(21)
);

// Background truecolor in colon form: \e[48:2:10:20:30m
test_sgr_color_field!(
    test_sgr_bg_truecolor_colon_form,
    seq b"\x1b[48:2:10:20:30m",
    background,
    crate::types::Color::Rgb(10, 20, 30)
);

#[test]
fn test_sgr_compound_reset_in_sequence() {
    // SGR 0 mid-sequence resets everything accumulated before it.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[1;3;0;31m"); // bold, italic, RESET, then red fg
                                     // After reset, only red fg should remain.
    assert!(
        !term.current_attrs.flags.contains(SgrFlags::BOLD),
        "bold must be cleared by mid-sequence SGR 0"
    );
    assert!(
        !term.current_attrs.flags.contains(SgrFlags::ITALIC),
        "italic must be cleared by mid-sequence SGR 0"
    );
    assert_eq!(
        term.current_attrs.foreground,
        crate::types::Color::Named(crate::types::NamedColor::Red),
        "red foreground applied after SGR 0 must persist"
    );
}

/// All 8 bright `NamedColor` variants in SGR order (BrightBlack … BrightWhite).
const BRIGHT_COLORS: [crate::types::NamedColor; 8] = [
    crate::types::NamedColor::BrightBlack,
    crate::types::NamedColor::BrightRed,
    crate::types::NamedColor::BrightGreen,
    crate::types::NamedColor::BrightYellow,
    crate::types::NamedColor::BrightBlue,
    crate::types::NamedColor::BrightMagenta,
    crate::types::NamedColor::BrightCyan,
    crate::types::NamedColor::BrightWhite,
];

/// Verify all 8 bright foreground or background SGR codes in one loop.
///
/// Usage:
/// ```text
/// test_sgr_all_bright_variants!(name, base BASE, field)
/// ```
/// `BASE` is 90 for foreground (90–97) or 100 for background (100–107).
macro_rules! test_sgr_all_bright_variants {
    ($name:ident, base $base:expr, $field:ident) => {
        #[test]
        fn $name() {
            let mut term = crate::TerminalCore::new(24, 80);
            for (i, expected) in BRIGHT_COLORS.iter().enumerate() {
                let code = $base + i as u8;
                term.advance(format!("\x1b[{}m", code).as_bytes());
                assert_eq!(
                    term.current_attrs.$field,
                    crate::types::Color::Named(*expected),
                    "SGR code {}",
                    code
                );
            }
        }
    };
}

// Verify all 8 bright foreground colors (90-97) map to the correct NamedColor.
test_sgr_all_bright_variants!(test_sgr_all_bright_fg_variants, base 90, foreground);

// Verify all 8 bright background colors (100-107) map to the correct NamedColor.
test_sgr_all_bright_variants!(test_sgr_all_bright_bg_variants, base 100, background);

include!("sgr_color.rs");
