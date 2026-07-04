use crate::util::bit_set::BitSet;

#[derive(Debug)]
pub(crate) struct ExpectedBits {
    pub(crate) capacity: usize,
    pub(crate) set: &'static [usize],
    pub(crate) clear: &'static [usize],
    pub(crate) count_ones: usize,
}

impl ExpectedBits {
    pub(crate) fn assert_matches(&self, label: &str, bit_set: &BitSet) {
        assert_eq!(bit_set.len(), self.capacity, "{label}");
        assert_eq!(bit_set.count_ones(), self.count_ones, "{label}");
        for &i in self.set {
            assert!(bit_set.get(i), "{label}: bit {i} should be set in {self:?}");
        }
        for &i in self.clear {
            assert!(
                !bit_set.get(i),
                "{label}: bit {i} should be clear in {self:?}"
            );
        }
    }
}

pub(crate) fn bit_set(capacity: usize, set: &[usize]) -> BitSet {
    let mut bit_set = BitSet::new(capacity);
    for &i in set {
        bit_set.set(i, true);
    }
    bit_set
}
