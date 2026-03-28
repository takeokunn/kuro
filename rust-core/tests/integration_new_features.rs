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

include!("include/integration_sgr_truecolor.rs");
