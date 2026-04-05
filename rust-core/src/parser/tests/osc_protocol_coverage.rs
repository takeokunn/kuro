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
    use crate::TerminalCore;
    use crate::types::Color;
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
    let b64 = crate::util::base64::encode(&png_bytes);
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
    let b64 = crate::util::base64::encode(&png_bytes);

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
    use crate::TerminalCore;
    use crate::types::osc::PromptMark;
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
    use crate::TerminalCore;
    use crate::types::osc::ClipboardAction;
    let mut core = TerminalCore::new(24, 80);
    // base64("hi") = "aGk="
    let params: &[&[u8]] = &[b"52", b"p", b"aGk="];
    super::handle_osc_52(&mut core, params);
    assert_eq!(core.osc_data().clipboard_actions.len(), 1);
    match &core.osc_data().clipboard_actions[0] {
        ClipboardAction::Write(s) => assert_eq!(s, "hi"),
        other @ ClipboardAction::Query => panic!("expected Write(\"hi\"), got {other:?}"),
    }
}

/// `handle_osc_default_colors` set-then-query for OSC 10 returns the exact
/// color that was just set (not the fallback grey).
#[test]
fn test_handle_osc_default_colors_set_then_query_returns_set_color() {
    use crate::TerminalCore;
    use crate::types::Color;
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
    use crate::TerminalCore;
    use crate::types::Color;
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
