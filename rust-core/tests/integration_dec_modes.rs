//! Integration tests for DEC private modes.

use kuro_core::TerminalCore;

#[test]
fn test_decckm_enable() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?1h"); // enable DECCKM (application cursor keys)
    assert!(term.app_cursor_keys(), "DECCKM should be enabled");
}

#[test]
fn test_decckm_disable() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?1h");
    term.advance(b"\x1b[?1l"); // disable DECCKM
    assert!(!term.app_cursor_keys(), "DECCKM should be disabled");
}

#[test]
fn test_decckm_toggle_multiple_times() {
    let mut term = TerminalCore::new(24, 80);
    for _ in 0..5 {
        term.advance(b"\x1b[?1h");
        assert!(term.app_cursor_keys());
        term.advance(b"\x1b[?1l");
        assert!(!term.app_cursor_keys());
    }
}

#[test]
fn test_bracketed_paste_mode_enable() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2004h");
    assert!(term.bracketed_paste(), "Bracketed paste should be enabled");
}

#[test]
fn test_bracketed_paste_mode_disable() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2004h");
    term.advance(b"\x1b[?2004l");
    assert!(!term.bracketed_paste(), "Bracketed paste should be disabled");
}

#[test]
fn test_alternate_screen_activate() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?1049h"); // switch to alt screen
    assert!(
        term.is_alternate_screen_active(),
        "Alt screen should be active"
    );
}

#[test]
fn test_alternate_screen_deactivate() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?1049h");
    term.advance(b"\x1b[?1049l");
    assert!(
        !term.is_alternate_screen_active(),
        "Should return to primary screen"
    );
}

#[test]
fn test_alternate_screen_isolates_cursor() {
    let mut term = TerminalCore::new(24, 80);
    // Write to primary screen, cursor advances
    term.advance(b"primary content");
    let primary_col = term.cursor_col();
    assert!(primary_col > 0, "Primary cursor should have advanced");

    // Switch to alt screen — alt screen starts with cursor at (0,0)
    term.advance(b"\x1b[?1049h");
    assert_eq!(term.cursor_col(), 0, "Alt screen cursor should be at col 0");
    assert_eq!(term.cursor_row(), 0, "Alt screen cursor should be at row 0");

    // Switch back to primary — cursor should be restored
    term.advance(b"\x1b[?1049l");
    assert_eq!(
        term.cursor_col(),
        primary_col,
        "Primary screen cursor col should be restored"
    );
}

#[test]
fn test_dectcem_cursor_hide() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?25l"); // hide cursor
    assert!(!term.cursor_visible(), "Cursor should be hidden");
}

#[test]
fn test_dectcem_cursor_show() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?25l");
    term.advance(b"\x1b[?25h"); // show cursor
    assert!(term.cursor_visible(), "Cursor should be visible");
}

#[test]
fn test_dec_modes_default_state() {
    let term = TerminalCore::new(24, 80);
    // Default: app cursor keys off, bracketed paste off
    assert!(!term.app_cursor_keys());
    assert!(!term.bracketed_paste());
    // Default: cursor visible
    assert!(term.cursor_visible());
    // Default: alternate screen not active
    assert!(!term.is_alternate_screen_active());
}

#[test]
fn test_dectcem_after_ris() {
    let mut term = TerminalCore::new(24, 80);
    // Hide cursor
    term.advance(b"\x1b[?25l");
    assert!(!term.cursor_visible());
    // Full reset (RIS) should restore cursor visibility
    term.advance(b"\x1bc");
    assert!(
        term.cursor_visible(),
        "Cursor should be visible after RIS"
    );
}

#[test]
fn test_decckm_reset_after_ris() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?1h");
    assert!(term.app_cursor_keys());
    term.advance(b"\x1bc"); // RIS
    assert!(!term.app_cursor_keys(), "DECCKM should be reset after RIS");
}

#[test]
fn test_bracketed_paste_reset_after_ris() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2004h");
    assert!(term.bracketed_paste());
    term.advance(b"\x1bc"); // RIS
    assert!(
        !term.bracketed_paste(),
        "Bracketed paste should be reset after RIS"
    );
}

#[test]
fn test_alternate_screen_deactivated_after_ris() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?1049h");
    assert!(term.is_alternate_screen_active());
    term.advance(b"\x1bc"); // RIS
    assert!(
        !term.is_alternate_screen_active(),
        "Alt screen should be deactivated after RIS"
    );
}
