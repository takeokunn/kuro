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

// ── Macro: test_nl_zero_param ─────────────────────────────────────────────────
//
// Generates a test verifying that CNL or CPL treats an explicit zero parameter
// identically to 1 (via `.max(1)`), yielding the expected cursor position.
//
// Usage:
// ```text
// test_nl_zero_param!(test_name, b"seq", start (row, col) => expected (row, col))
// ```
macro_rules! test_nl_zero_param {
    (
        $(
            $name:ident : $seq:expr , ($sr:expr, $sc:expr) => ($er:expr, $ec:expr) , $msg:expr
        ),+ $(,)?
    ) => {
        $(
            #[test]
            fn $name() {
                let mut term = crate::TerminalCore::new(24, 80);
                term.screen.move_cursor($sr, $sc);
                term.advance($seq);
                assert_eq!(term.screen.cursor.row, $er, $msg);
                assert_eq!(term.screen.cursor.col, $ec, $msg);
            }
        )+
    };
}

test_nl_zero_param! {
    // CSI 0 E — explicit zero must be clamped to 1 by .max(1)
    test_cnl_zero_param_treated_as_1:
        b"\x1b[0E", (3, 15) => (4, 0), "CNL 0 must move down 1 and reset col to 0",
    // CSI 0 F — explicit zero must be clamped to 1 by .max(1)
    test_cpl_zero_param_treated_as_1:
        b"\x1b[0F", (5, 20) => (4, 0), "CPL 0 must move up 1 and reset col to 0",
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

// ── Macro: test_csi_cursor_moves ─────────────────────────────────────────────
//
// Generates a test that: places the cursor at a given position, sends a CSI
// sequence, and asserts the resulting cursor position.
//
// Usage:
// ```text
// test_csi_cursor_moves!(test_name : b"seq", start (row, col) => expected (row, col), "msg")
// ```
macro_rules! test_csi_cursor_moves {
    (
        $(
            $name:ident : $seq:expr , ($sr:expr, $sc:expr) => ($er:expr, $ec:expr) , $msg:expr
        ),+ $(,)?
    ) => {
        $(
            #[test]
            fn $name() {
                let mut term = term!(24, 80);
                term.screen.move_cursor($sr, $sc);
                term.advance($seq);
                assert_cursor!(term, $er, $ec);
            }
        )+
    };
}

test_csi_cursor_moves! {
    // CSI 3 A from row 10 → row 7; column unchanged.
    test_csi_cursor_up_cuu_moves_cursor:
        b"\x1b[3A", (10, 0) => (7, 0), "CUU 3 from row 10 must land at row 7",
    // CSI 2 B from row 5 → row 7; column unchanged.
    test_csi_cursor_down_cud_moves_cursor:
        b"\x1b[2B", (5, 0) => (7, 0), "CUD 2 from row 5 must land at row 7",
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
