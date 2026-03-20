//! Property-based tests for `crate::types::cursor` (Cursor, CursorShape)
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
            .unwrap_or_else(|_| panic!("try_from({v}) must succeed for canonical value"));
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
    assert_eq!(i64::from(shape), 0, "canonical encoding of BlinkingBlock is 0");
}
