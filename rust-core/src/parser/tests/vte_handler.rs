//! Property-based and example-based tests for `vte_handler` parsing.
//!
//! Module under test: `parser/vte_handler.rs`
//! Tier: T3 — `ProptestConfig::with_cases(256)`

use crate::types::cell::SgrFlags;
use crate::TerminalCore;

// ── Local test-only macros ─────────────────────────────────────────────────

/// Create a standard 24×80 `TerminalCore` pre-fed with `$bytes`.
///
/// ```
/// let term = term_with!(b"Hello");
/// ```
macro_rules! term_with {
    ($bytes:expr) => {{
        let mut _t = crate::TerminalCore::new(24, 80);
        _t.advance($bytes);
        _t
    }};
}

/// Assert a single cell's character value.
///
/// ```
/// assert_cell_char!(term, row 0, col 2, 'l');
/// ```
macro_rules! assert_cell_char {
    ($term:expr, row $r:expr, col $c:expr, $ch:expr) => {{
        assert_eq!(
            $term.screen.get_cell($r, $c).unwrap().char(),
            $ch,
            "cell ({}, {}) expected {:?}",
            $r,
            $c,
            $ch
        );
    }};
}

/// Assert the cursor is at an exact (row, col) position.
///
/// ```
/// assert_cursor!(term, row 4, col 0);
/// ```
macro_rules! assert_cursor {
    ($term:expr, row $r:expr, col $c:expr) => {{
        assert_eq!(
            $term.screen.cursor().row,
            $r,
            "cursor row: expected {}, got {}",
            $r,
            $term.screen.cursor().row
        );
        assert_eq!(
            $term.screen.cursor().col,
            $c,
            "cursor col: expected {}, got {}",
            $c,
            $term.screen.cursor().col
        );
    }};
}

/// Assert `meta.pending_responses` is non-empty and that the first entry
/// starts with `$prefix` (as a byte slice).
///
/// ```
/// assert_response_starts!(term, b"\x1b[?");
/// ```
macro_rules! assert_response_starts {
    ($term:expr, $prefix:expr) => {{
        assert!(
            !$term.meta.pending_responses.is_empty(),
            "expected at least one queued response, got none"
        );
        assert!(
            $term.meta.pending_responses[0].starts_with($prefix),
            "response should start with {:?}, got {:?}",
            $prefix,
            &$term.meta.pending_responses[0]
        );
    }};
}

/// Assert that an SGR sequence sets a specific flag bit in `current_attrs`.
///
/// ```
/// assert_sgr_flag!(b"\x1b[3m", SgrFlags::ITALIC, "SGR 3 must set ITALIC");
/// ```
macro_rules! assert_sgr_flag {
    ($seq:expr, $flag:expr, $msg:expr) => {{
        let _t = term_with!($seq);
        assert!(_t.current_attrs.flags.contains($flag), "{}", $msg);
    }};
}

/// Assert that a C0 control byte advances the cursor row by exactly `$delta` rows,
/// leaving the cursor within valid bounds.
///
/// Used for LF/VT/FF (0x0A–0x0C) which all act as line feeds.
///
/// ```
/// assert_c0_linefeed!(0x0A, 1, "LF");
/// ```
macro_rules! assert_c0_linefeed {
    ($byte:expr, $delta:expr, $label:expr) => {{
        let mut _t = crate::TerminalCore::new(24, 80);
        let _row_before = _t.screen.cursor.row;
        _t.advance(&[$byte]);
        assert_eq!(
            _t.screen.cursor.row,
            _row_before + $delta,
            "{} (0x{:02x}) must advance cursor row by {}",
            $label,
            $byte,
            $delta
        );
    }};
}

/// Generate a test asserting that `$seq` does NOT produce any pending response.
///
/// ```
/// assert_no_response!(test_so_no_response, b"\x0e");
/// ```
macro_rules! assert_no_response {
    ($name:ident, $seq:expr) => {
        #[test]
        fn $name() {
            let _t = term_with!($seq);
            assert!(
                _t.meta.pending_responses.is_empty(),
                "sequence {:?} must not queue any response",
                $seq
            );
        }
    };
}

// ── Tests ──────────────────────────────────────────────────────────────────

#[test]
fn test_vte_print() {
    let term = term_with!(b"Hello");

    assert_cell_char!(term, row 0, col 0, 'H');
    assert_cell_char!(term, row 0, col 1, 'e');
    assert_cell_char!(term, row 0, col 2, 'l');
    assert_cell_char!(term, row 0, col 3, 'l');
    assert_cell_char!(term, row 0, col 4, 'o');
}

#[test]
fn test_vte_sgr_bold() {
    let term = term_with!(b"\x1b[1mBold");
    assert!(term.current_attrs.flags.contains(SgrFlags::BOLD));
}

#[test]
fn test_vte_cursor_movement() {
    let term = term_with!(b"ABC\x1b[2D");
    // Should move back 2 columns
    assert_cursor!(term, row 0, col 1);
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
    let mut term = term_with!(b"Hello");
    assert!(
        term.screen.cursor.col > 0,
        "cursor should be past col 0 after printing"
    );
    term.advance(&b"\r"[..]);
    assert_cursor!(term, row 0, col 0);
}

/// BS (0x08) at column 0 should not underflow — cursor stays at 0.
#[test]
fn test_execute_bs_at_start() {
    let mut term = TerminalCore::new(24, 80);
    assert_eq!(term.screen.cursor.col, 0);
    term.advance(&b"\x08"[..]);
    assert_cursor!(term, row 0, col 0);
}

/// HT (0x09) should move cursor right by at least one column to the next tab stop.
#[test]
fn test_execute_tab() {
    let mut term = TerminalCore::new(24, 80);
    let col_before = term.screen.cursor.col;
    term.advance(&b"\t"[..]);
    assert!(
        term.screen.cursor.col > col_before,
        "HT should move cursor right by at least 1 column"
    );
}

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
    term.advance(b"\x1b[5;10H"); // row 4, col 9 (1-indexed → 0-indexed)
    let saved_row = term.screen.cursor().row;
    let saved_col = term.screen.cursor().col;

    term.advance(b"\x1b7"); // DECSC
    term.advance(b"\x1b[1;1H"); // move away
    assert_cursor!(term, row 0, col 0);

    term.advance(b"\x1b8"); // DECRC
    assert_eq!(
        term.screen.cursor().row,
        saved_row,
        "DECRC should restore saved row"
    );
    assert_eq!(
        term.screen.cursor().col,
        saved_col,
        "DECRC should restore saved col"
    );
}

/// ESC H (HTS) sets a tab stop at the current column; a subsequent HT
/// from column 0 should land on that column.
#[test]
fn test_esc_hts_sets_tab_stop() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[6G"); // cursor to col 5 (1-indexed)
    assert_eq!(term.screen.cursor().col, 5);

    term.advance(b"\x1bH"); // HTS: set tab stop at col 5
    term.advance(b"\r"); // back to col 0
    assert_eq!(term.screen.cursor().col, 0);

    term.advance(b"\t"); // HT should jump to col 5
    assert_eq!(
        term.screen.cursor().col,
        5,
        "ESC H should set a tab stop at the cursor column"
    );
}

/// OSC 0 sets the window title.
#[test]
fn test_osc_dispatch_osc0_sets_title() {
    let term = term_with!(b"\x1b]0;MyTitle\x07");
    assert_eq!(
        term.meta.title, "MyTitle",
        "OSC 0 should set the window title"
    );
    assert!(term.meta.title_dirty, "title_dirty flag should be set");
}

/// OSC 2 also sets the window title.
#[test]
fn test_osc_dispatch_osc2_sets_title() {
    let term = term_with!(b"\x1b]2;AnotherTitle\x07");
    assert_eq!(term.meta.title, "AnotherTitle");
}

/// Unknown DCS should be accepted without panicking.
#[test]
fn test_hook_put_unhook_unknown_dcs_no_panic() {
    let mut term = term_with!(b"\x1bPhello\x1b\\");
    term.advance(b"ok");
    assert_cell_char!(term, row 0, col 0, 'o');
    assert_cell_char!(term, row 0, col 1, 'k');
}

/// DCS + q (XTGETTCAP) for the "TN" capability should queue a response.
#[test]
fn test_hook_put_unhook_xtgettcap_tn_queues_response() {
    let term = term_with!(b"\x1bP+q544e\x1b\\");
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
    let mut term = term_with!(b"A");
    let col_after_base = term.screen.cursor().col;
    term.advance("\u{0301}".as_bytes()); // U+0301 COMBINING ACUTE ACCENT
    assert_eq!(
        term.screen.cursor().col,
        col_after_base,
        "combining character must not advance the cursor"
    );
}

/// VS16 (U+FE0F) after a base character should combine into the previous cell.
#[test]
fn test_variation_selector_16_combines() {
    use crate::types::cell::CellWidth;

    let term = term_with!("❤\u{FE0F}".as_bytes());

    let cell = term.screen.get_cell(0, 0).unwrap();
    assert_eq!(
        cell.grapheme(),
        "❤\u{FE0F}",
        "VS16 should be combined into the previous cell's grapheme"
    );
    assert_eq!(
        cell.width,
        CellWidth::Half,
        "base char ❤ is width 1, so cell should be Half"
    );
    assert_eq!(
        term.screen.cursor().col,
        1,
        "VS16 must not advance the cursor"
    );
}

/// VS15 (U+FE0E) after a base character should combine into the previous cell.
#[test]
fn test_variation_selector_15_combines() {
    let term = term_with!("A\u{FE0E}".as_bytes());

    let cell = term.screen.get_cell(0, 0).unwrap();
    assert_eq!(
        cell.grapheme(),
        "A\u{FE0E}",
        "VS15 should be combined into the previous cell's grapheme"
    );
    assert_eq!(
        term.screen.cursor().col,
        1,
        "VS15 must not advance the cursor"
    );
}

/// Wide emoji (U+1F525 🔥) should occupy two cells.
#[test]
fn test_standalone_emoji_still_wide() {
    use crate::types::cell::CellWidth;

    let term = term_with!("🔥".as_bytes());

    let cell = term.screen.get_cell(0, 0).unwrap();
    assert_eq!(cell.char(), '🔥');
    assert_eq!(
        cell.width,
        CellWidth::Full,
        "wide emoji should be CellWidth::Full"
    );
    let placeholder = term.screen.get_cell(0, 1).unwrap();
    assert_eq!(
        placeholder.width,
        CellWidth::Wide,
        "second cell of wide emoji should be CellWidth::Wide placeholder"
    );
    assert_eq!(
        term.screen.cursor().col,
        2,
        "wide emoji should advance cursor by 2"
    );
}

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
    let resp = String::from_utf8_lossy(&term.meta.pending_responses[0]);
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
    let resp = String::from_utf8_lossy(&term.meta.pending_responses[0]);
    // Response must contain "5;10R" (1-indexed)
    assert!(
        resp.contains("5;10R"),
        "DSR response must encode cursor as 1-indexed row;col, got: {resp:?}"
    );
}

/// DSR with a parameter other than 6 must be silently ignored.
#[test]
fn test_csi_dsr_unknown_param_no_response() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[5n"); // param 5 — not a recognised DSR code
    assert!(
        term.meta.pending_responses.is_empty(),
        "DSR with unknown param must not queue a response"
    );
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

// ── New tests: ESC sequences not yet covered ───────────────────────────────

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
// Kuro does not implement charset switching; they should be silently ignored
// without panicking and without generating any response.
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
    assert_sgr_flag!(
        b"\x1b[8m",
        SgrFlags::HIDDEN,
        "SGR 8 must set HIDDEN flag"
    );
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

use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    // PANIC SAFETY: print() with any printable Unicode character never panics
    fn prop_print_any_char_no_panic(c in proptest::char::range('\u{0020}', '\u{FFFE}')) {
        let mut term = crate::TerminalCore::new(24, 80);
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
