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

pub(super) fn encode_empty_png_with_dimensions_b64(width: u32, height: u32) -> String {
    let mut bytes = Vec::new();
    bytes.extend_from_slice(b"\x89PNG\r\n\x1a\n");

    let mut ihdr = Vec::with_capacity(13);
    ihdr.extend_from_slice(&width.to_be_bytes());
    ihdr.extend_from_slice(&height.to_be_bytes());
    ihdr.extend_from_slice(&[8, 6, 0, 0, 0]);

    append_png_chunk(&mut bytes, b"IHDR", &ihdr);
    append_png_chunk(&mut bytes, b"IDAT", &[]);
    append_png_chunk(&mut bytes, b"IEND", &[]);
    crate::util::base64::encode(&bytes)
}

fn append_png_chunk(bytes: &mut Vec<u8>, name: &[u8; 4], data: &[u8]) {
    let data_len = u32::try_from(data.len()).expect("PNG test chunk length must fit u32");
    bytes.extend_from_slice(&data_len.to_be_bytes());
    bytes.extend_from_slice(name);
    bytes.extend_from_slice(data);

    let crc = png_crc32(name.iter().copied().chain(data.iter().copied()));
    bytes.extend_from_slice(&crc.to_be_bytes());
}

fn png_crc32(bytes: impl Iterator<Item = u8>) -> u32 {
    let mut crc = 0xffff_ffffu32;
    for byte in bytes {
        crc ^= u32::from(byte);
        for _ in 0..8 {
            let mask = 0u32.wrapping_sub(crc & 1);
            crc = (crc >> 1) ^ (0xedb8_8320 & mask);
        }
    }
    !crc
}
