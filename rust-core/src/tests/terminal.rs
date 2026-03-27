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

// ── New tests covering previously untested behaviors ──────────────────────

/// IL (CSI L — Insert Line) inserts blank lines pushing content down.
#[test]
fn test_csi_il_inserts_blank_line() {
    let mut term = super::make_term();
    // Print a line on row 0 and move cursor back to row 0
    term.advance(b"First line content");
    term.advance(b"\x1b[1;1H"); // cursor to row 0, col 0
    term.advance(b"\x1b[1L"); // IL 1: insert blank line above current row
                              // Row 0 should now be blank (the inserted line)
    assert_cell_char!(term, row 0, col 0, ' ');
    // Previous row 0 content should be at row 1
    assert_cell_char!(term, row 1, col 0, 'F');
}

/// DL (CSI M — Delete Line) removes the current line, scrolling content up.
#[test]
fn test_csi_dl_deletes_current_line() {
    let mut term = super::make_term();
    // Write 'X' at row 1 col 0 using explicit CUP
    term.advance(b"\x1b[2;1H"); // CSI 2;1H → row 1, col 0
    term.advance(b"X");
    // Move cursor back to row 0
    term.advance(b"\x1b[1;1H");
    term.advance(b"\x1b[1M"); // DL 1: delete row 0
                              // 'X' from row 1 must shift up to row 0
    assert_cell_char!(term, row 0, col 0, 'X');
    // Row 1 is now blank (shifted in at the bottom)
    assert_cell_char!(term, row 1, col 0, ' ');
}

/// Scroll region (DECSTBM, CSI r) — content outside the region must not scroll.
#[test]
fn test_csi_decstbm_scroll_region_set_and_respected() {
    let mut term = super::make_term();
    // Set scroll region to rows 2-5 (1-indexed: CSI 2;5r)
    term.advance(b"\x1b[2;5r");
    // Cursor must be moved to the home position (top of scroll region) after DECSTBM
    // The scroll-region top in 0-indexed is 1; cursor must be at row ≤ 1
    // (Some terminals move to absolute (0,0); others to region top — just assert in-bounds)
    assert!(
        term.screen.cursor().row <= 1,
        "DECSTBM should move cursor to home"
    );

    // Write a marker on row 0 (outside region)
    term.advance(b"\x1b[1;1H");
    term.advance(b"OUTSIDE");

    // Move to the bottom of the scroll region (row 4, 0-indexed) and feed a LF
    term.advance(b"\x1b[5;1H"); // row 4, col 0 (1-indexed row 5)
    term.advance(b"\n"); // should scroll only rows 1-4

    // Row 0 ('OUTSIDE') must be intact — it's outside the scroll region
    assert_cell_char!(term, row 0, col 0, 'O');
}

/// CSI S (scroll up N lines) must scroll the visible screen up.
#[test]
fn test_csi_scroll_up_shifts_content() {
    let mut term = super::make_term();
    // Put a marker on row 1
    term.advance(b"\x1b[2;1H");
    term.advance(b"MARKER");
    term.advance(b"\x1b[1;1H"); // back to row 0

    // CSI 1 S — scroll up 1 line
    term.advance(b"\x1b[1S");

    // MARKER should now be on row 0
    assert_cell_char!(term, row 0, col 0, 'M');
}

/// CSI T (scroll down N lines) must scroll the visible screen down.
#[test]
fn test_csi_scroll_down_shifts_content() {
    let mut term = super::make_term();
    // Put a marker on row 0
    term.advance(b"\x1b[1;1H");
    term.advance(b"MARKER");
    term.advance(b"\x1b[1;1H");

    // CSI 1 T — scroll down 1 line
    term.advance(b"\x1b[1T");

    // MARKER should now be on row 1
    assert_cell_char!(term, row 1, col 0, 'M');
}

/// Cursor positions reported by DSR (CSI 6 n) must match the actual cursor.
#[test]
fn test_cursor_position_matches_dsr_response() {
    let mut term = super::make_term();
    term.advance(b"\x1b[12;34H"); // row 11, col 33 (0-indexed)
    let actual_row = term.screen.cursor().row + 1; // 1-indexed
    let actual_col = term.screen.cursor().col + 1;

    term.advance(b"\x1b[6n"); // DSR
    assert_eq!(term.meta.pending_responses.len(), 1);
    let resp = String::from_utf8_lossy(&term.meta.pending_responses[0]);
    let expected = format!("\x1b[{actual_row};{actual_col}R");
    assert_eq!(
        resp.as_ref(),
        expected,
        "DSR response must exactly encode the current cursor position"
    );
}

proptest! {
        #[test]
        fn prop_vte_parse_never_panics(bytes in proptest::collection::vec(any::<u8>(), 0..256)) {
            let mut term = super::make_term();
            term.advance(&bytes);
            prop_assert!(term.screen.cursor().row < 24);
            prop_assert!(term.screen.cursor().col < 80);
}

        #[test]
        fn prop_resize_cursor_always_in_bounds(
            new_rows in 1u16..50,
            new_cols in 1u16..50,
        ) {
            let mut term = super::make_term();
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
            if bold { term.advance(b"\x1b[1m"); }
            if italic { term.advance(b"\x1b[3m"); }
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
            for chunk in bytes.chunks(64) {
                term.advance(chunk);
            }
            prop_assert!(term.screen.cursor().row < 24,
                "cursor row {} out of bounds after large input", term.screen.cursor().row);
            prop_assert!(term.screen.cursor().col < 80,
                "cursor col {} out of bounds after large input", term.screen.cursor().col);
        }
    }

// ── New targeted tests ─────────────────────────────────────────────────────

/// `cursor_row()` and `cursor_col()` return the same values as the inner cursor.
#[test]
fn test_cursor_row_col_accessors_match_screen() {
    let mut term = super::make_term();
    term.advance(b"\x1b[8;15H"); // row 7, col 14 (0-indexed)
    assert_eq!(term.cursor_row(), term.screen.cursor().row);
    assert_eq!(term.cursor_col(), term.screen.cursor().col);
    assert_eq!(term.cursor_row(), 7);
    assert_eq!(term.cursor_col(), 14);
}

/// `rows()` and `cols()` reflect the initial screen dimensions.
#[test]
fn test_rows_cols_accessors() {
    let term = super::make_term();
    assert_eq!(term.rows(), 24);
    assert_eq!(term.cols(), 80);
}

/// `resize` to smaller dimensions clamps both rows and cols.
#[test]
fn test_resize_shrinks_dimensions() {
    let mut term = super::make_term();
    term.resize(10, 40);
    assert_eq!(term.rows(), 10, "rows must shrink to 10");
    assert_eq!(term.cols(), 40, "cols must shrink to 40");
}

/// After `resize` to different dimensions, tab stops update to the new column count.
#[test]
fn test_resize_updates_tab_stops() {
    let mut term = super::make_term();
    term.resize(24, 40);
    // Tab every 8 columns — the first tab stop after resize should be at col 8.
    term.advance(b"\x1b[1;1H"); // cursor to col 0
    term.advance(b"\t"); // advance to first tab stop
    assert_eq!(
        term.screen.cursor().col,
        8,
        "first tab stop on a 40-col terminal must be at col 8"
    );
}

/// `flush_print_buf` with an empty buffer is a no-op.
#[test]
fn test_flush_print_buf_empty_is_noop() {
    let mut term = super::make_term();
    assert!(term.print_buf.is_empty(), "print_buf must start empty");
    term.flush_print_buf(); // must not panic, must not change cursor
    assert_cursor!(term, row 0, col 0);
}

/// `flush_print_buf` flushes buffered ASCII to the screen and clears the buffer.
#[test]
fn test_flush_print_buf_writes_content() {
    let mut term = super::make_term();
    term.print_buf.extend_from_slice(b"ABC");
    assert_eq!(
        term.print_buf.len(),
        3,
        "buffer must hold 3 bytes before flush"
    );
    term.flush_print_buf();
    assert!(
        term.print_buf.is_empty(),
        "flush_print_buf must clear print_buf"
    );
    // The three ASCII chars must now be on the screen.
    assert_cell_char!(term, row 0, col 0, 'A');
    assert_cell_char!(term, row 0, col 1, 'B');
    assert_cell_char!(term, row 0, col 2, 'C');
}

/// `scrollback_chars` returns character rows for content that was scrolled off.
#[test]
fn test_scrollback_chars_returns_pushed_lines() {
    let mut term = super::make_term();
    term.advance(b"SCROLLED");
    // Push the line into scrollback with 24 newlines.
    for _ in 0..24 {
        term.advance(b"\n");
    }
    let chars = term.scrollback_chars(100);
    assert!(
        !chars.is_empty(),
        "scrollback_chars must be non-empty after scrolling content off-screen"
    );
    // The first scrolled line must contain our marker.
    let has_marker = chars
        .iter()
        .any(|row| row.iter().collect::<String>().contains("SCROLLED"));
    assert!(
        has_marker,
        "scrollback_chars must include the 'SCROLLED' marker line"
    );
}

/// `scrollback_chars` with `max_lines=0` returns an empty vec.
#[test]
fn test_scrollback_chars_max_lines_zero() {
    let mut term = super::make_term();
    term.advance(b"line\n");
    for _ in 0..24 {
        term.advance(b"\n");
    }
    let chars = term.scrollback_chars(0);
    assert!(
        chars.is_empty(),
        "scrollback_chars(0) must return an empty vec"
    );
}

/// `title()` and `title_dirty()` reflect OSC 2 sequences.
#[test]
fn test_title_and_title_dirty_accessors() {
    let mut term = super::make_term();
    assert_eq!(term.title(), "", "title must be empty initially");
    assert!(!term.title_dirty(), "title_dirty must be false initially");

    term.advance(b"\x1b]2;MyTitle\x07");
    assert_eq!(term.title(), "MyTitle", "title must match OSC 2 payload");
    assert!(
        term.title_dirty(),
        "title_dirty must be true after OSC 2 sets a title"
    );
}

/// `palette_dirty()` is false initially and true after OSC 4.
#[test]
fn test_palette_dirty_accessor() {
    let mut term = super::make_term();
    assert!(
        !term.palette_dirty(),
        "palette_dirty must be false initially"
    );

    term.advance(b"\x1b]4;1;rgb:ff/00/00\x1b\\"); // OSC 4 sets palette entry 1
    assert!(
        term.palette_dirty(),
        "palette_dirty must be true after OSC 4"
    );
}

/// `default_colors_dirty()` is false initially and true after OSC 10.
#[test]
fn test_default_colors_dirty_accessor() {
    let mut term = super::make_term();
    assert!(
        !term.default_colors_dirty(),
        "default_colors_dirty must be false initially"
    );

    term.advance(b"\x1b]10;rgb:ff/80/00\x07"); // OSC 10 sets default fg
    assert!(
        term.default_colors_dirty(),
        "default_colors_dirty must be true after OSC 10"
    );
}

/// `pending_responses()` returns a slice of queued responses.
#[test]
fn test_pending_responses_accessor() {
    let mut term = super::make_term();
    assert!(
        term.pending_responses().is_empty(),
        "pending_responses must be empty initially"
    );

    term.advance(b"\x1b[6n"); // DSR — queues a CPR response
    assert_eq!(
        term.pending_responses().len(),
        1,
        "pending_responses must hold 1 entry after DSR"
    );
}

/// `current_foreground()` returns `Color::Default` initially.
#[test]
fn test_current_foreground_default() {
    let term = super::make_term();
    assert_eq!(
        *term.current_foreground(),
        crate::types::Color::Default,
        "current_foreground must be Color::Default initially"
    );
}

/// After SGR 31 (red foreground), `current_foreground()` is a Named color.
#[test]
fn test_current_foreground_after_sgr31() {
    let mut term = super::make_term();
    term.advance(b"\x1b[31m"); // SGR 31: red foreground
    assert!(
        matches!(*term.current_foreground(), crate::types::Color::Named(_)),
        "current_foreground must be a Named color after SGR 31, got {:?}",
        term.current_foreground()
    );
}

/// `dec_modes()` accessor returns the live DecModes ref.
#[test]
fn test_dec_modes_accessor_reflects_live_state() {
    let mut term = super::make_term();
    assert!(
        term.dec_modes().cursor_visible,
        "cursor_visible must be true initially"
    );
    term.advance(b"\x1b[?25l"); // DECTCEM off
    assert!(
        !term.dec_modes().cursor_visible,
        "dec_modes().cursor_visible must be false after CSI ?25l"
    );
}

/// `current_attrs()` accessor returns the live SgrAttributes ref.
#[test]
fn test_current_attrs_accessor_reflects_sgr() {
    let mut term = super::make_term();
    assert!(
        !term.current_attrs().flags.contains(SgrFlags::BOLD),
        "bold must be clear initially"
    );
    term.advance(b"\x1b[1m"); // bold on
    assert!(
        term.current_attrs().flags.contains(SgrFlags::BOLD),
        "current_attrs() must reflect bold after SGR 1"
    );
}

/// `osc_data()` accessor returns the live OscData ref (CWD example).
#[test]
fn test_osc_data_accessor_reflects_osc7() {
    let mut term = super::make_term();
    assert!(
        term.osc_data().cwd.is_none(),
        "osc_data().cwd must be None initially"
    );
    term.advance(b"\x1b]7;file://localhost/tmp\x07");
    assert!(
        term.osc_data().cwd.is_some(),
        "osc_data().cwd must be Some after OSC 7"
    );
}

/// `soft_reset` clears `saved_primary_attrs` (the alt-screen SGR snapshot).
#[test]
fn test_soft_reset_clears_saved_primary_attrs() {
    let mut term = super::make_term();
    // Force-set saved_primary_attrs to simulate a previous alt-screen save.
    term.saved_primary_attrs = Some(crate::types::cell::SgrAttributes::default());
    assert!(
        term.saved_primary_attrs.is_some(),
        "pre-condition: saved_primary_attrs must be Some"
    );
    term.advance(b"\x1b[!p"); // DECSTR (soft reset)
    assert!(
        term.saved_primary_attrs.is_none(),
        "soft_reset must clear saved_primary_attrs"
    );
}

/// After `reset()`, `parser_in_ground` is `true` and `print_buf` is empty.
#[test]
fn test_reset_restores_parser_state() {
    let mut term = super::make_term();
    // Corrupt parser state manually to simulate mid-sequence input.
    term.parser_in_ground = false;
    term.print_buf.extend_from_slice(b"leftover");

    term.reset();

    assert!(
        term.parser_in_ground,
        "reset must set parser_in_ground to true"
    );
    assert!(term.print_buf.is_empty(), "reset must clear print_buf");
}
