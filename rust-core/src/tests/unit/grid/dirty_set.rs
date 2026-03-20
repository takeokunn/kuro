//! Property-based tests for `BitVecDirtySet` and the `DirtySet` trait.
//!
//! These tests complement the 18 example-based unit tests embedded in
//! `src/grid/dirty_set.rs` by verifying invariants across randomly generated
//! inputs (proptest T2 tier: 500 cases each).

use crate::grid::dirty_set::{BitVecDirtySet, DirtySet};
use proptest::prelude::*;

fn arb_rows() -> impl Strategy<Value = Vec<usize>> {
    proptest::collection::vec(0usize..50usize, 0..20)
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(500))]

    #[test]
    // IDEMPOTENCE: Inserting the same row N times must yield len() == 1.
    fn prop_insert_idempotent(row in 0usize..100usize, n in 1usize..20usize) {
        let mut ds = BitVecDirtySet::new(100);
        for _ in 0..n {
            ds.insert(row);
        }
        prop_assert_eq!(ds.len(), 1);
    }

    #[test]
    // CONSISTENCY: After any sequence of inserts, len() must equal iter().count().
    fn prop_len_equals_iter_count(rows in arb_rows()) {
        let mut ds = BitVecDirtySet::new(50);
        for &r in &rows {
            ds.insert(r);
        }
        prop_assert_eq!(ds.len(), ds.iter().count());
    }

    #[test]
    // INVARIANT: contains(r) is true after insert(r) and false after clear().
    fn prop_contains_after_insert(row in 0usize..100usize) {
        let mut ds = BitVecDirtySet::new(100);
        ds.insert(row);
        prop_assert!(ds.contains(row));
        ds.clear();
        prop_assert!(!ds.contains(row));
    }

    #[test]
    // ORDERING: iter() yields values in strictly ascending order with no duplicates.
    fn prop_iter_sorted_no_duplicates(rows in arb_rows()) {
        let mut ds = BitVecDirtySet::new(50);
        for &r in &rows {
            ds.insert(r);
        }
        let collected: Vec<usize> = ds.iter().collect();
        for window in collected.windows(2) {
            prop_assert!(window[0] < window[1],
                "iter() is not strictly ascending: {} >= {}", window[0], window[1]);
        }
    }

    #[test]
    // TRANSFORMATION: shift_left(n) maps row r (>= n) to row r-n; original r is cleared.
    fn prop_shift_left_mapping(
        n in 1usize..12usize,
        extra in 0usize..12usize,
    ) {
        // r = n + extra, so r >= n is guaranteed.
        let r = n + extra;
        let capacity = r + 1;
        let mut ds = BitVecDirtySet::new(capacity);
        ds.insert(r);
        ds.shift_left(n);
        prop_assert!(ds.contains(r - n),
            "expected bit at {} after shift_left({}) of row {}", r - n, n, r);
        prop_assert!(!ds.contains(r),
            "original bit at {} should be clear after shift_left({})", r, n);
    }

    #[test]
    // TRANSFORMATION: shift_right(n) maps row r to row r+n; original r is cleared.
    fn prop_shift_right_mapping(
        n in 1usize..12usize,
        r in 0usize..12usize,
    ) {
        // Capacity must be large enough that r+n is in-bounds.
        let capacity = r + n + 1;
        let mut ds = BitVecDirtySet::new(capacity);
        ds.insert(r);
        ds.shift_right(n);
        prop_assert!(ds.contains(r + n),
            "expected bit at {} after shift_right({}) of row {}", r + n, n, r);
        prop_assert!(!ds.contains(r),
            "original bit at {} should be clear after shift_right({})", r, n);
    }

    #[test]
    // BOUNDARY: shift_left(n) where n >= capacity clears every bit (is_empty).
    fn prop_shift_exceeds_capacity_clears(rows in arb_rows()) {
        // Fixed capacity of 24; shift by 24 must clear everything.
        let capacity = 24usize;
        let mut ds = BitVecDirtySet::new(capacity);
        for r in rows.iter().map(|&r| r % capacity) {
            ds.insert(r);
        }
        ds.shift_left(capacity);
        prop_assert!(ds.is_empty(),
            "shift_left(capacity) must leave the set empty");
    }

    #[test]
    // PANIC SAFETY: Inserting any row index up to 999 must not panic.
    fn prop_grow_beyond_initial_capacity(row in 0usize..=999usize) {
        let mut ds = BitVecDirtySet::new(4);
        ds.insert(row);
        prop_assert!(ds.contains(row));
        prop_assert_eq!(ds.len(), 1);
    }
}
