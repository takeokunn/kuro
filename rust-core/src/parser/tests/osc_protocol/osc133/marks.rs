use crate::types::osc::PromptMark;
use crate::TerminalCore;

test_osc_133_mark!(test_handle_osc_133_prompt_start, b"A", PromptStart);
test_osc_133_mark!(test_handle_osc_133_prompt_end, b"B", PromptEnd);
test_osc_133_mark!(test_handle_osc_133_command_start, b"C", CommandStart);
test_osc_133_mark!(test_handle_osc_133_command_end, b"D", CommandEnd);

#[test]
fn test_handle_osc_133_unknown_mark_is_noop() {
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"133", b"Z"];
    super::handle_osc_133(&mut core, params);
    assert!(core.osc_data().prompt_marks.is_empty());
}

#[test]
fn test_handle_osc_133_missing_param_is_noop() {
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"133"];
    super::handle_osc_133(&mut core, params);
    assert!(core.osc_data().prompt_marks.is_empty());
}

#[test]
fn test_handle_osc_133_mark_records_cursor_position() {
    let mut core = TerminalCore::new(24, 80);
    // Move cursor to a known position before emitting the mark.
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

test_osc_133_exit_code!(
    test_handle_osc_133_command_end_exit_code_zero,
    b"0",
    Some(0)
);
test_osc_133_exit_code!(test_handle_osc_133_command_end_exit_code_one, b"1", Some(1));
test_osc_133_exit_code!(
    test_handle_osc_133_command_end_exit_code_127,
    b"127",
    Some(127)
);
test_osc_133_exit_code!(
    test_handle_osc_133_command_end_exit_code_negative,
    b"-1",
    Some(-1)
);
test_osc_133_exit_code!(
    test_handle_osc_133_command_end_exit_code_non_numeric_is_none,
    b"abc",
    None
);

#[test]
fn test_handle_osc_133_command_end_no_exit_code_param() {
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
    let mut core = TerminalCore::new(24, 80);
    // Even if a third param is provided, non-D marks should have exit_code: None.
    let params: &[&[u8]] = &[b"133", b"A", b"0"];
    super::handle_osc_133(&mut core, params);
    assert_eq!(core.osc_data().prompt_marks.len(), 1);
    let ev = &core.osc_data().prompt_marks[0];
    assert_eq!(ev.mark, PromptMark::PromptStart);
    assert_eq!(ev.exit_code, None);
}
