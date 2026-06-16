use super::make_session;

pub(crate) const MAX_PROMPT_DURATION_MS: u64 = 365 * 24 * 3600 * 1000;

/// Build an OSC 133 `D` sequence with the requested optional extras.
pub(crate) fn build_osc133_d(
    exit_code: i32,
    aid: Option<&str>,
    duration: Option<u64>,
    err: Option<&str>,
) -> Vec<u8> {
    let mut out = Vec::with_capacity(64);
    out.extend_from_slice(b"\x1b]133;D;");
    out.extend_from_slice(exit_code.to_string().as_bytes());
    if let Some(a) = aid {
        out.extend_from_slice(b";aid=");
        out.extend_from_slice(a.as_bytes());
    }
    if let Some(d) = duration {
        out.extend_from_slice(b";duration=");
        out.extend_from_slice(d.to_string().as_bytes());
    }
    if let Some(e) = err {
        out.extend_from_slice(b";err=");
        out.extend_from_slice(e.as_bytes());
    }
    out.extend_from_slice(b"\x1b\\");
    out
}

/// Feed one payload into a fresh session and return the single drained prompt mark.
pub(crate) fn take_single_prompt_mark(payload: &[u8]) -> crate::types::osc::PromptMarkEvent {
    let mut session = make_session();
    session.core.advance(payload);
    let marks = session.take_prompt_marks();
    assert_eq!(marks.len(), 1, "expected exactly one drained mark");
    marks
        .into_iter()
        .next()
        .expect("prompt mark payload must drain exactly one event")
}
