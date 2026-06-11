#[test]
fn test_cub_cursor_backward_clamp() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[1;10H"); // col 9 (0-indexed)
    assert_eq!(term.cursor_col(), 9);
    term.advance(b"\x1b[3D"); // CUB 3 → col 6
    assert_eq!(term.cursor_col(), 6, "CUB 3 from col 9 must land on col 6");
    // CUB with a count larger than current col must clamp to 0
    term.advance(b"\x1b[100D");
    assert_eq!(term.cursor_col(), 0, "CUB 100 must clamp cursor to col 0");
}

/// CUF (CSI n C) moves the cursor right by n columns, clamping at the right margin.
#[test]
fn test_cuf_cursor_forward_clamp() {
    let mut term = TerminalCore::new(24, 10);
    term.advance(b"\x1b[1;1H"); // col 0
    term.advance(b"\x1b[3C"); // CUF 3 → col 3
    assert_eq!(term.cursor_col(), 3, "CUF 3 from col 0 must land on col 3");
    // CUF with a large count must clamp at last column (9 on a 10-col terminal)
    term.advance(b"\x1b[100C");
    assert_eq!(
        term.cursor_col(),
        9,
        "CUF 100 must clamp cursor to last col (9)"
    );
}

/// CUD (CSI n B) moves the cursor down by n rows, clamping at the last row.
#[test]
fn test_cud_cursor_down_clamp() {
    let mut term = TerminalCore::new(10, 80);
    term.advance(b"\x1b[1;1H"); // row 0
    term.advance(b"\x1b[3B"); // CUD 3 → row 3
    assert_eq!(term.cursor_row(), 3, "CUD 3 from row 0 must land on row 3");
    term.advance(b"\x1b[100B"); // CUD large → clamp at last row (9)
    assert_eq!(
        term.cursor_row(),
        9,
        "CUD 100 must clamp cursor to last row (9)"
    );
}

/// EL 0 (CSI 0 K) erases from cursor to end of line.
#[test]
fn test_el0_erases_to_end_of_line() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"ABCDE");
    term.advance(b"\x1b[1;3H"); // move to row 0, col 2 (1-indexed)
    term.advance(b"\x1b[0K"); // EL 0: erase from cursor to EOL
                              // Cells 0 and 1 must still hold 'A' and 'B'; cells from col 2 onward must be erased
    let a = term.get_cell(0, 0).expect("cell (0,0) must exist");
    let b = term.get_cell(0, 1).expect("cell (0,1) must exist");
    assert_eq!(a.char(), 'A', "cell (0,0) must be 'A' — not erased by EL 0");
    assert_eq!(b.char(), 'B', "cell (0,1) must be 'B' — not erased by EL 0");
    let c = term.get_cell(0, 2).expect("cell (0,2) must exist");
    assert_eq!(c.char(), ' ', "cell (0,2) must be erased (space) by EL 0");
}

/// EL 1 (CSI 1 K) erases from beginning of line to cursor (inclusive).
#[test]
fn test_el1_erases_to_start_of_line() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"ABCDE");
    term.advance(b"\x1b[1;4H"); // move to row 0, col 3 (1-indexed)
    term.advance(b"\x1b[1K"); // EL 1: erase from BOL to cursor
                              // Cols 0–3 must be spaces; col 4 must still hold 'E'
    for col in 0..=3 {
        let cell = term.get_cell(0, col).expect("cell must exist");
        assert_eq!(
            cell.char(),
            ' ',
            "cell (0,{col}) must be erased (space) by EL 1"
        );
    }
    let e = term.get_cell(0, 4).expect("cell (0,4) must exist");
    assert_eq!(e.char(), 'E', "cell (0,4) must survive EL 1");
}

/// SGR strikethrough (9) and blink (5) must set the corresponding flags.
#[test]
fn test_sgr_strikethrough_and_blink() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[9m"); // strikethrough on
    let attrs = term.current_attrs();
    assert!(
        attrs.flags.contains(SgrFlags::STRIKETHROUGH),
        "strikethrough must be set after SGR 9"
    );
    term.advance(b"\x1b[5m"); // blink-slow on
    let attrs2 = term.current_attrs();
    assert!(
        attrs2.flags.contains(SgrFlags::BLINK_SLOW),
        "blink must be set after SGR 5"
    );
    // SGR 0 must clear both
    term.advance(b"\x1b[0m");
    let attrs3 = term.current_attrs();
    assert!(
        !attrs3.flags.contains(SgrFlags::STRIKETHROUGH),
        "strikethrough cleared by SGR 0"
    );
    assert!(
        !attrs3.flags.contains(SgrFlags::BLINK_SLOW),
        "blink cleared by SGR 0"
    );
}

/// SGR reverse video (7) must set the INVERSE flag.
#[test]
fn test_sgr_reverse_video() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[7m"); // reverse on
    let attrs = term.current_attrs();
    assert!(
        attrs.flags.contains(SgrFlags::INVERSE),
        "INVERSE must be set after SGR 7"
    );
    term.advance(b"\x1b[0m");
    assert!(
        !term.current_attrs().flags.contains(SgrFlags::INVERSE),
        "INVERSE cleared by SGR 0"
    );
}

/// IL (CSI n L) inserts n blank lines at the cursor row, scrolling down.
/// The cursor must not leave the scroll region and no panic must occur.
#[test]
fn test_il_insert_lines_no_panic() {
    let mut term = TerminalCore::new(10, 80);
    term.advance(b"line0\nline1\nline2");
    term.advance(b"\x1b[2;1H"); // move to row 1 (1-indexed)
    term.advance(b"\x1b[2L"); // IL 2: insert 2 blank lines
    assert!(
        term.cursor_row() < 10,
        "cursor row must remain in bounds after IL"
    );
}

/// DL (CSI n M) deletes n lines at the cursor row, scrolling up within the region.
/// No panic must occur and cursor must stay in bounds.
#[test]
fn test_dl_delete_lines_no_panic() {
    let mut term = TerminalCore::new(10, 80);
    term.advance(b"line0\nline1\nline2\nline3");
    term.advance(b"\x1b[2;1H"); // move to row 1 (1-indexed)
    term.advance(b"\x1b[2M"); // DL 2: delete 2 lines
    assert!(
        term.cursor_row() < 10,
        "cursor row must remain in bounds after DL"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// REP — Repeat Character (CSI Ps b)
// ─────────────────────────────────────────────────────────────────────────────

/// REP repeats the last printed ASCII character the specified number of times.
#[test]
fn test_rep_repeats_last_ascii_char() {
    let mut term = TerminalCore::new(24, 80);
    // Print 'A' then repeat it 4 more times → columns 0..4 all = 'A'
    term.advance(b"A\x1b[4b");
    for col in 0..5 {
        let ch = term.get_cell(0, col).map(|c| c.char()).unwrap_or('\0');
        assert_eq!(ch, 'A', "REP: cell (0,{col}) must be 'A', got {ch:?}");
    }
}

/// REP with count 1 (default) adds exactly one copy.
#[test]
fn test_rep_default_count_is_one() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"X\x1b[b"); // CSI b with no param → default 1
    let c0 = term.get_cell(0, 0).map(|c| c.char()).unwrap_or('\0');
    let c1 = term.get_cell(0, 1).map(|c| c.char()).unwrap_or('\0');
    assert_eq!(c0, 'X', "REP: first cell must be 'X'");
    assert_eq!(c1, 'X', "REP: second cell must be 'X' (default repeat=1)");
}

/// REP with no preceding character is a no-op (must not panic).
#[test]
fn test_rep_without_prior_char_is_noop() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[5b"); // No preceding character
    assert_eq!(term.cursor_row(), 0);
    assert_eq!(term.cursor_col(), 0);
}

/// REP after a non-ASCII character repeats it.
#[test]
fn test_rep_repeats_non_ascii_char() {
    let mut term = TerminalCore::new(24, 80);
    // Print '€' (U+20AC, width 1) then repeat 2 more times
    term.advance("€\x1b[2b".as_bytes());
    for col in 0..3 {
        let ch = term.get_cell(0, col).map(|c| c.char()).unwrap_or('\0');
        assert_eq!(ch, '€', "REP non-ASCII: cell (0,{col}) must be '€', got {ch:?}");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// XTPUSHTITLE / XTPOPTITLE (CSI 22;0;0t / CSI 23;0;0t)
// ─────────────────────────────────────────────────────────────────────────────

/// XTPUSHTITLE saves the current title; XTPOPTITLE restores it.
#[test]
fn test_xtpushtitle_xtpoptitle_roundtrip() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b]2;original title\x07"); // set title
    term.advance(b"\x1b[22;0;0t");              // push
    term.advance(b"\x1b]2;temporary title\x07"); // change title
    term.advance(b"\x1b[23;0;0t");              // pop → restore
    assert_eq!(term.title(), "original title");
    assert!(term.title_dirty(), "title_dirty must be set after pop");
}

/// XTPUSHTITLE stack supports multiple levels.
#[test]
fn test_xtpushtitle_stack_multiple_levels() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b]2;level-0\x07");
    term.advance(b"\x1b[22;0;0t");
    term.advance(b"\x1b]2;level-1\x07");
    term.advance(b"\x1b[22;0;0t");
    term.advance(b"\x1b]2;level-2\x07");
    term.advance(b"\x1b[23;0;0t"); // pop → level-1
    assert_eq!(term.title(), "level-1");
    term.advance(b"\x1b[23;0;0t"); // pop → level-0
    assert_eq!(term.title(), "level-0");
}

/// XTPOPTITLE on an empty stack must be a no-op (no panic, title unchanged).
#[test]
fn test_xtpoptitle_on_empty_stack_is_noop() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b]2;my title\x07");
    term.advance(b"\x1b[23;0;0t"); // pop empty stack
    assert_eq!(term.title(), "my title", "title unchanged after noop pop");
}

// ─────────────────────────────────────────────────────────────────────────────
// soft_reset must clear sgr_stack
// ─────────────────────────────────────────────────────────────────────────────

/// DECSTR (CSI ! p) must clear the XTPUSHSGR stack.
#[test]
fn test_soft_reset_clears_sgr_stack() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[1m");       // bold on
    term.advance(b"\x1b[#{\x1b[0m"); // push bold, reset
    term.advance(b"\x1b[!p");       // DECSTR: soft reset — must clear the stack
    term.advance(b"\x1b[#}");       // pop from (now empty) stack — must be noop
    assert!(!term.current_bold(), "bold must NOT be restored after soft_reset cleared stack");
}

// ─────────────────────────────────────────────────────────────────────────────
// XTMODKEYS (CSI > 4 ; Ps m)
// ─────────────────────────────────────────────────────────────────────────────

/// XTMODKEYS type 4 value 2 sets modifyOtherKeys to 2.
#[test]
fn test_xtmodkeys_sets_modify_other_keys() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[>4;2m"); // modifyOtherKeys level 2
    assert_eq!(term.dec_modes().modify_other_keys, 2);
}

/// XTMODKEYS with value 0 disables modifyOtherKeys.
#[test]
fn test_xtmodkeys_reset_to_zero() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[>4;1m");
    assert_eq!(term.dec_modes().modify_other_keys, 1);
    term.advance(b"\x1b[>4;0m");
    assert_eq!(term.dec_modes().modify_other_keys, 0);
}

/// XTMODKEYS for type != 4 must be silently accepted without panic.
#[test]
fn test_xtmodkeys_non_4_type_is_noop() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[>1;1m"); // type 1 = modifyCursorKeys (not tracked)
    assert_eq!(term.dec_modes().modify_other_keys, 0, "untracked type must not affect modify_other_keys");
}

// ─────────────────────────────────────────────────────────────────────────────
// SGR 53 / 55 — Overline
// ─────────────────────────────────────────────────────────────────────────────

/// SGR 53 sets overline; SGR 55 resets it; SGR 0 also resets it.
#[test]
fn test_sgr53_overline_on_and_55_off() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[53m");
    assert!(term.current_overline(), "SGR 53 must set overline");
    term.advance(b"\x1b[55m");
    assert!(!term.current_overline(), "SGR 55 must clear overline");
}

#[test]
fn test_sgr0_clears_overline() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[53m");
    term.advance(b"\x1b[0m");
    assert!(!term.current_overline(), "SGR 0 must clear overline");
}

// ─────────────────────────────────────────────────────────────────────────────
// DECERA (CSI Pt;Pl;Pb;Pr $ z) — Erase Rectangular Area
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_decera_fills_rectangle_with_spaces() {
    let mut term = TerminalCore::new(10, 20);
    // Use CUP to position cursor precisely (avoids \r\n complications)
    term.advance(b"\x1b[1;1HAAAAAAAAAAAAAAAAAAAA"); // row 0 (1-indexed): 20 A's
    term.advance(b"\x1b[2;1HBBBBBBBBBBBBBBBBBBBB"); // row 1 (1-indexed): 20 B's
    term.advance(b"\x1b[3;1HCCCCCCCCCCCCCCCCCCCC"); // row 2 (1-indexed): 20 C's
    // Erase rectangle: rows 2-3, cols 5-10 (1-indexed) → 0-indexed: rows 1-2, cols 4-9
    term.advance(b"\x1b[2;5;3;10$z");
    // Row 0 should be untouched: 20 A's
    for col in 0..20 {
        assert_eq!(term.get_cell(0, col).map(|c| c.char()).unwrap_or('\0'), 'A',
            "row 0 col {col} must be untouched");
    }
    // Row 1 cols 4-9 (0-indexed) should be spaces
    for col in 4..10 {
        assert_eq!(term.get_cell(1, col).map(|c| c.char()).unwrap_or('\0'), ' ',
            "row 1 col {col} must be erased");
    }
    // Row 1 col 10 (0-indexed, outside rect) should be B
    assert_eq!(term.get_cell(1, 10).map(|c| c.char()).unwrap_or('\0'), 'B');
}

#[test]
fn test_decera_does_not_panic_out_of_bounds() {
    let mut term = TerminalCore::new(5, 10);
    term.advance(b"\x1b[1;1;999;999$z"); // huge rectangle — must clamp, not panic
    assert!(term.cursor_row() < 5);
}


