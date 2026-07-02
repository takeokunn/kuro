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

/// Assert that a default-color query queued exactly one well-formed response.
macro_rules! assert_osc_default_colors_response_contains {
    ($core:expr, $osc_num:expr, [$($fragment:expr),+ $(,)?], $message:expr) => {{
        let core = &$core;
        assert_eq!(core.pending_responses().len(), 1);
        let resp = std::str::from_utf8(&core.pending_responses()[0]).unwrap();
        let num_str = std::str::from_utf8($osc_num).unwrap();
        assert!(
            resp.contains(num_str),
            "response must contain OSC number {num_str}: got {resp:?}"
        );
        $(
            assert!(
                resp.contains($fragment),
                "{}: missing fragment {:?}; got {resp:?}",
                $message,
                $fragment
            );
        )+
    }};
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
            assert_osc_default_colors_response_contains!(
                core,
                $osc_num,
                ["rgb:"],
                "set query response must contain rgb: color spec"
            );
        }
    };
}

/// Generate a `handle_osc_default_colors` query test where the color is unset.
macro_rules! test_osc_default_colors_query_unset {
    ($name:ident, $osc_num:expr, $field:ident) => {
        #[test]
        fn $name() {
            let mut core = crate::TerminalCore::new(24, 80);
            let params: &[&[u8]] = &[$osc_num, b"?"];
            super::handle_osc_default_colors(&mut core, params);
            assert_osc_default_colors_response_contains!(
                core,
                $osc_num,
                ["8080"],
                concat!(
                    "unset ",
                    stringify!($field),
                    " query must respond with grey (0x8080)"
                )
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
            assert_osc_default_colors_response_contains!(
                core,
                $osc_num,
                ["rgb:", $expected],
                "round-trip query response must contain rgb: color spec and encoded value"
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

/// Generate a simple OSC 7 hostname preservation test.
macro_rules! test_osc_7_hostname {
    ($name:ident, $payload:expr, cwd $cwd:expr, host $host:expr) => {
        #[test]
        fn $name() {
            let mut core = make_core!();
            let params: &[&[u8]] = &[b"7", $payload];
            crate::parser::osc::handle_osc(&mut core, params, false);
            assert_eq!(core.osc_data().cwd.as_deref(), Some($cwd));
            assert_eq!(core.osc_data().cwd_host.as_deref(), $host);
        }
    };
}

/// Generate an OSC 7 host reset test that first stores a remote hostname.
macro_rules! test_osc_7_hostname_reset {
    ($name:ident, first $first:expr, second $second:expr, cwd $cwd:expr) => {
        #[test]
        fn $name() {
            let mut core = make_core!();
            let first_params: &[&[u8]] = &[b"7", $first];
            crate::parser::osc::handle_osc(&mut core, first_params, false);
            assert_eq!(core.osc_data().cwd_host.as_deref(), Some("remotehost"));

            let second_params: &[&[u8]] = &[b"7", $second];
            crate::parser::osc::handle_osc(&mut core, second_params, false);
            assert!(core.osc_data().cwd_host.is_none());
            assert_eq!(core.osc_data().cwd.as_deref(), Some($cwd));
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

/// Assert that `handle_osc_52` recorded exactly one action matching `pattern`.
macro_rules! assert_osc_52_action {
    ($core:expr, $pattern:pat $(if $guard:expr)? ) => {{
        use crate::types::osc::ClipboardAction;
        let actions = &$core.osc_data().clipboard_actions;
        assert_eq!(actions.len(), 1);
        assert!(matches!(&actions[0], $pattern $(if $guard)?));
    }};
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

/// Build a 1x1 PNG in memory and return it as base64.
macro_rules! test_1x1_png_b64 {
    ($color_type:expr, [$($pixel:expr),+ $(,)?]) => {{
        let mut buf: Vec<u8> = Vec::new();
        {
            let mut encoder = png::Encoder::new(&mut buf, 1, 1);
            encoder.set_color($color_type);
            encoder.set_depth(png::BitDepth::Eight);
            let mut writer = encoder.write_header().expect("PNG header");
            writer
                .write_image_data(&[$($pixel),+])
                .expect("PNG data");
        }
        crate::util::base64::encode(&buf)
    }};
}

pub(super) fn encode_empty_png_with_dimensions_b64(width: u32, height: u32) -> String {
    let mut bytes = Vec::new();
    bytes.extend_from_slice(b"\x89PNG\r\n\x1a\n");

    let mut ihdr = Vec::with_capacity(13);
    ihdr.extend_from_slice(&width.to_be_bytes());
    ihdr.extend_from_slice(&height.to_be_bytes());
    ihdr.extend_from_slice(&[8, 6, 0, 0, 0]);

    append_png_chunk(&mut bytes, b"IHDR", &ihdr);
    append_png_chunk(&mut bytes, b"IDAT", &[]);
    append_png_chunk(&mut bytes, b"IEND", &[]);
    crate::util::base64::encode(&bytes)
}

fn append_png_chunk(bytes: &mut Vec<u8>, name: &[u8; 4], data: &[u8]) {
    let data_len = u32::try_from(data.len()).expect("PNG test chunk length must fit u32");
    bytes.extend_from_slice(&data_len.to_be_bytes());
    bytes.extend_from_slice(name);
    bytes.extend_from_slice(data);

    let crc = png_crc32(name.iter().copied().chain(data.iter().copied()));
    bytes.extend_from_slice(&crc.to_be_bytes());
}

fn png_crc32(bytes: impl Iterator<Item = u8>) -> u32 {
    let mut crc = 0xffff_ffffu32;
    for byte in bytes {
        crc ^= u32::from(byte);
        for _ in 0..8 {
            let mask = 0u32.wrapping_sub(crc & 1);
            crc = (crc >> 1) ^ (0xedb8_8320 & mask);
        }
    }
    !crc
}

/// Construct a `TerminalCore` with the standard 24x80 grid.
macro_rules! make_core {
    () => {
        crate::TerminalCore::new(24, 80)
    };
}
