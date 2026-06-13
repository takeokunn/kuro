//! Property-based and example-based tests for `csi` parsing.
//!
//! Module under test: `parser/csi.rs`
//! Tier: T2 — `ProptestConfig::with_cases(500)`
#![expect(
    clippy::cast_possible_truncation,
    reason = "test coordinate casts: rows/cols are terminal dimensions (≤ 65535); usize→u16 is safe"
)]

use super::*;

// ── Test helpers ──────────────────────────────────────────────────────────────

/// Construct a fresh `TerminalCore` with the given dimensions.
macro_rules! term {
    ($rows:expr, $cols:expr) => {
        crate::TerminalCore::new($rows, $cols)
    };
}

/// Assert cursor row and column in one expression.
macro_rules! assert_cursor {
    ($term:expr, $row:expr, $col:expr) => {
        assert_eq!($term.screen.cursor.row, $row, "cursor.row mismatch");
        assert_eq!($term.screen.cursor.col, $col, "cursor.col mismatch");
    };
    ($term:expr, row = $row:expr) => {
        assert_eq!($term.screen.cursor.row, $row, "cursor.row mismatch");
    };
    ($term:expr, col = $col:expr) => {
        assert_eq!($term.screen.cursor.col, $col, "cursor.col mismatch");
    };
}

/// Table-driven macro for tests that: (a) create a fresh 24×80 terminal,
/// (b) feed a single CSI byte sequence, and (c) assert the resulting cursor.
///
/// Pattern: `test_name : b"sequence" => (row, col)`
macro_rules! test_cursor_commands {
    ($( $name:ident : $input:expr => ($row:expr, $col:expr) ),+ $(,)?) => {
        $(
            #[test]
            fn $name() {
                let mut term = term!(24, 80);
                term.advance($input);
                assert_cursor!(term, $row, $col);
            }
        )+
    };
}

test_cursor_commands! {
    // VPA: CSI 5 d — row 5 (1-indexed) → row 4 (0-indexed), col unchanged
    test_vpa_move_cursor:        b"\x1b[5d"    => (4,  0),
    // CHA: CSI 20 G — col 20 (1-indexed) → col 19 (0-indexed), row unchanged
    test_cha_move_cursor:        b"\x1b[20G"   => (0, 19),
    // HVP: CSI 10;30 f — (row=10, col=30) 1-indexed → (9, 29) 0-indexed
    test_hvp_move_cursor:        b"\x1b[10;30f" => (9, 29),
    // HVP partial: CSI 5 f — row=5, col defaults to 1 → (4, 0)
    test_hvp_partial_params:     b"\x1b[5f"    => (4,  0),
    // CUP explicit params: CSI 5;10 H → (4, 9) 0-indexed
    test_cup_multi_param_semicolon: b"\x1b[5;10H" => (4, 9),
    // CUD: CSI 4 B — move down 4 from row 0 → row 4
    test_cud_move_cursor_down:   b"\x1b[4B"    => (4,  0),
    // CUF: CSI 10 C — move right 10 from col 0 → col 10
    test_cuf_move_cursor_right:  b"\x1b[10C"   => (0, 10),
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
fn test_hvp_bounds() {
    let mut term = crate::TerminalCore::new(10, 50);

    // Try to move beyond screen bounds (CSI 100;100 f)
    term.advance(b"\x1b[100;100f");

    // Should clamp to screen boundaries
    assert_eq!(term.screen.cursor.row, 9); // 10 rows max
    assert_eq!(term.screen.cursor.col, 49); // 50 cols max
}

// ── Cursor-direction default-parameter macro ──────────────────────────────────

/// Table-driven macro for testing that CSI cursor-movement functions treat an
/// absent parameter identically to an explicit 1.
///
/// Pattern: `test_name : fn_under_test , start (row, col) => expected (row, col)`
macro_rules! test_cursor_default {
    (
        $(
            $name:ident : $fn:ident , ($sr:expr, $sc:expr) => ($er:expr, $ec:expr)
        ),+ $(,)?
    ) => {
        $(
            #[test]
            fn $name() {
                let mut term = term!(24, 80);
                term.screen.move_cursor($sr, $sc);
                let params = vte::Params::default();
                $fn(&mut term, &params);
                assert_cursor!(term, $er, $ec);
            }
        )+
    };
}

test_cursor_default! {
    // CUU default (no param) moves up 1
    test_cuu_default: csi_cuu, (4, 0)  => (3, 0),
    // CUD default (no param) moves down 1
    test_cud_default: csi_cud, (3, 0)  => (4, 0),
    // CUF default (no param) moves right 1
    test_cuf_default: csi_cuf, (0, 5)  => (0, 6),
    // CUB default (no param) moves left 1
    test_cub_default: csi_cub, (0, 10) => (0, 9),
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

// --- HPR (Horizontal Position Relative) tests ---
// HPR (CSI a) is an alias for CUF: moves cursor right by N columns.

#[test]
fn test_hpr_moves_cursor_right() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.screen.move_cursor(5, 10);
    term.advance(b"\x1b[5a"); // HPR 5 — move right 5
    assert_eq!(term.screen.cursor.row, 5);
    assert_eq!(term.screen.cursor.col, 15);
}

#[test]
fn test_hpr_default_is_1() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.screen.move_cursor(0, 20);
    term.advance(b"\x1b[a"); // HPR default (1)
    assert_eq!(term.screen.cursor.col, 21);
}

// --- VPR (Vertical Position Relative) tests ---
// VPR (CSI e) is an alias for CUD: moves cursor down by N rows.

#[test]
fn test_vpr_moves_cursor_down() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.screen.move_cursor(5, 10);
    term.advance(b"\x1b[3e"); // VPR 3 — move down 3
    assert_eq!(term.screen.cursor.row, 8);
    assert_eq!(term.screen.cursor.col, 10);
}

#[test]
fn test_vpr_default_is_1() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.screen.move_cursor(5, 0);
    term.advance(b"\x1b[e"); // VPR default (1)
    assert_eq!(term.screen.cursor.row, 6);
}

include!("csi_cursor_line_clamping.rs");

include!("csi_device_status.rs");

include!("csi_pbt.rs");
