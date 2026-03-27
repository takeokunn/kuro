//! Unit tests for `Screen` alternate screen methods (alternate.rs):
//! `switch_to_alternate`, `switch_to_primary`, `is_alternate_screen_active`.

use crate::grid::screen::Screen;
use crate::types::cell::SgrAttributes;
use proptest::prelude::*;

fn make_screen() -> Screen {
    Screen::new(24, 80)
}

// ---------------------------------------------------------------------------
// is_alternate_screen_active — initial state
// ---------------------------------------------------------------------------

#[test]
fn alternate_initially_inactive() {
    let s = make_screen();
    assert!(
        !s.is_alternate_screen_active(),
        "alternate screen must be inactive on construction"
    );
}

// ---------------------------------------------------------------------------
// switch_to_alternate
// ---------------------------------------------------------------------------

#[test]
fn switch_to_alternate_activates_flag() {
    let mut s = make_screen();
    s.switch_to_alternate();
    assert!(s.is_alternate_screen_active());
}

#[test]
fn switch_to_alternate_is_idempotent() {
    let mut s = make_screen();
    s.switch_to_alternate();
    s.switch_to_alternate(); // second call must be a no-op
    assert!(s.is_alternate_screen_active());
}

#[test]
fn switch_to_alternate_cursor_starts_at_origin() {
    let mut s = make_screen();
    // Move primary cursor away
    s.move_cursor(10, 20);
    s.switch_to_alternate();
    // Alternate screen's cursor must start at (0, 0)
    assert_eq!(s.cursor().row, 0, "alternate cursor row must start at 0");
    assert_eq!(s.cursor().col, 0, "alternate cursor col must start at 0");
}

#[test]
fn switch_to_alternate_clears_content() {
    let mut s = make_screen();
    // Write something on the primary, then switch
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    s.print('X', attrs, true);

    s.switch_to_alternate();

    // Alternate screen (0, 0) must be blank, not 'X'
    assert_eq!(
        s.get_cell(0, 0).unwrap().char(),
        ' ',
        "alternate screen must be blank after switch"
    );
}

#[test]
fn switch_to_alternate_saves_primary_cursor() {
    let mut s = make_screen();
    s.move_cursor(7, 15);
    s.switch_to_alternate();
    // Switch back and verify cursor was restored
    s.switch_to_primary();
    assert_eq!(s.cursor().row, 7);
    assert_eq!(s.cursor().col, 15);
}

// ---------------------------------------------------------------------------
// switch_to_primary
// ---------------------------------------------------------------------------

#[test]
fn switch_to_primary_deactivates_flag() {
    let mut s = make_screen();
    s.switch_to_alternate();
    s.switch_to_primary();
    assert!(!s.is_alternate_screen_active());
}

#[test]
fn switch_to_primary_is_idempotent_when_not_alternate() {
    let mut s = make_screen();
    // Calling switch_to_primary when primary is already active must be a no-op
    s.switch_to_primary();
    assert!(!s.is_alternate_screen_active());
}

#[test]
fn switch_to_primary_restores_cursor() {
    let mut s = make_screen();
    s.move_cursor(3, 12);
    s.switch_to_alternate();
    s.move_cursor(1, 1); // move cursor on alt screen
    s.switch_to_primary();
    // Primary cursor must be at the saved position, not alt's (1, 1)
    assert_eq!(s.cursor().row, 3);
    assert_eq!(s.cursor().col, 12);
}

// ---------------------------------------------------------------------------
// Content isolation between primary and alternate
// ---------------------------------------------------------------------------

#[test]
fn primary_content_unaffected_by_alternate_writes() {
    let mut s = make_screen();
    let attrs = SgrAttributes::default();

    // Write 'P' on primary at (0, 0)
    s.move_cursor(0, 0);
    s.print('P', attrs, true);

    // Switch to alternate, write 'A' at (0, 0)
    s.switch_to_alternate();
    s.move_cursor(0, 0);
    s.print('A', attrs, true);

    // Switch back: primary cell must still be 'P'
    s.switch_to_primary();
    assert_eq!(
        s.get_cell(0, 0).unwrap().char(),
        'P',
        "primary content must survive alternate screen session"
    );
}

#[test]
fn alternate_content_unaffected_by_primary_writes_after_switch() {
    let mut s = make_screen();
    let attrs = SgrAttributes::default();

    // Set up alternate with 'A'
    s.switch_to_alternate();
    s.move_cursor(0, 0);
    s.print('A', attrs, true);

    // Go back to primary, write 'P' there
    s.switch_to_primary();
    s.move_cursor(0, 0);
    s.print('P', attrs, true);

    // Re-enter alternate — its content must be blank (alt is always cleared on entry)
    s.switch_to_alternate();
    assert_eq!(
        s.get_cell(0, 0).unwrap().char(),
        ' ',
        "alternate screen is always cleared on switch_to_alternate"
    );
}

#[test]
fn alternate_screen_dimensions_match_primary() {
    let mut s = make_screen();
    s.switch_to_alternate();
    assert_eq!(s.rows(), 24);
    assert_eq!(s.cols(), 80);
}

// ---------------------------------------------------------------------------
// PBT
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Dirty state across screen switches
// ---------------------------------------------------------------------------

#[test]
fn switch_to_alternate_marks_alternate_full_dirty() {
    // switch_to_alternate must mark the alternate buffer as full-dirty so the
    // render cycle repaints the whole screen on entry.
    let mut s = make_screen();
    s.switch_to_alternate();
    assert!(
        s.is_full_dirty(),
        "alternate screen must be full-dirty immediately after switch_to_alternate"
    );
}

#[test]
fn switch_to_primary_marks_primary_full_dirty() {
    // switch_to_primary must mark the primary buffer as full-dirty so the
    // render cycle repaints the whole screen on return.
    let mut s = make_screen();
    s.switch_to_alternate();
    // Consume the alt full-dirty.
    let _ = s.take_dirty_lines();
    s.switch_to_primary();
    assert!(
        s.is_full_dirty(),
        "primary screen must be full-dirty after returning from alternate"
    );
}

#[test]
fn take_dirty_lines_on_alternate_drains_alt_dirty() {
    // take_dirty_lines() while alternate is active must drain the alternate
    // buffer's dirty set, not the primary's.
    let mut s = make_screen();
    s.switch_to_alternate();
    // Alternate is full-dirty on entry; take_dirty_lines() must return all rows.
    let dirty = s.take_dirty_lines();
    assert_eq!(
        dirty.len(),
        24,
        "take_dirty_lines on alternate must return all 24 rows"
    );
    // After drain, alternate must be clean.
    assert!(
        !s.is_full_dirty(),
        "alternate must not be full-dirty after take_dirty_lines"
    );
}

#[test]
fn switch_to_alternate_saves_scroll_region_then_restores() {
    // switch_to_alternate saves the primary scroll region; switch_to_primary
    // restores it.
    let mut s = make_screen();
    // Set a custom scroll region on the primary.
    s.set_scroll_region(3, 18);
    let saved_top = s.get_scroll_region().top;
    let saved_bottom = s.get_scroll_region().bottom;

    s.switch_to_alternate();
    s.switch_to_primary();

    // Scroll region must have been restored.
    assert_eq!(
        s.get_scroll_region().top,
        saved_top,
        "scroll_region.top must be restored after returning from alternate"
    );
    assert_eq!(
        s.get_scroll_region().bottom,
        saved_bottom,
        "scroll_region.bottom must be restored after returning from alternate"
    );
}

#[test]
fn cursor_position_isolated_between_primary_and_alternate() {
    // Moving the cursor on the alternate screen must not affect the saved
    // primary cursor, and vice-versa.
    let mut s = make_screen();
    // Primary cursor at (10, 30).
    s.move_cursor(10, 30);
    s.switch_to_alternate();
    // Move cursor on the alternate to an entirely different position.
    s.move_cursor(5, 7);
    assert_eq!(s.cursor().row, 5, "alternate cursor row must be 5");
    assert_eq!(s.cursor().col, 7, "alternate cursor col must be 7");
    // Return to primary — must get back (10, 30), not (5, 7).
    s.switch_to_primary();
    assert_eq!(
        s.cursor().row,
        10,
        "primary cursor row must be 10 after returning from alternate"
    );
    assert_eq!(
        s.cursor().col,
        30,
        "primary cursor col must be 30 after returning from alternate"
    );
}

#[test]
fn multiple_alt_cycles_restore_cursor_each_time() {
    // Performing two full alternate cycles in succession must restore the
    // primary cursor accurately on each return.
    let mut s = Screen::new(24, 80);
    let attrs = SgrAttributes::default();

    // First cycle — set primary cursor to (3, 7).
    s.move_cursor(3, 7);
    s.switch_to_alternate();
    s.switch_to_primary();
    assert_eq!(s.cursor().row, 3, "first cycle: cursor.row must be 3");
    assert_eq!(s.cursor().col, 7, "first cycle: cursor.col must be 7");

    // Second cycle — move primary to (15, 60) before entering.
    s.move_cursor(15, 60);
    s.switch_to_alternate();
    // Write something on alternate to ensure state divergence.
    s.print('Q', attrs, true);
    s.switch_to_primary();
    assert_eq!(s.cursor().row, 15, "second cycle: cursor.row must be 15");
    assert_eq!(s.cursor().col, 60, "second cycle: cursor.col must be 60");
}

// ---------------------------------------------------------------------------
// PBT
// ---------------------------------------------------------------------------

proptest! {
    #![proptest_config(ProptestConfig::with_cases(64))]

    #[test]
    // INVARIANT: after enter+exit cycle, primary content at (0,0) is preserved
    fn prop_primary_content_survives_alt_cycle(ch in proptest::char::range('A', 'Z')) {
        let mut s = Screen::new(24, 80);
        let attrs = SgrAttributes::default();

        // Write ch on primary at (0, 0)
        s.move_cursor(0, 0);
        s.print(ch, attrs, true);

        // Full alternate cycle
        s.switch_to_alternate();
        s.switch_to_primary();

        prop_assert_eq!(s.get_cell(0, 0).unwrap().char(), ch);
    }

    #[test]
    // INVARIANT: after enter+exit, is_alternate_screen_active() is false
    fn prop_not_alternate_after_full_cycle(rows in 4u16..=30u16, cols in 10u16..=100u16) {
        let mut s = Screen::new(rows, cols);
        s.switch_to_alternate();
        s.switch_to_primary();
        prop_assert!(!s.is_alternate_screen_active());
    }

    #[test]
    // INVARIANT: saved cursor row/col survive alternate cycle
    fn prop_cursor_restored_after_alt_cycle(
        row in 0usize..24usize,
        col in 0usize..80usize,
    ) {
        let mut s = Screen::new(24, 80);
        s.move_cursor(row, col);
        s.switch_to_alternate();
        s.switch_to_primary();
        prop_assert_eq!(s.cursor().row, row);
        prop_assert_eq!(s.cursor().col, col);
    }
}
