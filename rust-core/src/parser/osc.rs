//! OSC (Operating System Command) sequence handler

use super::osc_protocol::{
    encode_color_spec, handle_osc_104, handle_osc_133, handle_osc_1337, handle_osc_51,
    handle_osc_52, handle_osc_777, handle_osc_9, handle_osc_99, handle_osc_default_colors,
    parse_color_spec,
};

use crate::types::osc::DefaultColorSlot;
use crate::TerminalCore;

use crate::parser::limits::{MAX_TITLE_BYTES, OSC7_MAX_PATH_BYTES, OSC8_MAX_URI_BYTES};

/// Handle OSC sequences dispatched from the VTE parser.
/// Called from `TerminalCore::osc_dispatch`.
///
/// Handles:
/// - OSC 0 / OSC 2: set window title.
/// - OSC 4: Set/query individual palette color entries.
/// - OSC 7: Current Working Directory notification (`file://host/path`).
/// - OSC 8: Hyperlinks (`ESC]8;params;uri ST`).
/// - OSC 10/11/12: Set/query default foreground/background/cursor colors.
/// - OSC 22: Window pointer cursor shape (CSS cursor name, e.g. "pointer", "default").
/// - OSC 110/111/112: Reset default foreground/background/cursor color to terminal default.
/// - OSC 51: Emacs eval command request (security: Elisp-side whitelist filtering).
/// - OSC 52: Clipboard access.
/// - OSC 99: Kitty desktop notifications (`metadata ; payload`, colon-separated metadata).
/// - OSC 104: Reset color palette.
/// - OSC 133: Shell integration prompt marks.
/// - OSC 1337: iTerm2 inline images.
/// - All other OSC numbers are silently discarded.
pub(crate) fn handle_osc(core: &mut TerminalCore, params: &[&[u8]], _bell_terminated: bool) {
    if params.is_empty() {
        return;
    }
    match params[0] {
        b"0" | b"2" => handle_osc_title(core, params),
        b"7" => handle_osc_7(core, params),
        b"8" => handle_osc_8(core, params),
        b"9" => handle_osc_9(core, params),
        b"99" => handle_osc_99(core, params),
        b"777" => handle_osc_777(core, params),
        b"4" => handle_osc_4(core, params),
        b"10" | b"11" | b"12" => handle_osc_default_colors(core, params),
        // OSC 22 — window pointer cursor shape (e.g. "default", "pointer", "text", "crosshair").
        // Applications set this to change the OS mouse cursor within the terminal area.
        b"22" => handle_osc_pointer_shape(core, params),
        // OSC 110/111/112: reset default fg/bg/cursor color to terminal default.
        // Symmetric counterparts to OSC 10/11/12 set/query.
        b"110" => reset_osc_default_color(core, DefaultColorSlot::Foreground),
        b"111" => reset_osc_default_color(core, DefaultColorSlot::Background),
        b"112" => reset_osc_default_color(core, DefaultColorSlot::Cursor),
        b"51" => handle_osc_51(core, params),
        b"52" => handle_osc_52(core, params),
        b"104" => handle_osc_104(core, params),
        b"133" => handle_osc_133(core, params),
        b"1337" => handle_osc_1337(core, params),
        _ => {} // all other OSC numbers: silently ignore
    }
}

fn osc_lossy_text(raw: &[u8]) -> String {
    String::from_utf8_lossy(raw).into_owned()
}

fn osc_normalized_lossy_text(raw: &[u8], max_len: Option<usize>) -> Option<String> {
    if max_len.is_some_and(|max_len| raw.len() > max_len) {
        return None;
    }

    let text = osc_lossy_text(raw);
    if text.is_empty() {
        None
    } else {
        Some(text)
    }
}

fn osc_apply_param<T, F, G>(params: &[&[u8]], idx: usize, parse: F, mut set: G)
where
    F: Fn(&[u8]) -> Option<T>,
    G: FnMut(T),
{
    if let Some(value) = params.get(idx).and_then(|raw| parse(raw)) {
        set(value);
    }
}

fn osc_title_from_raw(raw: &[u8]) -> Option<String> {
    osc_normalized_lossy_text(raw, Some(MAX_TITLE_BYTES))
}

fn osc_param_value<T>(params: &[&[u8]], idx: usize, parse: fn(&[u8]) -> Option<T>) -> Option<T> {
    params.get(idx).and_then(|raw| parse(raw))
}

fn handle_osc_title(core: &mut TerminalCore, params: &[&[u8]]) {
    osc_apply_param(params, 1, osc_title_from_raw, |title| {
        core.meta.set_title(title);
    });
}

fn osc_pointer_shape_from_raw(raw: &[u8]) -> Option<String> {
    osc_normalized_lossy_text(raw, None)
}

fn handle_osc_pointer_shape(core: &mut TerminalCore, params: &[&[u8]]) {
    osc_apply_param(params, 1, osc_pointer_shape_from_raw, |name| {
        core.osc_data.set_pointer_shape(Some(name));
    });
}

fn osc7_host_and_path(after_scheme: &str) -> (&str, &str) {
    match after_scheme.find('/') {
        Some(i) => (&after_scheme[..i], &after_scheme[i..]),
        None => ("", after_scheme),
    }
}

fn osc7_cwd_from_raw(raw: &[u8]) -> Option<(Option<String>, String)> {
    let url = osc_lossy_text(raw);
    let after_scheme = url.strip_prefix("file://")?;
    let (host, path) = osc7_host_and_path(after_scheme);

    if path.len() > OSC7_MAX_PATH_BYTES {
        return None;
    }

    let host = match host {
        "" | "localhost" => None,
        host => Some(host.to_owned()),
    };
    let path = path.to_owned();

    Some((host, path))
}

fn osc8_uri_from_raw(raw: &[u8]) -> Option<Option<String>> {
    if raw.is_empty() {
        return Some(None);
    }
    osc_normalized_lossy_text(raw, Some(OSC8_MAX_URI_BYTES)).map(Some)
}

fn reset_osc_default_color(core: &mut TerminalCore, slot: DefaultColorSlot) {
    core.osc_data.reset_default_color(slot);
}

#[inline]
fn handle_osc_7(core: &mut TerminalCore, params: &[&[u8]]) {
    osc_apply_param(params, 1, osc7_cwd_from_raw, |(host, path)| {
        core.osc_data.set_cwd(host, Some(path));
    });
}

/// Handle OSC 8 — hyperlink start/end.
///
/// Wire format: `OSC 8 ; params ; uri BEL`
/// An empty `uri` closes the active hyperlink. A non-empty `uri`
/// (≤ [`OSC8_MAX_URI_BYTES`]) opens a new hyperlink.
/// The `params` field (e.g. `id=`) is accepted but not stored.
#[inline]
fn handle_osc_8(core: &mut TerminalCore, params: &[&[u8]]) {
    let Some(_) = params.get(1) else {
        return;
    };

    osc_apply_param(params, 2, osc8_uri_from_raw, |uri| {
        // Close hyperlink or store a validated URI.
        core.osc_data.set_hyperlink_uri(uri);
    });
}

/// Compute the standard xterm 256-color built-in color for palette index `idx`.
///
/// - Indices   0–15:  Standard 16 ANSI colors (xterm defaults).
/// - Indices  16–231: 6×6×6 RGB cube; component `c` → 0 if c==0, else 55+40×c.
/// - Indices 232–255: Grayscale ramp; value = 8 + 10×(idx−232).
fn xterm_default_color(idx: usize) -> [u8; 3] {
    const ANSI16: [[u8; 3]; 16] = [
        [0, 0, 0],
        [128, 0, 0],
        [0, 128, 0],
        [128, 128, 0],
        [0, 0, 128],
        [128, 0, 128],
        [0, 128, 128],
        [192, 192, 192],
        [128, 128, 128],
        [255, 0, 0],
        [0, 255, 0],
        [255, 255, 0],
        [0, 0, 255],
        [255, 0, 255],
        [0, 255, 255],
        [255, 255, 255],
    ];
    match idx {
        0..=15 => ANSI16[idx],
        16..=231 => {
            let i = idx - 16;
            let b = i % 6;
            let g = (i / 6) % 6;
            let r = i / 36;
            let c = |v: usize| -> u8 {
                if v == 0 {
                    0
                } else {
                    (55 + 40 * v) as u8
                }
            };
            [c(r), c(g), c(b)]
        }
        232..=255 => {
            let v = (8 + 10 * (idx - 232)) as u8;
            [v, v, v]
        }
        _ => [0, 0, 0],
    }
}

fn parse_osc_palette_index(params: &[&[u8]]) -> Option<usize> {
    osc_param_value(params, 1, |raw| {
        std::str::from_utf8(raw)
            .ok()
            .and_then(|idx_str| idx_str.parse::<usize>().ok())
            .filter(|idx| *idx < 256)
    })
}

fn apply_osc_palette_query(core: &mut TerminalCore, idx: usize) {
    let rgb = core.osc_data.palette[idx].unwrap_or_else(|| xterm_default_color(idx));
    let resp = format!("\x1b]4;{};{}\x07", idx, encode_color_spec(rgb));
    core.meta.pending_responses.push(resp.into_bytes());
}

fn apply_osc_palette_update(core: &mut TerminalCore, idx: usize, spec_raw: &[u8]) {
    let spec = std::str::from_utf8(spec_raw).unwrap_or("");
    if let Some(rgb) = parse_color_spec(spec) {
        core.osc_data.set_palette_entry(idx, rgb);
    }
}

/// Handle OSC 4 — 256-color palette set/query.
///
/// Wire format: `OSC 4 ; index ; spec BEL`
/// `spec = "?"` queries entry `index`; any other spec is parsed as
/// `rgb:RR/GG/BB` and stored in `core.osc_data.palette[index]`.
/// Sets `palette_dirty = true` on a successful set.
#[inline]
fn handle_osc_4(core: &mut TerminalCore, params: &[&[u8]]) {
    let Some(idx) = parse_osc_palette_index(params) else {
        return;
    };
    let Some(spec_raw) = params.get(2) else {
        return;
    };

    // OSC 4 - Set/query palette color: OSC 4 ; N ; spec ST
    // params[1] = index, params[2] = "?" or "rgb:..." spec
    if *spec_raw == b"?" {
        // Query: return the application override if set, else the xterm built-in default.
        apply_osc_palette_query(core, idx);
    } else {
        apply_osc_palette_update(core, idx, spec_raw);
    }
}

#[cfg(test)]
#[path = "tests/osc.rs"]
mod tests;
