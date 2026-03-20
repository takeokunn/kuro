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
