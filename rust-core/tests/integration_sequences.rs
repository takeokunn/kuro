//! Integration tests for complex escape sequence interactions.

use kuro_core::TerminalCore;

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
