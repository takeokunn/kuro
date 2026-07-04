//! Self-contained bit-set backed by `Vec<u64>`.
//!
//! Replaces `bitvec::BitVec` for dirty-line tracking in the terminal grid.
//! Bits are stored in little-endian word order: bit `i` lives in
//! `words[i / 64]` at position `i % 64`.

use std::ops::Range;

const WORD_BITS: usize = 64;

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
        Self {
            words,
            bit_len: capacity,
        }
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
        self.words[word_index(i)] & bit_mask(i) != 0
    }

    /// Set bit `i` to `val`. Panics if `i >= self.len()`.
    #[inline]
    pub(crate) fn set(&mut self, i: usize, val: bool) {
        debug_assert!(i < self.bit_len, "bit index out of bounds");
        if val {
            self.words[word_index(i)] |= bit_mask(i);
        } else {
            self.words[word_index(i)] &= !bit_mask(i);
        }
    }

    /// Grow (or shrink) to `new_len` bits.  New bits are initialised to `val`.
    /// Existing bits are preserved across the operation.
    pub(crate) fn resize(&mut self, new_len: usize, val: bool) {
        let old_len = self.bit_len;
        let new_word_count = words_for(new_len);
        let fill = if val { u64::MAX } else { 0u64 };
        self.words.resize(new_word_count, fill);

        if val && new_len > old_len && old_len > 0 {
            self.set_grown_bits_in_existing_tail(old_len, new_len);
        }

        self.clear_padding_bits(new_len);
        self.bit_len = new_len;
    }

    /// Count the number of set bits.
    #[inline]
    pub(crate) fn count_ones(&self) -> usize {
        self.words
            .iter()
            .map(|w| usize::try_from(w.count_ones()).expect("u64 bit count fits usize"))
            .sum()
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
            let base = wi * WORD_BITS;
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

    fn set_grown_bits_in_existing_tail(&mut self, old_len: usize, new_len: usize) {
        let Some(old_tail_word) = tail_word(old_len) else {
            return;
        };
        let new_end_in_tail_word = new_len.min(word_end(old_tail_word));
        if new_end_in_tail_word <= old_len {
            return;
        }

        self.words[old_tail_word] |= bit_range_mask(old_len, new_end_in_tail_word);
    }

    fn clear_padding_bits(&mut self, len: usize) {
        let Some(last) = tail_word(len) else {
            return;
        };
        if last < self.words.len() {
            self.words[last] &= low_bits_mask(bit_offset(len));
        }
    }
}

/// Compute number of `u64` words needed for `n` bits.
#[inline]
fn words_for(n: usize) -> usize {
    n.div_ceil(WORD_BITS)
}

#[inline]
fn word_index(i: usize) -> usize {
    i / WORD_BITS
}

#[inline]
fn bit_offset(i: usize) -> usize {
    i % WORD_BITS
}

#[inline]
fn bit_mask(i: usize) -> u64 {
    1u64 << bit_offset(i)
}

#[inline]
fn word_end(word_index: usize) -> usize {
    (word_index + 1) * WORD_BITS
}

#[inline]
fn tail_word(len: usize) -> Option<usize> {
    let tail = bit_offset(len);
    (tail != 0).then(|| word_index(len))
}

#[inline]
fn low_bits_mask(bits: usize) -> u64 {
    debug_assert!(bits < WORD_BITS);
    (1u64 << bits) - 1
}

#[inline]
fn bit_range_mask(start: usize, end: usize) -> u64 {
    debug_assert_eq!(word_index(start), word_index(end - 1));
    high_exclusive_mask(end) & !low_bits_mask(bit_offset(start))
}

#[inline]
fn high_exclusive_mask(end: usize) -> u64 {
    let offset = bit_offset(end);
    if offset == 0 {
        u64::MAX
    } else {
        low_bits_mask(offset)
    }
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
        let bit = usize::try_from(self.0.trailing_zeros()).expect("u64 bit offset fits usize");
        self.0 &= self.0 - 1; // clear lowest set bit
        Some(bit)
    }
}

#[cfg(test)]
mod tests;
