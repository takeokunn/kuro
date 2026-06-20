use crate::TerminalCore;

#[test]
fn osc_133_oversized_aid_rejected() {
    use crate::parser::limits::OSC133_MAX_AID_BYTES;

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

#[test]
fn osc_133_oversized_err_path_rejected() {
    use crate::parser::limits::OSC133_MAX_ERR_PATH_BYTES;

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
    assert_eq!(ev.exit_code, Some(0));
}

#[test]
fn osc_133_aid_at_limit_accepted() {
    use crate::parser::limits::OSC133_MAX_AID_BYTES;

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

#[test]
fn osc_133_invalid_utf8_extra_is_skipped() {
    let mut core = TerminalCore::new(24, 80);
    // params: ["133", "A", <0xFF — invalid UTF-8>, "aid=goodid"]
    let bad: &[u8] = &[0xFF];
    let params: &[&[u8]] = &[b"133", b"A", bad, b"aid=goodid"];
    super::handle_osc_133(&mut core, params);
    assert_eq!(
        core.osc_data().prompt_marks.len(),
        1,
        "mark must still be pushed"
    );
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(
        ev.aid.as_deref(),
        Some("goodid"),
        "aid= after the invalid-UTF8 param must still be captured"
    );
}

#[test]
fn test_handle_osc_133_caps_at_max_pending_prompt_marks() {
    use crate::parser::limits::MAX_PENDING_PROMPT_MARKS;

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
