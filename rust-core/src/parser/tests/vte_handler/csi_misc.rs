
// ── REP — Repeat Last Printed Character (CSI Ps b) ───────────────────────────
//
// REP repeats the most recently printed character Ps times at the current cursor
// position, using the current SGR attributes.  If no character has been printed
// yet (last_printed_char == None), the sequence is a no-op.
//
// Macros `term_with!` and `assert_cell_char!` are inherited from the parent
// vte_handler.rs test module.

#[test]
fn test_rep_repeats_last_char_at_cursor() {
    // Print 'A', then REP 3: columns 1-3 must also contain 'A'.
    let mut term = crate::TerminalCore::new(5, 20);
    term.advance(b"A");          // prints 'A' at col 0; cursor moves to col 1
    term.advance(b"\x1b[3b");   // REP 3: repeat 'A' three more times
    assert_cell_char!(term, row 0, col 0, 'A');
    assert_cell_char!(term, row 0, col 1, 'A');
    assert_cell_char!(term, row 0, col 2, 'A');
    assert_cell_char!(term, row 0, col 3, 'A');
    // Cursor must have advanced past the repeated characters.
    assert_eq!(term.screen.cursor().col, 4, "cursor must be at col 4 after REP 3");
}

#[test]
fn test_rep_default_param_repeats_once() {
    // REP with omitted Ps defaults to 1.
    let mut term = crate::TerminalCore::new(5, 20);
    term.advance(b"Z");
    term.advance(b"\x1b[b"); // REP 1 (default)
    assert_cell_char!(term, row 0, col 0, 'Z');
    assert_cell_char!(term, row 0, col 1, 'Z');
    assert_eq!(term.screen.cursor().col, 2, "cursor must advance 1 after REP default");
}

#[test]
fn test_rep_zero_param_still_repeats_once() {
    // Ps=0 is clamped to 1 by the .max(1) guard.
    let mut term = crate::TerminalCore::new(5, 20);
    term.advance(b"Q");
    term.advance(b"\x1b[0b"); // REP 0 → clamped to 1
    assert_cell_char!(term, row 0, col 0, 'Q');
    assert_cell_char!(term, row 0, col 1, 'Q');
}

#[test]
fn test_rep_noop_when_no_prior_print() {
    // With no preceding printed character, REP must leave the screen unchanged.
    let mut term = crate::TerminalCore::new(5, 20);
    // Do NOT print anything first; advance sends REP immediately.
    term.advance(b"\x1b[5b"); // REP 5 — last_printed_char is None → no-op
    // Row 0, col 0 must remain the default blank cell.
    assert_cell_char!(term, row 0, col 0, ' ');
    assert_eq!(term.screen.cursor().col, 0, "cursor must not advance when REP is a no-op");
}

#[test]
fn test_rep_uses_current_sgr_attrs() {
    // REP must apply the CURRENT SGR attributes, not those in effect when the
    // original character was printed.
    let mut term = crate::TerminalCore::new(5, 20);
    term.advance(b"\x1b[1m"); // bold on
    term.advance(b"X");        // print 'X' with bold
    term.advance(b"\x1b[0m"); // reset attributes (bold off)
    term.advance(b"\x1b[2b"); // REP 2 — should print 'X' with NO bold (current attrs)
    // 'X' must appear at cols 1 and 2.
    assert_cell_char!(term, row 0, col 1, 'X');
    assert_cell_char!(term, row 0, col 2, 'X');
    // The repeated cells should NOT be bold (current attrs are plain).
    let cell = term.screen.get_cell(0, 1).unwrap();
    assert!(
        !cell.attrs.flags.contains(crate::types::cell::SgrFlags::BOLD),
        "REP must use current (non-bold) SGR attrs, not those at print time"
    );
}

#[test]
fn test_rep_last_char_updates_on_each_print() {
    // After printing two different characters, REP must repeat the LAST one.
    let mut term = crate::TerminalCore::new(5, 20);
    term.advance(b"A"); // last_printed_char = 'A'
    term.advance(b"B"); // last_printed_char = 'B'
    term.advance(b"\x1b[3b"); // REP 3 → 'B' repeated
    assert_cell_char!(term, row 0, col 0, 'A');
    assert_cell_char!(term, row 0, col 1, 'B');
    assert_cell_char!(term, row 0, col 2, 'B');
    assert_cell_char!(term, row 0, col 3, 'B');
    assert_cell_char!(term, row 0, col 4, 'B');
}
