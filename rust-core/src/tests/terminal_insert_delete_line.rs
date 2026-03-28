// ── New tests covering previously untested behaviors ──────────────────────

/// IL (CSI L — Insert Line) inserts blank lines pushing content down.
#[test]
fn test_csi_il_inserts_blank_line() {
    let mut term = super::make_term();
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
    let mut term = super::make_term();
    // Write 'X' at row 1 col 0 using explicit CUP
    term.advance(b"\x1b[2;1H"); // CSI 2;1H → row 1, col 0
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
    let mut term = super::make_term();
    // Set scroll region to rows 2-5 (1-indexed: CSI 2;5r)
    term.advance(b"\x1b[2;5r");
    // Cursor must be moved to the home position (top of scroll region) after DECSTBM
    // The scroll-region top in 0-indexed is 1; cursor must be at row ≤ 1
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
    let mut term = super::make_term();
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
    let mut term = super::make_term();
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
    let mut term = super::make_term();
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
            let mut term = super::make_term();
            term.advance(&bytes);
            prop_assert!(term.screen.cursor().row < 24);
            prop_assert!(term.screen.cursor().col < 80);
}

        #[test]
        fn prop_resize_cursor_always_in_bounds(
            new_rows in 1u16..50,
            new_cols in 1u16..50,
        ) {
            let mut term = super::make_term();
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
            let mut term = super::make_term();
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
            let mut term = super::make_term();
            let seq = format!("\x1b[{row};{col}H");
            term.advance(seq.as_bytes());
            prop_assert!(term.screen.cursor().row < 24,
                "CUP row {} must clamp to <24, got {}", row, term.screen.cursor().row);
            prop_assert!(term.screen.cursor().col < 80,
                "CUP col {} must clamp to <80, got {}", col, term.screen.cursor().col);
        }

        #[test]
        fn prop_esc_m_never_panics(initial_row in 0usize..24) {
            let mut term = super::make_term();
            let seq = format!("\x1b[{};1H", initial_row + 1);
            term.advance(seq.as_bytes());
            term.advance(b"\x1bM");
            prop_assert!(term.screen.cursor().row < 24, "ESC M must not cause row overflow");
        }

        #[test]
        fn prop_large_input_cursor_in_bounds(
            bytes in proptest::collection::vec(any::<u8>(), 0..1024),
        ) {
            let mut term = super::make_term();
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
    let mut term = super::make_term();
    term.advance(b"\x1b[8;15H"); // row 7, col 14 (0-indexed)
    assert_eq!(term.cursor_row(), term.screen.cursor().row);
    assert_eq!(term.cursor_col(), term.screen.cursor().col);
    assert_eq!(term.cursor_row(), 7);
    assert_eq!(term.cursor_col(), 14);
}

/// `rows()` and `cols()` reflect the initial screen dimensions.
#[test]
fn test_rows_cols_accessors() {
    let term = super::make_term();
    assert_eq!(term.rows(), 24);
    assert_eq!(term.cols(), 80);
}

/// `resize` to smaller dimensions clamps both rows and cols.
#[test]
fn test_resize_shrinks_dimensions() {
    let mut term = super::make_term();
    term.resize(10, 40);
    assert_eq!(term.rows(), 10, "rows must shrink to 10");
    assert_eq!(term.cols(), 40, "cols must shrink to 40");
}

/// After `resize` to different dimensions, tab stops update to the new column count.
#[test]
fn test_resize_updates_tab_stops() {
    let mut term = super::make_term();
    term.resize(24, 40);
    // Tab every 8 columns — the first tab stop after resize should be at col 8.
    term.advance(b"\x1b[1;1H"); // cursor to col 0
    term.advance(b"\t"); // advance to first tab stop
    assert_eq!(
        term.screen.cursor().col,
        8,
        "first tab stop on a 40-col terminal must be at col 8"
    );
}

/// `flush_print_buf` with an empty buffer is a no-op.
#[test]
fn test_flush_print_buf_empty_is_noop() {
    let mut term = super::make_term();
    assert!(term.print_buf.is_empty(), "print_buf must start empty");
    term.flush_print_buf(); // must not panic, must not change cursor
    assert_cursor!(term, row 0, col 0);
}

/// `flush_print_buf` flushes buffered ASCII to the screen and clears the buffer.
#[test]
fn test_flush_print_buf_writes_content() {
    let mut term = super::make_term();
    term.print_buf.extend_from_slice(b"ABC");
    assert_eq!(
        term.print_buf.len(),
        3,
        "buffer must hold 3 bytes before flush"
    );
    term.flush_print_buf();
    assert!(
        term.print_buf.is_empty(),
        "flush_print_buf must clear print_buf"
    );
    // The three ASCII chars must now be on the screen.
    assert_cell_char!(term, row 0, col 0, 'A');
    assert_cell_char!(term, row 0, col 1, 'B');
    assert_cell_char!(term, row 0, col 2, 'C');
}

/// `scrollback_chars` returns character rows for content that was scrolled off.
#[test]
fn test_scrollback_chars_returns_pushed_lines() {
    let mut term = super::make_term();
    term.advance(b"SCROLLED");
    // Push the line into scrollback with 24 newlines.
    for _ in 0..24 {
        term.advance(b"\n");
    }
    let chars = term.scrollback_chars(100);
    assert!(
        !chars.is_empty(),
        "scrollback_chars must be non-empty after scrolling content off-screen"
    );
    // The first scrolled line must contain our marker.
    let has_marker = chars
        .iter()
        .any(|row| row.iter().collect::<String>().contains("SCROLLED"));
    assert!(
        has_marker,
        "scrollback_chars must include the 'SCROLLED' marker line"
    );
}

/// `scrollback_chars` with `max_lines=0` returns an empty vec.
#[test]
fn test_scrollback_chars_max_lines_zero() {
    let mut term = super::make_term();
    term.advance(b"line\n");
    for _ in 0..24 {
        term.advance(b"\n");
    }
    let chars = term.scrollback_chars(0);
    assert!(
        chars.is_empty(),
        "scrollback_chars(0) must return an empty vec"
    );
}

/// `title()` and `title_dirty()` reflect OSC 2 sequences.
#[test]
fn test_title_and_title_dirty_accessors() {
    let mut term = super::make_term();
    assert_eq!(term.title(), "", "title must be empty initially");
    assert!(!term.title_dirty(), "title_dirty must be false initially");

    term.advance(b"\x1b]2;MyTitle\x07");
    assert_eq!(term.title(), "MyTitle", "title must match OSC 2 payload");
    assert!(
        term.title_dirty(),
        "title_dirty must be true after OSC 2 sets a title"
    );
}

/// `palette_dirty()` is false initially and true after OSC 4.
#[test]
fn test_palette_dirty_accessor() {
    let mut term = super::make_term();
    assert!(
        !term.palette_dirty(),
        "palette_dirty must be false initially"
    );

    term.advance(b"\x1b]4;1;rgb:ff/00/00\x1b\\"); // OSC 4 sets palette entry 1
    assert!(
        term.palette_dirty(),
        "palette_dirty must be true after OSC 4"
    );
}

/// `default_colors_dirty()` is false initially and true after OSC 10.
#[test]
fn test_default_colors_dirty_accessor() {
    let mut term = super::make_term();
    assert!(
        !term.default_colors_dirty(),
        "default_colors_dirty must be false initially"
    );

    term.advance(b"\x1b]10;rgb:ff/80/00\x07"); // OSC 10 sets default fg
    assert!(
        term.default_colors_dirty(),
        "default_colors_dirty must be true after OSC 10"
    );
}

/// `pending_responses()` returns a slice of queued responses.
#[test]
fn test_pending_responses_accessor() {
    let mut term = super::make_term();
    assert!(
        term.pending_responses().is_empty(),
        "pending_responses must be empty initially"
    );

    term.advance(b"\x1b[6n"); // DSR — queues a CPR response
    assert_eq!(
        term.pending_responses().len(),
        1,
        "pending_responses must hold 1 entry after DSR"
    );
}

/// `current_foreground()` returns `Color::Default` initially.
#[test]
fn test_current_foreground_default() {
    let term = super::make_term();
    assert_eq!(
        *term.current_foreground(),
        crate::types::Color::Default,
        "current_foreground must be Color::Default initially"
    );
}

/// After SGR 31 (red foreground), `current_foreground()` is a Named color.
#[test]
fn test_current_foreground_after_sgr31() {
    let mut term = super::make_term();
    term.advance(b"\x1b[31m"); // SGR 31: red foreground
    assert!(
        matches!(*term.current_foreground(), crate::types::Color::Named(_)),
        "current_foreground must be a Named color after SGR 31, got {:?}",
        term.current_foreground()
    );
}

/// `dec_modes()` accessor returns the live DecModes ref.
#[test]
fn test_dec_modes_accessor_reflects_live_state() {
    let mut term = super::make_term();
    assert!(
        term.dec_modes().cursor_visible,
        "cursor_visible must be true initially"
    );
    term.advance(b"\x1b[?25l"); // DECTCEM off
    assert!(
        !term.dec_modes().cursor_visible,
        "dec_modes().cursor_visible must be false after CSI ?25l"
    );
}

/// `current_attrs()` accessor returns the live SgrAttributes ref.
#[test]
fn test_current_attrs_accessor_reflects_sgr() {
    let mut term = super::make_term();
    assert!(
        !term.current_attrs().flags.contains(SgrFlags::BOLD),
        "bold must be clear initially"
    );
    term.advance(b"\x1b[1m"); // bold on
    assert!(
        term.current_attrs().flags.contains(SgrFlags::BOLD),
        "current_attrs() must reflect bold after SGR 1"
    );
}

/// `osc_data()` accessor returns the live OscData ref (CWD example).
#[test]
fn test_osc_data_accessor_reflects_osc7() {
    let mut term = super::make_term();
    assert!(
        term.osc_data().cwd.is_none(),
        "osc_data().cwd must be None initially"
    );
    term.advance(b"\x1b]7;file://localhost/tmp\x07");
    assert!(
        term.osc_data().cwd.is_some(),
        "osc_data().cwd must be Some after OSC 7"
    );
}

/// `soft_reset` clears `saved_primary_attrs` (the alt-screen SGR snapshot).
#[test]
fn test_soft_reset_clears_saved_primary_attrs() {
    let mut term = super::make_term();
    // Force-set saved_primary_attrs to simulate a previous alt-screen save.
    term.saved_primary_attrs = Some(crate::types::cell::SgrAttributes::default());
    assert!(
        term.saved_primary_attrs.is_some(),
        "pre-condition: saved_primary_attrs must be Some"
    );
    term.advance(b"\x1b[!p"); // DECSTR (soft reset)
    assert!(
        term.saved_primary_attrs.is_none(),
        "soft_reset must clear saved_primary_attrs"
    );
}

/// After `reset()`, `parser_in_ground` is `true` and `print_buf` is empty.
#[test]
fn test_reset_restores_parser_state() {
    let mut term = super::make_term();
    // Corrupt parser state manually to simulate mid-sequence input.
    term.parser_in_ground = false;
    term.print_buf.extend_from_slice(b"leftover");

    term.reset();

    assert!(
        term.parser_in_ground,
        "reset must set parser_in_ground to true"
    );
    assert!(term.print_buf.is_empty(), "reset must clear print_buf");
}
