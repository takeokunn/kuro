//! Dirty line tracking for the terminal screen buffer.
//!
//! Provides a `DirtySet` trait and a `BitVecDirtySet` implementation that uses
//! a compact bit-vector instead of a `HashSet<usize>`.  The bit-vector approach
//! eliminates hash-function overhead on every `insert()` call, which is the
//! hot path when printing characters to the screen.

use bitvec::prelude::*;

/// Tracks which screen rows have been modified since the last render.
pub trait DirtySet: Send + Sync {
    /// Mark `row` as dirty.
    fn insert(&mut self, row: usize);
    /// Return `true` if `row` is currently marked dirty.
    fn contains(&self, row: usize) -> bool;
    /// Iterate over all dirty row indices in ascending order.
    fn iter(&self) -> Box<dyn Iterator<Item = usize> + '_>;
    /// Clear all dirty flags.
    fn clear(&mut self);
    /// Number of dirty rows.
    fn len(&self) -> usize;
    /// `true` when no rows are dirty.
    fn is_empty(&self) -> bool;
}

/// Bit-vector backed dirty-set.
///
/// Each bit corresponds to one screen row.  The vector is grown on demand when
/// a row index beyond the current capacity is inserted.
#[derive(Debug, Clone)]
pub struct BitVecDirtySet {
    bits: BitVec,
    count: usize,
}

impl BitVecDirtySet {
    /// Create an empty set pre-allocated for `capacity` rows.
    pub fn new(capacity: usize) -> Self {
        Self {
            bits: bitvec![0; capacity],
            count: 0,
        }
    }

    /// Grow the backing vector so that index `row` is valid.
    #[inline]
    fn ensure_capacity(&mut self, row: usize) {
        if row >= self.bits.len() {
            self.bits.resize(row + 1, false);
        }
    }
}

impl DirtySet for BitVecDirtySet {
    #[inline]
    fn insert(&mut self, row: usize) {
        self.ensure_capacity(row);
        // Only increment count if the bit was previously clear.
        if !self.bits[row] {
            self.bits.set(row, true);
            self.count += 1;
        }
    }

    #[inline]
    fn contains(&self, row: usize) -> bool {
        self.bits.get(row).map(|b| *b).unwrap_or(false)
    }

    fn iter(&self) -> Box<dyn Iterator<Item = usize> + '_> {
        Box::new(self.bits.iter_ones())
    }

    #[inline]
    fn clear(&mut self) {
        self.bits.fill(false);
        self.count = 0;
    }

    #[inline]
    fn len(&self) -> usize {
        self.count
    }

    #[inline]
    fn is_empty(&self) -> bool {
        self.count == 0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
}
