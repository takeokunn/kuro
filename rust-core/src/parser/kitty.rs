//! Kitty Graphics Protocol APC sequence parser
//!
//! Handles parsing of `ESC _ G key=value,key=value;Base64payload ESC \` sequences.
//! The APC payload bytes are extracted by the scanner in `TerminalCore::advance()`
//! and dispatched here for parsing and decoding.

use crate::parser::limits::MAX_CHUNK_DATA_BYTES;

/// Kitty Graphics Protocol format code for 24-bit RGB (3 bytes per pixel).
const FORMAT_RGB: u32 = 24;
/// Kitty Graphics Protocol format code for 32-bit RGBA (4 bytes per pixel).
const FORMAT_RGBA: u32 = 32;
/// Kitty Graphics Protocol format code for PNG (decoded on receipt).
const FORMAT_PNG: u32 = 100;

/// Post-decode image format (stored in `GraphicsStore`)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ImageFormat {
    /// f=24: 3 bytes per pixel (R, G, B)
    Rgb,
    /// f=32: 4 bytes per pixel (R, G, B, A)
    Rgba,
}

/// Parsed parameters from the Kitty Graphics APC header
#[derive(Debug, Default, Clone, Copy)]
pub struct KittyParams {
    /// Action: t=transmit, T=transmit+display, p=place, d=delete, f=frame, q=query
    pub action: Option<char>,
    /// Format: 24=RGB, 32=RGBA, 100=PNG
    pub format: Option<u32>,
    /// Transmission type: d=direct (base64), f=file, t=temp, s=shared-mem
    pub transmission: Option<char>,
    /// Image pixel width
    pub width: Option<u32>,
    /// Image pixel height
    pub height: Option<u32>,
    /// Image ID (0 = auto-assign)
    pub image_id: Option<u32>,
    /// Placement ID
    pub placement_id: Option<u32>,
    /// More chunks follow (m=1) or this is final (m=0/absent)
    pub more: bool,
    /// Quiet mode (suppress responses): 1=suppress OK, 2=suppress all
    pub quiet: u8,
    /// Display width in cells
    pub columns: Option<u32>,
    /// Display height in cells
    pub rows: Option<u32>,
    /// Cell-internal X offset in pixels
    pub x_offset: u32,
    /// Cell-internal Y offset in pixels
    pub y_offset: u32,
    /// Delete sub-command (when action=d)
    pub delete_sub: Option<char>,
}

impl KittyParams {
    /// Parse comma-separated key=value pairs from the APC header bytes.
    ///
    /// Format: `a=t,f=100,i=1,m=0`
    #[must_use]
    #[expect(
        clippy::cast_possible_truncation,
        reason = "quiet is 0 or 2 per Kitty graphics protocol spec; u32→u8 is always safe for valid inputs"
    )]
    pub fn parse(header: &[u8]) -> Self {
        let mut params = Self::default();
        for kv in header.split(|&b| b == b',') {
            apply_kitty_param(&mut params, kv);
        }
        params
    }
}

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
fn apply_kitty_param(params: &mut KittyParams, kv: &[u8]) {
    let Some((key, val)) = split_kitty_param_pair(kv) else {
        return;
    };

    match key {
        'a' => set_kitty_char_param(&mut params.action, val),
        'f' => set_kitty_u32_param(&mut params.format, val),
        't' => set_kitty_char_param(&mut params.transmission, val),
        's' => set_kitty_u32_param(&mut params.width, val),
        'v' => set_kitty_u32_param(&mut params.height, val),
        'i' => set_kitty_u32_param(&mut params.image_id, val),
        'p' => set_kitty_u32_param(&mut params.placement_id, val),
        'm' => set_kitty_bool_param(&mut params.more, val),
        'q' => set_kitty_u8_param(&mut params.quiet, val),
        'c' => set_kitty_u32_param(&mut params.columns, val),
        'r' => set_kitty_u32_param(&mut params.rows, val),
        'X' => set_kitty_u32_or_zero_param(&mut params.x_offset, val),
        'Y' => set_kitty_u32_or_zero_param(&mut params.y_offset, val),
        'd' => set_kitty_char_param(&mut params.delete_sub, val),
        _ => {}
    }
}

/// A finalized, decoded Kitty Graphics command ready for dispatch to `GraphicsStore`
#[expect(
    missing_docs,
    reason = "KittyCommand variants are self-documenting from the Kitty Graphics Protocol spec; prose docs add no value here"
)]
#[derive(Debug)]
pub enum KittyCommand {
    /// Transmit image data and store (a=t)
    Transmit {
        image_id: Option<u32>,
        pixels: Vec<u8>,
        format: ImageFormat,
        pixel_width: u32,
        pixel_height: u32,
        placement_id: Option<u32>,
    },
    /// Transmit image data, store, and place at current cursor (a=T)
    TransmitAndDisplay {
        image_id: Option<u32>,
        pixels: Vec<u8>,
        format: ImageFormat,
        pixel_width: u32,
        pixel_height: u32,
        columns: Option<u32>,
        rows: Option<u32>,
        placement_id: Option<u32>,
    },
    /// Place a previously stored image at current cursor (a=p)
    Place {
        image_id: u32,
        placement_id: Option<u32>,
        columns: Option<u32>,
        rows: Option<u32>,
    },
    /// Delete image(s) or placement(s) (a=d)
    Delete {
        delete_sub: char,
        image_id: Option<u32>,
        placement_id: Option<u32>,
    },
    /// Query terminal graphics capability (a=q)
    Query { image_id: Option<u32> },
}

/// In-progress chunk accumulation state for multi-chunk transfers (m=1).
///
/// Stored in `TerminalCore` between consecutive APC sequences when `m=1`.
pub struct KittyChunkState {
    /// Parameters from the first chunk (contain image format, size, id)
    pub params: KittyParams,
    /// Accumulated base64-decoded data across all chunks so far
    pub data: Vec<u8>,
}

struct KittyPayload {
    params: KittyParams,
    data: Vec<u8>,
}

/// Process a complete APC payload (everything between `ESC _ G` and `ESC \`).
///
/// `chunk_state` is the persistent multi-chunk state from `TerminalCore`.
/// Returns a `KittyCommand` when the sequence is complete, or `None` if:
/// - More chunks are expected (m=1)
/// - The payload is malformed
/// - The transmission type is not 'd' (direct) — file/shared-mem not supported
pub fn process_apc_payload(
    payload: &[u8],
    chunk_state: &mut Option<KittyChunkState>,
) -> Option<KittyCommand> {
    let (header, b64_data) = split_apc_payload(payload);
    let params = KittyParams::parse(header);

    finalize_apc_payload(params, b64_data, chunk_state).and_then(|payload| {
        build_command(payload.params, payload.data)
    })
}

fn split_apc_payload(payload: &[u8]) -> (&[u8], &[u8]) {
    payload.iter().position(|&b| b == b';').map_or_else(
        || (payload, &[][..]),
        |pos| (&payload[..pos], &payload[pos + 1..]),
    )
}

fn finalize_apc_payload(
    params: KittyParams,
    b64_data: &[u8],
    chunk_state: &mut Option<KittyChunkState>,
) -> Option<KittyPayload> {
    if params.transmission.unwrap_or('d') != 'd' {
        *chunk_state = None;
        return None;
    }

    let decoded = decode_apc_payload_data(b64_data)?;

    if params.more {
        accumulate_apc_chunk(params, decoded, chunk_state)?;
        return None;
    } else {
        Some(finish_apc_payload(params, decoded, chunk_state))
    }
}

fn decode_apc_payload_data(b64_data: &[u8]) -> Option<Vec<u8>> {
    if b64_data.is_empty() {
        Some(Vec::new())
    } else {
        crate::util::base64::decode(b64_data).ok()
    }
}

fn accumulate_apc_chunk(
    params: KittyParams,
    decoded: Vec<u8>,
    chunk_state: &mut Option<KittyChunkState>,
) -> Option<()> {
    match chunk_state {
        None => start_apc_chunk(params, decoded, chunk_state),
        Some(_) => extend_apc_chunk(decoded, chunk_state),
    }
}

fn start_apc_chunk(
    params: KittyParams,
    decoded: Vec<u8>,
    chunk_state: &mut Option<KittyChunkState>,
) -> Option<()> {
    if decoded.len() > MAX_CHUNK_DATA_BYTES {
        *chunk_state = None;
        return None;
    }

    *chunk_state = Some(KittyChunkState {
        params,
        data: decoded,
    });
    Some(())
}

fn extend_apc_chunk(decoded: Vec<u8>, chunk_state: &mut Option<KittyChunkState>) -> Option<()> {
    let state = chunk_state.as_mut()?;

    if state.data.len() + decoded.len() > MAX_CHUNK_DATA_BYTES {
        *chunk_state = None;
        return None;
    }

    state.data.extend_from_slice(&decoded);
    Some(())
}

fn finish_apc_payload(
    params: KittyParams,
    decoded: Vec<u8>,
    chunk_state: &mut Option<KittyChunkState>,
) -> KittyPayload {
    if let Some(mut state) = chunk_state.take() {
        state.data.extend_from_slice(&decoded);
        KittyPayload {
            params: state.params,
            data: state.data,
        }
    } else {
        KittyPayload {
            params,
            data: decoded,
        }
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
fn build_command(params: KittyParams, raw_data: Vec<u8>) -> Option<KittyCommand> {
    let action = params.action.unwrap_or('T');

    match action {
        't' | 'T' => {
            let payload = decode_pixel_data(raw_data, &params)?;
            Some(build_kitty_transmit_command(
                params,
                payload,
                action == 'T',
            ))
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

#[cfg(test)]
#[path = "tests/kitty.rs"]
mod tests;
