//! Integration tests for reset behaviour, `OscData` initialization, and
//! miscellaneous FR-T3 regressions that do not belong to a single protocol
//! topic file.
//!
//! Protocol-specific tests have been split into:
//!   - `integration_osc.rs`       — OSC 4 / 10 / 11 / 12 / 104 / 133 / 1337
//!   - `integration_dec_modes.rs` — XTVERSION, DECRQM, mouse-pixel, DA1/DA2,
//!     synchronized-output, Kitty KB
//!   - `integration_dcs.rs`       — DCS XTGETTCAP, DCS Sixel
//!   - `integration_sgr.rs`       — SGR extended underline (4:X, 21, 58, 59)

mod common;

use kuro_core::TerminalCore;

// ─────────────────────────────────────────────────────────────────────────────
// OscData::default() — ensure palette is 256 elements
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn osc_data_palette_initialized_to_256_nones() {
    let t = TerminalCore::new(24, 80);
    assert_eq!(
        t.osc_data().palette.len(),
        256,
        "OscData.palette must have 256 entries"
    );
    assert!(
        t.osc_data()
            .palette
            .iter()
            .all(std::option::Option::is_none),
        "All palette entries must be None initially"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Regression: reset() must clear dcs_state and palette
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn reset_clears_palette_entries() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]4;0;rgb:ff/00/00\x07");
    assert!(t.osc_data().palette[0].is_some());
    t.advance(b"\x1bc"); // RIS full reset
    assert!(
        t.osc_data().palette[0].is_none(),
        "RIS reset must clear palette entries"
    );
}

#[test]
fn reset_clears_default_colors() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]10;rgb:ff/ff/ff\x07");
    assert!(t.osc_data().default_fg.is_some());
    t.advance(b"\x1bc"); // RIS
    assert!(
        t.osc_data().default_fg.is_none(),
        "RIS reset must clear default_fg"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// FR-008: DECRQM state-machine — enable → query → disable → query
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn decrqm_mode_after_disable_responds_reset() {
    let mut t = TerminalCore::new(24, 80);

    // Enable focus events mode (1004)
    t.advance(b"\x1b[?1004h");

    // Query — mode 1004 should be reported as set (status 1)
    t.advance(b"\x1b[?1004$p");
    let responses_after_enable = common::read_responses(&t);
    assert!(
        !responses_after_enable.is_empty(),
        "DECRQM after enabling mode 1004 must produce a response"
    );
    // The last response is the DECRQM reply: should contain status 1 (set)
    let resp_enabled = responses_after_enable.last().unwrap();
    assert!(
        resp_enabled.contains("1004") && resp_enabled.contains('1') && resp_enabled.contains("$y"),
        "DECRQM for enabled mode 1004 must contain '1004;1$y', got: {resp_enabled:?}"
    );

    // Record how many responses exist before the disable+query round-trip
    let count_before_disable = responses_after_enable.len();

    // Disable focus events mode (1004)
    t.advance(b"\x1b[?1004l");

    // Query again — mode 1004 should now be reported as reset (status 2)
    t.advance(b"\x1b[?1004$p");
    let responses_after_disable = common::read_responses(&t);
    assert!(
        responses_after_disable.len() > count_before_disable,
        "DECRQM after disabling mode 1004 must produce an additional response"
    );
    // The last response is the new DECRQM reply: should contain status 2 (reset)
    let resp_disabled = responses_after_disable.last().unwrap();
    assert!(
        resp_disabled.contains("1004")
            && resp_disabled.contains('2')
            && resp_disabled.contains("$y"),
        "DECRQM for disabled mode 1004 must contain '1004;2$y', got: {resp_disabled:?}"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// FR-T3: OSC 4 ST terminator code path
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_osc4_st_terminator() {
    let mut t = TerminalCore::new(24, 80);
    // OSC 4 ; 1 ; rgb:ff/00/00 ST — same as BEL terminator but uses ESC backslash
    t.advance(b"\x1b]4;1;rgb:ff/00/00\x1b\\");
    let palette = &t.osc_data().palette;
    assert_eq!(
        palette[1],
        Some([0xff, 0x00, 0x00]),
        "Palette index 1 should be red after OSC 4 with ST terminator, got: {:?}",
        palette[1]
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// FR-T3: RIS clears DEC modes
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_ris_clears_dec_modes() {
    let mut t = TerminalCore::new(24, 80);

    // Enable DECCKM (app cursor keys, ?1) and bracketed paste (?2004)
    t.advance(b"\x1b[?1h");
    t.advance(b"\x1b[?2004h");
    assert!(
        t.dec_modes().app_cursor_keys,
        "app_cursor_keys must be enabled after ?1h"
    );
    assert!(
        t.dec_modes().bracketed_paste,
        "bracketed_paste must be enabled after ?2004h"
    );

    // RIS — Reset to Initial State
    t.advance(b"\x1bc");

    assert!(
        !t.dec_modes().app_cursor_keys,
        "app_cursor_keys must be reset to false after RIS"
    );
    assert!(
        !t.dec_modes().bracketed_paste,
        "bracketed_paste must be reset to false after RIS"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// FR-T3: Kitty keyboard stack depth (3 pushes, 3 pops)
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_kitty_stack_depth() {
    let mut t = TerminalCore::new(24, 80);
    assert_eq!(t.dec_modes().keyboard_flags, 0, "flags must start at 0");

    // Push flags=1
    t.advance(b"\x1b[>1u");
    assert_eq!(
        t.dec_modes().keyboard_flags,
        1,
        "flags should be 1 after first push"
    );

    // Push flags=2
    t.advance(b"\x1b[>2u");
    assert_eq!(
        t.dec_modes().keyboard_flags,
        2,
        "flags should be 2 after second push"
    );

    // Push flags=3
    t.advance(b"\x1b[>3u");
    assert_eq!(
        t.dec_modes().keyboard_flags,
        3,
        "flags should be 3 after third push"
    );
    assert_eq!(
        t.dec_modes().keyboard_flags_stack.len(),
        3,
        "stack must have 3 entries after 3 pushes"
    );

    // Query — current flags should be 3
    t.advance(b"\x1b[?u");
    let responses = common::read_responses(&t);
    assert!(
        !responses.is_empty(),
        "Kitty keyboard query must produce a response"
    );
    let resp = &responses[0];
    assert!(
        resp.contains('3'),
        "Query response must report current flags=3, got: {resp:?}"
    );

    // Pop — flags should revert to 2
    t.advance(b"\x1b[<u");
    assert_eq!(
        t.dec_modes().keyboard_flags,
        2,
        "flags should be 2 after first pop"
    );

    // Pop — flags should revert to 1
    t.advance(b"\x1b[<u");
    assert_eq!(
        t.dec_modes().keyboard_flags,
        1,
        "flags should be 1 after second pop"
    );

    // Pop — flags should revert to 0 (default)
    t.advance(b"\x1b[<u");
    assert_eq!(
        t.dec_modes().keyboard_flags,
        0,
        "flags should be 0 after third pop"
    );
    assert_eq!(
        t.dec_modes().keyboard_flags_stack.len(),
        0,
        "stack must be empty after all pops"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Application keypad mode (DECKPAM / DECKPNM — ESC = / ESC >)
// ─────────────────────────────────────────────────────────────────────────────

/// ESC = sets `app_keypad`; ESC > clears it.
#[test]
fn test_app_keypad_deckpam_deckpnm() {
    let mut t = TerminalCore::new(24, 80);
    assert!(
        !t.dec_modes().app_keypad,
        "app_keypad must default to false"
    );
    t.advance(b"\x1b="); // DECKPAM — application keypad on
    assert!(
        t.dec_modes().app_keypad,
        "app_keypad must be true after ESC ="
    );
    t.advance(b"\x1b>"); // DECKPNM — normal keypad
    assert!(
        !t.dec_modes().app_keypad,
        "app_keypad must be false after ESC >"
    );
}

/// RIS (ESC c) must clear `app_keypad` back to false.
#[test]
fn test_app_keypad_reset_after_ris() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b="); // enable
    assert!(t.dec_modes().app_keypad);
    t.advance(b"\x1bc"); // RIS
    assert!(!t.dec_modes().app_keypad, "RIS must clear app_keypad");
}

/// Repeated DECKPAM/DECKPNM toggling must not corrupt state.
#[test]
fn test_app_keypad_toggle_idempotent() {
    let mut t = TerminalCore::new(24, 80);
    for _ in 0..5 {
        t.advance(b"\x1b=");
        assert!(t.dec_modes().app_keypad);
        t.advance(b"\x1b>");
        assert!(!t.dec_modes().app_keypad);
    }
}

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
    assert!(
        !t.dec_modes().mouse_sgr,
        "mouse_sgr must default to false"
    );
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
    assert!(
        t.palette_dirty(),
        "palette_dirty must be true after OSC 4"
    );
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
