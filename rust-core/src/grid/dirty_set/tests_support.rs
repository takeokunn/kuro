use crate::grid::dirty_set::DirtySet;
use crate::grid::BitVecDirtySet;

use proptest::prelude::*;

pub(crate) fn set_with_rows(capacity: usize, rows: &[usize]) -> BitVecDirtySet {
    let mut set = BitVecDirtySet::new(capacity);
    for &row in rows {
        set.insert(row);
    }
    set
}

pub(crate) fn rows(set: &BitVecDirtySet) -> Vec<usize> {
    set.iter().collect()
}

pub(crate) fn assert_rows(set: &BitVecDirtySet, expected: &[usize]) {
    assert_eq!(rows(set), expected);
    assert_eq!(set.iter_ones_direct().collect::<Vec<_>>(), expected);
    assert_eq!(set.len(), expected.len());
    assert_eq!(set.is_empty(), expected.is_empty());
}

pub(crate) fn run_case_table<C, F>(cases: &[C], mut f: F)
where
    F: FnMut(&C),
{
    for case in cases {
        f(case);
    }
}

pub(crate) fn arb_rows() -> impl Strategy<Value = Vec<usize>> {
    proptest::collection::vec(0usize..50usize, 0..20)
}
