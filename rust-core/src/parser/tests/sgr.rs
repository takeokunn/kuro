use super::*;

#[test]
fn test_sgr_reset() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.current_attrs.bold = true;
    term.current_attrs.italic = true;

    let params = vte::Params::default();
    handle_sgr(&mut term, &params);

    assert!(!term.current_attrs.bold);
    assert!(!term.current_attrs.italic);
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
    assert!(term.current_attrs.bold, "bold should be set");
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
fn test_sgr_decstbm_inverted_margins_no_panic() {
    // \x1b[10;5r — DECSTBM with top=10 > bottom=5 (inverted)
    // Should not panic; scroll operations with inverted region are no-ops
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[10;5r");
    // Attempt scrolls — should not panic
    term.advance(b"\x1b[S"); // Scroll up
    term.advance(b"\x1b[T"); // Scroll down
}

#[test]
fn test_sgr_empty_sequence_resets_all() {
    // \x1b[m — empty SGR sequence resets all attributes
    let mut term = crate::TerminalCore::new(24, 80);
    // First set some attributes
    term.advance(b"\x1b[1;3;4m"); // bold, italic, underline
    assert!(term.current_attrs.bold, "bold should be set before reset");
    assert!(
        term.current_attrs.italic,
        "italic should be set before reset"
    );
    assert!(
        term.current_attrs.underline(),
        "underline should be set before reset"
    );
    // Now reset with empty sequence
    term.advance(b"\x1b[m");
    // All attributes should be reset
    assert!(!term.current_attrs.bold, "bold should be reset");
    assert!(!term.current_attrs.italic, "italic should be reset");
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

#[test]
fn test_sgr_bold_turn_off_code_22() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[1m"); // bold on
    assert!(term.current_attrs.bold);
    term.advance(b"\x1b[22m"); // turn off bold+dim
    assert!(!term.current_attrs.bold, "Bold should be off after CSI 22m");
}

#[test]
fn test_sgr_italic_turn_off_code_23() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[3m"); // italic on
    assert!(term.current_attrs.italic);
    term.advance(b"\x1b[23m"); // turn off italic
    assert!(
        !term.current_attrs.italic,
        "Italic should be off after CSI 23m"
    );
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
fn test_sgr_inverse_turn_off_code_27() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[7m"); // inverse on
    assert!(term.current_attrs.inverse);
    term.advance(b"\x1b[27m"); // turn off inverse
    assert!(
        !term.current_attrs.inverse,
        "Inverse should be off after CSI 27m"
    );
}

#[test]
fn test_sgr_blink_turn_off_code_25_clears_slow() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[5m"); // blink_slow on
    assert!(term.current_attrs.blink_slow);
    term.advance(b"\x1b[25m"); // turn off blink (both slow and fast)
    assert!(
        !term.current_attrs.blink_slow,
        "blink_slow should be off after CSI 25m"
    );
}

#[test]
fn test_sgr_blink_turn_off_code_25_clears_fast() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[6m"); // blink_fast on
    assert!(term.current_attrs.blink_fast);
    term.advance(b"\x1b[25m"); // turn off blink (both slow and fast)
    assert!(
        !term.current_attrs.blink_fast,
        "blink_fast should be off after CSI 25m"
    );
}

#[test]
fn test_sgr_hidden_turn_off_code_28() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[8m"); // hidden on
    assert!(term.current_attrs.hidden);
    term.advance(b"\x1b[28m"); // turn off hidden
    assert!(
        !term.current_attrs.hidden,
        "Hidden should be off after CSI 28m"
    );
}

#[test]
fn test_sgr_strikethrough_turn_off_code_29() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[9m"); // strikethrough on
    assert!(term.current_attrs.strikethrough);
    term.advance(b"\x1b[29m"); // turn off strikethrough
    assert!(
        !term.current_attrs.strikethrough,
        "Strikethrough should be off after CSI 29m"
    );
}
