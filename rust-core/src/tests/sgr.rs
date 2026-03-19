//! SGR underline/color attribute tests.

use super::super::*;

// === SGR underline style tests ===

#[test]
fn test_sgr_4_colon_3_sets_curly_underline() {
    let mut term = super::make_term();
    // CSI 4:3 m — curly underline (colon sub-parameter form)
    term.advance(b"\x1b[4:3m");
    assert_eq!(
        term.current_attrs.underline_style,
        types::cell::UnderlineStyle::Curly,
        "SGR 4:3 should set curly underline"
    );
}

#[test]
fn test_sgr_4_colon_5_sets_dashed_underline() {
    let mut term = super::make_term();
    term.advance(b"\x1b[4:5m");
    assert_eq!(
        term.current_attrs.underline_style,
        types::cell::UnderlineStyle::Dashed,
        "SGR 4:5 should set dashed underline"
    );
}

#[test]
fn test_sgr_21_sets_double_underline() {
    let mut term = super::make_term();
    term.advance(b"\x1b[21m");
    assert_eq!(
        term.current_attrs.underline_style,
        types::cell::UnderlineStyle::Double,
        "SGR 21 should set double underline"
    );
}

#[test]
fn test_sgr_24_clears_underline() {
    let mut term = super::make_term();
    term.advance(b"\x1b[4:3m"); // Set curly
    assert!(
        term.current_attrs.underline(),
        "Curly underline should be active"
    );
    term.advance(b"\x1b[24m"); // Clear
    assert!(
        !term.current_attrs.underline(),
        "SGR 24 should clear underline"
    );
    assert_eq!(
        term.current_attrs.underline_style,
        types::cell::UnderlineStyle::None,
        "SGR 24 should set underline_style to None"
    );
}

#[test]
fn test_sgr_58_5_sets_underline_color_indexed() {
    let mut term = super::make_term();
    term.advance(b"\x1b[58;5;196m");
    assert_eq!(
        term.current_attrs.underline_color,
        types::color::Color::Indexed(196),
        "SGR 58;5;196 should set indexed underline color 196"
    );
}

#[test]
fn test_sgr_58_2_sets_underline_color_rgb() {
    let mut term = super::make_term();
    term.advance(b"\x1b[58;2;255;128;0m");
    assert_eq!(
        term.current_attrs.underline_color,
        types::color::Color::Rgb(255, 128, 0),
        "SGR 58;2;255;128;0 should set RGB underline color"
    );
}

#[test]
fn test_sgr_59_resets_underline_color() {
    let mut term = super::make_term();
    term.advance(b"\x1b[58;5;196m");
    assert_ne!(
        term.current_attrs.underline_color,
        types::color::Color::Default,
        "Underline color should be set before reset"
    );
    term.advance(b"\x1b[59m");
    assert_eq!(
        term.current_attrs.underline_color,
        types::color::Color::Default,
        "SGR 59 should reset underline color to Default"
    );
}
