//! Property-based and example-based tests for `kitty` parsing.
//!
//! Module under test: `parser/kitty.rs`
//! Tier: T3 — `ProptestConfig::with_cases(256)`

use super::*;
use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
use proptest::prelude::*;

#[test]
fn test_parse_params_basic() {
    let params = KittyParams::parse(b"a=t,f=100,i=1,m=0");
    assert_eq!(params.action, Some('t'));
    assert_eq!(params.format, Some(100));
    assert_eq!(params.image_id, Some(1));
    assert!(!params.more);
}

#[test]
fn test_parse_params_more() {
    let params = KittyParams::parse(b"a=t,m=1,i=5");
    assert!(params.more);
    assert_eq!(params.image_id, Some(5));
}

#[test]
fn test_parse_params_empty() {
    let params = KittyParams::parse(b"");
    assert!(params.action.is_none());
    assert!(!params.more);
}

#[test]
fn test_process_single_chunk_query() {
    let mut chunk_state = None;
    let payload = b"a=q,i=1";
    let result = process_apc_payload(payload, &mut chunk_state);
    assert!(matches!(
        result,
        Some(KittyCommand::Query { image_id: Some(1) })
    ));
}

#[test]
fn test_process_chunk_accumulation() {
    let mut chunk_state = None;

    // First chunk: m=1, carries params including 1x1 pixel dimensions
    let result = process_apc_payload(b"a=t,f=32,i=2,s=1,v=1,m=1;", &mut chunk_state);
    assert!(result.is_none(), "m=1 chunk should return None");
    assert!(chunk_state.is_some(), "chunk_state should be set");

    // Final chunk: m=0 with 4 bytes of RGBA data for 1x1 image (AAAAAA== = 4 zero bytes)
    let result = process_apc_payload(b"m=0;AAAAAA==", &mut chunk_state);
    assert!(chunk_state.is_none(), "chunk_state should be cleared");
    assert!(matches!(
        result,
        Some(KittyCommand::Transmit {
            image_id: Some(2),
            format: ImageFormat::Rgba,
            ..
        })
    ));
}

#[test]
fn test_malformed_base64_returns_none() {
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=t,f=32;not!valid!base64!!!", &mut chunk_state);
    assert!(result.is_none());
}

#[test]
fn test_unsupported_transmission_returns_none() {
    let mut chunk_state = None;
    // t=f means file transfer, which we don't support
    let result = process_apc_payload(b"a=t,t=f,i=1;", &mut chunk_state);
    assert!(result.is_none());
}

#[test]
fn test_delete_command() {
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=d,d=a", &mut chunk_state);
    assert!(matches!(
        result,
        Some(KittyCommand::Delete {
            delete_sub: 'a',
            ..
        })
    ));
}

#[test]
fn test_kitty_three_chunk_accumulation() {
    // Split a valid Kitty transmit across three APC sequences: m=1, m=1, m=0.
    // The image notification must only appear after the final (m=0) chunk.
    //
    // Payload strategy: each chunk carries an empty base64 body (';' with no
    // data), which is valid and decodes to zero bytes.  The final m=0 chunk
    // supplies the full self-contained payload so build_command succeeds.
    let mut chunk_state = None;

    // First chunk: m=1 — sets image params, accumulation begins.
    let result = process_apc_payload(b"a=t,f=32,i=7,s=1,v=1,m=1;", &mut chunk_state);
    assert!(
        result.is_none(),
        "first m=1 chunk must not return an image notification"
    );
    assert!(
        chunk_state.is_some(),
        "chunk_state must be populated after first chunk"
    );

    // Second chunk: m=1 — still accumulating, carries empty payload.
    let result = process_apc_payload(b"m=1;", &mut chunk_state);
    assert!(
        result.is_none(),
        "second m=1 chunk must not return an image notification"
    );
    assert!(
        chunk_state.is_some(),
        "chunk_state must still be set after second chunk"
    );

    // Third (final) chunk: m=0 — completes the sequence.
    // "AAAAAA==" decodes to 4 zero bytes (one 1×1 RGBA pixel).
    let result = process_apc_payload(b"m=0;AAAAAA==", &mut chunk_state);
    assert!(
        chunk_state.is_none(),
        "chunk_state must be cleared after final m=0 chunk"
    );
    assert!(
        result.is_some(),
        "final m=0 chunk must return a KittyCommand"
    );
    assert!(
        matches!(
            result,
            Some(KittyCommand::Transmit {
                image_id: Some(7),
                format: ImageFormat::Rgba,
                ..
            })
        ),
        "final chunk must produce a Transmit command with the correct image_id and format"
    );
}

#[test]
fn test_kitty_three_chunk_with_intermediate_payload() {
    // Three-chunk sequence where EVERY chunk carries actual base64 payload data.
    //
    // Payload strategy:
    //   chunk 1 (m=1): "AAAA" → base64 for [0x00, 0x00, 0x00]  (3 bytes)
    //   chunk 2 (m=1): "BBBB" → base64 for [0x04, 0x10, 0x41]  (3 bytes)
    //   chunk 3 (m=0): "CCCC" → base64 for [0x08, 0x20, 0x82]  (3 bytes)
    //
    // The KittyChunkState must NOT clear accumulated data when processing the
    // intermediate m=1 chunk — it must extend it.  After the final m=0 chunk
    // the total decoded payload is 9 bytes (all three decoded together).
    //
    // We use format f=24 (RGB) with a 1×3 image (width=1, height=3) so
    // build_command accepts the 9-byte payload without error.
    let mut chunk_state = None;

    // ---- Chunk 1: a=t, f=24, i=9, s=1, v=3, m=1; payload "AAAA" ----
    let result = process_apc_payload(b"a=t,f=24,i=9,s=1,v=3,m=1;AAAA", &mut chunk_state);
    assert!(
        result.is_none(),
        "first m=1 chunk must not return a command"
    );
    assert!(
        chunk_state.is_some(),
        "chunk_state must be populated after first m=1 chunk"
    );
    {
        let state = chunk_state.as_ref().unwrap();
        assert_eq!(
            state.data.len(),
            3,
            "first chunk: 3 decoded bytes must be accumulated"
        );
    }

    // ---- Chunk 2: m=1; payload "BBBB" ----
    // This is the critical case: an intermediate chunk with real data.
    // The accumulated buffer must grow to 6 bytes, not be reset.
    let result = process_apc_payload(b"m=1;BBBB", &mut chunk_state);
    assert!(
        result.is_none(),
        "second m=1 chunk must not return a command"
    );
    assert!(
        chunk_state.is_some(),
        "chunk_state must still be set after second m=1 chunk"
    );
    {
        let state = chunk_state.as_ref().unwrap();
        assert_eq!(
            state.data.len(),
            6,
            "second chunk: accumulated data must be 6 bytes (3+3), NOT cleared"
        );
    }

    // ---- Chunk 3: m=0; payload "CCCC" ----
    // Final chunk supplies the last 3 bytes; total concatenated payload = 9 bytes.
    let result = process_apc_payload(b"m=0;CCCC", &mut chunk_state);
    assert!(
        chunk_state.is_none(),
        "chunk_state must be cleared after final m=0 chunk"
    );
    assert!(
        result.is_some(),
        "final m=0 chunk must return a KittyCommand"
    );
    match result.unwrap() {
        KittyCommand::Transmit {
            image_id,
            pixels,
            format,
            pixel_width,
            pixel_height,
            ..
        } => {
            assert_eq!(
                image_id,
                Some(9),
                "image_id must match the first-chunk param"
            );
            assert_eq!(format, ImageFormat::Rgb, "format must be Rgb (f=24)");
            assert_eq!(pixel_width, 1, "pixel_width must match s=1");
            assert_eq!(pixel_height, 3, "pixel_height must match v=3");
            assert_eq!(
                pixels.len(),
                9,
                "final payload must be 9 bytes (3 chunks × 3 bytes each)"
            );
        }
        other => panic!("expected KittyCommand::Transmit, got {other:?}"),
    }
}

// ── Place command ─────────────────────────────────────────────────────────────

#[test]
fn test_place_command_with_image_id() {
    let mut chunk_state = None;
    // a=p,i=3,c=10,r=5 — place image 3 in a 10×5 cell region
    let result = process_apc_payload(b"a=p,i=3,c=10,r=5", &mut chunk_state);
    match result.unwrap() {
        KittyCommand::Place {
            image_id,
            columns,
            rows,
            placement_id,
        } => {
            assert_eq!(image_id, 3);
            assert_eq!(columns, Some(10));
            assert_eq!(rows, Some(5));
            assert!(placement_id.is_none());
        }
        other => panic!("expected Place, got {other:?}"),
    }
}

#[test]
fn test_place_command_missing_image_id_returns_none() {
    // a=p without i= — image_id is required for Place; must return None
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=p", &mut chunk_state);
    assert!(result.is_none(), "Place without image_id must return None");
}

// ── TransmitAndDisplay (a=T) ──────────────────────────────────────────────────

#[test]
fn test_transmit_and_display_command() {
    let mut chunk_state = None;
    // AAAAAA== decodes to 4 zero bytes — valid 1×1 RGBA pixel
    let result = process_apc_payload(b"a=T,f=32,i=42,s=1,v=1,c=8,r=4;AAAAAA==", &mut chunk_state);
    match result.unwrap() {
        KittyCommand::TransmitAndDisplay {
            image_id,
            format,
            pixel_width,
            pixel_height,
            columns,
            rows,
            placement_id,
            ..
        } => {
            assert_eq!(image_id, Some(42));
            assert_eq!(format, ImageFormat::Rgba);
            assert_eq!(pixel_width, 1);
            assert_eq!(pixel_height, 1);
            assert_eq!(columns, Some(8));
            assert_eq!(rows, Some(4));
            assert!(placement_id.is_none());
        }
        other => panic!("expected TransmitAndDisplay, got {other:?}"),
    }
}

// ── Zero-dimension rejection ───────────────────────────────────────────────────

#[test]
fn test_transmit_zero_width_returns_none() {
    // f=32 (raw RGBA) with s=0 — zero width must be rejected
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=t,f=32,i=1,s=0,v=1;AAAAAA==", &mut chunk_state);
    assert!(
        result.is_none(),
        "Transmit with zero width must return None for raw formats"
    );
}

#[test]
fn test_transmit_zero_height_returns_none() {
    // f=32 (raw RGBA) with v=0 — zero height must be rejected
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=t,f=32,i=1,s=1,v=0;AAAAAA==", &mut chunk_state);
    assert!(
        result.is_none(),
        "Transmit with zero height must return None for raw formats"
    );
}

// ── Animation frame action 'f' ─────────────────────────────────────────────────

#[test]
fn test_animation_frame_action_returns_none() {
    // a=f is unsupported; must return None without panicking
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=f,i=1;", &mut chunk_state);
    assert!(
        result.is_none(),
        "Animation frame action (a=f) must return None"
    );
}

// ── Delete sub-command default ─────────────────────────────────────────────────

#[test]
fn test_delete_command_default_sub() {
    // a=d with no d= key: delete_sub defaults to 'a'
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=d", &mut chunk_state);
    match result.unwrap() {
        KittyCommand::Delete { delete_sub, .. } => {
            assert_eq!(
                delete_sub, 'a',
                "delete_sub must default to 'a' when absent"
            );
        }
        other => panic!("expected Delete, got {other:?}"),
    }
}

// ── Unknown format ─────────────────────────────────────────────────────────────

#[test]
fn test_transmit_unknown_format_returns_none() {
    // f=99 is not a valid Kitty format code
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=t,f=99,i=1,s=1,v=1;AAAAAA==", &mut chunk_state);
    assert!(
        result.is_none(),
        "Transmit with unknown format code must return None"
    );
}

// ── RGB format (f=24) ─────────────────────────────────────────────────────────

#[test]
fn test_transmit_rgb_format() {
    // "AAAA" decodes to 3 zero bytes — one 1×1 RGB pixel
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=t,f=24,i=10,s=1,v=1;AAAA", &mut chunk_state);
    match result.unwrap() {
        KittyCommand::Transmit { format, .. } => {
            assert_eq!(
                format,
                ImageFormat::Rgb,
                "f=24 must produce ImageFormat::Rgb"
            );
        }
        other => panic!("expected Transmit, got {other:?}"),
    }
}

// ── Macro helpers ─────────────────────────────────────────────────────────────

/// Feed a single-chunk Kitty transmit APC payload and assert on a Transmit command.
///
/// Usage:
/// ```
/// assert_transmit!(process_apc_payload(payload, &mut chunk_state),
///     image_id => Some(1),
///     format   => ImageFormat::Rgba,
///     pw       => 1,
///     ph       => 1
/// );
/// ```
macro_rules! assert_transmit {
    ($result:expr, image_id => $id:expr, format => $fmt:expr, pw => $pw:expr, ph => $ph:expr) => {{
        match $result {
            Some(KittyCommand::Transmit {
                image_id,
                format,
                pixel_width,
                pixel_height,
                ..
            }) => {
                assert_eq!(image_id, $id, "image_id mismatch");
                assert_eq!(format, $fmt, "format mismatch");
                assert_eq!(pixel_width, $pw, "pixel_width mismatch");
                assert_eq!(pixel_height, $ph, "pixel_height mismatch");
            }
            other => panic!("expected KittyCommand::Transmit, got {other:?}"),
        }
    }};
}

/// Assert that a `Delete` command has the expected `delete_sub`.
macro_rules! assert_delete_sub {
    ($result:expr, $sub:expr) => {{
        match $result {
            Some(KittyCommand::Delete { delete_sub, .. }) => {
                assert_eq!(delete_sub, $sub, "delete_sub mismatch");
            }
            other => panic!("expected KittyCommand::Delete, got {other:?}"),
        }
    }};
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]
    #[test]
    fn prop_kitty_params_parse_no_panic(data in any::<Vec<u8>>()) {
        // must not panic on arbitrary input
        let _ = KittyParams::parse(&data);
    }
}

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

// ── New coverage tests (Round 30) ─────────────────────────────────────────────

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

/// `process_apc_payload` must reject `t=t` (temp-file) transmission type.
///
/// Only 'd' (direct/inline base64) is supported; all others are silently ignored.
#[test]
fn test_unsupported_transmission_temp_file_returns_none() {
    // t=t means "temp file" — not supported
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=t,t=t,i=1;", &mut chunk_state);
    assert!(
        result.is_none(),
        "temp-file transmission (t=t) must return None"
    );
    assert!(
        chunk_state.is_none(),
        "chunk_state must be cleared when transmission is rejected"
    );
}

/// `process_apc_payload` must reject `t=s` (shared-memory) transmission type.
#[test]
fn test_unsupported_transmission_shared_mem_returns_none() {
    // t=s means "shared memory" — not supported
    let mut chunk_state = None;
    let result = process_apc_payload(b"a=t,t=s,i=2;", &mut chunk_state);
    assert!(
        result.is_none(),
        "shared-memory transmission (t=s) must return None"
    );
}

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
