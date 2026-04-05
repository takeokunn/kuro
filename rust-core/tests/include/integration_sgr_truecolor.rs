// ─────────────────────────────────────────────────────────────────────────────
// current_foreground() — SGR 38;2 RGB color
// ─────────────────────────────────────────────────────────────────────────────

/// SGR 38;2;r;g;b sets a true-colour foreground visible via `current_foreground()`.
#[test]
fn test_current_foreground_sgr_rgb() {
    let mut t = TerminalCore::new(24, 80);
    // Set foreground to rgb(255, 128, 0) via SGR 38;2;255;128;0
    t.advance(b"\x1b[38;2;255;128;0m");
    let fg = t.current_foreground();
    // The color must be a non-default RGB value
    match fg {
        kuro_core::Color::Rgb(r, g, b) => {
            assert_eq!(*r, 255, "red channel must be 255");
            assert_eq!(*g, 128, "green channel must be 128");
            assert_eq!(*b, 0, "blue channel must be 0");
        }
        other => panic!("expected Color::Rgb, got {other:?}"),
    }
}

/// SGR 0 (reset) after an RGB foreground restores `current_foreground()` to Default.
#[test]
fn test_current_foreground_reset_after_sgr_rgb() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[38;2;255;0;0m"); // red
    t.advance(b"\x1b[0m"); // SGR reset
    let fg = t.current_foreground();
    assert!(
        matches!(fg, kuro_core::Color::Default),
        "current_foreground must be Default after SGR 0, got {fg:?}"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// soft_reset() — mode interaction
// ─────────────────────────────────────────────────────────────────────────────

/// `soft_reset` clears origin_mode but must NOT switch screens or clear scrollback.
#[test]
fn test_soft_reset_clears_origin_mode() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?6h"); // enable DECOM
    assert!(
        t.dec_modes().origin_mode,
        "origin_mode set before soft_reset"
    );
    t.advance(b"\x1b[!p"); // DECSTR — soft reset
    assert!(
        !t.dec_modes().origin_mode,
        "soft_reset must clear origin_mode"
    );
}

/// `soft_reset` clears DECCKM (app_cursor_keys).
#[test]
fn test_soft_reset_clears_app_cursor_keys() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?1h");
    assert!(t.dec_modes().app_cursor_keys);
    t.advance(b"\x1b[!p"); // DECSTR
    assert!(
        !t.dec_modes().app_cursor_keys,
        "soft_reset must clear app_cursor_keys"
    );
}

/// `soft_reset` preserves screen content written before the reset.
#[test]
fn test_soft_reset_preserves_screen_content() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"Hello");
    t.advance(b"\x1b[!p"); // DECSTR
    assert_eq!(
        t.get_cell(0, 0).map(kuro_core::Cell::char),
        Some('H'),
        "soft_reset must not erase screen content"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// DECSC / DECRC via raw escape sequences (ESC 7 / ESC 8)
// ─────────────────────────────────────────────────────────────────────────────

/// ESC 7 saves and ESC 8 restores cursor position when sent as byte sequences.
#[test]
fn test_decsc_decrc_via_escape_sequences() {
    let mut t = TerminalCore::new(24, 80);
    // Move cursor to row 3, col 5 via CUP
    t.advance(b"\x1b[4;6H"); // CUP row 4, col 6 (1-indexed) → row 3, col 5 (0-indexed)
    assert_eq!(t.cursor_row(), 3);
    assert_eq!(t.cursor_col(), 5);

    t.advance(b"\x1b7"); // DECSC — save cursor

    // Move cursor away
    t.advance(b"\x1b[1;1H");
    assert_eq!(t.cursor_row(), 0);
    assert_eq!(t.cursor_col(), 0);

    t.advance(b"\x1b8"); // DECRC — restore cursor
    assert_eq!(t.cursor_row(), 3, "DECRC must restore row");
    assert_eq!(t.cursor_col(), 5, "DECRC must restore col");
}

/// ESC 8 without a prior ESC 7 is a no-op (cursor stays where it is).
#[test]
fn test_decrc_without_prior_decsc_is_noop() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[5;5H");
    let row_before = t.cursor_row();
    let col_before = t.cursor_col();
    t.advance(b"\x1b8"); // DECRC with no saved state
    // Cursor must not move (no saved state to restore)
    assert_eq!(
        t.cursor_row(),
        row_before,
        "DECRC without prior DECSC must not change row"
    );
    assert_eq!(
        t.cursor_col(),
        col_before,
        "DECRC without prior DECSC must not change col"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// DECTCEM — cursor visibility toggle
// ─────────────────────────────────────────────────────────────────────────────

/// ?25l hides the cursor; ?25h shows it again.
#[test]
fn test_dectcem_hide_show_toggle() {
    let mut t = TerminalCore::new(24, 80);
    assert!(t.cursor_visible(), "cursor must be visible by default");
    t.advance(b"\x1b[?25l"); // DECTCEM off — hide cursor
    assert!(!t.cursor_visible(), "cursor must be hidden after ?25l");
    t.advance(b"\x1b[?25h"); // DECTCEM on — show cursor
    assert!(t.cursor_visible(), "cursor must be visible after ?25h");
}

/// RIS (ESC c) must restore cursor visibility to true even if it was hidden.
#[test]
fn test_dectcem_restored_by_ris() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?25l"); // hide
    assert!(!t.cursor_visible());
    t.advance(b"\x1bc"); // RIS
    assert!(
        t.cursor_visible(),
        "RIS must restore cursor visibility to true"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Focus events (?1004)
// ─────────────────────────────────────────────────────────────────────────────

/// ?1004h enables focus events; ?1004l disables them.
#[test]
fn test_focus_events_enable_disable() {
    let mut t = TerminalCore::new(24, 80);
    assert!(
        !t.dec_modes().focus_events,
        "focus_events must default to false"
    );
    t.advance(b"\x1b[?1004h"); // enable
    assert!(
        t.dec_modes().focus_events,
        "focus_events must be true after ?1004h"
    );
    t.advance(b"\x1b[?1004l"); // disable
    assert!(
        !t.dec_modes().focus_events,
        "focus_events must be false after ?1004l"
    );
}

/// RIS must reset focus_events to false.
#[test]
fn test_focus_events_cleared_by_ris() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?1004h");
    assert!(t.dec_modes().focus_events);
    t.advance(b"\x1bc"); // RIS
    assert!(
        !t.dec_modes().focus_events,
        "RIS must reset focus_events to false"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Mouse tracking modes
// ─────────────────────────────────────────────────────────────────────────────

/// ?1000h enables normal mouse tracking; ?1000l disables it.
#[test]
fn test_mouse_mode_1000_enable_disable() {
    let mut t = TerminalCore::new(24, 80);
    assert_eq!(t.dec_modes().mouse_mode, 0, "mouse_mode must default to 0");
    t.advance(b"\x1b[?1000h");
    assert_eq!(
        t.dec_modes().mouse_mode,
        1000,
        "mouse_mode must be 1000 after ?1000h"
    );
    t.advance(b"\x1b[?1000l");
    assert_eq!(
        t.dec_modes().mouse_mode,
        0,
        "mouse_mode must be 0 after ?1000l"
    );
}

/// SGR mouse (?1006h) must set mouse_sgr; ?1006l clears it.
#[test]
fn test_mouse_sgr_enable_disable() {
    let mut t = TerminalCore::new(24, 80);
    assert!(!t.dec_modes().mouse_sgr, "mouse_sgr must default to false");
    t.advance(b"\x1b[?1006h");
    assert!(
        t.dec_modes().mouse_sgr,
        "mouse_sgr must be true after ?1006h"
    );
    t.advance(b"\x1b[?1006l");
    assert!(
        !t.dec_modes().mouse_sgr,
        "mouse_sgr must be false after ?1006l"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// palette_dirty / default_colors_dirty flags
// ─────────────────────────────────────────────────────────────────────────────

/// OSC 4 sets palette_dirty; reset() clears it.
#[test]
fn test_palette_dirty_set_and_cleared_by_reset() {
    let mut t = TerminalCore::new(24, 80);
    assert!(!t.palette_dirty(), "palette_dirty must start false");
    t.advance(b"\x1b]4;2;rgb:00/ff/00\x07"); // set palette index 2 to green
    assert!(t.palette_dirty(), "palette_dirty must be true after OSC 4");
    t.reset();
    assert!(
        !t.palette_dirty(),
        "palette_dirty must be false after reset()"
    );
}

/// OSC 10 sets default_colors_dirty; reset() clears it.
#[test]
fn test_default_colors_dirty_set_and_cleared_by_reset() {
    let mut t = TerminalCore::new(24, 80);
    assert!(
        !t.default_colors_dirty(),
        "default_colors_dirty must start false"
    );
    t.advance(b"\x1b]10;rgb:ff/ff/ff\x07"); // set default fg
    assert!(
        t.default_colors_dirty(),
        "default_colors_dirty must be true after OSC 10"
    );
    t.reset();
    assert!(
        !t.default_colors_dirty(),
        "default_colors_dirty must be false after reset()"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// OSC 1 — icon title (alias for window title in many terminals)
// ─────────────────────────────────────────────────────────────────────────────

/// OSC 1 sets the icon name; must not panic and cursor must remain in bounds.
#[test]
fn test_osc1_icon_title_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]1;my-icon\x07"); // OSC 1: icon title
    assert!(t.cursor_row() < 24);
    assert!(t.cursor_col() < 80);
}

// ─────────────────────────────────────────────────────────────────────────────
// soft_reset keyboard stack
// ─────────────────────────────────────────────────────────────────────────────

/// soft_reset (DECSTR) must also clear keyboard_flags_stack.
#[test]
fn test_soft_reset_clears_keyboard_flags_stack() {
    let mut t = TerminalCore::new(24, 80);
    // Push two flag sets onto the stack
    t.advance(b"\x1b[>1u");
    t.advance(b"\x1b[>2u");
    assert_eq!(
        t.dec_modes().keyboard_flags_stack.len(),
        2,
        "stack must have 2 entries after 2 pushes"
    );
    t.soft_reset();
    assert_eq!(
        t.dec_modes().keyboard_flags_stack.len(),
        0,
        "soft_reset must clear keyboard_flags_stack"
    );
    assert_eq!(
        t.dec_modes().keyboard_flags,
        0,
        "soft_reset must reset keyboard_flags to 0"
    );
}
