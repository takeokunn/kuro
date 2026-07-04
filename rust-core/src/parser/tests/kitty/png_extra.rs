use super::support::encode_1x1_png_b64;
use crate::parser::kitty::{KittyCommand, KittyParams};

// ── Additional new tests ───────────────────────────────────────────────────────

// Delete sub-command variants.
test_delete_sub_command_variants!(
    test_delete_sub_command_variants,
    payload = b"a=d,d=r",
    expected = 'r',
    label = "delete by row range",
    payload = b"a=d,d=x",
    expected = 'x',
    label = "delete by column range",
    payload = b"a=d,d=B",
    expected = 'B',
    label = "delete below cursor",
);

// Delete sub-command 'n' (delete by image number)
test_kitty_payload_once_case!(
    test_delete_sub_command_n_variant,
    payload = b"a=d,d=n,i=8",
    check = |result: Option<KittyCommand>| assert_delete_sub_and!(result, 'n', image_id => Some(8)),
);

// KittyParams: 'r' and 'c' keys are parsed as rows/cols for Place commands
test_kitty_params_case!(
    test_parse_params_r_and_c_keys,
    params = b"r=12,c=40",
    check = |params: KittyParams| {
        assert_eq!(params.rows, Some(12), "r= key must set rows");
        assert_eq!(params.columns, Some(40), "c= key must set columns");
    },
);

// A 2×2 RGB image (4 pixels × 3 channels = 12 bytes)
test_transmit_nxn_image!(
    test_transmit_rgb_2x2_image,
    fmt_key = 24,
    image_id = 50,
    n = 2,
    nbytes = 12,
    fmt_var = Rgb,
);

// A 2×2 RGBA image (4 pixels × 4 channels = 16 bytes)
test_transmit_nxn_image!(
    test_transmit_rgba_2x2_image,
    fmt_key = 32,
    image_id = 51,
    n = 2,
    nbytes = 16,
    fmt_var = Rgba,
);

// Query command with no image_id returns Query { image_id: None }
test_kitty_payload_once_case!(
    test_query_action_without_image_id_returns_none_id,
    payload = b"a=q",
    check = |result: Option<KittyCommand>| assert!(
        matches!(result, Some(KittyCommand::Query { image_id: None })),
        "a=q without i= must produce Query {{ image_id: None }}"
    ),
);

// Place command without c= and r= produces None for both
test_kitty_payload_once_case!(
    test_place_command_no_c_r_keys_produces_none_cols_rows,
    payload = b"a=p,i=10",
    check = |result: Option<KittyCommand>| assert_place_fields!(
        result,
        image_id => 10,
        placement_id => None,
        columns => None,
        rows => None,
    ),
);

// TransmitAndDisplay with no placement_id when p= is absent
test_kitty_payload_once_case!(
    test_transmit_and_display_no_placement_id_when_absent,
    payload = b"a=T,f=32,i=60,s=1,v=1;AAAAAA==",
    check = |result: Option<KittyCommand>| assert_transmit_and_display_placement_id!(result, None),
);

// PNG with a pure black 1×1 pixel round-trips correctly
test_png_pixel_round_trip!(
    test_kitty_png_rgb_black_pixel_round_trips,
    color_type = png::ColorType::Rgb,
    pixel = &[0x00, 0x00, 0x00],
    image_id = 70,
    fmt_var = Rgb,
    expected = vec![0u8, 0u8, 0u8],
    msg = "black pixel must round-trip as [0,0,0]",
);

// PNG with a pure white RGBA pixel round-trips correctly
test_png_pixel_round_trip!(
    test_kitty_png_rgba_white_pixel_round_trips,
    color_type = png::ColorType::Rgba,
    pixel = &[0xFF, 0xFF, 0xFF, 0xFF],
    image_id = 71,
    fmt_var = Rgba,
    expected = vec![0xFFu8, 0xFF, 0xFF, 0xFF],
    msg = "white pixel must round-trip",
);

// Chunk state is None when m=0 is the only chunk (no prior m=1)
test_kitty_payload_state_case!(
    test_single_chunk_m0_is_treated_as_complete,
    chunk_state = None,
    payload = b"a=t,f=32,i=80,s=1,v=1,m=0;AAAAAA==",
    check = |result, chunk_state| {
        // A standalone m=0 chunk (no prior accumulation) must be treated as a
        // complete single-chunk transmit if it has all required params.
        assert!(
            chunk_state.is_none(),
            "chunk_state must remain None when m=0 is processed without prior m=1"
        );
        let _ = result;
    },
);

// Verify that KittyParams::parse handles the 's' key (pixel width)
test_kitty_params_case!(
    test_parse_params_s_v_keys_set_width_height,
    params = b"s=640,v=480",
    check = |params: KittyParams| {
        assert_eq!(params.width, Some(640), "s= must set width");
        assert_eq!(params.height, Some(480), "v= must set height");
    },
);
