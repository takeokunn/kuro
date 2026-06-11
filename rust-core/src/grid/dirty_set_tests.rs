#[test]
fn test_insert_and_contains() {
    let mut ds = BitVecDirtySet::new(24);
    assert!(!ds.contains(0));
    ds.insert(0);
    assert!(ds.contains(0));
    assert!(!ds.contains(1));
}

#[test]
fn test_insert_idempotent() {
    let mut ds = BitVecDirtySet::new(24);
    ds.insert(5);
    ds.insert(5);
    assert_eq!(ds.len(), 1);
}

#[test]
fn test_clear() {
    let mut ds = BitVecDirtySet::new(24);
    ds.insert(0);
    ds.insert(3);
    ds.clear();
    assert!(ds.is_empty());
    assert!(!ds.contains(0));
    assert!(!ds.contains(3));
}

#[test]
fn test_iter_sorted() {
    let mut ds = BitVecDirtySet::new(24);
    ds.insert(10);
    ds.insert(2);
    ds.insert(7);
    let rows: Vec<usize> = ds.iter().collect();
    assert_eq!(rows, vec![2, 7, 10]);
}

#[test]
fn test_grow_beyond_capacity() {
    let mut ds = BitVecDirtySet::new(4);
    // Insert beyond initial capacity — should not panic.
    ds.insert(100);
    assert!(ds.contains(100));
    assert_eq!(ds.len(), 1);
}

#[test]
fn test_len_and_is_empty() {
    let mut ds = BitVecDirtySet::new(8);
    assert!(ds.is_empty());
    ds.insert(0);
    ds.insert(1);
    assert_eq!(ds.len(), 2);
    assert!(!ds.is_empty());
}

#[test]
fn test_shift_left_basic() {
    let mut ds = BitVecDirtySet::new(8);
    ds.insert(2);
    ds.insert(5);
    ds.shift_left(2);
    // 2→0, 5→3
    assert!(ds.contains(0));
    assert!(ds.contains(3));
    assert!(!ds.contains(2));
    assert!(!ds.contains(5));
    assert_eq!(ds.len(), 2);
}

#[test]
fn test_shift_left_drops_top_bits() {
    let mut ds = BitVecDirtySet::new(8);
    ds.insert(0);
    ds.insert(1);
    ds.insert(5);
    ds.shift_left(2);
    // 0 and 1 are lost (shifted past index 0), 5→3
    assert!(ds.contains(3));
    assert_eq!(ds.len(), 1);
}

#[test]
fn test_shift_left_clears_tail() {
    let mut ds = BitVecDirtySet::new(8);
    ds.insert(6);
    ds.insert(7);
    ds.shift_left(1);
    // 6→5, 7→6, position 7 should be clean
    assert!(ds.contains(5));
    assert!(ds.contains(6));
    assert!(!ds.contains(7));
    assert_eq!(ds.len(), 2);
}

#[test]
fn test_shift_left_exceeds_len() {
    let mut ds = BitVecDirtySet::new(8);
    ds.insert(3);
    ds.shift_left(10);
    assert!(ds.is_empty());
}

#[test]
fn test_shift_right_basic() {
    let mut ds = BitVecDirtySet::new(8);
    ds.insert(2);
    ds.insert(5);
    ds.shift_right(2);
    // 2→4, 5→7
    assert!(ds.contains(4));
    assert!(ds.contains(7));
    assert!(!ds.contains(2));
    assert!(!ds.contains(5));
    assert_eq!(ds.len(), 2);
}

#[test]
fn test_shift_right_drops_bottom_bits() {
    let mut ds = BitVecDirtySet::new(8);
    ds.insert(5);
    ds.insert(6);
    ds.insert(7);
    ds.shift_right(2);
    // 6 and 7 are lost (shifted past end), 5→7
    assert!(ds.contains(7));
    assert_eq!(ds.len(), 1);
}

#[test]
fn test_shift_right_clears_head() {
    let mut ds = BitVecDirtySet::new(8);
    ds.insert(0);
    ds.insert(1);
    ds.shift_right(2);
    // 0→2, 1→3, positions 0 and 1 should be clean
    assert!(ds.contains(2));
    assert!(ds.contains(3));
    assert!(!ds.contains(0));
    assert!(!ds.contains(1));
    assert_eq!(ds.len(), 2);
}

#[test]
fn test_shift_right_exceeds_len() {
    let mut ds = BitVecDirtySet::new(8);
    ds.insert(3);
    ds.shift_right(10);
    assert!(ds.is_empty());
}

#[test]
fn test_shift_zero_is_noop() {
    let mut ds = BitVecDirtySet::new(8);
    ds.insert(3);
    ds.insert(5);
    ds.shift_left(0);
    assert!(ds.contains(3));
    assert!(ds.contains(5));
    assert_eq!(ds.len(), 2);
    ds.shift_right(0);
    assert!(ds.contains(3));
    assert!(ds.contains(5));
    assert_eq!(ds.len(), 2);
}

#[test]
fn test_insert_range_basic() {
    let mut ds = BitVecDirtySet::new(24);
    ds.insert_range(2, 6); // marks rows 2,3,4,5 (half-open)
    for row in 2..6 {
        assert!(
            ds.contains(row),
            "row {row} should be dirty after insert_range"
        );
    }
    assert!(!ds.contains(1));
    assert!(!ds.contains(6));
    assert_eq!(ds.len(), 4);
}

#[test]
fn test_insert_range_empty_is_noop() {
    let mut ds = BitVecDirtySet::new(24);
    ds.insert_range(5, 5); // lo == hi → empty range
    assert!(ds.is_empty());
    ds.insert_range(7, 3); // lo > hi → empty range
    assert!(ds.is_empty());
}

#[test]
fn test_insert_range_idempotent_count() {
    let mut ds = BitVecDirtySet::new(24);
    ds.insert(3);
    ds.insert_range(2, 5); // overlaps row 3 already set
    // rows 2, 3, 4 — count must be 3, not 4
    assert_eq!(ds.len(), 3);
}

#[test]
fn test_insert_range_grows_capacity() {
    let mut ds = BitVecDirtySet::new(4);
    ds.insert_range(10, 13); // beyond initial capacity
    assert!(ds.contains(10));
    assert!(ds.contains(12));
    assert!(!ds.contains(13));
    assert_eq!(ds.len(), 3);
}

#[test]
fn test_iter_ones_direct_matches_iter() {
    let mut ds = BitVecDirtySet::new(16);
    ds.insert(1);
    ds.insert(8);
    ds.insert(15);
    let via_trait: Vec<usize> = ds.iter().collect();
    let via_direct: Vec<usize> = ds.iter_ones_direct().collect();
    assert_eq!(via_trait, via_direct);
    assert_eq!(via_direct, vec![1, 8, 15]);
}

#[test]
fn test_contains_out_of_bounds_returns_false() {
    let ds = BitVecDirtySet::new(8);
    // Querying a row beyond capacity must not panic and must return false.
    assert!(!ds.contains(1000));
}

#[test]
fn test_zero_capacity_construction() {
    let mut ds = BitVecDirtySet::new(0);
    assert!(ds.is_empty());
    // Inserting into a zero-capacity set must grow without panic.
    ds.insert(0);
    assert!(ds.contains(0));
    assert_eq!(ds.len(), 1);
}

// ── Additional coverage ───────────────────────────────────────────────────

#[test]
fn test_clone_is_independent() {
    // Clone must produce an independent copy — mutations to one must not
    // affect the other.
    let mut original = BitVecDirtySet::new(16);
    original.insert(3);
    original.insert(9);
    let mut cloned = original.clone();
    // Mutate the clone.
    cloned.insert(5);
    cloned.clear();
    // Original must still have its rows.
    assert!(original.contains(3));
    assert!(original.contains(9));
    assert_eq!(original.len(), 2);
    // Clone must be empty after clear.
    assert!(cloned.is_empty());
}

#[test]
fn test_iter_ones_direct_on_empty_set() {
    let ds = BitVecDirtySet::new(16);
    assert!(
        ds.iter_ones_direct().next().is_none(),
        "iter_ones_direct on empty set must yield nothing"
    );
}

#[test]
fn test_shift_left_by_one_boundary() {
    // Shift by exactly 1: row 0 is lost, row 1 → 0, row 7 → 6.
    let mut ds = BitVecDirtySet::new(8);
    ds.insert(0); // will be lost (shifted past index 0)
    ds.insert(1); // → 0
    ds.insert(7); // → 6
    ds.shift_left(1);
    // After shift: rows 0 and 6 are dirty; original row 0 is gone.
    assert!(ds.contains(0), "row 1 → 0 after shift_left(1)");
    assert!(ds.contains(6), "row 7 → 6 after shift_left(1)");
    assert!(!ds.contains(7), "row 7 must be clean after shift");
    assert_eq!(ds.len(), 2);
}

#[test]
fn test_shift_left_by_len_minus_one() {
    // Shift by len-1: only the last bit survives at position 0.
    let mut ds = BitVecDirtySet::new(8);
    ds.insert(7); // only the top bit
    ds.shift_left(7);
    assert!(ds.contains(0), "row 7 → 0 after shift_left(7)");
    assert_eq!(ds.len(), 1);
}

#[test]
fn test_shift_right_by_len_minus_one() {
    // Shift by len-1: only index 0 survives, at the last position.
    let mut ds = BitVecDirtySet::new(8);
    ds.insert(0);
    ds.shift_right(7);
    assert!(ds.contains(7), "row 0 → 7 after shift_right(7)");
    assert_eq!(ds.len(), 1);
}

#[test]
fn test_insert_range_full_range() {
    // insert_range covering the entire capacity marks every row dirty.
    let mut ds = BitVecDirtySet::new(8);
    ds.insert_range(0, 8);
    assert_eq!(ds.len(), 8, "all 8 rows must be dirty");
    for row in 0..8 {
        assert!(ds.contains(row), "row {row} must be dirty");
    }
}

#[test]
fn test_insert_range_then_clear_resets_count() {
    // Inserting a range then clearing must reset len to 0.
    let mut ds = BitVecDirtySet::new(16);
    ds.insert_range(4, 12);
    assert_eq!(ds.len(), 8);
    ds.clear();
    assert_eq!(ds.len(), 0);
    assert!(ds.is_empty());
    for row in 4..12 {
        assert!(!ds.contains(row), "row {row} must not be dirty after clear");
    }
}

// ── Additional coverage ────────────────────────────────────────────────────

#[test]
fn test_insert_single_row_then_shift_left_by_exact_amount() {
    // Shifting left by exactly the row index moves it to position 0.
    let mut ds = BitVecDirtySet::new(16);
    ds.insert(5);
    ds.shift_left(5);
    assert!(ds.contains(0), "row 5 must land at 0 after shift_left(5)");
    assert!(!ds.contains(5), "original row 5 must be clean after shift");
    assert_eq!(ds.len(), 1);
}

#[test]
fn test_shift_left_then_shift_right_round_trip() {
    // shift_left(n) followed by shift_right(n) is a round-trip only when
    // none of the bits are near the boundaries (would be lost).
    let mut ds = BitVecDirtySet::new(16);
    ds.insert(4);
    ds.insert(8);
    ds.shift_left(2); // 4→2, 8→6
    ds.shift_right(2); // 2→4, 6→8
    assert!(
        ds.contains(4),
        "row 4 must survive left-then-right round-trip"
    );
    assert!(
        ds.contains(8),
        "row 8 must survive left-then-right round-trip"
    );
    assert_eq!(ds.len(), 2);
}

include!("dirty_set_tests2.rs");
