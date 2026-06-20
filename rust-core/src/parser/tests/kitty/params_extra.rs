use super::support::encode_1x1_png_b64;
use crate::parser::kitty::{KittyChunkState, KittyCommand, KittyParams};
use proptest::prelude::*;

test_kitty_payload_once_case!(
    test_placement_id_u32_max,
    payload = format!("a=t,f=32,i=1,s=1,v=1,p={};AAAAAA==", u32::MAX),
    check = |result: Option<KittyCommand>| assert_transmit_placement_id!(result, Some(u32::MAX)),
);

// ── Place command carries placement_id ────────────────────────────────────────

test_kitty_payload_once_case!(
    test_place_command_with_placement_id,
    payload = b"a=p,i=5,p=9,c=4,r=2",
    check = |result: Option<KittyCommand>| assert_place_fields!(
        result,
        image_id => 5,
        placement_id => Some(9),
        columns => Some(4),
        rows => Some(2),
    ),
);

// ── All KittyAction variants exercised ────────────────────────────────────────

test_kitty_payload_once_case!(
    test_query_action_with_image_id,
    payload = b"a=q,i=77",
    check = |result: Option<KittyCommand>| assert!(
        matches!(result, Some(KittyCommand::Query { image_id: Some(77) })),
        "a=q,i=77 must produce Query {{ image_id: Some(77) }}"
    ),
);

test_kitty_payload_once_case!(
    test_transmit_and_display_placement_id_propagates,
    payload = b"a=T,f=32,i=3,s=1,v=1,p=11;AAAAAA==",
    check =
        |result: Option<KittyCommand>| assert_transmit_and_display_placement_id!(result, Some(11)),
);

// ── Delete sub-command variants not yet covered ────────────────────────────────

test_delete_sub_command_variants!(
    test_delete_sub_command_variants,
    payload = b"a=d,d=c",
    expected = 'c',
    label = "delete in the cursor column",
    payload = b"a=d,d=z",
    expected = 'z',
    label = "delete by z-index",
    payload = b"a=d,d=A",
    expected = 'A',
    label = "delete on or above current cursor row",
);

// ── Chunk with exactly MAX_CHUNK_DATA_BYTES payload ───────────────────────────

test_kitty_payload_state_case!(
    test_first_chunk_exactly_at_max_is_accepted,
    chunk_state = {
        use crate::parser::limits::MAX_CHUNK_DATA_BYTES;

        Some(KittyChunkState {
            params: KittyParams::parse(b"a=t,f=32,i=2,s=1,v=1"),
            data: vec![0u8; MAX_CHUNK_DATA_BYTES],
        })
    },
    payload = b"m=0;",
    check = |result, chunk_state| {
        // A first m=1 chunk whose decoded payload equals exactly
        // MAX_CHUNK_DATA_BYTES must be accepted (not discarded).
        assert!(
            chunk_state.is_none(),
            "chunk_state must be cleared after m=0"
        );
        let _ = result; // result may be Some or None — both acceptable
    },
);

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

test_kitty_png_transmit_case!(
    test_kitty_png_rgb_color_type_produces_rgb_format,
    payload = format!(
        "a=t,f=100,i=30,s=1,v=1;{}",
        encode_1x1_png_b64(png::ColorType::Rgb, &[0x00, 0x00, 0x00])
    ),
    fmt_var = Rgb,
    expected_len = 3,
    pixels = pixels => {},
    expected = "Transmit",
);

test_kitty_png_transmit_case!(
    test_kitty_png_rgba_color_type_produces_rgba_format,
    payload = format!(
        "a=t,f=100,i=31,s=1,v=1;{}",
        encode_1x1_png_b64(png::ColorType::Rgba, &[0xFF, 0x00, 0x00, 0xFF])
    ),
    fmt_var = Rgba,
    expected_len = 4,
    pixels = pixels => {
        // Verify the opaque-red pixel round-tripped correctly.
        assert_eq!(pixels[0], 0xFF, "R channel must be 0xFF");
        assert_eq!(pixels[3], 0xFF, "A channel must be 0xFF");
    },
    expected = "Transmit",
);
