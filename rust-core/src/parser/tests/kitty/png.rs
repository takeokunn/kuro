use crate::parser::kitty::{process_apc_payload, ImageFormat, KittyCommand, KittyParams};
use super::support::encode_1x1_png_b64;

// ── PNG color-type expansion ───────────────────────────────────────────────────

#[test]
fn test_kitty_png_grayscale_expands_to_rgb() {
    // f=100 with a 1×1 Grayscale PNG: the single gray channel must be replicated
    // to R=G=B.  Result format is ImageFormat::Rgb; payload = 3 bytes.
    let gray_value: u8 = 0x80;
    let b64 = encode_1x1_png_b64(png::ColorType::Grayscale, &[gray_value]);
    let mut chunk_state = None;
    let payload = format!("a=t,f=100,i=32;{b64}");
    let result = process_apc_payload(payload.as_bytes(), &mut chunk_state);
    match result {
        Some(KittyCommand::Transmit { format, pixels, .. }) => {
            assert_eq!(
                format,
                ImageFormat::Rgb,
                "Grayscale PNG must expand to ImageFormat::Rgb"
            );
            assert_eq!(pixels.len(), 3, "1 grayscale pixel expanded to 3 RGB bytes");
            // All three channels must equal the original gray value.
            assert_eq!(pixels[0], gray_value, "R must equal gray_value");
            assert_eq!(pixels[1], gray_value, "G must equal gray_value");
            assert_eq!(pixels[2], gray_value, "B must equal gray_value");
        }
        other => panic!("expected Transmit, got {other:?}"),
    }
}

#[test]
fn test_kitty_png_grayscale_alpha_expands_to_rgba() {
    // f=100 with a 1×1 GrayscaleAlpha PNG: (gray, alpha) must expand to
    // (gray, gray, gray, alpha).  Result format is ImageFormat::Rgba; payload = 4 bytes.
    let gray_value: u8 = 0x80;
    let alpha_value: u8 = 0xC0;
    let b64 = encode_1x1_png_b64(png::ColorType::GrayscaleAlpha, &[gray_value, alpha_value]);
    let mut chunk_state = None;
    let payload = format!("a=t,f=100,i=33;{b64}");
    let result = process_apc_payload(payload.as_bytes(), &mut chunk_state);
    match result {
        Some(KittyCommand::Transmit { format, pixels, .. }) => {
            assert_eq!(
                format,
                ImageFormat::Rgba,
                "GrayscaleAlpha PNG must expand to ImageFormat::Rgba"
            );
            assert_eq!(
                pixels.len(),
                4,
                "1 grayscale+alpha pixel expanded to 4 RGBA bytes"
            );
            // R, G, B channels must all equal the original gray value.
            assert_eq!(pixels[0], gray_value, "R must equal gray_value");
            assert_eq!(pixels[1], gray_value, "G must equal gray_value");
            assert_eq!(pixels[2], gray_value, "B must equal gray_value");
            // Alpha channel must equal the original alpha value.
            assert_eq!(pixels[3], alpha_value, "A must equal alpha_value");
        }
        other => panic!("expected Transmit, got {other:?}"),
    }
}

// ── KittyParams field coverage ─────────────────────────────────────────────────

#[test]
fn test_kitty_params_empty_data_produces_none_action() {
    // Sending an empty payload (no header, no data) must not panic and must
    // return None (no action → build_command defaults to 'T' but no valid data).
    let mut chunk_state = None;
    let result = process_apc_payload(b"", &mut chunk_state);
    // Empty payload → action defaults to 'T' (TransmitAndDisplay) but no format/data
    // → decode_pixel_data succeeds for RGBA with 0 bytes and 0×0 dims → rejected
    assert!(result.is_none(), "empty APC payload must return None");
}

#[test]
fn test_kitty_params_no_semicolon_no_data_chunk() {
    // A header with no ';' separator produces an empty b64 body (zero bytes decoded).
    // With format RGBA (default) and no s=/v= dims (both 0) this must be rejected.
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=t,f=32,i=99", &mut chunk_state);
    assert!(
        result.is_none(),
        "header with no ';' and no b64 data, zero dims must return None"
    );
}

#[test]
fn test_kitty_params_duplicate_key_last_wins() {
    // KittyParams::parse processes keys left to right; the last value for a
    // repeated key overwrites the earlier one.
    // Send "f=24,f=32": format must be 32 (the second value).
    let params = KittyParams::parse(b"f=24,f=32");
    assert_eq!(
        params.format,
        Some(32),
        "duplicate key: last value (32) must win over first (24)"
    );
}

#[test]
fn test_kitty_params_transmission_absent_defaults_to_direct() {
    // When no 't=' key is present, transmission defaults to None in the struct.
    // process_apc_payload treats missing transmission as 'd' (direct).
    let params = KittyParams::parse(b"a=t,i=1");
    assert!(
        params.transmission.is_none(),
        "transmission must be None when 't=' key is absent"
    );
}

#[test]
fn test_kitty_params_quiet_one_parsed() {
    // q=1 suppresses OK responses but still allows error responses.
    let params = KittyParams::parse(b"q=1");
    assert_eq!(params.quiet, 1, "q=1 must set quiet to 1");
}

#[test]
fn test_kitty_process_apc_empty_b64_after_semicolon_no_panic() {
    // A transmission command with a ';' separator but no following base64 data
    // (empty payload body) must not panic and must gracefully return None or
    // a valid command (depending on format and dims).
    //
    // f=32 (RGBA), s=0, v=0, no data → 0-dim rejection → None.
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=t,f=32,i=50;", &mut chunk_state);
    assert!(
        result.is_none(),
        "empty b64 body with zero dims must return None without panicking"
    );
}

// ── New coverage tests ─────────────────────────────────────────────────────────

/// `KittyParams::parse` silently skips key-value pairs shorter than 3 bytes.
///
/// The guard `if kv.len() < 3 || kv[1] != b'='` is designed to skip both
/// zero-length entries and entries like "ab" (key without '=' at index 1).
/// This test passes two short entries ("a" and "f=") and verifies that
/// the trailing valid entry "i=5" is still parsed correctly.
#[test]
fn test_parse_params_short_kv_pairs_skipped() {
    // "a" → len=1 < 3, skipped
    // "f=" → len=2 < 3, skipped
    // "i=5" → valid, parsed
    let params = KittyParams::parse(b"a,f=,i=5");
    assert_eq!(
        params.image_id,
        Some(5),
        "valid 'i=5' entry after short entries must be parsed"
    );
    assert!(
        params.action.is_none(),
        "short 'a' entry must be skipped (no action set)"
    );
    assert!(
        params.format.is_none(),
        "short 'f=' entry must be skipped (no format set)"
    );
}

/// `KittyParams::parse` skips entries where index 1 is not `=`.
///
/// Exercises the `kv[1] != b'='` branch of the guard condition.
#[test]
fn test_parse_params_no_equals_at_index1_skipped() {
    // "abc" → kv[1] = 'b' ≠ '=' → skipped; "i=3" is valid
    let params = KittyParams::parse(b"abc,i=3");
    assert_eq!(params.image_id, Some(3));
    // 'a' of "abc" was not parsed as an action because the whole entry was skipped
    assert!(
        params.action.is_none(),
        "'abc' must be skipped — no action extracted"
    );
}

// `process_apc_payload` must reject `t=t` (temp-file) transmission type.
// Only 'd' (direct/inline base64) is supported; all others are silently ignored.
test_unsupported_transmission!(
    test_unsupported_transmission_temp_file_returns_none,
    payload = b"a=t,t=t,i=1;",
    label = "temp-file (t=t)",
);

// `process_apc_payload` must reject `t=s` (shared-memory) transmission type.
test_unsupported_transmission!(
    test_unsupported_transmission_shared_mem_returns_none,
    payload = b"a=t,t=s,i=2;",
    label = "shared-memory (t=s)",
);

/// When no `a=` key is present, `build_command` defaults the action to `'T'`
/// (TransmitAndDisplay), not `'t'`.
///
/// This exercises the `params.action.unwrap_or('T')` path in `build_command`.
#[test]
fn test_default_action_is_transmit_and_display() {
    // No a= key: action defaults to 'T' (TransmitAndDisplay).
    // AAAAAA== = 4 zero bytes = valid 1×1 RGBA pixel.
    let mut chunk_state = None;
    let result = process_apc_payload(b"f=32,i=1,s=1,v=1;AAAAAA==", &mut chunk_state);
    assert!(
        matches!(result, Some(KittyCommand::TransmitAndDisplay { .. })),
        "absent a= key must default to TransmitAndDisplay"
    );
}

/// `parse_u32` (via `KittyParams::parse`) must return `None` for a value that
/// overflows `u32` (i.e., any value > 4,294,967,295).
///
/// `"4294967296"` is `u32::MAX + 1`; `str::parse::<u32>()` returns `Err`.
#[test]
fn test_parse_params_u32_overflow_returns_none() {
    let params = KittyParams::parse(b"i=4294967296");
    assert!(
        params.image_id.is_none(),
        "u32::MAX+1 must parse to None (overflow)"
    );
}

/// `decode_png` Indexed color type branch: an Indexed-color PNG must not panic
/// and must produce an `ImageFormat::Rgba` result with the raw palette-expanded
/// bytes from the `png` crate.
///
/// This exercises the `png::ColorType::Indexed => (buf, ImageFormat::Rgba)` arm,
/// which is the one remaining uncovered branch in `decode_png`.
#[test]
fn test_kitty_png_indexed_color_type_produces_rgba_format() {
    // The `png` crate requires a PLTE chunk for Indexed-color PNGs.
    // Build a 1×1 Indexed PNG with a single-entry palette at runtime.
    let mut png_bytes: Vec<u8> = Vec::new();
    {
        let mut enc = png::Encoder::new(&mut png_bytes, 1, 1);
        enc.set_color(png::ColorType::Indexed);
        enc.set_depth(png::BitDepth::Eight);
        // Set a 1-entry palette: index 0 → (0xAB, 0xCD, 0xEF)
        enc.set_palette(vec![0xAB, 0xCD, 0xEF]);
        let mut writer = enc.write_header().expect("PNG header write");
        // Image data: one pixel at palette index 0.
        writer.write_image_data(&[0u8]).expect("PNG pixel write");
    }
    let b64 = crate::util::base64::encode(&png_bytes);
    let payload = format!("a=t,f=100,i=40,s=1,v=1;{b64}");
    let mut chunk_state = None;
    let result = process_apc_payload(payload.as_bytes(), &mut chunk_state);
    // The Indexed branch returns (buf, ImageFormat::Rgba) without transformation —
    // so the command must succeed (Some) and carry the Rgba format tag.
    assert!(
        result.is_some(),
        "Indexed-color PNG must decode successfully"
    );
    match result.unwrap() {
        KittyCommand::Transmit { format, .. } => {
            assert_eq!(
                format,
                ImageFormat::Rgba,
                "Indexed PNG must map to ImageFormat::Rgba"
            );
        }
        other => panic!("expected Transmit, got {other:?}"),
    }
}
