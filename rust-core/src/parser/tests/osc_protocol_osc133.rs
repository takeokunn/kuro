// ── osc_protocol_osc133.rs — included into parser::tests::osc_protocol ───────
//
// All OSC 133 shell-integration tests live here:
//   - Prompt-mark letter dispatch (A/B/C/D)
//   - Exit-code positional parsing (D mark only)
//   - Ghostty/FinalTerm kv extras (aid, duration, err)
//   - Length-limit and control-char sanitisation edge cases (FR-119)
//
// Shared macros (`test_osc_133_mark!`, `make_core!`) are defined in the parent
// `osc_protocol.rs` / `osc_protocol_colors.rs` and are in scope via `include!`.

// ── handle_osc_133 ────────────────────────────────────────────────────────────

test_osc_133_mark!(test_handle_osc_133_prompt_start, b"A", PromptStart);
test_osc_133_mark!(test_handle_osc_133_prompt_end, b"B", PromptEnd);
test_osc_133_mark!(test_handle_osc_133_command_start, b"C", CommandStart);
test_osc_133_mark!(test_handle_osc_133_command_end, b"D", CommandEnd);

#[test]
fn test_handle_osc_133_unknown_mark_is_noop() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"133", b"Z"];
    super::handle_osc_133(&mut core, params);
    assert!(core.osc_data().prompt_marks.is_empty());
}

#[test]
fn test_handle_osc_133_missing_param_is_noop() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"133"];
    super::handle_osc_133(&mut core, params);
    assert!(core.osc_data().prompt_marks.is_empty());
}

#[test]
fn test_handle_osc_133_mark_records_cursor_position() {
    use crate::types::osc::PromptMark;
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    // Move cursor to a known position before emitting the mark
    core.advance(b"\x1b[5;10H"); // row 5, col 10 (1-based → 4, 9 zero-based)
    let params: &[&[u8]] = &[b"133", b"A"];
    super::handle_osc_133(&mut core, params);
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(ev.mark, PromptMark::PromptStart);
    // cursor row/col must be captured at call time
    assert_eq!(ev.row, 4);
    assert_eq!(ev.col, 9);
}

// ── handle_osc_133 exit_code ─────────────────────────────────────────────────

#[test]
fn test_handle_osc_133_command_end_exit_code_zero() {
    use crate::types::osc::PromptMark;
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"133", b"D", b"0"];
    super::handle_osc_133(&mut core, params);
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(ev.mark, PromptMark::CommandEnd);
    assert_eq!(ev.exit_code, Some(0));
}

#[test]
fn test_handle_osc_133_command_end_exit_code_one() {
    use crate::types::osc::PromptMark;
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"133", b"D", b"1"];
    super::handle_osc_133(&mut core, params);
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(ev.mark, PromptMark::CommandEnd);
    assert_eq!(ev.exit_code, Some(1));
}

#[test]
fn test_handle_osc_133_command_end_exit_code_127() {
    use crate::types::osc::PromptMark;
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"133", b"D", b"127"];
    super::handle_osc_133(&mut core, params);
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(ev.mark, PromptMark::CommandEnd);
    assert_eq!(ev.exit_code, Some(127));
}

#[test]
fn test_handle_osc_133_command_end_exit_code_negative() {
    use crate::types::osc::PromptMark;
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"133", b"D", b"-1"];
    super::handle_osc_133(&mut core, params);
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(ev.mark, PromptMark::CommandEnd);
    assert_eq!(ev.exit_code, Some(-1));
}

#[test]
fn test_handle_osc_133_command_end_exit_code_non_numeric_is_none() {
    use crate::types::osc::PromptMark;
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"133", b"D", b"abc"];
    super::handle_osc_133(&mut core, params);
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(ev.mark, PromptMark::CommandEnd);
    assert_eq!(ev.exit_code, None);
}

#[test]
fn test_handle_osc_133_command_end_no_exit_code_param() {
    use crate::types::osc::PromptMark;
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"133", b"D"];
    super::handle_osc_133(&mut core, params);
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(ev.mark, PromptMark::CommandEnd);
    assert_eq!(ev.exit_code, None);
}

#[test]
fn test_handle_osc_133_prompt_start_exit_code_always_none() {
    use crate::types::osc::PromptMark;
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    // Even if a third param is provided, non-D marks should have exit_code: None
    let params: &[&[u8]] = &[b"133", b"A", b"0"];
    super::handle_osc_133(&mut core, params);
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(ev.mark, PromptMark::PromptStart);
    assert_eq!(ev.exit_code, None);
}

// ── handle_osc_133 Ghostty/FinalTerm kv extras (aid, duration, err) ──────────

#[test]
fn osc_133_a_with_aid_captured() {
    use crate::types::osc::PromptMark;
    use crate::TerminalCore;
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
    use crate::types::osc::PromptMark;
    use crate::TerminalCore;
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
    use crate::types::osc::PromptMark;
    use crate::TerminalCore;
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
    use crate::types::osc::PromptMark;
    use crate::TerminalCore;
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
    use crate::types::osc::PromptMark;
    use crate::TerminalCore;
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
    use crate::types::osc::PromptMark;
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]133;D;0;duration=notanumber\x07");
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(ev.mark, PromptMark::CommandEnd);
    assert_eq!(ev.exit_code, Some(0));
    assert!(ev.duration_ms.is_none());
}

// ── handle_osc_133 FR-119 edge cases (additional coverage) ───────────────────

/// D mark with `aid=` parameter — verifies kv extras are parsed alongside the
/// positional exit code.
#[test]
fn osc_133_d_with_aid_and_exit_code() {
    use crate::types::osc::PromptMark;
    use crate::TerminalCore;
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
    use crate::types::osc::PromptMark;
    use crate::TerminalCore;
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
    use crate::TerminalCore;
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
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]133;A;aid=first;aid=second\x07");
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(ev.aid.as_deref(), Some("second"), "last aid= wins");
}

/// Oversized `aid=` (> `OSC133_MAX_AID_BYTES` = 256) — silently dropped.
#[test]
fn osc_133_oversized_aid_rejected() {
    use crate::parser::limits::OSC133_MAX_AID_BYTES;
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let big_aid: Vec<u8> = vec![b'x'; OSC133_MAX_AID_BYTES + 1];
    let mut seq = b"\x1b]133;A;aid=".to_vec();
    seq.extend_from_slice(&big_aid);
    seq.extend_from_slice(b"\x07");
    core.advance(&seq);
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert!(
        ev.aid.is_none(),
        "aid= longer than OSC133_MAX_AID_BYTES must be silently dropped"
    );
}

/// Oversized `err=` (> `OSC133_MAX_ERR_PATH_BYTES` = 4096) — silently dropped.
#[test]
fn osc_133_oversized_err_path_rejected() {
    use crate::parser::limits::OSC133_MAX_ERR_PATH_BYTES;
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let big_err: Vec<u8> = vec![b'x'; OSC133_MAX_ERR_PATH_BYTES + 1];
    let mut seq = b"\x1b]133;D;0;err=".to_vec();
    seq.extend_from_slice(&big_err);
    seq.extend_from_slice(b"\x07");
    core.advance(&seq);
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert!(
        ev.err_path.is_none(),
        "err= longer than OSC133_MAX_ERR_PATH_BYTES must be silently dropped"
    );
    // exit_code is still accepted — only the oversized field is rejected.
    assert_eq!(ev.exit_code, Some(0));
}

/// `aid=` containing a C0 control byte (0x01) — sanitised to `None`.
///
/// Bypasses the VTE state machine (which would itself abort an OSC on a C0
/// byte) by calling `handle_osc_133` directly, so this test verifies the
/// parser-level `has_control_bytes` guard specifically.
#[test]
fn osc_133_aid_with_control_char_rejected() {
    use crate::TerminalCore;
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
    use crate::TerminalCore;
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

/// `aid=` exactly at the limit (`OSC133_MAX_AID_BYTES` bytes) is accepted —
/// boundary check.
#[test]
fn osc_133_aid_at_limit_accepted() {
    use crate::parser::limits::OSC133_MAX_AID_BYTES;
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let exact: Vec<u8> = vec![b'a'; OSC133_MAX_AID_BYTES];
    let mut seq = b"\x1b]133;A;aid=".to_vec();
    seq.extend_from_slice(&exact);
    seq.extend_from_slice(b"\x07");
    core.advance(&seq);
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(
        ev.aid.as_ref().map(String::len),
        Some(OSC133_MAX_AID_BYTES),
        "aid= at exactly the limit must be retained"
    );
}

// ── MAX_PENDING_PROMPT_MARKS cap (DoS prevention) ────────────────────────────

/// C4 (V#?): pushing more than `MAX_PENDING_PROMPT_MARKS` prompt-A marks must
/// stop accumulation at the cap. Excess marks are silently dropped — the cap
/// prevents a runaway shell from OOM-ing the host Emacs by emitting marks
/// faster than Elisp drains them.
#[test]
fn test_handle_osc_133_caps_at_max_pending_prompt_marks() {
    use crate::parser::limits::MAX_PENDING_PROMPT_MARKS;
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"133", b"A"];
    // Push 300 > MAX_PENDING_PROMPT_MARKS (256). Loop body invokes
    // handle_osc_133 directly so the test bypasses the VTE state machine
    // and isolates the cap enforcement in handle_osc_133 itself.
    for _ in 0..300 {
        super::handle_osc_133(&mut core, params);
    }
    assert_eq!(
        core.osc_data().prompt_marks.len(),
        MAX_PENDING_PROMPT_MARKS,
        "prompt_marks must saturate at MAX_PENDING_PROMPT_MARKS ({MAX_PENDING_PROMPT_MARKS})"
    );
}
