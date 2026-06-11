#[test]
fn test_insert_range_single_element() {
    // insert_range(n, n+1) marks exactly one row.
    let mut ds = BitVecDirtySet::new(16);
    ds.insert_range(7, 8);
    assert!(ds.contains(7));
    assert!(!ds.contains(6));
    assert!(!ds.contains(8));
    assert_eq!(ds.len(), 1);
}

#[test]
fn test_iter_on_empty_set_yields_nothing() {
    let ds = BitVecDirtySet::new(8);
    let rows: Vec<usize> = ds.iter().collect();
    assert!(
        rows.is_empty(),
        "trait iter on empty set must yield nothing"
    );
}

#[test]
fn test_insert_first_and_last_row() {
    // Insert the very first (0) and very last valid index.
    let mut ds = BitVecDirtySet::new(10);
    ds.insert(0);
    ds.insert(9);
    assert_eq!(ds.len(), 2);
    let rows: Vec<usize> = ds.iter().collect();
    assert_eq!(rows, vec![0, 9]);
}

#[test]
fn test_len_matches_count_of_iter_items() {
    let mut ds = BitVecDirtySet::new(32);
    for row in (0..32usize).step_by(3) {
        ds.insert(row);
    }
    let iter_count = ds.iter().count();
    assert_eq!(
        ds.len(),
        iter_count,
        "len() must equal the number of items yielded by iter()"
    );
}

#[test]
fn test_insert_range_does_not_clear_existing_bits_outside_range() {
    // Rows outside the insert_range must remain as they were.
    let mut ds = BitVecDirtySet::new(16);
    ds.insert(0); // row outside the range
    ds.insert(15); // row outside the range
    ds.insert_range(5, 10); // marks rows 5..10
    assert!(
        ds.contains(0),
        "row 0 must still be dirty after insert_range"
    );
    assert!(
        ds.contains(15),
        "row 15 must still be dirty after insert_range"
    );
    assert_eq!(ds.len(), 2 + 5, "total must be 2 pre-existing + 5 new");
}

#[test]
fn test_shift_left_all_ones() {
    // When all rows are dirty, shift_left(1) must:
    // - still leave rows 0..(len-1) dirty (shifted from 1..len)
    // - clear the last row (shifted past end)
    let mut ds = BitVecDirtySet::new(4);
    ds.insert_range(0, 4); // all 4 dirty
    ds.shift_left(1);
    // rows 1→0, 2→1, 3→2; row 3 becomes clean
    for row in 0..3 {
        assert!(
            ds.contains(row),
            "row {row} must be dirty after shift_left(1)"
        );
    }
    assert!(!ds.contains(3), "row 3 must be clean after shift_left(1)");
    assert_eq!(ds.len(), 3);
}

#[test]
fn test_shift_right_all_ones() {
    // When all rows are dirty, shift_right(1) must:
    // - leave rows 1..len dirty (shifted from 0..len-1)
    // - clear row 0
    let mut ds = BitVecDirtySet::new(4);
    ds.insert_range(0, 4); // all 4 dirty
    ds.shift_right(1);
    assert!(!ds.contains(0), "row 0 must be clean after shift_right(1)");
    for row in 1..4 {
        assert!(
            ds.contains(row),
            "row {row} must be dirty after shift_right(1)"
        );
    }
    assert_eq!(ds.len(), 3);
}

#[test]
fn test_clone_after_insert_range() {
    let mut original = BitVecDirtySet::new(16);
    original.insert_range(3, 8);
    let clone = original.clone();
    assert_eq!(clone.len(), original.len());
    let orig_rows: Vec<usize> = original.iter().collect();
    let clone_rows: Vec<usize> = clone.iter().collect();
    assert_eq!(
        orig_rows, clone_rows,
        "clone must match original after insert_range"
    );
}

#[test]
fn test_insert_adjacent_rows_count_correct() {
    // Inserting rows 0, 1, 2 individually must give len=3, not 1.
    let mut ds = BitVecDirtySet::new(8);
    ds.insert(0);
    ds.insert(1);
    ds.insert(2);
    assert_eq!(ds.len(), 3);
    let rows: Vec<usize> = ds.iter().collect();
    assert_eq!(rows, vec![0, 1, 2]);
}

// ── Property-based tests (merged from tests/unit/grid/dirty_set.rs) ─────

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

// ── Example-based tests (complement to inline tests) ────────────────────

#[test]
fn iter_on_empty_set_yields_nothing_pbt() {
    let ds = BitVecDirtySet::new(16);
    let collected: Vec<usize> = ds.iter().collect();
    assert!(
        collected.is_empty(),
        "iter() on empty set must yield no elements"
    );
}

#[test]
fn contains_at_exact_capacity_boundary_returns_false() {
    let capacity = 8usize;
    let ds = BitVecDirtySet::new(capacity);
    assert!(
        !ds.contains(capacity),
        "contains at index == capacity must return false"
    );
    assert!(
        !ds.contains(capacity + 100),
        "contains at index far beyond capacity must return false"
    );
}

#[test]
fn insert_range_single_element_pbt() {
    let mut ds = BitVecDirtySet::new(16);
    ds.insert_range(5, 6);
    assert_eq!(ds.len(), 1);
    assert!(ds.contains(5));
    assert!(!ds.contains(4));
    assert!(!ds.contains(6));
}

#[test]
fn iter_ones_direct_matches_iter_after_shift_left() {
    let mut ds = BitVecDirtySet::new(10);
    ds.insert(3);
    ds.insert(7);
    ds.shift_left(2);
    let via_trait: Vec<usize> = ds.iter().collect();
    let via_direct: Vec<usize> = ds.iter_ones_direct().collect();
    assert_eq!(via_trait, via_direct);
    assert_eq!(via_direct, vec![1, 5]);
}

#[test]
fn clear_on_empty_set_stays_empty() {
    let mut ds = BitVecDirtySet::new(8);
    assert!(ds.is_empty());
    ds.clear();
    assert!(ds.is_empty());
    assert_eq!(ds.len(), 0);
}

#[test]
fn insert_large_index_multiple_growth_steps() {
    let mut ds = BitVecDirtySet::new(4);
    let large = 1023usize;
    ds.insert(large);
    assert!(ds.contains(large));
    assert_eq!(ds.len(), 1);
    assert!(!ds.contains(0));
    assert!(!ds.contains(large - 1));
}

#[test]
fn is_empty_reflects_state_correctly() {
    let mut ds = BitVecDirtySet::new(10);
    assert!(ds.is_empty());
    ds.insert(3);
    assert!(!ds.is_empty());
    ds.clear();
    assert!(ds.is_empty());
}

#[test]
fn iter_ones_direct_after_capacity_growth() {
    let mut ds = BitVecDirtySet::new(2);
    ds.insert(50);
    ds.insert(100);
    let result: Vec<usize> = ds.iter_ones_direct().collect();
    assert_eq!(result, vec![50, 100]);
}
