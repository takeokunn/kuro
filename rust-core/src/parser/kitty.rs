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
            if kv.len() < 3 || kv[1] != b'=' {
                continue;
            }
            let key = kv[0] as char;
            let val = &kv[2..];
            match key {
                'a' => params.action = val.first().map(|&b| b as char),
                'f' => params.format = parse_u32(val),
                't' => params.transmission = val.first().map(|&b| b as char),
                's' => params.width = parse_u32(val),
                'v' => params.height = parse_u32(val),
                'i' => params.image_id = parse_u32(val),
                'p' => params.placement_id = parse_u32(val),
                'm' => params.more = val.first().copied() == Some(b'1'),
                'q' => params.quiet = parse_u32(val).unwrap_or(0) as u8,
                'c' => params.columns = parse_u32(val),
                'r' => params.rows = parse_u32(val),
                'X' => params.x_offset = parse_u32(val).unwrap_or(0),
                'Y' => params.y_offset = parse_u32(val).unwrap_or(0),
                'd' => params.delete_sub = val.first().map(|&b| b as char),
                _ => {} // unknown key — silently ignore
            }
        }
        params
    }
}

#[inline]
fn parse_u32(bytes: &[u8]) -> Option<u32> {
    std::str::from_utf8(bytes).ok()?.parse().ok()
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
    // Split at ';' to separate key=value header from base64 payload
    let (header, b64_data) = payload.iter().position(|&b| b == b';').map_or_else(
        || (payload, &[][..]),
        |pos| (&payload[..pos], &payload[pos + 1..]),
    );

    let params = KittyParams::parse(header);

    // Only 'd' (direct/inline) transmission is supported
    let transmission = params.transmission.unwrap_or('d');
    if transmission != 'd' {
        // File/shared-memory transfer not supported — silently ignore
        *chunk_state = None;
        return None;
    }

    // Base64 decode the payload
    let decoded = if b64_data.is_empty() {
        Vec::new()
    } else if let Ok(d) = crate::util::base64::decode(b64_data) {
        d
    } else {
        // Malformed base64 — discard entire sequence including any chunk state
        *chunk_state = None;
        return None;
    };

    if params.more {
        // m=1: accumulate this chunk and wait for more
        match chunk_state.as_mut() {
            None => {
                // First chunk: initialize state with these params
                if decoded.len() <= MAX_CHUNK_DATA_BYTES {
                    *chunk_state = Some(KittyChunkState {
                        params,
                        data: decoded,
                    });
                }
            }
            Some(state) => {
                // Subsequent chunk: append decoded data (check size limit)
                if state.data.len() + decoded.len() <= MAX_CHUNK_DATA_BYTES {
                    state.data.extend_from_slice(&decoded);
                } else {
                    // Accumulated data exceeds limit — discard entire sequence
                    *chunk_state = None;
                    return None;
                }
            }
        }
        return None; // Not complete yet
    }

    // m=0 or absent: this is the final (or only) chunk
    let (final_params, final_data) = if let Some(mut state) = chunk_state.take() {
        // Combine accumulated data with this final chunk
        state.data.extend_from_slice(&decoded);
        (state.params, state.data)
    } else {
        // Single-chunk sequence
        (params, decoded)
    };

    build_command(final_params, final_data)
}

/// Decode raw payload bytes according to the Kitty format code.
///
/// Returns `(pixels, format, pixel_width, pixel_height)` or `None` on error.
/// For raw formats (24/32), zero dimensions are treated as malformed.
#[inline]
fn decode_pixel_data(
    raw_data: Vec<u8>,
    params: &KittyParams,
) -> Option<(Vec<u8>, ImageFormat, u32, u32)> {
    let format_code = params.format.unwrap_or(FORMAT_RGBA);
    let (pixels, format) = match format_code {
        FORMAT_RGB => (raw_data, ImageFormat::Rgb),
        FORMAT_RGBA => (raw_data, ImageFormat::Rgba),
        FORMAT_PNG => match decode_png(&raw_data) {
            Ok((p, fmt)) => (p, fmt),
            Err(_) => return None, // corrupt PNG — silently discard
        },
        _ => return None, // unknown format — silently discard
    };

    let pixel_width = params.width.unwrap_or(0);
    let pixel_height = params.height.unwrap_or(0);
    // For raw pixel formats, zero dimensions indicate a malformed command
    if format_code != FORMAT_PNG && (pixel_width == 0 || pixel_height == 0) {
        return None;
    }

    Some((pixels, format, pixel_width, pixel_height))
}

/// Build a `KittyCommand` from finalized params and decoded (non-base64) payload.
fn build_command(params: KittyParams, raw_data: Vec<u8>) -> Option<KittyCommand> {
    let action = params.action.unwrap_or('T');

    match action {
        't' | 'T' => {
            let (pixels, format, pixel_width, pixel_height) = decode_pixel_data(raw_data, &params)?;

            if action == 't' {
                Some(KittyCommand::Transmit {
                    image_id: params.image_id,
                    pixels,
                    format,
                    pixel_width,
                    pixel_height,
                    placement_id: params.placement_id,
                })
            } else {
                Some(KittyCommand::TransmitAndDisplay {
                    image_id: params.image_id,
                    pixels,
                    format,
                    pixel_width,
                    pixel_height,
                    columns: params.columns,
                    rows: params.rows,
                    placement_id: params.placement_id,
                })
            }
        }
        'p' => {
            let image_id = params.image_id?;
            Some(KittyCommand::Place {
                image_id,
                placement_id: params.placement_id,
                columns: params.columns,
                rows: params.rows,
            })
        }
        'd' => {
            let delete_sub = params.delete_sub.unwrap_or('a');
            Some(KittyCommand::Delete {
                delete_sub,
                image_id: params.image_id,
                placement_id: params.placement_id,
            })
        }
        'q' => Some(KittyCommand::Query {
            image_id: params.image_id,
        }),
        'f' => {
            // Animation frames: not supported in Phase 15
            #[cfg(debug_assertions)]
            eprintln!("[kuro] kitty animation frames not supported (a=f)");
            None
        }
        _ => None, // unknown action — silently discard
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
