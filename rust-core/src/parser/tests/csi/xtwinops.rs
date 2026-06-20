use super::tests_support::*;

// Tests for handle_xtwinops (CSI Ps t) and handle_decreqtparm (CSI Ps x).

// ── XTWINOPS: CSI 14 t — pixel size query ────────────────────────────────────

#[test]
fn test_xtwinops_op14_queues_pixel_size_response() {
    let mut term = term!(24, 80);
    term.advance(b"\x1b[14t");
    assert_single_pending_response_bytes(&term, b"\x1b[4;0;0t");
}

// ── XTWINOPS: CSI 18 t — rows×cols query ─────────────────────────────────────

#[test]
fn test_xtwinops_op18_queues_rows_cols_response() {
    let mut term = term!(30, 100);
    term.advance(b"\x1b[18t");
    assert_single_pending_response_text(&term, "\x1b[8;30;100t");
}

// ── XTWINOPS: CSI 19 t — screen size in cells ────────────────────────────────

#[test]
fn test_xtwinops_op19_queues_screen_size_response() {
    let mut term = term!(24, 80);
    term.advance(b"\x1b[19t");
    assert_single_pending_response_text(&term, "\x1b[9;24;80t");
}

// ── XTWINOPS: CSI 22 t — XTPUSHTITLE ────────────────────────────────────────

#[test]
fn test_xtwinops_op22_pushes_title_to_stack() {
    let mut term = term!(24, 80);
    term.meta.title = "my-title".to_owned();
    term.advance(b"\x1b[22t");
    assert_eq!(
        term.meta.title_stack.len(),
        1,
        "CSI 22 t must push one entry onto title_stack"
    );
    assert_eq!(
        term.meta.title_stack[0], "my-title",
        "pushed title must match the current title"
    );
    assert_no_pending_responses(&term);
}

#[test]
fn test_xtwinops_op22_stacks_multiple_titles() {
    let mut term = term!(24, 80);
    term.meta.title = "first".to_owned();
    term.advance(b"\x1b[22t");
    term.meta.title = "second".to_owned();
    term.advance(b"\x1b[22t");
    assert_eq!(term.meta.title_stack.len(), 2);
    assert_eq!(term.meta.title_stack[0], "first");
    assert_eq!(term.meta.title_stack[1], "second");
}

// ── XTWINOPS: CSI 23 t — XTPOPTITLE ─────────────────────────────────────────

#[test]
fn test_xtwinops_op23_pops_title_from_stack() {
    let mut term = term!(24, 80);
    term.meta.title = "saved".to_owned();
    term.advance(b"\x1b[22t"); // push "saved"
    term.meta.title = "changed".to_owned();
    term.advance(b"\x1b[23t"); // pop
    assert_eq!(
        term.meta.title, "saved",
        "CSI 23 t must restore the most recently pushed title"
    );
    assert!(
        term.meta.title_stack.is_empty(),
        "title_stack must be empty after pop"
    );
    assert!(
        term.meta.title_dirty,
        "title_dirty must be set after restore"
    );
}

#[test]
fn test_xtwinops_op23_empty_stack_is_noop() {
    let mut term = term!(24, 80);
    term.meta.title = "original".to_owned();
    term.advance(b"\x1b[23t"); // pop from empty stack — must not panic
    assert_eq!(
        term.meta.title, "original",
        "pop from empty stack must leave title unchanged"
    );
    assert_no_pending_responses(&term);
}

// ── XTWINOPS: unknown op — silent no-op ──────────────────────────────────────

#[test]
fn test_xtwinops_unknown_op_is_noop() {
    let mut term = term!(24, 80);
    term.advance(b"\x1b[99t");
    assert_no_pending_responses(&term);
}

// ── DECREQTPARM: CSI 0 x → sol=2 ────────────────────────────────────────────

#[test]
fn test_decreqtparm_ps0_queues_report_sol2() {
    let mut term = term!(24, 80);
    term.advance(b"\x1b[0x");
    assert_single_pending_response_bytes(&term, b"\x1b[2;1;1;128;128;1;0x");
}

// ── DECREQTPARM: CSI 1 x → sol=3 ────────────────────────────────────────────

#[test]
fn test_decreqtparm_ps1_queues_report_sol3() {
    let mut term = term!(24, 80);
    term.advance(b"\x1b[1x");
    assert_single_pending_response_bytes(&term, b"\x1b[3;1;1;128;128;1;0x");
}

// ── DECREQTPARM: CSI 2 x — unsupported → no response ────────────────────────

#[test]
fn test_decreqtparm_ps2_is_noop() {
    let mut term = term!(24, 80);
    term.advance(b"\x1b[2x");
    assert_no_pending_responses(&term);
}

// ── DECREQTPARM: default (omitted param = 0) ─────────────────────────────────

#[test]
fn test_decreqtparm_default_param_treated_as_0() {
    let mut term = term!(24, 80);
    term.advance(b"\x1b[x"); // no param → defaults to 0
    assert_single_pending_response_bytes(&term, b"\x1b[2;1;1;128;128;1;0x");
}
