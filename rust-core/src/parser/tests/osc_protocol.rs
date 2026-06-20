//! Property-based and example-based tests for `osc_protocol` parsing.
//!
//! Module under test: `parser/osc_protocol.rs`
//! Tier: T3 — `ProptestConfig::with_cases(256)`

use super::*;

#[macro_use]
#[path = "osc_protocol/support.rs"]
mod support;

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
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    // base64("hello") = "aGVsbG8="
    let params: &[&[u8]] = &[b"52", b"c", b"aGVsbG8="];
    super::handle_osc_52(&mut core, params);
    assert_osc_52_action!(core, ClipboardAction::Write(s) if s == "hello");
}

#[test]
fn test_handle_osc_52_query_clipboard() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"52", b"c", b"?"];
    super::handle_osc_52(&mut core, params);
    assert_osc_52_action!(core, ClipboardAction::Query);
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

// ── handle_osc_133 (moved to osc_protocol/osc133.rs) ─────────────────────────

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

// ── handle_osc_51 (Elisp eval) ───────────────────────────────────────────────

#[test]
fn osc51_eval_command_stored() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"51", b"e", b"(message \"hello\")"];
    super::handle_osc_51(&mut core, params);
    assert_eq!(core.osc_data().eval_commands.len(), 1);
    assert_eq!(core.osc_data().eval_commands[0], "(message \"hello\")");
}

#[test]
fn osc51_non_e_subcommand_ignored() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"51", b"x", b"(evil-stuff)"];
    super::handle_osc_51(&mut core, params);
    assert!(core.osc_data().eval_commands.is_empty());
}

#[test]
fn osc51_oversized_command_rejected() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let big = vec![b'a'; 4097];
    let params: &[&[u8]] = &[b"51", b"e", &big];
    super::handle_osc_51(&mut core, params);
    assert!(core.osc_data().eval_commands.is_empty());
}

#[test]
fn osc51_invalid_utf8_rejected() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let bad_utf8: &[u8] = &[0xFF, 0xFE, 0xFD];
    let params: &[&[u8]] = &[b"51", b"e", bad_utf8];
    super::handle_osc_51(&mut core, params);
    assert!(core.osc_data().eval_commands.is_empty());
}

#[test]
fn osc51_empty_command_stored() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"51", b"e", b""];
    super::handle_osc_51(&mut core, params);
    assert_eq!(core.osc_data().eval_commands.len(), 1);
    assert_eq!(core.osc_data().eval_commands[0], "");
}

/// OSC 51 with no subcommand param at all (`params = ["51"]`) must be a no-op.
///
/// Exercises the `if let Some(sub) = params.get(1)` None branch.
#[test]
fn osc51_no_subcommand_param_is_noop() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"51"];
    super::handle_osc_51(&mut core, params);
    assert!(
        core.osc_data().eval_commands.is_empty(),
        "no subcommand → no eval command"
    );
}

/// OSC 51 with `e` subcommand but no command param (`params = ["51","e"]`) is a no-op.
///
/// Exercises the `if let Some(cmd_raw) = params.get(2)` None branch.
#[test]
fn osc51_e_subcommand_no_command_is_noop() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"51", b"e"];
    super::handle_osc_51(&mut core, params);
    assert!(
        core.osc_data().eval_commands.is_empty(),
        "e without command → no eval command"
    );
}

#[path = "osc_protocol/osc7.rs"]
mod osc7;

#[path = "osc_protocol/colors.rs"]
mod colors;

#[path = "osc_protocol/colors_extra.rs"]
mod colors_extra;

#[path = "osc_protocol/coverage.rs"]
mod coverage;

#[path = "osc_protocol/osc133.rs"]
mod osc133;
