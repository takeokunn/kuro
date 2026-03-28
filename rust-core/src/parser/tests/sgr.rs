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

#[test]
fn test_sgr_blink_slow_set() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[5m");
    assert!(
        term.current_attrs.flags.contains(SgrFlags::BLINK_SLOW),
        "SGR 5 must set BLINK_SLOW"
    );
}

#[test]
fn test_sgr_blink_fast_set() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[6m");
    assert!(
        term.current_attrs.flags.contains(SgrFlags::BLINK_FAST),
        "SGR 6 must set BLINK_FAST"
    );
}

#[test]
fn test_sgr_blink_turn_off_code_25_clears_slow() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[5m"); // blink_slow on
    assert!(term.current_attrs.flags.contains(SgrFlags::BLINK_SLOW));
    term.advance(b"\x1b[25m"); // turn off blink (both slow and fast)
    assert!(
        !term.current_attrs.flags.contains(SgrFlags::BLINK_SLOW),
        "blink_slow should be off after CSI 25m"
    );
}

#[test]
fn test_sgr_blink_turn_off_code_25_clears_fast() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[6m"); // blink_fast on
    assert!(term.current_attrs.flags.contains(SgrFlags::BLINK_FAST));
    term.advance(b"\x1b[25m"); // turn off blink (both slow and fast)
    assert!(
        !term.current_attrs.flags.contains(SgrFlags::BLINK_FAST),
        "blink_fast should be off after CSI 25m"
    );
}

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

#[test]
fn test_sgr_39_resets_foreground() {
    // SGR 39 explicitly resets the foreground to Default.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[31m"); // red fg
    assert_ne!(term.current_attrs.foreground, crate::types::Color::Default);
    term.advance(b"\x1b[39m");
    assert_eq!(
        term.current_attrs.foreground,
        crate::types::Color::Default,
        "SGR 39 must reset foreground to Default"
    );
}

#[test]
fn test_sgr_49_resets_background() {
    // SGR 49 explicitly resets the background to Default.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[41m"); // red bg
    assert_ne!(term.current_attrs.background, crate::types::Color::Default);
    term.advance(b"\x1b[49m");
    assert_eq!(
        term.current_attrs.background,
        crate::types::Color::Default,
        "SGR 49 must reset background to Default"
    );
}

#[test]
fn test_sgr_underline_color_semicolon_form() {
    // SGR 58;2;r;g;b sets underline color (truecolor, semicolon form).
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[58;2;255;128;0m");
    assert_eq!(
        term.current_attrs.underline_color,
        crate::types::Color::Rgb(255, 128, 0),
        "SGR 58;2;r;g;b must set underline_color to Rgb"
    );
}

#[test]
fn test_sgr_underline_color_colon_form() {
    // SGR 58:2:r:g:b sets underline color (truecolor, colon form).
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[58:2:0:200:100m");
    assert_eq!(
        term.current_attrs.underline_color,
        crate::types::Color::Rgb(0, 200, 100),
        "SGR 58:2:r:g:b (colon form) must set underline_color"
    );
}

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

#[test]
fn test_sgr_underline_color_indexed_semicolon() {
    // SGR 58;5;n sets underline color to indexed palette entry.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[58;5;200m");
    assert_eq!(
        term.current_attrs.underline_color,
        crate::types::Color::Indexed(200),
        "SGR 58;5;n must set underline_color to Indexed(n)"
    );
}

#[test]
fn test_sgr_bg_256_colon_form() {
    // Background 256-color in colon form: \e[48:5:21m
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[48:5:21m");
    assert_eq!(
        term.current_attrs.background,
        crate::types::Color::Indexed(21),
        "SGR 48:5:n (colon form) must set background to Indexed(n)"
    );
}

#[test]
fn test_sgr_bg_truecolor_colon_form() {
    // Background truecolor in colon form: \e[48:2:10:20:30m
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[48:2:10:20:30m");
    assert_eq!(
        term.current_attrs.background,
        crate::types::Color::Rgb(10, 20, 30),
        "SGR 48:2:r:g:b (colon form) must set background to Rgb"
    );
}

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

#[test]
fn test_sgr_all_bright_fg_variants() {
    // Verify all 8 bright foreground colors (90-97) map to the correct NamedColor.
    use crate::types::NamedColor;
    let expected = [
        NamedColor::BrightBlack,
        NamedColor::BrightRed,
        NamedColor::BrightGreen,
        NamedColor::BrightYellow,
        NamedColor::BrightBlue,
        NamedColor::BrightMagenta,
        NamedColor::BrightCyan,
        NamedColor::BrightWhite,
    ];
    for (offset, &color) in expected.iter().enumerate() {
        let mut term = crate::TerminalCore::new(24, 80);
        let seq = format!("\x1b[{}m", 90 + offset);
        term.advance(seq.as_bytes());
        assert_eq!(
            term.current_attrs.foreground,
            crate::types::Color::Named(color),
            "SGR {} must set BrightFg[{}]",
            90 + offset,
            offset
        );
    }
}

#[test]
fn test_sgr_all_bright_bg_variants() {
    // Verify all 8 bright background colors (100-107) map to the correct NamedColor.
    use crate::types::NamedColor;
    let expected = [
        NamedColor::BrightBlack,
        NamedColor::BrightRed,
        NamedColor::BrightGreen,
        NamedColor::BrightYellow,
        NamedColor::BrightBlue,
        NamedColor::BrightMagenta,
        NamedColor::BrightCyan,
        NamedColor::BrightWhite,
    ];
    for (offset, &color) in expected.iter().enumerate() {
        let mut term = crate::TerminalCore::new(24, 80);
        let seq = format!("\x1b[{}m", 100 + offset);
        term.advance(seq.as_bytes());
        assert_eq!(
            term.current_attrs.background,
            crate::types::Color::Named(color),
            "SGR {} must set BrightBg[{}]",
            100 + offset,
            offset
        );
    }
}

// ── Macro: test_sgr_color_default_reset ──────────────────────────────────────
//
// Generates a test that sets a named color then verifies the explicit-reset
// SGR code restores it to `Color::Default`.
//
// Usage:
// ```text
// test_sgr_color_default_reset!(test_name, set_seq, reset_seq, field, field_label)
// ```
// `field` is either `foreground` or `background`.
macro_rules! test_sgr_color_default_reset {
    (
        $name:ident,
        $set_seq:expr,
        $reset_seq:expr,
        $field:ident,
        $field_label:expr
    ) => {
        #[test]
        fn $name() {
            let mut term = crate::TerminalCore::new(24, 80);
            term.advance($set_seq);
            assert_ne!(
                term.current_attrs.$field,
                crate::types::Color::Default,
                concat!($field_label, " must be non-Default after set sequence")
            );
            term.advance($reset_seq);
            assert_eq!(
                term.current_attrs.$field,
                crate::types::Color::Default,
                concat!($field_label, " must be Default after explicit reset SGR")
            );
        }
    };
}

// SGR 39 resets foreground; SGR 49 resets background — two flavours, one macro.
test_sgr_color_default_reset!(
    test_sgr_39_resets_foreground_macro,
    b"\x1b[32m",
    b"\x1b[39m",
    foreground,
    "foreground"
);
test_sgr_color_default_reset!(
    test_sgr_49_resets_background_macro,
    b"\x1b[42m",
    b"\x1b[49m",
    background,
    "background"
);

// ── Macro: test_sgr_indexed_color_pair ───────────────────────────────────────
//
// Generates fg + bg tests for a 256-color indexed sequence (semicolon form).
//
// Usage:
// ```text
// test_sgr_indexed_color_pair!(fg_name, bg_name, idx)
// ```
macro_rules! test_sgr_indexed_color_pair {
    ($fg_name:ident, $bg_name:ident, $idx:literal) => {
        #[test]
        fn $fg_name() {
            let mut term = crate::TerminalCore::new(24, 80);
            term.advance(concat!("\x1b[38;5;", stringify!($idx), "m").as_bytes());
            assert_eq!(
                term.current_attrs.foreground,
                crate::types::Color::Indexed($idx),
                concat!(
                    "SGR 38;5;",
                    stringify!($idx),
                    " must set foreground to Indexed(",
                    stringify!($idx),
                    ")"
                )
            );
        }

        #[test]
        fn $bg_name() {
            let mut term = crate::TerminalCore::new(24, 80);
            term.advance(concat!("\x1b[48;5;", stringify!($idx), "m").as_bytes());
            assert_eq!(
                term.current_attrs.background,
                crate::types::Color::Indexed($idx),
                concat!(
                    "SGR 48;5;",
                    stringify!($idx),
                    " must set background to Indexed(",
                    stringify!($idx),
                    ")"
                )
            );
        }
    };
}

// Boundary values: index 0 (first entry) and 255 (last entry).
test_sgr_indexed_color_pair!(test_sgr_256_fg_index_0, test_sgr_256_bg_index_0, 0);
test_sgr_indexed_color_pair!(test_sgr_256_fg_index_255, test_sgr_256_bg_index_255, 255);

// ── New edge-case tests ───────────────────────────────────────────────────────

#[test]
fn test_sgr_53_overline_is_noop() {
    // SGR 53 (overline) is not supported by this terminal and falls into `_ => {}`.
    // It must not panic and must leave all other attributes unchanged.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[1m"); // bold on first
    term.advance(b"\x1b[53m"); // overline — unrecognised, should be ignored
    assert!(
        term.current_attrs.flags.contains(SgrFlags::BOLD),
        "SGR 53 must not clear BOLD (unrecognised code is a no-op)"
    );
    assert_eq!(
        term.current_attrs.foreground,
        crate::types::Color::Default,
        "SGR 53 must not alter foreground color"
    );
}

#[test]
fn test_sgr_55_overline_reset_is_noop() {
    // SGR 55 (overline off) is unrecognised and must be a no-op.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[3m"); // italic on
    term.advance(b"\x1b[55m"); // overline off — unrecognised
    assert!(
        term.current_attrs.flags.contains(SgrFlags::ITALIC),
        "SGR 55 must not clear ITALIC (unrecognised code is a no-op)"
    );
}

#[test]
fn test_sgr_blink_25_clears_both_simultaneously() {
    // SGR 25 must clear both BLINK_SLOW and BLINK_FAST in a single sequence.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[5m"); // BLINK_SLOW on
    term.advance(b"\x1b[6m"); // BLINK_FAST on
    assert!(term.current_attrs.flags.contains(SgrFlags::BLINK_SLOW));
    assert!(term.current_attrs.flags.contains(SgrFlags::BLINK_FAST));
    term.advance(b"\x1b[25m"); // off — clears both
    assert!(
        !term.current_attrs.flags.contains(SgrFlags::BLINK_SLOW),
        "SGR 25 must clear BLINK_SLOW"
    );
    assert!(
        !term.current_attrs.flags.contains(SgrFlags::BLINK_FAST),
        "SGR 25 must clear BLINK_FAST"
    );
}

#[test]
fn test_sgr_attrs_survive_color_change() {
    // Setting a new foreground color must not disturb previously set flags.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[1m"); // bold on
    term.advance(b"\x1b[3m"); // italic on
    term.advance(b"\x1b[32m"); // green fg — color change
    assert!(
        term.current_attrs.flags.contains(SgrFlags::BOLD),
        "BOLD must survive a foreground color change"
    );
    assert!(
        term.current_attrs.flags.contains(SgrFlags::ITALIC),
        "ITALIC must survive a foreground color change"
    );
    assert_eq!(
        term.current_attrs.foreground,
        crate::types::Color::Named(crate::types::NamedColor::Green)
    );
}

#[test]
fn test_sgr_all_normal_fg_colors_30_to_37() {
    // Verify all 8 normal foreground colors (30-37) round-trip correctly.
    use crate::types::NamedColor;
    let expected = [
        NamedColor::Black,
        NamedColor::Red,
        NamedColor::Green,
        NamedColor::Yellow,
        NamedColor::Blue,
        NamedColor::Magenta,
        NamedColor::Cyan,
        NamedColor::White,
    ];
    for (offset, &color) in expected.iter().enumerate() {
        let mut term = crate::TerminalCore::new(24, 80);
        let seq = format!("\x1b[{}m", 30 + offset);
        term.advance(seq.as_bytes());
        assert_eq!(
            term.current_attrs.foreground,
            crate::types::Color::Named(color),
            "SGR {} must set Fg[{}]",
            30 + offset,
            offset
        );
    }
}

// ── New edge-case tests (round 34) ───────────────────────────────────────────

#[test]
fn test_sgr_reset_clears_all_flags_and_colors() {
    // SGR 0 must reset every attribute: all flags, both colors, underline_color,
    // and underline_style — in one pass.
    let mut term = crate::TerminalCore::new(24, 80);
    // Set many things at once.
    term.advance(b"\x1b[1m"); // BOLD
    term.advance(b"\x1b[2m"); // DIM
    term.advance(b"\x1b[3m"); // ITALIC
    term.advance(b"\x1b[4m"); // underline
    term.advance(b"\x1b[5m"); // BLINK_SLOW
    term.advance(b"\x1b[7m"); // INVERSE
    term.advance(b"\x1b[8m"); // HIDDEN
    term.advance(b"\x1b[9m"); // STRIKETHROUGH
    term.advance(b"\x1b[31m"); // red fg
    term.advance(b"\x1b[41m"); // red bg
    term.advance(b"\x1b[58;2;255;0;255m"); // underline_color
                                           // Now reset.
    term.advance(b"\x1b[0m");
    assert!(
        term.current_attrs.flags.is_empty(),
        "SGR 0 must clear all SgrFlags"
    );
    assert_eq!(
        term.current_attrs.foreground,
        crate::types::Color::Default,
        "SGR 0 must reset foreground"
    );
    assert_eq!(
        term.current_attrs.background,
        crate::types::Color::Default,
        "SGR 0 must reset background"
    );
    assert_eq!(
        term.current_attrs.underline_color,
        crate::types::Color::Default,
        "SGR 0 must reset underline_color"
    );
    assert_eq!(
        term.current_attrs.underline_style,
        crate::types::cell::UnderlineStyle::None,
        "SGR 0 must reset underline_style to None"
    );
}

#[test]
fn test_sgr_0_resets_underline_color() {
    // SGR 0 resets underline_color to Default — distinct from SGR 59.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[58;5;100m"); // underline_color = Indexed(100)
    assert_eq!(
        term.current_attrs.underline_color,
        crate::types::Color::Indexed(100)
    );
    term.advance(b"\x1b[0m");
    assert_eq!(
        term.current_attrs.underline_color,
        crate::types::Color::Default,
        "SGR 0 must reset underline_color (same as SGR 59 effect)"
    );
}

#[test]
fn test_sgr_truecolor_black_fg() {
    // RGB(0,0,0) as foreground — excluded from proptest but valid parser input.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[38;2;0;0;0m");
    assert_eq!(
        term.current_attrs.foreground,
        crate::types::Color::Rgb(0, 0, 0),
        "SGR 38;2;0;0;0 must produce Rgb(0,0,0) even though it encodes like Default"
    );
}

#[test]
fn test_sgr_truecolor_white_fg() {
    // RGB(255,255,255) as foreground — maximum component values.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[38;2;255;255;255m");
    assert_eq!(
        term.current_attrs.foreground,
        crate::types::Color::Rgb(255, 255, 255),
        "SGR 38;2;255;255;255 must produce Rgb(255,255,255)"
    );
}

#[test]
fn test_sgr_truecolor_white_bg() {
    // RGB(255,255,255) as background.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[48;2;255;255;255m");
    assert_eq!(
        term.current_attrs.background,
        crate::types::Color::Rgb(255, 255, 255),
        "SGR 48;2;255;255;255 must produce Rgb(255,255,255) background"
    );
}

#[test]
fn test_sgr_unknown_200_is_noop() {
    // SGR 200 is outside all recognised ranges and must fall into `_ => {}`.
    // Existing flags and colors must be undisturbed.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[1m"); // BOLD on
    term.advance(b"\x1b[32m"); // green fg
    term.advance(b"\x1b[200m"); // unknown — no-op
    assert!(
        term.current_attrs.flags.contains(SgrFlags::BOLD),
        "SGR 200 must not clear BOLD"
    );
    assert_eq!(
        term.current_attrs.foreground,
        crate::types::Color::Named(crate::types::NamedColor::Green),
        "SGR 200 must not alter foreground color"
    );
}

#[test]
fn test_sgr_unknown_150_is_noop() {
    // SGR 150 falls in the gap between 107 and recognised codes.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[3m"); // ITALIC on
    term.advance(b"\x1b[150m"); // unknown — no-op
    assert!(
        term.current_attrs.flags.contains(SgrFlags::ITALIC),
        "SGR 150 must not clear ITALIC"
    );
    assert_eq!(
        term.current_attrs.background,
        crate::types::Color::Default,
        "SGR 150 must not set background"
    );
}

#[test]
fn test_sgr_4_colon_high_subparam_defaults_to_straight() {
    // 4:6 and above are unrecognised sub-params; the `_ =>` arm sets Straight.
    use crate::types::cell::UnderlineStyle;
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[4:6m"); // sub-param 6: not in 0-5 map
    assert_eq!(
        term.current_attrs.underline_style,
        UnderlineStyle::Straight,
        "4:6 sub-param must fall through to Straight via `_ => Straight` arm"
    );
}

#[test]
fn test_sgr_underline_color_reset_does_not_affect_underline_style() {
    // SGR 59 resets only underline_color, not underline_style.
    use crate::types::cell::UnderlineStyle;
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[4:3m"); // curly underline style
    term.advance(b"\x1b[58;2;10;20;30m"); // set underline_color
    term.advance(b"\x1b[59m"); // reset underline_color
    assert_eq!(
        term.current_attrs.underline_color,
        crate::types::Color::Default,
        "SGR 59 must reset underline_color to Default"
    );
    assert_eq!(
        term.current_attrs.underline_style,
        UnderlineStyle::Curly,
        "SGR 59 must not change underline_style"
    );
}

#[test]
fn test_sgr_compound_bold_truecolor_strikethrough() {
    // A single CSI sequence combining bold + truecolor fg + strikethrough.
    // \e[1;38;2;10;20;30;9m
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[1;38;2;10;20;30;9m");
    assert!(
        term.current_attrs.flags.contains(SgrFlags::BOLD),
        "compound: BOLD must be set"
    );
    assert!(
        term.current_attrs.flags.contains(SgrFlags::STRIKETHROUGH),
        "compound: STRIKETHROUGH must be set"
    );
    assert_eq!(
        term.current_attrs.foreground,
        crate::types::Color::Rgb(10, 20, 30),
        "compound: truecolor fg Rgb(10,20,30) must be set"
    );
}

#[test]
fn test_sgr_all_normal_bg_colors_40_to_47() {
    // Verify all 8 normal background colors (40-47) map to correct NamedColor.
    use crate::types::NamedColor;
    let expected = [
        NamedColor::Black,
        NamedColor::Red,
        NamedColor::Green,
        NamedColor::Yellow,
        NamedColor::Blue,
        NamedColor::Magenta,
        NamedColor::Cyan,
        NamedColor::White,
    ];
    for (offset, &color) in expected.iter().enumerate() {
        let mut term = crate::TerminalCore::new(24, 80);
        let seq = format!("\x1b[{}m", 40 + offset);
        term.advance(seq.as_bytes());
        assert_eq!(
            term.current_attrs.background,
            crate::types::Color::Named(color),
            "SGR {} must set Bg[{}]",
            40 + offset,
            offset
        );
    }
}

use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(500))]

    #[test]
    // ROUNDTRIP: CSI 38;5;{idx}m sets foreground to Color::Indexed(idx)
    fn prop_sgr_fg_256_roundtrip(idx in 0u8..=255u8) {
        let mut term = crate::TerminalCore::new(24, 80);
        term.advance(format!("\x1b[38;5;{idx}m").as_bytes());
        prop_assert_eq!(
            term.current_attrs.foreground,
            crate::types::Color::Indexed(idx),
            "256-color fg must be Indexed({})", idx
        );
    }

    #[test]
    // ROUNDTRIP: CSI 48;5;{idx}m sets background to Color::Indexed(idx)
    fn prop_sgr_bg_256_roundtrip(idx in 0u8..=255u8) {
        let mut term = crate::TerminalCore::new(24, 80);
        term.advance(format!("\x1b[48;5;{idx}m").as_bytes());
        prop_assert_eq!(
            term.current_attrs.background,
            crate::types::Color::Indexed(idx),
            "256-color bg must be Indexed({})", idx
        );
    }

    #[test]
    // ROUNDTRIP: CSI 38;2;r;g;bm sets foreground to Color::Rgb(r,g,b)
    // Excludes Rgb(0,0,0) which collides with Color::Default in encode_color
    fn prop_sgr_truecolor_fg_roundtrip(
        r in 0u8..=255u8,
        g in 0u8..=255u8,
        b in 0u8..=255u8
    ) {
        // Skip the degenerate case: Rgb(0,0,0) encodes identically to Default
        prop_assume!(r != 0 || g != 0 || b != 0);
        let mut term = crate::TerminalCore::new(24, 80);
        term.advance(format!("\x1b[38;2;{r};{g};{b}m").as_bytes());
        prop_assert_eq!(
            term.current_attrs.foreground,
            crate::types::Color::Rgb(r, g, b),
            "truecolor fg must be Rgb({},{},{})", r, g, b
        );
    }

    #[test]
    // PANIC SAFETY: any single SGR parameter in 0..=107 must not panic
    fn prop_sgr_arbitrary_no_panic(code in 0u16..=107u16) {
        let mut term = crate::TerminalCore::new(24, 80);
        term.advance(format!("\x1b[{code}m").as_bytes());
        // Terminal must still have a valid cursor position
        prop_assert!(term.screen.cursor.row < 24);
    }

    #[test]
    // INVARIANT: SGR 0 resets foreground to Default regardless of prior named color
    fn prop_sgr_reset_clears_fg(offset in 0u16..=7u16) {
        let mut term = crate::TerminalCore::new(24, 80);
        // Set a named foreground color (CSI 30m–CSI 37m)
        term.advance(format!("\x1b[{}m", 30 + offset).as_bytes());
        // Now reset with SGR 0
        term.advance(b"\x1b[0m");
        prop_assert_eq!(
            term.current_attrs.foreground,
            crate::types::Color::Default,
            "SGR 0 must reset foreground to Default"
        );
    }

    #[test]
    // INVARIANT: Named foreground colors (30-37) set a non-Default foreground
    fn prop_sgr_named_fg_not_default(offset in 0u16..=7u16) {
        let mut term = crate::TerminalCore::new(24, 80);
        term.advance(format!("\x1b[{}m", 30 + offset).as_bytes());
        prop_assert_ne!(
            term.current_attrs.foreground,
            crate::types::Color::Default,
            "CSI {}m must set a named foreground color", 30 + offset
        );
    }
}
