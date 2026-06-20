use super::*;

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
    let mut core = make_core!();
    let params: &[&[u8]] = &[b"10", b"notacolor"];
    super::handle_osc_default_colors(&mut core, params);
    assert!(core.osc_data().default_fg.is_none());
    assert!(!core.osc_data().default_colors_dirty);
}

#[test]
fn test_handle_osc_default_colors_missing_spec_is_noop() {
    let mut core = make_core!();
    // Only one param — no color spec at index 1
    let params: &[&[u8]] = &[b"10"];
    super::handle_osc_default_colors(&mut core, params);
    assert!(core.osc_data().default_fg.is_none());
    assert!(core.pending_responses().is_empty());
}

test_osc_default_colors_query_unset!(
    test_handle_osc_default_colors_query_unset_produces_grey_response,
    b"10",
    default_fg
);

// ── handle_osc_52 (extended) ──────────────────────────────────────────────────

// "!!!" is not valid base64 — must be silently ignored
test_osc_52_clipboard_empty!(
    test_handle_osc_52_invalid_base64_is_noop,
    &[b"52", b"c", b"!!!"],
    "invalid base64 must produce no clipboard action"
);

// base64 of [0xFF] is "/w==" — valid base64 but not valid UTF-8
test_osc_52_clipboard_empty!(
    test_handle_osc_52_non_utf8_payload_is_noop,
    &[b"52", b"c", b"/w=="],
    "non-UTF8 clipboard payload must be ignored"
);

// ── handle_osc_1337 ───────────────────────────────────────────────────────────

// Payload does not start with "File=" — should be silently ignored
test_osc_1337_noop!(
    test_handle_osc_1337_non_file_prefix_is_noop,
    &[b"1337", b"SetBadge=:aGVsbG8="]
);

// No second param — missing payload
test_osc_1337_noop!(test_handle_osc_1337_missing_param_is_noop, &[b"1337"]);

// ── parse_iterm2_params ────────────────────────────────────────────────────────

test_iterm2_params!(
    test_parse_iterm2_params_empty_string,
    input "",
    inline false,
    cols None,
    rows None
);

test_iterm2_params!(
    test_parse_iterm2_params_inline_one,
    input "inline=1",
    inline true,
    cols None,
    rows None
);

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

// width=0 is treated as "auto" (None)
test_iterm2_param_zero_is_none!(
    test_parse_iterm2_params_width_zero_becomes_none,
    input "inline=1;width=0",
    field display_cols
);
test_iterm2_param_zero_is_none!(
    test_parse_iterm2_params_height_zero_becomes_none,
    input "inline=1;height=0",
    field display_rows
);

test_iterm2_params!(
    test_parse_iterm2_params_unknown_keys_ignored,
    input "inline=1;name=foo.png;size=1234;preserveAspectRatio=1",
    inline true,
    cols None,
    rows None
);

test_iterm2_params!(
    test_parse_iterm2_params_all_fields,
    input "inline=1;width=20;height=5",
    inline true,
    cols Some(20),
    rows Some(5)
);

// ── decode_iterm2_image ────────────────────────────────────────────────────────

test_decode_iterm2_none!(test_decode_iterm2_image_empty_returns_none, "");
test_decode_iterm2_none!(
    test_decode_iterm2_image_invalid_base64_returns_none,
    "!!!notbase64!!!"
);
test_decode_iterm2_none!(
    test_decode_iterm2_image_valid_base64_non_png_returns_none,
    "aGVsbG8="
);

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

// "File=" prefix but no ':' separator — no crash; no side effects on clipboard
test_osc_1337_noop!(
    test_handle_osc_1337_no_colon_separator_is_noop,
    &[b"1337", b"File=inline=1"]
);

// inline=0 — image should NOT be stored
test_osc_1337_noop!(
    test_handle_osc_1337_not_inline_is_noop,
    &[b"1337", b"File=inline=0:aGVsbG8="]
);

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

test_roundtrip_color!(test_roundtrip_black, [0, 0, 0]);
test_roundtrip_color!(test_roundtrip_white, [255, 255, 255]);

// ── handle_osc_52 (size cap) ──────────────────────────────────────────────────

#[test]
fn test_handle_osc_52_oversized_payload_is_noop() {
    // Payload exceeds 1MB cap (1_048_576 + 1 bytes).
    // The data itself is not valid base64, but the size guard fires first.
    let mut core = make_core!();
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
    // Exactly 1MB of valid base64 ('A' chars decode fine).
    // The handler accepts payloads with len <= 1_048_576.
    // "AAAA" decodes to [0, 0, 0] — we just verify no panic.
    let mut core = make_core!();
    let at_cap = vec![b'A'; 1_048_576];
    let params: &[&[u8]] = &[b"52", b"c", &at_cap];
    super::handle_osc_52(&mut core, params);
    // No assertion on clipboard_actions — the decoded bytes may or may not be valid UTF-8.
    // The key invariant is that it does not panic.
}

#[test]
fn test_handle_osc_52_empty_data_is_noop() {
    let mut core = make_core!();
    let params: &[&[u8]] = &[b"52", b"c", b""];
    super::handle_osc_52(&mut core, params);
    assert_osc_52_action!(core, ClipboardAction::Write { data, .. } if data.is_empty());
}

// ── handle_osc_104 (out-of-range index) ───────────────────────────────────────

// Index 256 is out of range (valid indices are 0..=255).
// palette_dirty is set unconditionally; palette[0] must be untouched.
test_osc_104_bad_param_no_change!(
    test_handle_osc_104_out_of_range_index_is_noop,
    idx 0,
    initial [1, 2, 3],
    params &[b"104", b"256"],
    msg "palette entry 0 must be untouched for out-of-range index 256"
);

#[test]
fn test_handle_osc_104_index_255_boundary() {
    // Index 255 is the last valid palette slot.
    let mut core = make_core!();
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

// Non-numeric index string: parse::<usize>() fails, handler does nothing.
// palette_dirty is still set by the function regardless.
test_osc_104_bad_param_no_change!(
    test_handle_osc_104_non_numeric_index_is_noop,
    idx 1,
    initial [9, 8, 7],
    params &[b"104", b"abc"],
    msg "non-numeric index must leave palette unchanged"
);

// ── handle_osc_133 (empty mark byte) ─────────────────────────────────────────

#[test]
fn test_handle_osc_133_empty_mark_is_noop() {
    // Param exists but is an empty byte slice — first() returns None.
    let mut core = make_core!();
    let params: &[&[u8]] = &[b"133", b""];
    super::handle_osc_133(&mut core, params);
    assert!(
        core.osc_data().prompt_marks.is_empty(),
        "empty mark byte must produce no prompt mark event"
    );
}
