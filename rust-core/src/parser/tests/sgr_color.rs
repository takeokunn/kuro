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


include!("sgr_color_edge_cases.rs");
