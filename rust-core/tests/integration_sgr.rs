//! Integration tests for SGR (Select Graphic Rendition) extended attributes.

mod common;

use kuro_core::TerminalCore;

// ─────────────────────────────────────────────────────────────────────────────
// SGR Extended Underline Types (4:X sub-params, 21, 58, 59)
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn sgr_4_colon_2_sets_double_underline() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[4:2m");
    assert_eq!(
        t.current_attrs().underline_style,
        kuro_core::UnderlineStyle::Double,
        "SGR 4:2 must set Double underline"
    );
}

#[test]
fn sgr_4_colon_3_sets_curly_underline() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[4:3m");
    assert_eq!(
        t.current_attrs().underline_style,
        kuro_core::UnderlineStyle::Curly
    );
}

#[test]
fn sgr_4_colon_4_sets_dotted_underline() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[4:4m");
    assert_eq!(
        t.current_attrs().underline_style,
        kuro_core::UnderlineStyle::Dotted
    );
}

#[test]
fn sgr_4_colon_5_sets_dashed_underline() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[4:5m");
    assert_eq!(
        t.current_attrs().underline_style,
        kuro_core::UnderlineStyle::Dashed
    );
}

#[test]
fn sgr_4_colon_0_clears_underline() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[4m"); // set straight first
    assert!(t.current_underline());
    t.advance(b"\x1b[4:0m"); // clear via sub-param
    assert!(!t.current_underline(), "SGR 4:0 must clear underline");
}

#[test]
fn sgr_21_sets_double_underline() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[21m");
    assert_eq!(
        t.current_attrs().underline_style,
        kuro_core::UnderlineStyle::Double,
        "SGR 21 must set Double underline"
    );
}

#[test]
fn sgr_58_sets_underline_color_rgb() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[58:2:255:128:0m"); // RGB underline color
    assert_eq!(
        t.current_attrs().underline_color,
        kuro_core::Color::Rgb(255, 128, 0),
        "SGR 58:2:R:G:B must set underline_color to Rgb"
    );
}

#[test]
fn sgr_59_resets_underline_color() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[58:2:255:0:0m"); // set red underline color
    t.advance(b"\x1b[59m"); // reset underline color
    assert_eq!(
        t.current_attrs().underline_color,
        kuro_core::Color::Default,
        "SGR 59 must reset underline_color to Default"
    );
}

#[test]
fn sgr_4_colon_1_sets_straight_underline() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[4:1m");
    assert_eq!(
        t.current_attrs().underline_style,
        kuro_core::UnderlineStyle::Straight,
        "SGR 4:1 must set Straight underline"
    );
}
