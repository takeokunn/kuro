//! Hyperlink range extraction from terminal cell slices.

use crate::types::cell::{Cell, CellWidth};

use super::line::grapheme_scalar_count;

/// Extract hyperlink ranges from a line's cells.
///
/// Returns `(start_buf_offset, end_buf_offset, uri)` for each contiguous
/// run of cells sharing the same hyperlink URI.  Cells without a hyperlink
/// are skipped.  `CellWidth::Wide` placeholder cells are also skipped (the
/// hyperlink belongs to the preceding `Full` cell).
///
/// Buffer offsets use character counts (not byte offsets) — matching the
/// convention used by `face_ranges` in `fill_encode_pool`.
#[must_use]
pub fn encode_hyperlink_ranges(cells: &[Cell]) -> Vec<(usize, usize, String)> {
    let mut ranges: Vec<(usize, usize, String)> = Vec::new();
    let mut buf_offset = 0usize;
    let mut current_uri: Option<String> = None;
    let mut range_start = 0usize;

    for cell in cells {
        if cell.width == CellWidth::Wide {
            // Placeholder for second half of wide char — skip
            continue;
        }

        let cell_ref: Option<&str> = cell.hyperlink_id();

        if cell_ref != current_uri.as_deref() {
            // Emit previous range (if any)
            if let Some(prev_uri) = current_uri.take() {
                ranges.push((range_start, buf_offset, prev_uri));
            }
            if cell_ref.is_some() {
                range_start = buf_offset;
            }
            current_uri = cell_ref.map(str::to_owned);
        }

        // Advance buf_offset — match fill_encode_pool's len ≤ 2 fast path:
        // len=1 → ASCII; len=2 → U+0080..U+07FF (single scalar, 2 UTF-8 bytes).
        // len > 2 may be multi-scalar; delegate to the #[cold] helper.
        buf_offset += if cell.grapheme().len() <= 2 {
            1
        } else {
            grapheme_scalar_count(cell.grapheme())
        };
    }

    // Emit final range
    if let Some(uri) = current_uri {
        ranges.push((range_start, buf_offset, uri));
    }

    ranges
}
