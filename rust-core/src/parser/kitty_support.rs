use super::{ImageFormat, KittyCommand, KittyParams};

/// Kitty Graphics Protocol format code for 24-bit RGB (3 bytes per pixel).
const FORMAT_RGB: u32 = 24;
/// Kitty Graphics Protocol format code for 32-bit RGBA (4 bytes per pixel).
const FORMAT_RGBA: u32 = 32;
/// Kitty Graphics Protocol format code for PNG (decoded on receipt).
const FORMAT_PNG: u32 = 100;

#[inline]
fn parse_u32(bytes: &[u8]) -> Option<u32> {
    std::str::from_utf8(bytes).ok()?.parse().ok()
}

#[inline]
fn first_char(bytes: &[u8]) -> Option<char> {
    bytes.first().copied().map(char::from)
}

#[inline]
fn split_kitty_param_pair(kv: &[u8]) -> Option<(char, &[u8])> {
    if kv.len() < 3 || kv[1] != b'=' {
        return None;
    }
    Some((kv[0] as char, &kv[2..]))
}

#[inline]
fn set_kitty_char_param(slot: &mut Option<char>, val: &[u8]) {
    *slot = first_char(val);
}

#[inline]
fn set_kitty_u32_param(slot: &mut Option<u32>, val: &[u8]) {
    *slot = parse_u32(val);
}

#[inline]
fn set_kitty_u8_param(slot: &mut u8, val: &[u8]) {
    *slot = parse_u32(val).unwrap_or(0) as u8;
}

#[inline]
fn set_kitty_bool_param(slot: &mut bool, val: &[u8]) {
    *slot = val.first().copied() == Some(b'1');
}

#[inline]
fn set_kitty_u32_or_zero_param(slot: &mut u32, val: &[u8]) {
    *slot = parse_u32(val).unwrap_or(0);
}

#[inline]
fn apply_kitty_char_param(params: &mut KittyParams, key: char, val: &[u8]) -> bool {
    match key {
        'a' => {
            set_kitty_char_param(&mut params.action, val);
            true
        }
        't' => {
            set_kitty_char_param(&mut params.transmission, val);
            true
        }
        'd' => {
            set_kitty_char_param(&mut params.delete_sub, val);
            true
        }
        _ => false,
    }
}

#[inline]
fn apply_kitty_u32_param(params: &mut KittyParams, key: char, val: &[u8]) -> bool {
    match key {
        'f' => {
            set_kitty_u32_param(&mut params.format, val);
            true
        }
        's' => {
            set_kitty_u32_param(&mut params.width, val);
            true
        }
        'v' => {
            set_kitty_u32_param(&mut params.height, val);
            true
        }
        'i' => {
            set_kitty_u32_param(&mut params.image_id, val);
            true
        }
        'p' => {
            set_kitty_u32_param(&mut params.placement_id, val);
            true
        }
        'c' => {
            set_kitty_u32_param(&mut params.columns, val);
            true
        }
        'r' => {
            set_kitty_u32_param(&mut params.rows, val);
            true
        }
        _ => false,
    }
}

#[inline]
fn apply_kitty_control_param(params: &mut KittyParams, key: char, val: &[u8]) -> bool {
    match key {
        'm' => {
            set_kitty_bool_param(&mut params.more, val);
            true
        }
        'q' => {
            set_kitty_u8_param(&mut params.quiet, val);
            true
        }
        'X' => {
            set_kitty_u32_or_zero_param(&mut params.x_offset, val);
            true
        }
        'Y' => {
            set_kitty_u32_or_zero_param(&mut params.y_offset, val);
            true
        }
        _ => false,
    }
}

#[inline]
pub(super) fn apply_kitty_param(params: &mut KittyParams, kv: &[u8]) {
    let Some((key, val)) = split_kitty_param_pair(kv) else {
        return;
    };

    if apply_kitty_char_param(params, key, val)
        || apply_kitty_u32_param(params, key, val)
        || apply_kitty_control_param(params, key, val)
    {
        return;
    }
}

#[inline]
fn resolve_kitty_image_payload(
    raw_data: Vec<u8>,
    format_code: u32,
) -> Option<(Vec<u8>, ImageFormat)> {
    match format_code {
        FORMAT_RGB => Some((raw_data, ImageFormat::Rgb)),
        FORMAT_RGBA => Some((raw_data, ImageFormat::Rgba)),
        FORMAT_PNG => decode_png(&raw_data).ok(),
        _ => None,
    }
}

#[inline]
fn require_kitty_image_dimensions(params: &KittyParams, format_code: u32) -> Option<(u32, u32)> {
    let pixel_width = params.width.unwrap_or(0);
    let pixel_height = params.height.unwrap_or(0);
    if format_code != FORMAT_PNG && (pixel_width == 0 || pixel_height == 0) {
        return None;
    }
    Some((pixel_width, pixel_height))
}

#[inline]
fn decode_pixel_data(raw_data: Vec<u8>, params: &KittyParams) -> Option<KittyImagePayload> {
    let format_code = params.format.unwrap_or(FORMAT_RGBA);
    let (pixels, format) = resolve_kitty_image_payload(raw_data, format_code)?;
    let (pixel_width, pixel_height) = require_kitty_image_dimensions(params, format_code)?;

    Some(KittyImagePayload {
        pixels,
        format,
        pixel_width,
        pixel_height,
    })
}

#[derive(Debug, Clone)]
struct KittyImagePayload {
    pixels: Vec<u8>,
    format: ImageFormat,
    pixel_width: u32,
    pixel_height: u32,
}

fn build_kitty_transmit_command(
    params: KittyParams,
    payload: KittyImagePayload,
    display: bool,
) -> KittyCommand {
    if display {
        KittyCommand::TransmitAndDisplay {
            image_id: params.image_id,
            pixels: payload.pixels,
            format: payload.format,
            pixel_width: payload.pixel_width,
            pixel_height: payload.pixel_height,
            columns: params.columns,
            rows: params.rows,
            placement_id: params.placement_id,
        }
    } else {
        KittyCommand::Transmit {
            image_id: params.image_id,
            pixels: payload.pixels,
            format: payload.format,
            pixel_width: payload.pixel_width,
            pixel_height: payload.pixel_height,
            placement_id: params.placement_id,
        }
    }
}

fn build_kitty_place_command(params: KittyParams) -> Option<KittyCommand> {
    let image_id = params.image_id?;
    Some(KittyCommand::Place {
        image_id,
        placement_id: params.placement_id,
        columns: params.columns,
        rows: params.rows,
    })
}

fn build_kitty_delete_command(params: KittyParams) -> KittyCommand {
    KittyCommand::Delete {
        delete_sub: params.delete_sub.unwrap_or('a'),
        image_id: params.image_id,
        placement_id: params.placement_id,
    }
}

fn build_kitty_query_command(params: KittyParams) -> KittyCommand {
    KittyCommand::Query {
        image_id: params.image_id,
    }
}

/// Build a `KittyCommand` from finalized params and decoded (non-base64) payload.
pub(super) fn build_command(params: KittyParams, raw_data: Vec<u8>) -> Option<KittyCommand> {
    let action = params.action.unwrap_or('T');

    match action {
        't' | 'T' => {
            let payload = decode_pixel_data(raw_data, &params)?;
            Some(build_kitty_transmit_command(params, payload, action == 'T'))
        }
        'p' => build_kitty_place_command(params),
        'd' => Some(build_kitty_delete_command(params)),
        'q' => Some(build_kitty_query_command(params)),
        'f' => {
            // Animation frames: not supported in Phase 15
            #[cfg(debug_assertions)]
            eprintln!("[kuro] kitty animation frames not supported (a=f)");
            None
        }
        _ => None,
    }
}

/// Decode PNG bytes to raw pixel data (RGB or RGBA).
///
/// PNG format 100 is always decoded to Rgb or Rgba on storage.
/// The `ImageFormat::Png` variant does not exist in the stored enum.
fn decode_png(data: &[u8]) -> Result<(Vec<u8>, ImageFormat), &'static str> {
    let decoder = png::Decoder::new(std::io::Cursor::new(data));
    let mut reader = decoder.read_info().map_err(|_| "png decode error")?;
    let mut buf = vec![0u8; reader.output_buffer_size()];
    let info = reader.next_frame(&mut buf).map_err(|_| "png frame error")?;
    buf.truncate(info.buffer_size());

    let (pixels, format) = match info.color_type {
        png::ColorType::Rgb => (buf, ImageFormat::Rgb),
        png::ColorType::Rgba => (buf, ImageFormat::Rgba),
        png::ColorType::Grayscale => {
            // Expand to RGB
            let rgb = buf.iter().flat_map(|&v| [v, v, v]).collect();
            (rgb, ImageFormat::Rgb)
        }
        png::ColorType::GrayscaleAlpha => {
            // Expand to RGBA
            let rgba = buf
                .chunks(2)
                .flat_map(|ch| [ch[0], ch[0], ch[0], ch[1]])
                .collect();
            (rgba, ImageFormat::Rgba)
        }
        png::ColorType::Indexed => {
            // Indexed and other types: unsupported, treat as opaque
            (buf, ImageFormat::Rgba)
        }
    };

    Ok((pixels, format))
}
