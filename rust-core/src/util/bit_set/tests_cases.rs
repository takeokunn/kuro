use super::tests_support::*;
use crate::util::bit_set::BitSet;
use std::ops::Range;

#[test]
fn set_get_and_count_track_state() {
    let mut bit_set = BitSet::new(128);
    assert!(!bit_set.get(0));
    assert_eq!(bit_set.count_ones(), 0);

    for i in [0, 63, 64] {
        bit_set.set(i, true);
    }
    ExpectedBits {
        capacity: 128,
        set: &[0, 63, 64],
        clear: &[1, 65, 127, 128],
        count_ones: 3,
    }
    .assert_matches("set/get after setting bits", &bit_set);

    bit_set.set(0, false);
    assert!(!bit_set.get(0));
    assert_eq!(bit_set.count_ones(), 2);
}

#[test]
fn iter_ones_returns_set_indices_in_order() {
    let bit_set = bit_set(200, &[1, 63, 64, 127]);
    assert_eq!(
        bit_set.iter_ones().collect::<Vec<_>>(),
        vec![1, 63, 64, 127]
    );
}

#[test]
fn fill_sets_or_clears_all_logical_bits() {
    let mut bit_set = BitSet::new(10);
    bit_set.fill(true);
    assert_eq!(bit_set.count_ones(), 10);
    bit_set.fill(false);
    assert_eq!(bit_set.count_ones(), 0);
}

#[test]
fn fill_range_cases() {
    struct Case {
        name: &'static str,
        initial_fill: bool,
        range: Range<usize>,
        value: bool,
        expected: ExpectedBits,
    }

    for case in [
        Case {
            name: "basic set",
            initial_fill: false,
            range: 2..5,
            value: true,
            expected: ExpectedBits {
                capacity: 8,
                set: &[2, 3, 4],
                clear: &[0, 1, 5],
                count_ones: 3,
            },
        },
        Case {
            name: "empty range",
            initial_fill: false,
            range: 3..3,
            value: true,
            expected: ExpectedBits {
                capacity: 8,
                set: &[],
                clear: &[0, 3, 7],
                count_ones: 0,
            },
        },
        Case {
            name: "clear subset",
            initial_fill: true,
            range: 3..6,
            value: false,
            expected: ExpectedBits {
                capacity: 8,
                set: &[0, 2, 6, 7],
                clear: &[3, 4, 5],
                count_ones: 5,
            },
        },
        Case {
            name: "cross word boundary",
            initial_fill: false,
            range: 60..68,
            value: true,
            expected: ExpectedBits {
                capacity: 128,
                set: &[60, 63, 64, 67],
                clear: &[59, 68, 127],
                count_ones: 8,
            },
        },
    ] {
        let mut bit_set = BitSet::new(case.expected.capacity);
        bit_set.fill(case.initial_fill);
        bit_set.fill_range(case.range, case.value);
        case.expected.assert_matches(case.name, &bit_set);
    }
}

#[test]
fn resize_cases_preserve_existing_bits_and_initialize_new_bits() {
    struct Case {
        name: &'static str,
        initial: BitSet,
        new_len: usize,
        value: bool,
        expected: ExpectedBits,
    }

    for case in [
        Case {
            name: "grow false",
            initial: bit_set(4, &[3]),
            new_len: 8,
            value: false,
            expected: ExpectedBits {
                capacity: 8,
                set: &[3],
                clear: &[0, 4, 7],
                count_ones: 1,
            },
        },
        Case {
            name: "grow true same word",
            initial: bit_set(4, &[1]),
            new_len: 8,
            value: true,
            expected: ExpectedBits {
                capacity: 8,
                set: &[1, 4, 7],
                clear: &[0, 2, 3],
                count_ones: 5,
            },
        },
        Case {
            name: "grow true cross word",
            initial: BitSet::new(3),
            new_len: 130,
            value: true,
            expected: ExpectedBits {
                capacity: 130,
                set: &[3, 63, 64, 129],
                clear: &[0, 1, 2, 130],
                count_ones: 127,
            },
        },
        Case {
            name: "grow true from empty partial word",
            initial: BitSet::new(0),
            new_len: 8,
            value: true,
            expected: ExpectedBits {
                capacity: 8,
                set: &[0, 7],
                clear: &[8],
                count_ones: 8,
            },
        },
        Case {
            name: "grow true from empty full word",
            initial: BitSet::new(0),
            new_len: 64,
            value: true,
            expected: ExpectedBits {
                capacity: 64,
                set: &[0, 63],
                clear: &[64],
                count_ones: 64,
            },
        },
        Case {
            name: "shrink drops high bits",
            initial: bit_set(128, &[63, 64]),
            new_len: 64,
            value: false,
            expected: ExpectedBits {
                capacity: 64,
                set: &[63],
                clear: &[64],
                count_ones: 1,
            },
        },
    ] {
        let mut bit_set = case.initial;
        bit_set.resize(case.new_len, case.value);
        case.expected.assert_matches(case.name, &bit_set);
    }
}

#[test]
fn copy_within_cases_match_memmove_direction() {
    struct Case {
        name: &'static str,
        initial: BitSet,
        src: Range<usize>,
        dst: usize,
        expected: ExpectedBits,
    }

    for case in [
        Case {
            name: "shift left",
            initial: bit_set(8, &[2, 4]),
            src: 2..8,
            dst: 0,
            expected: ExpectedBits {
                capacity: 8,
                set: &[0, 2],
                clear: &[1, 3, 5],
                count_ones: 2,
            },
        },
        Case {
            name: "shift right",
            initial: bit_set(8, &[0, 2]),
            src: 0..6,
            dst: 2,
            expected: ExpectedBits {
                capacity: 8,
                set: &[0, 2, 4],
                clear: &[1, 3, 5],
                count_ones: 3,
            },
        },
        Case {
            name: "empty range",
            initial: bit_set(8, &[2]),
            src: 3..3,
            dst: 0,
            expected: ExpectedBits {
                capacity: 8,
                set: &[2],
                clear: &[0, 3],
                count_ones: 1,
            },
        },
        Case {
            name: "same source and destination",
            initial: bit_set(8, &[3]),
            src: 3..6,
            dst: 3,
            expected: ExpectedBits {
                capacity: 8,
                set: &[3],
                clear: &[4],
                count_ones: 1,
            },
        },
    ] {
        let mut bit_set = case.initial;
        bit_set.copy_within(case.src, case.dst);
        case.expected.assert_matches(case.name, &bit_set);
    }
}
