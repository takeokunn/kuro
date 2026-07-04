use super::super::make_term;
use super::*;

#[test]
fn test_esc_m_reverse_index_at_top_scrolls_down() {
    let mut term = make_term();
    term.advance(b"A");
    term.advance(b"\x1b[1;1H");
    term.advance(b"\x1b[1;1H");
    assert_eq!(term.screen.cursor().row, 0);
    term.advance(b"X");
    term.advance(b"\x1b[1;1H");
    assert_eq!(term.screen.cursor().row, 0);
    term.advance(b"\x1bM");
    assert_eq!(
        term.screen.cursor().row,
        0,
        "ESC M at scroll top should keep cursor at row 0"
    );
    let cell_row1 = term.screen.get_cell(1, 0).unwrap();
    assert_eq!(
        cell_row1.char(),
        'X',
        "ESC M at scroll top: previous row 0 content should move to row 1"
    );
}

#[test]
fn test_esc_m_at_row_zero_no_underflow() {
    let mut term = make_term();
    assert_eq!(term.screen.cursor().row, 0);
    term.advance(b"\x1bM");
    assert_eq!(
        term.screen.cursor().row,
        0,
        "ESC M at row 0 (scroll top) must not underflow"
    );
}

#[test]
fn test_esc_d_index_basic() {
    let mut term = make_term();
    term.advance(b"\x1b[1;1H");
    assert_eq!(term.screen.cursor().row, 0);
    term.advance(b"\x1bD");
    assert_eq!(term.screen.cursor().row, 1, "ESC D should move cursor down");
}

#[test]
fn test_esc_e_next_line() {
    let mut term = make_term();
    term.advance(b"\x1b[1;5H"); // row 0, col 4
    assert_eq!(term.screen.cursor().col, 4);
    term.advance(b"\x1bE"); // NEL
    assert_cursor!(term, row 1, col 0);
}

// === Clean shutdown / drop test ===

#[test]
fn test_terminal_drop_does_not_panic() {
    let term = make_term();
    drop(term);
}

// ── Insert/Delete line tests (previously in terminal_insert_delete_line.rs) ──

/// IL (CSI L — Insert Line) inserts blank lines pushing content down.
#[test]
fn test_csi_il_inserts_blank_line() {
    let mut term = make_term();
    // Print a line on row 0 and move cursor back to row 0
    term.advance(b"First line content");
    term.advance(b"\x1b[1;1H"); // cursor to row 0, col 0
    term.advance(b"\x1b[1L"); // IL 1: insert blank line above current row
                              // Row 0 should now be blank (the inserted line)
    assert_cell_char!(term, row 0, col 0, ' ');
    // Previous row 0 content should be at row 1
    assert_cell_char!(term, row 1, col 0, 'F');
}

/// DL (CSI M — Delete Line) removes the current line, scrolling content up.
#[test]
fn test_csi_dl_deletes_current_line() {
    let mut term = make_term();
    // Write 'X' at row 1 col 0 using explicit CUP
    term.advance(b"\x1b[2;1H"); // CSI 2;1H -> row 1, col 0
    term.advance(b"X");
    // Move cursor back to row 0
    term.advance(b"\x1b[1;1H");
    term.advance(b"\x1b[1M"); // DL 1: delete row 0
                              // 'X' from row 1 must shift up to row 0
    assert_cell_char!(term, row 0, col 0, 'X');
    // Row 1 is now blank (shifted in at the bottom)
    assert_cell_char!(term, row 1, col 0, ' ');
}

/// Scroll region (DECSTBM, CSI r) — content outside the region must not scroll.
#[test]
fn test_csi_decstbm_scroll_region_set_and_respected() {
    let mut term = make_term();
    // Set scroll region to rows 2-5 (1-indexed: CSI 2;5r)
    term.advance(b"\x1b[2;5r");
    // Cursor must be moved to the home position (top of scroll region) after DECSTBM
    // The scroll-region top in 0-indexed is 1; cursor must be at row <= 1
    // (Some terminals move to absolute (0,0); others to region top — just assert in-bounds)
    assert!(
        term.screen.cursor().row <= 1,
        "DECSTBM should move cursor to home"
    );

    // Write a marker on row 0 (outside region)
    term.advance(b"\x1b[1;1H");
    term.advance(b"OUTSIDE");

    // Move to the bottom of the scroll region (row 4, 0-indexed) and feed a LF
    term.advance(b"\x1b[5;1H"); // row 4, col 0 (1-indexed row 5)
    term.advance(b"\n"); // should scroll only rows 1-4

    // Row 0 ('OUTSIDE') must be intact — it's outside the scroll region
    assert_cell_char!(term, row 0, col 0, 'O');
}

/// CSI S (scroll up N lines) must scroll the visible screen up.
#[test]
fn test_csi_scroll_up_shifts_content() {
    let mut term = make_term();
    // Put a marker on row 1
    term.advance(b"\x1b[2;1H");
    term.advance(b"MARKER");
    term.advance(b"\x1b[1;1H"); // back to row 0

    // CSI 1 S — scroll up 1 line
    term.advance(b"\x1b[1S");

    // MARKER should now be on row 0
    assert_cell_char!(term, row 0, col 0, 'M');
}

/// CSI T (scroll down N lines) must scroll the visible screen down.
#[test]
fn test_csi_scroll_down_shifts_content() {
    let mut term = make_term();
    // Put a marker on row 0
    term.advance(b"\x1b[1;1H");
    term.advance(b"MARKER");
    term.advance(b"\x1b[1;1H");

    // CSI 1 T — scroll down 1 line
    term.advance(b"\x1b[1T");

    // MARKER should now be on row 1
    assert_cell_char!(term, row 1, col 0, 'M');
}

/// Cursor positions reported by DSR (CSI 6 n) must match the actual cursor.
#[test]
fn test_cursor_position_matches_dsr_response() {
    let mut term = make_term();
    term.advance(b"\x1b[12;34H"); // row 11, col 33 (0-indexed)
    let actual_row = term.screen.cursor().row + 1; // 1-indexed
    let actual_col = term.screen.cursor().col + 1;

    term.advance(b"\x1b[6n"); // DSR
    assert_eq!(term.meta.pending_responses.len(), 1);
    let resp = String::from_utf8_lossy(&term.meta.pending_responses[0]);
    let expected = format!("\x1b[{actual_row};{actual_col}R");
    assert_eq!(
        resp.as_ref(),
        expected,
        "DSR response must exactly encode the current cursor position"
    );
}

proptest! {
        #[test]
        fn prop_vte_parse_never_panics(bytes in proptest::collection::vec(any::<u8>(), 0..256)) {
            let mut term = make_term();
            term.advance(&bytes);
            prop_assert!(term.screen.cursor().row < 24);
            prop_assert!(term.screen.cursor().col < 80);
}

        #[test]
        fn prop_resize_cursor_always_in_bounds(
            new_rows in 1u16..50,
            new_cols in 1u16..50,
        ) {
            let mut term = make_term();
            term.advance(b"\x1b[20;70H");
            term.resize(new_rows, new_cols);
            prop_assert!(term.screen.cursor().row < new_rows as usize,
                "cursor row {} >= {}", term.screen.cursor().row, new_rows);
            prop_assert!(term.screen.cursor().col < new_cols as usize,
                "cursor col {} >= {}", term.screen.cursor().col, new_cols);
        }

        #[test]
        fn prop_sgr_reset_always_clears(
            bold in any::<bool>(),
            italic in any::<bool>(),
        ) {
            let mut term = make_term();
            if bold { term.advance(b"\x1b[1m"); }
            if italic { term.advance(b"\x1b[3m"); }
            term.advance(b"\x1b[0m");
            prop_assert!(!term.current_bold(), "SGR 0 must clear bold");
            prop_assert!(!term.current_italic(), "SGR 0 must clear italic");
            prop_assert!(!term.current_underline(), "SGR 0 must clear underline");
        }

        #[test]
        fn prop_cup_clamps_to_screen(
            row in 1u16..200,
            col in 1u16..200,
        ) {
            let mut term = make_term();
            let seq = format!("\x1b[{row};{col}H");
            term.advance(seq.as_bytes());
            prop_assert!(term.screen.cursor().row < 24,
                "CUP row {} must clamp to <24, got {}", row, term.screen.cursor().row);
            prop_assert!(term.screen.cursor().col < 80,
                "CUP col {} must clamp to <80, got {}", col, term.screen.cursor().col);
        }

        #[test]
        fn prop_esc_m_never_panics(initial_row in 0usize..24) {
            let mut term = make_term();
            let seq = format!("\x1b[{};1H", initial_row + 1);
            term.advance(seq.as_bytes());
            term.advance(b"\x1bM");
            prop_assert!(term.screen.cursor().row < 24, "ESC M must not cause row overflow");
        }

        #[test]
        fn prop_large_input_cursor_in_bounds(
            bytes in proptest::collection::vec(any::<u8>(), 0..1024),
        ) {
            let mut term = make_term();
            for chunk in bytes.chunks(64) {
                term.advance(chunk);
            }
            prop_assert!(term.screen.cursor().row < 24,
                "cursor row {} out of bounds after large input", term.screen.cursor().row);
            prop_assert!(term.screen.cursor().col < 80,
                "cursor col {} out of bounds after large input", term.screen.cursor().col);
        }
    }

// ── New targeted tests ─────────────────────────────────────────────────────

/// `cursor_row()` and `cursor_col()` return the same values as the inner cursor.
#[test]
fn test_cursor_row_col_accessors_match_screen() {
    let mut term = make_term();
    term.advance(b"\x1b[8;15H"); // row 7, col 14 (0-indexed)
    assert_eq!(term.cursor_row(), term.screen.cursor().row);
    assert_eq!(term.cursor_col(), term.screen.cursor().col);
    assert_eq!(term.cursor_row(), 7);
    assert_eq!(term.cursor_col(), 14);
}

/// `rows()` and `cols()` reflect the initial screen dimensions.
#[test]
fn test_rows_cols_accessors() {
    let term = make_term();
    assert_eq!(term.rows(), 24);
    assert_eq!(term.cols(), 80);
}

/// `resize` to smaller dimensions clamps both rows and cols.
#[test]
fn test_resize_shrinks_dimensions() {
    let mut term = make_term();
    term.resize(10, 40);
    assert_eq!(term.rows(), 10, "rows must shrink to 10");
    assert_eq!(term.cols(), 40, "cols must shrink to 40");
}
