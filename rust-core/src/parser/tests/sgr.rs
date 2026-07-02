//! Property-based and example-based tests for `sgr` parsing.
//!
//! Module under test: `parser/sgr.rs`
//! Tier: T2 — `ProptestConfig::with_cases(500)`

use super::*;
use crate::types::cell::SgrFlags;

#[macro_use]
#[path = "sgr/support.rs"]
mod support;

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
fn test_sgr_256color_out_of_range_unchanged() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[38;5;256m");
    assert!(
        matches!(term.current_attrs.foreground, crate::types::Color::Default),
        "Foreground should remain Default when 256-color index is out of range"
    );
}

#[test]
fn test_sgr_colon_256color_out_of_range_unchanged() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[38:5:256m");
    assert!(
        matches!(term.current_attrs.foreground, crate::types::Color::Default),
        "Foreground should remain Default when colon-form 256-color index is out of range"
    );
}

#[test]
fn test_sgr_truecolor_partial_rgb_unchanged() {
    // \x1b[38;2;255m — truecolor with only R component, G and B missing
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[38;2;255m");
    assert!(
        matches!(term.current_attrs.foreground, crate::types::Color::Default),
        "Partial truecolor should be ignored instead of defaulting missing components to 0"
    );
}

#[test]
fn test_sgr_colon_truecolor_partial_rgb_unchanged() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[38:2:255m");
    assert!(
        matches!(term.current_attrs.foreground, crate::types::Color::Default),
        "Partial colon-form truecolor should be ignored"
    );
}

#[test]
fn test_sgr_truecolor_out_of_range_unchanged() {
    // \x1b[38;2;300;300;300m — values exceed u8 range
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[38;2;300;300;300m");
    assert!(
        matches!(term.current_attrs.foreground, crate::types::Color::Default),
        "Out-of-range truecolor should be ignored instead of truncated"
    );
}

#[test]
fn test_sgr_colon_truecolor_out_of_range_unchanged() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[38:2:300:0:0m");
    assert!(
        matches!(term.current_attrs.foreground, crate::types::Color::Default),
        "Out-of-range colon-form truecolor should be ignored instead of truncated"
    );
}

#[path = "sgr/ext.rs"]
mod ext;

#[path = "sgr/color.rs"]
mod color;

#[path = "sgr/edge_cases.rs"]
mod edge_cases;

#[path = "sgr/apply_attrs.rs"]
mod apply_attrs;
