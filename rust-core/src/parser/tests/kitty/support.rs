use crate::parser::kitty::{process_apc_payload, KittyCommand};

#[macro_use]
#[path = "support/macros.rs"]
mod macros;

pub(super) fn process_apc_payload_once(payload: &[u8]) -> Option<KittyCommand> {
    let mut chunk_state = None;
    process_apc_payload(payload, &mut chunk_state)
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
