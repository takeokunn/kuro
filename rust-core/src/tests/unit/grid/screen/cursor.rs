//! Property-based and example-based tests for Screen cursor movement methods.
//!
//! Module under test: `grid/screen/cursor.rs`
//! Tier: T2 — `ProptestConfig::with_cases(500)`

use crate::grid::screen::Screen;
use crate::types::cell::SgrAttributes;
use crate::types::color::Color;
use proptest::prelude::*;

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Standard 24×80 screen for most tests.
fn make_screen() -> Screen {
    Screen::new(24, 80)
}

// ── Property-based tests ──────────────────────────────────────────────────────

proptest! {
    #![proptest_config(ProptestConfig::with_cases(500))]

    #[test]
    // INVARIANT: move_cursor clamps row to [0, rows-1]; cursor.row is always in-bounds.
    fn prop_move_cursor_clamps_row(row in 0usize..200usize, col in 0usize..80usize) {
        let mut screen = make_screen();
        screen.move_cursor(row, col);
        prop_assert!(
            screen.cursor().row < screen.rows() as usize,
            "cursor.row {} must be < rows {}",
            screen.cursor().row,
            screen.rows()
        );
    }

    #[test]
    // INVARIANT: move_cursor clamps col to [0, cols-1]; cursor.col is always in-bounds.
    fn prop_move_cursor_clamps_col(row in 0usize..24usize, col in 0usize..200usize) {
        let mut screen = make_screen();
        screen.move_cursor(row, col);
        prop_assert!(
            screen.cursor().col < screen.cols() as usize,
            "cursor.col {} must be < cols {}",
            screen.cursor().col,
            screen.cols()
        );
    }

    #[test]
    // INVARIANT: move_cursor always clears pending_wrap regardless of position.
    fn prop_move_cursor_clears_pending_wrap(row in 0usize..200usize, col in 0usize..200usize) {
        let mut screen = make_screen();
        // Artificially set pending_wrap to simulate a prior last-column print.
        screen.cursor.pending_wrap = true;
        screen.move_cursor(row, col);
        prop_assert!(
            !screen.cursor().pending_wrap,
            "move_cursor must clear pending_wrap"
        );
    }

    #[test]
    // INVARIANT: move_cursor_by never panics for any i32 row/col offsets.
    fn prop_move_cursor_by_no_panic(row_offset in i32::MIN..=i32::MAX, col_offset in i32::MIN..=i32::MAX) {
        let mut screen = make_screen();
        // Should not panic under any offset combination.
        screen.move_cursor_by(row_offset, col_offset);
        // Cursor must remain in-bounds after clamping.
        prop_assert!(screen.cursor().row < screen.rows() as usize);
        prop_assert!(screen.cursor().col < screen.cols() as usize);
    }

    #[test]
    // INVARIANT: move_cursor_by clears pending_wrap for any offset.
    fn prop_move_cursor_by_clears_pending_wrap(
        row_offset in -50i32..50i32,
        col_offset in -50i32..50i32,
    ) {
        let mut screen = make_screen();
        screen.cursor.pending_wrap = true;
        screen.move_cursor_by(row_offset, col_offset);
        prop_assert!(
            !screen.cursor().pending_wrap,
            "move_cursor_by must clear pending_wrap"
        );
    }

    #[test]
    // INVARIANT: carriage_return always sets cursor.col to 0.
    fn prop_carriage_return_col_zero(start_col in 0usize..80usize) {
        let mut screen = make_screen();
        screen.move_cursor(0, start_col);
        screen.carriage_return();
        prop_assert_eq!(
            screen.cursor().col, 0,
            "carriage_return must set col to 0"
        );
    }

    #[test]
    // INVARIANT: backspace never underflows (col stays >= 0 as a usize).
    fn prop_backspace_saturating(start_col in 0usize..80usize) {
        let mut screen = make_screen();
        screen.move_cursor(0, start_col);
        // Backspace many more times than there are columns — must not panic or underflow.
        for _ in 0..100 {
            screen.backspace();
        }
        // usize can't go negative; verify the invariant explicitly.
        prop_assert_eq!(
            screen.cursor().col, 0,
            "backspace must saturate at col 0"
        );
    }

    #[test]
    // INVARIANT: tab advances cursor.col to the next tab stop (multiple of 8),
    // clamped to cols-1.
    fn prop_tab_advances_to_stop(start_col in 0usize..79usize) {
        let mut screen = make_screen();
        let cols = screen.cols() as usize;
        screen.move_cursor(0, start_col);
        screen.tab();
        let new_col = screen.cursor().col;
        let expected = ((start_col / 8) + 1) * 8;
        let expected_clamped = expected.min(cols - 1);
        prop_assert_eq!(
            new_col, expected_clamped,
            "tab from col {} should advance to {} (clamped from {})",
            start_col, expected_clamped, expected
        );
    }

    #[test]
    // INVARIANT: backspace clears pending_wrap.
    fn prop_backspace_clears_pending_wrap(start_col in 0usize..80usize) {
        let mut screen = make_screen();
        screen.move_cursor(0, start_col);
        screen.cursor.pending_wrap = true;
        screen.backspace();
        prop_assert!(
            !screen.cursor().pending_wrap,
            "backspace must clear pending_wrap"
        );
    }

    #[test]
    // INVARIANT: carriage_return clears pending_wrap.
    fn prop_carriage_return_clears_pending_wrap(start_col in 0usize..80usize) {
        let mut screen = make_screen();
        screen.move_cursor(0, start_col);
        screen.cursor.pending_wrap = true;
        screen.carriage_return();
        prop_assert!(
            !screen.cursor().pending_wrap,
            "carriage_return must clear pending_wrap"
        );
    }

    #[test]
    // INVARIANT: tab clears pending_wrap.
    fn prop_tab_clears_pending_wrap(start_col in 0usize..79usize) {
        let mut screen = make_screen();
        screen.move_cursor(0, start_col);
        screen.cursor.pending_wrap = true;
        screen.tab();
        prop_assert!(
            !screen.cursor().pending_wrap,
            "tab must clear pending_wrap"
        );
    }

    #[test]
    // INVARIANT: after move_cursor, the exact clamped values are stored.
    fn prop_move_cursor_exact_clamped_value(row in 0usize..200usize, col in 0usize..200usize) {
        let mut screen = make_screen();
        let rows = screen.rows() as usize;
        let cols = screen.cols() as usize;
        screen.move_cursor(row, col);
        let expected_row = row.min(rows - 1);
        let expected_col = col.min(cols - 1);
        prop_assert_eq!(screen.cursor().row, expected_row);
        prop_assert_eq!(screen.cursor().col, expected_col);
    }
}

// ── Example-based tests ───────────────────────────────────────────────────────

#[test]
fn test_line_feed_advances_row() {
    let mut screen = make_screen();
    assert_eq!(screen.cursor().row, 0);
    screen.line_feed(Color::Default);
    assert_eq!(screen.cursor().row, 1);
    assert_eq!(screen.cursor().col, 0);
}

#[test]
fn test_line_feed_clears_pending_wrap() {
    // line_feed_impl sets pending_wrap = false before advancing.
    let mut screen = make_screen();
    // Place cursor at a mid-screen row so LF advances without scrolling.
    screen.move_cursor(5, 10);
    screen.cursor.pending_wrap = true;
    screen.line_feed(Color::Default);
    assert!(!screen.cursor().pending_wrap);
}

#[test]
fn test_line_feed_at_bottom_scrolls() {
    // When cursor is at row 23 (last row of a 24-row screen), LF triggers scroll_up.
    let mut screen = make_screen();
    screen.move_cursor(23, 0);
    screen.line_feed(Color::Default);
    // Cursor stays at row 23 (scroll region bottom - 1).
    assert_eq!(screen.cursor().row, 23);
}

#[test]
fn test_carriage_return_clears_pending_wrap_example() {
    let mut screen = make_screen();
    screen.move_cursor(3, 50);
    screen.cursor.pending_wrap = true;
    screen.carriage_return();
    assert_eq!(screen.cursor().col, 0);
    assert!(!screen.cursor().pending_wrap);
}

#[test]
fn test_move_cursor_clamps_to_last_row() {
    let mut screen = make_screen();
    screen.move_cursor(9999, 0);
    assert_eq!(screen.cursor().row, 23); // rows=24, last index=23
}

#[test]
fn test_move_cursor_clamps_to_last_col() {
    let mut screen = make_screen();
    screen.move_cursor(0, 9999);
    assert_eq!(screen.cursor().col, 79); // cols=80, last index=79
}

#[test]
fn test_backspace_from_zero_stays_zero() {
    let mut screen = make_screen();
    assert_eq!(screen.cursor().col, 0);
    screen.backspace();
    assert_eq!(screen.cursor().col, 0);
}

#[test]
fn test_backspace_decrements_col() {
    let mut screen = make_screen();
    screen.move_cursor(0, 10);
    screen.backspace();
    assert_eq!(screen.cursor().col, 9);
}

#[test]
fn test_tab_from_col_zero() {
    let mut screen = make_screen();
    screen.tab();
    assert_eq!(screen.cursor().col, 8);
}

#[test]
fn test_tab_from_col_7() {
    // col=7: next stop is (7/8+1)*8 = 8.
    let mut screen = make_screen();
    screen.move_cursor(0, 7);
    screen.tab();
    assert_eq!(screen.cursor().col, 8);
}

#[test]
fn test_tab_from_col_8() {
    // col=8: next stop is (8/8+1)*8 = 16.
    let mut screen = make_screen();
    screen.move_cursor(0, 8);
    screen.tab();
    assert_eq!(screen.cursor().col, 16);
}

#[test]
fn test_tab_at_last_tab_stop_clamps() {
    // col=79 (last col of 80-col screen): (79/8+1)*8 = 80, clamped to 79.
    let mut screen = make_screen();
    screen.move_cursor(0, 79);
    screen.tab();
    assert_eq!(screen.cursor().col, 79);
}

#[test]
fn test_move_cursor_by_positive_offsets() {
    let mut screen = make_screen();
    screen.move_cursor(5, 10);
    screen.move_cursor_by(3, 5); // row_offset=3, col_offset=5
                                 // move_by(col_offset=5, row_offset=3): col += 5 → 15, row += 3 → 8
    assert_eq!(screen.cursor().row, 8);
    assert_eq!(screen.cursor().col, 15);
}

#[test]
fn test_move_cursor_by_negative_clamps_at_zero() {
    let mut screen = make_screen();
    screen.move_cursor(2, 5);
    // Large negative offsets must not underflow.
    screen.move_cursor_by(-1000, -1000);
    assert_eq!(screen.cursor().row, 0);
    assert_eq!(screen.cursor().col, 0);
}

#[test]
fn test_move_cursor_by_large_positive_clamps_at_max() {
    let mut screen = make_screen();
    screen.move_cursor_by(10000, 10000);
    assert_eq!(screen.cursor().row, 23);
    assert_eq!(screen.cursor().col, 79);
}

// ── print_ascii_run tests ─────────────────────────────────────────────────────

#[test]
fn print_ascii_run_writes_bytes_at_cursor() {
    let mut screen = make_screen();
    let attrs = SgrAttributes::default();
    screen.move_cursor(0, 0);
    screen.print_ascii_run(b"ABC", attrs, true);
    assert_eq!(screen.get_cell(0, 0).unwrap().char(), 'A');
    assert_eq!(screen.get_cell(0, 1).unwrap().char(), 'B');
    assert_eq!(screen.get_cell(0, 2).unwrap().char(), 'C');
}

#[test]
fn print_ascii_run_advances_cursor() {
    let mut screen = make_screen();
    let attrs = SgrAttributes::default();
    screen.move_cursor(0, 0);
    screen.print_ascii_run(b"HELLO", attrs, true);
    // Cursor should have advanced by 5 columns.
    assert_eq!(screen.cursor().col, 5);
}

#[test]
fn print_ascii_run_empty_slice_is_noop() {
    let mut screen = make_screen();
    let attrs = SgrAttributes::default();
    screen.move_cursor(0, 10);
    screen.print_ascii_run(b"", attrs, true);
    // Cursor must not move.
    assert_eq!(screen.cursor().col, 10);
    assert_eq!(screen.cursor().row, 0);
}

#[test]
fn print_ascii_run_wraps_at_right_margin_with_auto_wrap() {
    let mut screen = make_screen();
    let attrs = SgrAttributes::default();
    // Position cursor at col 78, print 3 bytes — the third triggers wrap.
    screen.move_cursor(0, 78);
    screen.print_ascii_run(b"XYZ", attrs, true);
    // 'X' at (0,78), 'Y' at (0,79) sets pending_wrap; 'Z' wraps to (1,0).
    assert_eq!(screen.get_cell(0, 78).unwrap().char(), 'X');
    assert_eq!(screen.get_cell(0, 79).unwrap().char(), 'Y');
    assert_eq!(screen.get_cell(1, 0).unwrap().char(), 'Z');
}

#[test]
fn print_ascii_run_no_wrap_without_auto_wrap() {
    // When auto_wrap=false, bytes that reach the last column stay there
    // without wrapping; cursor stays at cols-1.
    let mut screen = make_screen();
    let attrs = SgrAttributes::default();
    screen.move_cursor(0, 78);
    screen.print_ascii_run(b"XYZ", attrs, false);
    // 'X' at (0,78); 'Y' at (0,79) sets cursor to last col; 'Z' overwrites (0,79)
    // because no-auto-wrap clamps the cursor and overwrites the last cell in place.
    assert_eq!(screen.get_cell(0, 78).unwrap().char(), 'X');
    assert_eq!(screen.get_cell(0, 79).unwrap().char(), 'Z');
    // Row 1 col 0 must not have 'Z' — no wrap occurred.
    assert_eq!(screen.get_cell(1, 0).unwrap().char(), ' ');
    // Cursor stays at last column.
    assert_eq!(screen.cursor().col, 79);
}

#[test]
fn print_ascii_run_marks_row_dirty() {
    let mut screen = make_screen();
    let attrs = SgrAttributes::default();
    let _ = screen.take_dirty_lines(); // drain initial state
    screen.move_cursor(3, 0);
    screen.print_ascii_run(b"hello", attrs, true);
    let dirty = screen.take_dirty_lines();
    assert!(
        dirty.contains(&3),
        "row 3 must be dirty after print_ascii_run"
    );
}

#[test]
fn print_ascii_run_preserves_cell_count_at_line_boundary() {
    // After a run that fills an entire row, line cell count must remain cols.
    let mut screen = Screen::new(4, 10);
    let attrs = SgrAttributes::default();
    screen.move_cursor(0, 0);
    screen.print_ascii_run(b"1234567890", attrs, true);
    assert_eq!(
        screen.get_line(0).unwrap().cells.len(),
        10,
        "cell count must remain 10 after full-line ASCII run"
    );
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(128))]

    #[test]
    // PANIC SAFETY: print_ascii_run with a random printable ASCII slice never panics;
    // cursor stays in-bounds and line width is preserved.
    fn prop_print_ascii_run_no_panic(
        len in 0usize..200usize,
        start_col in 0usize..80usize,
        auto_wrap in proptest::bool::ANY,
    ) {
        let mut screen = Screen::new(24, 80);
        let attrs = SgrAttributes::default();
        let bytes: Vec<u8> = (0..len).map(|i| b'A' + (i % 26) as u8).collect();
        screen.move_cursor(0, start_col);
        screen.print_ascii_run(&bytes, attrs, auto_wrap);
        prop_assert!(screen.cursor().row < 24, "cursor.row out of bounds");
        prop_assert!(screen.cursor().col < 80, "cursor.col out of bounds");
        prop_assert_eq!(screen.get_line(0).unwrap().cells.len(), 80);
    }
}

// ── print() tests ─────────────────────────────────────────────────────────────

#[test]
fn print_ascii_char_writes_cell() {
    let mut screen = make_screen();
    let attrs = SgrAttributes::default();
    screen.move_cursor(0, 0);
    screen.print('A', attrs, true);
    assert_eq!(screen.get_cell(0, 0).unwrap().char(), 'A');
    assert_eq!(screen.cursor().col, 1);
}

#[test]
fn print_sets_pending_wrap_at_last_column() {
    // Printing into column 79 (last col of 80-col screen) sets pending_wrap.
    let mut screen = make_screen();
    let attrs = SgrAttributes::default();
    screen.move_cursor(0, 79);
    screen.print('X', attrs, true);
    assert!(
        screen.cursor().pending_wrap,
        "pending_wrap must be set after printing at last column with auto_wrap=true"
    );
    assert_eq!(screen.cursor().col, 79, "cursor must stay at last column");
}

#[test]
fn print_no_pending_wrap_without_auto_wrap() {
    // With auto_wrap=false, reaching last column does NOT set pending_wrap.
    let mut screen = make_screen();
    let attrs = SgrAttributes::default();
    screen.move_cursor(0, 79);
    screen.print('X', attrs, false);
    assert!(
        !screen.cursor().pending_wrap,
        "pending_wrap must NOT be set when auto_wrap=false"
    );
}

#[test]
fn print_deferred_wrap_fires_on_next_print() {
    // After pending_wrap is set, the next print wraps to col 0 of the next row.
    let mut screen = make_screen();
    let attrs = SgrAttributes::default();
    // Fill to last column, triggering pending_wrap.
    screen.move_cursor(0, 79);
    screen.print('A', attrs, true);
    assert!(screen.cursor().pending_wrap);
    // The deferred wrap fires on the next print.
    screen.print('B', attrs, true);
    assert_eq!(screen.cursor().row, 1, "wrap must advance to row 1");
    assert_eq!(screen.cursor().col, 1, "cursor must be at col 1 after 'B'");
    assert_eq!(screen.get_cell(1, 0).unwrap().char(), 'B');
}

#[test]
fn print_deferred_wrap_does_not_fire_when_auto_wrap_off() {
    // When auto_wrap=false, a pending_wrap (from a prior true-mode print) does not fire.
    // However note: pending_wrap is only set when auto_wrap=true, so test
    // the in-place overwrite behavior: printing at last col with auto_wrap=false overwrites.
    let mut screen = make_screen();
    let attrs = SgrAttributes::default();
    // Print to second-to-last column so cursor is at 78, then fill 79.
    screen.move_cursor(0, 79);
    screen.print('A', attrs, false); // no pending_wrap set
    assert!(!screen.cursor().pending_wrap);
    // Cursor is at col 79. Print again — overwrites col 79 in place.
    screen.print('B', attrs, false);
    assert_eq!(screen.get_cell(0, 79).unwrap().char(), 'B');
    assert_eq!(screen.cursor().row, 0, "row must not change without wrap");
}

#[test]
fn print_marks_row_dirty() {
    let mut screen = make_screen();
    let attrs = SgrAttributes::default();
    let _ = screen.take_dirty_lines();
    screen.move_cursor(5, 0);
    screen.print('Z', attrs, true);
    let dirty = screen.take_dirty_lines();
    assert!(dirty.contains(&5), "row 5 must be dirty after print()");
}

#[test]
fn print_wide_char_places_placeholder() {
    // CJK wide character occupies 2 columns; col+1 gets a Wide placeholder.
    let mut screen = make_screen();
    let attrs = SgrAttributes::default();
    screen.move_cursor(0, 0);
    screen.print('中', attrs, true); // Unicode width 2
    let main_cell = screen.get_cell(0, 0).unwrap();
    assert_eq!(main_cell.char(), '中');
    // Cursor must have advanced by 2.
    assert_eq!(screen.cursor().col, 2);
}

#[test]
fn print_wide_char_at_last_col_wraps() {
    // Wide char does not fit at col 79 (would need cols 79 and 80). auto_wrap=true
    // should wrap the character to the next line.
    let mut screen = make_screen();
    let attrs = SgrAttributes::default();
    screen.move_cursor(0, 79);
    screen.print('字', attrs, true); // width 2
                                     // Should appear at (1, 0) after wrapping, not at (0, 79).
    let cell = screen.get_cell(1, 0).unwrap();
    assert_eq!(cell.char(), '字', "wide char must wrap to next row");
}

// ── cursor() and cursor_mut() on alternate screen ────────────────────────────

#[test]
fn cursor_ref_on_primary_screen() {
    let screen = make_screen();
    // When not in alternate mode, cursor() returns primary cursor.
    assert_eq!(screen.cursor().row, 0);
    assert_eq!(screen.cursor().col, 0);
}

#[test]
fn cursor_ref_on_alternate_screen() {
    use crate::TerminalCore;
    // Switch to alternate screen via CSI ?1049h, then verify cursor() reflects it.
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[5;10H"); // move primary cursor to (4, 9)
    term.advance(b"\x1b[?1049h"); // enter alternate screen
                                  // Alternate screen cursor starts at (0,0); primary cursor at (4,9).
    assert_eq!(
        term.screen.cursor().row,
        0,
        "alternate cursor row must start at 0"
    );
    assert_eq!(
        term.screen.cursor().col,
        0,
        "alternate cursor col must start at 0"
    );
}

#[test]
fn cursor_mut_on_primary_modifies_primary() {
    let mut screen = make_screen();
    screen.cursor_mut().row = 7;
    screen.cursor_mut().col = 12;
    assert_eq!(screen.cursor().row, 7);
    assert_eq!(screen.cursor().col, 12);
}

// ── line_feed outside scroll region ──────────────────────────────────────────

#[test]
fn line_feed_outside_scroll_region_moves_down() {
    // Set scroll region to rows 5..10; place cursor above the region at row 2.
    // LF must simply move down without scrolling.
    let mut screen = make_screen();
    screen.set_scroll_region(5, 10);
    screen.move_cursor(2, 0);
    screen.line_feed(Color::Default);
    assert_eq!(
        screen.cursor().row,
        3,
        "LF outside region must just move down"
    );
}

#[test]
fn line_feed_below_scroll_region_does_not_scroll() {
    // Cursor below the scroll region's bottom — LF moves down but does not scroll.
    let mut screen = make_screen();
    screen.set_scroll_region(0, 10);
    screen.move_cursor(15, 0);
    screen.line_feed(Color::Default);
    assert_eq!(
        screen.cursor().row,
        16,
        "LF below scroll region must just move down"
    );
}

#[test]
fn line_feed_at_screen_bottom_clamps() {
    // With full-screen scroll region (default), LF at row 23 scrolls, keeping cursor at 23.
    let mut screen = make_screen();
    screen.move_cursor(23, 0);
    screen.line_feed(Color::Default);
    assert_eq!(screen.cursor().row, 23);
}

// ── Additional coverage ───────────────────────────────────────────────────────

#[test]
fn move_cursor_rel_positive_overflow_clamps_to_last_row_and_col() {
    // move_cursor_by with offsets that would exceed screen bounds must clamp
    // row to rows-1 and col to cols-1 rather than wrapping or panicking.
    let mut screen = make_screen();
    screen.move_cursor(20, 70);
    // offset pushes both row and col well beyond the screen edge
    screen.move_cursor_by(100, 100);
    assert_eq!(screen.cursor().row, 23, "row must clamp to 23");
    assert_eq!(screen.cursor().col, 79, "col must clamp to 79");
}

#[test]
fn move_cursor_rel_negative_overflow_clamps_at_origin() {
    // move_cursor_by with large negative offsets must clamp at (0, 0).
    let mut screen = make_screen();
    screen.move_cursor(3, 5);
    screen.move_cursor_by(-100, -100);
    assert_eq!(screen.cursor().row, 0, "row must clamp at 0");
    assert_eq!(screen.cursor().col, 0, "col must clamp at 0");
}

#[test]
fn tab_from_col_exactly_at_tab_stop_jumps_to_next_stop() {
    // When the cursor is already on a tab-stop boundary (col = 16),
    // tab() must advance to the next boundary (col = 24), not stay in place.
    let mut screen = make_screen();
    screen.move_cursor(0, 16); // already a tab stop (16 % 8 == 0)
    screen.tab();
    assert_eq!(
        screen.cursor().col,
        24,
        "tab from a tab-stop boundary must jump to the NEXT stop"
    );
}

#[test]
fn line_feed_col_preserved_after_advance() {
    // LF advances the row but must NOT reset the column.
    let mut screen = make_screen();
    screen.move_cursor(0, 40);
    screen.line_feed(Color::Default);
    assert_eq!(screen.cursor().row, 1, "LF must advance row by 1");
    assert_eq!(
        screen.cursor().col,
        40,
        "LF must NOT reset col — that is CR's job"
    );
}

#[test]
fn carriage_return_row_unchanged() {
    // carriage_return() resets column to 0 but must leave the row untouched.
    let mut screen = make_screen();
    screen.move_cursor(7, 50);
    screen.carriage_return();
    assert_eq!(screen.cursor().row, 7, "CR must not change the row");
    assert_eq!(screen.cursor().col, 0, "CR must reset col to 0");
}
