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

/// Table-driven macro for DECSCUSR (CSI Ps SP q) shape tests.
///
/// Pattern: `test_name : b"setup_seq" , b"target_seq" => ShapeVariant , "msg"`
/// The setup sequence moves away from the target so the assertion is meaningful.
macro_rules! test_decscusr {
    (
        $(
            $name:ident : $setup:expr , $target:expr => $shape:ident , $msg:expr
        ),+ $(,)?
    ) => {
        $(
            #[test]
            fn $name() {
                let mut term = crate::TerminalCore::new(24, 80);
                term.advance($setup);
                term.advance($target);
                assert_eq!(
                    term.dec_modes.cursor_shape,
                    crate::types::cursor::CursorShape::$shape,
                    $msg
                );
            }
        )+
    };
}

test_decscusr! {
    // param 0 → BlinkingBlock (0 is alias for 1/default)
    test_decscusr_blinking_block_param0:
        b"\x1b[6 q", b"\x1b[0 q" => BlinkingBlock, "DECSCUSR 0 should set BlinkingBlock",
    // param 1 → BlinkingBlock
    test_decscusr_blinking_block_param1:
        b"\x1b[4 q", b"\x1b[1 q" => BlinkingBlock, "DECSCUSR 1 should set BlinkingBlock",
    // param 2 → SteadyBlock
    test_decscusr_steady_block:
        b"\x1b[5 q", b"\x1b[2 q" => SteadyBlock, "DECSCUSR 2 should set SteadyBlock",
    // param 3 → BlinkingUnderline
    test_decscusr_blinking_underline:
        b"\x1b[2 q", b"\x1b[3 q" => BlinkingUnderline, "DECSCUSR 3 should set BlinkingUnderline",
    // param 4 → SteadyUnderline
    test_decscusr_steady_underline:
        b"\x1b[1 q", b"\x1b[4 q" => SteadyUnderline, "DECSCUSR 4 should set SteadyUnderline",
    // param 5 → BlinkingBar
    test_decscusr_blinking_bar:
        b"\x1b[2 q", b"\x1b[5 q" => BlinkingBar, "DECSCUSR 5 should set BlinkingBar",
    // param 6 → SteadyBar
    test_decscusr_steady_bar:
        b"\x1b[1 q", b"\x1b[6 q" => SteadyBar, "DECSCUSR 6 should set SteadyBar",
    // unknown param → BlinkingBlock fallback
    test_decscusr_unknown_param_defaults_to_blinking_block:
        b"\x1b[6 q", b"\x1b[99 q" => BlinkingBlock,
        "DECSCUSR with unrecognised param should fall back to BlinkingBlock",
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

// ── New tests: multi-param, default-param, boundary ──────────────────────────

#[test]
fn test_cup_default_row_only() {
    // CSI ;5H — row omitted (defaults to 1), col=5 → (0,4)
    let mut term = term!(24, 80);
    term.screen.move_cursor(10, 30);
    term.advance(b"\x1b[;5H");
    assert_cursor!(term, 0, 4);
}

#[test]
fn test_cuu_multi_row_from_middle() {
    // Move down to row 10, then CUU 3 → row 7; column stays
    let mut term = term!(24, 80);
    term.screen.move_cursor(10, 20);
    term.advance(b"\x1b[3A");
    assert_cursor!(term, 7, 20);
}

#[test]
fn test_cud_explicit_one_same_as_default() {
    // CSI 1 B == CSI B: both move down exactly one row
    let mut term_explicit = term!(24, 80);
    term_explicit.screen.move_cursor(3, 5);
    term_explicit.advance(b"\x1b[1B");

    let mut term_default = term!(24, 80);
    term_default.screen.move_cursor(3, 5);
    let params = vte::Params::default();
    csi_cud(&mut term_default, &params);

    assert_eq!(
        term_explicit.screen.cursor.row,
        term_default.screen.cursor.row
    );
    assert_eq!(
        term_explicit.screen.cursor.col,
        term_default.screen.cursor.col
    );
}

#[test]
fn test_cuf_multi_column_from_middle() {
    // Move to col 10, CUF 5 → col 15; row stays
    let mut term = term!(24, 80);
    term.screen.move_cursor(7, 10);
    term.advance(b"\x1b[5C");
    assert_cursor!(term, 7, 15);
}

#[test]
fn test_cub_explicit_zero_treated_as_1() {
    // CSI 0 D — explicit zero must be treated as 1 by .max(1)
    let mut term = term!(24, 80);
    term.screen.move_cursor(0, 5);
    term.advance(b"\x1b[0D");
    assert_cursor!(term, 0, 4);
}

#[test]
fn test_cuu_clamps_already_at_top_with_large_n() {
    // Already at row 0; CUU 1000 must stay at row 0
    let mut term = term!(24, 80);
    assert_eq!(term.screen.cursor.row, 0);
    term.advance(b"\x1b[1000A");
    assert_cursor!(term, row = 0);
}

#[test]
fn test_cuf_clamps_already_at_right_with_large_n() {
    // Start at last column; CUF 1000 must stay at last column
    let mut term = term!(24, 40);
    term.screen.move_cursor(0, 39);
    term.advance(b"\x1b[1000C");
    assert_cursor!(term, col = 39);
}

#[test]
fn test_cup_top_left_corner_idempotent() {
    // CUP to (1,1) from any position must always yield (0,0)
    let mut term = term!(24, 80);
    term.screen.move_cursor(23, 79);
    term.advance(b"\x1b[1;1H");
    assert_cursor!(term, 0, 0);
    // Repeating the same sequence changes nothing
    term.advance(b"\x1b[1;1H");
    assert_cursor!(term, 0, 0);
}

// ── Edge-case tests ───────────────────────────────────────────────────────────

#[test]
fn test_csi_vpa_zero_param_maps_to_row_zero() {
    // CSI 0 d — explicit zero is treated as 1 (1-indexed), which maps to row 0 (0-indexed).
    // The VPA handler uses `.unwrap_or(1).saturating_sub(1)`, so 0 → saturating_sub → 0.
    let mut term = term!(24, 80);
    term.screen.move_cursor(10, 5);
    term.advance(b"\x1b[0d");
    assert_cursor!(term, row = 0);
}

#[test]
fn test_csi_cha_param_exceeds_width_clamps() {
    // CSI 999 G on an 80-col terminal: column must clamp to the last column (79).
    let mut term = term!(24, 80);
    term.advance(b"\x1b[999G");
    assert_cursor!(term, col = 79);
}

#[test]
fn test_csi_cursor_up_cuu_moves_cursor() {
    // CSI 3 A from row 10 → row 7; column unchanged.
    let mut term = term!(24, 80);
    term.screen.move_cursor(10, 0);
    term.advance(b"\x1b[3A");
    assert_cursor!(term, 7, 0);
}

#[test]
fn test_csi_cursor_down_cud_moves_cursor() {
    // CSI 2 B from row 5 → row 7; column unchanged.
    let mut term = term!(24, 80);
    term.screen.move_cursor(5, 0);
    term.advance(b"\x1b[2B");
    assert_cursor!(term, 7, 0);
}

#[test]
fn test_csi_rep_does_not_panic() {
    // REP (CSI 3 b) is not implemented (falls through to `_ => {}`).
    // Verify that feeding it after a printable character does not panic.
    let mut term = term!(24, 80);
    term.advance(b"A"); // print 'A'
    term.advance(b"\x1b[3b"); // REP 3 — silently ignored
                              // The cursor must not have moved back or wrapped in an unexpected way.
    assert_cursor!(term, row = 0);
}

// ── New edge-case tests ───────────────────────────────────────────────────────

// DSR (Device Status Report) tests

#[test]
fn test_dsr_param6_enqueues_cpr_response() {
    // CSI 6 n should push an ESC[row;colR response into pending_responses.
    let mut term = term!(24, 80);
    term.screen.move_cursor(4, 9); // row=5, col=10 in 1-indexed
    term.advance(b"\x1b[6n");
    assert_eq!(
        term.meta.pending_responses.len(),
        1,
        "DSR 6 must enqueue exactly one response"
    );
    assert_eq!(
        term.meta.pending_responses[0], b"\x1b[5;10R",
        "DSR 6 response must be ESC[row;colR (1-indexed)"
    );
}

#[test]
fn test_dsr_param6_at_origin_is_1_1() {
    // At (0,0) the 1-indexed response is ESC[1;1R.
    let mut term = term!(24, 80);
    term.advance(b"\x1b[6n");
    assert_eq!(term.meta.pending_responses[0], b"\x1b[1;1R");
}

#[test]
fn test_dsr_non_6_param_is_silent_noop() {
    // DSR with param 5 (operating status) is not implemented — must not enqueue anything.
    let mut term = term!(24, 80);
    term.advance(b"\x1b[5n");
    assert!(
        term.meta.pending_responses.is_empty(),
        "DSR 5 is unimplemented and must not enqueue a response"
    );
}

// Zero-parameter tests for CUU / CUD / CUF / CUB
// VT standard: 0 is treated identically to 1 (csi_param1! uses .max(1)).

#[test]
fn test_cuu_zero_param_treated_as_1() {
    // CSI 0 A — explicit zero must move up by 1
    let mut term = term!(24, 80);
    term.screen.move_cursor(5, 10);
    term.advance(b"\x1b[0A");
    assert_cursor!(term, 4, 10);
}

#[test]
fn test_cud_zero_param_treated_as_1() {
    // CSI 0 B — explicit zero must move down by 1
    let mut term = term!(24, 80);
    term.screen.move_cursor(5, 10);
    term.advance(b"\x1b[0B");
    assert_cursor!(term, 6, 10);
}

#[test]
fn test_cuf_zero_param_treated_as_1() {
    // CSI 0 C — explicit zero must move right by 1
    let mut term = term!(24, 80);
    term.screen.move_cursor(3, 10);
    term.advance(b"\x1b[0C");
    assert_cursor!(term, 3, 11);
}

// Corner-case: cursor at bottom-right, movement in each direction

#[test]
fn test_cuu_from_bottom_right_corner() {
    // CUU 3 from the bottom-right corner: row decreases, col stays at last col.
    let mut term = term!(10, 40);
    term.screen.move_cursor(9, 39);
    term.advance(b"\x1b[3A");
    assert_cursor!(term, 6, 39);
}

#[test]
fn test_cub_from_bottom_right_corner_clamps() {
    // CUB large-n from bottom-right: col clamps to 0, row unchanged.
    let mut term = term!(10, 40);
    term.screen.move_cursor(9, 39);
    term.advance(b"\x1b[999D");
    assert_cursor!(term, 9, 0);
}

// VPA / CHA zero-param behaviour

#[test]
fn test_vpa_zero_param_maps_to_first_row() {
    // CSI 0 d — zero is treated as 1 (1-indexed) → row 0 (0-indexed).
    // saturating_sub(1) on 0 yields 0.
    let mut term = term!(24, 80);
    term.screen.move_cursor(15, 5);
    term.advance(b"\x1b[0d");
    assert_cursor!(term, row = 0);
}

#[test]
fn test_cha_zero_param_maps_to_first_col() {
    // CSI 0 G — zero saturating_sub(1) = 0 → column 0.
    let mut term = term!(24, 80);
    term.screen.move_cursor(5, 30);
    term.advance(b"\x1b[0G");
    assert_cursor!(term, col = 0);
}

// Sequential movements

#[test]
fn test_sequential_cup_then_cuu() {
    // CUP to (8,20) then CUU 3 → row 4, col 19 (0-indexed).
    let mut term = term!(24, 80);
    term.advance(b"\x1b[8;20H"); // → (7, 19)
    term.advance(b"\x1b[3A"); // → (4, 19)
    assert_cursor!(term, 4, 19);
}

#[test]
fn test_sequential_cnl_then_cpl_returns_to_origin() {
    // CNL 4 from row 3 → row 7 col 0; CPL 4 → row 3 col 0.
    let mut term = term!(24, 80);
    term.screen.move_cursor(3, 25);
    term.advance(b"\x1b[4E"); // CNL 4 → row 7, col 0
    assert_cursor!(term, 7, 0);
    term.advance(b"\x1b[4F"); // CPL 4 → row 3, col 0
    assert_cursor!(term, 3, 0);
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
