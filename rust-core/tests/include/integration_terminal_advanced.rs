// -----------------------------------------------------------------------------
// REGRESSION TESTS — SPC cursor movement
//
// Bug: encode_line() trimmed trailing spaces before passing the line text to
// Emacs.  kuro--update-cursor computes the buffer position as:
//
//   (min (+ line-start col) line-end)
//
// After trimming, `line-end` was shorter than the cursor column when the
// cursor was inside trailing whitespace, so the visual cursor was clamped
// to the last non-space character.  Symptom: pressing SPC at a bash prompt
// did not move the cursor.
//
// The fix: remove trailing-space trimming from encode_line and get_dirty_lines.
// The tests below pin the correct behaviour at the TerminalCore level so that
// any future regression is caught before it reaches the Emacs render layer.
// -----------------------------------------------------------------------------

/// A single SPC byte must advance the cursor one column to the right.
///
/// This is the minimal reproduction of the original bug:
///   1. kuro sends 0x20 to the PTY.
///   2. The shell echoes 0x20 back.
///   3. VTE calls screen.print(' ') → `cursor_col` += 1.
///
/// If `encode_line` trimmed the space away, the Emacs buffer line became empty,
/// causing kuro--update-cursor to clamp the cursor back to col 0.
#[test]
fn test_spc_advances_cursor_rightward() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b" ");
    assert_eq!(
        term.cursor_col(),
        1,
        "cursor col must be 1 after a single SPC — \
         regression: trailing-space trimming must not discard the echoed space"
    );
    // The cell at column 0 must contain a space, not a default/empty cell.
    let cell = term.get_cell(0, 0).expect("cell (0,0) must exist");
    assert_eq!(
        cell.char(),
        ' ',
        "cell (0,0) must be ' ' after advancing through a space"
    );
}

/// After text followed by a trailing space, cursor lands after the space.
///
/// Simulates the typical bash readline echo of "echo hello ":
///   - 10 chars of "echo hello"
///   - 1 trailing space typed by the user
///
/// The cursor must land at col 11, not col 10 (the trimmed position).
#[test]
fn test_cursor_lands_after_trailing_space() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"echo hello ");
    assert_eq!(
        term.cursor_col(),
        11,
        "cursor col must be 11 after 'echo hello ' \
         (10 non-space chars + 1 trailing space)"
    );
}

/// Multiple consecutive spaces must each advance the cursor.
#[test]
fn test_multiple_trailing_spaces_advance_cursor() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"AB   "); // 2 non-space + 3 trailing spaces
    assert_eq!(
        term.cursor_col(),
        5,
        "cursor col must be 5 after 'AB   ' (2 chars + 3 trailing spaces)"
    );
}

/// Backspace after a space must move the cursor back.
///
/// Guards the cursor movement round-trip:
///   SPC → cursor right, BS → cursor left.
/// If SPC didn't advance the cursor, BS from the wrong position would
/// compound the error.
#[test]
fn test_backspace_after_space_moves_cursor_left() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"A "); // 'A' at col 0, space at col 1 → cursor at 2
    assert_eq!(term.cursor_col(), 2, "cursor must be at col 2 after 'A '");
    term.advance(b"\x08"); // BS → cursor back to col 1
    assert_eq!(
        term.cursor_col(),
        1,
        "cursor must be at col 1 after backspace"
    );
}

/// C-b (0x02), C-f (0x06), C-e (0x05) must NOT write printable characters.
///
/// These bytes are C0 control characters handled by VTE's `execute` callback,
/// not `print`.  If they leaked into the cell grid as printable glyphs, it
/// would mean the PTY is echoing them as the two-char sequences "^B"/"^F"/"^E"
/// (ECHOCTL mode), which indicates readline is in dumb-terminal mode due to
/// the PTY window size being 0×0 at shell startup.
///
/// At the `TerminalCore` level these bytes are not printable, so cells stay
/// empty and the cursor stays at col 0.
#[test]
fn test_control_chars_do_not_print_visible_glyphs() {
    let mut term = TerminalCore::new(24, 80);
    // Feed raw C-b, C-f, C-e (as the terminal core would see them from the PTY
    // when readline is operating correctly and does NOT echo them as ^X).
    term.advance(&[0x02, 0x06, 0x05]);
    assert_eq!(
        term.cursor_col(),
        0,
        "C-b/C-f/C-e must not advance the cursor — they are control chars, not printable"
    );
    // All cells on row 0 must be default (space) — no "^B", "^F", "^E" glyphs.
    for col in 0..5 {
        let cell = term.get_cell(0, col).expect("cell must exist");
        assert_eq!(
            cell.char(),
            ' ',
            "cell (0,{col}) must be a space — control chars must not write glyphs"
        );
    }
}

// === soft_reset vs reset ===

/// `soft_reset` clears SGR attributes but preserves screen content.
///
/// DECSTR (CSI ! p) is used by applications after a session recovery:
/// they want to clear mode state without erasing what's on screen.
#[test]
fn test_soft_reset_clears_sgr_preserves_content() {
    let mut term = TerminalCore::new(24, 80);
    // Write text and set bold+italic
    term.advance(b"\x1b[1;3mHello");
    assert!(term.current_bold(), "bold must be set before soft_reset");
    assert!(
        term.current_italic(),
        "italic must be set before soft_reset"
    );

    term.soft_reset();

    // SGR attributes must be cleared
    assert!(!term.current_bold(), "bold must be clear after soft_reset");
    assert!(
        !term.current_italic(),
        "italic must be clear after soft_reset"
    );

    // Screen content must be preserved — 'H' at (0,0)
    let cell = term.get_cell(0, 0).expect("cell (0,0) must exist");
    assert_eq!(cell.char(), 'H', "soft_reset must not erase screen content");
}

/// `soft_reset` moves cursor to home and keeps cursor visible.
#[test]
fn test_soft_reset_homes_cursor_and_keeps_visible() {
    let mut term = TerminalCore::new(24, 80);
    // Hide cursor and move away from home
    term.advance(b"\x1b[?25l"); // DECTCEM off
    term.advance(b"\x1b[10;20H"); // move cursor
    assert!(
        !term.cursor_visible(),
        "cursor should be hidden before soft_reset"
    );

    term.soft_reset();

    assert_eq!(term.cursor_row(), 0, "soft_reset must home the cursor row");
    assert_eq!(term.cursor_col(), 0, "soft_reset must home the cursor col");
    assert!(
        term.cursor_visible(),
        "soft_reset must restore cursor visibility"
    );
}

/// `reset` (RIS - ESC c) clears the title, resets to primary screen, and
/// resets tab stops to the default 8-column grid.
#[test]
fn test_reset_clears_title_and_resets_state() {
    let mut term = TerminalCore::new(24, 80);
    // Set a title via OSC 2
    term.advance(b"\x1b]2;my-title\x07");
    assert_eq!(term.title(), "my-title", "title must be set before reset");

    // Switch to alternate screen and write something
    term.advance(b"\x1b[?1049h"); // enter alt screen
    term.advance(b"altcontent");
    assert!(
        term.is_alternate_screen_active(),
        "must be on alt screen before reset"
    );

    term.reset();

    // Must be back on primary screen
    assert!(
        !term.is_alternate_screen_active(),
        "reset must switch back to primary screen"
    );
    // Title must be cleared
    assert_eq!(term.title(), "", "reset must clear the title");
    // Cursor must be at home
    assert_eq!(term.cursor_row(), 0);
    assert_eq!(term.cursor_col(), 0);
}

// === Title dirty flag lifecycle ===

/// Title dirty flag is set on OSC 2 and remains set until it is consumed via reset.
#[test]
fn test_title_dirty_set_then_cleared_by_reset() {
    let mut term = TerminalCore::new(24, 80);
    assert!(!term.title_dirty(), "title_dirty must start false");

    term.advance(b"\x1b]2;test-title\x07");
    assert!(term.title_dirty(), "title_dirty must be true after OSC 2");
    assert_eq!(term.title(), "test-title");

    // A full reset clears title_dirty
    term.reset();
    assert!(!term.title_dirty(), "title_dirty must be false after reset");
    assert_eq!(term.title(), "");
}

/// A second OSC 2 after the first re-sets title_dirty to true.
#[test]
fn test_title_dirty_resets_on_second_osc2() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b]2;first\x07");
    assert!(term.title_dirty());

    // Simulate consuming the dirty flag (as the render cycle would)
    // by using reset (cheapest way to clear title_dirty in integration tests)
    term.reset();
    assert!(!term.title_dirty());

    // A new OSC 2 must re-set the flag
    term.advance(b"\x1b]2;second\x07");
    assert!(
        term.title_dirty(),
        "title_dirty must be true after second OSC 2"
    );
    assert_eq!(term.title(), "second");
}

// === Tab stop initialization after resize ===

/// After a resize that grows the terminal, new default tab stops appear at
/// every 8th column in the expanded region.
#[test]
fn test_tab_stops_available_after_resize_grow() {
    let mut term = TerminalCore::new(24, 16); // only cols 8 is a tab stop
                                              // Tab from col 0 should land on col 8
    term.advance(b"\t");
    assert_eq!(
        term.cursor_col(),
        8,
        "tab should land on col 8 in 16-col terminal"
    );

    // Resize to 32 cols — col 24 is now a new default tab stop
    term.resize(24, 32);
    // Move cursor to col 8 (a known stop) then tab; should jump to col 16
    term.advance(b"\x1b[1;9H"); // move to row 0, col 9 (0-indexed: row=0, col=8)
    term.advance(b"\t");
    assert_eq!(
        term.cursor_col(),
        16,
        "tab from col 8 should land on col 16 after resize to 32 cols"
    );
}
