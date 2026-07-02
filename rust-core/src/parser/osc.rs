//! OSC (Operating System Command) sequence handler

use super::osc_protocol::{
    encode_color_spec, handle_osc_104, handle_osc_133, handle_osc_1337, handle_osc_51,
    handle_osc_52, handle_osc_777, handle_osc_9, handle_osc_99, handle_osc_default_colors,
    parse_color_spec,
};

use crate::types::osc::DefaultColorSlot;
use crate::TerminalCore;

use crate::parser::limits::{MAX_TITLE_BYTES, OSC7_MAX_PATH_BYTES, OSC8_MAX_URI_BYTES};

const OSC7_MAX_HOST_BYTES: usize = 253;

struct Osc7Cwd {
    host: Option<String>,
    path: String,
}

/// Handle OSC sequences dispatched from the VTE parser.
/// Called from `TerminalCore::osc_dispatch`.
///
/// Handles:
/// - OSC 0 / OSC 2: set window title.
/// - OSC 4: Set/query individual palette color entries.
/// - OSC 3/5/6: X-property / special-color ops — parsed, safe no-op.
/// - OSC 7: Current Working Directory notification (`file://host/path`).
/// - OSC 8: Hyperlinks (`ESC]8;params;uri ST`).
/// - OSC 9: iTerm2 notification (`OSC 9 ; body`) and ConEmu progress (`OSC 9 ; 4 ; state ; pct`).
/// - OSC 10/11/12: Set/query default foreground/background/cursor colors.
/// - OSC 18/19: Window / text-area size queries (respond like CSI 18 t / 19 t).
/// - OSC 22: Window pointer cursor shape (CSS cursor name, e.g. "pointer", "default").
/// - OSC 23: Query current cursor shape — respond `OSC 23 ; <decscusr> ST`.
/// - OSC 110/111/112: Reset default foreground/background/cursor color to terminal default.
/// - OSC 51: Typed command request (security: validated on Rust and Elisp sides).
/// - OSC 52: Clipboard access.
/// - OSC 99: Kitty desktop notifications (`metadata ; payload`, colon-separated metadata).
/// - OSC 104: Reset color palette.
/// - OSC 133: Shell integration prompt marks.
/// - OSC 1337: iTerm2 inline images + `CurrentDirectory=`/`SetUserVar=`/`RemoteHost=`.
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
        b"66" => handle_osc_66(core, params),
        b"99" => handle_osc_99(core, params),
        b"777" => handle_osc_777(core, params),
        b"4" => handle_osc_4(core, params),
        b"10" | b"11" | b"12" => handle_osc_default_colors(core, params),
        // OSC 22 — window pointer cursor shape (e.g. "default", "pointer", "text", "crosshair").
        // Applications set this to change the OS mouse cursor within the terminal area.
        b"22" => handle_osc_pointer_shape(core, params),
        // OSC 18 / OSC 19 — window / text-area size queries. Respond like xterm's
        // CSI 18 t / CSI 19 t (character-cell size report) by delegating to the
        // XTWINOPS size-report builder. Pixel metrics are not tracked, so we use
        // the cell-based report (CSI 8;rows;cols / CSI 9;rows;cols).
        b"18" => handle_osc_size_query(core, 18),
        b"19" => handle_osc_size_query(core, 19),
        // OSC 23 — query the current cursor shape; respond via OSC.
        b"23" => handle_osc_cursor_shape_query(core, params),
        // OSC 3/5/6 — X property / special-color / dynamic special-color ops.
        // Parsed and treated as a safe no-op rather than left unrecognized.
        b"3" | b"5" | b"6" => {} // graceful no-op
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

/// Handle OSC 18 / OSC 19 — window / text-area size queries.
///
/// xterm answers these with the same character-cell report as the equivalent
/// XTWINOPS query (`CSI 18 t` → `CSI 8 ; rows ; cols t`, `CSI 19 t` →
/// `CSI 9 ; rows ; cols t`). We reuse [`build_xtwinops_size_report`] so the two
/// paths stay in lockstep. `op` is the equivalent CSI t operation number
/// (18 or 19). Pixel metrics are not tracked by this cell-based core.
fn handle_osc_size_query(core: &mut TerminalCore, op: u16) {
    let rows = core.screen.rows();
    let cols = core.screen.cols();
    if let Some(response) =
        crate::parser::csi::build_xtwinops_size_report(op, rows.into(), cols.into())
    {
        core.meta.pending_responses.push(response);
    }
}

/// Handle OSC 23 — query the current cursor shape, responding via OSC 23.
///
/// Responds `OSC 23 ; <decscusr> ST` where `<decscusr>` is the DECSCUSR
/// parameter integer for the current cursor shape (0/2/3/4/5/6). This mirrors
/// the DECSCUSR set sequence so applications can round-trip the cursor shape.
fn handle_osc_cursor_shape_query(core: &mut TerminalCore, params: &[&[u8]]) {
    // Only the bare query form `OSC 23 ; ?` (or no second param) reports.
    match params.get(1) {
        None => {}
        Some(p) if p.is_empty() || *p == b"?" => {}
        Some(_) => return,
    }
    let decscusr = i64::from(core.dec_modes.cursor_shape);
    let resp = format!("\x1b]23;{decscusr}\x07");
    core.meta.pending_responses.push(resp.into_bytes());
}

fn has_control_char(text: &str) -> bool {
    text.chars().any(|ch| ch.is_control() || ch == '\u{7f}')
}

fn hex_nibble(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

fn percent_decode_utf8(raw: &str) -> Option<String> {
    let bytes = raw.as_bytes();
    let mut decoded = Vec::with_capacity(bytes.len());
    let mut idx = 0;

    while idx < bytes.len() {
        if bytes[idx] == b'%' {
            let hi = hex_nibble(*bytes.get(idx + 1)?)?;
            let lo = hex_nibble(*bytes.get(idx + 2)?)?;
            decoded.push((hi << 4) | lo);
            idx += 3;
        } else {
            decoded.push(bytes[idx]);
            idx += 1;
        }
    }

    String::from_utf8(decoded).ok()
}

fn is_osc7_hostname_label(label: &str) -> bool {
    if label.is_empty() || label.len() > 63 {
        return false;
    }

    let bytes = label.as_bytes();
    let first = bytes[0];
    let last = bytes[bytes.len() - 1];
    first.is_ascii_alphanumeric()
        && last.is_ascii_alphanumeric()
        && bytes
            .iter()
            .all(|byte| byte.is_ascii_alphanumeric() || *byte == b'-')
}

fn is_osc7_safe_host(host: &str) -> bool {
    !host.is_empty()
        && host.len() <= OSC7_MAX_HOST_BYTES
        && host.is_ascii()
        && !has_control_char(host)
        && host.split('.').all(is_osc7_hostname_label)
}

fn osc7_host_from_raw(raw_host: &str) -> Option<Option<String>> {
    let host = percent_decode_utf8(raw_host)?;
    if host.is_empty() || host.eq_ignore_ascii_case("localhost") {
        Some(None)
    } else if is_osc7_safe_host(&host) {
        Some(Some(host))
    } else {
        None
    }
}

fn osc7_cwd_from_raw(raw: &[u8]) -> Option<Osc7Cwd> {
    let url = std::str::from_utf8(raw).ok()?;
    let after_scheme = url.strip_prefix("file://")?;
    let slash = after_scheme.find('/')?;
    let (raw_host, raw_path) = after_scheme.split_at(slash);

    let host = osc7_host_from_raw(raw_host)?;
    let path = percent_decode_utf8(raw_path)?;
    if path.len() > OSC7_MAX_PATH_BYTES || !path.starts_with('/') || has_control_char(&path) {
        return None;
    }

    Some(Osc7Cwd { host, path })
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
    osc_apply_param(params, 1, osc7_cwd_from_raw, |cwd| {
        core.osc_data.set_cwd(cwd.host, Some(cwd.path));
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

/// Maximum OSC 66 payload size in bytes (Kitty spec: "escape-code-safe UTF-8,
/// max 4096 bytes").  Payloads longer than this are truncated on a UTF-8
/// boundary before printing.
const OSC66_MAX_PAYLOAD_BYTES: usize = 4096;

/// Parse the colon-separated OSC 66 metadata into a [`TextSize`].
///
/// Metadata is a `:`-separated list of `key=value` pairs.  Recognised keys:
/// `s` (scale 1..=7, default 1), `w` (width 0..=7), `n` (numerator 0..=15),
/// `d` (denominator 0..=15), `v` (valign 0..=2), `h` (halign 0..=2).
/// Unknown keys and malformed values are ignored (the field keeps its default).
/// The denominator is forced to `0` when it is not strictly greater than the
/// numerator (per spec: "must be > n when non-zero"), which neutralises the
/// fraction rather than producing a nonsensical multiplier.
fn parse_osc66_metadata(raw: &[u8]) -> crate::types::cell::TextSize {
    use crate::types::cell::TextSize;
    let mut ts = TextSize::default();
    let meta = match std::str::from_utf8(raw) {
        Ok(s) => s,
        Err(_) => return ts,
    };

    for pair in meta.split(':') {
        let Some((key, value)) = pair.split_once('=') else {
            continue;
        };
        let Ok(v) = value.parse::<u8>() else {
            continue;
        };
        match key {
            "s" => ts.scale = v.clamp(1, 7),
            "w" => ts.width = v.min(7),
            "n" => ts.numerator = v.min(15),
            "d" => ts.denominator = v.min(15),
            "v" => ts.valign = v.min(2),
            "h" => ts.halign = v.min(2),
            _ => {}
        }
    }

    // Spec: denominator must be > numerator when non-zero. Otherwise drop the
    // fraction so the multiplier stays sane.
    if ts.denominator != 0 && ts.denominator <= ts.numerator {
        ts.denominator = 0;
        ts.numerator = 0;
    }

    ts
}

/// Handle OSC 66 — Kitty text-sizing protocol.
///
/// Wire format: `OSC 66 ; metadata ; text ST`.  `metadata` is a colon-separated
/// list of `key=value` pairs (see [`parse_osc66_metadata`]); `text` is the
/// payload to render at the requested size.  The payload may itself contain
/// `;` — VTE splits the OSC on `;`, so any `params[3..]` are rejoined with `;`.
/// The payload is capped at [`OSC66_MAX_PAYLOAD_BYTES`] and printed through the
/// normal print path with each cell stamped with the parsed `TextSize`.
fn handle_osc_66(core: &mut TerminalCore, params: &[&[u8]]) {
    let meta_raw: &[u8] = params.get(1).copied().unwrap_or(b"");
    let ts = parse_osc66_metadata(meta_raw);

    // Rejoin the payload: VTE splits on ';', so a payload containing ';' arrives
    // as params[2], params[3], ... — join them back with ';'.
    let payload: Vec<u8> = if params.len() <= 3 {
        params.get(2).copied().unwrap_or(b"").to_vec()
    } else {
        params[2..].join(&b';')
    };

    if payload.is_empty() {
        return;
    }

    // Cap to OSC66_MAX_PAYLOAD_BYTES on a UTF-8 char boundary.
    let text = String::from_utf8_lossy(&payload);
    let text: &str = if text.len() > OSC66_MAX_PAYLOAD_BYTES {
        let mut end = OSC66_MAX_PAYLOAD_BYTES;
        while end > 0 && !text.is_char_boundary(end) {
            end -= 1;
        }
        &text[..end]
    } else {
        &text
    };

    if text.is_empty() {
        return;
    }

    let text = text.to_owned();
    core.print_text_sized_payload(&text, ts);
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
                    u8::try_from(55 + 40 * v).expect("xterm color cube component fits in u8")
                }
            };
            [c(r), c(g), c(b)]
        }
        232..=255 => {
            let v =
                u8::try_from(8 + 10 * (idx - 232)).expect("xterm grayscale component fits in u8");
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
