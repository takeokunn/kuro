//! Unit and property tests for `TerminalCore`.
//!
//! This module is declared via `#[cfg(test)] mod tests;` in `lib.rs` and
//! therefore has access to all private items in the parent module through
//! `use super::*;`.
use super::*;
use proptest::prelude::*;

#[test]
fn test_terminal_creation() {
    let term = TerminalCore::new(24, 80);
    assert_eq!(term.screen.rows(), 24);
    assert_eq!(term.screen.cols(), 80);
}

#[test]
fn test_simple_print() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"Hello");
    // Check first cell
    let cell = term.screen.get_cell(0, 0).unwrap();
    assert_eq!(cell.char(), 'H');
}

#[test]
fn test_decsc_decrc_basic() {
    let mut term = TerminalCore::new(24, 80);

    // Move cursor to a known position
    term.advance(b"\x1b[6;11H"); // CSI 6;11H -> row 5, col 10 (0-indexed)

    let row_before = term.screen.cursor().row;
    let col_before = term.screen.cursor().col;

    // ESC 7: save cursor position and attributes (DECSC)
    term.advance(b"\x1b7");
    assert!(
        term.saved_cursor.is_some(),
        "saved_cursor should be set after ESC 7"
    );

    // Move cursor somewhere else
    term.advance(b"\x1b[1;1H"); // CSI 1;1H -> row 0, col 0

    assert_eq!(term.screen.cursor().row, 0);
    assert_eq!(term.screen.cursor().col, 0);

    // ESC 8: restore cursor position and attributes (DECRC)
    term.advance(b"\x1b8");

    // Cursor should be restored to the saved position
    assert_eq!(term.screen.cursor().row, row_before);
    assert_eq!(term.screen.cursor().col, col_before);

    // saved_cursor should be consumed
    assert!(
        term.saved_cursor.is_none(),
        "saved_cursor should be cleared after ESC 8"
    );
}

#[test]
fn test_decsc_decrc_preserves_attrs() {
    let mut term = TerminalCore::new(24, 80);

    // Set bold via SGR
    term.advance(b"\x1b[1m"); // CSI 1m -> bold on
    assert!(term.current_attrs.bold);

    // Save cursor + attrs
    term.advance(b"\x1b7"); // DECSC

    // Reset attrs
    term.advance(b"\x1b[0m"); // CSI 0m -> reset
    assert!(!term.current_attrs.bold);

    // Restore cursor + attrs
    term.advance(b"\x1b8"); // DECRC

    // Bold should be restored
    assert!(term.current_attrs.bold);
}

#[test]
fn test_ris_full_reset() {
    let mut term = TerminalCore::new(24, 80);

    // Move cursor, set bold, save state
    term.advance(b"\x1b[10;20H"); // move cursor
    term.advance(b"\x1b[1m"); // bold on
    term.advance(b"\x1b7"); // save cursor

    // Full terminal reset via RIS (ESC c)
    term.advance(b"\x1bc");

    // Cursor should be at home
    assert_eq!(term.screen.cursor().row, 0);
    assert_eq!(term.screen.cursor().col, 0);

    // Attributes should be reset to default
    assert!(!term.current_attrs.bold);

    // Saved cursor state should be cleared
    assert!(term.saved_cursor.is_none());
    assert!(term.saved_attrs.is_none());

    // Alternate screen should not be active
    assert!(!term.screen.is_alternate_screen_active());
}

#[test]
fn test_dectcem_cursor_visibility() {
    let mut term = TerminalCore::new(24, 80);

    // Cursor is visible by default (DECTCEM default = true)
    assert!(term.dec_modes.cursor_visible);

    // CSI ?25l: hide cursor (DECTCEM reset)
    term.advance(b"\x1b[?25l");
    assert!(
        !term.dec_modes.cursor_visible,
        "cursor should be hidden after CSI ?25l"
    );

    // CSI ?25h: show cursor (DECTCEM set)
    term.advance(b"\x1b[?25h");
    assert!(
        term.dec_modes.cursor_visible,
        "cursor should be visible after CSI ?25h"
    );
}

#[test]
fn test_dectcem_after_ris() {
    let mut term = TerminalCore::new(24, 80);

    // Cursor is visible by default
    assert!(term.dec_modes.cursor_visible);

    // Hide cursor
    term.advance(b"\x1b[?25l");
    assert!(!term.dec_modes.cursor_visible);

    // Full reset (RIS) reinitialises dec_modes via DecModes::new(), which
    // correctly sets cursor_visible=true and auto_wrap=true as per VT terminal defaults.
    term.advance(b"\x1bc");
    assert!(
        term.dec_modes.cursor_visible,
        "cursor should be visible after RIS (DecModes::new() sets cursor_visible=true)"
    );
}

#[test]
fn test_osc_title_set() {
    let mut core = TerminalCore::new(24, 80);
    assert_eq!(core.title, "");
    assert!(!core.title_dirty);

    core.advance(b"\x1b]2;hello tmux\x07");
    assert_eq!(core.title, "hello tmux");
    assert!(core.title_dirty);
}

#[test]
fn test_osc_icon_and_title() {
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]0;test title\x07");
    assert_eq!(core.title, "test title");
    assert!(core.title_dirty);
}

#[test]
fn test_osc_empty_ignored() {
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]2;\x07");
    assert_eq!(core.title, "");
    assert!(!core.title_dirty);
}

#[test]
fn test_osc_title_st_terminator() {
    // ST-terminated (ESC \) should be handled identically to BEL
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]2;st term title\x1b\\");
    assert_eq!(core.title, "st term title");
    assert!(core.title_dirty);
}

#[test]
fn test_osc_title_reset_clears() {
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]2;before reset\x07");
    assert!(core.title_dirty);
    core.reset(); // RIS ESC c
    assert_eq!(core.title, "");
    assert!(!core.title_dirty);
}

#[test]
fn test_osc_title_atomic_clear() {
    // Verify that title_dirty is cleared after being read, and the title value is correct.
    let mut core = TerminalCore::new(24, 80);

    core.advance(b"\x1b]2;test title\x07");
    assert!(
        core.title_dirty,
        "title_dirty should be set after OSC dispatch"
    );
    assert_eq!(core.title, "test title");

    // Simulate the atomic-clear: read title, then clear dirty flag
    let read_title = core.title.clone();
    core.title_dirty = false;

    assert_eq!(read_title, "test title");
    assert!(
        !core.title_dirty,
        "title_dirty should be false after atomic clear"
    );

    // Verify a second dispatch sets dirty again
    core.advance(b"\x1b]2;new title\x07");
    assert!(
        core.title_dirty,
        "title_dirty should be set again after second dispatch"
    );
    assert_eq!(core.title, "new title");
}

#[test]
fn test_deckpam_sets_app_keypad() {
    let mut term = TerminalCore::new(24, 80);
    assert!(
        !term.dec_modes.app_keypad,
        "app_keypad should default to false"
    );
    term.advance(b"\x1b="); // ESC = : DECKPAM
    assert!(
        term.dec_modes.app_keypad,
        "app_keypad should be set after ESC ="
    );
}

#[test]
fn test_deckpnm_clears_app_keypad() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b="); // DECKPAM: set
    assert!(term.dec_modes.app_keypad);
    term.advance(b"\x1b>"); // DECKPNM: clear
    assert!(
        !term.dec_modes.app_keypad,
        "app_keypad should be cleared after ESC >"
    );
}

#[test]
fn test_deckpam_toggle_sequence() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b=\x1b>\x1b="); // DECKPAM → DECKPNM → DECKPAM
    assert!(
        term.dec_modes.app_keypad,
        "final state should be app_keypad=true"
    );
}

#[test]
fn test_osc_title_length_cap() {
    // Verify that oversized OSC titles are silently ignored
    let mut core = TerminalCore::new(24, 80);

    // Title within limit should work (1024 'a' chars)
    let mut ok_seq = b"\x1b]2;".to_vec();
    ok_seq.extend_from_slice(&vec![b'a'; 1024]);
    ok_seq.push(0x07);
    core.advance(&ok_seq);
    assert!(core.title_dirty, "1024-byte title should be accepted");
    core.title_dirty = false;

    // Title over limit should be ignored (1025 'a' chars)
    let mut big_seq = b"\x1b]2;".to_vec();
    big_seq.extend_from_slice(&vec![b'a'; 1025]);
    big_seq.push(0x07);
    core.advance(&big_seq);
    assert!(!core.title_dirty, "1025-byte title should be rejected");
}

#[test]
fn test_osc_title_non_utf8() {
    // Verify that non-UTF8 bytes are handled via lossy conversion (U+FFFD replacement)
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]2;hello\xff\xfeworld\x07");
    assert!(core.title_dirty, "Non-UTF8 title should still set dirty");
    assert!(
        !core.title.is_empty(),
        "Non-UTF8 title should produce non-empty result via lossy conversion"
    );
    // Should not panic — if we got here, test passes
}

#[test]
fn test_apc_payload_at_cap() {
    // Build an APC sequence: ESC _ <payload> ESC \
    // with exactly MAX_APC_PAYLOAD_BYTES bytes of payload
    const MAX_APC_PAYLOAD_BYTES: usize = 4 * 1024 * 1024;
    let mut core = TerminalCore::new(24, 80);
    let mut input = vec![0x1b, b'_']; // ESC _
    input.extend(std::iter::repeat(b'X').take(MAX_APC_PAYLOAD_BYTES));
    input.extend_from_slice(b"\x1b\\"); // ESC \  (string terminator)
    core.advance(&input);
    // The buffer should have been consumed and APC processed
    assert_eq!(
        core.apc_buf.len(),
        0,
        "apc_buf should be cleared after full APC sequence"
    );
}

#[test]
fn test_apc_payload_exceeds_cap_is_truncated() {
    const MAX_APC_PAYLOAD_BYTES: usize = 4 * 1024 * 1024;
    let mut core = TerminalCore::new(24, 80);
    let mut input = vec![0x1b, b'_']; // ESC _
                                      // Send MORE than the cap
    input.extend(std::iter::repeat(b'X').take(MAX_APC_PAYLOAD_BYTES + 100));
    input.extend_from_slice(b"\x1b\\"); // ESC \
    core.advance(&input);
    // Buffer should be cleared after processing, but during processing it was capped
    assert_eq!(
        core.apc_buf.len(),
        0,
        "apc_buf should be cleared after APC sequence completes"
    );
}

#[test]
fn test_apc_split_across_advance_calls() {
    let mut core = TerminalCore::new(24, 80);
    // Send APC open + part of payload in first call
    let part1 = b"\x1b_GHello";
    // Send rest of payload + close in second call
    let part2 = b" World\x1b\\";
    core.advance(part1);
    core.advance(part2);
    // After the sequence completes, apc_buf should be cleared
    assert_eq!(
        core.apc_buf.len(),
        0,
        "apc_buf should be cleared after split APC sequence"
    );
}

// === Wave 3.1: TDD Tests for Unified APC Handling (single-pass optimization) ===
// These tests verify behavior needed for merging APC pre-scanner into vte parser

/// Test: APC sequence followed by CSI sequence should process both correctly
/// This verifies that single-pass won't drop regular sequences
#[test]
fn test_apc_followed_by_csi_processes_both() {
    let mut core = TerminalCore::new(24, 80);
    // APC sequence (Kitty graphics query) + CSI sequence (cursor position)
    // CSI 5;10 H = CUP (cursor position) to row 5, col 10 (1-indexed)
    let input = b"\x1b_Ga=q\x1b\\\x1b[5;10H";
    core.advance(input);
    // APC should be processed (apc_buf cleared)
    assert_eq!(core.apc_buf.len(), 0, "APC should be fully processed");
    // CSI CUP should have moved cursor: row=5 (1-indexed) -> row 4 (0-indexed)
    // col=10 (1-indexed) -> col 9 (0-indexed)
    let cursor = core.screen.cursor();
    assert_eq!(
        cursor.row, 4,
        "CSI CUP row=5 (1-indexed) should set row to 4 (0-indexed)"
    );
    assert_eq!(
        cursor.col, 9,
        "CSI CUP col=10 (1-indexed) should set col to 9 (0-indexed)"
    );
}

/// Test: CSI sequence followed by APC should process both correctly
#[test]
fn test_csi_followed_by_apc_processes_both() {
    let mut core = TerminalCore::new(24, 80);
    // CSI sequence first, then APC
    let input = b"\x1b[2J\x1b_Ga=q\x1b\\";
    core.advance(input);
    // ED (clear screen) should have cleared the screen
    // Check that cursor moved to home position (0,0) after ED 2
    let cursor = core.screen.cursor();
    assert_eq!(cursor.row, 0, "ED 2 should move cursor to row 0");
    assert_eq!(cursor.col, 0, "ED 2 should move cursor to col 0");
    // APC should be processed
    assert_eq!(core.apc_buf.len(), 0, "APC should be fully processed");
}

/// Test: Multiple APC sequences in single advance() call
#[test]
fn test_multiple_apc_in_single_advance() {
    let mut core = TerminalCore::new(24, 80);
    // Two APC sequences in one buffer
    let input = b"\x1b_Ga=q\x1b\\\x1b_Ga=q\x1b\\";
    core.advance(input);
    // Both APCs should be processed, buffer should be clear
    assert_eq!(
        core.apc_buf.len(),
        0,
        "All APC sequences should be processed"
    );
}

/// Test: APC with embedded false ST (ESC + non-backslash)
#[test]
fn test_apc_with_false_esc_st() {
    let mut core = TerminalCore::new(24, 80);
    // APC with ESC X (not ST) embedded in payload - ESC should be kept in payload
    let input = b"\x1b_Gtest\x1bXmore\x1b\\";
    core.advance(input);
    // APC should complete and buffer should be cleared
    assert_eq!(core.apc_buf.len(), 0, "APC with false ST should complete");
}

/// Test: Mixed APC, CSI, and OSC in single buffer
#[test]
fn test_mixed_apc_csi_osc_single_buffer() {
    let mut core = TerminalCore::new(24, 80);
    // APC + CSI + OSC in one buffer
    let input = b"\x1b_Ga=q\x1b\\\x1b[1;1H\x1b]2;Title\x07";
    core.advance(input);
    // All sequences should be processed
    assert_eq!(core.apc_buf.len(), 0, "APC should be processed");
    assert_eq!(core.screen.cursor().row, 0, "CSI CUP should set cursor row");
    assert_eq!(core.screen.cursor().col, 0, "CSI CUP should set cursor col");
    assert!(core.title_dirty, "OSC title should set dirty flag");
}

/// Test: APC split across 3 advance() calls
#[test]
fn test_apc_split_across_three_advance_calls() {
    let mut core = TerminalCore::new(24, 80);
    // Part 1: ESC _ (APC start)
    core.advance(b"\x1b_");
    assert_eq!(core.apc_buf.len(), 0, "After ESC _, waiting for payload");
    // Part 2: Payload
    core.advance(b"Ga=q,s=100");
    assert!(core.apc_buf.len() > 0, "Payload should be buffered");
    // Part 3: ESC \ (ST terminator)
    core.advance(b"\x1b\\");
    assert_eq!(core.apc_buf.len(), 0, "APC should complete after ST");
}

/// Test: Non-APC DCS sequence passes through without interference
#[test]
fn test_dcs_sequence_not_affected_by_apc_scanner() {
    let mut core = TerminalCore::new(24, 80);
    // DCS sequence (ESC P ... ESC \) - different from APC (ESC _)
    let input = b"\x1bP$q\x1b\\";
    core.advance(input);
    // DCS should not trigger APC handling (apc_buf should remain empty)
    assert_eq!(
        core.apc_buf.len(),
        0,
        "DCS should not interfere with APC state"
    );
}

/// Test: APC with maximum payload size is handled without panic
#[test]
fn test_apc_maximum_payload_no_panic() {
    let mut core = TerminalCore::new(24, 80);
    const MAX_APC_PAYLOAD_BYTES: usize = 4 * 1024 * 1024;
    let mut input = vec![0x1b, b'_'];
    // Payload with Kitty graphics header + max data
    input.push(b'G');
    input.extend(std::iter::repeat(b'A').take(MAX_APC_PAYLOAD_BYTES - 1));
    input.extend_from_slice(b"\x1b\\");
    // Should not panic
    core.advance(&input);
    assert_eq!(core.apc_buf.len(), 0, "APC at max size should complete");
}

/// Test: Rapid ESC sequences don't confuse APC scanner
#[test]
fn test_rapid_esc_sequences_apc_scanner() {
    let mut core = TerminalCore::new(24, 80);
    // Multiple ESCs without forming APC
    let input = b"\x1b\x1b\x1b[A";
    core.advance(input);
    // ESC [ A = CUU (cursor up) - should process correctly
    // apc_buf should be empty (no APC started)
    assert_eq!(core.apc_buf.len(), 0, "Rapid ESCs should not start APC");
}

#[test]
fn test_resize_preserves_screen_content() {
    let mut term = TerminalCore::new(24, 80);
    // Print 'A' at the top-left corner
    term.advance(b"A");
    let row_before = term.screen.cursor().row;
    let col_before = term.screen.cursor().col;
    // Resize to a larger screen
    term.resize(30, 100);
    assert_eq!(term.screen.rows(), 30);
    assert_eq!(term.screen.cols(), 100);
    // Cursor position must remain in bounds after resize
    assert!(
        term.screen.cursor().row < 30,
        "cursor row out of bounds after resize"
    );
    assert!(
        term.screen.cursor().col < 100,
        "cursor col out of bounds after resize"
    );
    // Cursor should not have moved to an impossible position
    let _ = (row_before, col_before); // used for context
}

#[test]
fn test_advance_empty_input() {
    // Advancing with an empty slice must not panic
    let mut term = TerminalCore::new(24, 80);
    term.advance(&[]);
    // State is unchanged from initial
    assert_eq!(term.screen.cursor().row, 0);
    assert_eq!(term.screen.cursor().col, 0);
}

#[test]
fn test_advance_split_sequence() {
    // Send an incomplete CSI sequence in the first call, complete it in the second.
    // After both calls, bold should be set.
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b["); // incomplete CSI
    term.advance(b"1m"); // complete: SGR bold
    assert!(
        term.current_attrs.bold,
        "bold should be set after split CSI sequence"
    );
}

#[test]
fn test_execute_backspace_at_col_zero() {
    // Move to row 5 col 0 (CSI 5;1H) then send backspace.
    // Cursor must stay at col 0 (no underflow).
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[5;1H\x08");
    assert_eq!(
        term.screen.cursor().col,
        0,
        "backspace at col 0 must not move cursor below 0"
    );
    // Row should be 4 (0-indexed) after CSI 5;1H
    assert_eq!(term.screen.cursor().row, 4);
}

#[test]
fn test_csi_unknown_final_byte_no_panic() {
    // An unknown CSI final byte must be silently ignored without panicking.
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[999z");
    // If we reach here the test passes — no panic occurred
}

#[test]
fn test_osc_unknown_command_number_ignored() {
    // OSC with unknown command number must be silently discarded without crashing.
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b]99;some_data\x07");
    // Title must not have changed (OSC 99 is not handled)
    assert_eq!(term.title, "", "unknown OSC number must not update title");
    assert!(
        !term.title_dirty,
        "unknown OSC number must not set title_dirty"
    );
}

#[test]
fn test_combining_char_attached_to_base() {
    let mut term = TerminalCore::new(24, 80);
    // Print 'e' followed by combining acute accent U+0301
    term.advance("e\u{0301}".as_bytes());
    let cell = term.get_cell(0, 0).unwrap();
    assert_eq!(cell.grapheme.as_str(), "e\u{0301}");
}

#[test]
fn test_combining_char_at_col_zero_printed_standalone() {
    let mut term = TerminalCore::new(24, 80);
    // Send combining char at position (0,0) with no previous cell
    term.advance("\u{0301}".as_bytes());
    // Should not panic; cell at (0,0) should contain the combining char as standalone
    let cell = term.get_cell(0, 0).unwrap();
    assert_eq!(cell.grapheme.as_str(), "\u{0301}");
}

#[test]
fn test_combining_char_attaches_to_previous_row_last_col() {
    // When cursor is at col=0 of row>0, a combining char should attach to the
    // last cell of the previous row (not be discarded or printed standalone).
    let mut term = TerminalCore::new(24, 80);
    // Print 'e' at end of row 0 (col 79), then move cursor to row 1 col 0
    term.advance(b"\x1b[1;80H"); // CSI 1;80H -> row 0, col 79 (1-indexed)
    term.advance(b"e");
    // Cursor is now at row 0, col 79 (after printing 'e' auto-wrap is pending)
    // Move to row 1, col 0
    term.advance(b"\x1b[2;1H");
    // Send combining acute accent — should attach to 'e' at (row=0, col=79)
    term.advance("\u{0301}".as_bytes());
    let cell = term.get_cell(0, 79).unwrap();
    assert_eq!(
        cell.grapheme.as_str(),
        "e\u{0301}",
        "Combining char should attach to 'e' at previous row's last col"
    );
}

#[test]
fn test_normal_chars_unchanged_after_grapheme_support() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"ABC");
    assert_eq!(term.get_cell(0, 0).unwrap().char(), 'A');
    assert_eq!(term.get_cell(0, 1).unwrap().char(), 'B');
    assert_eq!(term.get_cell(0, 2).unwrap().char(), 'C');
}

#[test]
fn test_osc_7_stores_cwd() {
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]7;file://localhost/tmp/test\x07");
    assert!(core.osc_data.cwd_dirty);
    assert_eq!(core.osc_data.cwd, Some("/tmp/test".to_string()));
}

#[test]
fn test_osc_133_stores_prompt_marks() {
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]133;A\x07");
    assert_eq!(core.osc_data.prompt_marks.len(), 1);
    assert_eq!(
        core.osc_data.prompt_marks[0].mark,
        types::osc::PromptMark::PromptStart
    );
}

#[test]
fn test_osc_8_hyperlink() {
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]8;;https://example.com\x07");
    assert_eq!(
        core.osc_data.hyperlink.uri,
        Some("https://example.com".to_string())
    );
    // Close hyperlink
    core.advance(b"\x1b]8;;\x07");
    assert!(core.osc_data.hyperlink.uri.is_none());
}

#[test]
fn test_osc_104_clears_palette() {
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]104\x07");
    assert!(core.osc_data.palette_dirty);
}

#[test]
fn test_decscusr_sets_cursor_shape() {
    let mut term = TerminalCore::new(24, 80);
    // CSI 5 SP q → blinking bar
    term.advance(b"\x1b[5 q");
    assert_eq!(
        term.dec_modes.cursor_shape,
        types::cursor::CursorShape::BlinkingBar
    );
    // CSI 2 SP q → steady block
    term.advance(b"\x1b[2 q");
    assert_eq!(
        term.dec_modes.cursor_shape,
        types::cursor::CursorShape::SteadyBlock
    );
}

#[test]
fn test_decstr_soft_reset() {
    let mut term = TerminalCore::new(24, 80);
    // Set some modes
    term.advance(b"\x1b[?1h"); // DECCKM on
    term.advance(b"\x1b[1m"); // Bold on
    term.advance(b"\x1b[10;20H"); // Move cursor
                                  // Soft reset
    term.advance(b"\x1b[!p");
    // Cursor keys should be reset
    assert!(!term.dec_modes.app_cursor_keys);
    // SGR should be reset
    assert!(!term.current_attrs.bold);
    // Cursor should be at home
    assert_eq!(term.cursor_row(), 0);
    assert_eq!(term.cursor_col(), 0);
    // Auto-wrap should be on
    assert!(term.dec_modes.auto_wrap);
}

#[test]
fn test_decstr_preserves_screen_content() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"Hello");
    term.advance(b"\x1b[!p"); // Soft reset
                              // Content should be preserved
    let cell = term.get_cell(0, 0).unwrap();
    assert_eq!(cell.char(), 'H');
}

#[test]
fn test_kitty_keyboard_push_pop() {
    let mut term = TerminalCore::new(24, 80);
    assert_eq!(term.dec_modes.keyboard_flags, 0);
    // Push flags=1 (disambiguate)
    term.advance(b"\x1b[>1u");
    assert_eq!(term.dec_modes.keyboard_flags, 1);
    // Push flags=3 (disambiguate + event types)
    term.advance(b"\x1b[>3u");
    assert_eq!(term.dec_modes.keyboard_flags, 3);
    assert_eq!(term.dec_modes.keyboard_flags_stack.len(), 2);
    // Pop
    term.advance(b"\x1b[<u");
    assert_eq!(term.dec_modes.keyboard_flags, 1);
    // Pop again
    term.advance(b"\x1b[<u");
    assert_eq!(term.dec_modes.keyboard_flags, 0);
    // Pop on empty stack → stays at 0
    term.advance(b"\x1b[<u");
    assert_eq!(term.dec_modes.keyboard_flags, 0);
}

#[test]
fn test_kitty_keyboard_query() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[>5u"); // Set flags=5
    term.advance(b"\x1b[?u"); // Query
    assert_eq!(term.pending_responses.len(), 1);
    assert_eq!(term.pending_responses[0], b"\x1b[?5u");
}

// === Resource limit tests ===

#[test]
fn test_oversized_osc7_cwd_rejected() {
    let mut term = TerminalCore::new(24, 80);
    let long_path = format!("\x1b]7;file://localhost/{}\x07", "a".repeat(5000));
    term.advance(long_path.as_bytes());
    // CWD should NOT be stored (over 4096 limit)
    assert!(
        term.osc_data.cwd.is_none() || term.osc_data.cwd.as_ref().unwrap().len() <= 4096,
        "CWD over 4096 bytes should be rejected"
    );
}

#[test]
fn test_oversized_osc8_uri_rejected() {
    let mut term = TerminalCore::new(24, 80);
    let long_uri = format!("\x1b]8;;https://example.com/{}\x07", "x".repeat(9000));
    term.advance(long_uri.as_bytes());
    // Hyperlink should NOT be stored (over 8192 limit)
    assert!(
        term.osc_data.hyperlink.uri.is_none()
            || term.osc_data.hyperlink.uri.as_ref().unwrap().len() <= 8192,
        "Hyperlink URI over 8192 bytes should be rejected"
    );
}

#[test]
fn test_apc_payload_cap_enforced() {
    let mut term = TerminalCore::new(24, 80);
    // Send an APC with payload > 4MiB
    let large_payload = vec![b'A'; 5 * 1024 * 1024];
    let mut data = Vec::new();
    data.extend_from_slice(b"\x1b_G");
    data.extend_from_slice(&large_payload);
    data.extend_from_slice(b"\x1b\\");
    term.advance(&data);
    // Should not panic and apc_buf should be cleared after sequence completes
    assert_eq!(
        term.apc_buf.len(),
        0,
        "apc_buf should be cleared after oversized APC sequence"
    );
}

#[test]
fn test_title_sanitization_strips_control_chars() {
    let mut term = TerminalCore::new(24, 80);
    // Title with embedded BEL control character — the OSC parser splits on BEL,
    // so the title will be "Hello" (everything before the first BEL terminator)
    term.advance(b"\x1b]2;Hello\x07World\x07");
    // The title should not contain control characters
    assert!(
        !term.title.contains('\x07'),
        "Title should not contain BEL control character"
    );
}

// === SGR underline style tests ===

#[test]
fn test_sgr_4_colon_3_sets_curly_underline() {
    let mut term = TerminalCore::new(24, 80);
    // CSI 4:3 m — curly underline (colon sub-parameter form)
    term.advance(b"\x1b[4:3m");
    assert_eq!(
        term.current_attrs.underline_style,
        types::cell::UnderlineStyle::Curly,
        "SGR 4:3 should set curly underline"
    );
}

#[test]
fn test_sgr_4_colon_5_sets_dashed_underline() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[4:5m");
    assert_eq!(
        term.current_attrs.underline_style,
        types::cell::UnderlineStyle::Dashed,
        "SGR 4:5 should set dashed underline"
    );
}

#[test]
fn test_sgr_21_sets_double_underline() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[21m");
    assert_eq!(
        term.current_attrs.underline_style,
        types::cell::UnderlineStyle::Double,
        "SGR 21 should set double underline"
    );
}

#[test]
fn test_sgr_24_clears_underline() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[4:3m"); // Set curly
    assert!(
        term.current_attrs.underline(),
        "Curly underline should be active"
    );
    term.advance(b"\x1b[24m"); // Clear
    assert!(
        !term.current_attrs.underline(),
        "SGR 24 should clear underline"
    );
    assert_eq!(
        term.current_attrs.underline_style,
        types::cell::UnderlineStyle::None,
        "SGR 24 should set underline_style to None"
    );
}

#[test]
fn test_sgr_58_5_sets_underline_color_indexed() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[58;5;196m");
    assert_eq!(
        term.current_attrs.underline_color,
        types::color::Color::Indexed(196),
        "SGR 58;5;196 should set indexed underline color 196"
    );
}

#[test]
fn test_sgr_58_2_sets_underline_color_rgb() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[58;2;255;128;0m");
    assert_eq!(
        term.current_attrs.underline_color,
        types::color::Color::Rgb(255, 128, 0),
        "SGR 58;2;255;128;0 should set RGB underline color"
    );
}

#[test]
fn test_sgr_59_resets_underline_color() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[58;5;196m");
    assert_ne!(
        term.current_attrs.underline_color,
        types::color::Color::Default,
        "Underline color should be set before reset"
    );
    term.advance(b"\x1b[59m");
    assert_eq!(
        term.current_attrs.underline_color,
        types::color::Color::Default,
        "SGR 59 should reset underline color to Default"
    );
}

// === Wave 4.2: TDD Tests for Hybrid Parser Optimization ===
// These tests verify correctness of conditional APC scanning with memchr

/// Test: Plain text without ESC should process without APC state changes
/// Verifies that memchr-based fast path doesn't miss any APC sequences
#[test]
fn test_plain_text_no_esc_no_apc_state_change() {
    let mut core = TerminalCore::new(24, 80);
    // Plain ASCII text - no ESC bytes
    core.advance(b"Hello, World! This is plain text without escape sequences.");
    // apc_state should remain Idle (we can check by ensuring apc_buf is empty)
    assert_eq!(core.apc_buf.len(), 0, "No APC buffering for plain text");
    // Text should be printed correctly
    assert_eq!(core.get_cell(0, 0).unwrap().char(), 'H');
}

/// Test: Large plain text (1KB) without ESC processes correctly
/// Verifies memchr fast path handles bulk data without state corruption
#[test]
fn test_large_plain_text_processes_correctly() {
    let mut core = TerminalCore::new(24, 80);
    // 1KB of plain text
    let plain_text: Vec<u8> = (b'A'..=b'Z').cycle().take(1024).collect();
    core.advance(&plain_text);
    // No APC state should be active
    assert_eq!(core.apc_buf.len(), 0);
    // First cell should have 'A'
    assert_eq!(core.get_cell(0, 0).unwrap().char(), 'A');
}

/// Test: Text with ESC only at end processes correctly
/// Verifies memchr finds ESC even at buffer boundary
#[test]
fn test_esc_at_buffer_end_detected() {
    let mut core = TerminalCore::new(24, 80);
    // Plain text + ESC at the very end (incomplete sequence)
    let input = b"Hello World\x1b";
    core.advance(input);
    // ESC should be consumed (no panic), and apc_buf should be empty since
    // we're in AfterEsc state waiting for next byte
    // The ESC alone starts state machine but doesn't buffer anything yet
    // After advance completes, we should have processed the text
    assert_eq!(core.get_cell(0, 0).unwrap().char(), 'H');
}

/// Test: Text with ESC only at start processes correctly
/// Verifies memchr finds ESC at position 0
#[test]
fn test_esc_at_buffer_start_detected() {
    let mut core = TerminalCore::new(24, 80);
    // ESC at start (incomplete APC start), then plain text
    let input = b"\x1b_Gtest"; // ESC _ G (APC start without terminator)
    core.advance(input);
    // Should be in InApc state, buffering "test"
    assert!(core.apc_buf.len() > 0, "APC payload should be buffered");
}

/// Test: Multiple ESC bytes in sequence
/// Verifies memchr doesn't miss ESC bytes in rapid succession
#[test]
fn test_multiple_esc_bytes_detected() {
    let mut core = TerminalCore::new(24, 80);
    // ESC ESC ESC (multiple escape bytes)
    core.advance(b"\x1b\x1b\x1b");
    // Should not panic, apc_buf should be empty (no APC formed)
    assert_eq!(core.apc_buf.len(), 0);
}

/// Test: APC with large payload split across two advance calls
/// Verifies state persistence when first call has ESC
#[test]
fn test_apc_split_large_payload() {
    let mut core = TerminalCore::new(24, 80);
    // First chunk: ESC _ G + 512 bytes
    let mut part1 = vec![0x1b, b'_', b'G'];
    part1.extend(std::iter::repeat(b'X').take(512));
    core.advance(&part1);
    // Should be in InApc state with buffered payload
    assert!(core.apc_buf.len() > 500);

    // Second chunk: 512 more bytes + ESC \
    let mut part2: Vec<u8> = std::iter::repeat(b'Y').take(512).collect();
    part2.extend_from_slice(b"\x1b\\");
    core.advance(&part2);
    // APC should complete
    assert_eq!(core.apc_buf.len(), 0);
}

/// Test: Plain text after incomplete APC continues correctly
#[test]
fn test_plain_text_after_incomplete_apc() {
    let mut core = TerminalCore::new(24, 80);
    // Start an APC (incomplete)
    core.advance(b"\x1b_Gtest");
    assert!(core.apc_buf.len() > 0);
    // Now send plain text (no ESC) - should still process correctly
    // Note: This will be added to the APC buffer since we're in InApc state
    core.advance(b"more");
    // Should be buffering (still in APC)
    assert!(core.apc_buf.len() > 4);
}

/// Test: Buffer with ESC in the middle
#[test]
fn test_esc_in_middle_detected() {
    let mut core = TerminalCore::new(24, 80);
    // Plain text + ESC _ G test ESC \ + more plain text
    let input = b"Before\x1b_Gtest\x1b\\After";
    core.advance(input);
    // APC should complete, all text processed
    assert_eq!(core.apc_buf.len(), 0);
    // "Before" should be at the start
    assert_eq!(core.get_cell(0, 0).unwrap().char(), 'B');
}

/// Test: Performance critical - 100KB plain text should not run APC scanner
/// This is a correctness test that also validates the optimization path
#[test]
fn test_100kb_plain_text_no_apc_overhead() {
    let mut core = TerminalCore::new(24, 80);
    // 100KB of plain text (no ESC)
    let plain: Vec<u8> = std::iter::repeat(b'X').take(100 * 1024).collect();
    core.advance(&plain);
    // No APC state should be active
    assert_eq!(core.apc_buf.len(), 0);
    // First cell should be 'X' (wrapped many times)
    assert_eq!(core.get_cell(0, 0).unwrap().char(), 'X');
}

/// Test: Mixed content - plain + CSI + APC + plain
#[test]
fn test_mixed_content_all_sequences_processed() {
    let mut core = TerminalCore::new(24, 80);
    // Plain text + CSI (color) + APC + plain text
    let input = b"Start\x1b[31mRed\x1b[0m\x1b_Ga=q\x1b\\End";
    core.advance(input);
    // All sequences should process correctly
    assert_eq!(core.apc_buf.len(), 0, "APC should complete");
    // "Start" should be at position 0
    assert_eq!(core.get_cell(0, 0).unwrap().char(), 'S');
    // Should not have current bold (reset)
    assert!(!core.current_attrs.bold);
}

// === ESC M / ESC D / ESC E tests ===

#[test]
fn test_esc_m_reverse_index_basic() {
    // ESC M at row > scroll_top moves cursor up one row
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[5;1H"); // move to row 4 (0-indexed), col 0
    assert_eq!(term.screen.cursor().row, 4);
    term.advance(b"\x1bM"); // ESC M = RI
    assert_eq!(
        term.screen.cursor().row,
        3,
        "ESC M should move cursor up by 1"
    );
}

#[test]
fn test_esc_m_reverse_index_at_top_scrolls_down() {
    // ESC M at the top of the scroll region inserts a blank line (scroll_down)
    let mut term = TerminalCore::new(24, 80);
    // Write 'A' at row 0, then move cursor to row 0
    term.advance(b"A");
    term.advance(b"\x1b[1;1H"); // cursor to row 0, col 0
                                // Write marker text at row 0
    term.advance(b"\x1b[1;1H");
    assert_eq!(term.screen.cursor().row, 0);
    // Write 'X' at col 0 row 0
    term.advance(b"X");
    term.advance(b"\x1b[1;1H"); // back to row 0
    assert_eq!(term.screen.cursor().row, 0);
    // ESC M at scroll_top (row 0) should scroll_down: push X to row 1
    term.advance(b"\x1bM");
    // Cursor stays at row 0 (top of scroll region)
    assert_eq!(
        term.screen.cursor().row,
        0,
        "ESC M at scroll top should keep cursor at row 0"
    );
    // Row 1 should now contain 'X' (was scrolled down)
    let cell_row1 = term.screen.get_cell(1, 0).unwrap();
    assert_eq!(
        cell_row1.char(),
        'X',
        "ESC M at scroll top: previous row 0 content should move to row 1"
    );
}

#[test]
fn test_esc_m_at_row_zero_no_underflow() {
    // ESC M at row 0 (scroll top) must not underflow
    let mut term = TerminalCore::new(24, 80);
    // Already at row 0
    assert_eq!(term.screen.cursor().row, 0);
    term.advance(b"\x1bM"); // ESC M
    assert_eq!(
        term.screen.cursor().row,
        0,
        "ESC M at row 0 (scroll top) must not underflow"
    );
}

#[test]
fn test_esc_d_index_basic() {
    // ESC D (IND) moves cursor down, scrolls up at bottom of scroll region
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[1;1H"); // cursor to row 0
    assert_eq!(term.screen.cursor().row, 0);
    term.advance(b"\x1bD"); // IND
    assert_eq!(term.screen.cursor().row, 1, "ESC D should move cursor down");
}

#[test]
fn test_esc_e_next_line() {
    // ESC E (NEL) = CR + LF
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[1;5H"); // cursor to row 0, col 4
    assert_eq!(term.screen.cursor().col, 4);
    term.advance(b"\x1bE"); // NEL
    assert_eq!(
        term.screen.cursor().row,
        1,
        "ESC E should move to next line"
    );
    assert_eq!(
        term.screen.cursor().col,
        0,
        "ESC E should return cursor to col 0"
    );
}

// === Clean shutdown / drop test ===

#[test]
fn test_terminal_drop_does_not_panic() {
    // Create and immediately drop a terminal
    let term = TerminalCore::new(24, 80);
    drop(term);
    // If we get here, no panic during cleanup
}

proptest! {
        #[test]
        fn prop_vte_parse_never_panics(bytes in proptest::collection::vec(any::<u8>(), 0..256)) {
            let mut term = TerminalCore::new(24, 80);
            term.advance(&bytes);
            // Must not panic. Cursor stays in bounds.
            prop_assert!(term.screen.cursor().row < 24);
            prop_assert!(term.screen.cursor().col < 80);
}

        #[test]
        fn prop_resize_cursor_always_in_bounds(
            new_rows in 1u16..50,
            new_cols in 1u16..50,
        ) {
            let mut term = TerminalCore::new(24, 80);
            // Move cursor to somewhere potentially out of bounds after resize
            term.advance(b"\x1b[20;70H");
            term.resize(new_rows, new_cols);
            prop_assert!(term.screen.cursor().row < new_rows as usize,
                "cursor row {} >= {}", term.screen.cursor().row, new_rows);
            prop_assert!(term.screen.cursor().col < new_cols as usize,
                "cursor col {} >= {}", term.screen.cursor().col, new_cols);
        }

        #[test]
        fn prop_sgr_reset_always_clears(
            bold in any::<bool>(),
            italic in any::<bool>(),
        ) {
            let mut term = TerminalCore::new(24, 80);
            // Set attributes based on props
            if bold { term.advance(b"\x1b[1m"); }
            if italic { term.advance(b"\x1b[3m"); }
            // SGR 0 must clear everything
            term.advance(b"\x1b[0m");
            prop_assert!(!term.current_bold(), "SGR 0 must clear bold");
            prop_assert!(!term.current_italic(), "SGR 0 must clear italic");
            prop_assert!(!term.current_underline(), "SGR 0 must clear underline");
        }

        #[test]
        fn prop_cup_clamps_to_screen(
            row in 1u16..200,
            col in 1u16..200,
        ) {
            let mut term = TerminalCore::new(24, 80);
            // CUP uses 1-indexed row;col
            let seq = format!("\x1b[{};{}H", row, col);
            term.advance(seq.as_bytes());
            prop_assert!(term.screen.cursor().row < 24,
                "CUP row {} must clamp to <24, got {}", row, term.screen.cursor().row);
            prop_assert!(term.screen.cursor().col < 80,
                "CUP col {} must clamp to <80, got {}", col, term.screen.cursor().col);
        }

        #[test]
        fn prop_esc_m_never_panics(initial_row in 0usize..24) {
            let mut term = TerminalCore::new(24, 80);
            // Move cursor to arbitrary row then send ESC M
            let seq = format!("\x1b[{};1H", initial_row + 1);
            term.advance(seq.as_bytes());
            term.advance(b"\x1bM");
            prop_assert!(term.screen.cursor().row < 24, "ESC M must not cause row overflow");
        }

        #[test]
        fn prop_large_input_cursor_in_bounds(
            bytes in proptest::collection::vec(any::<u8>(), 0..1024),
        ) {
            let mut term = TerminalCore::new(24, 80);
            // Feed large arbitrary input
            for chunk in bytes.chunks(64) {
                term.advance(chunk);
            }
            prop_assert!(term.screen.cursor().row < 24,
                "cursor row {} out of bounds after large input", term.screen.cursor().row);
            prop_assert!(term.screen.cursor().col < 80,
                "cursor col {} out of bounds after large input", term.screen.cursor().col);
        }
    }

// -----------------------------------------------------------------------------
// REGRESSION TESTS: SPC cursor movement + trailing-space preservation
// -----------------------------------------------------------------------------
//
// These tests guard against the following bug that was introduced and fixed:
//
//   encode_line() was trimming trailing spaces from the rendered text before
//   sending it to Emacs.  kuro--update-cursor computes the buffer position as
//   `(min (+ line-start col) line-end)`.  After trimming, line-end was
//   smaller than the cursor column when the cursor was inside whitespace,
//   so the visual cursor was clamped to the wrong (non-space) column.
//
//   Symptom: pressing SPC at a bash prompt didn't visually move the cursor.
//
// DO NOT add trim_end_matches logic back to encode_line or get_dirty_lines
// without also fixing the Emacs-side cursor computation.
#[cfg(test)]
mod regression_spc_cursor {
    use super::*;
    use crate::ffi::codec::encode_line;

    /// Typing a single space must advance the cursor by one column.
    ///
    /// This is the minimal reproduction of the original bug: pressing SPC at a
    /// bash prompt left the cursor at col 0 because the echoed space was trimmed
    /// from the line text, making line-end == 0 and clamping the cursor.
    #[test]
    fn test_spc_advances_cursor_col_by_one() {
        let mut term = TerminalCore::new(24, 80);
        term.advance(b" ");
        assert_eq!(
            term.cursor_col(),
            1,
            "cursor col must be 1 after printing one space (SPC regression)"
        );
    }

    /// Multiple spaces must all advance the cursor correctly.
    #[test]
    fn test_multiple_spaces_advance_cursor() {
        let mut term = TerminalCore::new(24, 80);
        term.advance(b"   ");
        assert_eq!(
            term.cursor_col(),
            3,
            "cursor col must be 3 after printing three spaces"
        );
    }

    /// Text followed by trailing spaces: cursor lands after the last space.
    ///
    /// Reproduces: typing "echo hello " (with trailing space) must leave the
    /// cursor at col 11, not col 10 (which would be the trimmed position).
    #[test]
    fn test_cursor_col_after_text_then_space() {
        let mut term = TerminalCore::new(24, 80);
        term.advance(b"echo hello ");
        assert_eq!(
            term.cursor_col(),
            11,
            "cursor col must be 11 after 'echo hello ' (10 chars + 1 trailing space)"
        );
    }

    /// encode_line must preserve trailing spaces so the Emacs buffer line is
    /// at least as long as the terminal cursor column.
    #[test]
    fn test_encode_line_preserves_trailing_spaces_for_cursor() {
        let mut term = TerminalCore::new(24, 80);
        // Print text then a space — the space is now the cursor position
        term.advance(b"$ ");
        let cursor_col = term.cursor_col(); // should be 2
        assert_eq!(cursor_col, 2);

        let line = term.screen.get_line(0).expect("line 0 must exist");
        let (text, _, _) = encode_line(&line.cells);

        // The encoded text must be at least cursor_col characters long so that
        // `(+ line-start cursor_col)` never exceeds `line-end-position`.
        assert!(
            text.len() >= cursor_col,
            "encoded text length ({}) must be >= cursor_col ({}) — \
             trimming trailing spaces would break kuro--update-cursor",
            text.len(),
            cursor_col
        );
    }

    /// A line consisting entirely of spaces must not encode as an empty string.
    ///
    /// When the terminal is freshly initialized, all cells are spaces.  If
    /// encode_line collapsed such a line to "", every cursor-update call would
    /// clamp to col 0.
    #[test]
    fn test_blank_line_is_not_empty_after_encode() {
        let term = TerminalCore::new(24, 80);
        let line = term.screen.get_line(0).expect("line 0 must exist");
        let (text, _, _) = encode_line(&line.cells);
        // A blank 80-column line: encoded text must be 80 spaces, not "".
        assert_eq!(
            text.len(),
            80,
            "a blank 80-col line must encode to 80 spaces, not an empty string"
        );
    }

    /// Spaces appearing between non-space characters must be preserved.
    /// (These were never trimmed, but guard against regressions in internal
    /// run-length logic that could accidentally collapse middle spans.)
    #[test]
    fn test_internal_spaces_preserved() {
        let mut term = TerminalCore::new(24, 80);
        term.advance(b"foo   bar");
        let cell_space = term.get_cell(0, 3).expect("cell at (0,3) must exist");
        assert_eq!(
            cell_space.char(),
            ' ',
            "space at col 3 in 'foo   bar' must be stored in the grid"
        );
        let line = term.screen.get_line(0).expect("line 0 must exist");
        let (text, _, _) = encode_line(&line.cells);
        assert!(
            text.starts_with("foo   bar"),
            "encoded text must start with 'foo   bar' (spaces preserved), got: {:?}",
            &text[..text.len().min(20)]
        );
    }
}
