//! Protocol-specific OSC handlers: OSC 52 (clipboard), OSC 104 (palette reset),
//! OSC 133 (prompt marks), OSC 10/11/12 (default colors), OSC 1337 (iTerm2 images).

use crate::TerminalCore;

#[path = "osc_protocol_support.rs"]
mod support;

/// Encode an RGB triple as `rgb:RRRR/GGGG/BBBB` for OSC query responses.
pub(super) fn encode_color_spec(rgb: [u8; 3]) -> String {
    format!(
        "rgb:{:04x}/{:04x}/{:04x}",
        u16::from(rgb[0]) << 8 | u16::from(rgb[0]),
        u16::from(rgb[1]) << 8 | u16::from(rgb[1]),
        u16::from(rgb[2]) << 8 | u16::from(rgb[2])
    )
}

/// Parse `rgb:RR/GG/BB` or `#RRGGBB` color strings into `[R,G,B]`.
///
/// Supports both xterm-style `rgb:RR/GG/BB` (16-bit per channel, upper 8 bits used)
/// and CSS-style `#RRGGBB` (8-bit per channel).
pub(super) fn parse_color_spec(s: &str) -> Option<[u8; 3]> {
    let s = s.trim();
    if let Some(rest) = s.strip_prefix("rgb:") {
        // Format: rgb:RRRR/GGGG/BBBB (4 hex digits per channel) or rgb:RR/GG/BB (2 hex)
        let parts: Vec<&str> = rest.splitn(3, '/').collect();
        if parts.len() != 3 {
            return None;
        }
        let r = u16::from_str_radix(parts[0], 16).ok()?;
        let g = u16::from_str_radix(parts[1], 16).ok()?;
        let b = u16::from_str_radix(parts[2], 16).ok()?;
        Some([
            normalize_hex_channel(r, parts[0].len())?,
            normalize_hex_channel(g, parts[1].len())?,
            normalize_hex_channel(b, parts[2].len())?,
        ])
    } else if let Some(hex) = s.strip_prefix('#') {
        if hex.len() == 6 {
            let r = u8::from_str_radix(&hex[0..2], 16).ok()?;
            let g = u8::from_str_radix(&hex[2..4], 16).ok()?;
            let b = u8::from_str_radix(&hex[4..6], 16).ok()?;
            Some([r, g, b])
        } else {
            None
        }
    } else {
        None
    }
}

fn normalize_hex_channel(value: u16, digits: usize) -> Option<u8> {
    match digits {
        1 | 2 => u8::try_from(value).ok(),
        3 | 4 => u8::try_from(value >> 8).ok(),
        _ => None,
    }
}

pub(crate) fn handle_osc_51(core: &mut TerminalCore, params: &[&[u8]]) {
    support::handle_osc_51(core, params);
}

/// Handle OSC 52 — Clipboard access.
pub(crate) fn handle_osc_52(core: &mut TerminalCore, params: &[&[u8]]) {
    support::handle_osc_52(core, params);
}

/// Handle OSC 9 — desktop notification, iTerm2 form (`OSC 9 ; <body> ST`).
///
/// Only the single-parameter iTerm2 form is surfaced as a notification; the
/// multi-parameter ConEmu form (`OSC 9 ; 4 ; …` progress, etc.) is ignored so
/// progress updates are not shown as notifications.
pub(crate) fn handle_osc_9(core: &mut TerminalCore, params: &[&[u8]]) {
    support::handle_osc_9(core, params);
}

/// Handle OSC 777 — desktop notification (`OSC 777 ; notify ; <title> ; <body> ST`).
///
/// Only the `notify` subcommand is supported. An empty title is reported as
/// `None`; an empty body (or any field over [`NOTIFICATION_MAX_BYTES`]) is
/// ignored.
pub(crate) fn handle_osc_777(core: &mut TerminalCore, params: &[&[u8]]) {
    support::handle_osc_777(core, params);
}

pub(crate) fn handle_osc_104(core: &mut TerminalCore, params: &[&[u8]]) {
    support::handle_osc_104(core, params);
}

pub(crate) fn handle_osc_133(core: &mut TerminalCore, params: &[&[u8]]) {
    support::handle_osc_133(core, params);
}

/// Handle OSC 10/11/12 — Set/query default fg/bg/cursor color.
pub(crate) fn handle_osc_default_colors(core: &mut TerminalCore, params: &[&[u8]]) {
    support::handle_osc_default_colors(core, params);
}

#[path = "osc_iterm2_impls.rs"]
mod iterm2;

pub(crate) use iterm2::handle_osc_1337;
#[cfg(test)]
pub(crate) use iterm2::{decode_iterm2_image, parse_iterm2_params};

#[cfg(test)]
#[path = "tests/osc_protocol.rs"]
mod tests;
