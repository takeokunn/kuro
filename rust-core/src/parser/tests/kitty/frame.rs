//! Tests for Kitty animation: frame transmission (a=f) and control (a=a).
//!
//! Module under test: `parser/kitty.rs` + `parser/kitty_support.rs`

use crate::parser::kitty::{ImageFormat, KittyCommand, KittyParams};

// ── a=f frame parsing ──────────────────────────────────────────────────────────

test_kitty_payload_once_case!(
    test_frame_basic_rgba_parsed,
    // 1x1 RGBA pixel; AAAAAA== = 4 zero bytes.
    payload = b"a=f,f=32,i=7,s=1,v=1;AAAAAA==",
    check = |result: Option<KittyCommand>| match result {
        Some(KittyCommand::Frame {
            image_id,
            format,
            width,
            height,
            ..
        }) => {
            assert_eq!(image_id, Some(7), "a=f must carry the target image id");
            assert_eq!(format, ImageFormat::Rgba);
            assert_eq!(width, 1);
            assert_eq!(height, 1);
        }
        other => panic!("expected Frame, got {other:?}"),
    },
);

test_kitty_payload_once_case!(
    test_frame_offset_and_canvas_keys_parsed,
    // x/y = region offset; c = background canvas frame; X=1 replace; z = gap.
    payload = b"a=f,f=32,i=2,s=1,v=1,x=3,y=4,c=1,X=1,z=120;AAAAAA==",
    check = |result: Option<KittyCommand>| match result {
        Some(KittyCommand::Frame {
            x,
            y,
            base_frame,
            replace,
            gap,
            edit_frame,
            ..
        }) => {
            assert_eq!(x, 3, "x= sets region top-left X");
            assert_eq!(y, 4, "y= sets region top-left Y");
            assert_eq!(base_frame, Some(1), "c= names the background canvas frame");
            assert!(replace, "X=1 selects replace mode");
            assert_eq!(gap, Some(120), "z= sets frame gap in ms");
            assert_eq!(edit_frame, None, "no r= means no edit target");
        }
        other => panic!("expected Frame, got {other:?}"),
    },
);

test_kitty_payload_once_case!(
    test_frame_edit_target_via_r_key,
    payload = b"a=f,f=32,i=2,s=1,v=1,r=2;AAAAAA==",
    check = |result: Option<KittyCommand>| match result {
        Some(KittyCommand::Frame { edit_frame, .. }) => {
            assert_eq!(edit_frame, Some(2), "r= names the edit-target frame");
        }
        other => panic!("expected Frame, got {other:?}"),
    },
);

test_kitty_payload_once_case!(
    test_frame_bg_color_via_y_color_key,
    payload = b"a=f,f=32,i=2,s=1,v=1,Y=4278190335;AAAAAA==",
    check = |result: Option<KittyCommand>| match result {
        Some(KittyCommand::Frame { bg_color, .. }) => {
            // 0xFF0000FF = opaque red.
            assert_eq!(bg_color, 0xFF00_00FF, "Y= sets the canvas bg color");
        }
        other => panic!("expected Frame, got {other:?}"),
    },
);

test_kitty_params_case!(
    test_frame_negative_gap_parsed,
    params = b"a=f,z=-1",
    check = |params: KittyParams| assert_eq!(params.gap, Some(-1), "negative gap parses"),
);

// ── a=a animation control parsing ───────────────────────────────────────────────

test_kitty_payload_once_case!(
    test_animation_control_run_state,
    payload = b"a=a,i=9,s=3,v=1,c=2",
    check = |result: Option<KittyCommand>| match result {
        Some(KittyCommand::AnimationControl {
            image_id,
            state,
            loop_count,
            current_frame,
        }) => {
            assert_eq!(image_id, Some(9));
            assert_eq!(state, Some(3), "s=3 is the run/loop state");
            assert_eq!(loop_count, Some(1), "v=1 is the infinite loop marker");
            assert_eq!(current_frame, Some(2), "c=2 selects current frame");
        }
        other => panic!("expected AnimationControl, got {other:?}"),
    },
);

test_kitty_payload_once_case!(
    test_animation_control_stop_state,
    payload = b"a=a,i=1,s=1",
    check = |result: Option<KittyCommand>| match result {
        Some(KittyCommand::AnimationControl { state, .. }) => {
            assert_eq!(state, Some(1), "s=1 is the stop state");
        }
        other => panic!("expected AnimationControl, got {other:?}"),
    },
);

// ── Malformed handling ──────────────────────────────────────────────────────────

test_kitty_payload_once_case!(
    test_frame_unsupported_format_returns_none,
    payload = b"a=f,f=99,i=1,s=1,v=1;AAAAAA==",
    check = |result: Option<KittyCommand>| assert!(
        result.is_none(),
        "unknown format code for a=f must return None"
    ),
);
