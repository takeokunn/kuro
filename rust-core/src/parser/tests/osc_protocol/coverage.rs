use super::*;

// ── New coverage tests (Round 30) ─────────────────────────────────────────────

/// `parse_color_spec` must trim trailing whitespace (`.trim()` handles both sides).
#[test]
fn test_parse_color_spec_trims_whitespace_cases() {
    for (input, expected) in [
        ("#ff0000  ", Some([255, 0, 0])),
        ("  #00ff00  ", Some([0, 255, 0])),
        ("rgb:ff/00/00 ", Some([0xff, 0x00, 0x00])),
    ] {
        assert_eq!(parse_color_spec(input), expected);
    }
}

// `parse_iterm2_params` must strip `px` suffix from height values.
test_iterm2_params!(
    test_parse_iterm2_params_height_px_suffix,
    input "inline=1;height=48px",
    inline true,
    cols None,
    rows Some(48)
);

// `parse_iterm2_params` must strip `%` suffix from height values.
test_iterm2_params!(
    test_parse_iterm2_params_height_percent_suffix,
    input "inline=1;height=25%",
    inline true,
    cols None,
    rows Some(25)
);

// `handle_osc_default_colors` must accept a 4-digit `rgb:` spec for OSC 10.
//
// This exercises the `parse_color_spec` → `rgb:RRRR/GGGG/BBBB` branch when
// called from `handle_osc_default_colors`.
test_osc_default_colors_set!(
    test_handle_osc_default_colors_set_fg_via_rgb_4digit,
    b"10",
    b"rgb:ff00/8000/0000",
    default_fg,
    0xff,
    0x80,
    0x00
);

/// `decode_iterm2_image` must decode a 1×1 RGB PNG and convert it to RGBA.
///
/// The `osc_protocol.rs` implementation converts any non-RGBA PNG to RGBA
/// (the `_ => ImageFormat::Rgb` path in `decode_iterm2_image`).
#[test]
fn test_decode_iterm2_image_rgb_png_converts_to_rgba() {
    let b64 = test_1x1_png_b64!(png::ColorType::Rgb, [0xDE, 0xAD, 0xBE]);
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

    let b64 = test_1x1_png_b64!(png::ColorType::Rgba, [0xFF, 0xFF, 0xFF, 0xFF]);

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

/// `handle_osc_52` with a non-`c` selection character records the write and
/// carries the parsed [`SelectionTarget`] through.
///
/// The OSC 52 handler parses the selection character at params[1] and decodes
/// the data at params[2]. A `p` selection records a Write tagged Primary.
#[test]
fn test_handle_osc_52_non_c_selection_records_write() {
    use crate::types::osc::SelectionTarget;
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    // base64("hi") = "aGk="
    let params: &[&[u8]] = &[b"52", b"p", b"aGk="];
    super::handle_osc_52(&mut core, params);
    assert_osc_52_action!(
        core,
        ClipboardAction::Write { target: SelectionTarget::Primary, data } if data == "hi"
    );
}

// `handle_osc_default_colors` set-then-query for OSC 10 returns the exact
// color that was just set (not the fallback grey).
test_osc_default_colors_set_then_query!(
    test_handle_osc_default_colors_set_then_query_returns_set_color,
    b"10",
    b"#0080ff",
    default_fg,
    0x00,
    0x80,
    0xff,
    "0000/8080/ffff"
);

// `handle_osc_default_colors` OSC 11 (bg) set with a `#` spec then
// immediately queried must respond with the correct encoded value.
test_osc_default_colors_set_then_query!(
    test_handle_osc_default_colors_set_bg_then_query_round_trip,
    b"11",
    b"#102030",
    default_bg,
    0x10,
    0x20,
    0x30,
    "1010/2020/3030"
);

// `parse_iterm2_params` — when `inline` appears twice the last value wins.
//
// The parser iterates semicolon-separated key=value pairs in order; the
// second `inline=0` must overwrite the first `inline=1`.
test_iterm2_params!(
    test_parse_iterm2_params_duplicate_inline_last_wins,
    input "inline=1;inline=0",
    inline false,
    cols None,
    rows None
);

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
