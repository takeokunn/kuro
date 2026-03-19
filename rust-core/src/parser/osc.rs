//! OSC (Operating System Command) sequence handler

use super::osc_protocol::{
    encode_color_spec, handle_osc_1337, handle_osc_104, handle_osc_133, handle_osc_52,
    handle_osc_default_colors, parse_color_spec,
};

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
/// - OSC 52: Clipboard access.
/// - OSC 104: Reset color palette.
/// - OSC 133: Shell integration prompt marks.
/// - OSC 1337: iTerm2 inline images.
/// - All other OSC numbers are silently discarded.
pub(crate) fn handle_osc(core: &mut TerminalCore, params: &[&[u8]], _bell_terminated: bool) {
    if params.is_empty() {
        return;
    }
    match params[0] {
        b"0" | b"2" => {
            if let Some(raw) = params.get(1) {
                if raw.is_empty() {
                    return; // ignore empty titles
                }
                if raw.len() > MAX_TITLE_BYTES {
                    return; // ignore oversized titles (DoS prevention)
                }
                let title = String::from_utf8_lossy(raw).into_owned();
                core.meta.title = title;
                core.meta.title_dirty = true;
            }
        }
        b"7" => handle_osc_7(core, params),
        b"8" => handle_osc_8(core, params),
        b"4" => handle_osc_4(core, params),
        b"10" | b"11" | b"12" => handle_osc_default_colors(core, params),
        b"52" => handle_osc_52(core, params),
        b"104" => handle_osc_104(core, params),
        b"133" => handle_osc_133(core, params),
        b"1337" => handle_osc_1337(core, params),
        _ => {} // all other OSC numbers: silently ignore
    }
}

/// Handle OSC 7 — set current working directory.
///
/// Wire format: `OSC 7 ; file://hostname/path BEL`
/// Extracts the path component (after `file://host`), enforces
/// [`OSC7_MAX_PATH_BYTES`], and stores it in `core.osc_data.cwd`.
/// Sets `cwd_dirty = true` so the Emacs side updates the modeline.
#[inline]
fn handle_osc_7(core: &mut TerminalCore, params: &[&[u8]]) {
    if let Some(raw) = params.get(1) {
        let url = String::from_utf8_lossy(raw);
        // Strip file://hostname prefix to get just the path
        if let Some(after_scheme) = url.strip_prefix("file://") {
            // Skip hostname part (up to next /)
            let path = after_scheme
                .find('/')
                .map(|i| &after_scheme[i..])
                .unwrap_or(after_scheme);
            if path.len() <= OSC7_MAX_PATH_BYTES {
                core.osc_data.cwd = Some(path.to_string());
                core.osc_data.cwd_dirty = true;
            }
        }
    }
}

/// Handle OSC 8 — hyperlink start/end.
///
/// Wire format: `OSC 8 ; params ; uri BEL`
/// An empty `uri` closes the active hyperlink. A non-empty `uri`
/// (≤ [`OSC8_MAX_URI_BYTES`]) opens a new hyperlink.
/// The `params` field (e.g. `id=`) is accepted but not stored.
#[inline]
fn handle_osc_8(core: &mut TerminalCore, params: &[&[u8]]) {
    if params.get(1).is_some() {
        // params field (e.g. id=...) is accepted but intentionally discarded
        if let Some(uri_raw) = params.get(2) {
            let uri = String::from_utf8_lossy(uri_raw);
            if uri.is_empty() {
                // Close hyperlink
                core.osc_data.hyperlink = crate::types::osc::HyperlinkState::default();
            } else if uri.len() <= OSC8_MAX_URI_BYTES {
                core.osc_data.hyperlink = crate::types::osc::HyperlinkState {
                    uri: Some(uri.into_owned()),
                };
            }
        }
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
    // OSC 4 - Set/query palette color: OSC 4 ; N ; spec ST
    // params[1] = index, params[2] = "?" or "rgb:..." spec
    if let (Some(idx_raw), Some(spec_raw)) = (params.get(1), params.get(2)) {
        let idx_str = std::str::from_utf8(idx_raw).unwrap_or("");
        if let Ok(idx) = idx_str.parse::<usize>() {
            if idx < 256 {
                if *spec_raw == b"?" {
                    // Query: respond with current color
                    let rgb = core.osc_data.palette[idx].unwrap_or([0, 0, 0]);
                    let resp = format!("\x1b]4;{};{}\x07", idx, encode_color_spec(rgb));
                    core.meta.pending_responses.push(resp.into_bytes());
                } else {
                    let spec = std::str::from_utf8(spec_raw).unwrap_or("");
                    if let Some(rgb) = parse_color_spec(spec) {
                        core.osc_data.palette[idx] = Some(rgb);
                        core.osc_data.palette_dirty = true;
                    }
                }
            }
        }
    }
}

#[cfg(test)]
#[path = "tests/osc.rs"]
mod tests;
