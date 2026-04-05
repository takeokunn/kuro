// ── osc_protocol_colors.rs — included into parser::tests::osc_protocol ────────

use crate::TerminalCore;

// ── Macros ────────────────────────────────────────────────────────────────────

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

/// Generate an `handle_osc_1337` noop test: build params from `$params_expr`,
/// call `handle_osc_1337`, assert `clipboard_actions` is empty.
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

/// Generate an `handle_osc_52` noop test that asserts `clipboard_actions` is empty.
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

/// Generate a `parse_iterm2_params` test asserting that a dimension field becomes `None`
/// when its value is `0`.
macro_rules! test_iterm2_param_zero_is_none {
    ($name:ident, input $input:expr, field $field:ident) => {
        #[test]
        fn $name() {
            let p = super::parse_iterm2_params($input);
            assert_eq!(p.$field, None);
        }
    };
}

/// Generate an `encode_color_spec` → `parse_color_spec` round-trip test.
macro_rules! test_roundtrip_color {
    ($name:ident, [$r:expr, $g:expr, $b:expr]) => {
        #[test]
        fn $name() {
            let encoded = encode_color_spec([$r, $g, $b]);
            assert_eq!(parse_color_spec(&encoded), Some([$r, $g, $b]));
        }
    };
}

/// Generate an `handle_osc_104` test: set `palette[idx]` to `initial`, send a
/// bad (non-resetting) param, and assert the entry is unchanged and
/// `palette_dirty` is set.
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

/// Construct a `TerminalCore` with the standard 24×80 grid.
macro_rules! make_core {
    () => {
        TerminalCore::new(24, 80)
    };
}

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

#[test]
fn test_handle_osc_default_colors_query_unset_produces_grey_response() {
    let mut core = make_core!();
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
    // Zero-length data at index 2 is not "?" and not valid base64 text.
    let mut core = make_core!();
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
    // OSC number "99" is not 10/11/12 — the `_ => {}` match arm fires, so no
    // color field is written.  However, `default_colors_dirty` is set
    // unconditionally inside `if let Some([r,g,b])` once the color spec parses,
    // which is the existing behavior.
    let mut core = make_core!();
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
    // OSC number "99" with query — the `_ => return` branch fires; no response pushed.
    let mut core = make_core!();
    let params: &[&[u8]] = &[b"99", b"?"];
    super::handle_osc_default_colors(&mut core, params);
    assert!(
        core.pending_responses().is_empty(),
        "unknown OSC number query must push no response"
    );
}

#[test]
fn test_handle_osc_default_colors_query_unset_cursor_color_responds_grey() {
    // cursor_color is None — query must respond with fallback grey (128, 128, 128).
    let mut core = make_core!();
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
    let mut core = make_core!();
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
