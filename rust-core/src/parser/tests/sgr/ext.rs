use super::*;

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

// Verify all 8 bright foreground colors (90-97) map to the correct NamedColor.
test_sgr_all_bright_variants!(test_sgr_all_bright_fg_variants, base 90, foreground);

// Verify all 8 bright background colors (100-107) map to the correct NamedColor.
test_sgr_all_bright_variants!(test_sgr_all_bright_bg_variants, base 100, background);

/// Every rendition `serialize_sgr` emits round-trips through the parser:
/// re-applying the serialized string reproduces the identical `SgrAttributes`.
/// This is the faithfulness contract DECRQSS (`DCS $ q m`) depends on.
#[test]
fn test_serialize_sgr_round_trips_through_parser() {
    let cases: [&[u8]; 24] = [
        b"\x1b[m",              // default / reset
        b"\x1b[1m",             // bold
        b"\x1b[2m",             // dim
        b"\x1b[1;3;4;7;9m",     // bold italic underline inverse strikethrough
        b"\x1b[5m",             // slow blink
        b"\x1b[6m",             // fast blink
        b"\x1b[8m",             // hidden (concealed)
        b"\x1b[31m",            // fg named red
        b"\x1b[91m",            // fg bright red
        b"\x1b[38;5;196m",      // fg indexed
        b"\x1b[38;2;10;20;30m", // fg RGB
        b"\x1b[41m",            // bg named red (append_sgr_color base branch)
        b"\x1b[101m",           // bg bright red (append_sgr_color bright_base branch)
        b"\x1b[48;5;21m",       // bg indexed
        b"\x1b[48;2;10;20;30m", // bg RGB
        b"\x1b[4:3m",           // curly underline
        b"\x1b[58;2;9;8;7m",    // underline color RGB
        b"\x1b[58;5;200m",      // underline color indexed
        b"\x1b[53m",            // overline on
        b"\x1b[73m",            // superscript on
        b"\x1b[75m",            // subscript on
        b"\x1b[4:4m",           // dotted underline
        b"\x1b[4:5m",           // dashed underline
        b"\x1b[21m",            // double underline (SGR 21)
    ];
    for seq in cases {
        let mut a = crate::TerminalCore::new(24, 80);
        a.advance(seq);
        let original = a.current_attrs;
        let sgr = serialize_sgr(&original);
        let mut b = crate::TerminalCore::new(24, 80);
        b.advance(format!("\x1b[{sgr}m").as_bytes());
        assert_eq!(
            b.current_attrs, original,
            "round-trip failed for {seq:?}: serialized as {sgr:?}"
        );
    }
}
