// ── New edge-case tests ───────────────────────────────────────────────────────

// ── Macros ────────────────────────────────────────────────────────────────────

/// Assert that SU (CSI S) or SD (CSI T) treats a zero parameter as 1.
///
/// `$seq`        — escape sequence bytes, e.g. `b"\x1b[0S"`
/// `$row0_char`  — expected character at row 0 after the scroll
/// `$row0_msg`   — assertion message for row 0
/// `$bottom_row` — index of the last row (rows - 1)
/// `$bottom_char`— expected character at the bottom row
/// `$bottom_msg` — assertion message for the bottom row
macro_rules! test_scroll_zero_param_is_one {
    (
        $name:ident,
        seq    = $seq:expr,
        fill   = $fill:expr,
        rows   = $rows:expr,
        row0   = $row0_char:expr, $row0_msg:expr,
        bottom = $bottom_row:expr, $bottom_char:expr, $bottom_msg:expr
        $(,)?
    ) => {
        #[test]
        fn $name() {
            let mut term = crate::TerminalCore::new($rows, 10);
            fill_rows!(term, rows $rows, base $fill);
            term.advance($seq);
            assert_eq!(
                term.screen.get_line(0).unwrap().cells[0].char(),
                $row0_char,
                $row0_msg
            );
            assert_eq!(
                term.screen.get_line($bottom_row).unwrap().cells[0].char(),
                $bottom_char,
                $bottom_msg
            );
        }
    };
}

/// Assert that a full-height SU or SD blanks every visible row.
///
/// `$seq`  — escape sequence that scrolls by exactly `$rows` lines
/// `$fill` — character used to fill all rows before scrolling
/// `$rows` — terminal height (also the scroll count)
/// `$msg`  — base message string (row index is appended automatically)
macro_rules! test_scroll_full_height_blanks_all {
    (
        $name:ident,
        seq  = $seq:expr,
        fill = $fill:expr,
        rows = $rows:expr,
        msg  = $msg:literal
        $(,)?
    ) => {
        #[test]
        fn $name() {
            let mut term = crate::TerminalCore::new($rows, 10);
            fill_rows!(term, rows $rows, char $fill);
            term.advance($seq);
            for r in 0..$rows {
                assert_eq!(
                    term.screen.get_line(r).unwrap().cells[0].char(),
                    ' ',
                    "row {r}: {}",
                    $msg
                );
            }
        }
    };
}

/// Assert that SU or SD with a non-default SGR background propagates BCE to
/// newly inserted blank rows.
///
/// `$seq`        — escape sequence (must scroll by 2)
/// `$fill`       — character used to pre-fill rows
/// `$sgr`        — SGR sequence that sets the background color
/// `$blank_range`— range of rows that should be newly-blank
/// `$msg_char`   — base label for the blank-char assertion (row index appended)
/// `$msg_bg`     — base label for the BCE background assertion (row index appended)
macro_rules! test_scroll_bce_propagated {
    (
        $name:ident,
        seq         = $seq:expr,
        fill        = $fill:expr,
        sgr         = $sgr:expr,
        blank_range = $range:expr,
        msg_char    = $msg_char:literal,
        msg_bg      = $msg_bg:literal
        $(,)?
    ) => {
        #[test]
        fn $name() {
            let mut term = crate::TerminalCore::new(5, 10);
            fill_rows!(term, rows 5, char $fill);
            term.advance($sgr);
            term.advance($seq);
            for r in $range {
                let cell = term.screen.get_cell(r, 0).unwrap();
                assert_eq!(cell.char(), ' ', "row {r}: {}", $msg_char);
                assert_ne!(
                    cell.attrs.background,
                    crate::Color::Default,
                    "row {r}: {}",
                    $msg_bg
                );
            }
        }
    };
}

// ── Zero-param clamping ────────────────────────────────────────────────────────

// SU by 0 lines: CSI 0 S is treated as CSI 1 S (parameter 0 → default 1).
// Row 0 must receive what was in row 1.
test_scroll_zero_param_is_one!(
    test_su_zero_param_treated_as_one,
    seq    = b"\x1b[0S",
    fill   = b'0',
    rows   = 5,
    row0   = '1', "CSI 0 S must scroll up by 1",
    bottom = 4, ' ', "bottom row must be blank after SU 0→1",
);

/// SD by 0 lines: CSI 0 T is treated as CSI 1 T.
/// Row 0 must become blank, former row 0 content appears at row 1.
#[test]
fn test_sd_zero_param_treated_as_one() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_rows!(term, rows 5, base b'A');

    term.advance(b"\x1b[0T"); // 0 → clamped to 1

    assert_eq!(
        term.screen.get_line(0).unwrap().cells[0].char(),
        ' ',
        "CSI 0 T must scroll down by 1 — top row blank"
    );
    assert_eq!(
        term.screen.get_line(1).unwrap().cells[0].char(),
        'A',
        "former row 0 must appear at row 1"
    );
}

// ── Full-height blanking ───────────────────────────────────────────────────────

// SU with count equal to screen height blanks the whole visible area.
test_scroll_full_height_blanks_all!(
    test_su_full_screen_height_blanks_all,
    seq  = b"\x1b[4S",
    fill = 'X',
    rows = 4,
    msg  = "must be blank after full-height SU",
);

// SD with count equal to screen height blanks the whole visible area.
test_scroll_full_height_blanks_all!(
    test_sd_full_screen_height_blanks_all,
    seq  = b"\x1b[4T",
    fill = 'Y',
    rows = 4,
    msg  = "must be blank after full-height SD",
);

/// SU inside a scroll region that is only 1 row tall: no content to displace,
/// the single row simply becomes blank.
#[test]
fn test_su_one_row_scroll_region_becomes_blank() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'0');

    // Narrow scroll region: just row 5 (0-indexed top=5, bottom=6)
    term.screen.set_scroll_region(5, 6);

    let params = vte::Params::default();
    csi_su(&mut term, &params);

    // Row 5 should be blank; all others unchanged
    assert_eq!(term.screen.get_line(5).unwrap().cells[0].char(), ' ');
    assert_eq!(term.screen.get_line(4).unwrap().cells[0].char(), '4');
    assert_eq!(term.screen.get_line(6).unwrap().cells[0].char(), '6');
}

/// SD at the very last row of the scroll region with a large count: no panic,
/// and the content above the region must be untouched.
#[test]
fn test_sd_large_count_preserves_rows_outside_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'0');

    // Scroll region: rows 3..7 (0-indexed)
    term.screen.set_scroll_region(3, 7);

    term.advance(b"\x1b[999T"); // massive SD — must not panic

    // Rows outside the region must be intact
    assert_rows_unchanged!(term, rows 3, base b'0');
    // Rows 7..10 also outside region
    for r in 7..10 {
        let ch = (b'0' + r as u8) as char;
        assert_eq!(
            term.screen.get_line(r).unwrap().cells[0].char(),
            ch,
            "row {r} below region must be unchanged"
        );
    }
    // Rows inside region must all be blank
    for r in 3..7 {
        assert_eq!(
            term.screen.get_line(r).unwrap().cells[0].char(),
            ' ',
            "row {r} inside region must be blank after large SD"
        );
    }
}

/// RI repeated from row 1 (not the scroll-region top): cursor should walk up
/// each call until it reaches row 0.
#[test]
fn test_ri_repeated_cursor_walk_up() {
    let mut term = crate::TerminalCore::new(10, 10);
    term.screen.move_cursor(3, 5);

    // Three RI commands — cursor should be at row 0 after
    term.advance(b"\x1bM");
    term.advance(b"\x1bM");
    term.advance(b"\x1bM");

    assert_eq!(
        term.screen.cursor().row,
        0,
        "three RI calls from row 3 should reach row 0"
    );
    assert_eq!(
        term.screen.cursor().col,
        5,
        "RI must not change cursor column"
    );
}

/// SU with a scroll region not starting at row 0: rows above the region must
/// never be affected regardless of count.
#[test]
fn test_su_does_not_touch_rows_above_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'A');

    // Scroll region starts at row 4
    term.screen.set_scroll_region(4, 10);

    term.advance(b"\x1b[3S"); // scroll up 3 within region

    // Rows 0..4 must be absolutely untouched
    for r in 0..4 {
        let ch = (b'A' + r as u8) as char;
        assert_eq!(
            term.screen.get_line(r).unwrap().cells[0].char(),
            ch,
            "row {r} above scroll region must be unchanged"
        );
    }
}

/// SD with a scroll region not ending at the last row: rows below the region
/// must never be affected regardless of count.
#[test]
fn test_sd_does_not_touch_rows_below_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'0');

    // Scroll region ends before last row
    term.screen.set_scroll_region(0, 6);

    term.advance(b"\x1b[3T"); // scroll down 3 within region

    // Rows 6..10 must be absolutely untouched
    for r in 6..10 {
        let ch = (b'0' + r as u8) as char;
        assert_eq!(
            term.screen.get_line(r).unwrap().cells[0].char(),
            ch,
            "row {r} below scroll region must be unchanged"
        );
    }
}

// ── Additional edge-case tests ────────────────────────────────────────────────

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
    seq    = b"\x1b[0S",
    fill   = b'0',
    rows   = 5,
    row0   = '1', "CSI 0 S scrolls up by 1 (0 is clamped to 1)",
    bottom = 4, ' ', "bottom row must be blank after CSI 0 S",
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
    seq         = b"\x1b[2S",
    fill        = 'X',
    sgr         = b"\x1b[44m",
    blank_range = 3..5,
    msg_char    = "must be blank",
    msg_bg      = "SU blank line must carry BCE background",
);

// SD with a non-default SGR background: newly introduced blank lines at the
// top of the scroll region must carry the current SGR background color.
test_scroll_bce_propagated!(
    test_sd_bce_background_propagated,
    seq         = b"\x1b[2T",
    fill        = 'Y',
    sgr         = b"\x1b[41m",
    blank_range = 0..2,
    msg_char    = "must be blank",
    msg_bg      = "SD blank line must carry BCE background",
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
