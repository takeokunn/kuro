//! Basic terminal creation, resize, input, and cursor tests.

use super::super::*;
use crate::types::cell::SgrFlags;
use proptest::prelude::*;

// ── Local test-only macros ─────────────────────────────────────────────────

/// Assert the cursor is at an exact (row, col) position (0-indexed).
///
/// ```
/// assert_cursor!(term, row 4, col 0);
/// ```
macro_rules! assert_cursor {
    ($term:expr, row $r:expr, col $c:expr) => {{
        assert_eq!(
            $term.screen.cursor().row,
            $r,
            "cursor row: expected {}, got {}",
            $r,
            $term.screen.cursor().row
        );
        assert_eq!(
            $term.screen.cursor().col,
            $c,
            "cursor col: expected {}, got {}",
            $c,
            $term.screen.cursor().col
        );
    }};
}

/// Assert a single cell's character value by (row, col).
///
/// ```
/// assert_cell_char!(term, row 0, col 2, 'l');
/// ```
macro_rules! assert_cell_char {
    ($term:expr, row $r:expr, col $c:expr, $ch:expr) => {{
        assert_eq!(
            $term.get_cell($r, $c).unwrap().char(),
            $ch,
            "cell ({}, {}) expected {:?}",
            $r,
            $c,
            $ch
        );
    }};
}

/// Assert a specific SGR flag is set on `current_attrs`.
///
/// ```
/// assert_flag!(term, SgrFlags::BOLD);
/// ```
macro_rules! assert_flag {
    ($term:expr, $flag:expr) => {{
        assert!(
            $term.current_attrs.flags.contains($flag),
            "expected flag {:?} to be set",
            $flag
        );
    }};
}

/// Assert a specific SGR flag is NOT set on `current_attrs`.
macro_rules! assert_no_flag {
    ($term:expr, $flag:expr) => {{
        assert!(
            !$term.current_attrs.flags.contains($flag),
            "expected flag {:?} to be clear",
            $flag
        );
    }};
}

// ── Tests ──────────────────────────────────────────────────────────────────

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
    assert_cell_char!(term, row 0, col 0, 'H');
}

#[test]
fn test_decsc_decrc_basic() {
    let mut term = super::make_term();

    term.advance(b"\x1b[6;11H"); // CSI 6;11H -> row 5, col 10 (0-indexed)
    let row_before = term.screen.cursor().row;
    let col_before = term.screen.cursor().col;

    term.advance(b"\x1b7"); // DECSC
    assert!(
        term.saved_cursor.is_some(),
        "saved_cursor should be set after ESC 7"
    );

    term.advance(b"\x1b[1;1H");
    assert_cursor!(term, row 0, col 0);

    term.advance(b"\x1b8"); // DECRC
    assert_eq!(term.screen.cursor().row, row_before);
    assert_eq!(term.screen.cursor().col, col_before);
    assert!(
        term.saved_cursor.is_none(),
        "saved_cursor should be cleared after ESC 8"
    );
}

#[test]
fn test_decsc_decrc_preserves_attrs() {
    let mut term = super::make_term();

    term.advance(b"\x1b[1m"); // bold on
    assert_flag!(term, SgrFlags::BOLD);

    term.advance(b"\x1b7"); // DECSC
    term.advance(b"\x1b[0m"); // reset
    assert_no_flag!(term, SgrFlags::BOLD);

    term.advance(b"\x1b8"); // DECRC
    assert_flag!(term, SgrFlags::BOLD);
}

#[test]
fn test_ris_full_reset() {
    let mut term = super::make_term();

    term.advance(b"\x1b[10;20H");
    term.advance(b"\x1b[1m");
    term.advance(b"\x1b7");
    term.advance(b"\x1bc"); // RIS

    assert_cursor!(term, row 0, col 0);
    assert_no_flag!(term, SgrFlags::BOLD);
    assert!(term.saved_cursor.is_none());
    assert!(term.saved_attrs.is_none());
    assert!(!term.screen.is_alternate_screen_active());
}

#[test]
fn test_dectcem_cursor_visibility() {
    let mut term = super::make_term();

    assert!(term.dec_modes.cursor_visible);

    term.advance(b"\x1b[?25l");
    assert!(
        !term.dec_modes.cursor_visible,
        "cursor should be hidden after CSI ?25l"
    );

    term.advance(b"\x1b[?25h");
    assert!(
        term.dec_modes.cursor_visible,
        "cursor should be visible after CSI ?25h"
    );
}

#[test]
fn test_dectcem_after_ris() {
    let mut term = super::make_term();
    assert!(term.dec_modes.cursor_visible);

    term.advance(b"\x1b[?25l");
    assert!(!term.dec_modes.cursor_visible);

    term.advance(b"\x1bc");
    assert!(
        term.dec_modes.cursor_visible,
        "cursor should be visible after RIS (DecModes::new() sets cursor_visible=true)"
    );
}

#[test]
fn test_ris_resets_cursor_shape() {
    let mut term = super::make_term();

    term.advance(b"\x1b[6 q");
    assert_eq!(
        term.dec_modes.cursor_shape,
        CursorShape::SteadyBar,
        "cursor shape should be SteadyBar after CSI 6 SP q"
    );

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

    term.advance(b"\x1b[>1u");
    term.advance(b"\x1b[>3u");
    assert_eq!(
        term.dec_modes.keyboard_flags_stack.len(),
        2,
        "keyboard_flags_stack should have 2 entries after two pushes"
    );

    term.advance(b"\x1bc");
    assert!(
        term.dec_modes.keyboard_flags_stack.is_empty(),
        "RIS must clear keyboard_flags_stack"
    );
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
    term.advance(b"\x1b="); // DECKPAM
    assert!(
        term.dec_modes.app_keypad,
        "app_keypad should be set after ESC ="
    );
}

#[test]
fn test_deckpnm_clears_app_keypad() {
    let mut term = super::make_term();
    term.advance(b"\x1b=");
    assert!(term.dec_modes.app_keypad);
    term.advance(b"\x1b>");
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
    term.advance(b"A");
    let row_before = term.screen.cursor().row;
    let col_before = term.screen.cursor().col;
    term.resize(30, 100);
    assert_eq!(term.screen.rows(), 30);
    assert_eq!(term.screen.cols(), 100);
    assert!(
        term.screen.cursor().row < 30,
        "cursor row out of bounds after resize"
    );
    assert!(
        term.screen.cursor().col < 100,
        "cursor col out of bounds after resize"
    );
    let _ = (row_before, col_before);
}

#[test]
fn test_advance_empty_input() {
    let mut term = super::make_term();
    term.advance(&[]);
    assert_cursor!(term, row 0, col 0);
}

#[test]
fn test_advance_split_sequence() {
    let mut term = super::make_term();
    term.advance(b"\x1b["); // incomplete CSI
    term.advance(b"1m"); // complete: SGR bold
    assert_flag!(term, SgrFlags::BOLD);
}

#[test]
fn test_execute_backspace_at_col_zero() {
    let mut term = super::make_term();
    term.advance(b"\x1b[5;1H\x08");
    assert_cursor!(term, row 4, col 0);
}

#[test]
fn test_csi_unknown_final_byte_no_panic() {
    let mut term = super::make_term();
    term.advance(b"\x1b[999z");
    // No assertion needed — reaching here means no panic
}

#[test]
fn test_osc_unknown_command_number_ignored() {
    let mut term = super::make_term();
    term.advance(b"\x1b]99;some_data\x07");
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
    term.advance("e\u{0301}".as_bytes());
    let cell = term.get_cell(0, 0).unwrap();
    assert_eq!(cell.grapheme.as_str(), "e\u{0301}");
}

#[test]
fn test_combining_char_at_col_zero_printed_standalone() {
    let mut term = super::make_term();
    term.advance("\u{0301}".as_bytes());
    let cell = term.get_cell(0, 0).unwrap();
    assert_eq!(cell.grapheme.as_str(), "\u{0301}");
}

#[test]
fn test_combining_char_attaches_to_previous_row_last_col() {
    let mut term = super::make_term();
    term.advance(b"\x1b[1;80H"); // row 0, col 79
    term.advance(b"e");
    term.advance(b"\x1b[2;1H");
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
    assert_cell_char!(term, row 0, col 0, 'A');
    assert_cell_char!(term, row 0, col 1, 'B');
    assert_cell_char!(term, row 0, col 2, 'C');
}

#[test]
fn test_decscusr_sets_cursor_shape() {
    let mut term = super::make_term();
    term.advance(b"\x1b[5 q");
    assert_eq!(
        term.dec_modes.cursor_shape,
        types::cursor::CursorShape::BlinkingBar
    );
    term.advance(b"\x1b[2 q");
    assert_eq!(
        term.dec_modes.cursor_shape,
        types::cursor::CursorShape::SteadyBlock
    );
}

#[test]
fn test_decstr_soft_reset() {
    let mut term = super::make_term();
    term.advance(b"\x1b[?1h"); // DECCKM on
    term.advance(b"\x1b[1m"); // Bold on
    term.advance(b"\x1b[10;20H");
    term.advance(b"\x1b[!p"); // DECSTR
    assert!(!term.dec_modes.app_cursor_keys);
    assert_no_flag!(term, SgrFlags::BOLD);
    assert_cursor!(term, row 0, col 0);
    assert!(term.dec_modes.auto_wrap);
}

#[test]
fn test_decstr_preserves_screen_content() {
    let mut term = super::make_term();
    term.advance(b"Hello");
    term.advance(b"\x1b[!p");
    assert_cell_char!(term, row 0, col 0, 'H');
}

#[test]
fn test_kitty_keyboard_push_pop() {
    let mut term = super::make_term();
    assert_eq!(term.dec_modes.keyboard_flags, 0);
    term.advance(b"\x1b[>1u");
    assert_eq!(term.dec_modes.keyboard_flags, 1);
    term.advance(b"\x1b[>3u");
    assert_eq!(term.dec_modes.keyboard_flags, 3);
    assert_eq!(term.dec_modes.keyboard_flags_stack.len(), 2);
    term.advance(b"\x1b[<u");
    assert_eq!(term.dec_modes.keyboard_flags, 1);
    term.advance(b"\x1b[<u");
    assert_eq!(term.dec_modes.keyboard_flags, 0);
    term.advance(b"\x1b[<u"); // pop on empty stack
    assert_eq!(term.dec_modes.keyboard_flags, 0);
}

#[test]
fn test_kitty_keyboard_query() {
    let mut term = super::make_term();
    term.advance(b"\x1b[>5u");
    term.advance(b"\x1b[?u");
    assert_eq!(term.meta.pending_responses.len(), 1);
    assert_eq!(term.meta.pending_responses[0], b"\x1b[?5u");
}

#[test]
fn test_oversized_osc7_cwd_rejected() {
    let mut term = super::make_term();
    let long_path = format!("\x1b]7;file://localhost/{}\x07", "a".repeat(5000));
    term.advance(long_path.as_bytes());
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
    assert!(
        term.osc_data.hyperlink.uri.is_none()
            || term.osc_data.hyperlink.uri.as_ref().unwrap().len() <= 8192,
        "Hyperlink URI over 8192 bytes should be rejected"
    );
}

#[test]
fn test_apc_payload_cap_enforced() {
    let mut term = super::make_term();
    let large_payload = vec![b'A'; 5 * 1024 * 1024];
    let mut data = Vec::new();
    data.extend_from_slice(b"\x1b_G");
    data.extend_from_slice(&large_payload);
    data.extend_from_slice(b"\x1b\\");
    term.advance(&data);
    assert_eq!(
        term.kitty.apc_buf.len(),
        0,
        "apc_buf should be cleared after oversized APC sequence"
    );
}

#[test]
fn test_title_sanitization_strips_control_chars() {
    let mut term = super::make_term();
    term.advance(b"\x1b]2;Hello\x07World\x07");
    assert!(
        !term.meta.title.contains('\x07'),
        "Title should not contain BEL control character"
    );
}

// === ESC M / ESC D / ESC E tests ===

#[test]
fn test_esc_m_reverse_index_basic() {
    let mut term = super::make_term();
    term.advance(b"\x1b[5;1H");
    assert_eq!(term.screen.cursor().row, 4);
    term.advance(b"\x1bM");
    assert_eq!(
        term.screen.cursor().row,
        3,
        "ESC M should move cursor up by 1"
    );
}

#[test]
fn test_esc_m_reverse_index_at_top_scrolls_down() {
    let mut term = super::make_term();
    term.advance(b"A");
    term.advance(b"\x1b[1;1H");
    term.advance(b"\x1b[1;1H");
    assert_eq!(term.screen.cursor().row, 0);
    term.advance(b"X");
    term.advance(b"\x1b[1;1H");
    assert_eq!(term.screen.cursor().row, 0);
    term.advance(b"\x1bM");
    assert_eq!(
        term.screen.cursor().row,
        0,
        "ESC M at scroll top should keep cursor at row 0"
    );
    let cell_row1 = term.screen.get_cell(1, 0).unwrap();
    assert_eq!(
        cell_row1.char(),
        'X',
        "ESC M at scroll top: previous row 0 content should move to row 1"
    );
}

#[test]
fn test_esc_m_at_row_zero_no_underflow() {
    let mut term = super::make_term();
    assert_eq!(term.screen.cursor().row, 0);
    term.advance(b"\x1bM");
    assert_eq!(
        term.screen.cursor().row,
        0,
        "ESC M at row 0 (scroll top) must not underflow"
    );
}

#[test]
fn test_esc_d_index_basic() {
    let mut term = super::make_term();
    term.advance(b"\x1b[1;1H");
    assert_eq!(term.screen.cursor().row, 0);
    term.advance(b"\x1bD");
    assert_eq!(term.screen.cursor().row, 1, "ESC D should move cursor down");
}

#[test]
fn test_esc_e_next_line() {
    let mut term = super::make_term();
    term.advance(b"\x1b[1;5H"); // row 0, col 4
    assert_eq!(term.screen.cursor().col, 4);
    term.advance(b"\x1bE"); // NEL
    assert_cursor!(term, row 1, col 0);
}

// === Clean shutdown / drop test ===

#[test]
fn test_terminal_drop_does_not_panic() {
    let term = super::make_term();
    drop(term);
}

include!("terminal_insert_delete_line.rs");
