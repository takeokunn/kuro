//! Integration tests for DEC private modes.

mod common;

use kuro_core::TerminalCore;

// ─────────────────────────────────────────────────────────────────────────────
// Synchronized Output mode (?2026) — regression tests for claude-code rendering
//
// Background: claude-code (and other TUI apps) use DEC ?2026 to batch-update
// the terminal screen atomically.  Kuro's 60fps render timer must NOT flush
// partial frames while a sync batch is open; doing so produces garbled output
// like "⏺─Hello! How can─I─help─you─today?─" (separator chars leaking into text).
//
// These tests cover:
//   1. Basic state toggling (?2026h / ?2026l)
//   2. Grid content preserved during sync
//   3. mark_all_dirty triggered on ?2026l (tested via abstraction layer unit tests)
//   4. The claude-code startup sequence pattern
// ─────────────────────────────────────────────────────────────────────────────

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
    assert!(
        !term.bracketed_paste(),
        "Bracketed paste should be disabled"
    );
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
    assert!(term.cursor_visible(), "Cursor should be visible after RIS");
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
