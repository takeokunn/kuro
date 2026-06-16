/// Generate an `handle_osc_104` palette-reset test for a single valid index.
macro_rules! test_osc_104_reset_index {
    ($name:ident, $idx:expr, $init:expr) => {
        #[test]
        fn $name() {
            let mut core = crate::TerminalCore::new(24, 80);
            core.osc_data.palette[$idx] = Some($init);
            let idx_str = stringify!($idx);
            let params: &[&[u8]] = &[b"104", idx_str.as_bytes()];
            super::handle_osc_104(&mut core, params);
            assert_eq!(
                core.osc_data().palette[$idx],
                None,
                concat!("palette index ", stringify!($idx), " must be reset to None")
            );
            assert!(core.osc_data().palette_dirty);
        }
    };
}

/// Generate a `handle_osc_default_colors` query test where the color IS set.
macro_rules! test_osc_default_colors_query_set {
    ($name:ident, $osc_num:expr, $field:ident, $r:expr, $g:expr, $b:expr) => {
        #[test]
        fn $name() {
            use crate::types::Color;
            let mut core = crate::TerminalCore::new(24, 80);
            core.osc_data.$field = Some(Color::Rgb($r, $g, $b));
            let params: &[&[u8]] = &[$osc_num, b"?"];
            super::handle_osc_default_colors(&mut core, params);
            assert_eq!(core.pending_responses().len(), 1);
            let resp = std::str::from_utf8(&core.pending_responses()[0]).unwrap();
            let num_str = std::str::from_utf8($osc_num).unwrap();
            assert!(
                resp.contains(num_str),
                "response must contain OSC number {num_str}: got {resp:?}"
            );
            assert!(
                resp.contains("rgb:"),
                "response must contain rgb: color spec: got {resp:?}"
            );
        }
    };
}

/// Generate an `encode_color_spec` test.
macro_rules! test_encode_color_spec {
    ($name:ident, [$r:expr, $g:expr, $b:expr], $expected:expr) => {
        #[test]
        fn $name() {
            let result = encode_color_spec([$r, $g, $b]);
            assert_eq!(result, $expected);
        }
    };
}

/// Generate a `parse_color_spec` success test.
macro_rules! test_parse_color_spec_ok {
    ($name:ident, $input:expr, [$r:expr, $g:expr, $b:expr]) => {
        #[test]
        fn $name() {
            let result = parse_color_spec($input);
            assert_eq!(result, Some([$r, $g, $b]));
        }
    };
}

/// Generate a `parse_color_spec` failure test.
macro_rules! test_parse_color_spec_none {
    ($name:ident, $input:expr) => {
        #[test]
        fn $name() {
            assert_eq!(parse_color_spec($input), None);
        }
    };
}

/// Generate a `handle_osc_133` prompt-mark test.
macro_rules! test_osc_133_mark {
    ($name:ident, $byte:expr, $variant:ident) => {
        #[test]
        fn $name() {
            use crate::types::osc::PromptMark;
            let mut core = crate::TerminalCore::new(24, 80);
            let params: &[&[u8]] = &[b"133", $byte];
            super::handle_osc_133(&mut core, params);
            assert_eq!(core.osc_data().prompt_marks.len(), 1);
            assert_eq!(core.osc_data().prompt_marks[0].mark, PromptMark::$variant);
        }
    };
}

/// Generate an `handle_osc_133` `CommandEnd` exit-code test.
macro_rules! test_osc_133_exit_code {
    ($name:ident, $code_bytes:expr, $expected:expr) => {
        #[test]
        fn $name() {
            use crate::types::osc::PromptMark;
            let mut core = crate::TerminalCore::new(24, 80);
            let params: &[&[u8]] = &[b"133", b"D", $code_bytes];
            super::handle_osc_133(&mut core, params);
            assert_eq!(core.osc_data().prompt_marks.len(), 1);
            let ev = &core.osc_data().prompt_marks[0];
            assert_eq!(ev.mark, PromptMark::CommandEnd);
            assert_eq!(ev.exit_code, $expected);
        }
    };
}

/// Generate a `handle_osc_default_colors` set test.
macro_rules! test_osc_default_colors_set {
    ($name:ident, $osc_num:expr, $spec:expr, $field:ident, $r:expr, $g:expr, $b:expr) => {
        #[test]
        fn $name() {
            use crate::types::Color;
            let mut core = crate::TerminalCore::new(24, 80);
            let params: &[&[u8]] = &[$osc_num, $spec];
            super::handle_osc_default_colors(&mut core, params);
            assert_eq!(core.osc_data().$field, Some(Color::Rgb($r, $g, $b)));
            assert!(core.osc_data().default_colors_dirty);
        }
    };
}

/// Generate a `handle_osc_default_colors` set-then-query round-trip test.
macro_rules! test_osc_default_colors_set_then_query {
    ($name:ident, $osc_num:expr, $spec:expr, $field:ident, $r:expr, $g:expr, $b:expr, $expected:expr) => {
        #[test]
        fn $name() {
            use crate::types::Color;
            let mut core = crate::TerminalCore::new(24, 80);
            let set_params: &[&[u8]] = &[$osc_num, $spec];
            super::handle_osc_default_colors(&mut core, set_params);
            assert_eq!(core.osc_data().$field, Some(Color::Rgb($r, $g, $b)));
            assert!(core.osc_data().default_colors_dirty);

            let query_params: &[&[u8]] = &[$osc_num, b"?"];
            super::handle_osc_default_colors(&mut core, query_params);
            assert_eq!(core.pending_responses().len(), 1);
            let resp = std::str::from_utf8(&core.pending_responses()[0]).unwrap();
            let num_str = std::str::from_utf8($osc_num).unwrap();
            assert!(
                resp.contains(num_str),
                "response must contain OSC number {num_str}: got {resp:?}"
            );
            assert!(
                resp.contains("rgb:"),
                "response must contain rgb: color spec: got {resp:?}"
            );
            assert!(
                resp.contains($expected),
                "round-trip response must contain encoded value {expected}: got {resp:?}",
                expected = $expected
            );
        }
    };
}

/// Generate a `parse_iterm2_params` test that checks all three output fields.
macro_rules! test_iterm2_params {
    ($name:ident, input $input:expr, inline $inline:expr, cols $cols:expr, rows $rows:expr) => {
        #[test]
        fn $name() {
            let p = super::parse_iterm2_params($input);
            assert_eq!(p.inline, $inline);
            assert_eq!(p.display_cols, $cols);
            assert_eq!(p.display_rows, $rows);
        }
    };
}

/// Generate a `decode_iterm2_image` test asserting the result is `None`.
macro_rules! test_decode_iterm2_none {
    ($name:ident, $input:expr) => {
        #[test]
        fn $name() {
            assert!(super::decode_iterm2_image($input).is_none());
        }
    };
}

/// Generate an `handle_osc_1337` noop test.
macro_rules! test_osc_1337_noop {
    ($name:ident, $params_expr:expr) => {
        #[test]
        fn $name() {
            let mut core = make_core!();
            let params: &[&[u8]] = $params_expr;
            super::handle_osc_1337(&mut core, params);
            assert_eq!(core.osc_data().clipboard_actions.len(), 0);
        }
    };
}

/// Generate an `handle_osc_52` noop test.
macro_rules! test_osc_52_clipboard_empty {
    ($name:ident, $params_expr:expr, $msg:expr) => {
        #[test]
        fn $name() {
            let mut core = make_core!();
            let params: &[&[u8]] = $params_expr;
            super::handle_osc_52(&mut core, params);
            assert!(core.osc_data().clipboard_actions.is_empty(), $msg);
        }
    };
}

/// Generate a `parse_iterm2_params` zero-dimension test.
macro_rules! test_iterm2_param_zero_is_none {
    ($name:ident, input $input:expr, field $field:ident) => {
        #[test]
        fn $name() {
            let p = super::parse_iterm2_params($input);
            assert_eq!(p.$field, None);
        }
    };
}

/// Generate an `encode_color_spec` -> `parse_color_spec` round-trip test.
macro_rules! test_roundtrip_color {
    ($name:ident, [$r:expr, $g:expr, $b:expr]) => {
        #[test]
        fn $name() {
            let encoded = encode_color_spec([$r, $g, $b]);
            assert_eq!(parse_color_spec(&encoded), Some([$r, $g, $b]));
        }
    };
}

/// Generate an `handle_osc_104` bad-param no-change test.
macro_rules! test_osc_104_bad_param_no_change {
    ($name:ident, idx $idx:expr, initial $initial:expr, params $params_expr:expr, msg $msg:expr) => {
        #[test]
        fn $name() {
            let mut core = make_core!();
            core.osc_data.palette[$idx] = Some($initial);
            let params: &[&[u8]] = $params_expr;
            super::handle_osc_104(&mut core, params);
            assert_eq!(core.osc_data().palette[$idx], Some($initial), $msg);
            assert!(core.osc_data().palette_dirty);
        }
    };
}

/// Construct a `TerminalCore` with the standard 24x80 grid.
macro_rules! make_core {
    () => {
        crate::TerminalCore::new(24, 80)
    };
}
