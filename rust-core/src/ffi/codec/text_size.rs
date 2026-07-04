//! Text-size (Kitty OSC 66) range extraction from terminal cell slices.

use crate::types::cell::{Cell, CellWidth};

use super::line::grapheme_scalar_count;

/// Extract text-size ranges from a line's cells.
///
/// Returns `(start_buf_offset, end_buf_offset, scaled_permille)` for each
/// contiguous run of cells sharing the same effective text size.  Cells with
/// no text size (the normal/default sizing) are skipped, as are
/// `CellWidth::Wide` placeholder cells (the sizing belongs to the preceding
/// `Full` cell).
///
/// `scaled_permille` is the effective multiplier ×1000:
/// `scale * max(numerator, 1) / max(denominator, 1)` (see
/// [`crate::types::cell::TextSize::scaled_permille`]).  A normal cell would be
/// `1000`; such cells are never emitted because they carry no `TextSize`.
///
/// Buffer offsets use character counts (not byte offsets) — matching the
/// convention used by `face_ranges` in `fill_encode_pool` and
/// `encode_hyperlink_ranges`.
#[must_use]
pub fn encode_text_size_ranges(cells: &[Cell]) -> Vec<(usize, usize, u32)> {
    let mut ranges: Vec<(usize, usize, u32)> = Vec::new();
    let mut buf_offset = 0usize;
    let mut current: Option<u32> = None;
    let mut range_start = 0usize;

    for cell in cells {
        if cell.width == CellWidth::Wide {
            // Placeholder for second half of a wide char — skip.
            continue;
        }

        let permille: Option<u32> = cell.text_size().map(|ts| ts.scaled_permille());

        if permille != current {
            // Emit previous range (if any).
            if let Some(prev) = current.take() {
                ranges.push((range_start, buf_offset, prev));
            }
            if permille.is_some() {
                range_start = buf_offset;
            }
            current = permille;
        }

        // Advance buf_offset — same len ≤ 2 fast path as fill_encode_pool.
        buf_offset += if cell.grapheme().len() <= 2 {
            1
        } else {
            grapheme_scalar_count(cell.grapheme())
        };
    }

    // Emit final range.
    if let Some(p) = current {
        ranges.push((range_start, buf_offset, p));
    }

    ranges
}
