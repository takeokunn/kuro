// ── New tests: ESC sequences not yet covered ───────────────────────────────────────────────────

/// RIS (ESC c) performs a full terminal reset; cursor returns to origin.
#[test]
fn test_esc_ris_full_reset_cursor_to_origin() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[10;20H"); // move away
    assert_cursor!(term, row 9, col 19);
    term.advance(b"\x1bc"); // RIS: full reset
    assert_cursor!(term, row 0, col 0);
}

/// RI (ESC M) — Reverse Index: at row > 0, cursor moves up one row.
#[test]
fn test_esc_ri_moves_cursor_up() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[5;1H"); // row 4 (0-indexed)
    assert_cursor!(term, row 4, col 0);
    term.advance(b"\x1bM"); // RI
    assert_cursor!(term, row 3, col 0);
}

/// IND (ESC D) — Index: cursor moves down one row, just like LF.
#[test]
fn test_esc_ind_moves_cursor_down() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[3;1H"); // row 2 (0-indexed)
    assert_cursor!(term, row 2, col 0);
    term.advance(b"\x1bD"); // IND
    assert_cursor!(term, row 3, col 0);
}

/// NEL (ESC E) — Next Line: carriage return + line feed.
#[test]
fn test_esc_nel_cr_plus_lf() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[4;15H"); // row 3, col 14
    assert_cursor!(term, row 3, col 14);
    term.advance(b"\x1bE"); // NEL
    // cursor must be at row 4, col 0
    assert_cursor!(term, row 4, col 0);
}

/// DECKPAM (ESC =) and DECKPNM (ESC >) — application/normal keypad mode.
#[test]
fn test_esc_deckpam_deckpnm_toggle_app_keypad() {
    let mut term = TerminalCore::new(24, 80);
    assert!(
        !term.dec_modes.app_keypad,
        "app_keypad must default to false"
    );
    term.advance(b"\x1b="); // DECKPAM
    assert!(term.dec_modes.app_keypad, "DECKPAM must enable app_keypad");
    term.advance(b"\x1b>"); // DECKPNM
    assert!(
        !term.dec_modes.app_keypad,
        "DECKPNM must disable app_keypad"
    );
}

/// CNL (CSI E) — Cursor Next Line: moves down N rows and to column 0.
#[test]
fn test_csi_cnl_moves_down_and_to_col_zero() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[3;10H"); // row 2, col 9
    assert_cursor!(term, row 2, col 9);
    term.advance(b"\x1b[2E"); // CNL 2: down 2 rows, col 0
    assert_cursor!(term, row 4, col 0);
}

/// CPL (CSI F) — Cursor Previous Line: moves up N rows and to column 0.
#[test]
fn test_csi_cpl_moves_up_and_to_col_zero() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[6;15H"); // row 5, col 14
    assert_cursor!(term, row 5, col 14);
    term.advance(b"\x1b[3F"); // CPL 3: up 3 rows, col 0
    assert_cursor!(term, row 2, col 0);
}

/// CSI ? u — Kitty keyboard query: must queue a response.
#[test]
fn test_csi_kitty_kb_query_queues_response() {
    let term = term_with!(b"\x1b[?u");
    assert!(
        !term.meta.pending_responses.is_empty(),
        "CSI ? u must queue a keyboard flags response"
    );
}

// ── New tests: C0 controls, CSI handlers not yet covered ──────────────────

/// LF (0x0A), VT (0x0B), FF (0x0C) all advance the cursor row by exactly 1.
/// Use the macro to avoid three nearly-identical test bodies.
#[test]
fn test_c0_lf_vt_ff_all_advance_row() {
    assert_c0_linefeed!(0x0A, 1, "LF");
    assert_c0_linefeed!(0x0B, 1, "VT");
    assert_c0_linefeed!(0x0C, 1, "FF");
}

// SO (0x0E) and SI (0x0F) are character-set shift controls.
// They switch GL between G0 and G1 but must not generate any response.
assert_no_response!(test_so_no_response, b"\x0e");
assert_no_response!(test_si_no_response, b"\x0f");

// NUL (0x00) and DEL (0x7f) are ignored by the VTE execute path.
assert_no_response!(test_nul_no_response, b"\x00");

/// SGR dim (CSI 2 m) must set the DIM flag.
#[test]
fn test_vte_sgr_dim() {
    assert_sgr_flag!(b"\x1b[2m", SgrFlags::DIM, "SGR 2 must set DIM flag");
}

/// SGR rapid blink (CSI 6 m) must set the BLINK_FAST flag.
#[test]
fn test_vte_sgr_blink_fast() {
    assert_sgr_flag!(
        b"\x1b[6m",
        SgrFlags::BLINK_FAST,
        "SGR 6 must set BLINK_FAST flag"
    );
}

/// SGR concealed/hidden (CSI 8 m) must set the HIDDEN flag.
#[test]
fn test_vte_sgr_hidden() {
    assert_sgr_flag!(b"\x1b[8m", SgrFlags::HIDDEN, "SGR 8 must set HIDDEN flag");
}

/// CHA (CSI G) — Cursor Horizontal Absolute: moves cursor to column N (1-indexed).
#[test]
fn test_csi_cha_moves_to_absolute_column() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[20G"); // CHA 20 — move to col 19 (0-indexed)
    assert_eq!(
        term.screen.cursor().col,
        19,
        "CHA 20 must set cursor col to 19 (0-indexed)"
    );
}

/// VPA (CSI d) — Vertical Position Absolute: moves cursor to row N (1-indexed).
#[test]
fn test_csi_vpa_moves_to_absolute_row() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[10d"); // VPA 10 — move to row 9 (0-indexed)
    assert_eq!(
        term.screen.cursor().row,
        9,
        "VPA 10 must set cursor row to 9 (0-indexed)"
    );
}

/// HPA (CSI `` ` ``) — not yet implemented; must be silently ignored.
/// Cursor column must remain unchanged after receiving HPA.
#[test]
fn test_csi_hpa_unimplemented_is_noop() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[5;1H"); // cursor to row 4, col 0
    term.advance(b"\x1b[15`"); // HPA 15 — silently ignored
    // Column must not have changed (stays at 0)
    assert_eq!(
        term.screen.cursor().col,
        0,
        "HPA (unimplemented) must not change cursor col"
    );
}

/// DECSTR (CSI ! p) must clear bold SGR flag set before the reset.
#[test]
fn test_csi_decstr_clears_sgr_bold() {
    let mut term = term_with!(b"\x1b[1m"); // bold on
    assert!(term.current_attrs.flags.contains(SgrFlags::BOLD));
    term.advance(b"\x1b[!p"); // DECSTR
    // After soft reset, bold should be cleared
    assert!(
        !term.current_attrs.flags.contains(SgrFlags::BOLD),
        "DECSTR must clear SGR BOLD"
    );
}

/// REP (CSI b) — not yet implemented; must be silently ignored without panic.
/// After REP the printed character must still be in col 0; the cursor must
/// remain at col 1 (positioned after the original 'A' print, not moved by REP).
#[test]
fn test_csi_rep_unimplemented_is_noop() {
    let term = term_with!(b"A\x1b[3b"); // 'A' then REP 3 — silently ignored
    // 'A' printed at col 0; cursor advanced to col 1
    assert_cell_char!(term, row 0, col 0, 'A');
    // Cols 1-3 are blank — REP did nothing
    assert_cell_char!(term, row 0, col 1, ' ');
    assert_cell_char!(term, row 0, col 2, ' ');
    // Cursor must be at col 1 (after the 'A'), not moved further by REP
    assert_cursor!(term, row 0, col 1);
}

/// IL (CSI L) — Insert Line: inserts a blank line at the cursor row.
/// The line that was at the cursor row shifts down.
#[test]
fn test_csi_il_inserts_blank_line() {
    let mut term = term_with!(b"AAAA\nBBBB");
    // cursor is now at row 1; go back to row 0
    term.advance(b"\x1b[1;1H");
    term.advance(b"\x1b[1L"); // IL 1: insert blank line at row 0
    // Row 0 must now be blank; row 1 must have 'A' content
    assert_eq!(
        term.screen.get_cell(0, 0).unwrap().char(),
        ' ',
        "row 0 col 0 must be blank after IL"
    );
    assert_eq!(
        term.screen.get_cell(1, 0).unwrap().char(),
        'A',
        "row 1 col 0 must be 'A' shifted down by IL"
    );
}

/// DL (CSI M) — Delete Line: removes the cursor row; lines below shift up.
#[test]
fn test_csi_dl_deletes_line() {
    let mut term = TerminalCore::new(24, 80);
    // Place 'A' at row 0 col 0, 'B' at row 1 col 0 using explicit cursor moves
    // (avoids bare \n which is LF-only and does not reset the column).
    term.advance(b"\x1b[1;1H"); // CUP → row 0, col 0 (1-indexed)
    term.advance(b"A");
    term.advance(b"\x1b[2;1H"); // CUP → row 1, col 0 (1-indexed)
    term.advance(b"B");
    term.advance(b"\x1b[1;1H"); // cursor back to row 0
    term.advance(b"\x1b[1M"); // DL 1: delete row 0; row 1 shifts up
    // Row 0 now holds what was row 1 ('B' at col 0)
    assert_eq!(
        term.screen.get_cell(0, 0).unwrap().char(),
        'B',
        "row 0 must contain 'B' after DL deleted the previous row 0"
    );
}

/// DECSC (ESC 7) saves SGR attrs; DECRC (ESC 8) restores them.
#[test]
fn test_esc_decsc_saves_and_restores_sgr_attrs() {
    let mut term = TerminalCore::new(24, 80);
    // Set bold
    term.advance(b"\x1b[1m");
    assert!(term.current_attrs.flags.contains(SgrFlags::BOLD));
    term.advance(b"\x1b7"); // DECSC — save cursor + attrs
    // Clear bold
    term.advance(b"\x1b[0m");
    assert!(!term.current_attrs.flags.contains(SgrFlags::BOLD));
    term.advance(b"\x1b8"); // DECRC — restore
    assert!(
        term.current_attrs.flags.contains(SgrFlags::BOLD),
        "DECRC must restore BOLD flag saved by DECSC"
    );
}
