//! Integration tests for complex escape sequence interactions.

use kuro_core::{TerminalCore, types::cell::SgrFlags};

#[test]
fn test_decsc_decrc_saves_and_restores_cursor_position() {
    let mut term = TerminalCore::new(24, 80);
    // CSI 10;20H → 1-indexed row 10, col 20 → 0-indexed row 9, col 19
    term.advance(b"\x1b[10;20H");
    term.advance(b"\x1b7"); // DECSC: save cursor
    term.advance(b"\x1b[1;1H"); // move to row 0, col 0
    assert_eq!(term.cursor_row(), 0);
    term.advance(b"\x1b8"); // DECRC: restore cursor
    assert_eq!(term.cursor_row(), 9, "Row should be restored to 9");
    assert_eq!(term.cursor_col(), 19, "Col should be restored to 19");
}

#[test]
fn test_decsc_decrc_preserves_sgr_attributes() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[1m"); // bold on
    term.advance(b"\x1b7"); // save cursor (with attrs)
    term.advance(b"\x1b[0m"); // reset attrs
    assert!(!term.current_bold());
    term.advance(b"\x1b8"); // restore cursor (with attrs)
    assert!(term.current_bold(), "Bold should be restored after DECRC");
}

#[test]
fn test_cursor_movement_respects_screen_bounds() {
    let mut term = TerminalCore::new(5, 10);
    // Try to move cursor far outside bounds
    term.advance(b"\x1b[999;999H");
    assert!(term.cursor_row() < 5, "Row must be within 5");
    assert!(term.cursor_col() < 10, "Col must be within 10");
}

#[test]
fn test_ris_full_reset_clears_screen() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"Hello World\x1b[1m");
    term.advance(b"\x1bc"); // RIS: Full Reset
    assert!(!term.current_bold(), "Bold should be cleared after RIS");
    assert_eq!(term.cursor_row(), 0);
    assert_eq!(term.cursor_col(), 0);
}

#[test]
fn test_sgr_true_color_foreground_no_panic() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[38;2;255;128;0m"); // truecolor orange foreground
    // Must not panic, and cursor remains in bounds
    assert!(term.cursor_row() < 24);
}

#[test]
fn test_sgr_256_color_foreground_no_panic() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[38;5;196m"); // indexed color 196 (bright red in 256-color)
    assert!(term.cursor_row() < 24);
}

#[test]
fn test_insert_and_delete_chars_no_panic() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"ABCDE");
    term.advance(b"\x1b[1;3H"); // move to row 1, col 3 (1-indexed → row 0, col 2)
    term.advance(b"\x1b[1P"); // DCH: delete 1 char
    // Must not panic
    assert!(term.cursor_col() < 80);
}

#[test]
fn test_scroll_up_with_region_no_panic() {
    let mut term = TerminalCore::new(10, 80);
    term.advance(b"\x1b[3;7r"); // scroll region rows 3-7
    term.advance(b"\x1b[3;1H"); // move to top of region (1-indexed → row 2, col 0)
    term.advance(b"\x1b[S"); // SU: scroll up
    // Must not panic, cursor in bounds
    assert!(term.cursor_row() < 10);
}

#[test]
fn test_complex_sequence_does_not_panic() {
    let mut term = TerminalCore::new(24, 80);
    // A realistic terminal initialization sequence
    let init_seq = b"\x1b[?2004h\x1b[?1h\x1b=\x1b[?25h\x1b[?1049h\x1b[22;0;0t";
    term.advance(init_seq);
    // Must not panic, screen in valid state
    assert!(term.cursor_row() < 24);
    assert!(term.cursor_col() < 80);
}

#[test]
fn test_osc_title_set() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b]2;hello title\x07"); // OSC 2: set window title
    // Must not panic, cursor in bounds
    assert!(term.cursor_row() < 24);
}

#[test]
fn test_sgr_bold_italic_combined() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[1;3m"); // bold + italic in one SGR
    assert!(term.current_bold(), "Bold should be set");
    assert!(term.current_italic(), "Italic should be set");
}

#[test]
fn test_sgr_reset_clears_all_attributes() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[1;3;4m"); // bold + italic + underline
    assert!(term.current_bold());
    assert!(term.current_italic());
    assert!(term.current_underline());
    term.advance(b"\x1b[0m"); // SGR 0: reset all
    assert!(!term.current_bold(), "Bold should be cleared");
    assert!(!term.current_italic(), "Italic should be cleared");
    assert!(!term.current_underline(), "Underline should be cleared");
}

#[test]
fn test_cursor_position_after_csi_h_command() {
    let mut term = TerminalCore::new(24, 80);
    // CSI 5;10H = move to row 5, col 10 (1-indexed) → row 4, col 9 (0-indexed)
    term.advance(b"\x1b[5;10H");
    assert_eq!(term.cursor_row(), 4);
    assert_eq!(term.cursor_col(), 9);
}

#[test]
fn test_deckpam_deckpnm_no_panic() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b="); // DECKPAM: application keypad
    term.advance(b"\x1b>"); // DECKPNM: normal keypad
    // Must not panic
    assert!(term.cursor_row() < 24);
}

#[test]
fn test_line_feed_scrolls_at_bottom() {
    let mut term = TerminalCore::new(5, 80);
    // Fill screen with newlines to force scrolling
    for _ in 0..10 {
        term.advance(b"\n");
    }
    // Cursor must stay within bounds after scrolling
    assert!(term.cursor_row() < 5, "Row must stay < 5 after scroll");
}

#[test]
fn test_get_cell_returns_printed_char() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"XYZ");
    let cell_x = term.get_cell(0, 0).expect("cell (0,0) should exist");
    let cell_y = term.get_cell(0, 1).expect("cell (0,1) should exist");
    let cell_z = term.get_cell(0, 2).expect("cell (0,2) should exist");
    assert_eq!(cell_x.char(), 'X');
    assert_eq!(cell_y.char(), 'Y');
    assert_eq!(cell_z.char(), 'Z');
}

// ─────────────────────────────────────────────────────────────────────────────
// New tests: DECALN, VT52, character set, split-boundary advance()
// ─────────────────────────────────────────────────────────────────────────────

/// DECALN (`ESC # 8`) is not implemented in this emulator; it must be
/// silently ignored without panicking and must leave the cursor in bounds.
#[test]
fn test_decaln_esc_hash_8_does_not_panic() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b#8"); // DECALN: DEC Screen Alignment Test
    // Must not panic and cursor must remain in bounds
    assert!(
        term.cursor_row() < 24,
        "Row must stay within 24 after DECALN"
    );
    assert!(
        term.cursor_col() < 80,
        "Col must stay within 80 after DECALN"
    );
}

/// VT52 mode entry sequence (`ESC [ ? 2 l`) is handled as a DEC private mode
/// toggle, and the cursor must remain in bounds without panic.
#[test]
fn test_vt52_mode_entry_does_not_panic() {
    let mut term = TerminalCore::new(24, 80);
    // CSI ?2l — reset DECANM (switches to VT52 mode in real hardware;
    // this emulator ignores the mode silently)
    term.advance(b"\x1b[?2l");
    assert!(term.cursor_row() < 24);
    assert!(term.cursor_col() < 80);
}

/// Character set designation sequences (SCS: `ESC ( B`, `ESC ) 0`, etc.)
/// are unimplemented and must be silently ignored without panicking.
#[test]
fn test_scs_charset_designation_does_not_panic() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b(B"); // G0 = USASCII
    term.advance(b"\x1b)0"); // G1 = DEC Special
    term.advance(b"\x1b*B"); // G2 = USASCII
    term.advance(b"\x1b+0"); // G3 = DEC Special
    assert!(term.cursor_row() < 24);
    assert!(term.cursor_col() < 80);
}

/// NEL (`ESC E`) performs CR + LF (Next Line).  After printing a character
/// at column >0, NEL must move the cursor to column 0 of the next row.
#[test]
fn test_nel_moves_to_column_zero_of_next_row() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"Hello"); // cursor now at col 5, row 0
    assert_eq!(term.cursor_col(), 5);
    assert_eq!(term.cursor_row(), 0);
    term.advance(b"\x1bE"); // NEL: Next Line
    assert_eq!(term.cursor_col(), 0, "NEL must reset column to 0");
    assert_eq!(term.cursor_row(), 1, "NEL must advance row by 1");
}

/// RI (`ESC M`) moves the cursor up one line.  At the top of the scroll
/// region a scroll-down must occur, keeping the cursor at the top row.
#[test]
fn test_ri_reverse_index_moves_cursor_up() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[3;1H"); // move to row 3, col 1 (1-indexed → row 2, col 0)
    assert_eq!(term.cursor_row(), 2);
    term.advance(b"\x1bM"); // RI: Reverse Index
    assert_eq!(term.cursor_row(), 1, "RI must move cursor up one row");
    assert_eq!(term.cursor_col(), 0);
}

/// RI (`ESC M`) at the top of the scroll region must not push the cursor
/// above row 0 — a scroll-down occurs instead.
#[test]
fn test_ri_at_top_of_screen_stays_within_bounds() {
    let mut term = TerminalCore::new(24, 80);
    // Cursor already at row 0 after construction
    assert_eq!(term.cursor_row(), 0);
    term.advance(b"\x1bM"); // RI at the very top — triggers scroll-down
    assert_eq!(
        term.cursor_row(),
        0,
        "Cursor must stay at row 0 after RI scroll"
    );
}

/// A CSI sequence split exactly across two separate `advance()` calls must
/// be parsed identically to delivering all bytes in one call.
#[test]
fn test_csi_split_across_two_advance_calls_is_equivalent() {
    // Reference: one-shot delivery
    let mut ref_term = TerminalCore::new(24, 80);
    ref_term.advance(b"\x1b[5;10H"); // CSI 5;10H in one call

    // Split at every byte boundary of the CSI sequence and verify
    let seq = b"\x1b[5;10H";
    for split in 1..seq.len() {
        let mut split_term = TerminalCore::new(24, 80);
        split_term.advance(&seq[..split]);
        split_term.advance(&seq[split..]);
        assert_eq!(
            split_term.cursor_row(),
            ref_term.cursor_row(),
            "split at byte {split}: cursor row must match"
        );
        assert_eq!(
            split_term.cursor_col(),
            ref_term.cursor_col(),
            "split at byte {split}: cursor col must match"
        );
    }
}

/// An SGR sequence split across two `advance()` calls must set attributes
/// identically to the unsplit delivery.
#[test]
fn test_sgr_split_across_two_advance_calls_is_equivalent() {
    let seq = b"\x1b[1;3m"; // bold + italic
    for split in 1..seq.len() {
        let mut t = TerminalCore::new(24, 80);
        t.advance(&seq[..split]);
        t.advance(&seq[split..]);
        assert!(t.current_bold(), "split at byte {split}: bold must be set");
        assert!(
            t.current_italic(),
            "split at byte {split}: italic must be set"
        );
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// New tests: DECAWM, cursor movement, EL, SGR extras, insert/delete lines
// ─────────────────────────────────────────────────────────────────────────────

/// DECAWM off (?7l) must suppress wrap: printing past column 9 on a 10-col
/// terminal must not advance the cursor to row 1.
#[test]
fn test_decawm_off_suppresses_wrap() {
    let mut term = TerminalCore::new(10, 10);
    term.advance(b"\x1b[?7l"); // DECAWM off
    // Print 15 characters; without wrap the cursor should stay on row 0
    term.advance(b"AAAAABBBBBCCCCC");
    assert_eq!(
        term.cursor_row(),
        0,
        "DECAWM off: cursor must stay on row 0"
    );
}

/// Re-enabling DECAWM (?7h) after it was disabled must restore wrap behaviour.
#[test]
fn test_decawm_on_restores_wrap() {
    let mut term = TerminalCore::new(5, 5);
    term.advance(b"\x1b[?7l"); // DECAWM off
    term.advance(b"\x1b[?7h"); // DECAWM on
    // 6 chars on a 5-col terminal: the 6th must wrap to row 1
    term.advance(b"XXXXXY");
    assert_eq!(term.cursor_row(), 1, "DECAWM on: cursor must wrap to row 1");
    let cell = term
        .get_cell(1, 0)
        .expect("cell (1,0) must exist after wrap");
    assert_eq!(cell.char(), 'Y', "'Y' must land at row 1, col 0 after wrap");
}

/// CUB (CSI n D) moves the cursor left by n columns, clamping at column 0.
#[test]
fn test_cub_cursor_backward_clamp() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[1;10H"); // col 9 (0-indexed)
    assert_eq!(term.cursor_col(), 9);
    term.advance(b"\x1b[3D"); // CUB 3 → col 6
    assert_eq!(term.cursor_col(), 6, "CUB 3 from col 9 must land on col 6");
    // CUB with a count larger than current col must clamp to 0
    term.advance(b"\x1b[100D");
    assert_eq!(term.cursor_col(), 0, "CUB 100 must clamp cursor to col 0");
}

/// CUF (CSI n C) moves the cursor right by n columns, clamping at the right margin.
#[test]
fn test_cuf_cursor_forward_clamp() {
    let mut term = TerminalCore::new(24, 10);
    term.advance(b"\x1b[1;1H"); // col 0
    term.advance(b"\x1b[3C"); // CUF 3 → col 3
    assert_eq!(term.cursor_col(), 3, "CUF 3 from col 0 must land on col 3");
    // CUF with a large count must clamp at last column (9 on a 10-col terminal)
    term.advance(b"\x1b[100C");
    assert_eq!(
        term.cursor_col(),
        9,
        "CUF 100 must clamp cursor to last col (9)"
    );
}

/// CUD (CSI n B) moves the cursor down by n rows, clamping at the last row.
#[test]
fn test_cud_cursor_down_clamp() {
    let mut term = TerminalCore::new(10, 80);
    term.advance(b"\x1b[1;1H"); // row 0
    term.advance(b"\x1b[3B"); // CUD 3 → row 3
    assert_eq!(term.cursor_row(), 3, "CUD 3 from row 0 must land on row 3");
    term.advance(b"\x1b[100B"); // CUD large → clamp at last row (9)
    assert_eq!(
        term.cursor_row(),
        9,
        "CUD 100 must clamp cursor to last row (9)"
    );
}

/// EL 0 (CSI 0 K) erases from cursor to end of line.
#[test]
fn test_el0_erases_to_end_of_line() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"ABCDE");
    term.advance(b"\x1b[1;3H"); // move to row 0, col 2 (1-indexed)
    term.advance(b"\x1b[0K"); // EL 0: erase from cursor to EOL
    // Cells 0 and 1 must still hold 'A' and 'B'; cells from col 2 onward must be erased
    let a = term.get_cell(0, 0).expect("cell (0,0) must exist");
    let b = term.get_cell(0, 1).expect("cell (0,1) must exist");
    assert_eq!(a.char(), 'A', "cell (0,0) must be 'A' — not erased by EL 0");
    assert_eq!(b.char(), 'B', "cell (0,1) must be 'B' — not erased by EL 0");
    let c = term.get_cell(0, 2).expect("cell (0,2) must exist");
    assert_eq!(c.char(), ' ', "cell (0,2) must be erased (space) by EL 0");
}

/// EL 1 (CSI 1 K) erases from beginning of line to cursor (inclusive).
#[test]
fn test_el1_erases_to_start_of_line() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"ABCDE");
    term.advance(b"\x1b[1;4H"); // move to row 0, col 3 (1-indexed)
    term.advance(b"\x1b[1K"); // EL 1: erase from BOL to cursor
    // Cols 0–3 must be spaces; col 4 must still hold 'E'
    for col in 0..=3 {
        let cell = term.get_cell(0, col).expect("cell must exist");
        assert_eq!(
            cell.char(),
            ' ',
            "cell (0,{col}) must be erased (space) by EL 1"
        );
    }
    let e = term.get_cell(0, 4).expect("cell (0,4) must exist");
    assert_eq!(e.char(), 'E', "cell (0,4) must survive EL 1");
}

/// SGR strikethrough (9) and blink (5) must set the corresponding flags.
#[test]
fn test_sgr_strikethrough_and_blink() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[9m"); // strikethrough on
    let attrs = term.current_attrs();
    assert!(
        attrs.flags.contains(SgrFlags::STRIKETHROUGH),
        "strikethrough must be set after SGR 9"
    );
    term.advance(b"\x1b[5m"); // blink-slow on
    let attrs2 = term.current_attrs();
    assert!(
        attrs2.flags.contains(SgrFlags::BLINK_SLOW),
        "blink must be set after SGR 5"
    );
    // SGR 0 must clear both
    term.advance(b"\x1b[0m");
    let attrs3 = term.current_attrs();
    assert!(
        !attrs3.flags.contains(SgrFlags::STRIKETHROUGH),
        "strikethrough cleared by SGR 0"
    );
    assert!(
        !attrs3.flags.contains(SgrFlags::BLINK_SLOW),
        "blink cleared by SGR 0"
    );
}

/// SGR reverse video (7) must set the INVERSE flag.
#[test]
fn test_sgr_reverse_video() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[7m"); // reverse on
    let attrs = term.current_attrs();
    assert!(
        attrs.flags.contains(SgrFlags::INVERSE),
        "INVERSE must be set after SGR 7"
    );
    term.advance(b"\x1b[0m");
    assert!(
        !term.current_attrs().flags.contains(SgrFlags::INVERSE),
        "INVERSE cleared by SGR 0"
    );
}

/// IL (CSI n L) inserts n blank lines at the cursor row, scrolling down.
/// The cursor must not leave the scroll region and no panic must occur.
#[test]
fn test_il_insert_lines_no_panic() {
    let mut term = TerminalCore::new(10, 80);
    term.advance(b"line0\nline1\nline2");
    term.advance(b"\x1b[2;1H"); // move to row 1 (1-indexed)
    term.advance(b"\x1b[2L"); // IL 2: insert 2 blank lines
    assert!(
        term.cursor_row() < 10,
        "cursor row must remain in bounds after IL"
    );
}

/// DL (CSI n M) deletes n lines at the cursor row, scrolling up within the region.
/// No panic must occur and cursor must stay in bounds.
#[test]
fn test_dl_delete_lines_no_panic() {
    let mut term = TerminalCore::new(10, 80);
    term.advance(b"line0\nline1\nline2\nline3");
    term.advance(b"\x1b[2;1H"); // move to row 1 (1-indexed)
    term.advance(b"\x1b[2M"); // DL 2: delete 2 lines
    assert!(
        term.cursor_row() < 10,
        "cursor row must remain in bounds after DL"
    );
}
