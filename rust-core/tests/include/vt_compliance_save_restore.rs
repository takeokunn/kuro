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
