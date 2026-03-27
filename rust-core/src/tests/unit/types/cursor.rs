//! Property-based tests for `crate::types::cursor` (Cursor, `CursorShape`)
//!
//! Tests in this file complement the embedded `#[cfg(test)]` tests in
//! `src/types/cursor.rs` and add property-based coverage for mathematical
//! invariants and boundary conditions.

use crate::types::cursor::{Cursor, CursorShape};
use proptest::prelude::*;

// -------------------------------------------------------------------------
// Property-based tests
// -------------------------------------------------------------------------

proptest! {
    #![proptest_config(ProptestConfig::with_cases(1000))]

    #[test]
    // BOUNDARY: Values outside 0–6 must be rejected by TryFrom<i64>.
    // Tests the positive out-of-range side (7 and above).
    fn prop_cursor_shape_invalid_rejects_positive(v in 7i64..=1000i64) {
        prop_assert!(
            CursorShape::try_from(v).is_err(),
            "expected Err for DECSCUSR value {v}, got Ok"
        );
    }

    #[test]
    // BOUNDARY: Values outside 0–6 must be rejected by TryFrom<i64>.
    // Tests the negative side.
    fn prop_cursor_shape_invalid_rejects_negative(v in -1000i64..=-1i64) {
        prop_assert!(
            CursorShape::try_from(v).is_err(),
            "expected Err for DECSCUSR value {v}, got Ok"
        );
    }

    #[test]
    // PANIC SAFETY: move_by must never panic for any combination of i32 deltas,
    // regardless of the cursor's starting position.
    fn prop_move_by_no_panic(
        col in 0usize..=10000usize,
        row in 0usize..=10000usize,
        dx  in i32::MIN..=i32::MAX,
        dy  in i32::MIN..=i32::MAX,
    ) {
        let mut cursor = Cursor::new(col, row);
        // Must not panic — all overflow paths use saturating arithmetic.
        cursor.move_by(dx, dy);
        // Post-conditions: position fields are valid usize values (no UB).
        let _ = cursor.col;
        let _ = cursor.row;
    }

    #[test]
    // INVARIANT: move_to(col, row) sets cursor.col and cursor.row exactly.
    fn prop_move_to_sets_position(
        start_col in 0usize..=1000usize,
        start_row in 0usize..=1000usize,
        dest_col  in 0usize..=1000usize,
        dest_row  in 0usize..=1000usize,
    ) {
        let mut cursor = Cursor::new(start_col, start_row);
        cursor.move_to(dest_col, dest_row);
        prop_assert_eq!(cursor.col, dest_col);
        prop_assert_eq!(cursor.row, dest_row);
    }

    #[test]
    // INVARIANT: Cursor::new(col, row).visible is always true — new cursors
    // are visible by default.
    fn prop_new_cursor_visible_default(
        col in 0usize..=10000usize,
        row in 0usize..=10000usize,
    ) {
        let cursor = Cursor::new(col, row);
        prop_assert!(cursor.visible, "Cursor::new must default to visible=true");
    }
}

// -------------------------------------------------------------------------
// Example-based tests
// -------------------------------------------------------------------------

#[test]
// ROUNDTRIP: Canonical DECSCUSR values 0,2,3,4,5,6 must survive a
// From→TryFrom round-trip unchanged.  (Value 1 is an alias and maps back
// to 0, so it is intentionally excluded from the canonical list.)
fn test_cursor_shape_canonical_roundtrip() {
    for v in [0i64, 2, 3, 4, 5, 6] {
        let shape = CursorShape::try_from(v)
            .unwrap_or_else(|()| panic!("try_from({v}) must succeed for canonical value"));
        assert_eq!(
            i64::from(shape),
            v,
            "round-trip failed: {v} → {shape:?} → {}",
            i64::from(shape)
        );
    }
}

#[test]
// SATURATION: move_by with large negative deltas from (0,0) must clamp to
// (0,0) via saturating_sub, not wrap around or panic.
fn test_move_by_saturating() {
    let mut cursor = Cursor::new(0, 0);
    cursor.move_by(-1000, -1000);
    assert_eq!(cursor.col, 0, "col must saturate to 0");
    assert_eq!(cursor.row, 0, "row must saturate to 0");
}

#[test]
// SATURATION: Large positive deltas must saturate at usize::MAX, not panic.
fn test_move_by_saturating_positive() {
    let mut cursor = Cursor::new(usize::MAX, usize::MAX);
    // move_by takes i32 so i32::MAX is the largest positive step;
    // saturating_add(i32::MAX as usize) stays at usize::MAX.
    cursor.move_by(i32::MAX, i32::MAX);
    assert_eq!(cursor.col, usize::MAX);
    assert_eq!(cursor.row, usize::MAX);
}

#[test]
// INVARIANT: Cursor::new positions the cursor at the given column and row.
fn test_cursor_new_sets_initial_position() {
    let cursor = Cursor::new(42, 7);
    assert_eq!(cursor.col, 42);
    assert_eq!(cursor.row, 7);
    assert!(cursor.visible);
    assert_eq!(cursor.shape, CursorShape::BlinkingBlock);
    assert!(!cursor.pending_wrap);
}

#[test]
// ALIAS: DECSCUSR param 1 is an alias for BlinkingBlock; From<CursorShape>
// must encode it back as 0 (the canonical value), not 1.
fn test_cursor_shape_param1_alias_maps_to_zero() {
    let shape = CursorShape::try_from(1i64).expect("param 1 must be valid");
    assert_eq!(shape, CursorShape::BlinkingBlock);
    assert_eq!(
        i64::from(shape),
        0,
        "canonical encoding of BlinkingBlock is 0"
    );
}

// -------------------------------------------------------------------------
// New tests (Round 34B)
// -------------------------------------------------------------------------

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    // BOUNDARY: move_by with a negative delta larger than the current position
    // must clamp col/row to 0 via saturating_sub, never underflow to usize::MAX.
    fn prop_move_by_clamps_to_zero(
        col in 0usize..=500usize,
        row in 0usize..=500usize,
    ) {
        let mut cursor = Cursor::new(col, row);
        // Subtract more than the current position can hold.
        cursor.move_by(i32::MIN, i32::MIN);
        prop_assert_eq!(cursor.col, 0, "col must clamp to 0 for large negative dx");
        prop_assert_eq!(cursor.row, 0, "row must clamp to 0 for large negative dy");
    }

    #[test]
    // INVARIANT: move_to(col, row) stores the values exactly — no clamping,
    // no offset, no side-effects on other fields.
    fn prop_move_to_stores_exact_values(
        col in 0usize..=100_000usize,
        row in 0usize..=100_000usize,
    ) {
        let mut cursor = Cursor::new(0, 0);
        cursor.move_to(col, row);
        prop_assert_eq!(cursor.col, col);
        prop_assert_eq!(cursor.row, row);
    }

    #[test]
    // PANIC SAFETY: CursorShape::try_from(v) for v in 0..=6 must never panic.
    // Values 0-6 are either Ok or… actually all in-range, so all must be Ok.
    fn prop_try_from_valid_range(v in 0i64..=6i64) {
        let result = CursorShape::try_from(v);
        prop_assert!(result.is_ok(), "try_from({v}) must succeed for v in 0..=6");
    }

    #[test]
    // INVARIANT: move_by(1, 1) increments both col and row by exactly 1,
    // for any starting position where overflow is not a concern.
    fn prop_move_by_positive_increments(
        col in 0usize..=10_000usize,
        row in 0usize..=10_000usize,
    ) {
        let mut cursor = Cursor::new(col, row);
        cursor.move_by(1, 1);
        prop_assert_eq!(cursor.col, col + 1, "col must increase by exactly 1");
        prop_assert_eq!(cursor.row, row + 1, "row must increase by exactly 1");
    }
}

#[test]
// INVARIANT: Cursor::new(0, 0) has correct default field values:
// visible=true, shape=BlinkingBlock, pending_wrap=false.
fn test_cursor_default_values() {
    let cursor = Cursor::new(0, 0);
    assert_eq!(cursor.col, 0);
    assert_eq!(cursor.row, 0);
    assert!(cursor.visible, "new cursor must be visible by default");
    assert_eq!(
        cursor.shape,
        CursorShape::BlinkingBlock,
        "default shape is BlinkingBlock"
    );
    assert!(!cursor.pending_wrap, "pending_wrap must start false");
}

#[test]
// ROUNDTRIP: After move_to(col, row) and a subsequent move_to back to the
// previously recorded position, the cursor is restored to that position.
// (Cursor has no save/restore methods; this tests the move_to symmetry.)
fn test_cursor_save_restore() {
    let mut cursor = Cursor::new(10, 20);
    // Record the original position
    let saved_col = cursor.col;
    let saved_row = cursor.row;
    // Move somewhere else
    cursor.move_to(99, 99);
    assert_eq!(cursor.col, 99);
    assert_eq!(cursor.row, 99);
    // Restore by moving back to the saved values
    cursor.move_to(saved_col, saved_row);
    assert_eq!(cursor.col, 10, "col must be restored to saved value");
    assert_eq!(cursor.row, 20, "row must be restored to saved value");
}

#[test]
// FIELD: The visible field can be toggled freely — setting it to false and
// back to true must round-trip correctly.
fn test_cursor_visibility_toggle() {
    let mut cursor = Cursor::new(0, 0);
    assert!(cursor.visible);
    cursor.visible = false;
    assert!(
        !cursor.visible,
        "visible must be false after setting to false"
    );
    cursor.visible = true;
    assert!(cursor.visible, "visible must be true after restoring");
}

#[test]
// INVARIANT: CursorShape::default() returns BlinkingBlock.  This is the
// DECSCUSR 0/1 shape (blinking block), the canonical terminal default.
// Also confirms that try_from(0) and try_from(1) both yield BlinkingBlock.
fn test_cursor_shape_block_is_default() {
    assert_eq!(CursorShape::default(), CursorShape::BlinkingBlock);
    assert_eq!(
        CursorShape::try_from(0i64).unwrap(),
        CursorShape::BlinkingBlock
    );
    assert_eq!(
        CursorShape::try_from(1i64).unwrap(),
        CursorShape::BlinkingBlock
    );
}

#[test]
// INVARIANT: Cursor::new(5, 10) has col=5 and row=10 — position arguments
// are stored in (col, row) order, not swapped.
fn test_cursor_new_sets_position() {
    let cursor = Cursor::new(5, 10);
    assert_eq!(cursor.col, 5, "first argument is col");
    assert_eq!(cursor.row, 10, "second argument is row");
}
