/// Generate a turn-on / turn-off pair for an SGR flag attribute.
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
            assert!(
                term.current_attrs
                    .flags
                    .contains(crate::types::cell::SgrFlags::$flag)
            );
        }

        #[test]
        fn $off_name() {
            let mut term = crate::TerminalCore::new(24, 80);
            term.advance($on_seq);
            assert!(
                term.current_attrs
                    .flags
                    .contains(crate::types::cell::SgrFlags::$flag)
            );
            term.advance($off_seq);
            assert!(
                !term
                    .current_attrs
                    .flags
                    .contains(crate::types::cell::SgrFlags::$flag),
                $off_msg
            );
        }
    };
}

/// Apply a single SGR sequence and assert a color field equals the expected value.
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

/// Verify all 8 bright foreground or background SGR codes in one loop.
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

/// Generate a test that sets a named color then verifies explicit reset.
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

/// Generate foreground and background tests for a 256-color indexed sequence.
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

/// Generate a truecolor SGR sequence test.
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

/// Generate a test verifying that an unrecognised SGR code is a no-op.
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
                term.current_attrs
                    .flags
                    .contains(crate::types::cell::SgrFlags::$flag),
                $flag_msg
            );
            assert_eq!(term.current_attrs.$color_field, $color_val, $color_msg);
        }
    };
}

/// Verify all 8 named colors for a given SGR base code and color field.
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
