//! Property-based and example-based tests for `kitty` parsing.
//!
//! Module under test: `parser/kitty.rs`
//! Tier: T3 — `ProptestConfig::with_cases(256)`

use super::*;
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

include!("kitty_params.rs");
include!("kitty_png.rs");
