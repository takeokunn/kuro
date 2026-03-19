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
            assert_eq!(image_id, Some(9), "image_id must match the first-chunk param");
            assert_eq!(format, ImageFormat::Rgb, "format must be Rgb (f=24)");
            assert_eq!(pixel_width, 1, "pixel_width must match s=1");
            assert_eq!(pixel_height, 3, "pixel_height must match v=3");
            assert_eq!(
                pixels.len(),
                9,
                "final payload must be 9 bytes (3 chunks × 3 bytes each)"
            );
        }
        other => panic!("expected KittyCommand::Transmit, got {:?}", other),
    }
}

proptest! {
    #[test]
    fn prop_kitty_params_parse_no_panic(data in any::<Vec<u8>>()) {
        // must not panic on arbitrary input
        let _ = KittyParams::parse(&data);
    }
}
