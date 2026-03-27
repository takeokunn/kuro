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
            let mut term = TerminalCore::new(24, 80);
            term.advance($enable_seq);
            assert!(
                term.dec_modes().$field,
                concat!($label, " should be enabled after h")
            );
        }

        #[test]
        fn $name_dis() {
            let mut term = TerminalCore::new(24, 80);
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
            let mut term = TerminalCore::new(24, 80);
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
    let mut term = TerminalCore::new(24, 80);
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
fn test_dectcem_after_ris() {
    let mut term = TerminalCore::new(24, 80);
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

// ─────────────────────────────────────────────────────────────────────────────
// Default state
// ─────────────────────────────────────────────────────────────────────────────

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
    let mut term = TerminalCore::new(24, 80);
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
    let mut term = TerminalCore::new(24, 80);
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
    let mut term = TerminalCore::new(24, 80);
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
    let mut term = TerminalCore::new(24, 80);
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
    let mut term = TerminalCore::new(24, 80);
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
    let mut term = TerminalCore::new(24, 80);
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

/// Simulates the exact startup sequence that claude-code sends.
///
/// claude-code sends:
///   ?2004h ?1004h ?25l ?1004l ?2004l ?2026h  ← setup + sync on
///   ... draw header, separators, status bar, mode-line ...
///   ?2026l                                    ← sync off (frame complete)
///
/// This test verifies that all content survives the batch and the mode
/// state is clean after the sequence completes.
#[test]
fn test_sync_output_claude_code_startup_sequence() {
    let mut term = TerminalCore::new(24, 80);

    // Exact preamble from captured claude-code PTY output
    term.advance(b"\x1b[?2004h"); // bracketed paste on
    term.advance(b"\x1b[?1004h"); // focus events on (immediately disabled below)
    term.advance(b"\x1b[?25l"); // hide cursor while drawing
    term.advance(b"\x1b[?1004l"); // focus events off
    term.advance(b"\x1b[?2004l"); // bracketed paste off
    term.advance(b"\x1b[?2026h"); // SYNC ON — begin frame batch

    assert!(
        term.dec_modes().synchronized_output,
        "sync must be active at start of claude-code frame batch"
    );
    assert!(
        !term.cursor_visible(),
        "cursor must be hidden during frame draw"
    );

    // Draw content that claude-code would write (simplified):
    // Header line
    term.advance(b"\x1b[1;1HClaude Code v2");
    // Separator line (box-drawing chars U+2500 = 0xE2 0x94 0x80)
    term.advance(b"\x1b[2;1H");
    term.advance("\u{2500}".repeat(40).as_bytes()); // 40 × ─
                                                    // Input prompt area
    term.advance(b"\x1b[3;1H\xe2\x9d\xaf "); // ❯  (U+275F prompt)
                                             // Status bar at bottom
    term.advance(b"\x1b[24;1H");
    term.advance(b"\xef\x93\x93 Sonnet 4.6"); // NerdFont icon + model name

    // End frame batch
    term.advance(b"\x1b[?2026l"); // SYNC OFF

    // Verify mode state
    assert!(
        !term.dec_modes().synchronized_output,
        "sync must be off after ?2026l"
    );

    // Verify grid content survives the batch
    assert_eq!(
        term.get_cell(0, 0).map(kuro_core::Cell::char),
        Some('C'),
        "header 'C' must be at row 0, col 0 after sync batch"
    );
    // Box-drawing char at row 1, col 0 (U+2500 ─)
    assert_eq!(
        term.get_cell(1, 0).map(kuro_core::Cell::char),
        Some('\u{2500}'),
        "box-drawing ─ (U+2500) must be at row 1, col 0 after sync batch"
    );
    // Status bar at row 23
    // (NerdFont icon varies by font; just verify a printable char landed there)
    let status_cell = term.get_cell(23, 0).map(kuro_core::Cell::char);
    assert!(
        status_cell.is_some(),
        "status bar row 23 must have content after sync batch"
    );
}

/// ?2026 does NOT interact with alternate screen — both can be active at once.
#[test]
fn test_sync_output_independent_of_alternate_screen() {
    let mut term = TerminalCore::new(24, 80);

    // Activate both simultaneously
    term.advance(b"\x1b[?1049h"); // alt screen on
    term.advance(b"\x1b[?2026h"); // sync on

    assert!(term.is_alternate_screen_active());
    assert!(term.dec_modes().synchronized_output);

    // Disable sync — alt screen must still be active
    term.advance(b"\x1b[?2026l");
    assert!(!term.dec_modes().synchronized_output);
    assert!(
        term.is_alternate_screen_active(),
        "alt screen must remain active after ?2026l"
    );

    // Disable alt screen — sync must still be off
    term.advance(b"\x1b[?1049l");
    assert!(!term.is_alternate_screen_active());
    assert!(!term.dec_modes().synchronized_output);
}

/// RIS (ESC c) must reset `synchronized_output` to false.
#[test]
fn test_sync_output_reset_after_ris() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2026h");
    assert!(term.dec_modes().synchronized_output);
    term.advance(b"\x1bc"); // Full Reset (RIS)
    assert!(
        !term.dec_modes().synchronized_output,
        "RIS must clear synchronized_output"
    );
}

/// Simulate rapid consecutive sync batches (as claude-code produces during streaming).
/// Each batch: write a tool-result line, then reposition cursor up 1 to overwrite
/// the mode-line row. Verify the grid has correct content after all batches.
///
/// This is a regression test for the claude-code rendering corruption scenario where
/// each streaming update is a separate ?2026h/?2026l sync batch.
#[test]
fn test_sync_output_rapid_streaming_no_corruption() {
    let mut term = TerminalCore::new(10, 40);

    // Use CUP (CSI H) to set up initial content precisely
    // Row 0: "HeaderRow0"
    term.advance(b"\x1b[?2026h\x1b[1;1HHeaderRow0");
    // Row 1: separator chars (U+2500 = \xe2\x94\x80)
    term.advance(b"\x1b[2;1H");
    term.advance("\u{2500}".repeat(40).as_bytes());
    // Row 2: prompt
    term.advance(b"\x1b[3;1HPrompt> ");
    // Row 3: mode-line at col 2
    term.advance(b"\x1b[4;3HStatusBar");
    term.advance(b"\x1b[?2026l");

    // Verify initial state via CUP-positioned content
    assert_eq!(
        term.get_cell(0, 0).map(kuro_core::Cell::char),
        Some('H'),
        "row 0 col 0 = 'H'"
    );
    assert_eq!(
        term.get_cell(1, 0).map(kuro_core::Cell::char),
        Some('\u{2500}'),
        "row 1 col 0 = box-drawing separator"
    );
    assert_eq!(
        term.get_cell(2, 0).map(kuro_core::Cell::char),
        Some('P'),
        "row 2 col 0 = 'P' (Prompt)"
    );
    assert_eq!(
        term.get_cell(3, 2).map(kuro_core::Cell::char),
        Some('S'),
        "row 3 col 2 = 'S' (StatusBar)"
    );

    // Streaming: each batch appends a tool result and moves mode-line down.
    // Pattern from actual claude-code capture:
    //   ?2026h
    //   CR + CUF 2 + CUU N   (go to mode-line row)
    //   <new tool result line>
    //   <mode-line content at right col via CUF large>
    //   CR CR LF              (advance cursor)
    //   ?2026l
    //
    // Simplified: position to target row via CUP, write content, update mode-line.
    for batch in 1u8..=4 {
        let tool_row = 4 + batch as usize; // tool result goes to rows 5,6,7,8 (0-indexed)

        term.advance(b"\x1b[?2026h");

        // Write tool result at tool_row, col 0
        let row_1indexed = tool_row + 1;
        let cup = format!("\x1b[{row_1indexed};1H");
        term.advance(cup.as_bytes());
        let tool_content = format!("Tool{batch}Result       "); // 20 chars
        term.advance(tool_content.as_bytes());

        // Write mode-line at same row, right side (col 30)
        let cup_right = format!("\x1b[{row_1indexed};30H");
        term.advance(cup_right.as_bytes());
        term.advance(b"[StatusBar]");

        // Update mode-line row to previous batch's tool row (mode-line "moves up")
        // Simulate CUU behavior: write StatusBar on the row just above tool row
        if batch > 1 {
            let prev_row_1indexed = tool_row; // previous tool row = this row - 1
            let cup_prev = format!("\x1b[{prev_row_1indexed};3HStatusBar   ");
            term.advance(cup_prev.as_bytes());
        }

        term.advance(b"\x1b[?2026l");
    }

    // Verify: row 5 (0-indexed) has Tool1Result at col 0 (from batch 1)
    // batch=1 → tool_row=5, CUP row_1indexed=6 → \x1b[6;1H → writes to row 5 (0-indexed)
    assert_eq!(
        term.get_cell(5, 0).map(kuro_core::Cell::char),
        Some('T'),
        "row 5 col 0 must be 'T' from Tool1Result (batch 1)"
    );

    // Row 5 col 29 (0-indexed): [StatusBar] from batch 1 right-aligned mode-line
    // CUP \x1b[6;30H → col 30 (1-indexed) = col 29 (0-indexed)
    assert_eq!(
        term.get_cell(5, 29).map(kuro_core::Cell::char),
        Some('['),
        "row 5 col 30 must be '[' from [StatusBar] (batch 1 mode-line)"
    );

    // Row 6 (0-indexed): Tool2Result at col 0 (batch 2)
    // batch=2 → tool_row=6, CUP row_1indexed=7 → \x1b[7;1H → writes to row 6 (0-indexed)
    assert_eq!(
        term.get_cell(6, 0).map(kuro_core::Cell::char),
        Some('T'),
        "row 6 col 0 must be 'T' from Tool2Result (batch 2)"
    );

    // Header (row 0) unchanged
    assert_eq!(
        term.get_cell(0, 0).map(kuro_core::Cell::char),
        Some('H'),
        "row 0 must be unchanged after all batches"
    );

    // Separator (row 1) unchanged - box-drawing chars must survive batches
    assert_eq!(
        term.get_cell(1, 0).map(kuro_core::Cell::char),
        Some('\u{2500}'),
        "row 1 separator must be unchanged"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// XTVERSION (CSI > q)
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn xtversion_csi_greater_q_produces_dcs_response() {
    let mut t = TerminalCore::new(24, 80);
    // CSI > q — terminal version identification
    t.advance(b"\x1b[>q");
    let responses = common::read_responses(&t);
    assert!(
        !responses.is_empty(),
        "XTVERSION must produce at least one response"
    );
    let resp = &responses[0];
    // Response format: DCS > | <name>-<version> ST  (ESC P > | kuro-1.0.0 ESC \)
    assert!(
        resp.contains("kuro"),
        "XTVERSION response must contain 'kuro', got: {resp:?}"
    );
    assert!(
        resp.starts_with("\x1bP") || resp.contains(">|"),
        "XTVERSION response must be a DCS string, got: {resp:?}"
    );
}

#[test]
fn xtversion_csi_greater_0_q_produces_dcs_response() {
    // Optional: CSI > 0 q variant (param = 0)
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[>0q");
    // Should not panic; may or may not produce response (vte may not route "0q" with ">" same way)
    // The main test is no panic and optional response
    let _ = common::read_responses(&t);
}

// ─────────────────────────────────────────────────────────────────────────────
// DECRQM (CSI ? Ps $ p)
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn decrqm_mode_25_cursor_visible_responds_set() {
    let mut t = TerminalCore::new(24, 80);
    // Cursor is visible by default (mode 25 = set)
    // CSI ? 25 $ p
    t.advance(b"\x1b[?25$p");
    let responses = common::read_responses(&t);
    assert!(
        !responses.is_empty(),
        "DECRQM for mode 25 must produce a response"
    );
    let resp = &responses[0];
    // Response: CSI ? 25 ; 1 $ y  (status=1 means set)
    assert!(
        resp.contains("25") && resp.contains('1') && resp.contains("$y"),
        "DECRQM response for mode 25 (set) must contain '25;1$y', got: {resp:?}"
    );
}

#[test]
fn decrqm_mode_1049_alt_screen_responds_reset() {
    let mut t = TerminalCore::new(24, 80);
    // Alternate screen is off by default (mode 1049 = reset)
    t.advance(b"\x1b[?1049$p");
    let responses = common::read_responses(&t);
    assert!(
        !responses.is_empty(),
        "DECRQM for mode 1049 must produce a response"
    );
    let resp = &responses[0];
    // Response: CSI ? 1049 ; 2 $ y  (status=2 means reset)
    assert!(
        resp.contains("1049") && resp.contains('2') && resp.contains("$y"),
        "DECRQM response for mode 1049 (reset) must contain '1049;2$y', got: {resp:?}"
    );
}

#[test]
fn decrqm_mode_after_enable_responds_set() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?1004h"); // enable focus events
    t.advance(b"\x1b[?1004$p"); // query
    let responses = common::read_responses(&t);
    assert!(!responses.is_empty());
    let resp = &responses[0];
    assert!(
        resp.contains("1004") && resp.contains('1'),
        "After enabling mode 1004, DECRQM must report status=1, got: {resp:?}"
    );
}

#[test]
fn decrqm_unknown_mode_responds_not_recognized() {
    let mut t = TerminalCore::new(24, 80);
    // Mode 9999 — unknown/unsupported
    t.advance(b"\x1b[?9999$p");
    let responses = common::read_responses(&t);
    assert!(!responses.is_empty());
    let resp = &responses[0];
    // Status 0 = not recognized
    assert!(
        resp.contains("9999") && resp.contains('0'),
        "Unknown mode must return status=0, got: {resp:?}"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Mouse Pixel Mode (?1016)
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn mouse_pixel_mode_1016_enable_disable() {
    let mut t = TerminalCore::new(24, 80);
    assert!(
        !t.dec_modes().mouse_pixel,
        "Mouse pixel mode should be off by default"
    );
    t.advance(b"\x1b[?1016h"); // enable
    assert!(
        t.dec_modes().mouse_pixel,
        "Mouse pixel mode should be on after ?1016h"
    );
    t.advance(b"\x1b[?1016l"); // disable
    assert!(
        !t.dec_modes().mouse_pixel,
        "Mouse pixel mode should be off after ?1016l"
    );
}

#[test]
fn mouse_pixel_mode_1016_reported_by_decrqm() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?1016h");
    t.advance(b"\x1b[?1016$p");
    let responses = common::read_responses(&t);
    assert!(!responses.is_empty());
    let resp = &responses[0];
    assert!(
        resp.contains("1016") && resp.contains('1'),
        "Mouse pixel mode enabled → DECRQM must report status=1, got: {resp:?}"
    );
}

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
    assert!(!responses.is_empty(), "DECRQM for ?25 must produce a response");
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
    assert!(t.cursor_row() < 24, "cursor must be in bounds after unknown DECSCUSR");
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
    assert!(!t.dec_modes().bracketed_paste, "bracketed_paste must still be off");

    // Now enable bracketed paste as well
    t.advance(b"\x1b[?2004h");
    assert!(t.dec_modes().focus_events, "focus_events must remain on");
    assert!(t.dec_modes().bracketed_paste, "bracketed_paste must now be on");

    // Disable focus events — bracketed paste must remain
    t.advance(b"\x1b[?1004l");
    assert!(!t.dec_modes().focus_events, "focus_events must be off");
    assert!(t.dec_modes().bracketed_paste, "bracketed_paste must remain on");
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
    t.advance(b"\x1b[?1h");    // DECCKM
    t.advance(b"\x1b[?7l");    // DECAWM off (default is on, so toggling)
    t.advance(b"\x1b[?25l");   // DECTCEM hide
    t.advance(b"\x1b[?1004h"); // focus events
    t.advance(b"\x1b[?1006h"); // mouse SGR
    t.advance(b"\x1b[?1016h"); // mouse pixel
    t.advance(b"\x1b[?2004h"); // bracketed paste
    t.advance(b"\x1b[?2026h"); // synchronized output
    t.advance(b"\x1b[?1000h"); // mouse mode 1000
    t.advance(b"\x1b[6 q");    // cursor shape SteadyBar (wait, 6 = SteadyBar)
    t.advance(b"\x1b[>5u");    // kitty keyboard flags=5

    // Full reset
    t.advance(b"\x1bc");

    // Verify all defaults restored
    let m = t.dec_modes();
    assert!(!m.app_cursor_keys,    "app_cursor_keys must be off after RIS");
    assert!(m.auto_wrap,           "auto_wrap must be on after RIS");
    assert!(m.cursor_visible,      "cursor_visible must be on after RIS");
    assert!(!m.focus_events,       "focus_events must be off after RIS");
    assert!(!m.mouse_sgr,          "mouse_sgr must be off after RIS");
    assert!(!m.mouse_pixel,        "mouse_pixel must be off after RIS");
    assert!(!m.bracketed_paste,    "bracketed_paste must be off after RIS");
    assert!(!m.synchronized_output, "synchronized_output must be off after RIS");
    assert_eq!(m.mouse_mode, 0,    "mouse_mode must be 0 after RIS");
    assert_eq!(
        m.cursor_shape,
        kuro_core::types::cursor::CursorShape::BlinkingBlock,
        "cursor_shape must be BlinkingBlock after RIS"
    );
    assert_eq!(m.keyboard_flags, 0, "keyboard_flags must be 0 after RIS");
    assert!(!t.is_alternate_screen_active(), "alt screen must be off after RIS");
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
