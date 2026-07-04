use crate::types::osc::PromptMark;
use crate::TerminalCore;

#[test]
fn osc_133_a_with_aid_captured() {
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]133;A;aid=p-42\x07");
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(ev.mark, PromptMark::PromptStart);
    assert_eq!(ev.aid.as_deref(), Some("p-42"));
    assert!(ev.exit_code.is_none());
    assert!(ev.duration_ms.is_none());
    assert!(ev.err_path.is_none());
}

#[test]
fn osc_133_d_full_extras() {
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]133;D;0;aid=p-42;duration=1234;err=/tmp/e.log\x07");
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(ev.mark, PromptMark::CommandEnd);
    assert_eq!(ev.exit_code, Some(0));
    assert_eq!(ev.aid.as_deref(), Some("p-42"));
    assert_eq!(ev.duration_ms, Some(1234));
    assert_eq!(ev.err_path.as_deref(), Some("/tmp/e.log"));
}

#[test]
fn osc_133_d_nonzero_exit_with_aid() {
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]133;D;127;aid=p-43\x07");
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(ev.mark, PromptMark::CommandEnd);
    assert_eq!(ev.exit_code, Some(127));
    assert_eq!(ev.aid.as_deref(), Some("p-43"));
    assert!(ev.duration_ms.is_none());
    assert!(ev.err_path.is_none());
}

#[test]
fn osc_133_c_no_extras() {
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]133;C\x07");
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(ev.mark, PromptMark::CommandStart);
    assert!(ev.exit_code.is_none());
    assert!(ev.aid.is_none());
    assert!(ev.duration_ms.is_none());
    assert!(ev.err_path.is_none());
}

#[test]
fn osc_133_unknown_kv_ignored() {
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]133;A;bogus=xyz\x07");
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(ev.mark, PromptMark::PromptStart);
    assert!(ev.aid.is_none());
    assert!(ev.duration_ms.is_none());
    assert!(ev.err_path.is_none());
    assert!(ev.exit_code.is_none());
}

#[test]
fn osc_133_malformed_duration_ignored() {
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]133;D;0;duration=notanumber\x07");
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(ev.mark, PromptMark::CommandEnd);
    assert_eq!(ev.exit_code, Some(0));
    assert!(ev.duration_ms.is_none());
}

/// D mark with `aid=` parameter — verifies kv extras are parsed alongside the
/// positional exit code.
#[test]
fn osc_133_d_with_aid_and_exit_code() {
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]133;D;0;aid=job1\x07");
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(ev.mark, PromptMark::CommandEnd);
    assert_eq!(ev.exit_code, Some(0));
    assert_eq!(ev.aid.as_deref(), Some("job1"));
}

/// B mark with `aid=` — B has no positional exit code, but kv extras should
/// still land.
#[test]
fn osc_133_b_with_aid_captured() {
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]133;B;aid=job1\x07");
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(ev.mark, PromptMark::PromptEnd);
    assert!(ev.exit_code.is_none(), "B mark never carries an exit code");
    assert_eq!(ev.aid.as_deref(), Some("job1"));
}

/// Empty `aid=` value — current impl stores an empty string (no separate
/// "missing" vs "empty" distinction at the parser layer).
#[test]
fn osc_133_empty_aid_yields_empty_string() {
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]133;A;aid=\x07");
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(
        ev.aid.as_deref(),
        Some(""),
        "empty kv value is stored verbatim as Some(\"\")"
    );
}

/// Duplicate `aid=` keys — last-wins precedence (each kv param is processed
/// sequentially and later assignments overwrite earlier ones).
#[test]
fn osc_133_duplicate_aid_last_wins() {
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]133;A;aid=first;aid=second\x07");
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(ev.aid.as_deref(), Some("second"), "last aid= wins");
}

/// `aid=` containing a C0 control byte (0x01) — sanitised to `None`.
///
/// Bypasses the VTE state machine (which would itself abort an OSC on a C0
/// byte) by calling `handle_osc_133` directly, so this test verifies the
/// parser-level `has_control_bytes` guard specifically.
#[test]
fn osc_133_aid_with_control_char_rejected() {
    let mut core = TerminalCore::new(24, 80);
    let bad_kv: &[u8] = b"aid=foo\x01bar";
    let params: &[&[u8]] = &[b"133", b"A", bad_kv];
    super::handle_osc_133(&mut core, params);
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert!(
        ev.aid.is_none(),
        "aid= containing a C0 control byte must be silently dropped"
    );
}

/// `err=` containing a DEL byte (0x7F) — sanitised to `None`.
///
/// Calls `handle_osc_133` directly to exercise the parser-level guard.
#[test]
fn osc_133_err_with_del_byte_rejected() {
    let mut core = TerminalCore::new(24, 80);
    let bad_kv: &[u8] = b"err=/tmp/\x7flog";
    let params: &[&[u8]] = &[b"133", b"D", b"0", bad_kv];
    super::handle_osc_133(&mut core, params);
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert!(
        ev.err_path.is_none(),
        "err= containing DEL (0x7F) must be silently dropped"
    );
    assert_eq!(ev.exit_code, Some(0));
}
