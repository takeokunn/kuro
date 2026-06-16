/// Assert that `process_apc_payload` rejects an unsupported transmission type
/// (`t=t` or `t=s`) with `None`, and that `chunk_state` is cleared.
macro_rules! test_unsupported_transmission {
    ($name:ident, payload = $payload:expr, label = $label:expr $(,)?) => {
        #[test]
        fn $name() {
            let mut chunk_state = None;
            let result = process_apc_payload($payload, &mut chunk_state);
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
            let result = process_apc_payload(payload.as_bytes(), &mut chunk_state);
            match result.unwrap() {
                KittyCommand::Transmit {
                    format,
                    pixel_width,
                    pixel_height,
                    pixels,
                    ..
                } => {
                    assert_eq!(format, ImageFormat::$fmt_var);
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
            let result = process_apc_payload(payload.as_bytes(), &mut chunk_state);
            match result.unwrap() {
                KittyCommand::Transmit { pixels, format, .. } => {
                    assert_eq!(format, ImageFormat::$fmt_var);
                    assert_eq!(pixels, $expected, $msg);
                }
                other => panic!("expected Transmit, got {other:?}"),
            }
        }
    };
}

/// Assert that `process_apc_payload` returns a `KittyCommand::Transmit` with the
/// expected image_id, format, and pixel dimensions.
macro_rules! assert_transmit {
    ($result:expr, image_id => $image_id:expr, format => $format:expr, pw => $pw:expr, ph => $ph:expr $(,)?) => {
        match $result.unwrap() {
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
            }
            other => panic!("expected Transmit, got {other:?}"),
        }
    };
}

/// Assert that `process_apc_payload` returns a `KittyCommand::Delete` with the
/// expected delete sub-command.
macro_rules! assert_delete_sub {
    ($result:expr, $delete_sub:expr $(,)?) => {
        match $result.unwrap() {
            KittyCommand::Delete { delete_sub, .. } => {
                assert_eq!(delete_sub, $delete_sub);
            }
            other => panic!("expected Delete, got {other:?}"),
        }
    };
}

/// Encode `pixels` as a minimal 1x1 PNG using the `png` crate encoder,
/// then base64-encode the result so it can be embedded directly in an APC payload.
pub(super) fn encode_1x1_png_b64(color_type: png::ColorType, pixels: &[u8]) -> String {
    let mut buf: Vec<u8> = Vec::new();
    {
        let mut encoder = png::Encoder::new(&mut buf, 1, 1);
        encoder.set_color(color_type);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder.write_header().expect("PNG header write");
        writer.write_image_data(pixels).expect("PNG pixel write");
    }
    crate::util::base64::encode(&buf)
}
