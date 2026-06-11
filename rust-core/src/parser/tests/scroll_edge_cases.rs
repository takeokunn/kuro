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
    seq = b"\x1b[0S",
    fill = b'0',
    rows = 5,
    row0 = '1',
    "CSI 0 S must scroll up by 1",
    bottom = 4,
    ' ',
    "bottom row must be blank after SU 0→1",
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
    seq = b"\x1b[4S",
    fill = 'X',
    rows = 4,
    msg = "must be blank after full-height SU",
);

// SD with count equal to screen height blanks the whole visible area.
test_scroll_full_height_blanks_all!(
    test_sd_full_screen_height_blanks_all,
    seq = b"\x1b[4T",
    fill = 'Y',
    rows = 4,
    msg = "must be blank after full-height SD",
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

include!("scroll_edge_cases2.rs");
