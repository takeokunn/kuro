
use super::*;

/// SU (CSI S) does not move the cursor — cursor stays at its row even after
/// the scroll region shifts content up.
#[test]
fn test_scroll_up_cursor_stays_in_region() {
    let mut term = crate::TerminalCore::new(24, 80);
    // Set scroll region rows 2-10 (1-indexed CSI 2;10 r → 0-indexed top=1, bottom=10)
    term.advance(b"\x1b[2;10r");
    // Move cursor to row 5 (within the scroll region)
    term.screen.move_cursor(5, 10);
    assert_eq!(term.screen.cursor().row, 5);
    assert_eq!(term.screen.cursor().col, 10);

    // Scroll up 1 line within the region
    term.advance(b"\x1b[S");

    // Cursor must not be moved by SU
    assert_eq!(
        term.screen.cursor().row,
        5,
        "SU must not move the cursor row"
    );
    assert_eq!(
        term.screen.cursor().col,
        10,
        "SU must not move the cursor col"
    );
}

/// SD with a full-screen scroll region: after scrolling down 3, row 0 is blank
/// (the 3 newly inserted rows at the top).
#[test]
fn test_scroll_down_with_full_screen_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'A');

    // Full-screen terminal: default scroll region covers all rows.
    // Scroll down 3 lines
    term.advance(b"\x1b[3T");

    // Row 0 must be blank (newly inserted blank row from SD)
    assert_eq!(
        term.screen.get_line(0).unwrap().cells[0].char(),
        ' ',
        "row 0 must be blank after SD 3 (new blank inserted at top)"
    );
    // Row 1 and 2 also blank
    assert_eq!(
        term.screen.get_line(1).unwrap().cells[0].char(),
        ' ',
        "row 1 must be blank after SD 3"
    );
    assert_eq!(
        term.screen.get_line(2).unwrap().cells[0].char(),
        ' ',
        "row 2 must be blank after SD 3"
    );
    // Row 3 now holds former row 0 content ('A')
    assert_eq!(
        term.screen.get_line(3).unwrap().cells[0].char(),
        'A',
        "row 3 must hold former row 0 content after SD 3"
    );
}

/// Setting a second DECSTBM after moving the cursor: cursor must return to
/// home (0, 0) each time a valid DECSTBM is processed.
#[test]
fn test_decstbm_cursor_moves_to_home() {
    let mut term = crate::TerminalCore::new(24, 80);

    // First DECSTBM: rows 5-20 (1-indexed)
    term.advance(b"\x1b[5;20r");
    // Cursor should be at (0, 0) now
    assert_eq!(term.screen.cursor().row, 0);

    // Advance cursor to somewhere else
    term.screen.move_cursor(8, 15);
    assert_eq!(term.screen.cursor().row, 8);

    // Second DECSTBM: rows 3-15 (1-indexed)
    term.advance(b"\x1b[3;15r");

    // Cursor must be homed again
    assert_eq!(
        term.screen.cursor().row,
        0,
        "DECSTBM must always home cursor to row 0 (DECOM off)"
    );
    assert_eq!(
        term.screen.cursor().col,
        0,
        "DECSTBM must always home cursor to col 0"
    );
    // Scroll region must be updated
    assert_eq!(term.screen.get_scroll_region().top, 2); // 3-1=2
    assert_eq!(term.screen.get_scroll_region().bottom, 15);
}

// CSI 0 S — parameter 0 is clamped to 1 by the implementation (n.max(1)),
// so the screen scrolls up by exactly 1 line. This is distinct from a no-op.
test_scroll_zero_param_is_one!(
    test_su_zero_lines_is_one_line,
    seq = b"\x1b[0S",
    fill = b'0',
    rows = 5,
    row0 = '1',
    "CSI 0 S scrolls up by 1 (0 is clamped to 1)",
    bottom = 4,
    ' ',
    "bottom row must be blank after CSI 0 S",
);

/// CSI 0 T — parameter 0 is clamped to 1 by the implementation,
/// so the screen scrolls down by exactly 1 line.
#[test]
fn test_sd_zero_lines_is_one_line() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_rows!(term, rows 5, base b'A');

    // CSI 0 T: parameter 0 → treated as 1 (implementation uses n.max(1))
    term.advance(b"\x1b[0T");

    // Row 0 must be blank (new line inserted at top)
    assert_eq!(
        term.screen.get_line(0).unwrap().cells[0].char(),
        ' ',
        "CSI 0 T scrolls down by 1 (0 is clamped to 1) — row 0 becomes blank"
    );
    // Row 1 must hold former row 0 content ('A')
    assert_eq!(
        term.screen.get_line(1).unwrap().cells[0].char(),
        'A',
        "former row 0 content must appear at row 1 after CSI 0 T"
    );
}

// ── BCE (Background Color Erase) propagation ─────────────────────────────────

// SU with a non-default SGR background: newly introduced blank lines must
// carry the current SGR background color, not `Color::Default`.
test_scroll_bce_propagated!(
    test_su_bce_background_propagated,
    seq = b"\x1b[2S",
    fill = 'X',
    sgr = b"\x1b[44m",
    blank_range = 3..5,
    msg_char = "must be blank",
    msg_bg = "SU blank line must carry BCE background",
);

// SD with a non-default SGR background: newly introduced blank lines at the
// top of the scroll region must carry the current SGR background color.
test_scroll_bce_propagated!(
    test_sd_bce_background_propagated,
    seq = b"\x1b[2T",
    fill = 'Y',
    sgr = b"\x1b[41m",
    blank_range = 0..2,
    msg_char = "must be blank",
    msg_bg = "SD blank line must carry BCE background",
);

/// SD marks affected rows dirty — symmetry with `test_scroll_marks_dirty` for SU.
#[test]
fn test_sd_marks_dirty() {
    let mut term = crate::TerminalCore::new(5, 10);

    // Clear dirty set, fill a line, then mark it clean
    term.screen.take_dirty_lines();
    for c in 0..10 {
        if let Some(line) = term.screen.get_line_mut(4) {
            line.update_cell_with(c, crate::types::Cell::new('X'));
            line.is_dirty = false;
        }
    }

    // Scroll down 1 line
    let params = vte::Params::default();
    csi_sd(&mut term, &params);

    let dirty = term.screen.take_dirty_lines();
    assert!(!dirty.is_empty(), "SD must mark at least one row dirty");
}

/// DECSTBM with default parameters (CSI r) must restore the full-screen scroll
/// region: top=0, bottom=rows.
#[test]
fn test_decstbm_default_restores_full_screen() {
    let mut term = crate::TerminalCore::new(10, 80);

    // First set a non-default scroll region
    term.advance(b"\x1b[3;8r");
    assert_eq!(term.screen.get_scroll_region().top, 2);
    assert_eq!(term.screen.get_scroll_region().bottom, 8);

    // Now reset with default DECSTBM (no params → full screen)
    let params = vte::Params::default();
    csi_decstbm(&mut term, &params);

    assert_eq!(
        term.screen.get_scroll_region().top,
        0,
        "default DECSTBM must set top=0"
    );
    assert_eq!(
        term.screen.get_scroll_region().bottom,
        10,
        "default DECSTBM must set bottom=rows"
    );
}

/// RI (ESC M) BCE: when a scroll occurs (cursor at scroll-region top), the
/// newly inserted blank row at the top of the scroll region must carry the
/// current SGR background color.
#[test]
fn test_ri_bce_background_propagated() {
    let mut term = crate::TerminalCore::new(10, 10);

    // Fill all rows with content
    fill_rows!(term, rows 10, char 'X');

    // Set SGR green background
    term.advance(b"\x1b[42m"); // SGR 42 = green background

    // Place cursor at scroll-region top (row 0 with default region)
    term.screen.move_cursor(0, 0);

    // RI at the scroll-region top must scroll down and insert a blank row
    term.advance(b"\x1bM");

    // Row 0 is the newly inserted blank line — must carry BCE background
    let cell = term.screen.get_cell(0, 0).unwrap();
    assert_eq!(cell.char(), ' ', "RI blank row must be space");
    assert_ne!(
        cell.attrs.background,
        crate::Color::Default,
        "RI blank row at scroll-region top must carry BCE background"
    );
}

/// SU with a scroll region that occupies only two rows: one scroll-up must
/// leave the top row with the former bottom row's content, and the bottom row
/// blank.
#[test]
fn test_su_two_row_scroll_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'0');

    // 0-indexed scroll region: rows 4 and 5 (top=4, bottom=6 exclusive)
    term.screen.set_scroll_region(4, 6);

    let params = vte::Params::default();
    csi_su(&mut term, &params); // SU 1

    // Row 4 now holds what was in row 5 ('5')
    assert_eq!(term.screen.get_line(4).unwrap().cells[0].char(), '5');
    // Row 5 is now blank
    assert_eq!(term.screen.get_line(5).unwrap().cells[0].char(), ' ');
    // Rows outside the region are unchanged
    assert_eq!(term.screen.get_line(3).unwrap().cells[0].char(), '3');
    assert_eq!(term.screen.get_line(6).unwrap().cells[0].char(), '6');
}
