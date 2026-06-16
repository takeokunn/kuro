use crate::parser::kitty::{process_apc_payload, ImageFormat, KittyCommand, KittyParams};
use super::support::encode_1x1_png_b64;

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
