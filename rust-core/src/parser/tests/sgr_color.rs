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

// ── Macro: test_sgr_truecolor ─────────────────────────────────────────────────
//
// Generates a test that sends a truecolor SGR sequence and checks the result.
//
// Usage:
// ```text
// test_sgr_truecolor!(test_name, sgr_code, field, r, g, b, "msg")
// ```
// `sgr_code` is either 38 (fg) or 48 (bg); `field` is `foreground` or `background`.
macro_rules! test_sgr_truecolor {
    ($name:ident, $sgr:literal, $field:ident, $r:literal, $g:literal, $b:literal, $msg:expr) => {
        #[test]
        fn $name() {
            let mut term = crate::TerminalCore::new(24, 80);
            term.advance(
                concat!(
                    "\x1b[",
                    stringify!($sgr),
                    ";2;",
                    stringify!($r),
                    ";",
                    stringify!($g),
                    ";",
                    stringify!($b),
                    "m"
                )
                .as_bytes(),
            );
            assert_eq!(
                term.current_attrs.$field,
                crate::types::Color::Rgb($r, $g, $b),
                $msg
            );
        }
    };
}

test_sgr_truecolor!(
    test_sgr_truecolor_black_fg,
    38,
    foreground,
    0,
    0,
    0,
    "SGR 38;2;0;0;0 must produce Rgb(0,0,0) even though it encodes like Default"
);
test_sgr_truecolor!(
    test_sgr_truecolor_white_fg,
    38,
    foreground,
    255,
    255,
    255,
    "SGR 38;2;255;255;255 must produce Rgb(255,255,255)"
);
test_sgr_truecolor!(
    test_sgr_truecolor_white_bg,
    48,
    background,
    255,
    255,
    255,
    "SGR 48;2;255;255;255 must produce Rgb(255,255,255) background"
);

// ── Macro: test_sgr_unknown_noop ──────────────────────────────────────────────
//
// Generates a test verifying that an unrecognised SGR code is a no-op:
// a previously set flag must be unchanged and a color field must equal the
// expected value after the unknown code is sent.
//
// Usage:
// ```text
// test_sgr_unknown_noop!(test_name, setup_seq, unknown_seq,
//                        flag, flag_msg,
//                        color_field, color_val, color_msg)
// ```
macro_rules! test_sgr_unknown_noop {
    (
        $name:ident,
        $setup_seq:expr,
        $unknown_seq:expr,
        $flag:ident,
        $flag_msg:expr,
        $color_field:ident,
        $color_val:expr,
        $color_msg:expr
    ) => {
        #[test]
        fn $name() {
            let mut term = crate::TerminalCore::new(24, 80);
            term.advance($setup_seq);
            term.advance($unknown_seq);
            assert!(
                term.current_attrs.flags.contains(SgrFlags::$flag),
                $flag_msg
            );
            assert_eq!(term.current_attrs.$color_field, $color_val, $color_msg);
        }
    };
}

test_sgr_unknown_noop!(
    test_sgr_unknown_200_is_noop,
    b"\x1b[1m\x1b[32m", // BOLD on + green fg
    b"\x1b[200m",
    BOLD,
    "SGR 200 must not clear BOLD",
    foreground,
    crate::types::Color::Named(crate::types::NamedColor::Green),
    "SGR 200 must not alter foreground color"
);
test_sgr_unknown_noop!(
    test_sgr_unknown_150_is_noop,
    b"\x1b[3m", // ITALIC on
    b"\x1b[150m",
    ITALIC,
    "SGR 150 must not clear ITALIC",
    background,
    crate::types::Color::Default,
    "SGR 150 must not set background"
);

// ── Macro: test_sgr_all_named_colors ─────────────────────────────────────────
//
// Generates a loop test verifying all 8 named colors for a given SGR base code
// and color field.
//
// Usage:
// ```text
// test_sgr_all_named_colors!(test_name, base_code, field, "label")
// ```
macro_rules! test_sgr_all_named_colors {
    ($name:ident, $base:literal, $field:ident, $label:expr) => {
        #[test]
        fn $name() {
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
                let seq = format!("\x1b[{}m", $base + offset);
                term.advance(seq.as_bytes());
                assert_eq!(
                    term.current_attrs.$field,
                    crate::types::Color::Named(color),
                    "SGR {} must set {}[{}]",
                    $base + offset,
                    $label,
                    offset
                );
            }
        }
    };
}

test_sgr_all_named_colors!(test_sgr_all_normal_fg_colors_30_to_37, 30, foreground, "Fg");
test_sgr_all_named_colors!(test_sgr_all_normal_bg_colors_40_to_47, 40, background, "Bg");

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
