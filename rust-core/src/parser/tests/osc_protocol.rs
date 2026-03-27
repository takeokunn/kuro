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

// ── handle_osc_default_colors (extended) ──────────────────────────────────────

test_osc_default_colors_query_set!(
    test_handle_osc_default_colors_query_bg_produces_response,
    b"11",
    default_bg,
    0,
    255,
    0
);

#[test]
fn test_handle_osc_default_colors_invalid_color_spec_is_noop() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"10", b"notacolor"];
    super::handle_osc_default_colors(&mut core, params);
    assert!(core.osc_data().default_fg.is_none());
    assert!(!core.osc_data().default_colors_dirty);
}

#[test]
fn test_handle_osc_default_colors_missing_spec_is_noop() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    // Only one param — no color spec at index 1
    let params: &[&[u8]] = &[b"10"];
    super::handle_osc_default_colors(&mut core, params);
    assert!(core.osc_data().default_fg.is_none());
    assert!(core.pending_responses().is_empty());
}

#[test]
fn test_handle_osc_default_colors_query_unset_produces_grey_response() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    // default_fg is None — query must respond with the fallback grey (128, 128, 128)
    let params: &[&[u8]] = &[b"10", b"?"];
    super::handle_osc_default_colors(&mut core, params);
    assert_eq!(core.pending_responses().len(), 1);
    let resp = std::str::from_utf8(&core.pending_responses()[0]).unwrap();
    // rgb:8080/8080/8080 is the expected grey spec for (128, 128, 128)
    assert!(
        resp.contains("8080"),
        "unset fg query must respond with grey (0x8080)"
    );
}

// ── handle_osc_52 (extended) ──────────────────────────────────────────────────

#[test]
fn test_handle_osc_52_invalid_base64_is_noop() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    // "!!!" is not valid base64 — must be silently ignored
    let params: &[&[u8]] = &[b"52", b"c", b"!!!"];
    super::handle_osc_52(&mut core, params);
    assert!(core.osc_data().clipboard_actions.is_empty());
}

#[test]
fn test_handle_osc_52_non_utf8_payload_is_noop() {
    use crate::TerminalCore;
    // base64 encode some invalid UTF-8 bytes: [0xFF, 0xFE]
    // base64("/w==") would work, but let's use a known non-UTF8 payload
    let mut core = TerminalCore::new(24, 80);
    // base64 of [0xFF] is "/w=="
    let params: &[&[u8]] = &[b"52", b"c", b"/w=="];
    super::handle_osc_52(&mut core, params);
    assert!(
        core.osc_data().clipboard_actions.is_empty(),
        "non-UTF8 clipboard payload must be ignored"
    );
}

// ── handle_osc_1337 ───────────────────────────────────────────────────────────

#[test]
fn test_handle_osc_1337_non_file_prefix_is_noop() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    // Payload does not start with "File=" — should be silently ignored
    let params: &[&[u8]] = &[b"1337", b"SetBadge=:aGVsbG8="];
    super::handle_osc_1337(&mut core, params);
    // No image placements stored
    assert_eq!(core.osc_data().clipboard_actions.len(), 0);
}

#[test]
fn test_handle_osc_1337_missing_param_is_noop() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    // No second param
    let params: &[&[u8]] = &[b"1337"];
    super::handle_osc_1337(&mut core, params);
    assert_eq!(core.osc_data().clipboard_actions.len(), 0);
}

// ── parse_iterm2_params ────────────────────────────────────────────────────────

#[test]
fn test_parse_iterm2_params_empty_string() {
    let p = super::parse_iterm2_params("");
    assert!(!p.inline);
    assert_eq!(p.display_cols, None);
    assert_eq!(p.display_rows, None);
}

#[test]
fn test_parse_iterm2_params_inline_one() {
    let p = super::parse_iterm2_params("inline=1");
    assert!(p.inline);
    assert_eq!(p.display_cols, None);
    assert_eq!(p.display_rows, None);
}

#[test]
fn test_parse_iterm2_params_inline_zero() {
    let p = super::parse_iterm2_params("inline=0");
    assert!(!p.inline);
}

#[test]
fn test_parse_iterm2_params_width_plain() {
    let p = super::parse_iterm2_params("inline=1;width=40");
    assert_eq!(p.display_cols, Some(40));
}

#[test]
fn test_parse_iterm2_params_width_px_suffix() {
    let p = super::parse_iterm2_params("inline=1;width=320px");
    assert_eq!(p.display_cols, Some(320));
}

#[test]
fn test_parse_iterm2_params_width_percent_suffix() {
    let p = super::parse_iterm2_params("width=50%");
    assert_eq!(p.display_cols, Some(50));
}

#[test]
fn test_parse_iterm2_params_height_plain() {
    let p = super::parse_iterm2_params("inline=1;height=10");
    assert_eq!(p.display_rows, Some(10));
}

#[test]
fn test_parse_iterm2_params_width_zero_becomes_none() {
    // width=0 is treated as "auto" (None)
    let p = super::parse_iterm2_params("inline=1;width=0");
    assert_eq!(p.display_cols, None);
}

#[test]
fn test_parse_iterm2_params_height_zero_becomes_none() {
    let p = super::parse_iterm2_params("inline=1;height=0");
    assert_eq!(p.display_rows, None);
}

#[test]
fn test_parse_iterm2_params_unknown_keys_ignored() {
    let p = super::parse_iterm2_params("inline=1;name=foo.png;size=1234;preserveAspectRatio=1");
    assert!(p.inline);
    assert_eq!(p.display_cols, None);
    assert_eq!(p.display_rows, None);
}

#[test]
fn test_parse_iterm2_params_all_fields() {
    let p = super::parse_iterm2_params("inline=1;width=20;height=5");
    assert!(p.inline);
    assert_eq!(p.display_cols, Some(20));
    assert_eq!(p.display_rows, Some(5));
}

// ── decode_iterm2_image ────────────────────────────────────────────────────────

#[test]
fn test_decode_iterm2_image_empty_returns_none() {
    assert!(super::decode_iterm2_image("").is_none());
}

#[test]
fn test_decode_iterm2_image_invalid_base64_returns_none() {
    assert!(super::decode_iterm2_image("!!!notbase64!!!").is_none());
}

#[test]
fn test_decode_iterm2_image_valid_base64_non_png_returns_none() {
    // Valid base64 of "hello" — not a PNG
    assert!(super::decode_iterm2_image("aGVsbG8=").is_none());
}

#[test]
fn test_decode_iterm2_image_valid_png_returns_dimensions() {
    // Minimal 1×1 red RGBA PNG (base64 encoded).
    // Generated via Python: zlib.compress([filter=0, R=255, G=0, B=0, A=255]),
    // IHDR: 1×1, bit_depth=8, color_type=6 (RGBA).
    let png_b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==";
    let result = super::decode_iterm2_image(png_b64);
    assert!(result.is_some(), "valid PNG must decode successfully");
    let (pixels, w, h) = result.unwrap();
    assert_eq!(w, 1);
    assert_eq!(h, 1);
    // Output is always RGBA (4 bytes per pixel)
    assert_eq!(pixels.len(), 4);
}

// ── handle_osc_1337 dispatch ───────────────────────────────────────────────────

#[test]
fn test_handle_osc_1337_no_colon_separator_is_noop() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    // "File=" prefix but no ':' separator
    let params: &[&[u8]] = &[b"1337", b"File=inline=1"];
    super::handle_osc_1337(&mut core, params);
    // No crash; no side effects on clipboard
    assert_eq!(core.osc_data().clipboard_actions.len(), 0);
}

#[test]
fn test_handle_osc_1337_not_inline_is_noop() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    // inline=0 — image should NOT be stored
    let params: &[&[u8]] = &[b"1337", b"File=inline=0:aGVsbG8="];
    super::handle_osc_1337(&mut core, params);
    assert_eq!(core.osc_data().clipboard_actions.len(), 0);
}

// ── parse_color_spec overlong channel ─────────────────────────────────────────

#[test]
fn test_parse_color_spec_rgb_overlong_channel_returns_none() {
    // "ffffff" is 6 hex digits — u16::from_str_radix("ffffff", 16) = 0xffffff
    // which overflows u16 (max 0xffff), so from_str_radix returns Err and ? propagates None.
    assert_eq!(parse_color_spec("rgb:ffffff/00/00"), None);
}

// ── round-trip ────────────────────────────────────────────────────────────────

#[test]
fn test_roundtrip_encode_then_parse() {
    let original = [0xde, 0xad, 0xbe];
    let encoded = encode_color_spec(original);
    // encode produces 4-digit channels; parse takes upper 8 bits
    let parsed = parse_color_spec(&encoded).expect("round-trip must parse successfully");
    assert_eq!(
        parsed, original,
        "encode -> parse round-trip must recover original RGB"
    );
}

#[test]
fn test_roundtrip_black() {
    let encoded = encode_color_spec([0, 0, 0]);
    assert_eq!(parse_color_spec(&encoded), Some([0, 0, 0]));
}

#[test]
fn test_roundtrip_white() {
    let encoded = encode_color_spec([255, 255, 255]);
    assert_eq!(parse_color_spec(&encoded), Some([255, 255, 255]));
}

// ── handle_osc_52 (size cap) ──────────────────────────────────────────────────

#[test]
fn test_handle_osc_52_oversized_payload_is_noop() {
    use crate::TerminalCore;
    // Payload exceeds 1MB cap (1_048_576 + 1 bytes).
    // The data itself is not valid base64, but the size guard fires first.
    let mut core = TerminalCore::new(24, 80);
    let oversized = vec![b'A'; 1_048_577];
    let params: &[&[u8]] = &[b"52", b"c", &oversized];
    super::handle_osc_52(&mut core, params);
    assert!(
        core.osc_data().clipboard_actions.is_empty(),
        "payload over 1MB must be rejected without any action"
    );
}

#[test]
fn test_handle_osc_52_exactly_at_size_cap_is_accepted_or_rejected_without_panic() {
    use crate::TerminalCore;
    // Exactly 1MB of valid base64 ('A' chars decode fine).
    // The handler accepts payloads with len <= 1_048_576.
    // "AAAA" decodes to [0, 0, 0] — we just verify no panic.
    let mut core = TerminalCore::new(24, 80);
    let at_cap = vec![b'A'; 1_048_576];
    let params: &[&[u8]] = &[b"52", b"c", &at_cap];
    super::handle_osc_52(&mut core, params);
    // No assertion on clipboard_actions — the decoded bytes may or may not be valid UTF-8.
    // The key invariant is that it does not panic.
}

#[test]
fn test_handle_osc_52_empty_data_is_noop() {
    use crate::TerminalCore;
    // Zero-length data at index 2 is not "?" and not valid base64 text.
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"52", b"c", b""];
    super::handle_osc_52(&mut core, params);
    // Empty string is a valid base64 input that decodes to zero bytes,
    // which produces an empty String — so Write("") is pushed.
    // Either way, we verify no panic and the result is consistent.
    // (An empty clipboard write is valid per the protocol.)
    let actions = &core.osc_data().clipboard_actions;
    // If pushed, it must be Write("") — not Query.
    if let Some(action) = actions.first() {
        use crate::types::osc::ClipboardAction;
        assert!(
            matches!(action, ClipboardAction::Write(s) if s.is_empty()),
            "empty data must produce Write(\"\") if anything"
        );
    }
}

// ── handle_osc_104 (out-of-range index) ───────────────────────────────────────

#[test]
fn test_handle_osc_104_out_of_range_index_is_noop() {
    use crate::TerminalCore;
    // Index 256 is out of range (valid indices are 0..=255).
    let mut core = TerminalCore::new(24, 80);
    core.osc_data.palette[0] = Some([1, 2, 3]);
    let params: &[&[u8]] = &[b"104", b"256"];
    super::handle_osc_104(&mut core, params);
    // Palette entry 0 must be untouched; palette_dirty must be set
    // (the handler always sets palette_dirty regardless of whether it modified any entry).
    assert_eq!(
        core.osc_data().palette[0],
        Some([1, 2, 3]),
        "palette entry 0 must be untouched for out-of-range index 256"
    );
    assert!(
        core.osc_data().palette_dirty,
        "palette_dirty must be set even when index is out of range"
    );
}

#[test]
fn test_handle_osc_104_index_255_boundary() {
    use crate::TerminalCore;
    // Index 255 is the last valid palette slot.
    let mut core = TerminalCore::new(24, 80);
    core.osc_data.palette[255] = Some([200, 100, 50]);
    let params: &[&[u8]] = &[b"104", b"255"];
    super::handle_osc_104(&mut core, params);
    assert_eq!(
        core.osc_data().palette[255],
        None,
        "index 255 is valid and must be reset to None"
    );
    assert!(core.osc_data().palette_dirty);
}

#[test]
fn test_handle_osc_104_non_numeric_index_is_noop() {
    use crate::TerminalCore;
    // Non-numeric index string: parse::<usize>() fails, handler does nothing.
    let mut core = TerminalCore::new(24, 80);
    core.osc_data.palette[1] = Some([9, 8, 7]);
    let params: &[&[u8]] = &[b"104", b"abc"];
    super::handle_osc_104(&mut core, params);
    assert_eq!(
        core.osc_data().palette[1],
        Some([9, 8, 7]),
        "non-numeric index must leave palette unchanged"
    );
    // palette_dirty is still set by the function regardless.
    assert!(core.osc_data().palette_dirty);
}

// ── handle_osc_133 (empty mark byte) ─────────────────────────────────────────

#[test]
fn test_handle_osc_133_empty_mark_is_noop() {
    use crate::TerminalCore;
    // Param exists but is an empty byte slice — first() returns None.
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"133", b""];
    super::handle_osc_133(&mut core, params);
    assert!(
        core.osc_data().prompt_marks.is_empty(),
        "empty mark byte must produce no prompt mark event"
    );
}

// ── handle_osc_default_colors (OSC 12 query, unknown OSC number) ──────────────

test_osc_default_colors_query_set!(
    test_handle_osc_default_colors_query_cursor_color_produces_response,
    b"12",
    cursor_color,
    0,
    0,
    255
);

#[test]
fn test_handle_osc_default_colors_unknown_osc_number_set_changes_no_color() {
    use crate::TerminalCore;
    // OSC number "99" is not 10/11/12 — the `_ => {}` match arm fires, so no
    // color field is written.  However, `default_colors_dirty` is set
    // unconditionally inside `if let Some([r,g,b])` once the color spec parses,
    // which is the existing behavior.
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"99", b"#ff0000"];
    super::handle_osc_default_colors(&mut core, params);
    assert!(
        core.osc_data().default_fg.is_none(),
        "unknown OSC must not set default_fg"
    );
    assert!(
        core.osc_data().default_bg.is_none(),
        "unknown OSC must not set default_bg"
    );
    assert!(
        core.osc_data().cursor_color.is_none(),
        "unknown OSC must not set cursor_color"
    );
    // default_colors_dirty is set by the current implementation after any valid
    // color-spec parse, even for unknown OSC numbers.
    assert!(core.osc_data().default_colors_dirty);
}

#[test]
fn test_handle_osc_default_colors_unknown_osc_number_query_is_noop() {
    use crate::TerminalCore;
    // OSC number "99" with query — the `_ => return` branch fires; no response pushed.
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"99", b"?"];
    super::handle_osc_default_colors(&mut core, params);
    assert!(
        core.pending_responses().is_empty(),
        "unknown OSC number query must push no response"
    );
}

#[test]
fn test_handle_osc_default_colors_query_unset_cursor_color_responds_grey() {
    use crate::TerminalCore;
    // cursor_color is None — query must respond with fallback grey (128, 128, 128).
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"12", b"?"];
    super::handle_osc_default_colors(&mut core, params);
    assert_eq!(core.pending_responses().len(), 1);
    let resp = std::str::from_utf8(&core.pending_responses()[0]).unwrap();
    assert!(
        resp.contains("8080"),
        "unset cursor color query must respond with grey (0x8080): got {resp:?}"
    );
}

// ── New edge-case tests ────────────────────────────────────────────────────────

/// `parse_color_spec` with 1-digit channels treats them as ≤2-digit (value used directly).
///
/// The `normalize` function uses `digits > 2` to decide between 4-digit (shift-right-8)
/// and short-form (direct) modes, so "f" → `u16 = 15` → `15 as u8`.
#[test]
fn test_parse_color_spec_rgb_single_digit_channel_direct_value() {
    // 1-digit channels: digits ≤ 2, so value is used directly without shifting.
    // "f" = 0x0F = 15, "8" = 8, "0" = 0
    assert_eq!(parse_color_spec("rgb:f/8/0"), Some([15, 8, 0]));
}

/// `parse_color_spec` with 3-digit channels treats them as >2-digit (upper 8 bits used).
///
/// The `normalize` function uses `digits > 2`, so 3-digit "fff" → `u16 = 0x0FFF` →
/// `(0x0FFF >> 8) as u8 = 0x0F = 15`.
#[test]
fn test_parse_color_spec_rgb_3digit_channel_uses_upper_byte() {
    // 3-digit channels: digits > 2, so upper 8 bits are taken.
    // "fff" = 0x0FFF → 0x0FFF >> 8 = 0x0F = 15; "000" → 0
    assert_eq!(parse_color_spec("rgb:fff/000/000"), Some([15, 0, 0]));
}

// Palette boundary reset tests — generated by `test_osc_104_reset_index!`.
// index 0: first ANSI color
test_osc_104_reset_index!(test_handle_osc_104_index_0_boundary, 0, [10, 20, 30]);
// index 16: first 256-color cube entry
test_osc_104_reset_index!(test_handle_osc_104_index_16_boundary, 16, [0, 0, 0]);
// index 231: last 6×6×6 color cube entry
test_osc_104_reset_index!(test_handle_osc_104_index_231_boundary, 231, [255, 255, 255]);
// index 232: first greyscale-ramp entry
test_osc_104_reset_index!(test_handle_osc_104_index_232_boundary, 232, [8, 8, 8]);

/// Prompt mark at cursor row 0 (top-left boundary).
#[test]
fn test_handle_osc_133_mark_records_row_zero() {
    use crate::types::osc::PromptMark;
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    // Cursor starts at (0, 0) after construction — no CUP needed.
    let params: &[&[u8]] = &[b"133", b"A"];
    super::handle_osc_133(&mut core, params);
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(ev.mark, PromptMark::PromptStart);
    assert_eq!(ev.row, 0, "row must be 0 at top-left boundary");
    assert_eq!(ev.col, 0, "col must be 0 at top-left boundary");
}

/// `encode_color_spec` on a single-component boundary value: only the blue
/// channel is non-zero, with value 1 (the lowest non-zero 8-bit value).
#[test]
fn test_encode_color_spec_single_component_min_nonzero() {
    // 0x01 expands to 0x0101 in 16-bit
    let result = encode_color_spec([0, 0, 1]);
    assert_eq!(result, "rgb:0000/0000/0101");
}

use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    // PANIC SAFETY: OSC 133 (prompt mark) with any mark type string never panics
    fn prop_osc133_mark_no_panic(
        mark in prop_oneof![Just("A"), Just("B"), Just("C"), Just("D"), Just("Z")]
    ) {
        let mut term = crate::TerminalCore::new(24, 80);
        let seq = format!("\x1b]133;{mark}\x07");
        term.advance(seq.as_bytes());
        prop_assert!(term.screen.cursor().row < 24);
    }

    #[test]
    // PANIC SAFETY: OSC 7 (cwd) with arbitrary URI never panics
    fn prop_osc7_arbitrary_uri_no_panic(
        path in proptest::collection::vec(b'a'..=b'z', 1..=50)
    ) {
        let mut term = crate::TerminalCore::new(24, 80);
        let path_str = String::from_utf8(path).unwrap_or_default();
        let seq = format!("\x1b]7;file://localhost/{path_str}\x07");
        term.advance(seq.as_bytes());
        prop_assert!(term.screen.cursor().row < 24);
    }

    #[test]
    // PANIC SAFETY: OSC 1337 with arbitrary payload never panics
    fn prop_osc1337_no_panic(
        payload in proptest::collection::vec(b'a'..=b'z', 0..=50)
    ) {
        let mut term = crate::TerminalCore::new(24, 80);
        let p = String::from_utf8(payload).unwrap_or_default();
        let seq = format!("\x1b]1337;{p}\x07");
        term.advance(seq.as_bytes());
        prop_assert!(term.screen.cursor().row < 24);
    }
}

// ── New coverage tests (Round 30) ─────────────────────────────────────────────

/// `parse_color_spec` must trim trailing whitespace (`.trim()` handles both sides).
#[test]
fn test_parse_color_spec_trailing_whitespace_trimmed() {
    assert_eq!(parse_color_spec("#ff0000  "), Some([255, 0, 0]));
}

/// `parse_color_spec` must trim leading AND trailing whitespace simultaneously.
#[test]
fn test_parse_color_spec_leading_and_trailing_whitespace_trimmed() {
    assert_eq!(parse_color_spec("  #00ff00  "), Some([0, 255, 0]));
}

/// `parse_color_spec` must trim whitespace for `rgb:` prefix too.
#[test]
fn test_parse_color_spec_rgb_trailing_whitespace_trimmed() {
    assert_eq!(parse_color_spec("rgb:ff/00/00 "), Some([0xff, 0x00, 0x00]));
}

/// `parse_iterm2_params` must strip `px` suffix from height values.
#[test]
fn test_parse_iterm2_params_height_px_suffix() {
    let p = super::parse_iterm2_params("inline=1;height=48px");
    assert_eq!(
        p.display_rows,
        Some(48),
        "height=48px must strip 'px' and parse to 48"
    );
}

/// `parse_iterm2_params` must strip `%` suffix from height values.
#[test]
fn test_parse_iterm2_params_height_percent_suffix() {
    let p = super::parse_iterm2_params("inline=1;height=25%");
    assert_eq!(
        p.display_rows,
        Some(25),
        "height=25% must strip '%' and parse to 25"
    );
}

/// `handle_osc_default_colors` must accept a 4-digit `rgb:` spec for OSC 10.
///
/// This exercises the `parse_color_spec` → `rgb:RRRR/GGGG/BBBB` branch when
/// called from `handle_osc_default_colors`.
#[test]
fn test_handle_osc_default_colors_set_fg_via_rgb_4digit() {
    use crate::types::Color;
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    // "rgb:ff00/8000/0000" → R=0xff, G=0x80, B=0x00 (upper 8 bits of each channel)
    let params: &[&[u8]] = &[b"10", b"rgb:ff00/8000/0000"];
    super::handle_osc_default_colors(&mut core, params);
    assert_eq!(
        core.osc_data().default_fg,
        Some(Color::Rgb(0xff, 0x80, 0x00)),
        "4-digit rgb: spec must set default_fg correctly"
    );
    assert!(core.osc_data().default_colors_dirty);
}

/// `decode_iterm2_image` must decode a 1×1 RGB PNG and convert it to RGBA.
///
/// The `osc_protocol.rs` implementation converts any non-RGBA PNG to RGBA
/// (the `_ => ImageFormat::Rgb` path in `decode_iterm2_image`).
#[test]
fn test_decode_iterm2_image_rgb_png_converts_to_rgba() {
    use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
    use base64::Engine as _;

    // Build a minimal 1×1 RGB PNG at runtime so the test does not depend on
    // any hardcoded binary blob.
    let mut png_bytes: Vec<u8> = Vec::new();
    {
        let mut enc = png::Encoder::new(&mut png_bytes, 1, 1);
        enc.set_color(png::ColorType::Rgb);
        enc.set_depth(png::BitDepth::Eight);
        let mut writer = enc.write_header().expect("PNG header");
        writer
            .write_image_data(&[0xDE, 0xAD, 0xBE])
            .expect("PNG data");
    }
    let b64 = BASE64_STANDARD.encode(&png_bytes);
    let result = super::decode_iterm2_image(&b64);
    assert!(result.is_some(), "valid RGB PNG must decode successfully");
    let (pixels, w, h) = result.unwrap();
    assert_eq!(w, 1, "width must be 1");
    assert_eq!(h, 1, "height must be 1");
    // decode_iterm2_image always outputs RGBA (4 bytes per pixel) — see source
    assert_eq!(
        pixels.len(),
        4,
        "RGB PNG must be converted to RGBA (4 bytes)"
    );
    // The conversion pads alpha to 255.
    assert_eq!(pixels[3], 255, "padded alpha must be 255");
}

/// `handle_osc_1337` with a valid inline PNG must advance the cursor below
/// the placed image.
///
/// This exercises the full happy path through `handle_osc_1337`:
/// param parsing → image decode → `add_placement` → cursor advance.
#[test]
fn test_handle_osc_1337_inline_png_advances_cursor() {
    use crate::TerminalCore;
    use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
    use base64::Engine as _;

    // Build a 1×1 RGBA PNG.
    let mut png_bytes: Vec<u8> = Vec::new();
    {
        let mut enc = png::Encoder::new(&mut png_bytes, 1, 1);
        enc.set_color(png::ColorType::Rgba);
        enc.set_depth(png::BitDepth::Eight);
        let mut writer = enc.write_header().expect("PNG header");
        writer
            .write_image_data(&[0xFF, 0xFF, 0xFF, 0xFF])
            .expect("PNG data");
    }
    let b64 = BASE64_STANDARD.encode(&png_bytes);

    // Compose the OSC 1337 param string: inline=1, explicit 2-col × 1-row display.
    let param_str = format!("File=inline=1;width=2;height=1:{b64}");
    let mut core = TerminalCore::new(24, 80);
    let cursor_before = *core.screen.cursor();
    let params: &[&[u8]] = &[b"1337", param_str.as_bytes()];
    super::handle_osc_1337(&mut core, params);
    let cursor_after = *core.screen.cursor();
    // Cursor row must have advanced by the image's display_rows (1).
    assert!(
        cursor_after.row > cursor_before.row,
        "cursor row must advance past the image: before={}, after={}",
        cursor_before.row,
        cursor_after.row
    );
}

// ── New edge-case tests (Round 34) ────────────────────────────────────────────

/// `parse_color_spec` on a whitespace-only string must return `None`.
///
/// After `.trim()` the string is empty; it matches neither `rgb:` nor `#` prefix.
#[test]
fn test_parse_color_spec_whitespace_only_returns_none() {
    assert_eq!(parse_color_spec("   "), None);
}

/// `parse_color_spec` with `rgb:` prefix but an empty channel string must
/// return `None` (`u16::from_str_radix("", 16)` is `Err`).
#[test]
fn test_parse_color_spec_rgb_empty_channel_returns_none() {
    assert_eq!(parse_color_spec("rgb://00/00"), None);
}

/// `encode_color_spec` on `[1, 254, 128]` — non-trivial per-channel expansion.
///
/// - 0x01 → 0x0101
/// - 0xFE → 0xFEFE
/// - 0x80 → 0x8080
#[test]
fn test_encode_color_spec_nonzero_channels() {
    let result = encode_color_spec([1, 254, 128]);
    assert_eq!(result, "rgb:0101/fefe/8080");
}

/// Calling `handle_osc_104` twice with the same valid index is idempotent.
///
/// The first call resets the entry; the second call resets an already-`None`
/// entry without error.  `palette_dirty` is set each time.
#[test]
fn test_handle_osc_104_double_reset_is_idempotent() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    core.osc_data.palette[7] = Some([50, 100, 150]);
    let params: &[&[u8]] = &[b"104", b"7"];
    super::handle_osc_104(&mut core, params);
    assert_eq!(core.osc_data().palette[7], None);
    // Second call: entry already None — must not panic.
    super::handle_osc_104(&mut core, params);
    assert_eq!(core.osc_data().palette[7], None);
    assert!(core.osc_data().palette_dirty);
}

/// Multiple `handle_osc_133` calls accumulate prompt marks in order.
///
/// Sending A → B → C → D must push exactly four events in that order.
#[test]
fn test_handle_osc_133_multiple_marks_accumulate_in_order() {
    use crate::types::osc::PromptMark;
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    for mark_byte in [b"A" as &[u8], b"B", b"C", b"D"] {
        let params: &[&[u8]] = &[b"133", mark_byte];
        super::handle_osc_133(&mut core, params);
    }
    let marks = &core.osc_data().prompt_marks;
    assert_eq!(marks.len(), 4, "all four marks must be recorded");
    assert_eq!(marks[0].mark, PromptMark::PromptStart);
    assert_eq!(marks[1].mark, PromptMark::PromptEnd);
    assert_eq!(marks[2].mark, PromptMark::CommandStart);
    assert_eq!(marks[3].mark, PromptMark::CommandEnd);
}

/// `handle_osc_52` with a non-`c` selection character still records the write.
///
/// The OSC 52 handler does not validate the selection character at params[1];
/// it only uses params[2] (the data).  A `p` selection must behave identically
/// to `c` for Write actions.
#[test]
fn test_handle_osc_52_non_c_selection_records_write() {
    use crate::types::osc::ClipboardAction;
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    // base64("hi") = "aGk="
    let params: &[&[u8]] = &[b"52", b"p", b"aGk="];
    super::handle_osc_52(&mut core, params);
    assert_eq!(core.osc_data().clipboard_actions.len(), 1);
    match &core.osc_data().clipboard_actions[0] {
        ClipboardAction::Write(s) => assert_eq!(s, "hi"),
        other => panic!("expected Write(\"hi\"), got {other:?}"),
    }
}

/// `handle_osc_default_colors` set-then-query for OSC 10 returns the exact
/// color that was just set (not the fallback grey).
#[test]
fn test_handle_osc_default_colors_set_then_query_returns_set_color() {
    use crate::types::Color;
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    // Set default_fg to (0, 128, 255) via OSC 10.
    let set_params: &[&[u8]] = &[b"10", b"#0080ff"];
    super::handle_osc_default_colors(&mut core, set_params);
    assert_eq!(
        core.osc_data().default_fg,
        Some(Color::Rgb(0x00, 0x80, 0xff))
    );
    // Now query: must respond with the value we just set, not the grey fallback.
    let query_params: &[&[u8]] = &[b"10", b"?"];
    super::handle_osc_default_colors(&mut core, query_params);
    assert_eq!(core.pending_responses().len(), 1);
    let resp = std::str::from_utf8(&core.pending_responses()[0]).unwrap();
    // 0x00 → "0000", 0x80 → "8080", 0xff → "ffff"
    assert!(
        resp.contains("0000/8080/ffff"),
        "query must reflect the set value, not grey: got {resp:?}"
    );
}

/// `handle_osc_default_colors` OSC 11 (bg) set with a `#` spec then
/// immediately queried must respond with the correct encoded value.
#[test]
fn test_handle_osc_default_colors_set_bg_then_query_round_trip() {
    use crate::types::Color;
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let set_params: &[&[u8]] = &[b"11", b"#102030"];
    super::handle_osc_default_colors(&mut core, set_params);
    assert_eq!(
        core.osc_data().default_bg,
        Some(Color::Rgb(0x10, 0x20, 0x30))
    );
    let query_params: &[&[u8]] = &[b"11", b"?"];
    super::handle_osc_default_colors(&mut core, query_params);
    let resp = std::str::from_utf8(&core.pending_responses()[0]).unwrap();
    // 0x10 → "1010", 0x20 → "2020", 0x30 → "3030"
    assert!(
        resp.contains("1010/2020/3030"),
        "OSC 11 set-then-query round-trip failed: got {resp:?}"
    );
}

/// `parse_iterm2_params` — when `inline` appears twice the last value wins.
///
/// The parser iterates semicolon-separated key=value pairs in order; the
/// second `inline=0` must overwrite the first `inline=1`.
#[test]
fn test_parse_iterm2_params_duplicate_inline_last_wins() {
    let p = super::parse_iterm2_params("inline=1;inline=0");
    assert!(!p.inline, "last inline= value must take precedence");
}

/// `handle_osc_1337` with `File=inline=1:` and an empty base64 payload must
/// be a noop — `decode_iterm2_image("")` returns `None`.
#[test]
fn test_handle_osc_1337_empty_base64_after_colon_is_noop() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    // The payload after ':' is the empty string.
    let params: &[&[u8]] = &[b"1337", b"File=inline=1:"];
    super::handle_osc_1337(&mut core, params);
    // No image stored; cursor must remain at origin.
    assert_eq!(core.screen.cursor().row, 0);
    assert_eq!(core.screen.cursor().col, 0);
}
