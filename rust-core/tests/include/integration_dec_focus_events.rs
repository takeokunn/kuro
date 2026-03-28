// ─────────────────────────────────────────────────────────────────────────────
// DECSCNM (?5) — screen normal/reverse video (not implemented; silently ignored)
// ─────────────────────────────────────────────────────────────────────────────

// ?5h (reverse video) and ?5l (normal video) must not panic.
#[test]
fn test_decscnm_enable_disable_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?5h"); // DECSCNM reverse — silently ignored
    assert!(t.cursor_row() < 24);
    t.advance(b"\x1b[?5l"); // DECSCNM normal — silently ignored
    assert!(t.cursor_row() < 24);
}

// Terminal must continue accepting input after DECSCNM toggle.
#[test]
fn test_decscnm_does_not_corrupt_grid() {
    let mut t = TerminalCore::new(5, 20);
    t.advance(b"\x1b[?5h"); // reverse video on
    t.advance(b"Hello");
    assert_eq!(
        t.get_cell(0, 0).map(kuro_core::Cell::char),
        Some('H'),
        "cell (0,0) must hold 'H' after DECSCNM toggle"
    );
    t.advance(b"\x1b[?5l"); // reverse video off
    assert_eq!(
        t.get_cell(0, 0).map(kuro_core::Cell::char),
        Some('H'),
        "cell (0,0) must be unchanged after DECSCNM off"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// DECTCEM (?25) — additional cursor visibility tests
// ─────────────────────────────────────────────────────────────────────────────

// Toggling cursor visibility multiple times must stay consistent.
#[test]
fn test_dectcem_toggle_multiple_times() {
    let mut t = TerminalCore::new(24, 80);
    for i in 0..5 {
        t.advance(b"\x1b[?25l");
        assert!(
            !t.cursor_visible(),
            "iteration {i}: cursor must be hidden after ?25l"
        );
        t.advance(b"\x1b[?25h");
        assert!(
            t.cursor_visible(),
            "iteration {i}: cursor must be visible after ?25h"
        );
    }
}

// Cursor is visible by default and DECRQM should report status=1 (set).
#[test]
fn test_dectcem_default_visible_reported_by_decrqm() {
    let mut t = TerminalCore::new(24, 80);
    assert!(t.cursor_visible(), "cursor must be visible by default");
    t.advance(b"\x1b[?25$p"); // DECRQM query for mode 25
    let responses = common::read_responses(&t);
    assert!(
        !responses.is_empty(),
        "DECRQM for ?25 must produce a response"
    );
    let resp = &responses[0];
    // Status 1 = set (cursor visible)
    assert!(
        resp.contains("25") && resp.contains('1'),
        "DECRQM for mode 25 (default visible) must report status=1, got: {resp:?}"
    );
}

// After ?25l, DECRQM must report status=2 (reset).
#[test]
fn test_dectcem_hidden_reported_by_decrqm() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?25l"); // hide cursor
    t.advance(b"\x1b[?25$p"); // DECRQM query
    let responses = common::read_responses(&t);
    assert!(!responses.is_empty());
    let resp = &responses[0];
    assert!(
        resp.contains("25") && resp.contains('2'),
        "DECRQM for mode 25 (hidden) must report status=2, got: {resp:?}"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// DECSCUSR — cursor shape (CSI Ps SP q)
// ─────────────────────────────────────────────────────────────────────────────

// DECSCUSR 0 (default) must set BlinkingBlock.
#[test]
fn test_decscusr_0_blinking_block() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[2 q"); // set SteadyBlock first
    assert_eq!(
        t.dec_modes().cursor_shape,
        kuro_core::types::cursor::CursorShape::SteadyBlock
    );
    t.advance(b"\x1b[0 q"); // reset to default (BlinkingBlock)
    assert_eq!(
        t.dec_modes().cursor_shape,
        kuro_core::types::cursor::CursorShape::BlinkingBlock,
        "DECSCUSR 0 must set BlinkingBlock"
    );
}

// DECSCUSR 1 is an alias for BlinkingBlock.
#[test]
fn test_decscusr_1_blinking_block_alias() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[6 q"); // SteadyBar first
    t.advance(b"\x1b[1 q"); // DECSCUSR 1 — alias for BlinkingBlock
    assert_eq!(
        t.dec_modes().cursor_shape,
        kuro_core::types::cursor::CursorShape::BlinkingBlock,
        "DECSCUSR 1 must be alias for BlinkingBlock"
    );
}

// DECSCUSR 4 must set SteadyUnderline.
#[test]
fn test_decscusr_4_steady_underline() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[4 q");
    assert_eq!(
        t.dec_modes().cursor_shape,
        kuro_core::types::cursor::CursorShape::SteadyUnderline,
        "DECSCUSR 4 must set SteadyUnderline"
    );
}

// DECSCUSR 6 must set SteadyBar.
#[test]
fn test_decscusr_6_steady_bar() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[6 q");
    assert_eq!(
        t.dec_modes().cursor_shape,
        kuro_core::types::cursor::CursorShape::SteadyBar,
        "DECSCUSR 6 must set SteadyBar"
    );
}

// RIS (ESC c) must reset cursor_shape to the default (BlinkingBlock).
#[test]
fn test_decscusr_reset_after_ris() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[4 q"); // SteadyUnderline
    assert_eq!(
        t.dec_modes().cursor_shape,
        kuro_core::types::cursor::CursorShape::SteadyUnderline
    );
    t.advance(b"\x1bc"); // RIS
    assert_eq!(
        t.dec_modes().cursor_shape,
        kuro_core::types::cursor::CursorShape::BlinkingBlock,
        "RIS must reset cursor_shape to BlinkingBlock"
    );
}

// Unknown DECSCUSR parameter must not panic and must fall back to BlinkingBlock.
#[test]
fn test_decscusr_unknown_param_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[99 q"); // out-of-range parameter — must not panic
                             // Must not panic; cursor shape should be BlinkingBlock (fallback)
    assert!(
        t.cursor_row() < 24,
        "cursor must be in bounds after unknown DECSCUSR"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Mouse tracking — RIS resets mode 1002 and mode 1003
// ─────────────────────────────────────────────────────────────────────────────

// RIS must clear mouse_mode 1002 to 0.
#[test]
fn test_mouse_mode_1002_cleared_by_ris() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?1002h");
    assert_eq!(t.dec_modes().mouse_mode, 1002);
    t.advance(b"\x1bc"); // RIS
    assert_eq!(
        t.dec_modes().mouse_mode,
        0,
        "RIS must clear mouse_mode 1002 to 0"
    );
}

// RIS must clear mouse_mode 1003 to 0.
#[test]
fn test_mouse_mode_1003_cleared_by_ris() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?1003h");
    assert_eq!(t.dec_modes().mouse_mode, 1003);
    t.advance(b"\x1bc"); // RIS
    assert_eq!(
        t.dec_modes().mouse_mode,
        0,
        "RIS must clear mouse_mode 1003 to 0"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// DECRQM — querying enabled mouse tracking modes
// ─────────────────────────────────────────────────────────────────────────────

// After enabling ?1000, DECRQM must report status=1 for mode 1000.
#[test]
fn test_decrqm_mouse_mode_1000_enabled() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?1000h");
    t.advance(b"\x1b[?1000$p");
    let responses = common::read_responses(&t);
    assert!(!responses.is_empty());
    let resp = &responses[0];
    assert!(
        resp.contains("1000") && resp.contains('1'),
        "DECRQM ?1000 enabled → status=1, got: {resp:?}"
    );
}

// After disabling ?1000, DECRQM must report status=2 for mode 1000.
#[test]
fn test_decrqm_mouse_mode_1000_disabled() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?1000h");
    t.advance(b"\x1b[?1000l");
    t.advance(b"\x1b[?1000$p");
    let responses = common::read_responses(&t);
    assert!(!responses.is_empty());
    // Find the DECRQM response (may be after other responses)
    let resp = responses.last().unwrap();
    assert!(
        resp.contains("1000") && resp.contains('2'),
        "DECRQM ?1000 disabled → status=2, got: {resp:?}"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Focus events + Bracketed paste — independence
// ─────────────────────────────────────────────────────────────────────────────

// Enabling one must not implicitly enable the other.
#[test]
fn test_focus_events_and_bracketed_paste_are_independent() {
    let mut t = TerminalCore::new(24, 80);

    // Enable focus events only
    t.advance(b"\x1b[?1004h");
    assert!(t.dec_modes().focus_events, "focus_events must be on");
    assert!(
        !t.dec_modes().bracketed_paste,
        "bracketed_paste must still be off"
    );

    // Now enable bracketed paste as well
    t.advance(b"\x1b[?2004h");
    assert!(t.dec_modes().focus_events, "focus_events must remain on");
    assert!(
        t.dec_modes().bracketed_paste,
        "bracketed_paste must now be on"
    );

    // Disable focus events — bracketed paste must remain
    t.advance(b"\x1b[?1004l");
    assert!(!t.dec_modes().focus_events, "focus_events must be off");
    assert!(
        t.dec_modes().bracketed_paste,
        "bracketed_paste must remain on"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Kitty keyboard stack — overflow guard (stack capped at 64 entries)
// ─────────────────────────────────────────────────────────────────────────────

// Pushing more than 64 entries must not panic and stack size stays ≤ 64.
#[test]
fn test_kitty_keyboard_stack_overflow_guard() {
    let mut t = TerminalCore::new(24, 80);
    for flags in 0u32..70 {
        let seq = format!("\x1b[>{flags}u");
        t.advance(seq.as_bytes());
    }
    assert!(
        t.dec_modes().keyboard_flags_stack.len() <= 64,
        "keyboard_flags_stack must not exceed 64 entries"
    );
    // Pop 64 times — must not panic
    for _ in 0..70 {
        t.advance(b"\x1b[<u");
    }
    // After exhausting the stack, flags must be 0
    assert_eq!(
        t.dec_modes().keyboard_flags,
        0,
        "keyboard_flags must be 0 after exhausting stack"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// RIS resets all major modes simultaneously
// ─────────────────────────────────────────────────────────────────────────────

// RIS must clear every settable DEC mode back to its default.
#[test]
fn test_ris_resets_all_dec_modes() {
    let mut t = TerminalCore::new(24, 80);

    // Set everything that can be set
    t.advance(b"\x1b[?1h"); // DECCKM
    t.advance(b"\x1b[?7l"); // DECAWM off (default is on, so toggling)
    t.advance(b"\x1b[?25l"); // DECTCEM hide
    t.advance(b"\x1b[?1004h"); // focus events
    t.advance(b"\x1b[?1006h"); // mouse SGR
    t.advance(b"\x1b[?1016h"); // mouse pixel
    t.advance(b"\x1b[?2004h"); // bracketed paste
    t.advance(b"\x1b[?2026h"); // synchronized output
    t.advance(b"\x1b[?1000h"); // mouse mode 1000
    t.advance(b"\x1b[6 q"); // cursor shape SteadyBar (wait, 6 = SteadyBar)
    t.advance(b"\x1b[>5u"); // kitty keyboard flags=5

    // Full reset
    t.advance(b"\x1bc");

    // Verify all defaults restored
    let m = t.dec_modes();
    assert!(!m.app_cursor_keys, "app_cursor_keys must be off after RIS");
    assert!(m.auto_wrap, "auto_wrap must be on after RIS");
    assert!(m.cursor_visible, "cursor_visible must be on after RIS");
    assert!(!m.focus_events, "focus_events must be off after RIS");
    assert!(!m.mouse_sgr, "mouse_sgr must be off after RIS");
    assert!(!m.mouse_pixel, "mouse_pixel must be off after RIS");
    assert!(!m.bracketed_paste, "bracketed_paste must be off after RIS");
    assert!(
        !m.synchronized_output,
        "synchronized_output must be off after RIS"
    );
    assert_eq!(m.mouse_mode, 0, "mouse_mode must be 0 after RIS");
    assert_eq!(
        m.cursor_shape,
        kuro_core::types::cursor::CursorShape::BlinkingBlock,
        "cursor_shape must be BlinkingBlock after RIS"
    );
    assert_eq!(m.keyboard_flags, 0, "keyboard_flags must be 0 after RIS");
    assert!(
        !t.is_alternate_screen_active(),
        "alt screen must be off after RIS"
    );
}

/// Synchronized output and alt screen can both be active; each can be
/// cleared independently without affecting the other.
#[test]
fn test_sync_and_alt_screen_clear_independently() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?1049h"); // alt screen on
    t.advance(b"\x1b[?2026h"); // sync on

    assert!(t.is_alternate_screen_active());
    assert!(t.dec_modes().synchronized_output);

    // Clear sync — alt screen unchanged
    t.advance(b"\x1b[?2026l");
    assert!(
        !t.dec_modes().synchronized_output,
        "sync must be off after ?2026l"
    );
    assert!(
        t.is_alternate_screen_active(),
        "alt screen must remain active after clearing sync"
    );

    // Clear alt screen — sync unchanged (already off)
    t.advance(b"\x1b[?1049l");
    assert!(
        !t.is_alternate_screen_active(),
        "alt screen must be off after ?1049l"
    );
    assert!(!t.dec_modes().synchronized_output, "sync must still be off");
}
