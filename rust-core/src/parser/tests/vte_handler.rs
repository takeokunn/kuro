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

include!("vte_handler_device_attrs.rs");
include!("vte_handler_esc.rs");
include!("vte_handler_osc.rs");
