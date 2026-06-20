use super::{encode_color_spec, parse_color_spec};
use crate::parser::limits::{
    MAX_PENDING_PROMPT_MARKS, MAX_PROMPT_DURATION_MS, OSC133_MAX_AID_BYTES,
    OSC133_MAX_ERR_PATH_BYTES, OSC51_MAX_EVAL_BYTES,
};
use crate::types::osc::{
    ClipboardAction, DefaultColorSlot, Notification, NotificationChunk, PromptMark, PromptMarkEvent,
    SelectionTarget,
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

fn push_osc_52_clipboard_write(
    core: &mut TerminalCore,
    target: SelectionTarget,
    data_raw: &[u8],
) {
    if data_raw.len() > 1_048_576 {
        return;
    }

    if let Ok(decoded) = crate::util::base64::decode(data_raw) {
        if let Ok(text) = String::from_utf8(decoded) {
            core.osc_data
                .clipboard_actions
                .push(ClipboardAction::Write { target, data: text });
        }
    }
}

pub(super) fn handle_osc_52(core: &mut TerminalCore, params: &[&[u8]]) {
    let Some(data_raw) = params.get(2) else {
        return;
    };

    // Wire format: OSC 52 ; Pc ; Pd ST. The `Pc` selector defaults to clipboard
    // when empty or absent.
    let target = SelectionTarget::from_selector(params.get(1).copied().unwrap_or(b""));

    if data_raw == b"?" {
        core.osc_data
            .clipboard_actions
            .push(ClipboardAction::Query { target });
        return;
    }

    // 1MB cap.
    push_osc_52_clipboard_write(core, target, data_raw);
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
            id: None,
            report: false,
        })
    } else {
        Some(Notification {
            title: None,
            body: String::from_utf8_lossy(body_raw).into_owned(),
            id: None,
            report: false,
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

/// Which target the OSC 99 `p=` payload type writes into.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Osc99PayloadType {
    Title,
    Body,
    /// `p=close`, `p=icon`, `p=?` — recognised but not surfaced as text.
    Other,
}

/// Parsed OSC 99 metadata (colon-separated `key=value` pairs).
struct Osc99Metadata {
    /// `i=<id>` notification group id (empty when absent).
    id: String,
    /// `d=` done flag; default `true` (single-shot). `d=0` means more chunks follow.
    done: bool,
    /// `p=` payload type. Defaults to [`Osc99PayloadType::Body`] so the minimal
    /// form `OSC 99 ; ; text` yields a notification with `body = text` and no
    /// title (matching this terminal's notification contract). An explicit
    /// `p=title` sets the title instead.
    payload_type: Osc99PayloadType,
    /// `e=` encoding flag; `true` means the payload is base64.
    encoded: bool,
    /// `a=<actions>` requested the activation `report` action. The action list
    /// is comma-separated (`focus`, `report`); a leading `-` removes a default.
    /// We only track `report` since `focus` has no round-trip back to the app.
    report: bool,
    // Note: `u=<urgency>` is recognised but ignored.
}

impl Default for Osc99Metadata {
    fn default() -> Self {
        Self {
            id: String::new(),
            done: true,
            payload_type: Osc99PayloadType::Body,
            encoded: false,
            report: false,
        }
    }
}

/// Parse the OSC 99 `a=<actions>` comma-separated list, returning whether the
/// `report` action ends up enabled. Each entry may be prefixed with `-` to
/// remove a (default) action; `report` is not a default, so only an explicit
/// `report` (not `-report`) enables it.
fn parse_osc99_actions(value: &str) -> bool {
    let mut report = false;
    for action in value.split(',') {
        match action.strip_prefix('-') {
            Some("report") => report = false,
            Some(_) => {} // remove some other (e.g. default) action
            None => {
                if action == "report" {
                    report = true;
                }
            }
        }
    }
    report
}

/// Parse the colon-separated OSC 99 metadata field into a [`Osc99Metadata`].
///
/// Unknown keys and malformed pairs are ignored gracefully; a missing key keeps
/// its documented default. `a=<actions>` enables the `report` round-trip;
/// `u=<urgency>` is recognised but ignored.
fn parse_osc99_metadata(meta_raw: &[u8]) -> Osc99Metadata {
    let mut meta = Osc99Metadata::default();
    let Ok(meta_str) = std::str::from_utf8(meta_raw) else {
        return meta;
    };

    for pair in meta_str.split(':') {
        let Some((key, value)) = pair.split_once('=') else {
            continue; // malformed pair (no '='): ignore
        };
        match key {
            "i" => meta.id = value.to_owned(),
            "d" => meta.done = value != "0",
            "e" => meta.encoded = value == "1",
            "p" => {
                meta.payload_type = match value {
                    "body" => Osc99PayloadType::Body,
                    "title" => Osc99PayloadType::Title,
                    _ => Osc99PayloadType::Other, // close|icon|?|unknown
                };
            }
            "a" => meta.report = parse_osc99_actions(value),
            // u=<urgency>: ignored.
            _ => {}
        }
    }
    meta
}

/// Decode the OSC 99 payload into a lossy-UTF8 string, base64-decoding first when
/// `e=1`. Returns `None` when base64 decoding fails.
fn decode_osc99_payload(payload_raw: &[u8], encoded: bool) -> Option<String> {
    if encoded {
        let decoded = crate::util::base64::decode(payload_raw).ok()?;
        Some(String::from_utf8_lossy(&decoded).into_owned())
    } else {
        Some(String::from_utf8_lossy(payload_raw).into_owned())
    }
}

/// Append `text` to `dst`, capping the accumulated length at
/// [`NOTIFICATION_MAX_BYTES`]. Excess bytes are truncated on a char boundary.
fn append_capped(dst: &mut String, text: &str) {
    let remaining = crate::parser::limits::NOTIFICATION_MAX_BYTES.saturating_sub(dst.len());
    if remaining == 0 {
        return;
    }
    if text.len() <= remaining {
        dst.push_str(text);
    } else {
        let mut end = remaining;
        while end > 0 && !text.is_char_boundary(end) {
            end -= 1;
        }
        dst.push_str(&text[..end]);
    }
}

/// Finalize an accumulated [`NotificationChunk`], pushing a [`Notification`] when
/// it carries any body or title text.
fn finalize_notification_chunk(core: &mut TerminalCore, chunk: NotificationChunk) {
    if chunk.body.is_empty() && chunk.title.is_empty() {
        return;
    }
    core.osc_data.notifications.push(Notification {
        title: (!chunk.title.is_empty()).then_some(chunk.title),
        body: chunk.body,
        id: (!chunk.id.is_empty()).then_some(chunk.id),
        report: chunk.report,
    });
}

/// Handle OSC 99 — Kitty desktop notifications.
///
/// Wire format: `OSC 99 ; metadata ; payload ST` where `metadata` is a
/// colon-separated list of `key=value` pairs (`i`, `d`, `p`, `e`, `a`, `u`).
/// The minimal form `OSC 99 ; ; Hello world` yields a notification with body
/// text "Hello world" and no title.
///
/// Chunking: chunks sharing the same `i=<id>` with `d=0` accumulate; the
/// notification is pushed on `d=1` (or immediately when no `i=` is present, i.e.
/// a single-shot sequence). `e=1` payloads are base64-decoded. Accumulated text
/// is capped at [`NOTIFICATION_MAX_BYTES`].
///
/// `a=<actions>` is parsed but NOT yet wired to any action dispatch.
pub(super) fn handle_osc_99(core: &mut TerminalCore, params: &[&[u8]]) {
    let meta_raw: &[u8] = params.get(1).copied().unwrap_or(b"");
    let meta = parse_osc99_metadata(meta_raw);

    // The VTE parser splits OSC on ';'; rejoin any payload that itself contained
    // ';' so semicolons in the notification text are preserved.
    let payload: Vec<u8> = if params.len() <= 3 {
        params.get(2).copied().unwrap_or(b"").to_vec()
    } else {
        params[2..].join(&b';')
    };

    let Some(text) = decode_osc99_payload(&payload, meta.encoded) else {
        return; // malformed base64: ignore gracefully
    };

    // Take any in-progress chunk that matches this id; otherwise start fresh.
    let mut chunk = match core.osc_data.notification_chunk.take() {
        Some(existing) if existing.id == meta.id && !meta.id.is_empty() => existing,
        Some(orphan) => {
            // A different in-progress notification is abandoned by a new id;
            // finalize it so its accumulated text is not lost.
            finalize_notification_chunk(core, orphan);
            NotificationChunk {
                id: meta.id.clone(),
                ..NotificationChunk::default()
            }
        }
        None => NotificationChunk {
            id: meta.id.clone(),
            ..NotificationChunk::default()
        },
    };

    // Any chunk requesting the report action enables it for the notification.
    chunk.report |= meta.report;

    match meta.payload_type {
        Osc99PayloadType::Title => append_capped(&mut chunk.title, &text),
        Osc99PayloadType::Body => append_capped(&mut chunk.body, &text),
        Osc99PayloadType::Other => {} // close/icon/?: no text accumulation
    }

    // Single-shot (no id) or explicit completion (d=1) finalizes immediately.
    if meta.done || meta.id.is_empty() {
        finalize_notification_chunk(core, chunk);
    } else {
        core.osc_data.notification_chunk = Some(chunk);
    }
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
