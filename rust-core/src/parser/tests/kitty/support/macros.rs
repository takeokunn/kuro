/// Assert that `process_apc_payload` rejects a payload with `None` and that
/// `chunk_state` is cleared (e.g. a `t=t`/`t=s` media transfer with no path).
macro_rules! test_unsupported_transmission {
    ($name:ident, payload = $payload:expr, label = $label:expr $(,)?) => {
        #[test]
        fn $name() {
            let mut chunk_state = None;
            let result = $crate::parser::kitty::process_apc_payload($payload, &mut chunk_state);
            assert!(
                result.is_none(),
                concat!($label, " transmission must return None")
            );
            assert!(
                chunk_state.is_none(),
                "chunk_state must be cleared when transmission is rejected"
            );
        }
    };
}

/// Assert that a raw-pixel transmit of an N×N image carries the expected
/// format, dimensions, and pixel-buffer size.
macro_rules! test_transmit_nxn_image {
    (
        $name:ident,
        fmt_key  = $fmt_key:expr,
        image_id = $image_id:expr,
        n        = $n:expr,
        nbytes   = $nbytes:expr,
        fmt_var  = $fmt_var:ident
        $(,)?
    ) => {
        #[test]
        fn $name() {
            let b64 = crate::util::base64::encode(&[0u8; $nbytes]);
            let mut chunk_state = None;
            let payload = format!(
                "a=t,f={},i={},s={},v={};{}",
                $fmt_key, $image_id, $n, $n, b64
            );
            let result =
                $crate::parser::kitty::process_apc_payload(payload.as_bytes(), &mut chunk_state);
            match result.unwrap() {
                KittyCommand::Transmit {
                    format,
                    pixel_width,
                    pixel_height,
                    pixels,
                    ..
                } => {
                    assert_eq!(format, $crate::parser::kitty::ImageFormat::$fmt_var);
                    assert_eq!(pixel_width, $n);
                    assert_eq!(pixel_height, $n);
                    assert_eq!(
                        pixels.len(),
                        $nbytes,
                        concat!(
                            stringify!($n),
                            "×",
                            stringify!($n),
                            " ",
                            stringify!($fmt_var),
                            " byte count"
                        )
                    );
                }
                other => panic!("expected Transmit, got {other:?}"),
            }
        }
    };
}

/// Assert that a 1×1 PNG with a known pixel value round-trips through
/// `process_apc_payload` and produces the expected pixel bytes.
macro_rules! test_png_pixel_round_trip {
    (
        $name:ident,
        color_type = $color_type:expr,
        pixel      = $pixel:expr,
        image_id   = $image_id:expr,
        fmt_var    = $fmt_var:ident,
        expected   = $expected:expr,
        msg        = $msg:expr
        $(,)?
    ) => {
        #[test]
        fn $name() {
            let b64 = encode_1x1_png_b64($color_type, $pixel);
            let mut chunk_state = None;
            let payload = format!("a=t,f=100,i={},s=1,v=1;{}", $image_id, b64);
            let result =
                $crate::parser::kitty::process_apc_payload(payload.as_bytes(), &mut chunk_state);
            match result.unwrap() {
                KittyCommand::Transmit { pixels, format, .. } => {
                    assert_eq!(format, $crate::parser::kitty::ImageFormat::$fmt_var);
                    assert_eq!(pixels, $expected, $msg);
                }
                other => panic!("expected Transmit, got {other:?}"),
            }
        }
    };
}

/// Assert that `process_apc_payload` returns an already-unwrapped `KittyCommand`
/// variant with the expected shape.
macro_rules! assert_kitty_variant {
    ($result:expr, $variant:pat => $body:block, expected = $expected:literal $(,)?) => {
        match $result.unwrap() {
            $variant => $body,
            other => panic!("expected {}, got {other:?}", $expected),
        }
    };
}

/// Assert that `process_apc_payload` returns a 1×1 PNG transmit with the
/// expected format, dimensions, and pixel-buffer length.
macro_rules! assert_kitty_some_png_transmit {
    (
        $result:expr,
        fmt_var = $fmt_var:ident,
        expected_len = $expected_len:expr
        , pixels = $pixels:ident
        => $body:block,
        expected = $expected:literal
        $(,)?
    ) => {
        match $result {
            Some(KittyCommand::Transmit {
                format,
                pixel_width,
                pixel_height,
                pixels: $pixels,
                ..
            }) => {
                assert_eq!(format, $crate::parser::kitty::ImageFormat::$fmt_var);
                assert_eq!(pixel_width, 1, "pixel_width must match s=1");
                assert_eq!(pixel_height, 1, "pixel_height must match v=1");
                assert_eq!($pixels.len(), $expected_len, "unexpected pixel buffer size");
                $body
            }
            other => panic!("expected {}, got {other:?}", $expected),
        }
    };
}

macro_rules! test_kitty_png_transmit_case {
    (
        $name:ident,
        payload = $payload:expr,
        fmt_var = $fmt_var:ident,
        expected_len = $expected_len:expr,
        pixels = $pixels:ident => $body:block,
        expected = $expected:literal
        $(,)?
    ) => {
        #[test]
        fn $name() {
            let payload = $payload;
            let result = $crate::parser::kitty::tests::support::process_apc_payload_once(payload.as_ref());
            assert_kitty_some_png_transmit!(
                result,
                fmt_var = $fmt_var,
                expected_len = $expected_len,
                pixels = $pixels => $body,
                expected = $expected
            );
        }
    };
}

macro_rules! test_kitty_payload_once_case {
    (
        $name:ident,
        payload = $payload:expr,
        check = $check:expr
        $(,)?
    ) => {
        #[test]
        fn $name() {
            let payload = $payload;
            let result =
                $crate::parser::kitty::tests::support::process_apc_payload_once(payload.as_ref());
            ($check)(result);
        }
    };
}

macro_rules! test_kitty_payload_state_case {
    (
        $name:ident,
        chunk_state = $chunk_state:expr,
        payload = $payload:expr,
        check = $check:expr
        $(,)?
    ) => {
        #[test]
        fn $name() {
            let payload = $payload;
            let mut chunk_state = $chunk_state;
            let result =
                $crate::parser::kitty::process_apc_payload(payload.as_ref(), &mut chunk_state);
            let check: fn(
                Option<$crate::parser::kitty::KittyCommand>,
                Option<$crate::parser::kitty::KittyChunkState>,
            ) = $check;
            check(result, chunk_state);
        }
    };
}

macro_rules! test_kitty_params_case {
    (
        $name:ident,
        params = $params:expr,
        check = $check:expr
        $(,)?
    ) => {
        #[test]
        fn $name() {
            let params = $params;
            let result = $crate::parser::kitty::KittyParams::parse(params.as_ref());
            ($check)(result);
        }
    };
}

/// Assert that `process_apc_payload` returns a `KittyCommand::Transmit` with the
/// expected image_id, format, and pixel dimensions.
macro_rules! assert_transmit {
    ($result:expr, image_id => $image_id:expr, format => $format:expr, pw => $pw:expr, ph => $ph:expr $(,)?) => {
        assert_kitty_variant!(
            $result,
            KittyCommand::Transmit {
                image_id,
                format,
                pixel_width,
                pixel_height,
                ..
            } => {
                assert_eq!(image_id, $image_id);
                assert_eq!(format, $format);
                assert_eq!(pixel_width, $pw);
                assert_eq!(pixel_height, $ph);
            },
            expected = "Transmit"
        );
    };
}

/// Assert that `process_apc_payload` returns a `KittyCommand::Transmit` with the
/// expected placement_id.
macro_rules! assert_transmit_placement_id {
    ($result:expr, $placement_id:expr $(,)?) => {
        assert_kitty_variant!(
            $result,
            KittyCommand::Transmit { placement_id, .. } => {
                assert_eq!(placement_id, $placement_id);
            },
            expected = "Transmit"
        )
    };
}

/// Assert that `process_apc_payload` returns a `KittyCommand::TransmitAndDisplay`
/// with the expected placement_id.
macro_rules! assert_transmit_and_display_placement_id {
    ($result:expr, $placement_id:expr $(,)?) => {
        assert_kitty_variant!(
            $result,
            KittyCommand::TransmitAndDisplay { placement_id, .. } => {
                assert_eq!(placement_id, $placement_id);
            },
            expected = "TransmitAndDisplay"
        )
    };
}

/// Assert that `process_apc_payload` returns a `KittyCommand::Place` with the
/// expected fields.
macro_rules! assert_place_fields {
    (
        $result:expr,
        image_id => $image_id:expr,
        placement_id => $placement_id:expr,
        columns => $columns:expr,
        rows => $rows:expr
        $(,)?
    ) => {
        assert_kitty_variant!(
            $result,
            KittyCommand::Place {
                image_id,
                placement_id,
                columns,
                rows,
            } => {
                assert_eq!(image_id, $image_id);
                assert_eq!(placement_id, $placement_id);
                assert_eq!(columns, $columns);
                assert_eq!(rows, $rows);
            },
            expected = "Place"
        )
    };
}

/// Assert that `process_apc_payload` returns a `KittyCommand::Delete` with the
/// expected delete sub-command.
macro_rules! assert_delete_sub {
    ($result:expr, $delete_sub:expr $(,)?) => {
        assert_kitty_variant!(
            $result,
            KittyCommand::Delete { delete_sub, .. } => {
                assert_eq!(delete_sub, $delete_sub);
            },
            expected = "Delete"
        );
    };
}

/// Assert that `process_apc_payload` returns a `KittyCommand::Delete` with the
/// expected delete sub-command and associated payload field.
macro_rules! assert_delete_sub_and {
    ($result:expr, $delete_sub:expr, $field:ident => $field_value:expr $(,)?) => {
        assert_kitty_variant!(
            $result,
            KittyCommand::Delete { delete_sub, $field, .. } => {
                assert_eq!(delete_sub, $delete_sub);
                assert_eq!($field, $field_value);
            },
            expected = "Delete"
        )
    };
}

/// Generate a table-driven test for one-shot delete sub-command cases.
macro_rules! test_delete_sub_command_variants {
    (
        $name:ident,
        $(
            payload = $payload:expr,
            expected = $delete_sub:expr,
            label = $label:expr
        ),+ $(,)?
    ) => {
        #[test]
        fn $name() {
            for (payload, label, delete_sub) in [
                $(
                    ($payload.as_slice(), $label, $delete_sub),
                )+
            ] {
                let result = $crate::parser::kitty::tests::support::process_apc_payload_once(payload);
                assert!(result.is_some(), "{label} payload must parse");
                assert_delete_sub!(result, delete_sub);
            }
        }
    };
}
