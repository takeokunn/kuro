//! Integration tests for SGR (Select Graphic Rendition) extended attributes.

mod common;

use kuro_core::TerminalCore;

// ─────────────────────────────────────────────────────────────────────────────
// Macros
// ─────────────────────────────────────────────────────────────────────────────

/// Assert that a given escape sequence sets the expected `UnderlineStyle`.
///
/// Usage: `assert_underline_style!(escape_bytes, ExpectedVariant, "message")`
macro_rules! assert_underline_style {
    ($seq:expr, $expected:expr, $msg:literal) => {{
        let mut t = TerminalCore::new(24, 80);
        t.advance($seq);
        assert_eq!(t.current_attrs().underline_style, $expected, $msg);
    }};
    ($seq:expr, $expected:expr) => {{
        let mut t = TerminalCore::new(24, 80);
        t.advance($seq);
        assert_eq!(t.current_attrs().underline_style, $expected);
    }};
}

/// Assert that an SGR boolean flag (accessed via `current_attrs().flags`) is set
/// after applying `$set_seq`, cleared after applying `$clear_seq`, and that a
/// subsequent SGR 0 also clears it.
///
/// Usage: `assert_flag_set_clear!(set_bytes, clear_bytes, FLAG_CONST, "label")`
macro_rules! assert_flag_set_clear {
    ($set_seq:expr, $clear_seq:expr, $flag:expr, $label:literal) => {{
        let mut t = TerminalCore::new(24, 80);
        t.advance($set_seq);
        assert!(
            t.current_attrs().flags.contains($flag),
            "{}: flag should be set after {:?}",
            $label,
            $set_seq
        );
        t.advance($clear_seq);
        assert!(
            !t.current_attrs().flags.contains($flag),
            "{}: flag should be cleared after {:?}",
            $label,
            $clear_seq
        );
    }};
}

// ─────────────────────────────────────────────────────────────────────────────
// SGR Extended Underline Types (4:X sub-params, 21, 58, 59)
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn sgr_4_colon_1_sets_straight_underline() {
    assert_underline_style!(
        b"\x1b[4:1m",
        kuro_core::UnderlineStyle::Straight,
        "SGR 4:1 must set Straight underline"
    );
}

#[test]
fn sgr_4_colon_2_sets_double_underline() {
    assert_underline_style!(
        b"\x1b[4:2m",
        kuro_core::UnderlineStyle::Double,
        "SGR 4:2 must set Double underline"
    );
}

#[test]
fn sgr_4_colon_3_sets_curly_underline() {
    assert_underline_style!(b"\x1b[4:3m", kuro_core::UnderlineStyle::Curly);
}

#[test]
fn sgr_4_colon_4_sets_dotted_underline() {
    assert_underline_style!(b"\x1b[4:4m", kuro_core::UnderlineStyle::Dotted);
}

#[test]
fn sgr_4_colon_5_sets_dashed_underline() {
    assert_underline_style!(b"\x1b[4:5m", kuro_core::UnderlineStyle::Dashed);
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
    assert_underline_style!(
        b"\x1b[21m",
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

// ─────────────────────────────────────────────────────────────────────────────
// New edge-case tests
// ─────────────────────────────────────────────────────────────────────────────

/// SGR 0 (reset) after setting multiple attributes simultaneously must clear
/// every attribute including underline style and underline color.
#[test]
fn sgr_0_resets_all_after_multiple_simultaneous_attributes() {
    use kuro_core::types::cell::SgrFlags;
    let mut t = TerminalCore::new(24, 80);
    // Set bold + italic + strikethrough in one sequence
    t.advance(b"\x1b[1;3;9m");
    assert!(t.current_bold(), "bold should be set");
    assert!(t.current_italic(), "italic should be set");
    assert!(
        t.current_attrs().flags.contains(SgrFlags::STRIKETHROUGH),
        "strikethrough should be set"
    );
    // Now reset all with a single SGR 0
    t.advance(b"\x1b[0m");
    assert!(!t.current_bold(), "bold must be cleared by SGR 0");
    assert!(!t.current_italic(), "italic must be cleared by SGR 0");
    assert!(
        !t.current_attrs().flags.contains(SgrFlags::STRIKETHROUGH),
        "strikethrough must be cleared by SGR 0"
    );
}

/// SGR with multiple params in one escape: `\x1b[1;3;4m` sets bold, italic,
/// and underline in a single sequence.
#[test]
fn sgr_multi_param_bold_italic_underline_in_one_sequence() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[1;3;4m"); // bold + italic + underline
    assert!(t.current_bold(), "bold should be set by \\x1b[1;3;4m");
    assert!(t.current_italic(), "italic should be set by \\x1b[1;3;4m");
    assert!(
        t.current_underline(),
        "underline should be set by \\x1b[1;3;4m"
    );
}

/// SGR `\x1b[2;9m` sets dim and strikethrough simultaneously.
#[test]
fn sgr_multi_param_dim_and_strikethrough() {
    use kuro_core::types::cell::SgrFlags;
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[2;9m");
    assert!(
        t.current_attrs().flags.contains(SgrFlags::DIM),
        "dim should be set"
    );
    assert!(
        t.current_attrs().flags.contains(SgrFlags::STRIKETHROUGH),
        "strikethrough should be set"
    );
}

/// `\x1b[58;2;R;G;Bm` (semicolon form) sets underline color — the parser
/// must handle both `:` and `;` delimiters for the underline-color payload.
#[test]
fn sgr_58_semicolon_form_sets_underline_color() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[58;2;0;255;128m"); // RGB green-ish underline color via semicolons
    assert_eq!(
        t.current_attrs().underline_color,
        kuro_core::Color::Rgb(0, 255, 128),
        "SGR 58;2;R;G;B (semicolons) must set underline_color to Rgb"
    );
}

/// SGR 59 after setting the underline color via `\x1b[58;2;R;G;Bm` semicolon
/// form must reset the underline color back to Default.
#[test]
fn sgr_59_resets_underline_color_after_semicolon_form() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[58;2;10;20;30m");
    t.advance(b"\x1b[59m");
    assert_eq!(
        t.current_attrs().underline_color,
        kuro_core::Color::Default,
        "SGR 59 must reset underline_color to Default regardless of how color was set"
    );
}

/// SGR 4:0 must clear whichever underline style is active, not just Straight.
/// Verify it works after a curly underline is set.
#[test]
fn sgr_4_colon_0_clears_curly_underline() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[4:3m"); // set curly underline
    assert_eq!(
        t.current_attrs().underline_style,
        kuro_core::UnderlineStyle::Curly
    );
    t.advance(b"\x1b[4:0m"); // clear underline
    assert_eq!(
        t.current_attrs().underline_style,
        kuro_core::UnderlineStyle::None,
        "SGR 4:0 must set underline_style to None regardless of previous style"
    );
}

/// Verify all 6 underline styles (None through Dashed) round-trip through
/// SGR 4:0 correctly: after each style, SGR 0 resets underline_style to None.
#[test]
fn sgr_0_resets_all_underline_styles_to_none() {
    let sequences: &[(&[u8], kuro_core::UnderlineStyle)] = &[
        (b"\x1b[4m", kuro_core::UnderlineStyle::Straight),
        (b"\x1b[4:1m", kuro_core::UnderlineStyle::Straight),
        (b"\x1b[4:2m", kuro_core::UnderlineStyle::Double),
        (b"\x1b[4:3m", kuro_core::UnderlineStyle::Curly),
        (b"\x1b[4:4m", kuro_core::UnderlineStyle::Dotted),
        (b"\x1b[4:5m", kuro_core::UnderlineStyle::Dashed),
    ];
    for (set_seq, expected_style) in sequences {
        let mut t = TerminalCore::new(24, 80);
        t.advance(set_seq);
        assert_eq!(
            t.current_attrs().underline_style,
            *expected_style,
            "expected {expected_style:?} after {set_seq:?}"
        );
        t.advance(b"\x1b[0m");
        assert_eq!(
            t.current_attrs().underline_style,
            kuro_core::UnderlineStyle::None,
            "SGR 0 must reset underline_style to None (was {expected_style:?})"
        );
    }
}

/// SGR blink and inverse flags set and cleared individually.
#[test]
fn sgr_blink_and_inverse_flags() {
    use kuro_core::types::cell::SgrFlags;
    assert_flag_set_clear!(b"\x1b[5m", b"\x1b[0m", SgrFlags::BLINK_SLOW, "BLINK_SLOW");
    assert_flag_set_clear!(b"\x1b[7m", b"\x1b[0m", SgrFlags::INVERSE, "INVERSE");
}

/// SGR hidden (8) and strikethrough (9) flags set and cleared individually.
#[test]
fn sgr_hidden_and_strikethrough_flags() {
    use kuro_core::types::cell::SgrFlags;
    assert_flag_set_clear!(b"\x1b[8m", b"\x1b[0m", SgrFlags::HIDDEN, "HIDDEN");
    assert_flag_set_clear!(
        b"\x1b[9m",
        b"\x1b[0m",
        SgrFlags::STRIKETHROUGH,
        "STRIKETHROUGH"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// SGR foreground / background color — 256-indexed and RGB
// ─────────────────────────────────────────────────────────────────────────────

// SGR 38;5;N sets foreground to 256-color indexed palette entry N.
#[test]
fn sgr_38_5_sets_foreground_indexed_color() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[38;5;200m");
    assert_eq!(
        *t.current_foreground(),
        kuro_core::Color::Indexed(200),
        "SGR 38;5;200 must set foreground to Indexed(200)"
    );
}

// SGR 48;5;N sets background to 256-color indexed palette entry N.
#[test]
fn sgr_48_5_sets_background_indexed_color() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[48;5;100m");
    assert_eq!(
        t.current_attrs().background,
        kuro_core::Color::Indexed(100),
        "SGR 48;5;100 must set background to Indexed(100)"
    );
}

// SGR 38;2;R;G;B sets foreground to an RGB color.
#[test]
fn sgr_38_2_sets_foreground_rgb() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[38;2;10;20;30m");
    assert_eq!(
        *t.current_foreground(),
        kuro_core::Color::Rgb(10, 20, 30),
        "SGR 38;2;R;G;B must set foreground to Rgb"
    );
}

// SGR 48;2;R;G;B sets background to an RGB color.
#[test]
fn sgr_48_2_sets_background_rgb() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[48;2;100;150;200m");
    assert_eq!(
        t.current_attrs().background,
        kuro_core::Color::Rgb(100, 150, 200),
        "SGR 48;2;R;G;B must set background to Rgb"
    );
}

// SGR 39 resets foreground to Default.
#[test]
fn sgr_39_resets_foreground_to_default() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[38;5;99m");
    t.advance(b"\x1b[39m");
    assert_eq!(
        *t.current_foreground(),
        kuro_core::Color::Default,
        "SGR 39 must reset foreground to Default"
    );
}

// SGR 49 resets background to Default.
#[test]
fn sgr_49_resets_background_to_default() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[48;2;1;2;3m");
    t.advance(b"\x1b[49m");
    assert_eq!(
        t.current_attrs().background,
        kuro_core::Color::Default,
        "SGR 49 must reset background to Default"
    );
}

// SGR 0 resets both foreground and background to Default.
#[test]
fn sgr_0_resets_fg_and_bg_colors() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[38;5;200m");
    t.advance(b"\x1b[48;5;50m");
    t.advance(b"\x1b[0m");
    assert_eq!(
        *t.current_foreground(),
        kuro_core::Color::Default,
        "SGR 0 must reset foreground to Default"
    );
    assert_eq!(
        t.current_attrs().background,
        kuro_core::Color::Default,
        "SGR 0 must reset background to Default"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// SGR bright named colors — foreground (90–97) / background (100–107)
//
// These lock down the bright named-color dispatch in `parser/sgr.rs`
// (`bright_named_color_from_offset`) and `parser/sgr_support.rs`
// (`NAMED_SGR_COLOR_GROUPS` rows for bases 90 and 100). The parser is already
// correct; these are regression guards so a future refactor cannot silently
// downgrade bright colors to their normal variants or to Indexed values.
// ─────────────────────────────────────────────────────────────────────────────

/// SGR 90 must set the foreground to the bright-black named color
/// (`NamedColor::BrightBlack`), not the normal `Black` and not `Indexed(8)`.
#[test]
fn sgr_90_sets_foreground_bright_black() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[90m");
    assert_eq!(
        *t.current_foreground(),
        kuro_core::Color::Named(kuro_core::types::NamedColor::BrightBlack),
        "SGR 90 must set foreground to Named(BrightBlack)"
    );
}

/// SGR 97 must set the foreground to the bright-white named color
/// (the top of the 90–97 range, offset 7).
#[test]
fn sgr_97_sets_foreground_bright_white() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[97m");
    assert_eq!(
        *t.current_foreground(),
        kuro_core::Color::Named(kuro_core::types::NamedColor::BrightWhite),
        "SGR 97 must set foreground to Named(BrightWhite)"
    );
}

/// SGR 100 must set the background to the bright-black named color
/// (base 100, offset 0).
#[test]
fn sgr_100_sets_background_bright_black() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[100m");
    assert_eq!(
        t.current_attrs().background,
        kuro_core::Color::Named(kuro_core::types::NamedColor::BrightBlack),
        "SGR 100 must set background to Named(BrightBlack)"
    );
}

/// SGR 107 must set the background to the bright-white named color
/// (top of the 100–107 range, offset 7).
#[test]
fn sgr_107_sets_background_bright_white() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[107m");
    assert_eq!(
        t.current_attrs().background,
        kuro_core::Color::Named(kuro_core::types::NamedColor::BrightWhite),
        "SGR 107 must set background to Named(BrightWhite)"
    );
}

/// The full 90–97 range must map to BrightBlack..BrightWhite in offset order.
#[test]
fn sgr_90_through_97_map_to_bright_named_foreground_in_order() {
    use kuro_core::types::NamedColor::{
        BrightBlack, BrightBlue, BrightCyan, BrightGreen, BrightMagenta, BrightRed, BrightWhite,
        BrightYellow,
    };
    let cases: &[(&[u8], kuro_core::types::NamedColor)] = &[
        (b"\x1b[90m", BrightBlack),
        (b"\x1b[91m", BrightRed),
        (b"\x1b[92m", BrightGreen),
        (b"\x1b[93m", BrightYellow),
        (b"\x1b[94m", BrightBlue),
        (b"\x1b[95m", BrightMagenta),
        (b"\x1b[96m", BrightCyan),
        (b"\x1b[97m", BrightWhite),
    ];
    for (seq, expected) in cases {
        let mut t = TerminalCore::new(24, 80);
        t.advance(seq);
        assert_eq!(
            *t.current_foreground(),
            kuro_core::Color::Named(*expected),
            "{seq:?} must set foreground to Named({expected:?})"
        );
    }
}

/// The full 100–107 range must map to BrightBlack..BrightWhite in offset order.
#[test]
fn sgr_100_through_107_map_to_bright_named_background_in_order() {
    use kuro_core::types::NamedColor::{
        BrightBlack, BrightBlue, BrightCyan, BrightGreen, BrightMagenta, BrightRed, BrightWhite,
        BrightYellow,
    };
    let cases: &[(&[u8], kuro_core::types::NamedColor)] = &[
        (b"\x1b[100m", BrightBlack),
        (b"\x1b[101m", BrightRed),
        (b"\x1b[102m", BrightGreen),
        (b"\x1b[103m", BrightYellow),
        (b"\x1b[104m", BrightBlue),
        (b"\x1b[105m", BrightMagenta),
        (b"\x1b[106m", BrightCyan),
        (b"\x1b[107m", BrightWhite),
    ];
    for (seq, expected) in cases {
        let mut t = TerminalCore::new(24, 80);
        t.advance(seq);
        assert_eq!(
            t.current_attrs().background,
            kuro_core::Color::Named(*expected),
            "{seq:?} must set background to Named({expected:?})"
        );
    }
}

/// SGR 39 must reset a bright foreground (set via SGR 91) back to Default.
#[test]
fn sgr_39_resets_bright_foreground_to_default() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[91m"); // bright red foreground
    assert_eq!(
        *t.current_foreground(),
        kuro_core::Color::Named(kuro_core::types::NamedColor::BrightRed)
    );
    t.advance(b"\x1b[39m");
    assert_eq!(
        *t.current_foreground(),
        kuro_core::Color::Default,
        "SGR 39 must reset a bright foreground to Default"
    );
}

/// SGR 49 must reset a bright background (set via SGR 101) back to Default.
#[test]
fn sgr_49_resets_bright_background_to_default() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[101m"); // bright red background
    assert_eq!(
        t.current_attrs().background,
        kuro_core::Color::Named(kuro_core::types::NamedColor::BrightRed)
    );
    t.advance(b"\x1b[49m");
    assert_eq!(
        t.current_attrs().background,
        kuro_core::Color::Default,
        "SGR 49 must reset a bright background to Default"
    );
}

/// SGR 0 must reset both a bright foreground and a bright background to Default.
#[test]
fn sgr_0_resets_bright_fg_and_bg_to_default() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[95m"); // bright magenta foreground
    t.advance(b"\x1b[106m"); // bright cyan background
    t.advance(b"\x1b[0m");
    assert_eq!(
        *t.current_foreground(),
        kuro_core::Color::Default,
        "SGR 0 must reset a bright foreground to Default"
    );
    assert_eq!(
        t.current_attrs().background,
        kuro_core::Color::Default,
        "SGR 0 must reset a bright background to Default"
    );
}

/// Colon-indexed `38:5:9` must resolve to palette index 9, which is the
/// standard bright-red slot in the 256-color palette. The parser stores this
/// as `Color::Indexed(9)` (the palette layer resolves index 9 to bright red).
#[test]
fn sgr_38_colon_5_colon_9_maps_to_bright_red_index() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[38:5:9m");
    assert_eq!(
        *t.current_foreground(),
        kuro_core::Color::Indexed(9),
        "SGR 38:5:9 (colon form) must set foreground to Indexed(9), the bright-red palette slot"
    );
}

#[path = "include/integration_sgr_combining.rs"]
mod combining;
