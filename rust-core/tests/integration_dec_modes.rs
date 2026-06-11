//! Integration tests for DEC private modes.

mod common;

use kuro_core::TerminalCore;

// ─────────────────────────────────────────────────────────────────────────────
// Macros — extract repeated set / reset / RIS patterns
// ─────────────────────────────────────────────────────────────────────────────

/// Assert that CSI ?{mode}h sets `$field` on `dec_modes()` and
/// CSI ?{mode}l clears it.  `$enable_seq` / `$disable_seq` are byte literals.
macro_rules! assert_dec_mode_enable_disable {
    ($name_en:ident, $name_dis:ident, $enable_seq:expr, $disable_seq:expr, $field:ident, $label:expr) => {
        #[test]
        fn $name_en() {
            let mut term = common::new_terminal();
            term.advance($enable_seq);
            assert!(
                term.dec_modes().$field,
                concat!($label, " should be enabled after h")
            );
        }

        #[test]
        fn $name_dis() {
            let mut term = common::new_terminal();
            term.advance($enable_seq);
            term.advance($disable_seq);
            assert!(
                !term.dec_modes().$field,
                concat!($label, " should be disabled after l")
            );
        }
    };
}

/// Assert that RIS (ESC c) resets `$field` to `false` after it was set.
macro_rules! assert_dec_mode_reset_after_ris {
    ($name:ident, $enable_seq:expr, $field:ident, $label:expr) => {
        #[test]
        fn $name() {
            let mut term = common::new_terminal();
            term.advance($enable_seq);
            assert!(
                term.dec_modes().$field,
                concat!($label, " should be set before RIS")
            );
            term.advance(b"\x1bc"); // RIS
            assert!(
                !term.dec_modes().$field,
                concat!($label, " should be reset after RIS")
            );
        }
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// DECCKM (?1) — application cursor keys
// ─────────────────────────────────────────────────────────────────────────────

assert_dec_mode_enable_disable!(
    test_decckm_enable,
    test_decckm_disable,
    b"\x1b[?1h",
    b"\x1b[?1l",
    app_cursor_keys,
    "DECCKM"
);

assert_dec_mode_reset_after_ris!(
    test_decckm_reset_after_ris,
    b"\x1b[?1h",
    app_cursor_keys,
    "DECCKM"
);

#[test]
fn test_decckm_toggle_multiple_times() {
    let mut term = common::new_terminal();
    for _ in 0..5 {
        term.advance(b"\x1b[?1h");
        assert!(term.dec_modes().app_cursor_keys);
        term.advance(b"\x1b[?1l");
        assert!(!term.dec_modes().app_cursor_keys);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bracketed paste (?2004)
// ─────────────────────────────────────────────────────────────────────────────

assert_dec_mode_enable_disable!(
    test_bracketed_paste_mode_enable,
    test_bracketed_paste_mode_disable,
    b"\x1b[?2004h",
    b"\x1b[?2004l",
    bracketed_paste,
    "Bracketed paste"
);

assert_dec_mode_reset_after_ris!(
    test_bracketed_paste_reset_after_ris,
    b"\x1b[?2004h",
    bracketed_paste,
    "Bracketed paste"
);

// ─────────────────────────────────────────────────────────────────────────────
// Focus events (?1004)
// ─────────────────────────────────────────────────────────────────────────────

assert_dec_mode_enable_disable!(
    test_focus_events_enable,
    test_focus_events_disable,
    b"\x1b[?1004h",
    b"\x1b[?1004l",
    focus_events,
    "Focus events"
);

assert_dec_mode_reset_after_ris!(
    test_focus_events_reset_after_ris,
    b"\x1b[?1004h",
    focus_events,
    "Focus events"
);

// ─────────────────────────────────────────────────────────────────────────────
// Mouse SGR (?1006)
// ─────────────────────────────────────────────────────────────────────────────

assert_dec_mode_enable_disable!(
    test_mouse_sgr_enable,
    test_mouse_sgr_disable,
    b"\x1b[?1006h",
    b"\x1b[?1006l",
    mouse_sgr,
    "Mouse SGR"
);

assert_dec_mode_reset_after_ris!(
    test_mouse_sgr_reset_after_ris,
    b"\x1b[?1006h",
    mouse_sgr,
    "Mouse SGR"
);

// ─────────────────────────────────────────────────────────────────────────────
// Mouse pixel (?1016)
// ─────────────────────────────────────────────────────────────────────────────

assert_dec_mode_enable_disable!(
    test_mouse_pixel_enable,
    test_mouse_pixel_disable,
    b"\x1b[?1016h",
    b"\x1b[?1016l",
    mouse_pixel,
    "Mouse pixel"
);

assert_dec_mode_reset_after_ris!(
    test_mouse_pixel_reset_after_ris,
    b"\x1b[?1016h",
    mouse_pixel,
    "Mouse pixel"
);

// ─────────────────────────────────────────────────────────────────────────────
// DECTCEM (?25) — cursor visibility
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_dectcem_cursor_hide() {
    let mut term = common::new_terminal();
    term.advance(b"\x1b[?25l"); // hide cursor
    assert!(!term.cursor_visible(), "Cursor should be hidden");
}

#[test]
fn test_dectcem_cursor_show() {
    let mut term = common::new_terminal();
    term.advance(b"\x1b[?25l");
    term.advance(b"\x1b[?25h"); // show cursor
    assert!(term.cursor_visible(), "Cursor should be visible");
}

#[test]
fn test_dectcem_after_ris() {
    let mut term = common::new_terminal();
    // Hide cursor
    term.advance(b"\x1b[?25l");
    assert!(!term.cursor_visible());
    // Full reset (RIS) should restore cursor visibility
    term.advance(b"\x1bc");
    assert!(term.cursor_visible(), "Cursor should be visible after RIS");
}

// ─────────────────────────────────────────────────────────────────────────────
// Alternate screen (?1049)
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_alternate_screen_activate() {
    let mut term = common::new_terminal();
    term.advance(b"\x1b[?1049h"); // switch to alt screen
    assert!(
        term.is_alternate_screen_active(),
        "Alt screen should be active"
    );
}

#[test]
fn test_alternate_screen_deactivate() {
    let mut term = common::new_terminal();
    term.advance(b"\x1b[?1049h");
    term.advance(b"\x1b[?1049l");
    assert!(
        !term.is_alternate_screen_active(),
        "Should return to primary screen"
    );
}

#[test]
fn test_alternate_screen_isolates_cursor() {
    let mut term = common::new_terminal();
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
fn test_alternate_screen_deactivated_after_ris() {
    let mut term = common::new_terminal();
    term.advance(b"\x1b[?1049h");
    assert!(term.is_alternate_screen_active());
    term.advance(b"\x1bc"); // RIS
    assert!(
        !term.is_alternate_screen_active(),
        "Alt screen should be deactivated after RIS"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Default state
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_dec_modes_default_state() {
    let term = common::new_terminal();
    // Default: app cursor keys off, bracketed paste off
    assert!(!term.app_cursor_keys());
    assert!(!term.bracketed_paste());
    // Default: cursor visible
    assert!(term.cursor_visible());
    // Default: alternate screen not active
    assert!(!term.is_alternate_screen_active());
    // Default: auto_wrap on
    assert!(
        term.dec_modes().auto_wrap,
        "auto_wrap should default to true"
    );
    // Default: origin_mode off
    assert!(!term.dec_modes().origin_mode);
    // Default: mouse modes off
    assert_eq!(term.dec_modes().mouse_mode, 0);
    assert!(!term.dec_modes().mouse_sgr);
    assert!(!term.dec_modes().mouse_pixel);
}

// ─────────────────────────────────────────────────────────────────────────────
// Synchronized Output mode (?2026)
// ─────────────────────────────────────────────────────────────────────────────

/// ?2026h must set `synchronized_output` = true.
#[test]
fn test_sync_output_enable() {
    let mut term = common::new_terminal();
    assert!(
        !term.dec_modes().synchronized_output,
        "synchronized_output must default to false"
    );
    term.advance(b"\x1b[?2026h");
    assert!(
        term.dec_modes().synchronized_output,
        "?2026h must set synchronized_output = true"
    );
}

/// ?2026l must clear `synchronized_output` = false.
#[test]
fn test_sync_output_disable() {
    let mut term = common::new_terminal();
    term.advance(b"\x1b[?2026h");
    assert!(term.dec_modes().synchronized_output);
    term.advance(b"\x1b[?2026l");
    assert!(
        !term.dec_modes().synchronized_output,
        "?2026l must clear synchronized_output"
    );
}

/// Repeated toggling must not corrupt state or panic.
#[test]
fn test_sync_output_toggle_multiple_times() {
    let mut term = common::new_terminal();
    for i in 0..10 {
        term.advance(b"\x1b[?2026h");
        assert!(
            term.dec_modes().synchronized_output,
            "iteration {i}: ?2026h must enable sync"
        );
        term.advance(b"\x1b[?2026l");
        assert!(
            !term.dec_modes().synchronized_output,
            "iteration {i}: ?2026l must disable sync"
        );
    }
}

/// Content written to the grid while ?2026h is active must be preserved in
/// the internal grid.  The sync flag only controls *when* kuro renders; it
/// does not discard or delay writes to the terminal state machine.
#[test]
fn test_sync_output_grid_content_preserved() {
    let mut term = common::new_terminal();
    // Enable sync, write some content
    term.advance(b"\x1b[?2026hHello");
    assert!(term.dec_modes().synchronized_output);

    // Grid content must exist even while sync is still active
    assert_eq!(
        term.get_cell(0, 0).map(kuro_core::Cell::char),
        Some('H'),
        "cell (0,0) must contain 'H' while sync is active"
    );
    assert_eq!(
        term.get_cell(0, 4).map(kuro_core::Cell::char),
        Some('o'),
        "cell (0,4) must contain 'o' while sync is active"
    );

    // Disable sync — content must still be there
    term.advance(b"\x1b[?2026l");
    assert_eq!(
        term.get_cell(0, 0).map(kuro_core::Cell::char),
        Some('H'),
        "cell (0,0) must still contain 'H' after ?2026l"
    );
}

/// Cursor position advances correctly during a sync batch.
/// Regression: early broken builds would track cursor incorrectly during sync.
#[test]
fn test_sync_output_cursor_advances_normally() {
    let mut term = common::new_terminal();
    term.advance(b"\x1b[?2026h");
    term.advance(b"ABCDE"); // 5 chars → cursor should be at col 5
    assert_eq!(
        term.cursor_col(),
        5,
        "cursor must advance normally during sync"
    );
    term.advance(b"\x1b[?2026l");
    assert_eq!(
        term.cursor_col(),
        5,
        "cursor col must be unchanged after ?2026l"
    );
}

/// Multiple cursor-movement sequences must work inside a sync batch.
/// This is the pattern TUI apps use: erase, reposition, draw.
#[test]
fn test_sync_output_cursor_movement_inside_batch() {
    let mut term = common::new_terminal();
    term.advance(b"\x1b[?2026h");

    // Draw separator line on row 0
    term.advance(b"\x1b[1;1H"); // CUP row 1, col 1 (1-indexed)
    term.advance(b"----------");
    assert_eq!(term.get_cell(0, 0).map(kuro_core::Cell::char), Some('-'));

    // Move to row 1, overwrite with text
    term.advance(b"\x1b[2;1H"); // CUP row 2, col 1
    term.advance(b"Hello");
    assert_eq!(term.get_cell(1, 0).map(kuro_core::Cell::char), Some('H'));

    // Erase and rewrite row 0 (simulating TUI overwrite)
    term.advance(b"\x1b[1;1H\x1b[2KReplace"); // CUP + EL(2) + text
    assert_eq!(
        term.get_cell(0, 0).map(kuro_core::Cell::char),
        Some('R'),
        "row 0 must be overwritten with 'R' (EL+text inside sync batch)"
    );

    term.advance(b"\x1b[?2026l");
}

// ─────────────────────────────────────────────────────────────────────────────
// In-band resize notifications (?2048)
// Spec: https://gist.github.com/rockorager/e695fb2924d36b2bcf1fff4a3704bd83
// Report format: CSI 48 ; rows ; cols ; height_px ; width_px t  (pixels 0 here).
// ─────────────────────────────────────────────────────────────────────────────

assert_dec_mode_enable_disable!(
    test_inband_resize_enable,
    test_inband_resize_disable,
    b"\x1b[?2048h",
    b"\x1b[?2048l",
    resize_in_band,
    "In-band resize (2048)"
);

assert_dec_mode_reset_after_ris!(
    test_inband_resize_reset_after_ris,
    b"\x1b[?2048h",
    resize_in_band,
    "In-band resize (2048)"
);

/// Enabling ?2048 MUST immediately emit one report of the current size,
/// per spec ("when first enabled, the terminal MUST send a report").
#[test]
fn test_inband_resize_enable_emits_immediate_report() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2048h");
    assert_eq!(
        common::read_responses(&term),
        vec!["\x1b[48;24;80;0;0t".to_string()],
        "enabling ?2048 must emit exactly one immediate current-size report"
    );
}

/// After ?2048 is enabled, a resize emits a fresh report carrying the NEW size.
/// The immediate enable-report is emitted first, then the resize report.
#[test]
fn test_inband_resize_reports_new_size_on_resize() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2048h"); // immediate report: 24x80
    term.resize(30, 100); // resize report: 30x100
    assert_eq!(
        common::read_responses(&term),
        vec![
            "\x1b[48;24;80;0;0t".to_string(),
            "\x1b[48;30;100;0;0t".to_string(),
        ],
        "resize after ?2048 must report the new size in characters"
    );
}

/// A resize WITHOUT ?2048 enabled must NOT emit any in-band report.
#[test]
fn test_resize_without_2048_emits_no_report() {
    let mut term = TerminalCore::new(24, 80);
    term.resize(30, 100);
    assert!(
        common::read_responses(&term).is_empty(),
        "resize without ?2048 must not emit an in-band report"
    );
}

/// Re-enabling ?2048 while already enabled MUST report again (spec: "if the
/// mode is already enabled, the terminal MUST immediately report the current
/// size if an attempt is made to enable the feature").
#[test]
fn test_inband_resize_reenable_reports_again() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2048h\x1b[?2048h");
    assert_eq!(
        common::read_responses(&term),
        vec![
            "\x1b[48;24;80;0;0t".to_string(),
            "\x1b[48;24;80;0;0t".to_string(),
        ],
        "re-enabling ?2048 must emit another immediate report"
    );
}

/// DECRQM (CSI ? 2048 $ p) must report the mode as supported (status 1 = set
/// after enable), which is how clients detect in-band resize support.
#[test]
fn test_inband_resize_decrqm_reports_supported() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2048h"); // also pushes the immediate size report
    term.advance(b"\x1b[?2048$p"); // DECRQM query
    let responses = common::read_responses(&term);
    assert!(
        responses
            .iter()
            .any(|r| r.contains("2048") && r.contains("$y")),
        "DECRQM for enabled ?2048 must report it supported (CSI ? 2048 ; 1 $ y), got: {responses:?}"
    );
}

include!("include/integration_dec_sync_output.rs");
include!("include/integration_dec_reverse_video.rs");
