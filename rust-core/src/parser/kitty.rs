//! Kitty Graphics Protocol APC sequence parser
//!
//! Handles parsing of `ESC _ G key=value,key=value;Base64payload ESC \` sequences.
//! The APC payload bytes are extracted by the scanner in `TerminalCore::advance()`
//! and dispatched here for parsing and decoding.

use crate::parser::limits::MAX_CHUNK_DATA_BYTES;

#[path = "kitty_support.rs"]
mod support;
use support::{apply_kitty_param, build_command};

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
    pub fn parse(header: &[u8]) -> Self {
        let mut params = Self::default();
        for kv in header.split(|&b| b == b',') {
            apply_kitty_param(&mut params, kv);
        }
        params
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

    finalize_apc_payload(params, b64_data, chunk_state)
        .and_then(|(params, raw_data)| build_command(params, raw_data))
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
) -> Option<(KittyParams, Vec<u8>)> {
    if params.transmission.unwrap_or('d') != 'd' {
        *chunk_state = None;
        return None;
    }

    let decoded = decode_apc_payload_data(b64_data)?;

    if params.more {
        accumulate_apc_chunk(params, decoded, chunk_state)?;
        None
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
) -> (KittyParams, Vec<u8>) {
    if let Some(mut state) = chunk_state.take() {
        state.data.extend_from_slice(&decoded);
        (state.params, state.data)
    } else {
        (params, decoded)
    }
}

#[cfg(test)]
#[path = "tests/kitty.rs"]
mod tests;
