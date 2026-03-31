//! Self-contained bit-set backed by `Vec<u64>`.
//!
//! Replaces `bitvec::BitVec` for dirty-line tracking in the terminal grid.
//! Bits are stored in little-endian word order: bit `i` lives in
//! `words[i / 64]` at position `i % 64`.

use std::ops::Range;

/// A compact bit-set backed by `Vec<u64>`.
#[derive(Debug, Clone)]
pub(crate) struct BitSet {
    words: Vec<u64>,
    /// Number of logically valid bits (may be less than `words.len() * 64`).
    bit_len: usize,
}

impl BitSet {
    /// Create an empty set with all `capacity` bits initialised to `false`.
    #[inline]
    #[must_use]
    pub(crate) fn new(capacity: usize) -> Self {
        let words = vec![0u64; words_for(capacity)];
        Self { words, bit_len: capacity }
    }

    /// Number of logically valid bits.
    #[inline]
    pub(crate) fn len(&self) -> usize {
        self.bit_len
    }

    /// Read bit `i`. Returns `false` if `i >= self.len()`.
    #[inline]
    pub(crate) fn get(&self, i: usize) -> bool {
        if i >= self.bit_len {
            return false;
        }
        self.words[i / 64] & (1u64 << (i % 64)) != 0
    }

    /// Set bit `i` to `val`. Panics if `i >= self.len()`.
    #[inline]
    pub(crate) fn set(&mut self, i: usize, val: bool) {
        debug_assert!(i < self.bit_len, "bit index out of bounds");
        if val {
            self.words[i / 64] |= 1u64 << (i % 64);
        } else {
            self.words[i / 64] &= !(1u64 << (i % 64));
        }
    }

    /// Grow (or shrink) to `new_len` bits.  New bits are initialised to `val`.
    /// Existing bits are preserved across the operation.
    pub(crate) fn resize(&mut self, new_len: usize, val: bool) {
        let old_len = self.bit_len;
        let new_word_count = words_for(new_len);
        let fill = if val { u64::MAX } else { 0u64 };
        self.words.resize(new_word_count, fill);

        // When growing with val=true, the last pre-existing word may be partially
        // populated.  `Vec::resize` only fills *new* words; we must set the newly
        // valid bits inside the old last word explicitly.
        if val && new_len > old_len && old_len > 0 {
            let old_tail = old_len % 64;
            if old_tail != 0 {
                // The old last word has bits [0, old_tail) holding their existing values; set
                // bits [old_tail, ...) to true only if the new length extends into them.
                let old_last = (old_len - 1) / 64;
                let new_end_in_old_word = new_len.min((old_last + 1) * 64);
                if new_end_in_old_word > old_len {
                    // OR in bits from old_tail up to new_end_in_old_word (capped at 64).
                    let hi = new_end_in_old_word % 64; // 0 means full word
                    let new_bits_mask = if hi == 0 {
                        !((1u64 << old_tail) - 1) // all bits >= old_tail
                    } else {
                        ((1u64 << hi) - 1) & !((1u64 << old_tail) - 1)
                    };
                    self.words[old_last] |= new_bits_mask;
                }
            }
        }

        // Mask out bits beyond new_len in the last word (for both shrink and grow).
        // Always use &= to cap — setting of new bits within an old partial word
        // is already handled by the explicit growth block above; new whole words
        // filled by Vec::resize(fill) are already correct.
        let tail = new_len % 64;
        if tail != 0 && !self.words.is_empty() {
            let last = new_word_count.saturating_sub(1);
            if last < self.words.len() {
                let mask = (1u64 << tail) - 1;
                self.words[last] &= mask;
            }
        }
        self.bit_len = new_len;
    }

    /// Count the number of set bits.
    #[inline]
    pub(crate) fn count_ones(&self) -> usize {
        self.words.iter().map(|w| w.count_ones() as usize).sum()
    }

    /// Set all bits to `val`.
    pub(crate) fn fill(&mut self, val: bool) {
        let fill = if val { u64::MAX } else { 0u64 };
        for w in &mut self.words {
            *w = fill;
        }
        // Mask the last partial word.
        let tail = self.bit_len % 64;
        if val && tail != 0 {
            if let Some(last) = self.words.last_mut() {
                *last = (1u64 << tail) - 1;
            }
        }
    }

    /// Set all bits in `range` to `val`.
    #[inline]
    pub(crate) fn fill_range(&mut self, range: Range<usize>, val: bool) {
        for i in range {
            self.set(i, val);
        }
    }

    /// Iterate over indices of set bits in ascending order.
    #[inline]
    pub(crate) fn iter_ones(&self) -> impl Iterator<Item = usize> + '_ {
        self.words.iter().enumerate().flat_map(|(wi, &word)| {
            let base = wi * 64;
            OnesIter(word).map(move |bit| base + bit)
        })
    }

    /// Copy bits from `src` range to position `dst`.
    ///
    /// When `src.start >= dst` copies forward; otherwise copies backward to
    /// handle overlapping regions correctly (like `memmove`).
    pub(crate) fn copy_within(&mut self, src: Range<usize>, dst: usize) {
        let len = src.end.saturating_sub(src.start);
        if len == 0 {
            return;
        }
        let src_start = src.start;
        let dst_start = dst;
        if src_start == dst_start {
            return;
        }
        if src_start > dst_start {
            for i in 0..len {
                let v = self.get(src_start + i);
                self.set(dst_start + i, v);
            }
        } else {
            for i in (0..len).rev() {
                let v = self.get(src_start + i);
                self.set(dst_start + i, v);
            }
        }
    }

}

/// Compute number of `u64` words needed for `n` bits.
#[inline]
fn words_for(n: usize) -> usize {
    n.div_ceil(64)
}

/// Iterator over positions of set bits in a single `u64` word.
struct OnesIter(u64);

impl Iterator for OnesIter {
    type Item = usize;
    #[inline]
    fn next(&mut self) -> Option<usize> {
        if self.0 == 0 {
            return None;
        }
        let bit = self.0.trailing_zeros() as usize;
        self.0 &= self.0 - 1; // clear lowest set bit
        Some(bit)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_basic_set_get() {
        let mut s = BitSet::new(64);
        assert!(!s.get(0));
        s.set(0, true);
        assert!(s.get(0));
        s.set(0, false);
        assert!(!s.get(0));
    }

    #[test]
    fn test_count_ones() {
        let mut s = BitSet::new(128);
        assert_eq!(s.count_ones(), 0);
        s.set(0, true);
        s.set(63, true);
        s.set(64, true);
        assert_eq!(s.count_ones(), 3);
    }

    #[test]
    fn test_iter_ones() {
        let mut s = BitSet::new(200);
        s.set(1, true);
        s.set(63, true);
        s.set(64, true);
        s.set(127, true);
        let ones: Vec<usize> = s.iter_ones().collect();
        assert_eq!(ones, vec![1, 63, 64, 127]);
    }

    #[test]
    fn test_fill() {
        let mut s = BitSet::new(10);
        s.fill(true);
        assert_eq!(s.count_ones(), 10);
        s.fill(false);
        assert_eq!(s.count_ones(), 0);
    }

    #[test]
    fn test_copy_within_shift_left() {
        let mut s = BitSet::new(8);
        s.set(2, true);
        s.set(4, true);
        // shift left by 2: copy [2..8] to [0..]
        s.copy_within(2..8, 0);
        // bit 0 = old bit 2 = true
        // bit 2 = old bit 4 = true
        assert!(s.get(0));
        assert!(s.get(2));
    }

    #[test]
    fn test_copy_within_shift_right() {
        let mut s = BitSet::new(8);
        s.set(0, true);
        s.set(2, true);
        // shift right by 2: copy [0..6] to [2..]
        s.copy_within(0..6, 2);
        assert!(s.get(2)); // old bit 0
        assert!(s.get(4)); // old bit 2
    }

    #[test]
    fn test_resize_grow() {
        let mut s = BitSet::new(4);
        s.set(3, true);
        s.resize(8, false);
        assert_eq!(s.bit_len, 8);
        assert!(s.get(3));
        assert!(!s.get(4));
    }

    #[test]
    fn test_resize_grow_val_true_same_word() {
        // Grow from 4 bits to 8 bits with val=true — bits [4..8) must be set
        // while the pre-existing bits [0..4) must keep their original values.
        let mut s = BitSet::new(4);
        s.set(1, true);  // only bit 1 is set
        s.resize(8, true);
        assert_eq!(s.bit_len, 8);
        assert!(!s.get(0)); // was false, must stay false
        assert!(s.get(1));  // was true, must stay true
        assert!(!s.get(2)); // was false, must stay false
        assert!(!s.get(3)); // was false, must stay false
        assert!(s.get(4));  // new bit, val=true
        assert!(s.get(7));  // new bit, val=true
    }

    #[test]
    fn test_resize_grow_val_true_cross_word() {
        // Grow from 3 bits (< 1 word) to 130 bits (> 2 words) with val=true.
        let mut s = BitSet::new(3);
        s.resize(130, true);
        assert_eq!(s.bit_len, 130);
        // Original bits [0..3) were false (never set); must stay false.
        assert!(!s.get(0));
        assert!(!s.get(1));
        assert!(!s.get(2));
        // New bits [3..130) must be true.
        assert!(s.get(3));
        assert!(s.get(63));
        assert!(s.get(64));
        assert!(s.get(129));
        assert!(!s.get(130)); // out of range → false
    }

    #[test]
    fn test_resize_grow_val_true_from_empty() {
        // Growing from 0 bits skips the partial-word OR block (old_len == 0 guard).
        // Vec::resize fills new words with u64::MAX; the tail-mask caps to new_len.
        let mut s = BitSet::new(0);
        s.resize(8, true);
        assert_eq!(s.bit_len, 8);
        assert_eq!(s.count_ones(), 8);
        for i in 0..8 {
            assert!(s.get(i), "bit {i} should be set");
        }
        assert!(!s.get(8)); // out of range → false

        // Also test an exact word boundary (64 bits) — tail == 0, no mask step.
        let mut s2 = BitSet::new(0);
        s2.resize(64, true);
        assert_eq!(s2.bit_len, 64);
        assert_eq!(s2.count_ones(), 64);
        assert!(s2.get(0));
        assert!(s2.get(63));
        assert!(!s2.get(64)); // out of range → false
    }
}
