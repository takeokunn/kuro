use super::{encode_color_spec, parse_color_spec};
use crate::parser::limits::{
    MAX_PENDING_PROMPT_MARKS, MAX_PROMPT_DURATION_MS, OSC133_MAX_AID_BYTES,
    OSC133_MAX_ERR_PATH_BYTES, OSC51_MAX_EVAL_BYTES,
};
use crate::types::osc::{
    ClipboardAction, DefaultColorSlot, Notification, PromptMark, PromptMarkEvent,
};
use crate::TerminalCore;

fn push_osc_51_eval_command(core: &mut TerminalCore, cmd_raw: &[u8]) {
    if cmd_raw.len() > OSC51_MAX_EVAL_BYTES {
        return;
    }

    if let Ok(cmd) = std::str::from_utf8(cmd_raw) {
        core.osc_data.eval_commands.push(cmd.to_owned());
    }
}

pub(super) fn handle_osc_51(core: &mut TerminalCore, params: &[&[u8]]) {
    // Wire format: OSC 51 ; e ; COMMAND ST.
    let Some(sub) = params.get(1) else {
        return;
    };
    if *sub != b"e" {
        return;
    }

    let Some(cmd_raw) = params.get(2) else {
        return;
    };
    push_osc_51_eval_command(core, cmd_raw);
}

fn push_osc_52_clipboard_write(core: &mut TerminalCore, data_raw: &[u8]) {
    if data_raw.len() > 1_048_576 {
        return;
    }

    if let Ok(decoded) = crate::util::base64::decode(data_raw) {
        if let Ok(text) = String::from_utf8(decoded) {
            core.osc_data
                .clipboard_actions
                .push(ClipboardAction::Write(text));
        }
    }
}

pub(super) fn handle_osc_52(core: &mut TerminalCore, params: &[&[u8]]) {
    let Some(data_raw) = params.get(2) else {
        return;
    };

    if data_raw == b"?" {
        core.osc_data.clipboard_actions.push(ClipboardAction::Query);
        return;
    }

    // 1MB cap.
    push_osc_52_clipboard_write(core, data_raw);
}

fn build_notification(title_raw: Option<&[u8]>, body_raw: &[u8]) -> Option<Notification> {
    if body_raw.is_empty() || body_raw.len() > crate::parser::limits::NOTIFICATION_MAX_BYTES {
        return None;
    }
    if let Some(title_raw) = title_raw {
        if title_raw.len() > crate::parser::limits::NOTIFICATION_MAX_BYTES {
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

fn push_notification(core: &mut TerminalCore, title_raw: Option<&[u8]>, body_raw: &[u8]) {
    if let Some(notification) = build_notification(title_raw, body_raw) {
        core.osc_data.notifications.push(notification);
    }
}

pub(super) fn handle_osc_9(core: &mut TerminalCore, params: &[&[u8]]) {
    if params.len() != 2 {
        return;
    }
    if let Some(body_raw) = params.get(1) {
        push_notification(core, None, body_raw);
    }
}

pub(super) fn handle_osc_777(core: &mut TerminalCore, params: &[&[u8]]) {
    match params.get(1) {
        Some(sub) if *sub == b"notify" => {}
        _ => return, // only the "notify" subcommand is supported
    }
    let title_raw: &[u8] = params.get(2).copied().unwrap_or(b"");
    let body_raw: &[u8] = params.get(3).copied().unwrap_or(b"");
    push_notification(core, Some(title_raw), body_raw);
}

/// Handle OSC 104 — Reset color palette.
fn apply_osc_104_palette_reset(core: &mut TerminalCore, idx_raw: Option<&[u8]>) {
    match idx_raw {
        None => core.osc_data.clear_palette(),
        Some([]) => core.osc_data.clear_palette(),
        Some(idx_raw) => {
            let idx_str = std::str::from_utf8(idx_raw).unwrap_or("");
            if let Ok(idx) = idx_str.parse::<usize>() {
                if idx < 256 {
                    core.osc_data.clear_palette_entry(idx);
                }
            }
        }
    }

    core.osc_data.mark_palette_dirty();
}

pub(super) fn handle_osc_104(core: &mut TerminalCore, params: &[&[u8]]) {
    apply_osc_104_palette_reset(core, params.get(1).copied());
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
#[inline]
fn has_control_bytes(s: &str) -> bool {
    s.bytes().any(|b| b < 0x20 || b == 0x7F)
}

/// Strict printable-ASCII predicate for `aid=` values.
#[inline]
fn is_printable_aid(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|b| (0x21..=0x7E).contains(&b))
}

#[inline]
fn queue_prompt_mark_event(core: &mut TerminalCore, event: PromptMarkEvent) {
    core.osc_data
        .push_prompt_mark(event, MAX_PENDING_PROMPT_MARKS);
}

#[inline]
fn handle_osc_133_mark(core: &mut TerminalCore, mark: PromptMark, params: &[&[u8]]) {
    let extras = parse_osc133_extras(params, &mark);
    let event = build_prompt_mark_event(core, mark, extras);
    queue_prompt_mark_event(core, event);
}

#[inline]
fn parse_osc133_positional_exit_code(
    mark: &PromptMark,
    param_index: usize,
    raw: &str,
) -> Option<i32> {
    if matches!(mark, PromptMark::CommandEnd) && param_index == 2 && !raw.contains('=') {
        return raw.parse().ok();
    }

    None
}

#[inline]
fn osc133_extra_item_from_raw<'a>(
    mark: &PromptMark,
    index: usize,
    raw: &'a [u8],
) -> Option<Osc133ExtraItem<'a>> {
    let s = std::str::from_utf8(raw).ok()?;
    osc133_extra_item_from_str(mark, index, s)
}

#[inline]
fn apply_osc133_extra_item(extras: &mut Osc133Extras, item: Osc133ExtraItem<'_>) {
    match item {
        Osc133ExtraItem::ExitCode(exit_code) => {
            extras.exit_code = Some(exit_code);
        }
        Osc133ExtraItem::Pair { key, value } => {
            apply_osc133_extra_pair(extras, key, value);
        }
    }
}

enum Osc133ExtraItem<'a> {
    ExitCode(i32),
    Pair { key: &'a str, value: &'a str },
}

fn osc133_extra_item_from_str<'a>(
    mark: &PromptMark,
    index: usize,
    raw: &'a str,
) -> Option<Osc133ExtraItem<'a>> {
    if let Some(exit_code) = parse_osc133_positional_exit_code(mark, index, raw) {
        return Some(Osc133ExtraItem::ExitCode(exit_code));
    }

    raw.split_once('=')
        .map(|(key, value)| Osc133ExtraItem::Pair { key, value })
}

#[inline]
fn apply_osc133_aid(extras: &mut Osc133Extras, value: &str) {
    // Silent drop on oversize OR non-printable-ASCII (`[!-~]+`).
    if value.len() <= OSC133_MAX_AID_BYTES && (value.is_empty() || is_printable_aid(value)) {
        extras.aid = Some(value.to_string());
    }
}

#[inline]
fn apply_osc133_duration(extras: &mut Osc133Extras, value: &str) {
    extras.duration_ms = value
        .parse::<u64>()
        .ok()
        .filter(|ms| *ms <= MAX_PROMPT_DURATION_MS);
}

#[inline]
fn apply_osc133_err_path(extras: &mut Osc133Extras, value: &str) {
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
fn parse_osc133_extras(params: &[&[u8]], mark: &PromptMark) -> Osc133Extras {
    let mut extras = Osc133Extras::default();
    for (i, raw) in params.iter().enumerate().skip(2) {
        if let Some(item) = osc133_extra_item_from_raw(mark, i, raw) {
            apply_osc133_extra_item(&mut extras, item);
        }
    }
    extras
}

fn build_prompt_mark_event(
    core: &TerminalCore,
    mark: PromptMark,
    extras: Osc133Extras,
) -> PromptMarkEvent {
    let cursor = *core.screen.cursor();
    PromptMarkEvent::new(
        mark,
        cursor.row,
        cursor.col,
        extras.exit_code,
        extras.aid,
        extras.duration_ms,
        extras.err_path,
    )
}

pub(super) fn handle_osc_133(core: &mut TerminalCore, params: &[&[u8]]) {
    let Some(mark_raw) = params.get(1) else {
        return;
    };
    let Some(mark) = PromptMark::from_osc_133_mark(*mark_raw.first().unwrap_or(&0)) else {
        return;
    };

    handle_osc_133_mark(core, mark, params);
}

pub(super) fn default_color_slot(osc_num: &[u8]) -> Option<DefaultColorSlot> {
    match osc_num {
        b"10" => Some(DefaultColorSlot::Foreground),
        b"11" => Some(DefaultColorSlot::Background),
        b"12" => Some(DefaultColorSlot::Cursor),
        _ => None,
    }
}

pub(super) fn default_color_osc_num(slot: DefaultColorSlot) -> &'static str {
    match slot {
        DefaultColorSlot::Foreground => "10",
        DefaultColorSlot::Background => "11",
        DefaultColorSlot::Cursor => "12",
    }
}

fn emit_default_color_query(core: &mut TerminalCore, slot: DefaultColorSlot) {
    let rgb = core.osc_data.default_color_rgb(slot);
    let resp = format!(
        "\x1b]{};{}\x07",
        default_color_osc_num(slot),
        encode_color_spec(rgb)
    );
    core.meta.pending_responses.push(resp.into_bytes());
}

fn apply_default_color_update(core: &mut TerminalCore, slot: DefaultColorSlot, spec: &str) {
    let Some([r, g, b]) = parse_color_spec(spec) else {
        return;
    };

    core.osc_data
        .set_default_color(slot, Some(crate::types::Color::Rgb(r, g, b)));
}

pub(super) fn handle_osc_default_colors(core: &mut TerminalCore, params: &[&[u8]]) {
    let Some(spec_raw) = params.get(1) else {
        return;
    };

    let Some(slot) = default_color_slot(params[0]) else {
        return;
    };

    if *spec_raw == b"?" {
        emit_default_color_query(core, slot);
    } else {
        apply_default_color_update(core, slot, std::str::from_utf8(spec_raw).unwrap_or(""));
    }
}
