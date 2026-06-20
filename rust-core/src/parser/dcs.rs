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
    /// DCS 2 $ t (DECTABSR): tab stop report requested — no body data.
    Dectabsr,
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
        (b"$", 't') => {
            // DECTABSR: DCS 2 $ t ST — request tab stop report.
            // Only respond when the first parameter is 2 (tab stop request).
            let p0 = params.iter().next().and_then(|g| g.first()).copied().unwrap_or(0);
            if p0 == 2 {
                core.meta.dcs_state = DcsState::Dectabsr;
            }
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
        DcsState::Dectabsr | DcsState::Idle => {}
    }
}

/// Called when DCS sequence ends (ST).
pub fn dcs_unhook(core: &mut TerminalCore) {
    let state = std::mem::replace(&mut core.meta.dcs_state, DcsState::Idle);
    match state {
        DcsState::Xtgettcap { buf } => handle_xtgettcap(core, &buf),
        DcsState::Decrqss { buf } => handle_decrqss(core, &buf),
        DcsState::Sixel(decoder) => handle_sixel_complete(core, decoder),
        DcsState::Dectabsr => handle_dectabsr(core),
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
    let response = build_decrqss_response(core, buf);
    core.meta.pending_responses.push(response.into_bytes());
}

#[inline]
fn build_decrqss_response(core: &TerminalCore, buf: &[u8]) -> String {
    match buf {
        b" q" => build_decrqss_cursor_response(core),
        b"r" => build_decrqss_scroll_region_response(core),
        b"m" => build_decrqss_sgr_response(core),
        _ => build_decrqss_invalid_response(),
    }
}

#[inline]
fn build_decrqss_cursor_response(core: &TerminalCore) -> String {
    let ps = i64::from(core.dec_modes.cursor_shape);
    format!("\x1bP1$r{ps} q\x1b\\")
}

#[inline]
fn build_decrqss_scroll_region_response(core: &TerminalCore) -> String {
    let region = core.screen.get_scroll_region();
    let (top, bottom) = (region.top + 1, region.bottom);
    format!("\x1bP1$r{top};{bottom}r\x1b\\")
}

#[inline]
fn build_decrqss_sgr_response(core: &TerminalCore) -> String {
    let sgr = crate::parser::sgr::serialize_sgr(&core.current_attrs);
    format!("\x1bP1$r{sgr}m\x1b\\")
}

#[inline]
fn build_decrqss_invalid_response() -> String {
    "\x1bP0$r\x1b\\".to_string()
}

/// Handle DECTABSR — Transmit Tab Stop Report (`DCS 2 $ t ST`).
///
/// Responds with `DCS 2 ; 0 $ u Ps/Ps/.../Ps ST` where each Ps is a
/// 1-indexed column position of an active tab stop.  The trailing ST
/// uses the 7-bit form `ESC \`.
fn handle_dectabsr(core: &mut TerminalCore) {
    let stops = core.tab_stops.get_stops();
    let pt: String = stops
        .iter()
        .map(|&col| (col + 1).to_string()) // VT tab stops are 1-indexed
        .collect::<Vec<_>>()
        .join("/");
    let response = format!("\x1bP2;0$u{pt}\x1b\\");
    core.meta.pending_responses.push(response.into_bytes());
}

fn xtgettcap_hex_response(cap_hex: &str, value: &[u8]) -> String {
    let value_hex = hex_encode(value);
    format!("\x1bP1+r{cap_hex}={value_hex}\x1b\\")
}

fn xtgettcap_empty_response(cap_hex: &str) -> String {
    format!("\x1bP1+r{cap_hex}=\x1b\\")
}

fn xtgettcap_unknown_response(cap_hex: &str) -> String {
    format!("\x1bP0+r{cap_hex}\x1b\\")
}

fn xtgettcap_identity_response(cap_name: &str, cap_hex: &str) -> Option<String> {
    match cap_name {
        "TN" | "name" => Some(xtgettcap_hex_response(cap_hex, b"kuro")),
        "RGB" => Some(xtgettcap_hex_response(cap_hex, b"8:8:8")),
        "Tc" => Some(xtgettcap_empty_response(cap_hex)),
        "Ms" => Some(xtgettcap_hex_response(cap_hex, b"\x1b]52;%p1%s;%p2%s\x07")),
        "colors" | "Co" => Some(xtgettcap_hex_response(cap_hex, b"256")),
        "ccc" => Some(xtgettcap_empty_response(cap_hex)),
        "U8" | "u8" => Some(xtgettcap_hex_response(cap_hex, b"1")),
        _ => None,
    }
}

fn xtgettcap_style_response(cap_name: &str, cap_hex: &str) -> Option<String> {
    match cap_name {
        // Smulx — extended underline styles (4:N format, SGR 4:1..4:5)
        // neovim uses this to detect undercurl support.
        "Smulx" => Some(xtgettcap_hex_response(cap_hex, b"\x1b[4:%p1%dm")),
        // Smol — overline support (SGR 53).
        "Smol" => Some(xtgettcap_hex_response(cap_hex, b"\x1b[53m")),
        // Ss / Se — set/reset cursor style (DECSCUSR).
        "Ss" => Some(xtgettcap_hex_response(cap_hex, b"\x1b[%p1%d q")),
        "Se" => Some(xtgettcap_hex_response(cap_hex, b"\x1b[2 q")),
        // Su — underline color (SGR 58).
        "Su" => Some(xtgettcap_hex_response(cap_hex, b"\x1b[58:%p1%dm")),
        // sitm / ritm — italic mode set/reset (SGR 3 / SGR 23).
        "sitm" => Some(xtgettcap_hex_response(cap_hex, b"\x1b[3m")),
        "ritm" => Some(xtgettcap_hex_response(cap_hex, b"\x1b[23m")),
        // Ts / Te — strikethrough set/reset (SGR 9 / SGR 29).
        "Ts" => Some(xtgettcap_hex_response(cap_hex, b"\x1b[9m")),
        "Te" => Some(xtgettcap_hex_response(cap_hex, b"\x1b[29m")),
        // smxx / rmxx — strikethrough terminfo names (aliases for Ts/Te).
        "smxx" => Some(xtgettcap_hex_response(cap_hex, b"\x1b[9m")),
        "rmxx" => Some(xtgettcap_hex_response(cap_hex, b"\x1b[29m")),
        _ => None,
    }
}

fn xtgettcap_cursor_response(cap_name: &str, cap_hex: &str) -> Option<String> {
    match cap_name {
        // Cr — cursor reset sequence (restore cursor to default state).
        "Cr" => Some(xtgettcap_hex_response(cap_hex, b"\x1b[2 q")),
        // kt — key for the Tab key (HT, 0x09). neovim queries this.
        "kt" => Some(xtgettcap_hex_response(cap_hex, b"\x09")),
        // kbs — backspace key. Terminals should report this.
        "kbs" => Some(xtgettcap_hex_response(cap_hex, b"\x7f")),
        _ => None,
    }
}

fn xtgettcap_terminal_response(cap_name: &str, cap_hex: &str) -> Option<String> {
    match cap_name {
        // setrgbf / setrgbb — truecolor set foreground / background in terminfo
        // parameter format. vim, tmux, and other tools use these.
        "setrgbf" => Some(xtgettcap_hex_response(
            cap_hex,
            b"\x1b[38;2;%p1%d;%p2%d;%p3%dm",
        )),
        "setrgbb" => Some(xtgettcap_hex_response(
            cap_hex,
            b"\x1b[48;2;%p1%d;%p2%d;%p3%dm",
        )),
        // Sync — synchronized output (DEC mode 2026). Some tools check this.
        "Sync" => Some(xtgettcap_hex_response(cap_hex, b"\x1b[?2026h")),
        // E3 — clear the scrollback buffer (CSI 3 J / ED 3).
        "E3" => Some(xtgettcap_hex_response(cap_hex, b"\x1b[3J")),
        // bce — background color erase (we implement BCE per VT220 spec).
        "bce" => Some(xtgettcap_empty_response(cap_hex)),
        _ => None,
    }
}

type XtgettcapResponseBuilder = fn(&str, &str) -> Option<String>;

const XTGETTCAP_RESPONSE_BUILDERS: [XtgettcapResponseBuilder; 4] = [
    xtgettcap_identity_response,
    xtgettcap_style_response,
    xtgettcap_cursor_response,
    xtgettcap_terminal_response,
];

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
    XTGETTCAP_RESPONSE_BUILDERS
        .iter()
        .find_map(|builder| builder(cap_name, cap_hex))
        .unwrap_or_else(|| xtgettcap_unknown_response(cap_hex))
}

/// Handle XTGETTCAP response.
fn handle_xtgettcap(core: &mut TerminalCore, buf: &[u8]) {
    core.meta.pending_responses.extend(xtgettcap_responses(buf));
}

fn xtgettcap_responses(buf: &[u8]) -> Vec<Vec<u8>> {
    let mut responses = Vec::new();

    // buf contains hex-encoded capability name(s), semicolon separated.
    // Example: "544e" = "TN" (terminal name).
    for_each_xtgettcap_request(buf, |cap_name, cap_hex| {
        let response = build_xtgettcap_response(cap_name, cap_hex);
        responses.push(response.into_bytes());
    });

    responses
}

fn for_each_xtgettcap_request(buf: &[u8], mut f: impl FnMut(&str, &str)) {
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
        f(&cap_name, cap_hex);
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

fn sixel_cell_dimensions(width: u32, height: u32) -> (u32, u32) {
    (
        width.div_ceil(CELL_PIXEL_WIDTH),
        height.div_ceil(CELL_PIXEL_HEIGHT),
    )
}

fn advance_cursor_after_sixel(core: &mut TerminalCore, cell_h: u32) {
    let cursor = *core.screen.cursor();
    let max_row = (core.screen.rows() as usize).saturating_sub(1);
    let new_row = cursor.row.saturating_add(cell_h as usize).min(max_row);
    core.screen.move_cursor(new_row, 0);
}

fn build_sixel_image_data(
    pixels: Vec<u8>,
    width: u32,
    height: u32,
) -> crate::grid::screen::ImageData {
    crate::grid::screen::ImageData::new(
        pixels,
        crate::parser::kitty::ImageFormat::Rgba,
        width,
        height,
    )
}

fn build_sixel_image_placement(
    cursor: crate::types::cursor::Cursor,
    image_id: u32,
    cell_w: u32,
    cell_h: u32,
) -> crate::grid::screen::ImagePlacement {
    crate::grid::screen::ImagePlacement {
        image_id,
        placement_id: None,
        row: cursor.row,
        col: cursor.col,
        display_cols: cell_w,
        display_rows: cell_h,
        ..crate::grid::screen::ImagePlacement::default()
    }
}

fn store_sixel_image(core: &mut TerminalCore, pixels: Vec<u8>, width: u32, height: u32) -> u32 {
    let data = build_sixel_image_data(pixels, width, height);
    core.screen.active_graphics_mut().store_image(None, data)
}

fn add_sixel_placement(core: &mut TerminalCore, placement: crate::grid::screen::ImagePlacement) {
    if let Some(notif) = core.screen.active_graphics_mut().add_placement(placement) {
        core.kitty.pending_image_notifications.push(notif);
    }
}

fn finalize_sixel_image_placement(
    core: &mut TerminalCore,
    pixels: Vec<u8>,
    width: u32,
    height: u32,
) -> Option<u32> {
    if width == 0 || height == 0 {
        return None;
    }

    let actual_id = store_sixel_image(core, pixels, width, height);
    let cursor = *core.screen.cursor();
    let (cell_w, cell_h) = sixel_cell_dimensions(width, height);
    let placement = build_sixel_image_placement(cursor, actual_id, cell_w, cell_h);
    add_sixel_placement(core, placement);

    Some(cell_h)
}

fn handle_sixel_complete(core: &mut TerminalCore, decoder: crate::parser::sixel::SixelDecoder) {
    let Some((pixels, width, height)) = decoder.finish() else {
        return;
    };
    let Some(cell_h) = finalize_sixel_image_placement(core, pixels, width, height) else {
        return;
    };
    advance_cursor_after_sixel(core, cell_h);
}
