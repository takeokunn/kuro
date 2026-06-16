use crate::parser::kitty::{process_apc_payload, ImageFormat, KittyChunkState, KittyCommand, KittyParams};

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
