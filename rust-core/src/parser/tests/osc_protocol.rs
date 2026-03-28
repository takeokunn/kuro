//! Property-based and example-based tests for `osc_protocol` parsing.
//!
//! Module under test: `parser/osc_protocol.rs`
//! Tier: T3 — `ProptestConfig::with_cases(256)`

use super::*;

// ── Macros ───────────────────────────────────────────────────────────────────

/// Generate an `handle_osc_104` palette-reset test for a single valid index.
///
/// Pre-sets `palette[$idx]` to `$init`, calls `handle_osc_104` with that
/// index, and asserts the entry becomes `None` and `palette_dirty` is `true`.
macro_rules! test_osc_104_reset_index {
    ($name:ident, $idx:expr, $init:expr) => {
        #[test]
        fn $name() {
            use crate::TerminalCore;
            let mut core = TerminalCore::new(24, 80);
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
///
/// Pre-sets `core.osc_data.$field` to `Color::Rgb($r, $g, $b)`, sends the
/// query `params = [$osc_num, b"?"]`, and asserts:
/// - exactly one response is queued
/// - the response contains the OSC number string and `"rgb:"`
macro_rules! test_osc_default_colors_query_set {
    ($name:ident, $osc_num:expr, $field:ident, $r:expr, $g:expr, $b:expr) => {
        #[test]
        fn $name() {
            use crate::types::Color;
            use crate::TerminalCore;
            let mut core = TerminalCore::new(24, 80);
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

/// Generate an `encode_color_spec` test: call with `[$r, $g, $b]` and assert
/// the result equals `$expected`.
macro_rules! test_encode_color_spec {
    ($name:ident, [$r:expr, $g:expr, $b:expr], $expected:expr) => {
        #[test]
        fn $name() {
            let result = encode_color_spec([$r, $g, $b]);
            assert_eq!(result, $expected);
        }
    };
}

/// Generate a `parse_color_spec` success test: call with `$input` and assert
/// the result equals `Some([$r, $g, $b])`.
macro_rules! test_parse_color_spec_ok {
    ($name:ident, $input:expr, [$r:expr, $g:expr, $b:expr]) => {
        #[test]
        fn $name() {
            let result = parse_color_spec($input);
            assert_eq!(result, Some([$r, $g, $b]));
        }
    };
}

/// Generate a `parse_color_spec` failure test: call with `$input` and assert
/// the result is `None`.
macro_rules! test_parse_color_spec_none {
    ($name:ident, $input:expr) => {
        #[test]
        fn $name() {
            assert_eq!(parse_color_spec($input), None);
        }
    };
}

/// Generate a `handle_osc_133` prompt-mark test.
///
/// Sends the one-byte mark `$byte` (e.g. `b"A"`) and asserts that the single
/// recorded event carries the variant `PromptMark::$variant`.
macro_rules! test_osc_133_mark {
    ($name:ident, $byte:expr, $variant:ident) => {
        #[test]
        fn $name() {
            use crate::types::osc::PromptMark;
            use crate::TerminalCore;
            let mut core = TerminalCore::new(24, 80);
            let params: &[&[u8]] = &[b"133", $byte];
            super::handle_osc_133(&mut core, params);
            assert_eq!(core.osc_data().prompt_marks.len(), 1);
            assert_eq!(core.osc_data().prompt_marks[0].mark, PromptMark::$variant);
        }
    };
}

/// Generate a `handle_osc_default_colors` set test (OSC 10/11/12).
///
/// Sends `params = [osc_num, color_spec]`, then asserts:
/// - `$field` on `osc_data()` equals `Some(Color::Rgb($r, $g, $b))`
/// - `default_colors_dirty` is `true`
macro_rules! test_osc_default_colors_set {
    ($name:ident, $osc_num:expr, $spec:expr, $field:ident, $r:expr, $g:expr, $b:expr) => {
        #[test]
        fn $name() {
            use crate::types::Color;
            use crate::TerminalCore;
            let mut core = TerminalCore::new(24, 80);
            let params: &[&[u8]] = &[$osc_num, $spec];
            super::handle_osc_default_colors(&mut core, params);
            assert_eq!(core.osc_data().$field, Some(Color::Rgb($r, $g, $b)));
            assert!(core.osc_data().default_colors_dirty);
        }
    };
}

// ── encode_color_spec ────────────────────────────────────────────────────────

test_encode_color_spec!(
    test_encode_color_spec_basic_red,
    [255, 0, 0],
    "rgb:ffff/0000/0000"
);
test_encode_color_spec!(
    test_encode_color_spec_basic_green,
    [0, 255, 0],
    "rgb:0000/ffff/0000"
);
test_encode_color_spec!(
    test_encode_color_spec_basic_blue,
    [0, 0, 255],
    "rgb:0000/0000/ffff"
);
test_encode_color_spec!(
    test_encode_color_spec_black,
    [0, 0, 0],
    "rgb:0000/0000/0000"
);
test_encode_color_spec!(
    test_encode_color_spec_white,
    [255, 255, 255],
    "rgb:ffff/ffff/ffff"
);

#[test]
fn test_encode_color_spec_midrange() {
    // 0x80 -> 0x8080 in 16-bit expansion
    let result = encode_color_spec([0x80, 0x40, 0x20]);
    assert_eq!(result, "rgb:8080/4040/2020");
}

#[test]
fn test_encode_color_spec_format_has_three_channels() {
    let result = encode_color_spec([10, 20, 30]);
    let parts: Vec<&str> = result.strip_prefix("rgb:").unwrap().split('/').collect();
    assert_eq!(
        parts.len(),
        3,
        "encode_color_spec must produce three channels"
    );
    for part in &parts {
        assert_eq!(part.len(), 4, "each channel must be exactly 4 hex digits");
    }
}

// ── parse_color_spec ─────────────────────────────────────────────────────────

test_parse_color_spec_ok!(
    test_parse_color_spec_rgb_4digit,
    "rgb:ff00/8000/0000",
    [0xff, 0x80, 0x00]
);
test_parse_color_spec_ok!(
    test_parse_color_spec_rgb_2digit,
    "rgb:ff/80/00",
    [0xff, 0x80, 0x00]
);
test_parse_color_spec_ok!(
    test_parse_color_spec_hash_format,
    "#ff8000",
    [0xff, 0x80, 0x00]
);
test_parse_color_spec_ok!(test_parse_color_spec_hash_black, "#000000", [0, 0, 0]);
test_parse_color_spec_ok!(test_parse_color_spec_hash_white, "#ffffff", [255, 255, 255]);
test_parse_color_spec_ok!(
    test_parse_color_spec_leading_whitespace_trimmed,
    "  #ff0000",
    [255, 0, 0]
);

test_parse_color_spec_none!(test_parse_color_spec_invalid_returns_none, "notacolor");
test_parse_color_spec_none!(test_parse_color_spec_empty_returns_none, "");
test_parse_color_spec_none!(
    test_parse_color_spec_rgb_missing_channel_returns_none,
    "rgb:ff/80"
);
test_parse_color_spec_none!(test_parse_color_spec_hash_wrong_length_returns_none, "#fff");
test_parse_color_spec_none!(
    test_parse_color_spec_rgb_invalid_hex_returns_none,
    "rgb:zz/00/00"
);

// ── handle_osc_52 ─────────────────────────────────────────────────────────────

#[test]
fn test_handle_osc_52_write_clipboard() {
    use crate::types::osc::ClipboardAction;
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    // base64("hello") = "aGVsbG8="
    let params: &[&[u8]] = &[b"52", b"c", b"aGVsbG8="];
    super::handle_osc_52(&mut core, params);
    assert_eq!(core.osc_data().clipboard_actions.len(), 1);
    match &core.osc_data().clipboard_actions[0] {
        ClipboardAction::Write(s) => assert_eq!(s, "hello"),
        other @ ClipboardAction::Query => panic!("expected Write, got {other:?}"),
    }
}

#[test]
fn test_handle_osc_52_query_clipboard() {
    use crate::types::osc::ClipboardAction;
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"52", b"c", b"?"];
    super::handle_osc_52(&mut core, params);
    assert_eq!(core.osc_data().clipboard_actions.len(), 1);
    assert!(matches!(
        core.osc_data().clipboard_actions[0],
        ClipboardAction::Query
    ));
}

#[test]
fn test_handle_osc_52_missing_data_param_is_noop() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    // Only two params — no data at index 2
    let params: &[&[u8]] = &[b"52", b"c"];
    super::handle_osc_52(&mut core, params);
    assert!(core.osc_data().clipboard_actions.is_empty());
}

// ── handle_osc_104 ────────────────────────────────────────────────────────────

#[test]
fn test_handle_osc_104_reset_single_entry() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    // Pre-set palette entry 5
    core.osc_data.palette[5] = Some([255, 0, 0]);
    let params: &[&[u8]] = &[b"104", b"5"];
    super::handle_osc_104(&mut core, params);
    assert_eq!(core.osc_data().palette[5], None);
    assert!(core.osc_data().palette_dirty);
}

#[test]
fn test_handle_osc_104_reset_all_when_empty_arg() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    core.osc_data.palette[0] = Some([1, 2, 3]);
    core.osc_data.palette[255] = Some([4, 5, 6]);
    // Empty byte slice for index arg → reset all
    let params: &[&[u8]] = &[b"104", b""];
    super::handle_osc_104(&mut core, params);
    assert!(core
        .osc_data()
        .palette
        .iter()
        .all(std::option::Option::is_none));
    assert!(core.osc_data().palette_dirty);
}

#[test]
fn test_handle_osc_104_reset_all_when_no_arg() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    core.osc_data.palette[10] = Some([10, 20, 30]);
    // No index param at all
    let params: &[&[u8]] = &[b"104"];
    super::handle_osc_104(&mut core, params);
    assert!(core
        .osc_data()
        .palette
        .iter()
        .all(std::option::Option::is_none));
    assert!(core.osc_data().palette_dirty);
}

// ── handle_osc_133 ────────────────────────────────────────────────────────────

test_osc_133_mark!(test_handle_osc_133_prompt_start, b"A", PromptStart);
test_osc_133_mark!(test_handle_osc_133_prompt_end, b"B", PromptEnd);
test_osc_133_mark!(test_handle_osc_133_command_start, b"C", CommandStart);
test_osc_133_mark!(test_handle_osc_133_command_end, b"D", CommandEnd);

#[test]
fn test_handle_osc_133_unknown_mark_is_noop() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"133", b"Z"];
    super::handle_osc_133(&mut core, params);
    assert!(core.osc_data().prompt_marks.is_empty());
}

#[test]
fn test_handle_osc_133_missing_param_is_noop() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"133"];
    super::handle_osc_133(&mut core, params);
    assert!(core.osc_data().prompt_marks.is_empty());
}

#[test]
fn test_handle_osc_133_mark_records_cursor_position() {
    use crate::types::osc::PromptMark;
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    // Move cursor to a known position before emitting the mark
    core.advance(b"\x1b[5;10H"); // row 5, col 10 (1-based → 4, 9 zero-based)
    let params: &[&[u8]] = &[b"133", b"A"];
    super::handle_osc_133(&mut core, params);
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(ev.mark, PromptMark::PromptStart);
    // cursor row/col must be captured at call time
    assert_eq!(ev.row, 4);
    assert_eq!(ev.col, 9);
}

// ── handle_osc_default_colors ─────────────────────────────────────────────────

test_osc_default_colors_set!(
    test_handle_osc_default_colors_set_fg,
    b"10",
    b"#ff8000",
    default_fg,
    0xff,
    0x80,
    0x00
);
test_osc_default_colors_set!(
    test_handle_osc_default_colors_set_bg,
    b"11",
    b"#001122",
    default_bg,
    0x00,
    0x11,
    0x22
);
test_osc_default_colors_set!(
    test_handle_osc_default_colors_set_cursor_color,
    b"12",
    b"#aabbcc",
    cursor_color,
    0xaa,
    0xbb,
    0xcc
);

// Query tests for OSC 10/11/12 when color IS set — generated by
// `test_osc_default_colors_query_set!`.
test_osc_default_colors_query_set!(
    test_handle_osc_default_colors_query_fg_produces_response,
    b"10",
    default_fg,
    255,
    0,
    0
);

include!("osc_protocol_colors.rs");
include!("osc_protocol_coverage.rs");
