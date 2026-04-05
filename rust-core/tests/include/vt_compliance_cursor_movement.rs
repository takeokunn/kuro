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
            let ch = t.get_cell(row, col).map_or(' ', |c| c.char());
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

include!("vt_compliance_save_restore.rs");
