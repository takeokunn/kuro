// ─────────────────────────────────────────────────────────────────────────────
// DECFRA (CSI Pch;Pt;Pl;Pb;Pr $ x) — Fill Rectangular Area
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_decfra_fills_rectangle_with_char() {
    let mut term = TerminalCore::new(10, 20);
    // Fill rows 1-3, cols 2-5 with 'X' (char code 88)
    term.advance(b"\x1b[88;1;2;3;5$x");
    for row in 0..3 {
        for col in 1..5 {
            assert_eq!(term.get_cell(row, col).map(|c| c.char()).unwrap_or('\0'), 'X',
                "DECFRA: cell ({row},{col}) must be 'X'");
        }
    }
}

#[test]
fn test_decfra_does_not_panic_out_of_bounds() {
    let mut term = TerminalCore::new(5, 10);
    term.advance(b"\x1b[65;1;1;999;999$x"); // 'A', huge rect
    assert_eq!(term.get_cell(0, 0).map(|c| c.char()).unwrap_or('\0'), 'A');
}

// ─────────────────────────────────────────────────────────────────────────────
// DECSED / DECSEL — Selective Erase (CSI ? J / CSI ? K)
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_decsed_erases_display_without_panic() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"Hello");
    term.advance(b"\x1b[?2J"); // DECSED: erase entire display
    assert!(term.cursor_row() < 24);
}

#[test]
fn test_decsel_erases_line_without_panic() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"Hello");
    term.advance(b"\x1b[?K"); // DECSEL: erase to end of line
    assert!(term.cursor_col() < 80);
}

// ─────────────────────────────────────────────────────────────────────────────
// ENQ (0x05) response
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_enq_emits_answerback() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x05"); // ENQ
    let responses = term.pending_responses();
    assert!(!responses.is_empty(), "ENQ must produce at least one response");
    let combined: Vec<u8> = responses.iter().flatten().copied().collect();
    assert_eq!(combined, b"kuro", "ENQ response must be \"kuro\"");
}

// ─────────────────────────────────────────────────────────────────────────────
// SL (CSI Ps SP @) / SR (CSI Ps SP A) — Scroll Left / Scroll Right
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_sl_shifts_line_content_left() {
    let mut term = TerminalCore::new(4, 10);
    // Write ABCDEFGHIJ on row 0
    term.advance(b"\x1b[1;1HABCDEFGHIJ");
    // Scroll left by 3 (CSI 3 SP @)
    term.advance(b"\x1b[3 @");
    // cols 0-6 should be D-J (shifted left), cols 7-9 should be blank
    assert_eq!(term.get_cell(0, 0).map(|c| c.char()).unwrap_or('\0'), 'D');
    assert_eq!(term.get_cell(0, 6).map(|c| c.char()).unwrap_or('\0'), 'J');
    assert_eq!(term.get_cell(0, 7).map(|c| c.char()).unwrap_or('\0'), ' ');
}

#[test]
fn test_sr_shifts_line_content_right() {
    let mut term = TerminalCore::new(4, 10);
    // Write ABCDEFGHIJ on row 0
    term.advance(b"\x1b[1;1HABCDEFGHIJ");
    // Scroll right by 2 (CSI 2 SP A)
    term.advance(b"\x1b[2 A");
    // cols 0-1 should be blank, cols 2-9 should be A-H (shifted right)
    assert_eq!(term.get_cell(0, 0).map(|c| c.char()).unwrap_or('\0'), ' ');
    assert_eq!(term.get_cell(0, 1).map(|c| c.char()).unwrap_or('\0'), ' ');
    assert_eq!(term.get_cell(0, 2).map(|c| c.char()).unwrap_or('\0'), 'A');
    assert_eq!(term.get_cell(0, 9).map(|c| c.char()).unwrap_or('\0'), 'H');
}

#[test]
fn test_sl_does_not_panic_on_large_count() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"Hello");
    term.advance(b"\x1b[999 @"); // huge count — must clamp, not panic
    assert!(term.cursor_row() < 24);
}

// ─────────────────────────────────────────────────────────────────────────────
// ESC # 3/4/5/6 — double-height/width (silently accepted, no panic)
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_decdhl_top_bottom_accepted() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b#3"); // DECDHL-Top
    term.advance(b"\x1b#4"); // DECDHL-Bottom
    assert_eq!(term.cursor_row(), 0);
}

#[test]
fn test_decswl_decdwl_accepted() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b#5"); // DECSWL (single-width)
    term.advance(b"\x1b#6"); // DECDWL (double-width)
    assert_eq!(term.cursor_row(), 0);
}

// ─────────────────────────────────────────────────────────────────────────────
// DECIC (CSI Ps ' }) — Insert Column
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_decic_inserts_blank_column_across_all_rows() {
    let mut term = TerminalCore::new(4, 10);
    term.advance(b"\x1b[1;1HABCDEFGHIJ"); // row 0: A-J
    term.advance(b"\x1b[2;1HKLMNOPQRST"); // row 1: K-T
    // Move cursor to col 2 (0-indexed), then DECIC with count 2
    term.advance(b"\x1b[1;3H"); // cursor to row 0, col 2 (1-indexed)
    term.advance(b"\x1b[2'}"); // DECIC: insert 2 columns (intermediate = apostrophe 0x27)
    // Row 0: A B _ _ C D E F G H (cols 0-9), where _ is blank
    assert_eq!(term.get_cell(0, 0).map(|c| c.char()).unwrap_or('\0'), 'A');
    assert_eq!(term.get_cell(0, 1).map(|c| c.char()).unwrap_or('\0'), 'B');
    assert_eq!(term.get_cell(0, 2).map(|c| c.char()).unwrap_or('\0'), ' ');
    assert_eq!(term.get_cell(0, 3).map(|c| c.char()).unwrap_or('\0'), ' ');
    assert_eq!(term.get_cell(0, 4).map(|c| c.char()).unwrap_or('\0'), 'C');
}

#[test]
fn test_decic_does_not_panic_out_of_bounds() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[999'}"); // huge count (apostrophe intermediate)
    assert!(term.cursor_row() < 24);
}

// ─────────────────────────────────────────────────────────────────────────────
// DECDC (CSI Ps ' ~) — Delete Column
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_decdc_deletes_column_across_all_rows() {
    let mut term = TerminalCore::new(4, 10);
    term.advance(b"\x1b[1;1HABCDEFGHIJ"); // row 0: A-J
    // Move cursor to col 1 (0-indexed), then DECDC with count 1
    term.advance(b"\x1b[1;2H"); // cursor to row 0, col 1 (1-indexed = 0-indexed col 1)
    term.advance(b"\x1b[1'~"); // DECDC: delete 1 column (apostrophe intermediate)
    // Row 0: A C D E F G H I J _ (B deleted, rest shifted left)
    assert_eq!(term.get_cell(0, 0).map(|c| c.char()).unwrap_or('\0'), 'A');
    assert_eq!(term.get_cell(0, 1).map(|c| c.char()).unwrap_or('\0'), 'C');
    assert_eq!(term.get_cell(0, 2).map(|c| c.char()).unwrap_or('\0'), 'D');
    assert_eq!(term.get_cell(0, 9).map(|c| c.char()).unwrap_or('\0'), ' ');
}

// ─────────────────────────────────────────────────────────────────────────────
// DECCRA (CSI Pt;Pl;Pb;Pr;Pp;Pt2;Pl2;Pp2 $ v) — Copy Rectangular Area
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_deccra_copies_rectangle_to_destination() {
    let mut term = TerminalCore::new(10, 20);
    // Write "XY" at row 0, cols 0-1
    term.advance(b"\x1b[1;1HXY");
    // Copy 1x2 rectangle (row 1, cols 1-2) to (row 3, col 5)
    // Source: row 1 (1-indexed), col 1-2, dst: row 3, col 5
    term.advance(b"\x1b[1;1;1;2;0;3;5 v"); // DECCRA: src=row1,col1-2 dst=row3,col5

    // Wait — '$' intermediate, not ' '. Let me fix: CSI Pt;Pl;Pb;Pr;Pp;Pt2;Pl2;Pp2 $ v
    // Try: ESC [ 1 ; 1 ; 1 ; 2 ; 0 ; 3 ; 5 $ v
    term.advance(b"\x1b[1;1HXYXYXYXY"); // refresh source
    term.advance(b"\x1b[1;1;1;2;0;3;5$v"); // DECCRA
    assert_eq!(term.get_cell(2, 4).map(|c| c.char()).unwrap_or('\0'), 'X',
        "DECCRA: dst cell must be X");
}

#[test]
fn test_deccra_does_not_panic_out_of_bounds() {
    let mut term = TerminalCore::new(5, 10);
    term.advance(b"\x1b[1;1;999;999;0;1;1$v"); // huge source rect
    assert!(term.cursor_row() < 5);
}

// ─────────────────────────────────────────────────────────────────────────────
// DECNKM (mode 66) — aliases to app_keypad
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_decnkm_sets_app_keypad() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?66h"); // DECNKM set = app keypad mode
    assert!(term.dec_modes().app_keypad, "DECNKM set must enable app_keypad");
    term.advance(b"\x1b[?66l"); // DECNKM reset = numeric keypad
    assert!(!term.dec_modes().app_keypad, "DECNKM reset must disable app_keypad");
}

// ─────────────────────────────────────────────────────────────────────────────
// IRM (mode 4) — Insert/Replace Mode
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_irm_inserts_ascii_chars() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[1;1HABCDE");        // write ABCDE
    term.advance(b"\x1b[1;3H");             // cursor to col 2 (0-indexed)
    term.advance(b"\x1b[4h");              // IRM on
    term.advance(b"X");                    // insert X at col 2 → A B X C D (E pushed off)
    assert_eq!(term.get_cell(0, 0).map(|c| c.char()).unwrap_or('\0'), 'A');
    assert_eq!(term.get_cell(0, 1).map(|c| c.char()).unwrap_or('\0'), 'B');
    assert_eq!(term.get_cell(0, 2).map(|c| c.char()).unwrap_or('\0'), 'X');
    assert_eq!(term.get_cell(0, 3).map(|c| c.char()).unwrap_or('\0'), 'C');
}

#[test]
fn test_irm_reset_restores_replace_mode() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[1;1HABCDE");
    term.advance(b"\x1b[4h\x1b[4l"); // IRM on then off
    term.advance(b"\x1b[1;3H");
    term.advance(b"X");               // Replace mode: X overwrites C
    assert_eq!(term.get_cell(0, 2).map(|c| c.char()).unwrap_or('\0'), 'X');
    assert_eq!(term.get_cell(0, 3).map(|c| c.char()).unwrap_or('\0'), 'D');
}

// ─────────────────────────────────────────────────────────────────────────────
// LNM (mode 20) — Linefeed/Newline Mode
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_lnm_makes_lf_also_cr() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[20h");  // LNM on
    term.advance(b"\x1b[1;5H"); // cursor to col 4 (0-indexed)
    term.advance(b"\n");        // LF with LNM: should also do CR
    // Cursor should now be at col 0 (CR happened) and row 1
    assert_eq!(term.cursor_col(), 0, "LNM: LF must also do CR");
    assert_eq!(term.cursor_row(), 1);
}

// ─────────────────────────────────────────────────────────────────────────────
// CHT (CSI Ps I) / CBT (CSI Ps Z) — Tab forward/backward
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_cht_moves_to_next_tab_stop() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[1;1H"); // cursor to col 0
    term.advance(b"\x1b[1I");   // CHT 1: advance to next tab stop (col 8)
    assert_eq!(term.cursor_col(), 8, "CHT must advance to col 8");
}

#[test]
fn test_cht_n2_jumps_two_tab_stops() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[1;1H"); // cursor to col 0
    term.advance(b"\x1b[2I");   // CHT 2: advance two tab stops (col 16)
    assert_eq!(term.cursor_col(), 16, "CHT 2 must advance to col 16");
}

#[test]
fn test_cbt_moves_to_prev_tab_stop() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[1;20H"); // cursor to col 19 (0-indexed)
    term.advance(b"\x1b[1Z");    // CBT 1: back to col 16
    assert_eq!(term.cursor_col(), 16, "CBT must move back to col 16");
}

#[test]
fn test_cbt_at_col0_is_noop() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[1;1H"); // cursor at col 0
    term.advance(b"\x1b[1Z");   // CBT at col 0: must stay at 0
    assert_eq!(term.cursor_col(), 0, "CBT at col 0 must stay at 0");
}

// ─────────────────────────────────────────────────────────────────────────────
// HPR (CSI Ps a) / VPR (CSI Ps e) / HPA (CSI Ps `)
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_hpr_moves_cursor_right() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[1;5H"); // col 4
    term.advance(b"\x1b[3a");   // HPR 3: col 7
    assert_eq!(term.cursor_col(), 7);
}

#[test]
fn test_vpr_moves_cursor_down() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[3;1H"); // row 2
    term.advance(b"\x1b[2e");   // VPR 2: row 4
    assert_eq!(term.cursor_row(), 4);
}

#[test]
fn test_hpa_positions_cursor_absolutely() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[1;10H"); // col 9
    term.advance(b"\x1b[5`");    // HPA 5 (1-indexed): col 4
    assert_eq!(term.cursor_col(), 4);
}

// ─────────────────────────────────────────────────────────────────────────────
// XTGETTCAP — extended capability queries
// ─────────────────────────────────────────────────────────────────────────────

fn hex_encode_str(s: &[u8]) -> String {
    s.iter().map(|b| format!("{b:02x}")).collect()
}

#[test]
fn test_xtgettcap_smulx_returns_extended_underline() {
    let mut term = TerminalCore::new(24, 80);
    // DCS + q <hex("Smulx")> ST
    let cap_hex = hex_encode_str(b"Smulx");
    let seq = format!("\x1bP+q{cap_hex}\x1b\\");
    term.advance(seq.as_bytes());
    let responses = term.pending_responses();
    assert!(!responses.is_empty(), "Smulx query must produce a response");
    let resp = String::from_utf8_lossy(responses[0].as_slice()).to_string();
    assert!(resp.contains("1+r"), "Smulx response must be DCS 1+r (known)");
}

include!("integration_sequences_part2b.rs");
