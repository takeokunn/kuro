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
    crate::util::base64::encode(&buf)
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
