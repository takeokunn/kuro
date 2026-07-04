use super::tests_support::*;
use crate::grid::dirty_set::DirtySet;
use crate::grid::BitVecDirtySet;
use proptest::prelude::*;

#[test]
fn insert_cases_track_membership_and_count() {
    struct Case {
        name: &'static str,
        capacity: usize,
        inserts: &'static [usize],
        expected: &'static [usize],
    }

    const CASES: &[Case] = &[
        Case {
            name: "empty",
            capacity: 8,
            inserts: &[],
            expected: &[],
        },
        Case {
            name: "single row",
            capacity: 8,
            inserts: &[3],
            expected: &[3],
        },
        Case {
            name: "idempotent insert",
            capacity: 8,
            inserts: &[5, 5, 5],
            expected: &[5],
        },
        Case {
            name: "sorts iteration",
            capacity: 24,
            inserts: &[10, 2, 7],
            expected: &[2, 7, 10],
        },
        Case {
            name: "grows beyond initial capacity",
            capacity: 4,
            inserts: &[100],
            expected: &[100],
        },
        Case {
            name: "zero capacity grows",
            capacity: 0,
            inserts: &[0],
            expected: &[0],
        },
        Case {
            name: "first and last row",
            capacity: 10,
            inserts: &[0, 9],
            expected: &[0, 9],
        },
        Case {
            name: "large index",
            capacity: 4,
            inserts: &[1023],
            expected: &[1023],
        },
    ];

    run_case_table(CASES, |case| {
        let set = set_with_rows(case.capacity, case.inserts);
        assert_rows(&set, case.expected);
        for &row in case.expected {
            assert!(set.contains(row), "{} should contain {row}", case.name);
        }
    });
}

#[test]
fn clear_cases_reset_membership_and_count() {
    let mut set = set_with_rows(24, &[0, 3]);
    set.clear();
    assert_rows(&set, &[]);
    assert!(!set.contains(0));
    assert!(!set.contains(3));

    set.clear();
    assert_rows(&set, &[]);
}

#[test]
fn contains_out_of_bounds_returns_false() {
    let set = BitVecDirtySet::new(8);
    assert!(!set.contains(8));
    assert!(!set.contains(1000));
}

#[test]
fn clone_is_independent() {
    let original = set_with_rows(16, &[3, 9]);
    let mut cloned = original.clone();

    cloned.insert(5);
    cloned.clear();

    assert_rows(&original, &[3, 9]);
    assert_rows(&cloned, &[]);
}

#[test]
fn insert_range_cases_mark_expected_rows() {
    struct Case {
        capacity: usize,
        seed: &'static [usize],
        range: (usize, usize),
        expected: &'static [usize],
    }

    const CASES: &[Case] = &[
        Case {
            capacity: 24,
            seed: &[],
            range: (2, 6),
            expected: &[2, 3, 4, 5],
        },
        Case {
            capacity: 24,
            seed: &[],
            range: (5, 5),
            expected: &[],
        },
        Case {
            capacity: 24,
            seed: &[],
            range: (7, 3),
            expected: &[],
        },
        Case {
            capacity: 24,
            seed: &[3],
            range: (2, 5),
            expected: &[2, 3, 4],
        },
        Case {
            capacity: 4,
            seed: &[],
            range: (10, 13),
            expected: &[10, 11, 12],
        },
        Case {
            capacity: 8,
            seed: &[],
            range: (0, 8),
            expected: &[0, 1, 2, 3, 4, 5, 6, 7],
        },
        Case {
            capacity: 16,
            seed: &[],
            range: (7, 8),
            expected: &[7],
        },
        Case {
            capacity: 16,
            seed: &[0, 15],
            range: (5, 10),
            expected: &[0, 5, 6, 7, 8, 9, 15],
        },
    ];

    run_case_table(CASES, |case| {
        let mut set = set_with_rows(case.capacity, case.seed);
        set.insert_range(case.range.0, case.range.1);
        assert_rows(&set, case.expected);
    });
}

#[test]
fn shift_left_cases_match_scroll_up_mapping() {
    struct Case {
        capacity: usize,
        seed: &'static [usize],
        shift: usize,
        expected: &'static [usize],
    }

    const CASES: &[Case] = &[
        Case {
            capacity: 8,
            seed: &[3, 5],
            shift: 0,
            expected: &[3, 5],
        },
        Case {
            capacity: 8,
            seed: &[2, 5],
            shift: 2,
            expected: &[0, 3],
        },
        Case {
            capacity: 8,
            seed: &[0, 1, 5],
            shift: 2,
            expected: &[3],
        },
        Case {
            capacity: 8,
            seed: &[6, 7],
            shift: 1,
            expected: &[5, 6],
        },
        Case {
            capacity: 8,
            seed: &[3],
            shift: 10,
            expected: &[],
        },
        Case {
            capacity: 8,
            seed: &[7],
            shift: 7,
            expected: &[0],
        },
        Case {
            capacity: 4,
            seed: &[0, 1, 2, 3],
            shift: 1,
            expected: &[0, 1, 2],
        },
        Case {
            capacity: 16,
            seed: &[4, 8],
            shift: 2,
            expected: &[2, 6],
        },
    ];

    run_case_table(CASES, |case| {
        let mut set = set_with_rows(case.capacity, case.seed);
        set.shift_left(case.shift);
        assert_rows(&set, case.expected);
    });
}

#[test]
fn shift_right_cases_match_scroll_down_mapping() {
    struct Case {
        capacity: usize,
        seed: &'static [usize],
        shift: usize,
        expected: &'static [usize],
    }

    const CASES: &[Case] = &[
        Case {
            capacity: 8,
            seed: &[3, 5],
            shift: 0,
            expected: &[3, 5],
        },
        Case {
            capacity: 8,
            seed: &[2, 5],
            shift: 2,
            expected: &[4, 7],
        },
        Case {
            capacity: 8,
            seed: &[5, 6, 7],
            shift: 2,
            expected: &[7],
        },
        Case {
            capacity: 8,
            seed: &[0, 1],
            shift: 2,
            expected: &[2, 3],
        },
        Case {
            capacity: 8,
            seed: &[3],
            shift: 10,
            expected: &[],
        },
        Case {
            capacity: 8,
            seed: &[0],
            shift: 7,
            expected: &[7],
        },
        Case {
            capacity: 4,
            seed: &[0, 1, 2, 3],
            shift: 1,
            expected: &[1, 2, 3],
        },
    ];

    run_case_table(CASES, |case| {
        let mut set = set_with_rows(case.capacity, case.seed);
        set.shift_right(case.shift);
        assert_rows(&set, case.expected);
    });
}

#[test]
fn left_then_right_round_trip_keeps_non_boundary_rows() {
    let mut set = set_with_rows(16, &[4, 8]);
    set.shift_left(2);
    set.shift_right(2);
    assert_rows(&set, &[4, 8]);
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(500))]

    #[test]
    fn prop_insert_idempotent(row in 0usize..100usize, repeats in 1usize..20usize) {
        let mut set = BitVecDirtySet::new(100);
        for _ in 0..repeats {
            set.insert(row);
        }
        prop_assert_eq!(set.len(), 1);
        prop_assert!(set.contains(row));
    }

    #[test]
    fn prop_len_equals_iter_count(rows in arb_rows()) {
        let set = set_with_rows(50, &rows);
        prop_assert_eq!(set.len(), set.iter().count());
        prop_assert_eq!(set.iter().collect::<Vec<_>>(), set.iter_ones_direct().collect::<Vec<_>>());
    }

    #[test]
    fn prop_contains_after_insert_and_clear(row in 0usize..100usize) {
        let mut set = BitVecDirtySet::new(100);
        set.insert(row);
        prop_assert!(set.contains(row));
        set.clear();
        prop_assert!(!set.contains(row));
        prop_assert!(set.is_empty());
    }

    #[test]
    fn prop_iter_sorted_without_duplicates(rows in arb_rows()) {
        let set = set_with_rows(50, &rows);
        let collected: Vec<usize> = set.iter().collect();
        for window in collected.windows(2) {
            prop_assert!(window[0] < window[1],
                "iter() is not strictly ascending: {} >= {}", window[0], window[1]);
        }
    }

    #[test]
    fn prop_shift_left_mapping(n in 1usize..12usize, extra in 0usize..12usize) {
        let row = n + extra;
        let mut set = set_with_rows(row + 1, &[row]);
        set.shift_left(n);
        prop_assert!(set.contains(row - n));
        prop_assert!(!set.contains(row));
    }

    #[test]
    fn prop_shift_right_mapping(n in 1usize..12usize, row in 0usize..12usize) {
        let mut set = set_with_rows(row + n + 1, &[row]);
        set.shift_right(n);
        prop_assert!(set.contains(row + n));
        prop_assert!(!set.contains(row));
    }

    #[test]
    fn prop_shift_exceeds_capacity_clears(rows in arb_rows()) {
        let capacity = 24usize;
        let mut set = BitVecDirtySet::new(capacity);
        for row in rows.iter().map(|&row| row % capacity) {
            set.insert(row);
        }
        set.shift_left(capacity);
        prop_assert!(set.is_empty());
    }

    #[test]
    fn prop_grow_beyond_initial_capacity(row in 0usize..=999usize) {
        let mut set = BitVecDirtySet::new(4);
        set.insert(row);
        prop_assert!(set.contains(row));
        prop_assert_eq!(set.len(), 1);
    }

    #[test]
    fn prop_insert_range_marks_all_in_range(lo in 0usize..40usize, hi in 0usize..40usize) {
        let (lo, hi) = if lo <= hi { (lo, hi) } else { (hi, lo) };
        let mut set = BitVecDirtySet::new(50);
        set.insert_range(lo, hi);

        for row in lo..hi {
            prop_assert!(set.contains(row), "row {row} must be dirty");
        }
        if lo > 0 {
            prop_assert!(!set.contains(lo - 1));
        }
        if hi < 49 {
            prop_assert!(!set.contains(hi));
        }
    }

    #[test]
    fn prop_insert_range_len_correct(lo in 0usize..30usize, hi in 0usize..30usize) {
        let (lo, hi) = if lo <= hi { (lo, hi) } else { (hi, lo) };
        let mut set = BitVecDirtySet::new(40);
        set.insert_range(lo, hi);
        prop_assert_eq!(set.len(), hi - lo);
    }

    #[test]
    fn prop_insert_range_empty_is_noop(lo in 0usize..50usize) {
        let mut set = BitVecDirtySet::new(50);
        set.insert_range(lo, lo);
        prop_assert!(set.is_empty());
    }
}
