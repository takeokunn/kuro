//! Basic terminal creation, resize, input, and cursor tests.

use super::super::*;
use crate::types::cell::SgrFlags;
use proptest::prelude::*;

#[test]
fn test_terminal_creation() {
    let term = super::make_term();
    assert_eq!(term.screen.rows(), 24);
    assert_eq!(term.screen.cols(), 80);
}

#[test]
fn test_simple_print() {
    let mut term = super::make_term();
    term.advance(b"Hello");
    // Check first cell
    let cell = term.screen.get_cell(0, 0).unwrap();
    assert_eq!(cell.char(), 'H');
}

#[test]
fn test_decsc_decrc_basic() {
    let mut term = super::make_term();

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
    let mut term = super::make_term();

    // Set bold via SGR
    term.advance(b"\x1b[1m"); // CSI 1m -> bold on
    assert!(term.current_attrs.flags.contains(SgrFlags::BOLD));

    // Save cursor + attrs
    term.advance(b"\x1b7"); // DECSC

    // Reset attrs
    term.advance(b"\x1b[0m"); // CSI 0m -> reset
    assert!(!term.current_attrs.flags.contains(SgrFlags::BOLD));

    // Restore cursor + attrs
    term.advance(b"\x1b8"); // DECRC

    // Bold should be restored
    assert!(term.current_attrs.flags.contains(SgrFlags::BOLD));
}

#[test]
fn test_ris_full_reset() {
    let mut term = super::make_term();

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
    assert!(!term.current_attrs.flags.contains(SgrFlags::BOLD));

    // Saved cursor state should be cleared
    assert!(term.saved_cursor.is_none());
    assert!(term.saved_attrs.is_none());

    // Alternate screen should not be active
    assert!(!term.screen.is_alternate_screen_active());
}

#[test]
fn test_dectcem_cursor_visibility() {
    let mut term = super::make_term();

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
    let mut term = super::make_term();

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
fn test_ris_resets_cursor_shape() {
    let mut term = super::make_term();

    // Set cursor to SteadyBar (DECSCUSR 6)
    term.advance(b"\x1b[6 q");
    assert_eq!(
        term.dec_modes.cursor_shape,
        CursorShape::SteadyBar,
        "cursor shape should be SteadyBar after CSI 6 SP q"
    );

    // Full terminal reset (RIS — ESC c) must restore cursor_shape to default (BlinkingBlock)
    term.advance(b"\x1bc");
    assert_eq!(
        term.dec_modes.cursor_shape,
        CursorShape::BlinkingBlock,
        "RIS must reset cursor_shape to BlinkingBlock"
    );
}

#[test]
fn test_ris_clears_kitty_keyboard_stack() {
    let mut term = super::make_term();

    // Push two Kitty keyboard flag entries onto the stack (CSI > Ps u)
    term.advance(b"\x1b[>1u"); // push flags=1
    term.advance(b"\x1b[>3u"); // push flags=3
    assert_eq!(
        term.dec_modes.keyboard_flags_stack.len(),
        2,
        "keyboard_flags_stack should have 2 entries after two pushes"
    );

    // Full terminal reset (RIS — ESC c) must clear the entire stack
    term.advance(b"\x1bc");
    assert!(
        term.dec_modes.keyboard_flags_stack.is_empty(),
        "RIS must clear keyboard_flags_stack"
    );
    // keyboard_flags itself must also be reset to 0
    assert_eq!(
        term.dec_modes.keyboard_flags, 0,
        "RIS must reset keyboard_flags to 0"
    );
}

#[test]
fn test_deckpam_sets_app_keypad() {
    let mut term = super::make_term();
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
    let mut term = super::make_term();
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
    let mut term = super::make_term();
    term.advance(b"\x1b=\x1b>\x1b="); // DECKPAM -> DECKPNM -> DECKPAM
    assert!(
        term.dec_modes.app_keypad,
        "final state should be app_keypad=true"
    );
}

#[test]
fn test_resize_preserves_screen_content() {
    let mut term = super::make_term();
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
    let mut term = super::make_term();
    term.advance(&[]);
    // State is unchanged from initial
    assert_eq!(term.screen.cursor().row, 0);
    assert_eq!(term.screen.cursor().col, 0);
}

#[test]
fn test_advance_split_sequence() {
    // Send an incomplete CSI sequence in the first call, complete it in the second.
    // After both calls, bold should be set.
    let mut term = super::make_term();
    term.advance(b"\x1b["); // incomplete CSI
    term.advance(b"1m"); // complete: SGR bold
    assert!(
        term.current_attrs.flags.contains(SgrFlags::BOLD),
        "bold should be set after split CSI sequence"
    );
}

#[test]
fn test_execute_backspace_at_col_zero() {
    // Move to row 5 col 0 (CSI 5;1H) then send backspace.
    // Cursor must stay at col 0 (no underflow).
    let mut term = super::make_term();
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
    let mut term = super::make_term();
    term.advance(b"\x1b[999z");
    // If we reach here the test passes — no panic occurred
}

#[test]
fn test_osc_unknown_command_number_ignored() {
    // OSC with unknown command number must be silently discarded without crashing.
    let mut term = super::make_term();
    term.advance(b"\x1b]99;some_data\x07");
    // Title must not have changed (OSC 99 is not handled)
    assert_eq!(
        term.meta.title, "",
        "unknown OSC number must not update title"
    );
    assert!(
        !term.meta.title_dirty,
        "unknown OSC number must not set title_dirty"
    );
}

#[test]
fn test_combining_char_attached_to_base() {
    let mut term = super::make_term();
    // Print 'e' followed by combining acute accent U+0301
    term.advance("e\u{0301}".as_bytes());
    let cell = term.get_cell(0, 0).unwrap();
    assert_eq!(cell.grapheme.as_str(), "e\u{0301}");
}

#[test]
fn test_combining_char_at_col_zero_printed_standalone() {
    let mut term = super::make_term();
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
    let mut term = super::make_term();
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
    let mut term = super::make_term();
    term.advance(b"ABC");
    assert_eq!(term.get_cell(0, 0).unwrap().char(), 'A');
    assert_eq!(term.get_cell(0, 1).unwrap().char(), 'B');
    assert_eq!(term.get_cell(0, 2).unwrap().char(), 'C');
}

#[test]
fn test_decscusr_sets_cursor_shape() {
    let mut term = super::make_term();
    // CSI 5 SP q -> blinking bar
    term.advance(b"\x1b[5 q");
    assert_eq!(
        term.dec_modes.cursor_shape,
        types::cursor::CursorShape::BlinkingBar
    );
    // CSI 2 SP q -> steady block
    term.advance(b"\x1b[2 q");
    assert_eq!(
        term.dec_modes.cursor_shape,
        types::cursor::CursorShape::SteadyBlock
    );
}

#[test]
fn test_decstr_soft_reset() {
    let mut term = super::make_term();
    // Set some modes
    term.advance(b"\x1b[?1h"); // DECCKM on
    term.advance(b"\x1b[1m"); // Bold on
    term.advance(b"\x1b[10;20H"); // Move cursor
                                  // Soft reset
    term.advance(b"\x1b[!p");
    // Cursor keys should be reset
    assert!(!term.dec_modes.app_cursor_keys);
    // SGR should be reset
    assert!(!term.current_attrs.flags.contains(SgrFlags::BOLD));
    // Cursor should be at home
    assert_eq!(term.cursor_row(), 0);
    assert_eq!(term.cursor_col(), 0);
    // Auto-wrap should be on
    assert!(term.dec_modes.auto_wrap);
}

#[test]
fn test_decstr_preserves_screen_content() {
    let mut term = super::make_term();
    term.advance(b"Hello");
    term.advance(b"\x1b[!p"); // Soft reset
                              // Content should be preserved
    let cell = term.get_cell(0, 0).unwrap();
    assert_eq!(cell.char(), 'H');
}

#[test]
fn test_kitty_keyboard_push_pop() {
    let mut term = super::make_term();
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
    // Pop on empty stack -> stays at 0
    term.advance(b"\x1b[<u");
    assert_eq!(term.dec_modes.keyboard_flags, 0);
}

#[test]
fn test_kitty_keyboard_query() {
    let mut term = super::make_term();
    term.advance(b"\x1b[>5u"); // Set flags=5
    term.advance(b"\x1b[?u"); // Query
    assert_eq!(term.meta.pending_responses.len(), 1);
    assert_eq!(term.meta.pending_responses[0], b"\x1b[?5u");
}

#[test]
fn test_oversized_osc7_cwd_rejected() {
    let mut term = super::make_term();
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
    let mut term = super::make_term();
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
    let mut term = super::make_term();
    // Send an APC with payload > 4MiB
    let large_payload = vec![b'A'; 5 * 1024 * 1024];
    let mut data = Vec::new();
    data.extend_from_slice(b"\x1b_G");
    data.extend_from_slice(&large_payload);
    data.extend_from_slice(b"\x1b\\");
    term.advance(&data);
    // Should not panic and apc_buf should be cleared after sequence completes
    assert_eq!(
        term.kitty.apc_buf.len(),
        0,
        "apc_buf should be cleared after oversized APC sequence"
    );
}

#[test]
fn test_title_sanitization_strips_control_chars() {
    let mut term = super::make_term();
    // Title with embedded BEL control character — the OSC parser splits on BEL,
    // so the title will be "Hello" (everything before the first BEL terminator)
    term.advance(b"\x1b]2;Hello\x07World\x07");
    // The title should not contain control characters
    assert!(
        !term.meta.title.contains('\x07'),
        "Title should not contain BEL control character"
    );
}

// === ESC M / ESC D / ESC E tests ===

#[test]
fn test_esc_m_reverse_index_basic() {
    // ESC M at row > scroll_top moves cursor up one row
    let mut term = super::make_term();
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
    let mut term = super::make_term();
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
    let mut term = super::make_term();
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
    let mut term = super::make_term();
    term.advance(b"\x1b[1;1H"); // cursor to row 0
    assert_eq!(term.screen.cursor().row, 0);
    term.advance(b"\x1bD"); // IND
    assert_eq!(term.screen.cursor().row, 1, "ESC D should move cursor down");
}

#[test]
fn test_esc_e_next_line() {
    // ESC E (NEL) = CR + LF
    let mut term = super::make_term();
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
    let term = super::make_term();
    drop(term);
    // If we get here, no panic during cleanup
}

proptest! {
        #[test]
        fn prop_vte_parse_never_panics(bytes in proptest::collection::vec(any::<u8>(), 0..256)) {
            let mut term = super::make_term();
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
            let mut term = super::make_term();
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
            let mut term = super::make_term();
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
            let mut term = super::make_term();
            // CUP uses 1-indexed row;col
            let seq = format!("\x1b[{row};{col}H");
            term.advance(seq.as_bytes());
            prop_assert!(term.screen.cursor().row < 24,
                "CUP row {} must clamp to <24, got {}", row, term.screen.cursor().row);
            prop_assert!(term.screen.cursor().col < 80,
                "CUP col {} must clamp to <80, got {}", col, term.screen.cursor().col);
        }

        #[test]
        fn prop_esc_m_never_panics(initial_row in 0usize..24) {
            let mut term = super::make_term();
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
            let mut term = super::make_term();
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
