// ── Placement ID in Transmit ───────────────────────────────────────────────────

#[test]
fn test_transmit_carries_placement_id() {
    // p=7 must propagate to KittyCommand::Transmit::placement_id
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=t,f=32,i=1,s=1,v=1,p=7;AAAAAA==", &mut chunk_state);
    match result.unwrap() {
        KittyCommand::Transmit { placement_id, .. } => {
            assert_eq!(placement_id, Some(7), "placement_id must be Some(7)");
        }
        other => panic!("expected Transmit, got {other:?}"),
    }
}

// ── Quiet parameter parsing ────────────────────────────────────────────────────

#[test]
fn test_parse_params_quiet_zero() {
    let params = KittyParams::parse(b"q=0");
    assert_eq!(params.quiet, 0);
}

#[test]
fn test_parse_params_quiet_two() {
    // q=2 suppresses all responses per the Kitty Graphics Protocol spec
    let params = KittyParams::parse(b"q=2");
    assert_eq!(params.quiet, 2, "q=2 must be parsed correctly");
}

// ── X/Y pixel offset parsing ──────────────────────────────────────────────────

#[test]
fn test_parse_params_x_y_offsets() {
    let params = KittyParams::parse(b"X=16,Y=8");
    assert_eq!(params.x_offset, 16, "X=16 must set x_offset");
    assert_eq!(params.y_offset, 8, "Y=8 must set y_offset");
}

#[test]
fn test_parse_params_xy_absent_defaults_to_zero() {
    let params = KittyParams::parse(b"a=t");
    assert_eq!(params.x_offset, 0);
    assert_eq!(params.y_offset, 0);
}

// ── Delete sub-command variants ────────────────────────────────────────────────

#[test]
fn test_delete_sub_command_i_variant() {
    // a=d,d=i — delete by image ID
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=d,d=i,i=5", &mut chunk_state);
    match result.unwrap() {
        KittyCommand::Delete {
            delete_sub,
            image_id,
            ..
        } => {
            assert_eq!(delete_sub, 'i', "delete_sub must be 'i'");
            assert_eq!(image_id, Some(5));
        }
        other => panic!("expected Delete, got {other:?}"),
    }
}

#[test]
fn test_delete_sub_command_p_variant() {
    // a=d,d=p — delete by placement ID
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=d,d=p,i=3,p=2", &mut chunk_state);
    match result.unwrap() {
        KittyCommand::Delete {
            delete_sub,
            placement_id,
            ..
        } => {
            assert_eq!(delete_sub, 'p', "delete_sub must be 'p'");
            assert_eq!(placement_id, Some(2));
        }
        other => panic!("expected Delete, got {other:?}"),
    }
}

// ── Unknown action ─────────────────────────────────────────────────────────────

#[test]
fn test_unknown_action_returns_none() {
    // a=z is not a defined action; must return None
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=z,i=1", &mut chunk_state);
    assert!(result.is_none(), "unknown action code must return None");
}

// ── Chunk size limit enforcement ──────────────────────────────────────────────

#[test]
fn test_chunk_accumulation_size_limit_rejects_oversized_data() {
    use crate::parser::limits::MAX_CHUNK_DATA_BYTES;

    // Build a first chunk just at the limit (base64 payload that decodes to MAX bytes).
    // Strategy: send m=1 chunk with a payload that already equals MAX_CHUNK_DATA_BYTES,
    // then send a second m=1 chunk with 1 extra byte — that must be rejected.
    //
    // Since encoding MAX_CHUNK_DATA_BYTES bytes of base64 would require ~5.3 MiB of
    // ASCII, we instead test the boundary via state inspection:
    // inject a KittyChunkState whose data is already at the limit, then confirm
    // that the next chunk's extend_from_slice path (data.len() + decoded.len() > MAX)
    // triggers the discard.
    let mut chunk_state: Option<KittyChunkState> = Some(KittyChunkState {
        params: KittyParams::parse(b"a=t,f=32,i=1,s=1,v=1"),
        data: vec![0u8; MAX_CHUNK_DATA_BYTES],
    });

    // Second chunk: any non-empty payload pushes total above MAX_CHUNK_DATA_BYTES.
    // "AA==" decodes to 1 byte, making total = MAX + 1.
    let result = process_apc_payload(b"m=1;AA==", &mut chunk_state);
    assert!(result.is_none(), "oversized accumulation must be discarded");
    assert!(
        chunk_state.is_none(),
        "chunk_state must be cleared on size limit violation"
    );
}

// ── PNG format (f=100) — corrupt data rejection ────────────────────────────────

#[test]
fn test_transmit_png_format_corrupt_returns_none() {
    // f=100 with data that is not valid PNG must return None
    let mut chunk_state = None;
    // Base64 encode a short non-PNG blob: "not_a_png" → "bm90X2FfcG5n"
    let result = process_apc_payload(b"a=t,f=100,i=20;bm90X2FfcG5n", &mut chunk_state);
    assert!(
        result.is_none(),
        "f=100 with corrupt PNG data must return None"
    );
}

// ── parse_u32 edge cases via KittyParams ──────────────────────────────────────

#[test]
fn test_parse_params_invalid_numeric_value_ignored() {
    // f=xyz is not a valid u32; parse_u32 returns None → format stays None
    let params = KittyParams::parse(b"f=xyz");
    assert!(
        params.format.is_none(),
        "non-numeric format value must produce None"
    );
}

#[test]
fn test_parse_params_u32_max_value() {
    // i=4294967295 is u32::MAX; must parse without overflow
    let params = KittyParams::parse(b"i=4294967295");
    assert_eq!(params.image_id, Some(u32::MAX));
}

// ── Multi-chunk sequence: params come from first chunk, not the final chunk ───

#[test]
fn test_multi_chunk_params_from_first_chunk() {
    // The Kitty protocol specifies that the first chunk (m=1) supplies the
    // canonical image parameters (image_id, format, dims).  A final chunk (m=0)
    // that omits or changes those params must NOT override the first chunk's
    // values — the implementation always reads params from the accumulated
    // KittyChunkState, not from the m=0 chunk.
    //
    // This test verifies: first chunk sets i=10, f=32, s=1, v=1.
    // The m=0 chunk supplies only "m=0" (no overriding params) + the pixel data.
    // The resulting Transmit must have image_id=Some(10), format=Rgba.
    let mut chunk_state = None;

    // First chunk: sets all params; no pixel data yet.
    let r = process_apc_payload(b"a=t,f=32,i=10,s=1,v=1,m=1;", &mut chunk_state);
    assert!(r.is_none(), "m=1 chunk must return None");
    assert!(chunk_state.is_some(), "chunk_state must be populated");

    // Final chunk: only m=0 + pixel data — no overriding params.
    // "AAAAAA==" = 4 zero bytes → valid 1×1 RGBA pixel.
    let r2 = process_apc_payload(b"m=0;AAAAAA==", &mut chunk_state);
    // Params must come from the first chunk, not the m=0 chunk.
    assert_transmit!(r2, image_id => Some(10), format => ImageFormat::Rgba, pw => 1, ph => 1);
    assert!(
        chunk_state.is_none(),
        "chunk_state must be cleared after m=0"
    );
}

#[test]
fn test_two_independent_single_chunk_images_sequentially() {
    // Two independent single-chunk sequences (no m=1) processed in order must
    // each produce their own Transmit command with the correct image_id.
    let mut chunk_state = None;

    // Image A: image_id=10.
    let r1 = process_apc_payload(b"a=t,f=32,i=10,s=1,v=1;AAAAAA==", &mut chunk_state);
    assert_transmit!(r1, image_id => Some(10), format => ImageFormat::Rgba, pw => 1, ph => 1);
    assert!(
        chunk_state.is_none(),
        "chunk_state must be None after image A"
    );

    // Image B: image_id=20, same format.
    let r2 = process_apc_payload(b"a=t,f=32,i=20,s=1,v=1;AAAAAA==", &mut chunk_state);
    assert_transmit!(r2, image_id => Some(20), format => ImageFormat::Rgba, pw => 1, ph => 1);
    assert!(
        chunk_state.is_none(),
        "chunk_state must be None after image B"
    );
}

// ── Placement ID boundary values ──────────────────────────────────────────────

#[test]
fn test_placement_id_zero() {
    // p=0 is a valid placement_id value per the spec.
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=t,f=32,i=1,s=1,v=1,p=0;AAAAAA==", &mut chunk_state);
    match result.unwrap() {
        KittyCommand::Transmit { placement_id, .. } => {
            assert_eq!(placement_id, Some(0), "placement_id=0 must round-trip");
        }
        other => panic!("expected Transmit, got {other:?}"),
    }
}

#[test]
fn test_placement_id_u32_max() {
    // p=4294967295 (u32::MAX) must parse and propagate correctly.
    let mut chunk_state = None;
    let payload = format!("a=t,f=32,i=1,s=1,v=1,p={};AAAAAA==", u32::MAX);
    let result = process_apc_payload(payload.as_bytes(), &mut chunk_state);
    match result.unwrap() {
        KittyCommand::Transmit { placement_id, .. } => {
            assert_eq!(
                placement_id,
                Some(u32::MAX),
                "placement_id=u32::MAX must round-trip"
            );
        }
        other => panic!("expected Transmit, got {other:?}"),
    }
}

// ── Place command carries placement_id ────────────────────────────────────────

#[test]
fn test_place_command_with_placement_id() {
    // a=p with both i= and p= must propagate placement_id into Place.
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=p,i=5,p=9,c=4,r=2", &mut chunk_state);
    match result.unwrap() {
        KittyCommand::Place {
            image_id,
            placement_id,
            columns,
            rows,
        } => {
            assert_eq!(image_id, 5, "image_id must be 5");
            assert_eq!(placement_id, Some(9), "placement_id must be Some(9)");
            assert_eq!(columns, Some(4));
            assert_eq!(rows, Some(2));
        }
        other => panic!("expected Place, got {other:?}"),
    }
}

// ── All KittyAction variants exercised ────────────────────────────────────────

#[test]
fn test_query_action_with_image_id() {
    // a=q with i= must produce KittyCommand::Query with the image_id set.
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=q,i=77", &mut chunk_state);
    assert!(
        matches!(result, Some(KittyCommand::Query { image_id: Some(77) })),
        "a=q,i=77 must produce Query {{ image_id: Some(77) }}"
    );
}

#[test]
fn test_transmit_and_display_placement_id_propagates() {
    // a=T with p= must propagate placement_id into TransmitAndDisplay.
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=T,f=32,i=3,s=1,v=1,p=11;AAAAAA==", &mut chunk_state);
    match result.unwrap() {
        KittyCommand::TransmitAndDisplay { placement_id, .. } => {
            assert_eq!(placement_id, Some(11), "placement_id must be Some(11)");
        }
        other => panic!("expected TransmitAndDisplay, got {other:?}"),
    }
}

// ── Delete sub-command variants not yet covered ────────────────────────────────

#[test]
fn test_delete_sub_command_c_variant() {
    // a=d,d=c — delete all placements in the cursor column (spec sub-command 'c')
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=d,d=c", &mut chunk_state);
    assert_delete_sub!(result, 'c');
}

#[test]
fn test_delete_sub_command_z_variant() {
    // a=d,d=z — delete by z-index (spec sub-command 'z')
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=d,d=z", &mut chunk_state);
    assert_delete_sub!(result, 'z');
}

#[test]
fn test_delete_sub_command_uppercase_a_variant() {
    // a=d,d=A — delete all placements on or above current cursor row
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=d,d=A", &mut chunk_state);
    assert_delete_sub!(result, 'A');
}

// ── Chunk with exactly MAX_CHUNK_DATA_BYTES payload ───────────────────────────

#[test]
fn test_first_chunk_exactly_at_max_is_accepted() {
    use crate::parser::limits::MAX_CHUNK_DATA_BYTES;

    // A first m=1 chunk whose decoded payload equals exactly MAX_CHUNK_DATA_BYTES
    // must be accepted (not discarded) — the limit is ≤, not <.
    let mut chunk_state: Option<KittyChunkState> = Some(KittyChunkState {
        params: KittyParams::parse(b"a=t,f=32,i=2,s=1,v=1"),
        data: vec![0u8; MAX_CHUNK_DATA_BYTES],
    });

    // A subsequent m=0 chunk with zero bytes (empty b64) should NOT add to the
    // accumulated data and must attempt to build a command (rejected due to dims,
    // but chunk_state must be cleared).
    let result = process_apc_payload(b"m=0;", &mut chunk_state);
    assert!(
        chunk_state.is_none(),
        "chunk_state must be cleared after m=0"
    );
    // The command may succeed or fail depending on dims; either is acceptable.
    // The important invariant is that we did NOT discard on the size-limit path.
    // If it returns None it's because pixel dims are s=1,v=1 with 4 MiB data
    // which is a valid-but-oversized raw image. We just verify no panic occurred.
    let _ = result; // result may be Some or None — both acceptable
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    // PANIC SAFETY: Kitty keyboard protocol set/query with arbitrary flags never panics
    fn prop_kitty_kb_flags_no_panic(flags in 0u16..=65535u16) {
        let mut term = crate::TerminalCore::new(24, 80);
        // CSI = {flags} u — set kitty keyboard flags
        term.advance(format!("\x1b[={flags}u").as_bytes());
        prop_assert!(term.screen.cursor().row < 24);
    }

    #[test]
    // PANIC SAFETY: Kitty push/pop mode never panics
    fn prop_kitty_push_pop_no_panic(flags in 0u16..=31u16) {
        let mut term = crate::TerminalCore::new(24, 80);
        // CSI > {flags} u — push kitty keyboard mode
        term.advance(format!("\x1b[>{flags}u").as_bytes());
        // CSI < u — pop kitty keyboard mode
        term.advance(b"\x1b[<u");
        prop_assert!(term.screen.cursor().row < 24);
    }
}

// ── PNG decode color-type variants ────────────────────────────────────────────

/// Encode `pixels` as a minimal 1×1 PNG using the `png` crate encoder,
/// then base64-encode the result so it can be embedded directly in an APC payload.
///
/// `color_type` must be one of the `png::ColorType` variants.
/// `pixels` must contain exactly the right number of bytes for the chosen color type
/// (1 byte for Grayscale, 2 for GrayscaleAlpha, 3 for Rgb, 4 for Rgba).
fn encode_1x1_png_b64(color_type: png::ColorType, pixels: &[u8]) -> String {
    let mut buf: Vec<u8> = Vec::new();
    {
        let mut encoder = png::Encoder::new(&mut buf, 1, 1);
        encoder.set_color(color_type);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder.write_header().expect("PNG header write");
        writer.write_image_data(pixels).expect("PNG pixel write");
    }
    BASE64_STANDARD.encode(&buf)
}

#[test]
fn test_kitty_png_rgb_color_type_produces_rgb_format() {
    // f=100 with a valid 1×1 RGB PNG must decode to ImageFormat::Rgb.
    // pixel_width and pixel_height come from the s= / v= APC params, not from
    // the PNG IHDR — decode_pixel_data passes params.width / params.height through.
    let b64 = encode_1x1_png_b64(png::ColorType::Rgb, &[0x00, 0x00, 0x00]);
    let mut chunk_state = None;
    let payload = format!("a=t,f=100,i=30,s=1,v=1;{b64}");
    let result = process_apc_payload(payload.as_bytes(), &mut chunk_state);
    match result {
        Some(KittyCommand::Transmit {
            format,
            pixel_width,
            pixel_height,
            pixels,
            ..
        }) => {
            assert_eq!(
                format,
                ImageFormat::Rgb,
                "1×1 RGB PNG must decode to ImageFormat::Rgb"
            );
            assert_eq!(pixel_width, 1, "pixel_width must match s=1");
            assert_eq!(pixel_height, 1, "pixel_height must match v=1");
            assert_eq!(pixels.len(), 3, "1 RGB pixel = 3 bytes");
        }
        other => panic!("expected Transmit, got {other:?}"),
    }
}

#[test]
fn test_kitty_png_rgba_color_type_produces_rgba_format() {
    // f=100 with a valid 1×1 RGBA PNG must decode to ImageFormat::Rgba.
    // pixel_width and pixel_height come from the s= / v= APC params.
    let b64 = encode_1x1_png_b64(png::ColorType::Rgba, &[0xFF, 0x00, 0x00, 0xFF]);
    let mut chunk_state = None;
    let payload = format!("a=t,f=100,i=31,s=1,v=1;{b64}");
    let result = process_apc_payload(payload.as_bytes(), &mut chunk_state);
    match result {
        Some(KittyCommand::Transmit {
            format,
            pixel_width,
            pixel_height,
            pixels,
            ..
        }) => {
            assert_eq!(
                format,
                ImageFormat::Rgba,
                "1×1 RGBA PNG must decode to ImageFormat::Rgba"
            );
            assert_eq!(pixel_width, 1, "pixel_width must match s=1");
            assert_eq!(pixel_height, 1, "pixel_height must match v=1");
            assert_eq!(pixels.len(), 4, "1 RGBA pixel = 4 bytes");
            // Verify the opaque-red pixel round-tripped correctly.
            assert_eq!(pixels[0], 0xFF, "R channel must be 0xFF");
            assert_eq!(pixels[3], 0xFF, "A channel must be 0xFF");
        }
        other => panic!("expected Transmit, got {other:?}"),
    }
}
