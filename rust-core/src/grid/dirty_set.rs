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
    #[must_use]
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

    /// Shift all dirty bits left by `n` positions (for scroll-up).
    ///
    /// Content moved up, so dirty index `i` becomes `i - n`.
    /// Bits where `i < n` are lost (scrolled off screen).
    /// The bottom `n` positions become clean (new blank lines).
    #[inline]
    pub fn shift_left(&mut self, n: usize) {
        if n == 0 {
            return;
        }
        let len = self.bits.len();
        if n >= len {
            self.clear_all();
            return;
        }
        self.bits.copy_within(n..len, 0);
        for i in (len - n)..len {
            self.bits.set(i, false);
        }
        self.count = self.bits.count_ones();
    }

    /// Shift all dirty bits right by `n` positions (for scroll-down).
    ///
    /// Content moved down, so dirty index `i` becomes `i + n`.
    /// Bits where `i + n >= len` are lost (scrolled off screen).
    /// The top `n` positions become clean (new blank lines).
    #[inline]
    pub fn shift_right(&mut self, n: usize) {
        if n == 0 {
            return;
        }
        let len = self.bits.len();
        if n >= len {
            self.clear_all();
            return;
        }
        self.bits.copy_within(0..len - n, n);
        for i in 0..n {
            self.bits.set(i, false);
        }
        self.count = self.bits.count_ones();
    }

    /// Iterate over dirty row indices directly, bypassing the `DirtySet` trait's
    /// `Box<dyn Iterator>`.  Returns `bitvec::slice::IterOnes` which yields
    /// indices in ascending order without heap allocation.
    #[inline]
    #[must_use]
    pub fn iter_ones_direct(&self) -> bitvec::slice::IterOnes<'_, usize, bitvec::order::Lsb0> {
        self.bits.iter_ones()
    }

    /// Internal helper: clear all bits and reset count.
    #[inline]
    fn clear_all(&mut self) {
        self.bits.fill(false);
        self.count = 0;
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
        self.bits.get(row).is_some_and(|b| *b)
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
}
