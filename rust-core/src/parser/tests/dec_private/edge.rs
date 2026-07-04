// ── New edge-case tests + previously untested modes ──────────────────────────
// `test_dec_mode_via_advance!` is defined in the parent module.

use super::*;

// ── DEC ?5 screen_reverse ────────────────────────────────────────────────────
test_dec_mode_via_advance!(
    test_screen_reverse_set_and_clear,
    b"\x1b[?5h",
    b"\x1b[?5l",
    screen_reverse
);

// ── DEC ?12 cursor-blink toggle ───────────────────────────────────────────────

#[test]
fn test_dec12_set_makes_cursor_blink_variant() {
    // ?12h toggles the current cursor shape to its blinking counterpart.
    // Default shape is BlinkingBlock, so set should keep it blinking.
    let mut term = crate::TerminalCore::new(24, 80);
    // Switch to steady block first via DECSCUSR 2
    term.advance(b"\x1b[2 q");
    assert_eq!(
        term.dec_modes.cursor_shape,
        crate::types::cursor::CursorShape::SteadyBlock
    );
    // ?12h: steady → blinking
    term.advance(b"\x1b[?12h");
    assert_eq!(
        term.dec_modes.cursor_shape,
        crate::types::cursor::CursorShape::BlinkingBlock,
        "?12h on SteadyBlock must produce BlinkingBlock"
    );
}

#[test]
fn test_dec12_reset_makes_cursor_steady_variant() {
    // ?12l toggles blinking → steady.
    let mut term = crate::TerminalCore::new(24, 80);
    // Default shape is BlinkingBlock; ?12l must switch to SteadyBlock.
    term.advance(b"\x1b[?12l");
    assert_eq!(
        term.dec_modes.cursor_shape,
        crate::types::cursor::CursorShape::SteadyBlock,
        "?12l on BlinkingBlock must produce SteadyBlock"
    );
}

// ── DEC ?40/?45/?66/?80 simple boolean toggles ────────────────────────────────
test_dec_mode_via_advance!(
    test_allow_deccolm_set_and_clear,
    b"\x1b[?40h",
    b"\x1b[?40l",
    allow_deccolm
);
test_dec_mode_via_advance!(
    test_reverse_wraparound_set_and_clear,
    b"\x1b[?45h",
    b"\x1b[?45l",
    reverse_wraparound
);
// DEC ?66 DECNKM aliases `app_keypad`.
test_dec_mode_via_advance!(
    test_decnkm_mode66_set_and_clear,
    b"\x1b[?66h",
    b"\x1b[?66l",
    app_keypad
);
test_dec_mode_via_advance!(
    test_sixel_display_mode_set_and_clear,
    b"\x1b[?80h",
    b"\x1b[?80l",
    sixel_display_mode
);

// ── ANSI IRM (CSI 4 h/l) + LNM (CSI 20 h/l) ─────────────────────────────────
test_dec_mode_via_advance!(
    test_ansi_irm_insert_mode_set_and_clear,
    b"\x1b[4h",
    b"\x1b[4l",
    insert_mode
);
test_dec_mode_via_advance!(
    test_ansi_lnm_newline_mode_set_and_clear,
    b"\x1b[20h",
    b"\x1b[20l",
    newline_mode
);

#[test]
fn test_ansi_decrqm_irm_reports_correct_status() {
    let mut term = crate::TerminalCore::new(24, 80);
    // Query IRM (mode 4) when reset → status 2
    term.advance(b"\x1b[4$p");
    assert_single_pending_response_text(&term, "\x1b[4;2$y");
    term.meta.pending_responses.clear();
    // Set IRM then query → status 1
    term.advance(b"\x1b[4h");
    term.advance(b"\x1b[4$p");
    assert_single_pending_response_text(&term, "\x1b[4;1$y");
}

#[test]
fn test_ansi_decrqm_lnm_reports_correct_status() {
    let mut term = crate::TerminalCore::new(24, 80);
    // LNM reset → status 2
    term.advance(b"\x1b[20$p");
    assert_single_pending_response_text(&term, "\x1b[20;2$y");
    term.meta.pending_responses.clear();
    // Set LNM, query → status 1
    term.advance(b"\x1b[20h");
    term.advance(b"\x1b[20$p");
    assert_single_pending_response_text(&term, "\x1b[20;1$y");
}

#[test]
fn test_ansi_decrqm_unknown_mode_reports_zero() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[99$p"); // mode 99 is not implemented
    assert_single_pending_response_text(&term, "\x1b[99;0$y");
}

// ── Original edge cases ───────────────────────────────────────────────────────

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
    assert_pending_response_texts(&term, &["\x1b[?25;1$y", "\x1b[?1049;2$y"]);
}

#[test]
fn test_decrqm_alt_screen_47_reports_reset_then_set() {
    // Mode 47 is a settable alternate-screen variant; DECRQM must report its
    // real state (2 = reset on primary, 1 = set on alt), not 0 (unrecognised).
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?47$p"); // default: primary screen → reset
    assert_single_pending_response_text(&term, "\x1b[?47;2$y");
    term.meta.pending_responses.clear();
    term.advance(b"\x1b[?47h"); // enter alternate screen
    term.advance(b"\x1b[?47$p");
    assert_single_pending_response_text(&term, "\x1b[?47;1$y");
}

#[test]
fn test_decrqm_alt_screen_1047_is_queryable() {
    // Mode 1047 was settable but not queryable before — must no longer
    // report status 0 (unrecognised).
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?1047$p");
    assert_single_pending_response_text(&term, "\x1b[?1047;2$y");
}

#[test]
fn test_alt_screen_47_reset_noop_when_already_primary() {
    // CSI ? 47 l when already on the primary screen must not panic or switch.
    // The guard `47 | 1047 if term.dec_modes.alternate_screen` prevents the
    // switch from firing when not in alternate screen.
    let mut term = crate::TerminalCore::new(24, 80);
    assert!(
        !term.dec_modes.alternate_screen,
        "precondition: primary screen"
    );
    term.advance(b"\x1b[?47l"); // reset 47 — no-op (guard not satisfied)
    assert!(
        !term.dec_modes.alternate_screen,
        "alternate_screen must still be false after spurious ?47l"
    );
}

#[test]
fn test_alt_screen_1047_reset_noop_when_already_primary() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?1047l"); // reset without being in alt screen
    assert!(!term.dec_modes.alternate_screen);
}

#[test]
fn test_sync_output_2026_reset_noop_when_not_active() {
    // CSI ? 2026 l when synchronized_output is already false must not
    // call mark_all_dirty (no observable effect) and must not panic.
    let mut term = crate::TerminalCore::new(24, 80);
    assert!(
        !term.dec_modes.synchronized_output,
        "precondition: synchronized_output is false"
    );
    term.advance(b"\x1b[?2026l"); // reset — guard `2026 if synchronized_output` not satisfied
    assert!(!term.dec_modes.synchronized_output);
}

// ── DECCOLM (?3 / ?40) ───────────────────────────────────────────────────────

#[test]
fn test_deccolm_ignored_without_allow_deccolm() {
    // Mode 3 must be silently ignored when mode 40 (allow_deccolm) is not set.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?3h"); // set mode 3 without mode 40
    assert_eq!(
        term.screen.cols(),
        80,
        "grid must remain 80 cols when allow_deccolm is not set"
    );
    assert!(
        !term.dec_modes.deccolm,
        "deccolm flag must remain false when allow_deccolm is not set"
    );
}

#[test]
fn test_deccolm_set_resizes_to_132_cols() {
    // CSI ? 40 h → CSI ? 3 h: grid must expand to 132 columns.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?40h"); // enable allow_deccolm
    term.advance(b"\x1b[?3h"); // activate DECCOLM
    assert_eq!(
        term.screen.cols(),
        132,
        "grid must resize to 132 cols on DECCOLM set"
    );
    assert!(term.dec_modes.deccolm, "deccolm flag must be set");
}

#[test]
fn test_deccolm_reset_restores_80_cols() {
    // CSI ? 3 l while allow_deccolm is set must return to 80 columns.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?40h");
    term.advance(b"\x1b[?3h"); // enter 132-col mode
    term.advance(b"\x1b[?3l"); // reset — return to 80-col mode
    assert_eq!(
        term.screen.cols(),
        80,
        "grid must return to 80 cols on DECCOLM reset"
    );
    assert!(!term.dec_modes.deccolm, "deccolm flag must be cleared");
}

#[test]
fn test_deccolm_set_homes_cursor() {
    // DECCOLM set must home the cursor to (0, 0) unconditionally.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?40h");
    term.advance(b"\x1b[5;10H"); // move cursor away
    term.advance(b"\x1b[?3h");
    assert_eq!(
        term.screen.cursor().row,
        0,
        "cursor row must be 0 after DECCOLM set"
    );
    assert_eq!(
        term.screen.cursor().col,
        0,
        "cursor col must be 0 after DECCOLM set"
    );
}

#[test]
fn test_deccolm_set_clears_screen() {
    // DECCOLM set must erase the entire screen content (all rows).
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?40h");
    term.advance(b"hello"); // write some content
    term.advance(b"\x1b[?3h"); // DECCOLM — must clear
                               // All cells in the first row must be blank (space) after the clear.
    let line = term.screen.get_line(0).expect("row 0 must exist");
    let non_blank = line.cells.iter().any(|c| c.char() != ' ');
    assert!(!non_blank, "DECCOLM set must erase all screen content");
}

#[test]
fn test_decrqm_deccolm_reports_status() {
    // DECRQM for mode 3 must report set (1) / reset (2) correctly.
    let mut term = crate::TerminalCore::new(24, 80);
    // With allow_deccolm off, mode 3 is untracked but still returns reset (2).
    term.advance(b"\x1b[?3$p");
    assert_single_pending_response_text(&term, "\x1b[?3;2$y");
    term.meta.pending_responses.clear();
    // Enable mode 40 and set mode 3.
    term.advance(b"\x1b[?40h");
    term.advance(b"\x1b[?3h");
    term.advance(b"\x1b[?3$p");
    assert_single_pending_response_text(&term, "\x1b[?3;1$y");
}

// ── XTSAVE / XTRESTORE — CSI ? Pm s / CSI ? Pm r ─────────────────────────────
// Full-snapshot approximation: `s` pushes a clone of the whole DecModes,
// `r` pops and restores it.

#[test]
fn test_xtsave_xtrestore_round_trips_modes_via_advance() {
    // INTENT: Set modes 1049 and 2004, save, change them, restore → both
    // restored to their saved (true) state through the CSI ? s / ? r stream path.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?1049h\x1b[?2004h");
    assert!(term.dec_modes.alternate_screen);
    assert!(term.dec_modes.bracketed_paste);

    // XTSAVE — snapshot current modes (params are ignored in the full-snapshot model).
    term.advance(b"\x1b[?1049;2004s");

    // Mutate both modes after saving.
    term.advance(b"\x1b[?1049l\x1b[?2004l");
    assert!(!term.dec_modes.alternate_screen);
    assert!(!term.dec_modes.bracketed_paste);

    // XTRESTORE — pop the snapshot; both modes return to their saved (true) state.
    term.advance(b"\x1b[?1049;2004r");
    assert!(
        term.dec_modes.alternate_screen,
        "1049 must be restored to its saved value"
    );
    assert!(
        term.dec_modes.bracketed_paste,
        "2004 must be restored to its saved value"
    );
}

#[test]
fn test_save_modes_then_restore_modes_round_trip() {
    // INTENT: Direct DecModes API — save, mutate, restore returns the snapshot.
    let mut modes = DecModes::new();
    modes.set_mode(1049);
    modes.set_mode(2004);

    modes.save_modes();
    modes.reset_mode(1049);
    modes.reset_mode(2004);
    assert!(!modes.alternate_screen);
    assert!(!modes.bracketed_paste);

    assert!(modes.restore_modes(), "restore must report success");
    assert!(modes.alternate_screen);
    assert!(modes.bracketed_paste);
}

#[test]
fn test_restore_modes_empty_stack_is_no_op() {
    // INTENT: XTRESTORE with nothing saved must not change state and must
    // report failure (no snapshot popped).
    let mut modes = DecModes::new();
    modes.set_mode(2004);
    assert!(modes.bracketed_paste);

    assert!(
        !modes.restore_modes(),
        "restore on empty stack must return false"
    );
    // State is untouched.
    assert!(modes.bracketed_paste, "modes must be unchanged");
    assert!(modes.saved_modes.is_empty());
}

#[test]
fn test_restore_modes_empty_stack_no_op_via_advance() {
    // INTENT: CSI ? r with an empty save stack is a no-op on the stream path.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2004h");
    term.advance(b"\x1b[?r"); // restore with empty stack
    assert!(
        term.dec_modes.bracketed_paste,
        "empty-stack restore must leave modes untouched"
    );
}

#[test]
fn test_save_modes_stack_cap_holds() {
    // INTENT: The save stack is capped at SAVED_MODES_STACK_MAX; pushing more
    // than the cap evicts the oldest entry so length never exceeds the cap.
    let mut modes = DecModes::new();
    for _ in 0..(super::super::SAVED_MODES_STACK_MAX + 10) {
        modes.save_modes();
    }
    assert_eq!(
        modes.saved_modes.len(),
        super::super::SAVED_MODES_STACK_MAX,
        "stack must be capped at SAVED_MODES_STACK_MAX"
    );
}

#[test]
fn test_snapshot_carries_empty_stack() {
    // INTENT: Each saved snapshot stores an empty saved_modes so the structure
    // cannot grow quadratically with stack depth.
    let mut modes = DecModes::new();
    modes.save_modes();
    modes.save_modes();
    for snap in &modes.saved_modes {
        assert!(
            snap.saved_modes.is_empty(),
            "snapshots must not carry their own save stack"
        );
    }
}

#[test]
fn test_restore_preserves_remaining_stack() {
    // INTENT: Restoring pops only the top snapshot; earlier saves remain on the
    // stack and can be restored by a subsequent CSI ? r.
    let mut modes = DecModes::new();
    // First save: 2004 on, 1049 off.
    modes.set_mode(2004);
    modes.save_modes();
    // Second save: both on.
    modes.set_mode(1049);
    modes.save_modes();

    // Mutate then restore the top (both-on) snapshot.
    modes.reset_mode(2004);
    modes.reset_mode(1049);
    assert!(modes.restore_modes());
    assert!(modes.alternate_screen);
    assert!(modes.bracketed_paste);

    // The earlier (2004-only) snapshot must still be restorable.
    assert!(modes.restore_modes());
    assert!(modes.bracketed_paste, "2004 was on in the first save");
    assert!(!modes.alternate_screen, "1049 was off in the first save");
}
