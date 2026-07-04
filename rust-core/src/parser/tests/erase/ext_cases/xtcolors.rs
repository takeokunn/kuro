#[test]
fn xtpushcolors_saves_palette_and_xtpopcolors_restores_it() {
    let mut term = crate::TerminalCore::new(5, 10);
    // Set palette index 1 via OSC 4
    term.advance(b"\x1b]4;1;rgb:ff/00/00\x07");
    assert_eq!(term.osc_data.palette[1], Some([0xff, 0x00, 0x00]));

    // Push palette
    term.advance(b"\x1b[#P");
    assert_eq!(term.osc_data.palette_stack.len(), 1);

    // Change palette entry 1
    term.advance(b"\x1b]4;1;rgb:00/ff/00\x07");
    assert_eq!(term.osc_data.palette[1], Some([0x00, 0xff, 0x00]));

    // Pop restores original
    term.advance(b"\x1b[#Q");
    assert_eq!(term.osc_data.palette_stack.len(), 0);
    assert_eq!(term.osc_data.palette[1], Some([0xff, 0x00, 0x00]));
    assert!(term.osc_data.palette_dirty);
}

#[test]
fn xtreportcolors_reports_stack_depth() {
    let mut term = crate::TerminalCore::new(5, 10);
    // Initially depth 0
    term.advance(b"\x1b[#R");
    assert_eq!(term.meta.pending_responses.last().unwrap(), b"\x1b[0#S");

    // Push once
    term.advance(b"\x1b[#P");
    term.advance(b"\x1b[#R");
    assert_eq!(term.meta.pending_responses.last().unwrap(), b"\x1b[1#S");
}

#[test]
fn xtpushcolors_capped_at_10() {
    let mut term = crate::TerminalCore::new(5, 10);
    for _ in 0..15 {
        term.advance(b"\x1b[#P");
    }
    assert_eq!(
        term.osc_data.palette_stack.len(),
        10,
        "palette stack must be capped at 10"
    );
}

#[test]
fn xtpopcolors_on_empty_stack_is_noop() {
    // XTPOPCOLORS (CSI # Q) on an empty stack must be a no-op: no panic,
    // palette unchanged, palette_dirty stays false.
    let mut term = crate::TerminalCore::new(5, 10);
    // Set a known palette entry so we can confirm it is unchanged.
    term.advance(b"\x1b]4;7;rgb:aa/bb/cc\x07");
    assert_eq!(term.osc_data.palette[7], Some([0xaa, 0xbb, 0xcc]));
    assert!(term.osc_data.palette_stack.is_empty());
    // Pop on empty stack — must not panic and palette must survive.
    term.advance(b"\x1b[#Q");
    assert_eq!(
        term.osc_data.palette[7],
        Some([0xaa, 0xbb, 0xcc]),
        "palette must be unchanged after XTPOPCOLORS on empty stack"
    );
}
