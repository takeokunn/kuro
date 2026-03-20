//! Property-based and example-based tests for `csi` parsing.
//!
//! Module under test: `parser/csi.rs`
//! Tier: T2 — `ProptestConfig::with_cases(500)`
#![expect(clippy::cast_possible_truncation, reason = "test coordinate casts: rows/cols are terminal dimensions (≤ 65535); usize→u16 is safe")]

use super::*;

#[test]
fn test_vpa_move_cursor() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Start at (0, 0)
    assert_eq!(term.screen.cursor.row, 0);
    assert_eq!(term.screen.cursor.col, 0);

    // Move cursor to row 5 (1-indexed: CSI 5 d)
    term.advance(b"\x1b[5d");

    // Should move to row 4 (0-indexed), column unchanged
    assert_eq!(term.screen.cursor.row, 4);
    assert_eq!(term.screen.cursor.col, 0);
}

#[test]
fn test_vpa_default() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Move cursor to row 10
    term.screen.move_cursor(9, 0);
    assert_eq!(term.screen.cursor.row, 9);

    // VPA with no parameter defaults to row 1
    let params = vte::Params::default();
    csi_vpa(&mut term, &params);

    // Should move to row 0 (1-indexed: 1)
    assert_eq!(term.screen.cursor.row, 0);
}

#[test]
fn test_vpa_bounds() {
    let mut term = crate::TerminalCore::new(10, 80);

    // Try to move beyond screen bounds (CSI 100 d)
    term.advance(b"\x1b[100d");

    // Should clamp to screen boundary (row 9 for 10 rows)
    assert_eq!(term.screen.cursor.row, 9);
}

#[test]
fn test_cha_move_cursor() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Start at (0, 0)
    assert_eq!(term.screen.cursor.row, 0);
    assert_eq!(term.screen.cursor.col, 0);

    // Move cursor to column 20 (1-indexed: CSI 20 G)
    term.advance(b"\x1b[20G");

    // Should move to column 19 (0-indexed), row unchanged
    assert_eq!(term.screen.cursor.row, 0);
    assert_eq!(term.screen.cursor.col, 19);
}

#[test]
fn test_cha_default() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Move cursor to column 30
    term.screen.move_cursor(0, 29);
    assert_eq!(term.screen.cursor.col, 29);

    // CHA with no parameter defaults to column 1
    let params = vte::Params::default();
    csi_cha(&mut term, &params);

    // Should move to column 0 (1-indexed: 1)
    assert_eq!(term.screen.cursor.col, 0);
}

#[test]
fn test_cha_bounds() {
    let mut term = crate::TerminalCore::new(24, 50);

    // Try to move beyond screen bounds (CSI 100 G)
    term.advance(b"\x1b[100G");

    // Should clamp to screen boundary (col 49 for 50 cols)
    assert_eq!(term.screen.cursor.col, 49);
}

#[test]
fn test_hvp_move_cursor() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Start at (0, 0)
    assert_eq!(term.screen.cursor.row, 0);
    assert_eq!(term.screen.cursor.col, 0);

    // Move cursor to (row=10, col=30) (1-indexed: CSI 10;30 f)
    term.advance(b"\x1b[10;30f");

    // Should move to (9, 29) (0-indexed)
    assert_eq!(term.screen.cursor.row, 9);
    assert_eq!(term.screen.cursor.col, 29);
}

#[test]
fn test_hvp_default() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Move cursor to (15, 40)
    term.screen.move_cursor(14, 39);

    // HVP with no parameters defaults to (1, 1)
    let params = vte::Params::default();
    csi_hvp(&mut term, &params);

    // Should move to (0, 0) (1-indexed: 1,1)
    assert_eq!(term.screen.cursor.row, 0);
    assert_eq!(term.screen.cursor.col, 0);
}

#[test]
fn test_hvp_partial_params() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Move cursor to row 5 only (column defaults to 1): CSI 5 f
    term.advance(b"\x1b[5f");

    // Should move to (4, 0) (row=5, col=1 in 1-indexed)
    assert_eq!(term.screen.cursor.row, 4);
    assert_eq!(term.screen.cursor.col, 0);
}

#[test]
fn test_hvp_bounds() {
    let mut term = crate::TerminalCore::new(10, 50);

    // Try to move beyond screen bounds (CSI 100;100 f)
    term.advance(b"\x1b[100;100f");

    // Should clamp to screen boundaries
    assert_eq!(term.screen.cursor.row, 9); // 10 rows max
    assert_eq!(term.screen.cursor.col, 49); // 50 cols max
}

// --- CUU (Cursor Up) tests ---

#[test]
fn test_cuu_move_cursor_up() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Move cursor to row 5 (0-indexed) via CUP: CSI 6;1H (1-indexed)
    term.advance(b"\x1b[6;1H");
    assert_eq!(term.screen.cursor.row, 5);
    assert_eq!(term.screen.cursor.col, 0);

    // CUU 3: move up 3 rows (CSI 3 A)
    term.advance(b"\x1b[3A");

    // Should land at row 2 (0-indexed)
    assert_eq!(term.screen.cursor.row, 2);
    assert_eq!(term.screen.cursor.col, 0);
}

#[test]
fn test_cuu_default() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Move cursor to row 4 (0-indexed)
    term.screen.move_cursor(4, 0);
    assert_eq!(term.screen.cursor.row, 4);

    // CUU with no parameter defaults to 1: CSI A
    let params = vte::Params::default();
    csi_cuu(&mut term, &params);

    // Should move up 1 row to row 3
    assert_eq!(term.screen.cursor.row, 3);
    assert_eq!(term.screen.cursor.col, 0);
}

#[test]
fn test_cuu_clamps_at_top() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Cursor starts at row 0 (top)
    assert_eq!(term.screen.cursor.row, 0);

    // CUU 5 from row 0: should clamp to row 0
    term.advance(b"\x1b[5A");

    assert_eq!(term.screen.cursor.row, 0);
}

// --- CUD (Cursor Down) tests ---

#[test]
fn test_cud_move_cursor_down() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Cursor starts at row 0
    assert_eq!(term.screen.cursor.row, 0);

    // CUD 4: move down 4 rows (CSI 4 B)
    term.advance(b"\x1b[4B");

    // Should land at row 4 (0-indexed)
    assert_eq!(term.screen.cursor.row, 4);
    assert_eq!(term.screen.cursor.col, 0);
}

#[test]
fn test_cud_default() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Move cursor to row 3 (0-indexed)
    term.screen.move_cursor(3, 0);
    assert_eq!(term.screen.cursor.row, 3);

    // CUD with no parameter defaults to 1: CSI B
    let params = vte::Params::default();
    csi_cud(&mut term, &params);

    // Should move down 1 row to row 4
    assert_eq!(term.screen.cursor.row, 4);
    assert_eq!(term.screen.cursor.col, 0);
}

#[test]
fn test_cud_clamps_at_bottom() {
    let mut term = crate::TerminalCore::new(10, 80);

    // Move cursor to last row (row 9, 0-indexed)
    term.screen.move_cursor(9, 0);
    assert_eq!(term.screen.cursor.row, 9);

    // CUD 5 from last row: should clamp to last row
    term.advance(b"\x1b[5B");

    assert_eq!(term.screen.cursor.row, 9);
}

// --- CUF (Cursor Forward / Right) tests ---

#[test]
fn test_cuf_move_cursor_right() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Cursor starts at col 0
    assert_eq!(term.screen.cursor.col, 0);

    // CUF 10: move right 10 columns (CSI 10 C)
    term.advance(b"\x1b[10C");

    // Should land at col 10 (0-indexed)
    assert_eq!(term.screen.cursor.row, 0);
    assert_eq!(term.screen.cursor.col, 10);
}

#[test]
fn test_cuf_default() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Move cursor to col 5 (0-indexed)
    term.screen.move_cursor(0, 5);
    assert_eq!(term.screen.cursor.col, 5);

    // CUF with no parameter defaults to 1: CSI C
    let params = vte::Params::default();
    csi_cuf(&mut term, &params);

    // Should move right 1 column to col 6
    assert_eq!(term.screen.cursor.row, 0);
    assert_eq!(term.screen.cursor.col, 6);
}

#[test]
fn test_cuf_clamps_at_right_margin() {
    let mut term = crate::TerminalCore::new(24, 50);

    // Move cursor to last col (col 49, 0-indexed)
    term.screen.move_cursor(0, 49);
    assert_eq!(term.screen.cursor.col, 49);

    // CUF 5 from last col: should clamp to last col
    term.advance(b"\x1b[5C");

    assert_eq!(term.screen.cursor.col, 49);
}

// --- CUB (Cursor Back / Left) tests ---

#[test]
fn test_cub_move_cursor_left() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Move cursor to col 15 (0-indexed)
    term.screen.move_cursor(0, 15);
    assert_eq!(term.screen.cursor.col, 15);

    // CUB 7: move left 7 columns (CSI 7 D)
    term.advance(b"\x1b[7D");

    // Should land at col 8 (0-indexed)
    assert_eq!(term.screen.cursor.row, 0);
    assert_eq!(term.screen.cursor.col, 8);
}

#[test]
fn test_cub_default() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Move cursor to col 10 (0-indexed)
    term.screen.move_cursor(0, 10);
    assert_eq!(term.screen.cursor.col, 10);

    // CUB with no parameter defaults to 1: CSI D
    let params = vte::Params::default();
    csi_cub(&mut term, &params);

    // Should move left 1 column to col 9
    assert_eq!(term.screen.cursor.row, 0);
    assert_eq!(term.screen.cursor.col, 9);
}

#[test]
fn test_cub_clamps_at_left_margin() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Cursor starts at col 0 (left margin)
    assert_eq!(term.screen.cursor.col, 0);

    // CUB 5 from col 0: should clamp to col 0
    term.advance(b"\x1b[5D");

    assert_eq!(term.screen.cursor.col, 0);
}

// --- CUP (Cursor Position) tests ---

#[test]
fn test_cup_absolute_position() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Start at (0, 0)
    assert_eq!(term.screen.cursor.row, 0);
    assert_eq!(term.screen.cursor.col, 0);

    // CUP to (row=8, col=25) in 1-indexed: CSI 8;25H
    term.advance(b"\x1b[8;25H");

    // Should move to (7, 24) in 0-indexed
    assert_eq!(term.screen.cursor.row, 7);
    assert_eq!(term.screen.cursor.col, 24);
}

#[test]
fn test_cup_default() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Move cursor to an arbitrary position first
    term.screen.move_cursor(10, 30);
    assert_eq!(term.screen.cursor.row, 10);
    assert_eq!(term.screen.cursor.col, 30);

    // CUP with no parameters defaults to (1, 1): CSI H
    term.advance(b"\x1b[H");

    // Should move to (0, 0) in 0-indexed (row=1, col=1 in 1-indexed)
    assert_eq!(term.screen.cursor.row, 0);
    assert_eq!(term.screen.cursor.col, 0);
}

#[test]
fn test_cup_bounds() {
    let mut term = crate::TerminalCore::new(10, 50);

    // CUP beyond screen bounds: CSI 100;100H
    term.advance(b"\x1b[100;100H");

    // Should clamp to screen boundaries
    assert_eq!(term.screen.cursor.row, 9); // 10 rows max
    assert_eq!(term.screen.cursor.col, 49); // 50 cols max
}

// --- CNL (Cursor Next Line) tests ---

#[test]
fn test_cnl_moves_down_and_to_col0() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Position cursor at (row=3, col=15)
    term.screen.move_cursor(3, 15);

    // CNL 2: move down 2 lines, column 0 (CSI 2 E)
    term.advance(b"\x1b[2E");

    assert_eq!(term.screen.cursor.row, 5);
    assert_eq!(term.screen.cursor.col, 0);
}

#[test]
fn test_cnl_default_is_1() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.screen.move_cursor(5, 20);

    // CNL with no param defaults to 1
    term.advance(b"\x1b[E");

    assert_eq!(term.screen.cursor.row, 6);
    assert_eq!(term.screen.cursor.col, 0);
}

// --- CPL (Cursor Previous Line) tests ---

#[test]
fn test_cpl_moves_up_and_to_col0() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Position cursor at (row=10, col=40)
    term.screen.move_cursor(10, 40);

    // CPL 3: move up 3 lines, column 0 (CSI 3 F)
    term.advance(b"\x1b[3F");

    assert_eq!(term.screen.cursor.row, 7);
    assert_eq!(term.screen.cursor.col, 0);
}

#[test]
fn test_cpl_default_is_1() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.screen.move_cursor(5, 20);

    // CPL with no param defaults to 1
    term.advance(b"\x1b[F");

    assert_eq!(term.screen.cursor.row, 4);
    assert_eq!(term.screen.cursor.col, 0);
}

#[test]
fn test_cpl_clamps_at_top() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Move cursor to row 2, col 30
    term.screen.move_cursor(2, 30);

    // CPL 10: would go to row -8, should clamp to row 0 col 0
    term.advance(b"\x1b[10F");

    assert_eq!(term.screen.cursor.row, 0);
    assert_eq!(term.screen.cursor.col, 0);
}

#[test]
fn test_cnl_clamps_at_bottom() {
    let mut term = crate::TerminalCore::new(10, 80);
    // Place cursor on the last row, mid-column
    term.screen.move_cursor(9, 20);

    // CNL 5 from the last row: row should clamp to 9, col should be 0
    term.advance(b"\x1b[5E");

    assert_eq!(term.screen.cursor.row, 9);
    assert_eq!(term.screen.cursor.col, 0);
}

#[test]
fn test_cnl_zero_param_treated_as_1() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.screen.move_cursor(3, 15);

    // CSI 0 E — explicit zero must be clamped to 1 by .max(1)
    term.advance(b"\x1b[0E");

    assert_eq!(term.screen.cursor.row, 4);
    assert_eq!(term.screen.cursor.col, 0);
}

#[test]
fn test_cpl_zero_param_treated_as_1() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.screen.move_cursor(5, 20);

    // CSI 0 F — explicit zero must be clamped to 1 by .max(1)
    term.advance(b"\x1b[0F");

    assert_eq!(term.screen.cursor.row, 4);
    assert_eq!(term.screen.cursor.col, 0);
}

// ── DECSCUSR (Set Cursor Style) tests ────────────────────────────────

#[test]
fn test_decscusr_blinking_block_param0() {
    // CSI 0 SP q → BlinkingBlock
    let mut term = crate::TerminalCore::new(24, 80);
    // First set a non-default shape so the assertion is meaningful
    term.advance(b"\x1b[6 q"); // SteadyBar
    assert_eq!(term.dec_modes.cursor_shape, crate::types::cursor::CursorShape::SteadyBar);
    term.advance(b"\x1b[0 q");
    assert_eq!(
        term.dec_modes.cursor_shape,
        crate::types::cursor::CursorShape::BlinkingBlock,
        "DECSCUSR 0 should set BlinkingBlock"
    );
}

#[test]
fn test_decscusr_blinking_block_param1() {
    // CSI 1 SP q → BlinkingBlock
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[4 q"); // SteadyUnderline first
    term.advance(b"\x1b[1 q");
    assert_eq!(
        term.dec_modes.cursor_shape,
        crate::types::cursor::CursorShape::BlinkingBlock,
        "DECSCUSR 1 should set BlinkingBlock"
    );
}

#[test]
fn test_decscusr_steady_block() {
    // CSI 2 SP q → SteadyBlock
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[2 q");
    assert_eq!(
        term.dec_modes.cursor_shape,
        crate::types::cursor::CursorShape::SteadyBlock,
        "DECSCUSR 2 should set SteadyBlock"
    );
}

#[test]
fn test_decscusr_blinking_underline() {
    // CSI 3 SP q → BlinkingUnderline
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[3 q");
    assert_eq!(
        term.dec_modes.cursor_shape,
        crate::types::cursor::CursorShape::BlinkingUnderline,
        "DECSCUSR 3 should set BlinkingUnderline"
    );
}

#[test]
fn test_decscusr_steady_underline() {
    // CSI 4 SP q → SteadyUnderline
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[4 q");
    assert_eq!(
        term.dec_modes.cursor_shape,
        crate::types::cursor::CursorShape::SteadyUnderline,
        "DECSCUSR 4 should set SteadyUnderline"
    );
}

#[test]
fn test_decscusr_blinking_bar() {
    // CSI 5 SP q → BlinkingBar
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[5 q");
    assert_eq!(
        term.dec_modes.cursor_shape,
        crate::types::cursor::CursorShape::BlinkingBar,
        "DECSCUSR 5 should set BlinkingBar"
    );
}

#[test]
fn test_decscusr_steady_bar() {
    // CSI 6 SP q → SteadyBar
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[6 q");
    assert_eq!(
        term.dec_modes.cursor_shape,
        crate::types::cursor::CursorShape::SteadyBar,
        "DECSCUSR 6 should set SteadyBar"
    );
}

#[test]
fn test_decscusr_unknown_param_defaults_to_blinking_block() {
    // CSI 99 SP q → BlinkingBlock (fallback for unrecognised values)
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[6 q"); // set non-default first
    term.advance(b"\x1b[99 q");
    assert_eq!(
        term.dec_modes.cursor_shape,
        crate::types::cursor::CursorShape::BlinkingBlock,
        "DECSCUSR with unrecognised param should fall back to BlinkingBlock"
    );
}

#[test]
fn test_cpl_nix_progress_pattern() {
    // Simulate the nix progress overwrite pattern:
    // 1. Print 3 progress lines
    // 2. CPL 3 to go back to the first one
    // 3. Overwrite them
    let mut term = crate::TerminalCore::new(24, 80);

    // Print 3 lines of "progress"
    term.advance(b"line1\nline2\nline3\n");
    // Cursor is now at row 3, col 0

    // CPL 3: go back 3 lines to row 0, col 0
    term.advance(b"\x1b[3F");

    assert_eq!(term.screen.cursor.row, 0);
    assert_eq!(term.screen.cursor.col, 0);

    // Overwrite line 1 with new content
    term.advance(b"updated1");
    assert_eq!(term.screen.cursor.row, 0);
    assert_eq!(term.screen.cursor.col, 8);
}

use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(500))]

    #[test]
    // CLAMP: CUP row parameter is clamped to screen bounds
    fn prop_cup_row_clamped(r in 0u16..=500u16) {
        let rows: u16 = 24;
        let mut term = crate::TerminalCore::new(rows, 80);
        term.advance(format!("\x1b[{};1H", r + 1).as_bytes());
        let expected = (r as usize).min((rows - 1) as usize);
        prop_assert_eq!(
            term.screen.cursor.row, expected,
            "CUP row {} must clamp to {}", r, expected
        );
    }

    #[test]
    // CLAMP: CUP col parameter is clamped to screen bounds
    fn prop_cup_col_clamped(c in 0u16..=500u16) {
        let cols: u16 = 80;
        let mut term = crate::TerminalCore::new(24, cols);
        term.advance(format!("\x1b[1;{}H", c + 1).as_bytes());
        let expected = (c as usize).min((cols - 1) as usize);
        prop_assert_eq!(
            term.screen.cursor.col, expected,
            "CUP col {} must clamp to {}", c, expected
        );
    }

    #[test]
    // BOUNDARY: cursor up never moves above row 0
    fn prop_cursor_up_no_overflow(n in 0u16..=300u16) {
        let mut term = crate::TerminalCore::new(24, 80);
        term.screen.move_cursor(0, 0);
        term.advance(format!("\x1b[{n}A").as_bytes());
        prop_assert_eq!(term.screen.cursor.row, 0, "cursor up from row 0 must stay at 0");
    }

    #[test]
    // BOUNDARY: cursor down from last row never exceeds last row
    fn prop_cursor_down_no_overflow(n in 0u16..=300u16) {
        let rows: usize = 24;
        let mut term = crate::TerminalCore::new(rows as u16, 80);
        term.screen.move_cursor(rows - 1, 0);
        term.advance(format!("\x1b[{n}B").as_bytes());
        prop_assert!(
            term.screen.cursor.row < rows,
            "cursor down from last row must not exceed bounds"
        );
    }

    #[test]
    // BOUNDARY: cursor right never exceeds last column
    fn prop_cursor_right_in_bounds(n in 0u16..=300u16) {
        let mut term = crate::TerminalCore::new(24, 80);
        term.advance(format!("\x1b[{n}C").as_bytes());
        prop_assert!(term.screen.cursor.col < 80, "cursor.col must be < 80");
    }

    #[test]
    // BOUNDARY: cursor left from col 0 stays at col 0
    fn prop_cursor_left_in_bounds(n in 0u16..=300u16) {
        let mut term = crate::TerminalCore::new(24, 80);
        term.screen.move_cursor(0, 0);
        term.advance(format!("\x1b[{n}D").as_bytes());
        prop_assert_eq!(term.screen.cursor.col, 0, "cursor left from col 0 must stay at 0");
    }
}
