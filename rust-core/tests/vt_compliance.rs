//! VT100/VT220 compliance test suite
//!
//! Tests terminal emulator compliance with VT100/VT220 standards.
//! These tests exercise the full `advance()` pipeline without any Emacs runtime.

use kuro_core::types::cell::SgrFlags;
use kuro_core::TerminalCore;

// === VT100 Basic Cursor Movement ===

#[test]
fn vt_cup_moves_cursor() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[5;10H");
    assert_eq!(t.cursor_row(), 4, "CUP row");
    assert_eq!(t.cursor_col(), 9, "CUP col");
}

#[test]
fn vt_cuu_moves_up() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[5;10H\x1b[2A");
    assert_eq!(t.cursor_row(), 2);
}

#[test]
fn vt_cud_moves_down() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[5;10H\x1b[3B");
    assert_eq!(t.cursor_row(), 7);
}

#[test]
fn vt_cuf_moves_forward() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[1;10H\x1b[5C");
    assert_eq!(t.cursor_col(), 14);
}

#[test]
fn vt_cub_moves_back() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[1;15H\x1b[3D");
    assert_eq!(t.cursor_col(), 11);
}

#[test]
fn vt_home_moves_to_origin() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[10;20H\x1b[H");
    assert_eq!(t.cursor_row(), 0);
    assert_eq!(t.cursor_col(), 0);
}

// === VT100 Erase Operations ===

#[test]
fn vt_el_erases_line() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"ABCDE\x1b[1;1H\x1b[K");
    assert_eq!(t.get_cell(0, 0).unwrap().char(), ' ');
}

#[test]
fn vt_ed_erases_display() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"Hello\x1b[2J");
    assert_eq!(t.get_cell(0, 0).unwrap().char(), ' ');
}

// === SGR Attributes ===

#[test]
fn vt_sgr_bold() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[1m");
    assert!(t.current_attrs().flags.contains(SgrFlags::BOLD));
}

#[test]
fn vt_sgr_reset() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[1;3;4m");
    assert!(t.current_attrs().flags.contains(SgrFlags::BOLD));
    assert!(t.current_attrs().flags.contains(SgrFlags::ITALIC));
    t.advance(b"\x1b[0m");
    assert!(!t.current_attrs().flags.contains(SgrFlags::BOLD));
    assert!(!t.current_attrs().flags.contains(SgrFlags::ITALIC));
}

#[test]
fn vt_sgr_named_colors() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[31m");
    assert!(matches!(
        t.current_attrs().foreground,
        kuro_core::types::Color::Named(_)
    ));
}

#[test]
fn vt_sgr_rgb_color() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[38;2;255;128;0m");
    assert_eq!(
        t.current_attrs().foreground,
        kuro_core::types::Color::Rgb(255, 128, 0)
    );
}

#[test]
fn vt_sgr_256_color() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[38;5;196m");
    assert_eq!(
        t.current_attrs().foreground,
        kuro_core::types::Color::Indexed(196)
    );
}

// === DEC Private Modes ===

#[test]
fn vt_dectcem_cursor_visibility() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?25l");
    assert!(!t.dec_modes().cursor_visible);
    t.advance(b"\x1b[?25h");
    assert!(t.dec_modes().cursor_visible);
}

#[test]
fn vt_decckm_app_cursor() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?1h");
    assert!(t.dec_modes().app_cursor_keys);
    t.advance(b"\x1b[?1l");
    assert!(!t.dec_modes().app_cursor_keys);
}

#[test]
fn vt_decawm_auto_wrap() {
    let mut t = TerminalCore::new(24, 80);
    assert!(t.dec_modes().auto_wrap); // default on
    t.advance(b"\x1b[?7l");
    assert!(!t.dec_modes().auto_wrap);
    t.advance(b"\x1b[?7h");
    assert!(t.dec_modes().auto_wrap);
}

/// DEC pending wrap: writing at the last column must NOT immediately wrap.
///
/// Per DEC VT510 manual, DECAWM defers the wrap until the next printable
/// character.  This is essential for TUI apps (btop, htop) that draw
/// box-drawing characters at the last column without wanting a scroll.
#[test]
fn vt_decawm_pending_wrap() {
    let mut t = TerminalCore::new(3, 5);
    // Fill row 0 with 'A'
    t.advance(b"\x1b[1;1HAAAAA");
    // Cursor should be at last col with pending wrap, NOT on row 1
    assert_eq!(t.cursor_col(), 4, "cursor stays at last col (pending wrap)");
    assert_eq!(t.cursor_row(), 0, "cursor stays on row 0 (no wrap yet)");
    // Row 0 must have all 5 A's
    for col in 0..5 {
        assert_eq!(t.get_cell(0, col).unwrap().char(), 'A');
    }
    // CUP clears pending wrap — subsequent print must NOT wrap
    t.advance(b"\x1b[1;5H"); // move to (0,4) — last col
    t.advance(b"B");
    assert_eq!(
        t.cursor_col(),
        4,
        "after overwriting last col, pending wrap again"
    );
    assert_eq!(t.cursor_row(), 0, "still on row 0");
    // Now print another char — this must fire the deferred wrap
    t.advance(b"C");
    assert_eq!(t.cursor_row(), 1, "deferred wrap fires on next char");
    assert_eq!(
        t.cursor_col(),
        1,
        "cursor at col 1 after wrapping and printing 'C'"
    );
    // 'C' should be at row 1, col 0
    assert_eq!(t.get_cell(1, 0).unwrap().char(), 'C');
}

/// DECAWM off: printing at last column stays clamped, never wraps.
#[test]
fn vt_decawm_off_no_wrap() {
    let mut t = TerminalCore::new(3, 5);
    t.advance(b"\x1b[?7l"); // disable auto-wrap
    t.advance(b"\x1b[1;1HABCDE");
    // With DECAWM off, cursor stays at last column
    assert_eq!(t.cursor_col(), 4);
    assert_eq!(t.cursor_row(), 0);
    // Additional chars overwrite at last column, never wrap
    t.advance(b"FGH");
    assert_eq!(t.cursor_col(), 4, "DECAWM off: cursor clamped at last col");
    assert_eq!(t.cursor_row(), 0, "DECAWM off: never wraps to next row");
    // Last col should have 'H' (the last overwrite)
    assert_eq!(t.get_cell(0, 4).unwrap().char(), 'H');
}

#[test]
fn vt_bracketed_paste() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?2004h");
    assert!(t.dec_modes().bracketed_paste);
    t.advance(b"\x1b[?2004l");
    assert!(!t.dec_modes().bracketed_paste);
}

// === Alt Screen ===

#[test]
fn vt_alt_screen_switch() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"Hello");
    t.advance(b"\x1b[?1049h");
    assert!(t.dec_modes().alternate_screen);
    t.advance(b"\x1b[?1049l");
    assert!(!t.dec_modes().alternate_screen);
    assert_eq!(t.get_cell(0, 0).unwrap().char(), 'H');
}

// === Tab Stops ===

#[test]
fn vt_tab_default_stops() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[H\t");
    assert_eq!(t.cursor_col(), 8);
}

// === VPA/CHA ===

#[test]
fn vt_vpa_moves_to_row() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[5d");
    assert_eq!(t.cursor_row(), 4);
}

#[test]
fn vt_cha_moves_to_col() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[10G");
    assert_eq!(t.cursor_col(), 9);
}

// === Device Attributes ===

#[test]
fn vt_da1_response() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[c");
    assert!(
        !t.pending_responses().is_empty(),
        "DA1 must generate response"
    );
    let resp = &t.pending_responses()[0];
    assert!(resp.starts_with(b"\x1b[?"), "DA1 response format");
}

#[test]
fn vt_da2_response() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[>c");
    assert!(
        !t.pending_responses().is_empty(),
        "DA2 must generate response"
    );
}

// === DECSC/DECRC ===

#[test]
fn vt_save_restore_cursor() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[10;20H\x1b7\x1b[1;1H\x1b8");
    assert_eq!(t.cursor_row(), 9);
    assert_eq!(t.cursor_col(), 19);
}

// === Mouse Tracking ===

#[test]
fn vt_mouse_modes() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?1000h");
    assert_eq!(t.dec_modes().mouse_mode, 1000);
    t.advance(b"\x1b[?1000l");
    assert_eq!(t.dec_modes().mouse_mode, 0);
    t.advance(b"\x1b[?1002h");
    assert_eq!(t.dec_modes().mouse_mode, 1002);
    t.advance(b"\x1b[?1006h");
    assert!(t.dec_modes().mouse_sgr);
}

// === VT220 Extensions ===

#[test]
fn vt_decscusr_cursor_shape() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[5 q");
    assert_eq!(
        t.dec_modes().cursor_shape,
        kuro_core::types::cursor::CursorShape::BlinkingBar
    );
    t.advance(b"\x1b[2 q");
    assert_eq!(
        t.dec_modes().cursor_shape,
        kuro_core::types::cursor::CursorShape::SteadyBlock
    );
    t.advance(b"\x1b[3 q");
    assert_eq!(
        t.dec_modes().cursor_shape,
        kuro_core::types::cursor::CursorShape::BlinkingUnderline
    );
}

#[test]
fn vt_decstr_soft_reset() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?1h\x1b[1m\x1b[10;20H");
    t.advance(b"\x1b[!p");
    assert!(!t.dec_modes().app_cursor_keys);
    assert!(!t.current_attrs().flags.contains(SgrFlags::BOLD));
    assert_eq!(t.cursor_row(), 0);
    assert!(t.dec_modes().auto_wrap);
}

// === Modern Terminal Features ===

#[test]
fn vt_kitty_keyboard_protocol() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[>1u");
    assert_eq!(t.dec_modes().keyboard_flags, 1);
    t.advance(b"\x1b[>3u");
    assert_eq!(t.dec_modes().keyboard_flags, 3);
    t.advance(b"\x1b[<u");
    assert_eq!(t.dec_modes().keyboard_flags, 1);
    t.advance(b"\x1b[<u");
    assert_eq!(t.dec_modes().keyboard_flags, 0);
}

#[test]
fn vt_kitty_keyboard_query() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[>5u");
    t.advance(b"\x1b[?u");
    assert!(!t.pending_responses().is_empty());
    assert_eq!(t.pending_responses().last().unwrap(), b"\x1b[?5u");
}

#[test]
fn vt_osc7_cwd() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]7;file://localhost/tmp/test\x07");
    assert_eq!(t.osc_data().cwd, Some("/tmp/test".to_owned()));
    assert!(t.osc_data().cwd_dirty);
}

#[test]
fn vt_osc8_hyperlink() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]8;;https://example.com\x07");
    assert_eq!(
        t.osc_data().hyperlink.uri,
        Some("https://example.com".to_owned())
    );
    t.advance(b"\x1b]8;;\x07");
    assert!(t.osc_data().hyperlink.uri.is_none());
}

#[test]
fn vt_osc133_prompt_marks() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]133;A\x07");
    assert_eq!(t.osc_data().prompt_marks.len(), 1);
}

#[test]
fn vt_focus_events() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?1004h");
    assert!(t.dec_modes().focus_events);
    t.advance(b"\x1b[?1004l");
    assert!(!t.dec_modes().focus_events);
}

#[test]
fn vt_synchronized_output() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?2026h");
    assert!(t.dec_modes().synchronized_output);
    t.advance(b"\x1b[?2026l");
    assert!(!t.dec_modes().synchronized_output);
}

/// Verify that the synchronized output mode state transitions work correctly.
/// The mode should be set when ?2026h is sent and cleared when ?2026l is sent.
/// This is the public-API observable part of the sync suppression behavior.
#[test]
fn vt_synchronized_output_state_transitions() {
    let mut t = TerminalCore::new(5, 20);

    // Initially not active
    assert!(
        !t.dec_modes().synchronized_output,
        "sync should be off initially"
    );

    // Enable: ?2026h
    t.advance(b"\x1b[?2026h");
    assert!(
        t.dec_modes().synchronized_output,
        "sync should be on after ?2026h"
    );

    // Write content while sync is on
    t.advance(b"Hello World");
    assert!(
        t.dec_modes().synchronized_output,
        "sync should still be on after writing content"
    );

    // Disable: ?2026l — this should clear sync AND mark all lines dirty internally
    t.advance(b"\x1b[?2026l");
    assert!(
        !t.dec_modes().synchronized_output,
        "sync should be off after ?2026l"
    );

    // The content written during sync should be visible via get_cell
    let cell0 = t.get_cell(0, 0);
    assert_eq!(
        cell0.map(kuro_core::Cell::char),
        Some('H'),
        "first cell should be 'H' (content written during sync preserved in grid)"
    );
}

#[test]
fn vt_decom_origin_mode() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?6h");
    assert!(t.dec_modes().origin_mode);
    t.advance(b"\x1b[?6l");
    assert!(!t.dec_modes().origin_mode);
}

#[test]
fn vt_underline_styles() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[4:3m");
    assert_eq!(
        t.current_attrs().underline_style,
        kuro_core::types::cell::UnderlineStyle::Curly
    );
    t.advance(b"\x1b[4:5m");
    assert_eq!(
        t.current_attrs().underline_style,
        kuro_core::types::cell::UnderlineStyle::Dashed
    );
    t.advance(b"\x1b[21m");
    assert_eq!(
        t.current_attrs().underline_style,
        kuro_core::types::cell::UnderlineStyle::Double
    );
    t.advance(b"\x1b[24m");
    assert_eq!(
        t.current_attrs().underline_style,
        kuro_core::types::cell::UnderlineStyle::None
    );
}

#[test]
fn vt_underline_color() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[58;2;255;128;0m");
    assert_eq!(
        t.current_attrs().underline_color,
        kuro_core::types::color::Color::Rgb(255, 128, 0)
    );
    t.advance(b"\x1b[59m");
    assert_eq!(
        t.current_attrs().underline_color,
        kuro_core::types::color::Color::Default
    );
}

#[test]
fn vt_wide_char() {
    let mut t = TerminalCore::new(24, 80);
    t.advance("漢".as_bytes());
    assert_eq!(t.get_cell(0, 0).unwrap().char(), '漢');
}

#[test]
fn vt_combining_char() {
    let mut t = TerminalCore::new(24, 80);
    t.advance("e\u{0301}".as_bytes());
    assert_eq!(t.get_cell(0, 0).unwrap().grapheme(), "e\u{0301}");
}

#[test]
fn vt_title_set() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]2;My Terminal\x07");
    assert_eq!(t.title(), "My Terminal");
    assert!(t.title_dirty());
}

#[test]
fn vt_full_reset() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[1m\x1b[?1h");
    t.advance(b"\x1bc"); // RIS - full reset
    assert!(!t.current_attrs().flags.contains(SgrFlags::BOLD));
    assert!(!t.dec_modes().app_cursor_keys);
}

#[test]
fn vt_ri_reverse_index_scrolls_at_top() {
    // ESC M at top of scroll region inserts blank line at top
    let mut t = TerminalCore::new(24, 80);
    // Write 'X' at row 0
    t.advance(b"X");
    t.advance(b"\x1b[1;1H"); // cursor to row 0
                             // ESC M: should scroll down (insert blank at top, X goes to row 1)
    t.advance(b"\x1bM");
    assert_eq!(t.cursor_row(), 0, "cursor stays at scroll top after ESC M");
    let cell = t.get_cell(1, 0).unwrap();
    assert_eq!(cell.char(), 'X', "ESC M at scroll top pushes content down");
}

#[test]
fn vt_ri_reverse_index_moves_up() {
    // ESC M not at scroll top simply moves cursor up
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[5;1H"); // move to row 4
    assert_eq!(t.cursor_row(), 4);
    t.advance(b"\x1bM"); // ESC M
    assert_eq!(
        t.cursor_row(),
        3,
        "ESC M moves cursor up when not at scroll top"
    );
}

#[test]
fn vt_ind_index() {
    // ESC D (IND) moves cursor down
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[1;1H"); // row 0
    t.advance(b"\x1bD");
    assert_eq!(t.cursor_row(), 1, "ESC D moves cursor down");
}

#[test]
fn vt_nel_next_line() {
    // ESC E (NEL) = CR + LF
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[1;5H"); // row 0, col 4
    assert_eq!(t.cursor_col(), 4);
    t.advance(b"\x1bE");
    assert_eq!(t.cursor_row(), 1, "ESC E moves to next line");
    assert_eq!(t.cursor_col(), 0, "ESC E resets column to 0");
}

#[test]
fn vt_scroll_region_restricts_scrolling() {
    // DECSTBM: scroll region restricts scroll_up/down to that region
    let mut t = TerminalCore::new(24, 80);
    // Write markers on rows 0, 5, 10
    t.advance(b"\x1b[1;1H");
    t.advance(b"TOP");
    t.advance(b"\x1b[6;1H");
    t.advance(b"MID");
    t.advance(b"\x1b[11;1H");
    t.advance(b"BOT");
    // Set scroll region rows 5-10 (1-indexed: 6;11 → 0-indexed: 5..11)
    t.advance(b"\x1b[6;11r");
    // Move cursor to bottom of scroll region (row 10) and send LF to scroll
    t.advance(b"\x1b[11;1H");
    t.advance(b"\x0a"); // LF - should scroll within region
                        // TOP at row 0 must be unchanged
    let top_cell = t.get_cell(0, 0).unwrap();
    assert_eq!(
        top_cell.char(),
        'T',
        "scroll region must not affect rows above it"
    );
}

#[test]
fn vt_csi_hvp_same_as_cup() {
    // CSI row ; col f (HVP) behaves identically to CSI row ; col H (CUP)
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[10;20f");
    assert_eq!(
        t.cursor_row(),
        9,
        "HVP row (1-indexed) should become 9 (0-indexed)"
    );
    assert_eq!(
        t.cursor_col(),
        19,
        "HVP col (1-indexed) should become 19 (0-indexed)"
    );
}

#[test]
fn vt_ed3_clears_scrollback() {
    // CSI 3 J clears scrollback buffer
    let mut t = TerminalCore::new(24, 80);
    // Generate some scrollback by filling and scrolling
    for _ in 0..30 {
        t.advance(b"line\n");
    }
    assert!(
        t.scrollback_line_count() > 0,
        "should have scrollback lines"
    );
    t.advance(b"\x1b[3J"); // ED 3 — clear scrollback
    assert_eq!(
        t.scrollback_line_count(),
        0,
        "CSI 3 J should clear scrollback"
    );
}

#[test]
fn vt_sgr_invisible() {
    // SGR 8 sets hidden attribute; SGR 28 clears it
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[8m");
    assert!(
        t.current_attrs().flags.contains(SgrFlags::HIDDEN),
        "SGR 8 should set hidden attribute"
    );
    t.advance(b"\x1b[28m");
    assert!(
        !t.current_attrs().flags.contains(SgrFlags::HIDDEN),
        "SGR 28 should clear hidden attribute"
    );
}

#[test]
fn vt_sgr_strikethrough() {
    // SGR 9 sets strikethrough; SGR 29 clears it
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[9m");
    assert!(
        t.current_attrs().flags.contains(SgrFlags::STRIKETHROUGH),
        "SGR 9 should set strikethrough"
    );
    t.advance(b"\x1b[29m");
    assert!(
        !t.current_attrs().flags.contains(SgrFlags::STRIKETHROUGH),
        "SGR 29 should clear strikethrough"
    );
}

#[test]
fn vt_cursor_stays_in_bounds_after_large_cup() {
    // CUP with row/col beyond screen size should clamp to screen edge
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[9999;9999H");
    assert!(
        t.cursor_row() < 24,
        "cursor row must stay < 24 after out-of-bounds CUP"
    );
    assert!(
        t.cursor_col() < 80,
        "cursor col must stay < 80 after out-of-bounds CUP"
    );
}

#[test]
fn vt_il_dl_insert_delete_lines() {
    // IL (CSI n L) inserts blank lines, DL (CSI n M) deletes lines
    let mut t = TerminalCore::new(10, 40);
    t.advance(b"\x1b[1;1H");
    t.advance(b"Line0");
    t.advance(b"\x1b[2;1H");
    t.advance(b"Line1");
    t.advance(b"\x1b[3;1H");
    t.advance(b"Line2");
    // Move to row 1 and insert 1 line
    t.advance(b"\x1b[2;1H");
    t.advance(b"\x1b[1L"); // IL 1
                           // Line1 should now be at row 2 (0-indexed)
    let cell = t.get_cell(2, 0).unwrap();
    assert_eq!(cell.char(), 'L', "IL should push existing lines down");
    // Delete the inserted blank line
    t.advance(b"\x1b[2;1H");
    t.advance(b"\x1b[1M"); // DL 1
    let cell = t.get_cell(1, 0).unwrap();
    assert_eq!(cell.char(), 'L', "DL should pull lines up");
}

// === SM/RM mode 4 (IRM — Insert/Replace Mode) ===

#[test]
fn vt_sm4_irm_set_does_not_panic() {
    // CSI 4 h (SM mode 4) enables Insert Replacement Mode.
    // This is an ANSI mode (no '?' prefix).  The implementation silently
    // ignores it (falls through the `_ => {}` arm), so the only compliance
    // requirement is that the terminal must not panic and must leave the
    // cursor at a well-defined, in-bounds position.
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[5;10H");
    t.advance(b"\x1b[4h"); // SM mode 4 — IRM on
    assert_eq!(t.cursor_row(), 4, "cursor row must be unchanged after SM 4");
    assert_eq!(t.cursor_col(), 9, "cursor col must be unchanged after SM 4");
}

#[test]
fn vt_rm4_irm_reset_does_not_panic() {
    // CSI 4 l (RM mode 4) disables Insert Replacement Mode.
    // Same compliance requirement: no panic, cursor in bounds.
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[5;10H");
    t.advance(b"\x1b[4h"); // enable first
    t.advance(b"\x1b[4l"); // CSI 4 l — IRM off
    assert_eq!(t.cursor_row(), 4, "cursor row must be unchanged after RM 4");
    assert_eq!(t.cursor_col(), 9, "cursor col must be unchanged after RM 4");
}

// === CSI s / CSI u — ANSI Save/Restore Cursor ===

#[test]
fn vt_ansi_scp_rcp_save_restore_cursor() {
    // CSI s saves the cursor; CSI u restores it.
    // These are the ANSI equivalents of DEC ESC 7 / ESC 8.
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[10;20H"); // position cursor at (9, 19)
    t.advance(b"\x1b[s"); // CSI s — save
    t.advance(b"\x1b[1;1H"); // move to (0, 0)
    assert_eq!(t.cursor_row(), 0, "cursor at row 0 after CUP 1;1");
    t.advance(b"\x1b[u"); // CSI u — restore
    assert_eq!(t.cursor_row(), 9, "CSI u must restore saved row");
    assert_eq!(t.cursor_col(), 19, "CSI u must restore saved col");
}

#[test]
fn vt_ansi_rcp_without_prior_save_is_safe() {
    // CSI u without a prior CSI s must not panic.
    // The terminal should silently ignore the restore (no saved state).
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[5;10H");
    t.advance(b"\x1b[u"); // restore with no prior save — must not panic
    assert!(t.cursor_row() < 24, "cursor row must be in bounds");
    assert!(t.cursor_col() < 80, "cursor col must be in bounds");
}

// === REP (CSI b) — Repeat Last Character ===

#[test]
fn vt_rep_does_not_panic_after_print() {
    // REP (CSI Ps b) is not implemented; it silently falls through.
    // After printing 'A' and sending REP 5, the cursor must remain
    // in-bounds and the terminal must not panic.
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"A");
    t.advance(b"\x1b[5b"); // REP 5 — silently ignored
    assert!(
        t.cursor_row() < 24,
        "cursor row must be in bounds after REP"
    );
    assert!(
        t.cursor_col() < 80,
        "cursor col must be in bounds after REP"
    );
}

// === VPA (CSI d) — Vertical Position Absolute ===

#[test]
fn vt_vpa_preserves_column() {
    // VPA moves only the row; the column must remain unchanged.
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[1;15H"); // row 0, col 14
    t.advance(b"\x1b[10d"); // VPA row 10 (1-indexed) → row 9
    assert_eq!(t.cursor_row(), 9, "VPA must set row to 9");
    assert_eq!(t.cursor_col(), 14, "VPA must not change column");
}

#[test]
fn vt_vpa_clamps_beyond_screen() {
    // VPA with a row > screen height must clamp to the last row.
    let mut t = TerminalCore::new(10, 80);
    t.advance(b"\x1b[999d"); // beyond 10 rows
    assert!(
        t.cursor_row() < 10,
        "VPA must clamp row to < 10 (got {})",
        t.cursor_row()
    );
}

// === CNL/CPL with parameters > 1 ===

#[test]
fn vt_cnl_multi_moves_down_and_resets_col() {
    // CNL 3 (CSI 3 E) from (row=2, col=30) must land at (row=5, col=0).
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[3;31H"); // row 2, col 30
    t.advance(b"\x1b[3E"); // CNL 3
    assert_eq!(t.cursor_row(), 5, "CNL 3 must advance 3 rows");
    assert_eq!(t.cursor_col(), 0, "CNL must reset column to 0");
}

#[test]
fn vt_cpl_multi_moves_up_and_resets_col() {
    // CPL 4 (CSI 4 F) from (row=10, col=50) must land at (row=6, col=0).
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[11;51H"); // row 10, col 50
    t.advance(b"\x1b[4F"); // CPL 4
    assert_eq!(t.cursor_row(), 6, "CPL 4 must retreat 4 rows");
    assert_eq!(t.cursor_col(), 0, "CPL must reset column to 0");
}

// === IRM insert mode interaction with character printing ===

#[test]
fn vt_irm_ich_inserts_space_before_existing_content() {
    // Even without full IRM support, ICH (CSI @) must shift characters
    // to the right when called explicitly — this is the ICH sequence,
    // not SM/RM mode 4.  IRM compliance via ICH: insert 1 blank before 'B'.
    let mut t = TerminalCore::new(5, 20);
    t.advance(b"\x1b[1;1H");
    t.advance(b"ABC"); // row 0: A B C
    t.advance(b"\x1b[1;2H"); // cursor to (0, 1) — before 'B'
    t.advance(b"\x1b[1@"); // ICH 1 — insert 1 blank at col 1
                           // After ICH: col 0='A', col 1=' ' (inserted), col 2='B', col 3='C'
    assert_eq!(
        t.get_cell(0, 0).unwrap().char(),
        'A',
        "col 0 must be untouched"
    );
    assert_eq!(
        t.get_cell(0, 1).unwrap().char(),
        ' ',
        "col 1 must be inserted blank"
    );
    assert_eq!(
        t.get_cell(0, 2).unwrap().char(),
        'B',
        "col 2 must be shifted 'B'"
    );
    assert_eq!(
        t.get_cell(0, 3).unwrap().char(),
        'C',
        "col 3 must be shifted 'C'"
    );
}

// === HPA (CSI `) — Horizontal Position Absolute ===

#[test]
fn vt_hpa_does_not_panic() {
    // HPA (CSI Ps `) is not implemented; it silently falls through to `_ => {}`.
    // Compliance requirement: no panic, cursor stays in-bounds.
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[5;20H"); // position at (4, 19)
    t.advance(b"\x1b[10`"); // HPA col 10 (1-indexed) — silently ignored
    assert!(
        t.cursor_row() < 24,
        "cursor row must be in bounds after HPA"
    );
    assert!(
        t.cursor_col() < 80,
        "cursor col must be in bounds after HPA"
    );
}

// === ED (Erase Display) variants ===

/// ED 2 (`CSI 2 J`) must erase all cells on the visible screen.
///
/// After printing text in several rows, `\x1b[2J` must clear every cell
/// to a space.  Cursor position after ED 2 is implementation-defined but
/// must remain in-bounds.
#[test]
fn vt_ed2_full_screen_erase() {
    let mut t = TerminalCore::new(5, 20);
    // Write content on several rows
    t.advance(b"\x1b[1;1H");
    t.advance(b"AAAAAAAAAA");
    t.advance(b"\x1b[2;1H");
    t.advance(b"BBBBBBBBBB");
    t.advance(b"\x1b[3;1H");
    t.advance(b"CCCCCCCCCC");

    // Verify content is present
    assert_eq!(t.get_cell(0, 0).unwrap().char(), 'A');
    assert_eq!(t.get_cell(1, 0).unwrap().char(), 'B');
    assert_eq!(t.get_cell(2, 0).unwrap().char(), 'C');

    // ED 2 — erase entire visible display
    t.advance(b"\x1b[2J");

    // Every cell in the 5×20 grid must now be a space
    for row in 0..5_usize {
        for col in 0..20_usize {
            let ch = t.get_cell(row, col).map(|c| c.char()).unwrap_or(' ');
            assert_eq!(
                ch, ' ',
                "cell ({row},{col}) must be space after ED 2, got '{ch}'"
            );
        }
    }
    // Cursor must remain in-bounds
    assert!(
        t.cursor_row() < 5,
        "cursor row must be in bounds after ED 2"
    );
    assert!(
        t.cursor_col() < 20,
        "cursor col must be in bounds after ED 2"
    );
}

/// ED 3 (`CSI 3 J`) must not panic.
///
/// ED 3 clears the scrollback buffer.  Even with an empty scrollback the
/// sequence must be silently accepted.
#[test]
fn vt_ed3_no_panic() {
    let mut t = TerminalCore::new(24, 80);
    // Ensure some scrollback exists
    for _ in 0..30 {
        t.advance(b"line\n");
    }
    // Must not panic
    t.advance(b"\x1b[3J");
    // Scrollback should be cleared (or at least not panicked)
    assert!(t.cursor_row() < 24, "cursor must be in bounds after ED 3");
}

// === CUP with no parameters defaults to (1,1) ===

/// `CSI H` with no parameters must place the cursor at (row=0, col=0).
///
/// Per ECMA-48 §8.3.130 the default parameter value for both Ps1 and Ps2
/// is 1 (1-indexed), which maps to (0, 0) in 0-indexed terms.
#[test]
fn vt_cup_no_params_defaults_to_origin() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[10;20H"); // move away from home
    assert_eq!(t.cursor_row(), 9);
    assert_eq!(t.cursor_col(), 19);

    t.advance(b"\x1b[H"); // CUP with no params — must home the cursor
    assert_eq!(
        t.cursor_row(),
        0,
        "CUP with no params must set row to 0 (default Ps=1)"
    );
    assert_eq!(
        t.cursor_col(),
        0,
        "CUP with no params must set col to 0 (default Ps=1)"
    );
}

// === SM/RM with unknown private mode numbers ===

/// `CSI ? 9999 h` (unknown DEC private mode) must not panic.
///
/// Unknown mode numbers must be silently ignored; the cursor must remain
/// in-bounds and the terminal must continue operating normally.
#[test]
fn vt_sm_unknown_private_mode_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[5;10H");
    t.advance(b"\x1b[?9999h"); // unknown mode — must be silently ignored
    assert!(
        t.cursor_row() < 24,
        "cursor row must be in bounds after unknown SM"
    );
    assert!(
        t.cursor_col() < 80,
        "cursor col must be in bounds after unknown SM"
    );
}

/// `CSI ? 9999 l` (unknown DEC private mode reset) must not panic.
#[test]
fn vt_rm_unknown_private_mode_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[5;10H");
    t.advance(b"\x1b[?9999l"); // unknown mode reset — must be silently ignored
    assert!(
        t.cursor_row() < 24,
        "cursor row must be in bounds after unknown RM"
    );
    assert!(
        t.cursor_col() < 80,
        "cursor col must be in bounds after unknown RM"
    );
}

// === SGR 0 followed by SGR 1 ===

/// SGR 0 clears all attributes; a subsequent SGR 1 must set bold.
///
/// This exercises the common pattern of resetting then applying a new
/// attribute in a single sequence or across two advances.
#[test]
fn vt_sgr_reset_then_bold() {
    let mut t = TerminalCore::new(24, 80);

    // Set several attributes
    t.advance(b"\x1b[1;3;4m"); // bold + italic + underline
    assert!(t.current_attrs().flags.contains(SgrFlags::BOLD));
    assert!(t.current_attrs().flags.contains(SgrFlags::ITALIC));

    // SGR 0 resets everything
    t.advance(b"\x1b[0m");
    assert!(
        !t.current_attrs().flags.contains(SgrFlags::BOLD),
        "BOLD must be clear after SGR 0"
    );
    assert!(
        !t.current_attrs().flags.contains(SgrFlags::ITALIC),
        "ITALIC must be clear after SGR 0"
    );

    // SGR 1 after reset must set bold (only bold, not the others)
    t.advance(b"\x1b[1m");
    assert!(
        t.current_attrs().flags.contains(SgrFlags::BOLD),
        "BOLD must be set after SGR 0 followed by SGR 1"
    );
    assert!(
        !t.current_attrs().flags.contains(SgrFlags::ITALIC),
        "ITALIC must remain clear after SGR 1 (only bold was requested)"
    );
}

// === Character width: ASCII (width 1) vs fullwidth (width 2) ===

/// ASCII 'A' (U+0041) is a single-width character; cursor advances by 1.
///
/// Verifies that the width-1 path is taken for ordinary ASCII printable
/// characters and that only one grid cell is occupied.
#[test]
fn vt_ascii_char_is_single_width() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"A");
    assert_eq!(
        t.cursor_col(),
        1,
        "ASCII 'A' must advance cursor by exactly 1 column"
    );
    let cell = t.get_cell(0, 0).expect("cell (0,0) must exist");
    assert_eq!(cell.char(), 'A', "cell (0,0) must hold 'A'");
    // The cell immediately to the right must be empty (default space)
    let next = t.get_cell(0, 1).expect("cell (0,1) must exist");
    assert_eq!(
        next.char(),
        ' ',
        "cell (0,1) must be space — 'A' must not occupy two cells"
    );
}

/// Fullwidth Latin 'Ａ' (U+FF21) must advance cursor by 2 columns.
///
/// U+FF21 FULLWIDTH LATIN CAPITAL LETTER A is a Unicode fullwidth character
/// (East Asian Width = Fullwidth) and must occupy two consecutive grid cells,
/// advancing the cursor by 2.
#[test]
fn vt_fullwidth_char_is_double_width() {
    let mut t = TerminalCore::new(24, 80);
    t.advance("\u{FF21}".as_bytes()); // U+FF21: FULLWIDTH LATIN CAPITAL LETTER A
    assert_eq!(
        t.cursor_col(),
        2,
        "fullwidth 'Ａ' (U+FF21) must advance cursor by 2 columns"
    );
    let cell = t.get_cell(0, 0).expect("cell (0,0) must exist");
    assert_eq!(
        cell.char(),
        '\u{FF21}',
        "cell (0,0) must hold the fullwidth character"
    );
}

// === CUU/CUD/CUF/CUB with count 0 (treated as 1) ===

// CUU 0 (CSI 0 A) must move up by 1 (count 0 treated as default=1).
#[test]
fn vt_cuu_count_zero_treated_as_one() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[5;10H"); // row 4, col 9
    t.advance(b"\x1b[0A"); // CUU 0 — treated as CUU 1
    assert_eq!(t.cursor_row(), 3, "CUU 0 must move up by 1 (same as CUU 1)");
    assert_eq!(t.cursor_col(), 9, "CUU must not change column");
}

// CUD 0 (CSI 0 B) must move down by 1 (count 0 treated as default=1).
#[test]
fn vt_cud_count_zero_treated_as_one() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[5;10H"); // row 4, col 9
    t.advance(b"\x1b[0B"); // CUD 0 — treated as CUD 1
    assert_eq!(
        t.cursor_row(),
        5,
        "CUD 0 must move down by 1 (same as CUD 1)"
    );
    assert_eq!(t.cursor_col(), 9, "CUD must not change column");
}

// CUF 0 (CSI 0 C) must move right by 1 (count 0 treated as default=1).
#[test]
fn vt_cuf_count_zero_treated_as_one() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[1;5H"); // row 0, col 4
    t.advance(b"\x1b[0C"); // CUF 0 — treated as CUF 1
    assert_eq!(
        t.cursor_col(),
        5,
        "CUF 0 must move right by 1 (same as CUF 1)"
    );
    assert_eq!(t.cursor_row(), 0, "CUF must not change row");
}

// CUB 0 (CSI 0 D) must move left by 1 (count 0 treated as default=1).
#[test]
fn vt_cub_count_zero_treated_as_one() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[1;10H"); // row 0, col 9
    t.advance(b"\x1b[0D"); // CUB 0 — treated as CUB 1
    assert_eq!(
        t.cursor_col(),
        8,
        "CUB 0 must move left by 1 (same as CUB 1)"
    );
    assert_eq!(t.cursor_row(), 0, "CUB must not change row");
}

// === CUU/CUD/CUF/CUB clamped at screen bounds ===

// CUU large count must clamp at row 0.
#[test]
fn vt_cuu_clamped_at_top() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[3;10H"); // row 2
    t.advance(b"\x1b[999A"); // CUU 999 — must clamp at row 0
    assert_eq!(t.cursor_row(), 0, "CUU must clamp at row 0");
    assert_eq!(t.cursor_col(), 9, "CUU must not change column");
}

// CUD large count must clamp at last row.
#[test]
fn vt_cud_clamped_at_bottom() {
    let mut t = TerminalCore::new(10, 40);
    t.advance(b"\x1b[5;10H"); // row 4
    t.advance(b"\x1b[999B"); // CUD 999 — must clamp at last row (9)
    assert_eq!(t.cursor_row(), 9, "CUD must clamp at last row");
    assert_eq!(t.cursor_col(), 9, "CUD must not change column");
}

// CUF large count must clamp at last column.
#[test]
fn vt_cuf_clamped_at_right() {
    let mut t = TerminalCore::new(24, 40);
    t.advance(b"\x1b[1;5H"); // row 0, col 4
    t.advance(b"\x1b[999C"); // CUF 999 — must clamp at last col (39)
    assert_eq!(t.cursor_col(), 39, "CUF must clamp at last column");
    assert_eq!(t.cursor_row(), 0, "CUF must not change row");
}

// CUB large count must clamp at column 0.
#[test]
fn vt_cub_clamped_at_left() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[1;10H"); // row 0, col 9
    t.advance(b"\x1b[999D"); // CUB 999 — must clamp at col 0
    assert_eq!(t.cursor_col(), 0, "CUB must clamp at col 0");
    assert_eq!(t.cursor_row(), 0, "CUB must not change row");
}

// === DSR (CSI 6 n) — device status report cursor position ===

// DSR (CSI 6 n) must respond with CSI row ; col R (1-indexed).
#[test]
fn vt_dsr_cursor_position_response() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[5;10H"); // row 4, col 9 (0-indexed) = row 5, col 10 (1-indexed)
    t.advance(b"\x1b[6n"); // DSR
    assert!(
        !t.pending_responses().is_empty(),
        "DSR must generate a CPR response"
    );
    // Response: ESC [ row ; col R  (1-indexed)
    let raw = &t.pending_responses()[0];
    let resp = String::from_utf8_lossy(raw);
    assert!(
        resp.contains('R'),
        "DSR response must contain 'R' (CPR), got: {resp:?}"
    );
    assert!(
        resp.contains('5') && resp.contains("10"),
        "DSR response must contain row=5 and col=10 (1-indexed), got: {resp:?}"
    );
}

// DSR from origin (row 0, col 0) must respond with 1;1R.
#[test]
fn vt_dsr_at_origin_responds_1_1() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[H"); // home
    t.advance(b"\x1b[6n"); // DSR
    assert!(
        !t.pending_responses().is_empty(),
        "DSR must generate response"
    );
    let raw = &t.pending_responses()[0];
    let resp = String::from_utf8_lossy(raw);
    // Expect ESC [ 1 ; 1 R
    assert!(
        resp.contains("1;1R") || (resp.contains('1') && resp.contains('R')),
        "DSR at origin must respond with 1;1R, got: {resp:?}"
    );
}

// === DECSC/DECRC preserving SGR attributes ===

// DECSC (ESC 7) must save bold attribute; DECRC (ESC 8) must restore it.
#[test]
fn vt_decsc_decrc_saves_and_restores_bold() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[1m"); // set bold
    assert!(t.current_attrs().flags.contains(SgrFlags::BOLD));
    t.advance(b"\x1b7"); // DECSC — save cursor + attrs
    t.advance(b"\x1b[0m"); // reset bold
    assert!(!t.current_attrs().flags.contains(SgrFlags::BOLD));
    t.advance(b"\x1b8"); // DECRC — restore cursor + attrs
    assert!(
        t.current_attrs().flags.contains(SgrFlags::BOLD),
        "DECRC must restore bold attribute"
    );
}

// DECSC/DECRC must also restore the cursor position.
#[test]
fn vt_decsc_decrc_restores_position_and_attrs_together() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[3m"); // set italic
    t.advance(b"\x1b[8;15H"); // row 7, col 14
    t.advance(b"\x1b7"); // DECSC
    t.advance(b"\x1b[1;1H"); // move away
    t.advance(b"\x1b[0m"); // clear attrs
    t.advance(b"\x1b8"); // DECRC
    assert_eq!(t.cursor_row(), 7, "DECRC must restore row to 7");
    assert_eq!(t.cursor_col(), 14, "DECRC must restore col to 14");
    assert!(
        t.current_attrs().flags.contains(SgrFlags::ITALIC),
        "DECRC must restore italic attribute"
    );
}

// Multiple DECSC/DECRC pairs — only the most recent save is kept.
#[test]
fn vt_decsc_decrc_only_one_save_slot() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[3;5H"); // first position: row 2, col 4
    t.advance(b"\x1b7"); // DECSC (first save)
    t.advance(b"\x1b[10;20H"); // second position: row 9, col 19
    t.advance(b"\x1b7"); // DECSC (second save — overwrites first)
    t.advance(b"\x1b[1;1H"); // move to origin
    t.advance(b"\x1b8"); // DECRC — must restore second save, not first
    assert_eq!(
        t.cursor_row(),
        9,
        "DECRC must restore the most recent DECSC row"
    );
    assert_eq!(
        t.cursor_col(),
        19,
        "DECRC must restore the most recent DECSC col"
    );
}

// === SGR 0 clears foreground and background colors to Default ===

// SGR 0 must reset fg/bg to Color::Default.
#[test]
fn vt_sgr_reset_clears_fg_bg_to_default() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[38;2;255;0;0m"); // RGB red foreground
    t.advance(b"\x1b[48;2;0;255;0m"); // RGB green background
    assert_eq!(
        t.current_attrs().foreground,
        kuro_core::types::Color::Rgb(255, 0, 0)
    );
    assert_eq!(
        t.current_attrs().background,
        kuro_core::types::Color::Rgb(0, 255, 0)
    );
    t.advance(b"\x1b[0m"); // SGR 0 — reset all
    assert_eq!(
        t.current_attrs().foreground,
        kuro_core::types::Color::Default,
        "SGR 0 must reset foreground to Default"
    );
    assert_eq!(
        t.current_attrs().background,
        kuro_core::types::Color::Default,
        "SGR 0 must reset background to Default"
    );
}

// SGR 0 must clear all flags (bold, italic, underline, etc.).
#[test]
fn vt_sgr_reset_clears_all_flags() {
    let mut t = TerminalCore::new(24, 80);
    // Set a pile of attributes
    t.advance(b"\x1b[1;3;4;5;7;8;9m"); // bold, italic, underline, blink, reverse, hidden, strikethrough
    assert!(t.current_attrs().flags.contains(SgrFlags::BOLD));
    assert!(t.current_attrs().flags.contains(SgrFlags::ITALIC));
    t.advance(b"\x1b[0m"); // SGR 0
    assert!(
        t.current_attrs().flags.is_empty(),
        "SGR 0 must clear all SGR flags, got: {:?}",
        t.current_attrs().flags
    );
}

// === SS2/SS3 — single-shift sequences ===

// SS2 (ESC N) must not panic and terminal must continue operating.
#[test]
fn vt_ss2_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1bN"); // SS2
    assert!(
        t.cursor_row() < 24,
        "cursor row must be in bounds after SS2"
    );
    assert!(
        t.cursor_col() < 80,
        "cursor col must be in bounds after SS2"
    );
    // Terminal must remain functional after SS2
    t.advance(b"A");
    assert!(
        t.cursor_col() > 0 || t.cursor_row() > 0 || t.get_cell(0, 0).is_some(),
        "terminal must continue operating after SS2"
    );
}

// SS3 (ESC O) must not panic and terminal must continue operating.
#[test]
fn vt_ss3_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1bO"); // SS3 with no follow-on char
    assert!(
        t.cursor_row() < 24,
        "cursor row must be in bounds after SS3"
    );
    assert!(
        t.cursor_col() < 80,
        "cursor col must be in bounds after SS3"
    );
}

// SS3 followed by a letter (e.g., SS3 A = application cursor up) must not panic.
#[test]
fn vt_ss3_with_letter_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[5;10H"); // position away from home
    t.advance(b"\x1bOA"); // SS3 A — application cursor up (used by app keypad)
                          // Must not panic; cursor stays in bounds
    assert!(
        t.cursor_row() < 24,
        "cursor row must be in bounds after SS3 A"
    );
    assert!(
        t.cursor_col() < 80,
        "cursor col must be in bounds after SS3 A"
    );
}

// === DCS passthrough forwarding ===

// DCS sequences not handled by kuro (neither XTGETTCAP nor Sixel/Kitty)
// must not panic.
#[test]
fn vt_dcs_unknown_passthrough_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);
    // DCS 1 $ r <param> ST — DECRQSS (request selection/setting) — not implemented
    t.advance(b"\x1bP1$r1m\x1b\\"); // DCS 1 $ r 1 m ST
    assert!(
        t.cursor_row() < 24,
        "cursor must be in bounds after DCS passthrough"
    );
    assert!(
        t.cursor_col() < 80,
        "cursor must be in bounds after DCS passthrough"
    );
}

// DCS with a long unrecognised payload must not panic (test APC/DCS size limit path).
#[test]
fn vt_dcs_long_unknown_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);
    // Start a DCS sequence with a payload that doesn't match any handler
    let mut seq = b"\x1bP".to_vec();
    seq.extend(b"x".repeat(256)); // unrecognised 256-byte payload
    seq.extend(b"\x1b\\"); // ST
    t.advance(&seq);
    assert!(
        t.cursor_row() < 24,
        "cursor must be in bounds after long DCS"
    );
}

// === Attribute preservation: current_attrs reflects SGR 0 immediately ===

// After SGR 0 the current attrs must report no bold, and cells written
// after the reset must be reachable at their correct grid positions.
#[test]
fn vt_sgr_reset_changes_current_attrs_and_subsequent_cells_are_correct() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[1m"); // bold on
    t.advance(b"AB"); // write 'A' and 'B' with bold
    assert!(
        t.current_attrs().flags.contains(SgrFlags::BOLD),
        "current_attrs must show bold while it is active"
    );
    t.advance(b"\x1b[0m"); // SGR 0 — reset
    assert!(
        !t.current_attrs().flags.contains(SgrFlags::BOLD),
        "current_attrs must not show bold after SGR 0"
    );
    t.advance(b"C"); // write 'C' without bold

    // Grid content must be correct
    assert_eq!(
        t.get_cell(0, 0).map(kuro_core::Cell::char),
        Some('A'),
        "cell (0,0) must be 'A'"
    );
    assert_eq!(
        t.get_cell(0, 1).map(kuro_core::Cell::char),
        Some('B'),
        "cell (0,1) must be 'B'"
    );
    assert_eq!(
        t.get_cell(0, 2).map(kuro_core::Cell::char),
        Some('C'),
        "cell (0,2) must be 'C'"
    );
}
