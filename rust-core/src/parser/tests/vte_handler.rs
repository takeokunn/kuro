//! Property-based and example-based tests for `vte_handler` parsing.
//!
//! Module under test: `parser/vte_handler.rs`
//! Tier: T3 — `ProptestConfig::with_cases(256)`

use crate::types::cell::SgrFlags;
use crate::TerminalCore;

#[test]
fn test_vte_print() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(&b"Hello"[..]);

    assert_eq!(term.screen.get_cell(0, 0).unwrap().char(), 'H');
    assert_eq!(term.screen.get_cell(0, 1).unwrap().char(), 'e');
    assert_eq!(term.screen.get_cell(0, 2).unwrap().char(), 'l');
    assert_eq!(term.screen.get_cell(0, 3).unwrap().char(), 'l');
    assert_eq!(term.screen.get_cell(0, 4).unwrap().char(), 'o');
}

#[test]
fn test_vte_sgr_bold() {
    let mut term = TerminalCore::new(24, 80);
    // Set bold, print text, then verify bold is active (no reset)
    term.advance(&b"\x1b[1mBold"[..]);

    assert!(term.current_attrs.flags.contains(SgrFlags::BOLD));
}

#[test]
fn test_vte_cursor_movement() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(&b"ABC\x1b[2D"[..]);

    // Should move back 2 columns
    assert_eq!(term.screen.cursor.col, 1);
}

/// LF (0x0A) should advance the cursor to the next row.
#[test]
fn test_execute_lf() {
    let mut term = TerminalCore::new(24, 80);
    let row_before = term.screen.cursor.row;
    term.advance(&b"\n"[..]);
    assert_eq!(
        term.screen.cursor.row,
        row_before + 1,
        "LF should move cursor down one row"
    );
}

/// CR (0x0D) should move the cursor to column 0 of the current row.
#[test]
fn test_execute_cr() {
    let mut term = TerminalCore::new(24, 80);
    // Move cursor to a non-zero column first
    term.advance(&b"Hello"[..]);
    assert!(
        term.screen.cursor.col > 0,
        "cursor should be past col 0 after printing"
    );
    term.advance(&b"\r"[..]);
    assert_eq!(
        term.screen.cursor.col, 0,
        "CR should return cursor to column 0"
    );
}

/// BS (0x08) at column 0 should not underflow — cursor stays at 0.
#[test]
fn test_execute_bs_at_start() {
    let mut term = TerminalCore::new(24, 80);
    // Cursor starts at (0, 0)
    assert_eq!(term.screen.cursor.col, 0);
    term.advance(&b"\x08"[..]);
    assert_eq!(
        term.screen.cursor.col, 0,
        "BS at col 0 should keep cursor at 0"
    );
}

/// HT (0x09) should move cursor right by at least one column to the next tab stop.
#[test]
fn test_execute_tab() {
    let mut term = TerminalCore::new(24, 80);
    // Cursor starts at column 0; default tab stop is at column 8
    let col_before = term.screen.cursor.col;
    term.advance(&b"\t"[..]);
    assert!(
        term.screen.cursor.col > col_before,
        "HT should move cursor right by at least 1 column"
    );
}

// ── New tests ─────────────────────────────────────────────────────────────────

/// VT (0x0B) should advance the cursor down one row, just like LF.
#[test]
fn test_execute_vt() {
    let mut term = TerminalCore::new(24, 80);
    let row_before = term.screen.cursor.row;
    term.advance(&b"\x0b"[..]);
    assert_eq!(
        term.screen.cursor.row,
        row_before + 1,
        "VT (0x0b) should move cursor down one row"
    );
}

/// FF (0x0C) should advance the cursor down one row, just like LF.
#[test]
fn test_execute_ff() {
    let mut term = TerminalCore::new(24, 80);
    let row_before = term.screen.cursor.row;
    term.advance(&b"\x0c"[..]);
    assert_eq!(
        term.screen.cursor.row,
        row_before + 1,
        "FF (0x0c) should move cursor down one row"
    );
}

/// ESC 7 (DECSC) saves cursor position; ESC 8 (DECRC) restores it.
#[test]
fn test_esc_decsc_decrc_save_restore_cursor() {
    let mut term = TerminalCore::new(24, 80);
    // Move cursor to a known position
    term.advance(b"\x1b[5;10H"); // row 4, col 9 (1-indexed → 0-indexed)
    let saved_row = term.screen.cursor().row;
    let saved_col = term.screen.cursor().col;

    // Save cursor with ESC 7
    term.advance(b"\x1b7");

    // Move cursor somewhere else
    term.advance(b"\x1b[1;1H");
    assert_eq!(term.screen.cursor().row, 0);
    assert_eq!(term.screen.cursor().col, 0);

    // Restore cursor with ESC 8
    term.advance(b"\x1b8");
    assert_eq!(
        term.screen.cursor().row, saved_row,
        "DECRC should restore saved row"
    );
    assert_eq!(
        term.screen.cursor().col, saved_col,
        "DECRC should restore saved col"
    );
}

/// ESC H (HTS) sets a tab stop at the current column; a subsequent HT
/// from column 0 should land on that column.
#[test]
fn test_esc_hts_sets_tab_stop() {
    let mut term = TerminalCore::new(24, 80);
    // Move cursor to column 5 (CSI 6 G = column 6, 1-indexed)
    term.advance(b"\x1b[6G");
    assert_eq!(term.screen.cursor().col, 5);

    // Set a tab stop at column 5 with ESC H
    term.advance(b"\x1bH");

    // Return to column 0
    term.advance(b"\r");
    assert_eq!(term.screen.cursor().col, 0);

    // HT should advance to the new stop at column 5 (before the default at 8)
    term.advance(b"\t");
    assert_eq!(
        term.screen.cursor().col, 5,
        "ESC H should set a tab stop at the cursor column"
    );
}

/// OSC 0 sets the window title; verify the title is stored in meta.
#[test]
fn test_osc_dispatch_osc0_sets_title() {
    let mut term = TerminalCore::new(24, 80);
    // OSC 0 ; <title> BEL
    term.advance(b"\x1b]0;MyTitle\x07");
    assert_eq!(
        term.meta.title, "MyTitle",
        "OSC 0 should set the window title"
    );
    assert!(term.meta.title_dirty, "title_dirty flag should be set");
}

/// OSC 2 also sets the window title.
#[test]
fn test_osc_dispatch_osc2_sets_title() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b]2;AnotherTitle\x07");
    assert_eq!(term.meta.title, "AnotherTitle");
}

/// DCS hook + put + unhook: an unknown DCS (not + q or sixel) should
/// be accepted without panicking and leave DCS state idle afterwards.
#[test]
fn test_hook_put_unhook_unknown_dcs_no_panic() {
    let mut term = TerminalCore::new(24, 80);
    // Arbitrary unknown DCS: ESC P <data> ESC backslash
    // The VTE parser fires hook / put / unhook for this.
    term.advance(b"\x1bPhello\x1b\\");
    // No assertion needed beyond "did not panic"; confirm terminal is alive.
    term.advance(b"ok");
    assert_eq!(term.screen.get_cell(0, 0).unwrap().char(), 'o');
    assert_eq!(term.screen.get_cell(0, 1).unwrap().char(), 'k');
}

/// DCS + q (XTGETTCAP) for the "TN" capability should queue a response.
#[test]
fn test_hook_put_unhook_xtgettcap_tn_queues_response() {
    let mut term = TerminalCore::new(24, 80);
    // "TN" hex-encoded = "544e"
    // DCS + q 544e ST
    term.advance(b"\x1bP+q544e\x1b\\");
    assert!(
        !term.meta.pending_responses.is_empty(),
        "XTGETTCAP TN query should queue at least one response"
    );
    let resp = String::from_utf8_lossy(&term.meta.pending_responses[0]);
    assert!(
        resp.contains("544e"),
        "response should echo the capability hex name"
    );
}

/// `print()` with a combining character (zero-width) must NOT advance the cursor.
#[test]
fn test_print_combining_char_does_not_advance_cursor() {
    let mut term = TerminalCore::new(24, 80);
    // Print a base character first so there is a previous cell to attach to.
    term.advance(b"A");
    let col_after_base = term.screen.cursor().col;

    // U+0301 COMBINING ACUTE ACCENT (zero-width, combining)
    let combining = "\u{0301}";
    term.advance(combining.as_bytes());

    assert_eq!(
        term.screen.cursor().col, col_after_base,
        "combining character must not advance the cursor"
    );
}

use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    // PANIC SAFETY: print() with any printable Unicode character never panics
    fn prop_print_any_char_no_panic(c in proptest::char::range('\u{0020}', '\u{FFFE}')) {
        let mut term = crate::TerminalCore::new(24, 80);
        // Send character as UTF-8 bytes
        let mut buf = [0u8; 4];
        let s = c.encode_utf8(&mut buf);
        term.advance(s.as_bytes());
        prop_assert!(term.screen.cursor().row < 24);
    }

    #[test]
    // PANIC SAFETY: C0 control codes (0x00–0x1F) as execute() never panic
    fn prop_execute_c0_no_panic(byte in 0x00u8..=0x1Fu8) {
        let mut term = crate::TerminalCore::new(24, 80);
        term.advance(&[byte]);
        prop_assert!(term.screen.cursor().row < 24);
    }
}
