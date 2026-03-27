//! Property-based tests for `BitVecDirtySet` and the `DirtySet` trait.
//!
//! These tests complement the 18 example-based unit tests embedded in
//! `src/grid/dirty_set.rs` by verifying invariants across randomly generated
//! inputs (proptest T2 tier: 500 cases each).

use crate::grid::dirty_set::{BitVecDirtySet, DirtySet as _};
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

    #[test]
    // INVARIANT: insert_range(lo, hi) marks every index in lo..hi as dirty.
    fn prop_insert_range_marks_all_in_range(
        lo in 0usize..40usize,
        hi in 0usize..40usize,
    ) {
        let (lo, hi) = if lo <= hi { (lo, hi) } else { (hi, lo) };
        let mut ds = BitVecDirtySet::new(50);
        ds.insert_range(lo, hi);
        for i in lo..hi {
            prop_assert!(ds.contains(i), "row {i} must be dirty after insert_range({lo}, {hi})");
        }
        // Row immediately before range must be clean (if lo > 0)
        if lo > 0 {
            prop_assert!(!ds.contains(lo - 1), "row {} must be clean", lo - 1);
        }
        // Row immediately after range must be clean (if hi < capacity)
        if hi < 49 {
            prop_assert!(!ds.contains(hi), "row {} (hi) must be clean", hi);
        }
    }

    #[test]
    // INVARIANT: insert_range(lo, hi) sets len() == number of bits in lo..hi
    // (assuming the set was empty before).
    fn prop_insert_range_len_correct(
        lo in 0usize..30usize,
        hi in 0usize..30usize,
    ) {
        let (lo, hi) = if lo <= hi { (lo, hi) } else { (hi, lo) };
        let mut ds = BitVecDirtySet::new(40);
        ds.insert_range(lo, hi);
        let expected = hi - lo; // half-open range
        prop_assert_eq!(ds.len(), expected,
            "insert_range({}, {}) must produce len {}", lo, hi, expected);
    }

    #[test]
    // BOUNDARY: insert_range(lo, lo) (empty range) must leave the set unchanged.
    fn prop_insert_range_empty_is_noop(lo in 0usize..50usize) {
        let mut ds = BitVecDirtySet::new(50);
        ds.insert_range(lo, lo);
        prop_assert!(ds.is_empty(),
            "insert_range({lo}, {lo}) must be a no-op");
    }
}

// ── Example-based tests (complement to inline tests in dirty_set.rs) ──────────

#[test]
// iter() (trait, returns Box<dyn Iterator>) on an empty set must yield nothing.
fn iter_on_empty_set_yields_nothing() {
    let ds = BitVecDirtySet::new(16);
    let collected: Vec<usize> = ds.iter().collect();
    assert!(
        collected.is_empty(),
        "iter() on empty set must yield no elements"
    );
}

#[test]
// contains() at exactly index == capacity (one-past-end) must return false without panic.
fn contains_at_exact_capacity_boundary_returns_false() {
    let capacity = 8usize;
    let ds = BitVecDirtySet::new(capacity);
    // Index equal to capacity is one past the last valid index.
    assert!(
        !ds.contains(capacity),
        "contains at index == capacity must return false"
    );
    // Index well beyond capacity must also return false.
    assert!(
        !ds.contains(capacity + 100),
        "contains at index far beyond capacity must return false"
    );
}

#[test]
// insert_range(lo, lo+1) — single-element range — must mark exactly one row dirty.
fn insert_range_single_element() {
    let mut ds = BitVecDirtySet::new(16);
    ds.insert_range(5, 6); // half-open: only row 5
    assert_eq!(
        ds.len(),
        1,
        "single-element insert_range must produce len 1"
    );
    assert!(
        ds.contains(5),
        "row 5 must be dirty after insert_range(5, 6)"
    );
    assert!(!ds.contains(4), "row 4 must remain clean");
    assert!(!ds.contains(6), "row 6 (hi) must remain clean");
}

#[test]
// iter_ones_direct() after shift_left must agree with iter() (trait) on the same set.
fn iter_ones_direct_matches_iter_after_shift_left() {
    let mut ds = BitVecDirtySet::new(10);
    ds.insert(3);
    ds.insert(7);
    ds.shift_left(2); // 3→1, 7→5
    let via_trait: Vec<usize> = ds.iter().collect();
    let via_direct: Vec<usize> = ds.iter_ones_direct().collect();
    assert_eq!(
        via_trait, via_direct,
        "iter() and iter_ones_direct() must agree after shift_left"
    );
    assert_eq!(via_direct, vec![1, 5]);
}

#[test]
// clear() on an already-empty set must leave it empty without changing count.
fn clear_on_empty_set_stays_empty() {
    let mut ds = BitVecDirtySet::new(8);
    assert!(ds.is_empty());
    ds.clear();
    assert!(ds.is_empty(), "clear() on empty set must keep it empty");
    assert_eq!(ds.len(), 0, "len must remain 0 after clear() on empty set");
}

#[test]
// Inserting a very large index forces multiple doubling growth steps;
// the set must remain consistent after growth far beyond the initial capacity.
fn insert_large_index_multiple_growth_steps() {
    let mut ds = BitVecDirtySet::new(4);
    let large = 1023usize;
    ds.insert(large);
    assert!(
        ds.contains(large),
        "large index must be retrievable after growth"
    );
    assert_eq!(ds.len(), 1, "len must be 1 after inserting one large index");
    // Earlier indices must remain clean.
    assert!(
        !ds.contains(0),
        "index 0 must be clean after inserting only {large}"
    );
    assert!(!ds.contains(large - 1), "index {}-1 must be clean", large);
}

#[test]
// is_empty() must return true after inserting then clearing.
fn is_empty_reflects_state_correctly() {
    let mut ds = BitVecDirtySet::new(10);
    assert!(ds.is_empty(), "newly constructed set must be empty");
    ds.insert(3);
    assert!(!ds.is_empty(), "non-empty set must not be is_empty");
    ds.clear();
    assert!(ds.is_empty(), "set must be empty after clear()");
}

#[test]
// iter_ones_direct on a set grown beyond capacity must still yield correct indices.
fn iter_ones_direct_after_capacity_growth() {
    let mut ds = BitVecDirtySet::new(2);
    ds.insert(50);
    ds.insert(100);
    let result: Vec<usize> = ds.iter_ones_direct().collect();
    assert_eq!(
        result,
        vec![50, 100],
        "iter_ones_direct must yield grown indices in order"
    );
}
