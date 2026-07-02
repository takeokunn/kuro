use super::*;

/// BEL (0x07) should set `meta.bell_pending`.
#[test]
fn test_execute_bel_sets_bell_pending() {
    let mut term = TerminalCore::new(24, 80);
    assert!(
        !term.meta.bell_pending,
        "bell_pending should default to false"
    );
    term.advance(&[0x07]);
    assert!(
        term.meta.bell_pending,
        "BEL (0x07) must set meta.bell_pending"
    );
}

/// DA1 (CSI c or CSI 0 c) must queue a response starting with `\x1b[?`.
#[test]
fn test_csi_da1_queues_response() {
    let term = term_with!(b"\x1b[c");
    assert_response_starts!(term, b"\x1b[?");
}

/// DA1 must advertise Sixel graphics (attribute 4) so capable apps emit Sixel.
#[test]
fn test_csi_da1_advertises_sixel() {
    let term = term_with!(b"\x1b[c");
    assert_single_pending_response_bytes(&term, b"\x1b[?1;2;4c");
}

/// DA1 with an explicit 0 parameter (CSI 0 c) must reply identically to CSI c.
#[test]
fn test_csi_da1_zero_param_same_as_bare() {
    let term = term_with!(b"\x1b[0c");
    assert_single_pending_response_bytes(&term, b"\x1b[?1;2;4c");
}

/// DA2 (CSI > c) must queue a secondary device attribute response.
#[test]
fn test_csi_da2_queues_response() {
    let term = term_with!(b"\x1b[>c");
    assert_response_starts!(term, b"\x1b[>");
}

/// XTVERSION (CSI > q) must queue a DCS response containing the terminal name.
#[test]
fn test_csi_xtversion_queues_response() {
    let term = term_with!(b"\x1b[>q");
    assert_response_starts!(term, b"\x1bP>|");
    let resp = String::from_utf8_lossy(first_pending_response_bytes(&term));
    assert!(
        resp.contains("kuro"),
        "XTVERSION response must contain 'kuro', got: {resp:?}"
    );
}

/// DECSTR (CSI ! p) must perform a soft terminal reset without panicking.
#[test]
fn test_csi_decstr_soft_reset() {
    let mut term = term_with!(b"\x1b[1;31m"); // bold + red foreground
    term.advance(b"Hello");
    term.advance(b"\x1b[!p"); // DECSTR
    assert_cell_char!(term, row 0, col 0, 'H');
    term.advance(b"X");
    assert!(
        term.screen.cursor().col > 0 || term.screen.cursor().row > 0,
        "cursor must advance after printing following DECSTR"
    );
}

/// ANSI SCP (CSI s) saves the cursor; ANSI RCP (CSI u) restores it.
#[test]
fn test_csi_scp_rcp_save_restore_cursor() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[8;15H"); // row 7, col 14 (1-indexed)
    let saved_row = term.screen.cursor().row;
    let saved_col = term.screen.cursor().col;

    term.advance(b"\x1b[s"); // ANSI SCP
    term.advance(b"\x1b[1;1H");
    assert_cursor!(term, row 0, col 0);

    term.advance(b"\x1b[u"); // ANSI RCP
    assert_eq!(
        term.screen.cursor().row,
        saved_row,
        "RCP must restore saved row"
    );
    assert_eq!(
        term.screen.cursor().col,
        saved_col,
        "RCP must restore saved col"
    );
}

/// A combining character received at origin (0,0) — no previous cell.
/// Must not panic; terminal should remain usable.
#[test]
fn test_print_combining_at_origin_no_panic() {
    let mut term = TerminalCore::new(24, 80);
    assert_cursor!(term, row 0, col 0);
    term.advance("\u{0301}".as_bytes());
    term.advance(b"A");
    assert!(
        term.screen.cursor().col > 0,
        "cursor must advance after printing a normal char post-combining"
    );
}

// ── New tests covering previously untested handlers ────────────────────────

/// DSR (CSI 6 n) must queue a cursor-position report as `ESC [ row ; col R`.
#[test]
fn test_csi_dsr_queues_cursor_position() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[5;10H"); // cursor to row 4, col 9 (0-indexed)
    term.advance(b"\x1b[6n"); // DSR — cursor position report
    assert_response_starts!(term, b"\x1b[");
    let resp = String::from_utf8_lossy(first_pending_response_bytes(&term));
    // Response must contain "5;10R" (1-indexed)
    assert!(
        resp.contains("5;10R"),
        "DSR response must encode cursor as 1-indexed row;col, got: {resp:?}"
    );
}

/// DSR with a parameter other than 5 / 6 must be silently ignored.
#[test]
fn test_csi_dsr_unknown_param_no_response() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[99n"); // param 99 — not a recognised DSR code
    assert_no_pending_responses(&term);
}

/// DSR 5 (operating status) must reply ESC[0n ("terminal OK").
#[test]
fn test_csi_dsr_operating_status_ok() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[5n");
    assert_single_pending_response_bytes(&term, b"\x1b[0n");
}

/// TBC (CSI 0 g) — clear tab stop at cursor column.
/// After clearing, HT from column 0 must jump to the *next* remaining stop.
#[test]
fn test_csi_tbc_clears_tab_stop_at_cursor() {
    let mut term = TerminalCore::new(24, 80);
    // Default tab stops are at columns 8, 16, 24, …
    // HT from col 0 should normally land on col 8.
    term.advance(b"\x1b[9G"); // move to col 8 (1-indexed)
    assert_eq!(term.screen.cursor().col, 8);
    term.advance(b"\x1b[0g"); // TBC: clear tab stop at col 8
    term.advance(b"\r"); // back to col 0

    // HT must now skip col 8 and land on col 16 (next default stop)
    term.advance(b"\t");
    assert_ne!(
        term.screen.cursor().col,
        8,
        "TBC should have cleared the tab stop at col 8"
    );
}

/// TBC (CSI 3 g) — reset ALL tab stops to defaults.
/// User-set stops are removed; the standard every-8-column stops remain.
/// After TBC 3, HT from col 0 must still land on col 8 (default stop restored).
#[test]
fn test_csi_tbc_clears_user_tab_stops() {
    let mut term = TerminalCore::new(24, 80);
    // Set a custom stop at col 5 (between defaults at 0 and 8)
    term.advance(b"\x1b[6G"); // cursor to col 5
    term.advance(b"\x1bH"); // HTS: set stop at col 5
    term.advance(b"\r");

    // Verify custom stop is active: HT from col 0 lands on col 5
    term.advance(b"\t");
    assert_eq!(
        term.screen.cursor().col,
        5,
        "custom stop at col 5 must be active"
    );

    // TBC 3: reset all stops to defaults (removes custom stops)
    term.advance(b"\x1b[3g");
    term.advance(b"\r");

    // HT from col 0 must now land on col 8 (default), not col 5 (user stop removed)
    term.advance(b"\t");
    assert_eq!(
        term.screen.cursor().col,
        8,
        "TBC 3 must remove user-set stops, leaving only default stops at 8, 16, …"
    );
}

/// SGR italic (CSI 3 m) must set the ITALIC flag.
#[test]
fn test_vte_sgr_italic() {
    assert_sgr_flag!(b"\x1b[3m", SgrFlags::ITALIC, "SGR 3 must set ITALIC flag");
}

/// SGR underline (CSI 4 m) must set the underline style to a non-None value.
#[test]
fn test_vte_sgr_underline() {
    let term = term_with!(b"\x1b[4m");
    assert!(
        term.current_attrs.underline(),
        "SGR 4 must set underline style"
    );
}

/// SGR blink (CSI 5 m) must set the BLINK_SLOW flag.
#[test]
fn test_vte_sgr_blink() {
    assert_sgr_flag!(
        b"\x1b[5m",
        SgrFlags::BLINK_SLOW,
        "SGR 5 must set BLINK_SLOW flag"
    );
}

/// SGR reverse (CSI 7 m) must set the INVERSE flag.
#[test]
fn test_vte_sgr_reverse() {
    assert_sgr_flag!(b"\x1b[7m", SgrFlags::INVERSE, "SGR 7 must set INVERSE flag");
}

/// SGR strikethrough (CSI 9 m) must set the STRIKETHROUGH flag.
#[test]
fn test_vte_sgr_strikethrough() {
    assert_sgr_flag!(
        b"\x1b[9m",
        SgrFlags::STRIKETHROUGH,
        "SGR 9 must set STRIKETHROUGH flag"
    );
}

/// SGR reset (CSI 0 m) must clear all attribute flags set earlier.
#[test]
fn test_vte_sgr_reset_clears_all_flags() {
    let mut term = term_with!(b"\x1b[1;3;4;5;7;9m"); // all flags on
    assert!(term.current_attrs.flags.contains(SgrFlags::BOLD));
    term.advance(b"\x1b[0m");
    assert!(
        term.current_attrs.flags.is_empty(),
        "SGR 0 must clear all SGR flags"
    );
}

/// ICH (CSI @ — Insert Character) shifts characters right; cursor stays.
#[test]
fn test_csi_ich_inserts_blank_at_cursor() {
    let mut term = term_with!(b"ABCD");
    term.advance(b"\x1b[1;3H"); // cursor to (row 0, col 2)
    term.advance(b"\x1b[1@"); // ICH 1: insert 1 blank at col 2
                              // 'A' and 'B' remain; col 2 is now blank; 'C' shifts to col 3
    assert_cell_char!(term, row 0, col 0, 'A');
    assert_cell_char!(term, row 0, col 1, 'B');
    assert_cell_char!(term, row 0, col 2, ' ');
    assert_cell_char!(term, row 0, col 3, 'C');
}

/// DCH (CSI P — Delete Character) removes characters; cursor stays.
#[test]
fn test_csi_dch_deletes_char_at_cursor() {
    let mut term = term_with!(b"ABCD");
    term.advance(b"\x1b[1;2H"); // cursor to col 1
    term.advance(b"\x1b[1P"); // DCH 1: delete 'B'
                              // 'A' remains; 'C' shifts to col 1; 'D' to col 2; col 3 is blank
    assert_cell_char!(term, row 0, col 0, 'A');
    assert_cell_char!(term, row 0, col 1, 'C');
    assert_cell_char!(term, row 0, col 2, 'D');
    assert_cell_char!(term, row 0, col 3, ' ');
}

/// ECH (CSI X — Erase Character) blanks N cells without moving cursor.
#[test]
fn test_csi_ech_erases_without_moving_cursor() {
    let mut term = term_with!(b"ABCDE");
    term.advance(b"\x1b[1;2H"); // cursor to col 1
    let col_before = term.screen.cursor().col;
    term.advance(b"\x1b[2X"); // ECH 2: erase 2 chars from col 1
                              // Col 0 unchanged; cols 1-2 blank; col 3 onward unchanged
    assert_cell_char!(term, row 0, col 0, 'A');
    assert_cell_char!(term, row 0, col 1, ' ');
    assert_cell_char!(term, row 0, col 2, ' ');
    assert_cell_char!(term, row 0, col 3, 'D');
    assert_eq!(
        term.screen.cursor().col,
        col_before,
        "ECH must not move cursor"
    );
}

// ── XTMODKEYS (CSI > type ; value m) ─────────────────────────────────────────

/// XTMODKEYS type=4, value=2: sets modify_other_keys to 2 (level 2 extended).
#[test]
fn test_xtmodkeys_type4_value2_sets_level2() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[>4;2m");
    assert_eq!(
        term.dec_modes.modify_other_keys, 2,
        "XTMODKEYS 4;2 must set modify_other_keys to 2"
    );
}

/// XTMODKEYS type=4, value=1: sets modify_other_keys to 1 (level 1).
#[test]
fn test_xtmodkeys_type4_value1_sets_level1() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[>4;1m");
    assert_eq!(
        term.dec_modes.modify_other_keys, 1,
        "XTMODKEYS 4;1 must set modify_other_keys to 1"
    );
}

/// XTMODKEYS type=4, value=0: resets modify_other_keys to 0 (disabled).
#[test]
fn test_xtmodkeys_type4_value0_disables() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[>4;2m"); // set level 2 first
    term.advance(b"\x1b[>4;0m"); // then reset to 0
    assert_eq!(
        term.dec_modes.modify_other_keys, 0,
        "XTMODKEYS 4;0 must reset modify_other_keys to 0"
    );
}

/// XTMODKEYS with a value > 2 is invalid and must not change state.
#[test]
fn test_xtmodkeys_type4_invalid_value_is_noop() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.dec_modes.modify_other_keys = 1;
    term.advance(b"\x1b[>4;99m");
    assert_eq!(
        term.dec_modes.modify_other_keys, 1,
        "XTMODKEYS value > 2 must not change modify_other_keys"
    );
}

/// XTMODKEYS with a non-4 type is silently ignored (modify_other_keys unchanged).
#[test]
fn test_xtmodkeys_non_type4_is_noop() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.dec_modes.modify_other_keys = 1; // pre-set to 1
    term.advance(b"\x1b[>2;2m"); // type=2, not 4 — must be a no-op
    assert_eq!(
        term.dec_modes.modify_other_keys, 1,
        "XTMODKEYS type != 4 must not change modify_other_keys"
    );
}

/// XTMODKEYS with omitted params (bare CSI > m) defaults to type=0, which is not type 4 — noop.
#[test]
fn test_xtmodkeys_omitted_params_is_noop() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.dec_modes.modify_other_keys = 2;
    term.advance(b"\x1b[>m"); // no params — both type and value default to 0
    assert_eq!(
        term.dec_modes.modify_other_keys, 2,
        "XTMODKEYS with no params (type=0) must not change modify_other_keys"
    );
}
