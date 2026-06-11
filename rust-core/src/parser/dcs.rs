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
    /// DCS $ q (DECRQSS): accumulating the requested setting name.
    Decrqss {
        /// Raw payload naming the queried setting (e.g. `b" q"`, `b"r"`).
        buf: Vec<u8>,
    },
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
        (b"$", 'q') => {
            // DECRQSS: DCS $ q <setting> ST — request status string
            core.meta.dcs_state = DcsState::Decrqss { buf: Vec::new() };
        }
        (b"", 'q') => {
            // Sixel: DCS P1;P2;P3 q <data> ST
            let p2 = params
                .iter()
                .nth(1)
                .and_then(|p| p.first().copied())
                .unwrap_or(0);
            core.meta.dcs_state = DcsState::Sixel(
                crate::parser::sixel::SixelDecoder::new_with_palette(p2, &core.osc_data.palette),
            );
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
        DcsState::Decrqss { buf } => {
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
        DcsState::Decrqss { buf } => handle_decrqss(core, &buf),
        DcsState::Sixel(decoder) => handle_sixel_complete(core, decoder),
        DcsState::Idle => {}
    }
}

/// Handle DECRQSS — Request Status String (`DCS $ q <setting> ST`).
///
/// Answers a subset of settings with their current value as a *valid* response
/// `DCS 1 $ r <value><setting> ST`; unsupported settings get the *invalid*
/// response `DCS 0 $ r ST`.
///
/// Supported:
/// - `SP q` (DECSCUSR cursor style) → `DCS 1 $ r <Ps> SP q ST`. Neovim queries
///   this at startup to restore the cursor shape on exit.
/// - `r` (DECSTBM scroll region) → `DCS 1 $ r <top> ; <bottom> r ST`, reported
///   1-indexed and inclusive.
/// - `m` (SGR) → `DCS 1 $ r <params> m ST`, the current rendition serialized by
///   [`crate::parser::sgr::serialize_sgr`] (always begins with reset `0`).
///
/// Everything else is answered with the invalid-request response `DCS 0 $ r ST`.
fn handle_decrqss(core: &mut TerminalCore, buf: &[u8]) {
    let response = match buf {
        // DECSCUSR cursor style — the setting name is "SP q" (space, then q).
        b" q" => {
            let ps = i64::from(core.dec_modes.cursor_shape);
            format!("\x1bP1$r{ps} q\x1b\\")
        }
        // DECSTBM scroll region — report 1-indexed, inclusive margins.
        b"r" => {
            let region = core.screen.get_scroll_region();
            let (top, bottom) = (region.top + 1, region.bottom);
            format!("\x1bP1$r{top};{bottom}r\x1b\\")
        }
        // SGR — serialize the current rendition (always begins with reset "0").
        b"m" => {
            let sgr = crate::parser::sgr::serialize_sgr(&core.current_attrs);
            format!("\x1bP1$r{sgr}m\x1b\\")
        }
        // All other settings: invalid-request response.
        _ => "\x1bP0$r\x1b\\".to_string(),
    };
    core.meta.pending_responses.push(response.into_bytes());
}

/// Look up a single XTGETTCAP capability by its decoded name and build the
/// DCS response string.
///
/// Returns `DCS 1 + r <hex-name>=<hex-value> ST` for known capabilities and
/// `DCS 0 + r <hex-name> ST` for unknown ones.
///
/// `cap_hex` is the raw hex-encoded form of `cap_name` as received from the
/// client; it is echoed back verbatim so the caller can match the response to
/// the request without re-encoding.
#[inline]
fn build_xtgettcap_response(cap_name: &str, cap_hex: &str) -> String {
    match cap_name {
        "TN" | "name" => {
            let name_hex = hex_encode(&b"kuro"[..]);
            format!("\x1bP1+r{cap_hex}={name_hex}\x1b\\")
        }
        "RGB" => {
            let val_hex = hex_encode(&b"8:8:8"[..]);
            format!("\x1bP1+r{cap_hex}={val_hex}\x1b\\")
        }
        "Tc" => {
            // True color flag (empty value = supported)
            format!("\x1bP1+r{cap_hex}=\x1b\\")
        }
        "Ms" => {
            // Clipboard set/get format for tmux/screen compatibility
            let val: &[u8] = &b"\x1b]52;%p1%s;%p2%s\x07"[..];
            let val_hex = hex_encode(val);
            format!("\x1bP1+r{cap_hex}={val_hex}\x1b\\")
        }
        "colors" | "Co" => {
            let val_hex = hex_encode(&b"256"[..]);
            format!("\x1bP1+r{cap_hex}={val_hex}\x1b\\")
        }
        // Smulx — extended underline styles (4:N format, SGR 4:1..4:5)
        // neovim uses this to detect undercurl support
        "Smulx" => {
            let val_hex = hex_encode(b"\x1b[4:%p1%dm");
            format!("\x1bP1+r{cap_hex}={val_hex}\x1b\\")
        }
        // Smol — overline support (SGR 53)
        "Smol" => {
            let val_hex = hex_encode(b"\x1b[53m");
            format!("\x1bP1+r{cap_hex}={val_hex}\x1b\\")
        }
        // Ss / Se — set/reset cursor style (DECSCUSR)
        "Ss" => {
            let val_hex = hex_encode(b"\x1b[%p1%d q");
            format!("\x1bP1+r{cap_hex}={val_hex}\x1b\\")
        }
        "Se" => {
            let val_hex = hex_encode(b"\x1b[2 q");
            format!("\x1bP1+r{cap_hex}={val_hex}\x1b\\")
        }
        // Su — underline color (SGR 58)
        "Su" => {
            let val_hex = hex_encode(b"\x1b[58:%p1%dm");
            format!("\x1bP1+r{cap_hex}={val_hex}\x1b\\")
        }
        // ccc — can change colors (256-palette overrides via OSC 4)
        "ccc" => {
            format!("\x1bP1+r{cap_hex}=\x1b\\")
        }
        // U8 / u8 — terminal handles UTF-8 (neovim checks this)
        "U8" | "u8" => {
            let val_hex = hex_encode(b"1");
            format!("\x1bP1+r{cap_hex}={val_hex}\x1b\\")
        }
        // Cr — cursor reset sequence (restore cursor to default state)
        "Cr" => {
            let val_hex = hex_encode(b"\x1b[2 q");
            format!("\x1bP1+r{cap_hex}={val_hex}\x1b\\")
        }
        // bce — background color erase (we implement BCE per VT220 spec)
        "bce" => {
            format!("\x1bP1+r{cap_hex}=\x1b\\")
        }
        // sitm / ritm — italic mode set/reset (SGR 3 / SGR 23)
        "sitm" => {
            let val_hex = hex_encode(b"\x1b[3m");
            format!("\x1bP1+r{cap_hex}={val_hex}\x1b\\")
        }
        "ritm" => {
            let val_hex = hex_encode(b"\x1b[23m");
            format!("\x1bP1+r{cap_hex}={val_hex}\x1b\\")
        }
        // kt — key for the Tab key (HT, 0x09). neovim queries this.
        "kt" => {
            let val_hex = hex_encode(b"\x09");
            format!("\x1bP1+r{cap_hex}={val_hex}\x1b\\")
        }
        // Ts / Te — strikethrough set/reset (SGR 9 / SGR 29). neovim uses these.
        "Ts" => {
            let val_hex = hex_encode(b"\x1b[9m");
            format!("\x1bP1+r{cap_hex}={val_hex}\x1b\\")
        }
        "Te" => {
            let val_hex = hex_encode(b"\x1b[29m");
            format!("\x1bP1+r{cap_hex}={val_hex}\x1b\\")
        }
        // setrgbf / setrgbb — truecolor set foreground / background in terminfo
        // parameter format. vim, tmux, and other tools use these.
        "setrgbf" => {
            let val_hex = hex_encode(b"\x1b[38;2;%p1%d;%p2%d;%p3%dm");
            format!("\x1bP1+r{cap_hex}={val_hex}\x1b\\")
        }
        "setrgbb" => {
            let val_hex = hex_encode(b"\x1b[48;2;%p1%d;%p2%d;%p3%dm");
            format!("\x1bP1+r{cap_hex}={val_hex}\x1b\\")
        }
        // Sync — synchronized output (DEC mode 2026). Some tools check this.
        "Sync" => {
            let val_hex = hex_encode(b"\x1b[?2026h");
            format!("\x1bP1+r{cap_hex}={val_hex}\x1b\\")
        }
        // kbs — backspace key. Terminals should report this.
        "kbs" => {
            let val_hex = hex_encode(b"\x7f");
            format!("\x1bP1+r{cap_hex}={val_hex}\x1b\\")
        }
        // E3 — clear the scrollback buffer (CSI 3 J / ED 3). tmux queries this
        // to decide whether it can clear the host terminal's scrollback; we
        // implement ED 3 via `Screen::clear_scrollback`, so advertise it.
        "E3" => {
            let val_hex = hex_encode(b"\x1b[3J");
            format!("\x1bP1+r{cap_hex}={val_hex}\x1b\\")
        }
        // smxx / rmxx — strikethrough terminfo names (aliases for Ts/Te).
        "smxx" => {
            let val_hex = hex_encode(b"\x1b[9m");
            format!("\x1bP1+r{cap_hex}={val_hex}\x1b\\")
        }
        "rmxx" => {
            let val_hex = hex_encode(b"\x1b[29m");
            format!("\x1bP1+r{cap_hex}={val_hex}\x1b\\")
        }
        _ => {
            // Unknown capability
            format!("\x1bP0+r{cap_hex}\x1b\\")
        }
    }
}

/// Handle XTGETTCAP response.
fn handle_xtgettcap(core: &mut TerminalCore, buf: &[u8]) {
    // buf contains hex-encoded capability name(s), semicolon separated.
    // Example: "544e" = "TN" (terminal name).
    // Response format: DCS 1 + r <hex-name>=<hex-value> ST
    //                  DCS 0 + r <hex-name> ST (unknown)
    let Ok(s) = std::str::from_utf8(buf) else {
        return;
    };

    for cap_hex in s.split(';') {
        let cap_hex = cap_hex.trim();
        if cap_hex.is_empty() {
            continue;
        }
        let Some(cap_name) = hex_decode(cap_hex) else {
            continue;
        };
        let response = build_xtgettcap_response(&cap_name, cap_hex);
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
            placement_id: None,
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
