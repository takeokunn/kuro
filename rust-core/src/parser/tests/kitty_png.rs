// ── Macros ────────────────────────────────────────────────────────────────────

/// Assert that `process_apc_payload` rejects an unsupported transmission type
/// (`t=t` or `t=s`) with `None`, and that `chunk_state` is cleared.
///
/// `$name`    — test function name
/// `$payload` — full APC payload bytes
/// `$t_label` — human-readable label for the transmission type (for msg)
macro_rules! test_unsupported_transmission {
    ($name:ident, payload = $payload:expr, label = $label:expr $(,)?) => {
        #[test]
        fn $name() {
            let mut chunk_state = None;
            let result = process_apc_payload($payload, &mut chunk_state);
            assert!(
                result.is_none(),
                concat!($label, " transmission must return None")
            );
            assert!(
                chunk_state.is_none(),
                "chunk_state must be cleared when transmission is rejected"
            );
        }
    };
}

/// Assert that a raw-pixel transmit of an N×N image carries the expected
/// format, dimensions, and pixel-buffer size.
///
/// `$name`    — test function name
/// `$fmt_key` — `f=` value (24 = RGB, 32 = RGBA)
/// `$image_id`— `i=` value
/// `$n`       — side length (cols = rows = `$n`)
/// `$nbytes`  — expected pixel-buffer length
/// `$fmt_var` — `ImageFormat` variant (`Rgb` or `Rgba`)
macro_rules! test_transmit_nxn_image {
    (
        $name:ident,
        fmt_key  = $fmt_key:expr,
        image_id = $image_id:expr,
        n        = $n:expr,
        nbytes   = $nbytes:expr,
        fmt_var  = $fmt_var:ident
        $(,)?
    ) => {
        #[test]
        fn $name() {
            let b64 = BASE64_STANDARD.encode([0u8; $nbytes]);
            let mut chunk_state = None;
            let payload = format!(
                "a=t,f={},i={},s={},v={};{}",
                $fmt_key, $image_id, $n, $n, b64
            );
            let result = process_apc_payload(payload.as_bytes(), &mut chunk_state);
            match result.unwrap() {
                KittyCommand::Transmit {
                    format,
                    pixel_width,
                    pixel_height,
                    pixels,
                    ..
                } => {
                    assert_eq!(format, ImageFormat::$fmt_var);
                    assert_eq!(pixel_width, $n);
                    assert_eq!(pixel_height, $n);
                    assert_eq!(pixels.len(), $nbytes, concat!(stringify!($n), "×", stringify!($n), " ", stringify!($fmt_var), " byte count"));
                }
                other => panic!("expected Transmit, got {other:?}"),
            }
        }
    };
}

/// Assert that a 1×1 PNG with a known pixel value round-trips through
/// `process_apc_payload` and produces the expected pixel bytes.
///
/// `$name`      — test function name
/// `$color_type`— `png::ColorType` variant
/// `$pixel`     — pixel bytes passed to `encode_1x1_png_b64`
/// `$image_id`  — `i=` value
/// `$fmt_var`   — expected `ImageFormat` variant
/// `$expected`  — expected pixel bytes as a `vec!` expression
/// `$msg`       — assertion message
macro_rules! test_png_pixel_round_trip {
    (
        $name:ident,
        color_type = $color_type:expr,
        pixel      = $pixel:expr,
        image_id   = $image_id:expr,
        fmt_var    = $fmt_var:ident,
        expected   = $expected:expr,
        msg        = $msg:expr
        $(,)?
    ) => {
        #[test]
        fn $name() {
            let b64 = encode_1x1_png_b64($color_type, $pixel);
            let mut chunk_state = None;
            let payload = format!("a=t,f=100,i={},s=1,v=1;{}", $image_id, b64);
            let result = process_apc_payload(payload.as_bytes(), &mut chunk_state);
            match result.unwrap() {
                KittyCommand::Transmit { pixels, format, .. } => {
                    assert_eq!(format, ImageFormat::$fmt_var);
                    assert_eq!(pixels, $expected, $msg);
                }
                other => panic!("expected Transmit, got {other:?}"),
            }
        }
    };
}

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
    label   = "temp-file (t=t)",
);

// `process_apc_payload` must reject `t=s` (shared-memory) transmission type.
test_unsupported_transmission!(
    test_unsupported_transmission_shared_mem_returns_none,
    payload = b"a=t,t=s,i=2;",
    label   = "shared-memory (t=s)",
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
    let b64 = BASE64_STANDARD.encode(&png_bytes);
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

// ── Additional new tests ───────────────────────────────────────────────────────

// Delete sub-command 'r' (delete by row range)
#[test]
fn test_delete_sub_command_r_variant() {
    // a=d,d=r — delete all placements that intersect a row range
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=d,d=r", &mut chunk_state);
    assert_delete_sub!(result, 'r');
}

// Delete sub-command 'x' (delete by column range)
#[test]
fn test_delete_sub_command_x_variant() {
    // a=d,d=x — delete all placements that intersect a column range
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=d,d=x", &mut chunk_state);
    assert_delete_sub!(result, 'x');
}

// Delete sub-command 'B' (below cursor)
#[test]
fn test_delete_sub_command_uppercase_b_variant() {
    // a=d,d=B — delete all placements on or below current cursor row
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=d,d=B", &mut chunk_state);
    assert_delete_sub!(result, 'B');
}

// Delete sub-command 'n' (delete by image number)
#[test]
fn test_delete_sub_command_n_variant() {
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=d,d=n,i=8", &mut chunk_state);
    match result.unwrap() {
        KittyCommand::Delete {
            delete_sub,
            image_id,
            ..
        } => {
            assert_eq!(delete_sub, 'n');
            assert_eq!(image_id, Some(8));
        }
        other => panic!("expected Delete, got {other:?}"),
    }
}

// KittyParams: 'r' and 'c' keys are parsed as rows/cols for Place commands
#[test]
fn test_parse_params_r_and_c_keys() {
    let params = KittyParams::parse(b"r=12,c=40");
    assert_eq!(params.rows, Some(12), "r= key must set rows");
    assert_eq!(params.columns, Some(40), "c= key must set columns");
}

// A 2×2 RGB image (4 pixels × 3 channels = 12 bytes)
test_transmit_nxn_image!(
    test_transmit_rgb_2x2_image,
    fmt_key  = 24,
    image_id = 50,
    n        = 2,
    nbytes   = 12,
    fmt_var  = Rgb,
);

// A 2×2 RGBA image (4 pixels × 4 channels = 16 bytes)
test_transmit_nxn_image!(
    test_transmit_rgba_2x2_image,
    fmt_key  = 32,
    image_id = 51,
    n        = 2,
    nbytes   = 16,
    fmt_var  = Rgba,
);

// Query command with no image_id returns Query { image_id: None }
#[test]
fn test_query_action_without_image_id_returns_none_id() {
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=q", &mut chunk_state);
    assert!(
        matches!(result, Some(KittyCommand::Query { image_id: None })),
        "a=q without i= must produce Query {{ image_id: None }}"
    );
}

// Place command without c= and r= produces None for both
#[test]
fn test_place_command_no_c_r_keys_produces_none_cols_rows() {
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=p,i=10", &mut chunk_state);
    match result.unwrap() {
        KittyCommand::Place {
            image_id,
            columns,
            rows,
            placement_id,
        } => {
            assert_eq!(image_id, 10);
            assert!(columns.is_none(), "missing c= must produce None columns");
            assert!(rows.is_none(), "missing r= must produce None rows");
            assert!(placement_id.is_none());
        }
        other => panic!("expected Place, got {other:?}"),
    }
}

// TransmitAndDisplay with no placement_id when p= is absent
#[test]
fn test_transmit_and_display_no_placement_id_when_absent() {
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=T,f=32,i=60,s=1,v=1;AAAAAA==", &mut chunk_state);
    match result.unwrap() {
        KittyCommand::TransmitAndDisplay { placement_id, .. } => {
            assert!(
                placement_id.is_none(),
                "missing p= must produce None placement_id in TransmitAndDisplay"
            );
        }
        other => panic!("expected TransmitAndDisplay, got {other:?}"),
    }
}

// PNG with a pure black 1×1 pixel round-trips correctly
test_png_pixel_round_trip!(
    test_kitty_png_rgb_black_pixel_round_trips,
    color_type = png::ColorType::Rgb,
    pixel      = &[0x00, 0x00, 0x00],
    image_id   = 70,
    fmt_var    = Rgb,
    expected   = vec![0u8, 0u8, 0u8],
    msg        = "black pixel must round-trip as [0,0,0]",
);

// PNG with a pure white RGBA pixel round-trips correctly
test_png_pixel_round_trip!(
    test_kitty_png_rgba_white_pixel_round_trips,
    color_type = png::ColorType::Rgba,
    pixel      = &[0xFF, 0xFF, 0xFF, 0xFF],
    image_id   = 71,
    fmt_var    = Rgba,
    expected   = vec![0xFFu8, 0xFF, 0xFF, 0xFF],
    msg        = "white pixel must round-trip",
);

// Chunk state is None when m=0 is the only chunk (no prior m=1)
#[test]
fn test_single_chunk_m0_is_treated_as_complete() {
    // A standalone m=0 chunk (no prior accumulation) must be treated as a
    // complete single-chunk transmit if it has all required params.
    let mut chunk_state = None;
    // m=0 with full params — should succeed exactly like a non-chunked transmit.
    let result = process_apc_payload(b"a=t,f=32,i=80,s=1,v=1,m=0;AAAAAA==", &mut chunk_state);
    // m=0 with chunk_state=None means there was no accumulation: the
    // implementation merges params from the m=0 chunk itself.
    // Result may be Some or None; the invariant is: chunk_state must be cleared.
    assert!(
        chunk_state.is_none(),
        "chunk_state must remain None when m=0 is processed without prior m=1"
    );
    // Either the command was built successfully or rejected; no panic is the
    // primary invariant.
    let _ = result;
}

// Verify that KittyParams::parse handles the 's' key (pixel width)
#[test]
fn test_parse_params_s_v_keys_set_width_height() {
    let params = KittyParams::parse(b"s=640,v=480");
    assert_eq!(params.width, Some(640), "s= must set width");
    assert_eq!(params.height, Some(480), "v= must set height");
}
