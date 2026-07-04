use super::*;

// ---------------------------------------------------------------------------
// take_prompt_marks: drain-once semantics
// ---------------------------------------------------------------------------

/// `take_prompt_marks` returns empty on a fresh session.
#[test]
fn test_take_prompt_marks_empty_initially() {
    let mut session = make_session();
    assert!(
        session.take_prompt_marks().is_empty(),
        "take_prompt_marks must return empty vec on a fresh session"
    );
}

/// `take_prompt_marks` returns an event after OSC 133 and drains the queue.
#[test]
fn test_take_prompt_marks_drains_after_osc133() {
    let mut session = make_session();
    session.core.advance(b"\x1b]133;A\x1b\\");
    assert_drain_once!(session, take_prompt_marks, vec);
}

/// `aid=""` round-trips as `Some(String::new())`, not `None`.
#[test]
fn test_take_prompt_marks_aid_empty_string_preserved() {
    let ev = tests_support::take_single_prompt_mark(b"\x1b]133;D;0;aid=\x1b\\");
    assert_eq!(
        ev.aid.as_deref(),
        Some(""),
        "aid=\"\" must survive as Some(empty), never collapse to None"
    );
}

/// Missing extras stay `None`.
#[test]
fn test_take_prompt_marks_no_extras_all_none() {
    let ev = tests_support::take_single_prompt_mark(b"\x1b]133;D;0\x1b\\");
    assert!(ev.aid.is_none(), "aid must be None when no aid= kv is sent");
    assert!(
        ev.duration_ms.is_none(),
        "duration_ms must be None when no duration= kv is sent"
    );
    assert!(
        ev.err_path.is_none(),
        "err_path must be None when no err= kv is sent"
    );
}

/// Present extras stay `Some`.
#[test]
fn test_take_prompt_marks_all_extras_some() {
    let ev = tests_support::take_single_prompt_mark(
        b"\x1b]133;D;0;aid=app1;duration=1234;err=/var/log/x.log\x1b\\",
    );
    assert_eq!(ev.aid.as_deref(), Some("app1"));
    assert_eq!(ev.duration_ms, Some(1234));
    assert_eq!(ev.err_path.as_deref(), Some("/var/log/x.log"));
    assert_eq!(ev.exit_code, Some(0));
}

/// `duration_ms = u64::MAX` is rejected by the parser.
#[test]
fn test_take_prompt_marks_duration_u64_max_rejected() {
    let ev =
        tests_support::take_single_prompt_mark(b"\x1b]133;D;0;duration=18446744073709551615\x1b\\");
    assert_eq!(
        ev.duration_ms, None,
        "u64::MAX exceeds MAX_PROMPT_DURATION_MS (1 year); parser must drop to None"
    );
}

/// `duration_ms` exactly at the cap is accepted.
#[test]
fn test_take_prompt_marks_duration_at_cap_accepted() {
    let payload =
        tests_support::build_osc133_d(0, None, Some(tests_support::MAX_PROMPT_DURATION_MS), None);
    let ev = tests_support::take_single_prompt_mark(&payload);
    assert_eq!(
        ev.duration_ms,
        Some(tests_support::MAX_PROMPT_DURATION_MS),
        "duration_ms exactly at cap must round-trip"
    );
}

/// `duration_ms` one above the cap is rejected.
#[test]
fn test_take_prompt_marks_duration_above_cap_rejected() {
    let ev = tests_support::take_single_prompt_mark(&tests_support::build_osc133_d(
        0,
        None,
        Some(tests_support::MAX_PROMPT_DURATION_MS + 1),
        None,
    ));
    assert_eq!(
        ev.duration_ms, None,
        "duration_ms one above MAX_PROMPT_DURATION_MS must drop to None"
    );
}

/// Legacy consumers reading only the first four fields keep working.
#[test]
fn test_take_prompt_marks_legacy_4field_consumer_unaffected() {
    let ev = tests_support::take_single_prompt_mark(
        b"\x1b]133;D;42;aid=app1;duration=999;err=/tmp/e\x1b\\",
    );

    // A "legacy" consumer destructures only the first 4 logical fields.
    // It must succeed without referencing aid/duration_ms/err_path.
    let legacy_view: (crate::types::osc::PromptMark, usize, usize, Option<i32>) =
        (ev.mark.clone(), ev.row, ev.col, ev.exit_code);

    assert!(matches!(
        legacy_view.0,
        crate::types::osc::PromptMark::CommandEnd
    ));
    assert_eq!(
        legacy_view.1, 0,
        "row must reflect cursor at OSC 133 D time"
    );
    assert_eq!(
        legacy_view.2, 0,
        "col must reflect cursor at OSC 133 D time"
    );
    assert_eq!(
        legacy_view.3,
        Some(42),
        "exit-code positional param survives"
    );
}
