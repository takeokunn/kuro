// ─────────────────────────────────────────────────────────────────────────────
// DA1 / DA2 — device attributes (pre-existing, regression test)
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn da1_produces_response() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[c"); // Primary DA
    let responses = common::read_responses(&t);
    assert!(!responses.is_empty(), "DA1 must produce a response");
    let resp = &responses[0];
    assert!(
        resp.contains("?1"),
        "DA1 response must contain '?1', got: {resp:?}"
    );
}

#[test]
fn da2_produces_response() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[>c"); // Secondary DA
    let responses = common::read_responses(&t);
    assert!(!responses.is_empty(), "DA2 must produce a response");
    let resp = &responses[0];
    assert!(
        resp.starts_with("\x1b[>"),
        "DA2 response must start with ESC[>, got: {resp:?}"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Synchronized Output (?2026) — DECRQM regression test
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn synchronized_output_enable_disable() {
    let mut t = TerminalCore::new(24, 80);
    assert!(!t.dec_modes().synchronized_output);
    t.advance(b"\x1b[?2026h");
    assert!(t.dec_modes().synchronized_output);
    t.advance(b"\x1b[?2026l");
    assert!(!t.dec_modes().synchronized_output);
}

#[test]
fn decrqm_synchronized_output_reports_state() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?2026h");
    t.advance(b"\x1b[?2026$p");
    let responses = common::read_responses(&t);
    assert!(!responses.is_empty());
    let resp = &responses[0];
    assert!(
        resp.contains("2026") && resp.contains('1'),
        "?2026 enabled → DECRQM must report 1, got: {resp:?}"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Kitty keyboard protocol — regression test
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn kitty_keyboard_push_pop_query() {
    let mut t = TerminalCore::new(24, 80);
    assert_eq!(t.dec_modes().keyboard_flags, 0);
    // Push flags=1
    t.advance(b"\x1b[>1u");
    assert_eq!(t.dec_modes().keyboard_flags, 1);
    // Query → response with current flags
    t.advance(b"\x1b[?u");
    let responses = common::read_responses(&t);
    assert!(!responses.is_empty(), "Kitty keyboard query must respond");
    // Pop
    t.advance(b"\x1b[<u");
    assert_eq!(
        t.dec_modes().keyboard_flags,
        0,
        "Flags should revert after pop"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// DECAWM (?7) — auto-wrap mode
// ─────────────────────────────────────────────────────────────────────────────

/// ?7h enables auto-wrap (re-enables after explicit disable).
#[test]
fn test_decawm_enable() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?7l"); // disable first
    assert!(
        !t.dec_modes().auto_wrap,
        "auto_wrap should be off after ?7l"
    );
    t.advance(b"\x1b[?7h"); // re-enable
    assert!(t.dec_modes().auto_wrap, "auto_wrap should be on after ?7h");
}

/// ?7l disables auto-wrap; cursor must stay at right margin on overflow.
#[test]
fn test_decawm_disable_cursor_stays_at_margin() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?7l"); // disable auto-wrap
    // Write exactly 80 chars → cursor is at col 79 (last col, 0-indexed)
    t.advance(&[b'A'; 80]);
    assert_eq!(
        t.cursor_col(),
        79,
        "cursor must stop at col 79 (right margin) when auto_wrap is off"
    );
    // Write one more char — cursor must NOT advance past col 79
    t.advance(b"X");
    assert_eq!(
        t.cursor_col(),
        79,
        "cursor must remain at col 79 after overflow with auto_wrap disabled"
    );
}

/// RIS restores auto_wrap to true (its default-on value).
#[test]
fn test_decawm_restored_after_ris() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?7l");
    assert!(!t.dec_modes().auto_wrap);
    t.advance(b"\x1bc"); // RIS
    assert!(
        t.dec_modes().auto_wrap,
        "RIS must restore auto_wrap to true"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// DECOM (?6) — origin mode
// ─────────────────────────────────────────────────────────────────────────────

/// ?6h sets origin_mode; cursor moves to top of scroll region on activation.
#[test]
fn test_decom_enable_sets_flag_and_homes_cursor() {
    let mut t = TerminalCore::new(24, 80);
    // Move cursor away from home first
    t.advance(b"\x1b[5;10H"); // CUP row 5, col 10 (1-indexed)
    assert_eq!(t.cursor_row(), 4);
    assert_eq!(t.cursor_col(), 9);

    t.advance(b"\x1b[?6h"); // enable DECOM
    assert!(
        t.dec_modes().origin_mode,
        "origin_mode must be set after ?6h"
    );
    // Cursor must return to top-of-scroll-region (row 0, col 0)
    assert_eq!(
        t.cursor_row(),
        0,
        "DECOM enable must move cursor to top of scroll region"
    );
    assert_eq!(t.cursor_col(), 0, "DECOM enable must move cursor to col 0");
}

/// ?6l clears origin_mode; cursor returns to absolute home on deactivation.
#[test]
fn test_decom_disable_clears_flag_and_homes_cursor() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?6h"); // enable
    assert!(t.dec_modes().origin_mode);

    t.advance(b"\x1b[?6l"); // disable
    assert!(
        !t.dec_modes().origin_mode,
        "origin_mode must be clear after ?6l"
    );
    // Cursor must be at absolute home (row 0, col 0)
    assert_eq!(
        t.cursor_row(),
        0,
        "DECOM disable must move cursor to absolute row 0"
    );
    assert_eq!(
        t.cursor_col(),
        0,
        "DECOM disable must move cursor to absolute col 0"
    );
}

/// RIS resets origin_mode to false.
#[test]
fn test_decom_reset_after_ris() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?6h");
    assert!(t.dec_modes().origin_mode);
    t.advance(b"\x1bc"); // RIS
    assert!(!t.dec_modes().origin_mode, "RIS must clear origin_mode");
}

// ─────────────────────────────────────────────────────────────────────────────
// Mouse tracking modes (?1000 / ?1002 / ?1003)
// ─────────────────────────────────────────────────────────────────────────────

/// ?1000h enables normal-button mouse tracking; ?1000l disables it.
#[test]
fn test_mouse_mode_1000_enable_disable() {
    let mut t = TerminalCore::new(24, 80);
    assert_eq!(t.dec_modes().mouse_mode, 0, "mouse_mode defaults to 0");
    t.advance(b"\x1b[?1000h");
    assert_eq!(
        t.dec_modes().mouse_mode,
        1000,
        "?1000h must set mouse_mode to 1000"
    );
    t.advance(b"\x1b[?1000l");
    assert_eq!(
        t.dec_modes().mouse_mode,
        0,
        "?1000l must clear mouse_mode to 0"
    );
}

/// ?1002h enables button-event mouse tracking; ?1002l disables it.
#[test]
fn test_mouse_mode_1002_enable_disable() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?1002h");
    assert_eq!(
        t.dec_modes().mouse_mode,
        1002,
        "?1002h must set mouse_mode to 1002"
    );
    t.advance(b"\x1b[?1002l");
    assert_eq!(
        t.dec_modes().mouse_mode,
        0,
        "?1002l must clear mouse_mode to 0"
    );
}

/// ?1003h enables any-event mouse tracking; ?1003l disables it.
#[test]
fn test_mouse_mode_1003_enable_disable() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?1003h");
    assert_eq!(
        t.dec_modes().mouse_mode,
        1003,
        "?1003h must set mouse_mode to 1003"
    );
    t.advance(b"\x1b[?1003l");
    assert_eq!(
        t.dec_modes().mouse_mode,
        0,
        "?1003l must clear mouse_mode to 0"
    );
}

/// Switching from one mouse mode to another replaces the stored value.
#[test]
fn test_mouse_mode_switch_replaces_previous() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?1000h"); // normal tracking
    assert_eq!(t.dec_modes().mouse_mode, 1000);
    t.advance(b"\x1b[?1003h"); // upgrade to any-event
    assert_eq!(
        t.dec_modes().mouse_mode,
        1003,
        "?1003h must replace ?1000h value"
    );
}

/// RIS clears mouse_mode to 0.
#[test]
fn test_mouse_mode_cleared_after_ris() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?1000h");
    assert_eq!(t.dec_modes().mouse_mode, 1000);
    t.advance(b"\x1bc"); // RIS
    assert_eq!(
        t.dec_modes().mouse_mode,
        0,
        "RIS must clear mouse_mode to 0"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Mode persistence across resize
// ─────────────────────────────────────────────────────────────────────────────

/// DEC modes must survive a terminal resize without being cleared.
#[test]
fn test_dec_modes_persist_across_resize() {
    let mut t = TerminalCore::new(24, 80);

    // Set several modes before resize
    t.advance(b"\x1b[?1h"); // DECCKM
    t.advance(b"\x1b[?2004h"); // bracketed paste
    t.advance(b"\x1b[?1006h"); // mouse SGR
    t.advance(b"\x1b[?25l"); // hide cursor

    // Resize: shrink and grow
    t.resize(10, 40);
    t.resize(24, 80);

    assert!(
        t.dec_modes().app_cursor_keys,
        "app_cursor_keys must persist across resize"
    );
    assert!(
        t.dec_modes().bracketed_paste,
        "bracketed_paste must persist across resize"
    );
    assert!(
        t.dec_modes().mouse_sgr,
        "mouse_sgr must persist across resize"
    );
    assert!(
        !t.cursor_visible(),
        "cursor_visible=false must persist across resize"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Mode interaction: alternate screen + mouse tracking
// ─────────────────────────────────────────────────────────────────────────────

/// Mouse tracking mode is independent of alternate screen: enabling one does
/// not clear the other, and switching screens does not affect mouse state.
#[test]
fn test_alt_screen_and_mouse_mode_are_independent() {
    let mut t = TerminalCore::new(24, 80);

    // Enable mouse tracking
    t.advance(b"\x1b[?1000h");
    assert_eq!(t.dec_modes().mouse_mode, 1000);
    assert!(!t.is_alternate_screen_active());

    // Switch to alt screen — mouse mode must stay
    t.advance(b"\x1b[?1049h");
    assert!(t.is_alternate_screen_active(), "alt screen must be active");
    assert_eq!(
        t.dec_modes().mouse_mode,
        1000,
        "mouse_mode must be preserved when entering alt screen"
    );

    // Disable mouse while on alt screen
    t.advance(b"\x1b[?1000l");
    assert_eq!(t.dec_modes().mouse_mode, 0, "mouse disabled on alt screen");
    assert!(t.is_alternate_screen_active(), "alt screen still active");

    // Re-enable mouse, then return to primary — mouse mode must survive
    t.advance(b"\x1b[?1002h");
    t.advance(b"\x1b[?1049l");
    assert!(
        !t.is_alternate_screen_active(),
        "primary screen must be active"
    );
    assert_eq!(
        t.dec_modes().mouse_mode,
        1002,
        "mouse_mode must persist when leaving alt screen"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// DECCOLM (?3) — 132-column mode (not implemented; silently ignored)
// ─────────────────────────────────────────────────────────────────────────────

// ?3h must not panic; terminal stays in 80-column mode (no DECCOLM field).
#[test]
fn test_deccolm_enable_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?3h"); // DECCOLM on — silently ignored
    assert!(t.cursor_row() < 24, "cursor row must be in bounds");
    assert!(t.cursor_col() < 80, "cursor col must be in bounds");
}

// ?3l must not panic; cursor stays in bounds.
#[test]
fn test_deccolm_disable_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?3h");
    t.advance(b"\x1b[?3l"); // DECCOLM off — silently ignored
    assert!(t.cursor_row() < 24, "cursor row must be in bounds");
    assert!(t.cursor_col() < 80, "cursor col must be in bounds");
}

include!("integration_dec_focus_events.rs");
