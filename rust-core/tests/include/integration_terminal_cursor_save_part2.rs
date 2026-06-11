#[test]
fn test_title_dirty_flag_clears_after_reset() {
    let mut term = TerminalCore::new(24, 80);

    // Set a title
    term.advance(b"\x1b]2;my-title\x07");
    assert!(term.title_dirty(), "title_dirty must be true after OSC 2");
    assert_eq!(term.title(), "my-title");

    // reset() clears the dirty flag
    term.reset();
    assert!(
        !term.title_dirty(),
        "title_dirty must be false after reset()"
    );
    assert_eq!(term.title(), "", "title must be empty after reset()");

    // Calling again (no new OSC 2) — dirty must still be false
    assert!(
        !term.title_dirty(),
        "title_dirty must remain false without a new OSC 2"
    );
}

/// Scrollback buffer is cleared by ED 3 (`CSI 3 J`), not by `reset()`.
///
/// `reset()` (RIS — ESC c) is a terminal-mode reset; it resets DEC modes,
/// SGR attributes, tab stops, and title state, but intentionally preserves
/// screen content (including scrollback) so that session output is not lost
/// on a mode-reset event.
///
/// To wipe scrollback the application must send `CSI 3 J` explicitly.
#[test]
fn test_scrollback_cleared_by_ed3_not_reset() {
    // Use a small terminal so we generate scrollback quickly
    let mut term = TerminalCore::new(3, 20);
    // Force lines into scrollback by overflowing the 3-row screen
    term.advance(b"line1\nline2\nline3\nline4\nline5");
    let scrollback_before = term.scrollback_line_count();
    assert!(
        scrollback_before > 0,
        "scrollback must be non-empty after overflow; got {scrollback_before}"
    );

    // Full reset (RIS) does NOT clear scrollback — screen content is preserved
    term.reset();
    assert!(
        term.scrollback_line_count() > 0,
        "reset() must NOT clear scrollback (got 0, expected > 0)"
    );

    // ED 3 (CSI 3 J) explicitly clears the scrollback buffer
    term.advance(b"\x1b[3J");
    assert_eq!(
        term.scrollback_line_count(),
        0,
        "CSI 3 J must clear scrollback to 0"
    );
}

/// `set_default_bg_color` (via OSC 11) persists across a `resize`.
///
/// After setting a custom default background via OSC 11 and then resizing
/// the terminal, `osc_data().default_bg` must still hold the colour.
#[test]
fn test_default_bg_color_persists_across_resize() {
    let mut term = TerminalCore::new(24, 80);

    // Set a custom default background colour via OSC 11 (xterm protocol)
    // Format: OSC 11 ; rgb:RRRR/GGGG/BBBB BEL
    term.advance(b"\x1b]11;rgb:ff/00/7f\x07");
    assert!(
        term.osc_data().default_bg.is_some(),
        "default_bg must be set after OSC 11"
    );
    let bg_before = term.osc_data().default_bg;

    // Resize — must not clear the custom colour
    term.resize(20, 60);

    assert_eq!(
        term.osc_data().default_bg,
        bg_before,
        "default_bg must persist across resize"
    );
}

/// DECSC / DECRC cursor position round-trip via ESC 7 / ESC 8.
///
/// Save position at (4, 9), move elsewhere, restore — cursor returns to (4, 9).
#[test]
fn test_decsc_decrc_cursor_position() {
    let mut term = TerminalCore::new(24, 80);

    // Position cursor at (row=4, col=9)
    term.advance(b"\x1b[5;10H"); // CUP 1-indexed → 0-indexed (4, 9)
    assert_eq!(term.cursor_row(), 4);
    assert_eq!(term.cursor_col(), 9);

    // Save cursor via ESC 7
    term.advance(b"\x1b7");

    // Move cursor to home
    term.advance(b"\x1b[H");
    assert_eq!(
        term.cursor_row(),
        0,
        "cursor must be at row 0 after CUP home"
    );
    assert_eq!(
        term.cursor_col(),
        0,
        "cursor must be at col 0 after CUP home"
    );

    // Restore cursor via ESC 8
    term.advance(b"\x1b8");
    assert_eq!(
        term.cursor_row(),
        4,
        "DECRC must restore cursor to saved row 4"
    );
    assert_eq!(
        term.cursor_col(),
        9,
        "DECRC must restore cursor to saved col 9"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Alternate screen cursor preservation
// ─────────────────────────────────────────────────────────────────────────────

/// Entering alternate screen (?1049h) saves the primary cursor; exiting (?1049l)
/// restores it, so the cursor returns to the position it had before entering.
#[test]
fn test_alt_screen_saves_and_restores_cursor() {
    let mut term = TerminalCore::new(24, 80);
    // Position cursor on primary screen
    term.advance(b"\x1b[6;15H"); // CUP → row 5, col 14 (0-indexed)
    assert_eq!(term.cursor_row(), 5);
    assert_eq!(term.cursor_col(), 14);

    // Enter alt screen — cursor should reset on alt screen
    term.advance(b"\x1b[?1049h");
    assert!(
        term.is_alternate_screen_active(),
        "must be on alt screen after ?1049h"
    );
    // Move around on alt screen
    term.advance(b"\x1b[3;3H");
    assert_eq!(term.cursor_row(), 2);

    // Exit alt screen — cursor must return to saved primary position
    term.advance(b"\x1b[?1049l");
    assert!(
        !term.is_alternate_screen_active(),
        "must be on primary screen after ?1049l"
    );
    assert_eq!(
        term.cursor_row(),
        5,
        "primary cursor row must be restored after leaving alt screen"
    );
    assert_eq!(
        term.cursor_col(),
        14,
        "primary cursor col must be restored after leaving alt screen"
    );
}

/// Content printed on the alternate screen must not appear on the primary screen
/// after returning.
#[test]
fn test_alt_screen_content_does_not_bleed_to_primary() {
    let mut term = TerminalCore::new(24, 80);
    // Put known content on primary screen
    term.advance(b"\x1b[1;1H");
    term.advance(b"PRIMARY");

    // Enter alt screen and write different content
    term.advance(b"\x1b[?1049h");
    term.advance(b"\x1b[1;1H");
    term.advance(b"ALTSCR");

    // Return to primary screen
    term.advance(b"\x1b[?1049l");

    // Primary screen row 0 must still start with 'P'
    let cell = term
        .get_cell(0, 0)
        .expect("cell (0,0) must exist on primary");
    assert_eq!(
        cell.char(),
        'P',
        "primary screen must not be overwritten by alt-screen content"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Erase-in-display (ED) modes 0 and 1
// ─────────────────────────────────────────────────────────────────────────────

/// ED 0 (CSI 0 J) erases from cursor to end of display.
#[test]
fn test_ed0_erases_from_cursor_to_end() {
    let mut term = TerminalCore::new(5, 10);
    // Write something on row 0 and row 1
    term.advance(b"AAAAAAAAAA"); // fills row 0
    term.advance(b"\nBBBBBBBBBB"); // fills row 1
    // Move cursor to row 0, col 5
    term.advance(b"\x1b[1;6H"); // 1-indexed → row 0, col 5
    term.advance(b"\x1b[0J"); // ED 0: erase from cursor to bottom
    // col 0..4 on row 0 must still be 'A'
    for col in 0..5 {
        let cell = term.get_cell(0, col).expect("cell must exist");
        assert_eq!(cell.char(), 'A', "cell (0,{col}) must survive ED 0");
    }
    // col 5 onward on row 0 must be erased
    let erased = term.get_cell(0, 5).expect("cell (0,5) must exist");
    assert_eq!(erased.char(), ' ', "cell (0,5) must be erased by ED 0");
    // row 1 must be fully erased
    let r1 = term.get_cell(1, 0).expect("cell (1,0) must exist");
    assert_eq!(r1.char(), ' ', "row 1, col 0 must be erased by ED 0");
}

/// ED 1 (CSI 1 J) erases from beginning of display to cursor (inclusive).
#[test]
fn test_ed1_erases_from_start_to_cursor() {
    let mut term = TerminalCore::new(5, 10);
    // Write 'A' on row 0 and 'B' on row 1 (use CR+LF so 'B' starts at col 0)
    term.advance(b"AAAAAAAAAA");
    term.advance(b"\r\nBBBBBBBBBB");
    // Move cursor to row 1, col 4
    term.advance(b"\x1b[2;5H"); // 1-indexed → row 1, col 4
    term.advance(b"\x1b[1J"); // ED 1: erase from top to cursor
    // row 0 must be fully erased
    let r0 = term.get_cell(0, 0).expect("cell (0,0) must exist");
    assert_eq!(r0.char(), ' ', "row 0 must be erased by ED 1");
    // row 1, cols 0–4 must be erased
    for col in 0..=4 {
        let cell = term.get_cell(1, col).expect("cell must exist");
        assert_eq!(cell.char(), ' ', "cell (1,{col}) must be erased by ED 1");
    }
    // row 1, cols 5–9 must still be 'B'
    let surviving = term.get_cell(1, 5).expect("cell (1,5) must exist");
    assert_eq!(surviving.char(), 'B', "cell (1,5) must survive ED 1");
}

// ─────────────────────────────────────────────────────────────────────────────
// Backspace at column 0 is a no-op
// ─────────────────────────────────────────────────────────────────────────────

/// BS (0x08) at column 0 must not move the cursor to a negative column.
#[test]
fn test_backspace_at_col_zero_is_noop() {
    let mut term = TerminalCore::new(24, 80);
    assert_eq!(term.cursor_col(), 0);
    term.advance(b"\x08"); // BS at col 0
    assert_eq!(
        term.cursor_col(),
        0,
        "BS at col 0 must not underflow cursor"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab at the last tab stop clamps at end of line
// ─────────────────────────────────────────────────────────────────────────────

/// On an 80-col terminal the last tab stop is col 72.  A HT from col 72
/// must not advance the cursor past col 79.
#[test]
fn test_tab_at_last_stop_stays_in_bounds() {
    let mut term = TerminalCore::new(24, 80);
    // Move to col 72 (the last standard tab stop on an 80-col terminal)
    term.advance(b"\x1b[1;73H"); // 1-indexed → row 0, col 72
    assert_eq!(term.cursor_col(), 72);
    term.advance(b"\t"); // HT: horizontal tab
    assert!(
        term.cursor_col() < 80,
        "tab from last stop must not push cursor past col 79; got {}",
        term.cursor_col()
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Resize: content on visible rows is preserved
// ─────────────────────────────────────────────────────────────────────────────

/// After a resize that grows the terminal, content on the first row must
/// still be readable via `get_cell`.
#[test]
fn test_resize_grow_preserves_visible_content() {
    let mut term = TerminalCore::new(10, 40);
    term.advance(b"\x1b[1;1H");
    term.advance(b"HELLO");
    term.resize(20, 80);
    // Row 0 content must survive the resize
    let h = term
        .get_cell(0, 0)
        .expect("cell (0,0) must exist after resize");
    assert_eq!(
        h.char(),
        'H',
        "cell (0,0) must still be 'H' after resize grow"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// CRLF vs LF
// ─────────────────────────────────────────────────────────────────────────────

/// A bare LF (0x0a) advances the row but does NOT reset the column.
#[test]
fn test_lf_advances_row_but_not_col() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"ABCDE"); // cursor at col 5
    assert_eq!(term.cursor_col(), 5);
    term.advance(b"\n"); // LF — row advances, col unchanged
    assert_eq!(term.cursor_row(), 1, "LF must advance row");
    assert_eq!(term.cursor_col(), 5, "LF must not reset col");
}

/// A CRLF pair advances the row AND resets the column to 0.
#[test]
fn test_crlf_advances_row_and_resets_col() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"ABCDE"); // cursor at col 5
    term.advance(b"\r\n"); // CR + LF
    assert_eq!(term.cursor_row(), 1, "CRLF must advance row");
    assert_eq!(term.cursor_col(), 0, "CRLF must reset col to 0");
}
