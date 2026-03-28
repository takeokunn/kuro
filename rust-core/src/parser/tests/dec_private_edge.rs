// ── New edge-case tests ───────────────────────────────────────────────────────

#[test]
fn test_decom_cursor_moves_to_scroll_region_top_on_set() {
    // Setting DECOM (?6) must move the cursor to the top of the scroll region,
    // not just flip the origin_mode bit.
    let mut term = crate::TerminalCore::new(24, 80);
    // Set a scroll region (rows 3–20, 0-indexed) via DECSTBM
    term.advance(b"\x1b[4;20r"); // CSI 4 ; 20 r — sets scroll region rows 3..19
                                 // Move cursor away first
    term.advance(b"\x1b[10;5H");
    // Enable DECOM — must move cursor to scroll-region top (row 3)
    term.advance(b"\x1b[?6h");
    assert_eq!(
        term.screen.cursor().col,
        0,
        "DECOM set must reset cursor col to 0"
    );
    let top = term.screen.get_scroll_region().top;
    assert_eq!(
        term.screen.cursor().row,
        top,
        "DECOM set must move cursor to scroll-region top"
    );
}

#[test]
fn test_decom_cursor_moves_to_absolute_home_on_reset() {
    // Resetting DECOM (?6) must move cursor to absolute (0,0).
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?6h"); // enable DECOM
    term.advance(b"\x1b[5;5H"); // move cursor somewhere
    term.advance(b"\x1b[?6l"); // disable DECOM — cursor must go to (0,0)
    assert_eq!(
        term.screen.cursor().row,
        0,
        "DECOM reset must move cursor to row 0"
    );
    assert_eq!(
        term.screen.cursor().col,
        0,
        "DECOM reset must move cursor to col 0"
    );
}

#[test]
fn test_alt_screen_double_exit_is_noop() {
    // Exiting the alternate screen when already on primary must not panic or
    // corrupt state.  The guard `1049 if term.dec_modes.alternate_screen` in
    // `apply_mode_reset` prevents the switch from firing twice.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?1049h"); // enter alt screen
    term.advance(b"\x1b[?1049l"); // exit alt screen
    term.advance(b"\x1b[?1049l"); // exit again — must be a no-op
    assert!(
        !term.dec_modes.alternate_screen,
        "alternate_screen must be false after double exit"
    );
}

#[test]
fn test_sync_output_reset_marks_all_dirty() {
    // Resetting synchronized output (?2026) must call mark_all_dirty().
    // We cannot observe the dirty bits directly in this test, but we can
    // verify the round-trip doesn't panic and the flag is cleared.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2026h"); // enable sync output
    assert!(term.dec_modes.synchronized_output);
    term.advance(b"\x1b[?2026l"); // disable — must call mark_all_dirty()
    assert!(
        !term.dec_modes.synchronized_output,
        "synchronized_output must be cleared"
    );
}

#[test]
fn test_decscusr_block_blinking_0_and_1() {
    // DECSCUSR 0 and 1 both select blinking-block cursor shape.
    // Must not panic; terminal remains usable.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[0 q"); // blinking block (default)
    term.advance(b"\x1b[1 q"); // blinking block (explicit)
    assert!(term.screen.cursor().col < 80, "cursor must stay in bounds");
}

#[test]
fn test_decscusr_steady_block_2() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[2 q"); // steady block
    assert!(term.screen.cursor().row < 24);
}

#[test]
fn test_decscusr_out_of_range_7_no_panic() {
    // DECSCUSR with Ps=7 (out of standard 0–6 range) must not panic.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[7 q");
    assert!(term.screen.cursor().row < 24);
}

#[test]
fn test_kitty_kb_push_pop_restores_previous_non_zero() {
    // Push flags=7 on top of already-set flags=3.
    // After pop, flags must return to 3 (not 0).
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[>3u"); // push: save 0, current=3
    assert_eq!(term.dec_modes.keyboard_flags, 3);
    term.advance(b"\x1b[>7u"); // push: save 3, current=7
    assert_eq!(term.dec_modes.keyboard_flags, 7);
    term.advance(b"\x1b[<u"); // pop: restore 3
    assert_eq!(
        term.dec_modes.keyboard_flags, 3,
        "pop must restore the most-recently-pushed value (3)"
    );
    assert_eq!(term.dec_modes.keyboard_flags_stack.len(), 1);
}

#[test]
fn test_decrqm_multi_param_queues_multiple_responses() {
    // Sending two separate DECRQM queries in sequence must produce two entries
    // in pending_responses (one per query).
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?25$p"); // query cursor visible (default=set → status 1)
    term.advance(b"\x1b[?1049$p"); // query alt screen (default=reset → status 2)
    assert_eq!(
        term.meta.pending_responses.len(),
        2,
        "two DECRQM queries must produce two responses"
    );
    let r0 = String::from_utf8(term.meta.pending_responses[0].clone()).unwrap();
    let r1 = String::from_utf8(term.meta.pending_responses[1].clone()).unwrap();
    assert_eq!(r0, "\x1b[?25;1$y");
    assert_eq!(r1, "\x1b[?1049;2$y");
}
