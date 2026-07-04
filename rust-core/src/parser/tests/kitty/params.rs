use crate::parser::kitty::{process_apc_payload, ImageFormat, KittyCommand, KittyParams};
use crate::parser::limits::MAX_CHUNK_DATA_BYTES;

// ── Placement ID in Transmit ───────────────────────────────────────────────────

test_kitty_payload_once_case!(
    test_transmit_carries_placement_id,
    payload = b"a=t,f=32,i=1,s=1,v=1,p=7;AAAAAA==",
    check = |result: Option<KittyCommand>| assert_transmit_placement_id!(result, Some(7)),
);

// ── Quiet parameter parsing ────────────────────────────────────────────────────

test_kitty_params_case!(
    test_parse_params_quiet_zero,
    params = b"q=0",
    check = |result: KittyParams| assert_eq!(result.quiet, 0),
);

test_kitty_params_case!(
    test_parse_params_quiet_two,
    params = b"q=2",
    check = |result: KittyParams| assert_eq!(result.quiet, 2, "q=2 must be parsed correctly"),
);

test_kitty_params_case!(
    test_parse_params_quiet_out_of_range_ignored,
    params = b"q=999",
    check = |result: KittyParams| assert_eq!(result.quiet, 0),
);

test_kitty_params_case!(
    test_parse_params_quiet_invalid_after_valid_keeps_valid_value,
    params = b"q=2,q=999",
    check = |result: KittyParams| assert_eq!(result.quiet, 2),
);

test_kitty_params_case!(
    test_parse_params_quiet_valid_after_invalid_sets_valid_value,
    params = b"q=999,q=1",
    check = |result: KittyParams| assert_eq!(result.quiet, 1),
);

test_kitty_params_case!(
    test_parse_params_quiet_non_numeric_after_valid_keeps_valid_value,
    params = b"q=2,q=nope",
    check = |result: KittyParams| assert_eq!(result.quiet, 2),
);

// ── X/Y pixel offset parsing ──────────────────────────────────────────────────

test_kitty_params_case!(
    test_parse_params_x_y_offsets,
    params = b"X=16,Y=8",
    check = |result: KittyParams| {
        assert_eq!(result.x_offset, 16, "X=16 must set x_offset");
        assert_eq!(result.y_offset, 8, "Y=8 must set y_offset");
    },
);

test_kitty_params_case!(
    test_parse_params_xy_absent_defaults_to_zero,
    params = b"a=t",
    check = |result: KittyParams| {
        assert_eq!(result.x_offset, 0);
        assert_eq!(result.y_offset, 0);
    },
);

// ── Delete sub-command variants ────────────────────────────────────────────────

test_kitty_payload_once_case!(
    test_delete_sub_command_i_variant,
    payload = b"a=d,d=i,i=5",
    check = |result: Option<KittyCommand>| assert_delete_sub_and!(result, 'i', image_id => Some(5)),
);

test_kitty_payload_once_case!(
    test_delete_sub_command_p_variant,
    payload = b"a=d,d=p,i=3,p=2",
    check =
        |result: Option<KittyCommand>| assert_delete_sub_and!(result, 'p', placement_id => Some(2)),
);

// ── Unknown action ─────────────────────────────────────────────────────────────

test_kitty_payload_once_case!(
    test_unknown_action_returns_none,
    payload = b"a=z,i=1",
    check = |result: Option<KittyCommand>| assert!(
        result.is_none(),
        "unknown action code must return None"
    ),
);

// ── Chunk size limit enforcement ──────────────────────────────────────────────

test_kitty_payload_state_case!(
    test_chunk_accumulation_size_limit_rejects_oversized_data,
    chunk_state = Some(crate::parser::kitty::KittyChunkState {
        params: KittyParams::parse(b"a=t,f=32,i=1,s=1,v=1"),
        data: vec![0u8; MAX_CHUNK_DATA_BYTES],
    }),
    payload = b"m=1;AA==",
    check = |result, chunk_state| {
        assert!(result.is_none(), "oversized accumulation must be discarded");
        assert!(
            chunk_state.is_none(),
            "chunk_state must be cleared on size limit violation"
        );
    },
);

// ── PNG format (f=100) — corrupt data rejection ────────────────────────────────

test_kitty_payload_state_case!(
    test_transmit_png_format_corrupt_returns_none,
    chunk_state = None,
    payload = b"a=t,f=100,i=20;bm90X2FfcG5n",
    check = |result: Option<KittyCommand>, chunk_state| {
        // f=100 with data that is not valid PNG must return None.
        assert!(
            result.is_none(),
            "f=100 with corrupt PNG data must return None"
        );
        assert!(
            chunk_state.is_none(),
            "chunk_state must be cleared after corrupt PNG"
        );
    },
);

// ── parse_u32 edge cases via KittyParams ──────────────────────────────────────

test_kitty_params_case!(
    test_parse_params_invalid_numeric_value_ignored,
    params = b"f=xyz",
    check = |result: KittyParams| {
        assert!(
            result.format.is_none(),
            "non-numeric format value must produce None"
        );
    },
);

test_kitty_params_case!(
    test_parse_params_u32_max_value,
    params = b"i=4294967295",
    check = |result: KittyParams| assert_eq!(result.image_id, Some(u32::MAX)),
);

// ── Multi-chunk sequence: params come from first chunk, not the final chunk ───

test_kitty_payload_state_case!(
    test_multi_chunk_params_from_first_chunk,
    chunk_state = None,
    payload = b"a=t,f=32,i=10,s=1,v=1,m=1;",
    check = |r, mut chunk_state| {
        // The Kitty protocol specifies that the first chunk (m=1) supplies the
        // canonical image parameters. A final m=0 chunk must not override them.
        assert!(r.is_none(), "m=1 chunk must return None");
        assert!(chunk_state.is_some(), "chunk_state must be populated");

        // "AAAAAA==" = 4 zero bytes → valid 1×1 RGBA pixel.
        let r2 = process_apc_payload(b"m=0;AAAAAA==", &mut chunk_state);
        assert_transmit!(
            r2,
            image_id => Some(10),
            format => ImageFormat::Rgba,
            pw => 1,
            ph => 1
        );
        assert!(
            chunk_state.is_none(),
            "chunk_state must be cleared after m=0"
        );
    },
);

test_kitty_payload_state_case!(
    test_two_independent_single_chunk_images_sequentially,
    chunk_state = None,
    payload = b"a=t,f=32,i=10,s=1,v=1;AAAAAA==",
    check = |r1, mut chunk_state| {
        // Two independent single-chunk sequences processed in order must each
        // produce their own Transmit command with the correct image_id.
        assert_transmit!(
            r1,
            image_id => Some(10),
            format => ImageFormat::Rgba,
            pw => 1,
            ph => 1
        );
        assert!(
            chunk_state.is_none(),
            "chunk_state must be None after image A"
        );

        let r2 = process_apc_payload(b"a=t,f=32,i=20,s=1,v=1;AAAAAA==", &mut chunk_state);
        assert_transmit!(
            r2,
            image_id => Some(20),
            format => ImageFormat::Rgba,
            pw => 1,
            ph => 1
        );
        assert!(
            chunk_state.is_none(),
            "chunk_state must be None after image B"
        );
    },
);

// ── Placement ID boundary values ──────────────────────────────────────────────

test_kitty_payload_once_case!(
    test_placement_id_zero,
    payload = b"a=t,f=32,i=1,s=1,v=1,p=0;AAAAAA==",
    check = |result: Option<KittyCommand>| assert_transmit_placement_id!(result, Some(0)),
);
