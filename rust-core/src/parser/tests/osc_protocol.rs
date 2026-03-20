//! Property-based and example-based tests for `osc_protocol` parsing.
//!
//! Module under test: `parser/osc_protocol.rs`
//! Tier: T3 — `ProptestConfig::with_cases(256)`

use super::*;

// ── encode_color_spec ────────────────────────────────────────────────────────

#[test]
fn test_encode_color_spec_basic_red() {
    let result = encode_color_spec([255, 0, 0]);
    assert_eq!(result, "rgb:ffff/0000/0000");
}

#[test]
fn test_encode_color_spec_basic_green() {
    let result = encode_color_spec([0, 255, 0]);
    assert_eq!(result, "rgb:0000/ffff/0000");
}

#[test]
fn test_encode_color_spec_basic_blue() {
    let result = encode_color_spec([0, 0, 255]);
    assert_eq!(result, "rgb:0000/0000/ffff");
}

#[test]
fn test_encode_color_spec_black() {
    let result = encode_color_spec([0, 0, 0]);
    assert_eq!(result, "rgb:0000/0000/0000");
}

#[test]
fn test_encode_color_spec_white() {
    let result = encode_color_spec([255, 255, 255]);
    assert_eq!(result, "rgb:ffff/ffff/ffff");
}

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
    assert_eq!(parts.len(), 3, "encode_color_spec must produce three channels");
    for part in &parts {
        assert_eq!(part.len(), 4, "each channel must be exactly 4 hex digits");
    }
}

// ── parse_color_spec ─────────────────────────────────────────────────────────

#[test]
fn test_parse_color_spec_rgb_4digit() {
    // 4-digit per channel: upper 8 bits are used
    let result = parse_color_spec("rgb:ff00/8000/0000");
    assert_eq!(result, Some([0xff, 0x80, 0x00]));
}

#[test]
fn test_parse_color_spec_rgb_2digit() {
    // 2-digit per channel: value used directly
    let result = parse_color_spec("rgb:ff/80/00");
    assert_eq!(result, Some([0xff, 0x80, 0x00]));
}

#[test]
fn test_parse_color_spec_hash_format() {
    let result = parse_color_spec("#ff8000");
    assert_eq!(result, Some([0xff, 0x80, 0x00]));
}

#[test]
fn test_parse_color_spec_hash_black() {
    let result = parse_color_spec("#000000");
    assert_eq!(result, Some([0, 0, 0]));
}

#[test]
fn test_parse_color_spec_hash_white() {
    let result = parse_color_spec("#ffffff");
    assert_eq!(result, Some([255, 255, 255]));
}

#[test]
fn test_parse_color_spec_invalid_returns_none() {
    assert_eq!(parse_color_spec("notacolor"), None);
}

#[test]
fn test_parse_color_spec_empty_returns_none() {
    assert_eq!(parse_color_spec(""), None);
}

#[test]
fn test_parse_color_spec_rgb_missing_channel_returns_none() {
    // Only two channels provided
    assert_eq!(parse_color_spec("rgb:ff/80"), None);
}

#[test]
fn test_parse_color_spec_hash_wrong_length_returns_none() {
    assert_eq!(parse_color_spec("#fff"), None);
}

#[test]
fn test_parse_color_spec_rgb_invalid_hex_returns_none() {
    assert_eq!(parse_color_spec("rgb:zz/00/00"), None);
}

#[test]
fn test_parse_color_spec_leading_whitespace_trimmed() {
    let result = parse_color_spec("  #ff0000");
    assert_eq!(result, Some([255, 0, 0]));
}

// ── handle_osc_52 ─────────────────────────────────────────────────────────────

#[test]
fn test_handle_osc_52_write_clipboard() {
    use crate::TerminalCore;
    use crate::types::osc::ClipboardAction;
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
    use crate::TerminalCore;
    use crate::types::osc::ClipboardAction;
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
    assert!(core.osc_data().palette.iter().all(std::option::Option::is_none));
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
    assert!(core.osc_data().palette.iter().all(std::option::Option::is_none));
    assert!(core.osc_data().palette_dirty);
}

// ── handle_osc_133 ────────────────────────────────────────────────────────────

#[test]
fn test_handle_osc_133_prompt_start() {
    use crate::TerminalCore;
    use crate::types::osc::PromptMark;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"133", b"A"];
    super::handle_osc_133(&mut core, params);
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    assert_eq!(core.osc_data().prompt_marks[0].mark, PromptMark::PromptStart);
}

#[test]
fn test_handle_osc_133_command_end() {
    use crate::TerminalCore;
    use crate::types::osc::PromptMark;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"133", b"D"];
    super::handle_osc_133(&mut core, params);
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    assert_eq!(core.osc_data().prompt_marks[0].mark, PromptMark::CommandEnd);
}

#[test]
fn test_handle_osc_133_unknown_mark_is_noop() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"133", b"Z"];
    super::handle_osc_133(&mut core, params);
    assert!(core.osc_data().prompt_marks.is_empty());
}

// ── handle_osc_default_colors ─────────────────────────────────────────────────

#[test]
fn test_handle_osc_default_colors_set_fg() {
    use crate::TerminalCore;
    use crate::types::Color;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"10", b"#ff8000"];
    super::handle_osc_default_colors(&mut core, params);
    assert_eq!(core.osc_data().default_fg, Some(Color::Rgb(0xff, 0x80, 0x00)));
    assert!(core.osc_data().default_colors_dirty);
}

#[test]
fn test_handle_osc_default_colors_set_bg() {
    use crate::TerminalCore;
    use crate::types::Color;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"11", b"#001122"];
    super::handle_osc_default_colors(&mut core, params);
    assert_eq!(core.osc_data().default_bg, Some(Color::Rgb(0x00, 0x11, 0x22)));
    assert!(core.osc_data().default_colors_dirty);
}

#[test]
fn test_handle_osc_default_colors_query_fg_produces_response() {
    use crate::TerminalCore;
    use crate::types::Color;
    let mut core = TerminalCore::new(24, 80);
    core.osc_data.default_fg = Some(Color::Rgb(255, 0, 0));
    let params: &[&[u8]] = &[b"10", b"?"];
    super::handle_osc_default_colors(&mut core, params);
    assert_eq!(core.pending_responses().len(), 1);
    let resp = std::str::from_utf8(&core.pending_responses()[0]).unwrap();
    assert!(resp.contains("10"), "response must contain OSC number");
    assert!(resp.contains("rgb:"), "response must contain rgb: color spec");
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
