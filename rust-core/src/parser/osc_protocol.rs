//! Protocol-specific OSC handlers: OSC 52 (clipboard), OSC 104 (palette reset),
//! OSC 133 (prompt marks), OSC 10/11/12 (default colors), OSC 1337 (iTerm2 images).

use super::limits::NOTIFICATION_MAX_BYTES;
use crate::TerminalCore;
use crate::types::osc::{DefaultColorSlot, Notification};

/// Decode a `params` slot as UTF-8, returning `""` on failure.
///
/// Usage: `osc_param_str!(params, 1)` expands to the UTF-8 string at index 1,
/// or `""` if the slot is absent or contains invalid UTF-8.
macro_rules! osc_param_str {
    ($params:expr, $idx:literal) => {
        $params
            .get($idx)
            .and_then(|b| std::str::from_utf8(b).ok())
            .unwrap_or("")
    };
}

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
#[expect(
    clippy::cast_possible_truncation,
    reason = "2-digit hex colors are 0x00..=0xFF; the else branch is only reached when digits ≤ 2, so v fits in u8"
)]
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
        // Normalize to 8-bit (take upper 8 bits if 4-digit, else direct if 2-digit)
        let normalize = |v: u16, digits: usize| -> u8 {
            if digits > 2 {
                (v >> 8) as u8
            } else {
                v as u8
            }
        };
        Some([
            normalize(r, parts[0].len()),
            normalize(g, parts[1].len()),
            normalize(b, parts[2].len()),
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

fn default_color_slot(osc_num: &[u8]) -> Option<DefaultColorSlot> {
    match osc_num {
        b"10" => Some(DefaultColorSlot::Foreground),
        b"11" => Some(DefaultColorSlot::Background),
        b"12" => Some(DefaultColorSlot::Cursor),
        _ => None,
    }
}

/// Handle OSC 51 — Emacs eval command request.
/// Stores the command string for Elisp-side whitelist filtering.
pub(crate) fn handle_osc_51(core: &mut TerminalCore, params: &[&[u8]]) {
    // Wire format: OSC 51 ; e ; COMMAND ST
    // params[1] should be "e" (eval subcommand)
    // params[2] is the command string
    if let Some(sub) = params.get(1) {
        if *sub == b"e" {
            if let Some(cmd_raw) = params.get(2) {
                if cmd_raw.len() <= crate::parser::limits::OSC51_MAX_EVAL_BYTES {
                    if let Ok(cmd) = std::str::from_utf8(cmd_raw) {
                        core.osc_data.eval_commands.push(cmd.to_owned());
                    }
                }
            }
        }
    }
}

/// Handle OSC 52 — Clipboard access.
pub(crate) fn handle_osc_52(core: &mut TerminalCore, params: &[&[u8]]) {
    if let Some(data_raw) = params.get(2) {
        if data_raw == b"?" {
            core.osc_data
                .clipboard_actions
                .push(crate::types::osc::ClipboardAction::Query);
        } else if data_raw.len() <= 1_048_576 {
            // 1MB cap
            if let Ok(decoded) = crate::util::base64::decode(data_raw) {
                if let Ok(text) = String::from_utf8(decoded) {
                    core.osc_data
                        .clipboard_actions
                        .push(crate::types::osc::ClipboardAction::Write(text));
                }
            }
        }
    }
}

fn build_notification(title_raw: Option<&[u8]>, body_raw: &[u8]) -> Option<Notification> {
    if body_raw.is_empty() || body_raw.len() > NOTIFICATION_MAX_BYTES {
        return None;
    }
    if let Some(title_raw) = title_raw {
        if title_raw.len() > NOTIFICATION_MAX_BYTES {
            return None;
        }
        Some(Notification {
            title: (!title_raw.is_empty()).then(|| String::from_utf8_lossy(title_raw).into_owned()),
            body: String::from_utf8_lossy(body_raw).into_owned(),
        })
    } else {
        Some(Notification {
            title: None,
            body: String::from_utf8_lossy(body_raw).into_owned(),
        })
    }
}

/// Handle OSC 9 — desktop notification, iTerm2 form (`OSC 9 ; <body> ST`).
///
/// Only the single-parameter iTerm2 form is surfaced as a notification; the
/// multi-parameter ConEmu form (`OSC 9 ; 4 ; …` progress, etc.) is ignored so
/// progress updates are not shown as notifications.
pub(crate) fn handle_osc_9(core: &mut TerminalCore, params: &[&[u8]]) {
    if params.len() != 2 {
        return;
    }
    if let Some(body_raw) = params.get(1) {
        if let Some(notification) = build_notification(None, body_raw) {
            core.osc_data.notifications.push(notification);
        }
    }
}

/// Handle OSC 777 — desktop notification (`OSC 777 ; notify ; <title> ; <body> ST`).
///
/// Only the `notify` subcommand is supported. An empty title is reported as
/// `None`; an empty body (or any field over [`NOTIFICATION_MAX_BYTES`]) is
/// ignored.
pub(crate) fn handle_osc_777(core: &mut TerminalCore, params: &[&[u8]]) {
    match params.get(1) {
        Some(sub) if *sub == b"notify" => {}
        _ => return, // only the "notify" subcommand is supported
    }
    let title_raw: &[u8] = params.get(2).copied().unwrap_or(b"");
    let body_raw: &[u8] = params.get(3).copied().unwrap_or(b"");
    if let Some(notification) = build_notification(Some(title_raw), body_raw) {
        core.osc_data.notifications.push(notification);
    }
}

/// Handle OSC 104 — Reset color palette.
pub(crate) fn handle_osc_104(core: &mut TerminalCore, params: &[&[u8]]) {
    if let Some(idx_raw) = params.get(1) {
        if idx_raw.is_empty() {
            core.osc_data.clear_palette();
        } else {
            let idx_str = osc_param_str!(params, 1);
            if let Ok(idx) = idx_str.parse::<usize>() {
                if idx < 256 {
                    core.osc_data.clear_palette_entry(idx);
                }
            }
        }
    } else {
        core.osc_data.clear_palette();
    }
    core.osc_data.palette_dirty = true;
}

pub(crate) fn handle_osc_133(core: &mut TerminalCore, params: &[&[u8]]) {
    let Some(mark_raw) = params.get(1) else {
        return;
    };

    let Some(mark) = crate::types::osc::PromptMark::from_osc_133_mark(*mark_raw.first().unwrap_or(&0)) else {
        return;
    };

    handle_osc_133_mark(core, mark, params);
}

/// Result of parsing OSC 133 extras (params beyond the mark letter).
#[derive(Default)]
struct Osc133Extras {
    exit_code: Option<i32>,
    aid: Option<String>,
    duration_ms: Option<u64>,
    err_path: Option<String>,
}

/// Reject strings containing C0 controls (0x00..=0x1F) or DEL (0x7F).
///
/// Shell-supplied values must never smuggle ESC/NUL/DEL into Elisp-visible
/// fields. Oversized or control-bearing values are silently dropped.
#[inline]
fn has_control_bytes(s: &str) -> bool {
    s.bytes().any(|b| b < 0x20 || b == 0x7F)
}

/// Strict printable-ASCII predicate for `aid=` values.
///
/// `aid=` is a job/action identifier — by convention it must be a printable
/// ASCII token in the visible-glyph range `[!-~]` (0x21..=0x7E). This rejects
/// embedded spaces (which OSC parameter splitting would already mangle on `;`)
/// as well as any C0/DEL or non-ASCII byte. Stricter than `has_control_bytes`
/// which allows space (0x20) and high-bit / UTF-8 bytes.
#[inline]
fn is_printable_aid(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|b| (0x21..=0x7E).contains(&b))
}

#[inline]
fn queue_prompt_mark_event(core: &mut TerminalCore, event: crate::types::osc::PromptMarkEvent) {
    core.osc_data
        .push_prompt_mark(event, crate::parser::limits::MAX_PENDING_PROMPT_MARKS);
}

#[inline]
fn handle_osc_133_mark(
    core: &mut TerminalCore,
    mark: crate::types::osc::PromptMark,
    params: &[&[u8]],
) {
    let extras = parse_osc133_extras(params, &mark);
    let event = build_prompt_mark_event(core, mark, extras);
    queue_prompt_mark_event(core, event);
}

#[inline]
fn parse_osc133_positional_exit_code(
    mark: &crate::types::osc::PromptMark,
    param_index: usize,
    raw: &str,
) -> Option<i32> {
    if matches!(mark, crate::types::osc::PromptMark::CommandEnd)
        && param_index == 2
        && !raw.contains('=')
    {
        return raw.parse().ok();
    }

    None
}

#[inline]
fn parse_osc133_extra_item(
    extras: &mut Osc133Extras,
    mark: &crate::types::osc::PromptMark,
    index: usize,
    raw: &[u8],
) {
    let s = match std::str::from_utf8(raw) {
        Ok(v) => v,
        Err(_) => return,
    };

    if let Some(exit_code) = parse_osc133_positional_exit_code(mark, index, s) {
        extras.exit_code = Some(exit_code);
        return;
    }

    if let Some((key, value)) = s.split_once('=') {
        apply_osc133_extra_pair(extras, key, value);
    }
}

#[inline]
fn apply_osc133_aid(extras: &mut Osc133Extras, value: &str) {
    use super::limits::OSC133_MAX_AID_BYTES;

    // Silent drop on oversize OR non-printable-ASCII (`[!-~]+`).
    // Empty `aid=` round-trips as Some("") so consumers can distinguish
    // "absent" from "explicitly empty"; only non-empty values must satisfy
    // the printable predicate.
    if value.len() <= OSC133_MAX_AID_BYTES && (value.is_empty() || is_printable_aid(value)) {
        extras.aid = Some(value.to_string());
    }
}

#[inline]
fn apply_osc133_duration(extras: &mut Osc133Extras, value: &str) {
    use super::limits::MAX_PROMPT_DURATION_MS;

    extras.duration_ms = value
        .parse::<u64>()
        .ok()
        .filter(|ms| *ms <= MAX_PROMPT_DURATION_MS);
}

#[inline]
fn apply_osc133_err_path(extras: &mut Osc133Extras, value: &str) {
    use super::limits::OSC133_MAX_ERR_PATH_BYTES;

    // Silent drop on oversize or control-char injection.
    // `err_path` is UTF-8-tolerant (paths may contain non-ASCII).
    if value.len() <= OSC133_MAX_ERR_PATH_BYTES && !has_control_bytes(value) {
        extras.err_path = Some(value.to_string());
    }
}

#[inline]
fn apply_osc133_extra_pair(extras: &mut Osc133Extras, key: &str, value: &str) {
    match key {
        "aid" => apply_osc133_aid(extras, value),
        "duration" => apply_osc133_duration(extras, value),
        "err" => apply_osc133_err_path(extras, value),
        _ => {}
    }
}

#[inline]
fn parse_osc133_extras(params: &[&[u8]], mark: &crate::types::osc::PromptMark) -> Osc133Extras {
    let mut extras = Osc133Extras::default();
    // params[0] = "133", params[1] = mark letter; params[2..] are extras.
    for (i, raw) in params.iter().enumerate().skip(2) {
        parse_osc133_extra_item(&mut extras, mark, i, raw);
    }
    extras
}

fn build_prompt_mark_event(
    core: &TerminalCore,
    mark: crate::types::osc::PromptMark,
    extras: Osc133Extras,
) -> crate::types::osc::PromptMarkEvent {
    let cursor = *core.screen.cursor();
    crate::types::osc::PromptMarkEvent::new(
        mark,
        cursor.row,
        cursor.col,
        extras.exit_code,
        extras.aid,
        extras.duration_ms,
        extras.err_path,
    )
}

/// Handle OSC 10/11/12 — Set/query default fg/bg/cursor color.
pub(crate) fn handle_osc_default_colors(core: &mut TerminalCore, params: &[&[u8]]) {
    if let Some(spec_raw) = params.get(1) {
        let osc_num = params[0];
        if *spec_raw == b"?" {
            handle_osc_default_color_query(core, osc_num);
        } else {
            let spec = osc_param_str!(params, 1);
            handle_osc_default_color_set(core, osc_num, spec);
        }
    }
}

fn handle_osc_default_color_query(core: &mut TerminalCore, osc_num: &[u8]) {
    let Some(slot) = default_color_slot(osc_num) else {
        return;
    };
    emit_default_color_query(core, osc_num, slot);
}

fn handle_osc_default_color_set(core: &mut TerminalCore, osc_num: &[u8], spec: &str) {
    apply_default_color_update(core, osc_num, spec);
}

fn emit_default_color_query(core: &mut TerminalCore, osc_num: &[u8], slot: DefaultColorSlot) {
    let rgb = core.osc_data.default_color_rgb(slot);
    let resp = format!("\x1b]{};{}\x07", osc_num.escape_ascii(), encode_color_spec(rgb));
    core.meta.pending_responses.push(resp.into_bytes());
}

fn apply_default_color_update(core: &mut TerminalCore, osc_num: &[u8], spec: &str) {
    if let Some([r, g, b]) = parse_color_spec(spec) {
        let color = Some(crate::types::Color::Rgb(r, g, b));
        if let Some(slot) = default_color_slot(osc_num) {
            core.osc_data.set_default_color(slot, color);
        } else {
            core.osc_data.default_colors_dirty = true;
        }
    }
}

#[path = "osc_iterm2_impls.rs"]
mod iterm2;

#[cfg(test)]
pub(crate) use iterm2::{decode_iterm2_image, parse_iterm2_params};
pub(crate) use iterm2::handle_osc_1337;

#[cfg(test)]
#[path = "tests/osc_protocol.rs"]
mod tests;
