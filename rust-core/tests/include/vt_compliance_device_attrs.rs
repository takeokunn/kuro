// === Modern Terminal Features (continued) ===

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
