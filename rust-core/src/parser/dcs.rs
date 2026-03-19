//! DCS (Device Control String) sequence dispatcher.

use crate::TerminalCore;

const CELL_PIXEL_WIDTH: u32 = 8;
const CELL_PIXEL_HEIGHT: u32 = 16;

/// DCS state for accumulating sequences.
#[derive(Default)]
pub enum DcsState {
    /// No active DCS sequence.
    #[default]
    Idle,
    /// DCS + q (XTGETTCAP): accumulating hex-encoded capability name.
    Xtgettcap {
        /// Raw hex payload bytes from the XTGETTCAP request body.
        buf: Vec<u8>,
    },
    /// DCS P1;P2;P3 q (Sixel): in-progress sixel decoder.
    Sixel(crate::parser::sixel::SixelDecoder),
}


/// Called when DCS final byte is received (hook).
pub fn dcs_hook(
    core: &mut TerminalCore,
    params: &vte::Params,
    intermediates: &[u8],
    _ignore: bool,
    c: char,
) {
    match (intermediates, c) {
        (b"+", 'q') => {
            // XTGETTCAP: DCS + q <hex-name> ST
            core.meta.dcs_state = DcsState::Xtgettcap { buf: Vec::new() };
        }
        (b"", 'q') => {
            // Sixel: DCS P1;P2;P3 q <data> ST
            let p2 = params
                .iter()
                .nth(1)
                .and_then(|p| p.first().copied())
                .unwrap_or(0);
            core.meta.dcs_state = DcsState::Sixel(crate::parser::sixel::SixelDecoder::new(p2));
        }
        _ => {
            core.meta.dcs_state = DcsState::Idle;
        }
    }
}

/// Called for each data byte of the DCS sequence.
pub fn dcs_put(core: &mut TerminalCore, byte: u8) {
    match &mut core.meta.dcs_state {
        DcsState::Xtgettcap { buf } => {
            buf.push(byte);
        }
        DcsState::Sixel(decoder) => {
            decoder.put(byte);
        }
        DcsState::Idle => {}
    }
}

/// Called when DCS sequence ends (ST).
pub fn dcs_unhook(core: &mut TerminalCore) {
    let state = std::mem::replace(&mut core.meta.dcs_state, DcsState::Idle);
    match state {
        DcsState::Xtgettcap { buf } => handle_xtgettcap(core, &buf),
        DcsState::Sixel(decoder) => handle_sixel_complete(core, decoder),
        DcsState::Idle => {}
    }
}

/// Handle XTGETTCAP response.
fn handle_xtgettcap(core: &mut TerminalCore, buf: &[u8]) {
    // buf contains hex-encoded capability name(s), semicolon separated.
    // Example: "544e" = "TN" (terminal name).
    // Response format: DCS 1 + r <hex-name>=<hex-value> ST
    //                  DCS 0 + r <hex-name> ST (unknown)
    let s = match std::str::from_utf8(buf) {
        Ok(s) => s,
        Err(_) => return,
    };

    for cap_hex in s.split(';') {
        let cap_hex = cap_hex.trim();
        if cap_hex.is_empty() {
            continue;
        }

        let cap_name = match hex_decode(cap_hex) {
            Some(name) => name,
            None => continue,
        };

        let response = match cap_name.as_str() {
            "TN" | "name" => {
                let name_hex = hex_encode(&b"kuro"[..]);
                format!("\x1bP1+r{}={}\x1b\\", cap_hex, name_hex)
            }
            "RGB" => {
                let val_hex = hex_encode(&b"8:8:8"[..]);
                format!("\x1bP1+r{}={}\x1b\\", cap_hex, val_hex)
            }
            "Tc" => {
                // True color flag (empty value = supported)
                format!("\x1bP1+r{}=\x1b\\", cap_hex)
            }
            "Ms" => {
                // Clipboard set/get format for tmux/screen compatibility
                let val: &[u8] = &b"\x1b]52;%p1%s;%p2%s\x07"[..];
                let val_hex = hex_encode(val);
                format!("\x1bP1+r{}={}\x1b\\", cap_hex, val_hex)
            }
            "colors" | "Co" => {
                let val_hex = hex_encode(&b"256"[..]);
                format!("\x1bP1+r{}={}\x1b\\", cap_hex, val_hex)
            }
            _ => {
                // Unknown capability
                format!("\x1bP0+r{}\x1b\\", cap_hex)
            }
        };

        core.meta.pending_responses.push(response.into_bytes());
    }
}

fn hex_decode(hex: &str) -> Option<String> {
    if !hex.len().is_multiple_of(2) {
        return None;
    }

    let bytes: Option<Vec<u8>> = (0..hex.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).ok())
        .collect();

    bytes.and_then(|b| String::from_utf8(b).ok())
}

fn hex_encode(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        use std::fmt::Write as _;
        let _ = write!(&mut out, "{byte:02x}");
    }
    out
}

#[cfg(test)]
#[path = "tests/dcs.rs"]
mod tests;

/// Finalize a completed sixel sequence and add as image placement.
fn handle_sixel_complete(core: &mut TerminalCore, decoder: crate::parser::sixel::SixelDecoder) {
    use crate::grid::screen::{ImageData, ImagePlacement};
    use crate::parser::kitty::ImageFormat;

    if let Some((pixels, width, height)) = decoder.finish() {
        if width == 0 || height == 0 {
            return;
        }

        let data = ImageData {
            pixels,
            format: ImageFormat::Rgba,
            pixel_width: width,
            pixel_height: height,
        };

        let actual_id = core.screen.active_graphics_mut().store_image(None, data);
        let cursor = *core.screen.cursor();

        // Estimate cell geometry with a conventional 8x16 terminal cell.
        let cell_w = width.div_ceil(CELL_PIXEL_WIDTH);
        let cell_h = height.div_ceil(CELL_PIXEL_HEIGHT);

        let placement = ImagePlacement {
            image_id: actual_id,
            row: cursor.row,
            col: cursor.col,
            display_cols: cell_w.max(1),
            display_rows: cell_h.max(1),
        };

        if let Some(notif) = core.screen.active_graphics_mut().add_placement(placement) {
            core.kitty.pending_image_notifications.push(notif);
        }

        // Advance cursor after the rendered image region.
        let max_row = (core.screen.rows() as usize).saturating_sub(1);
        let new_row = cursor.row.saturating_add(cell_h as usize).min(max_row);
        core.screen.move_cursor(new_row, 0);
    }
}
