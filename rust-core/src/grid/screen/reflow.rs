//! Soft-wrap reflow (rewrap) on terminal width change.
//!
//! When a terminal's width changes, naively truncating/padding each physical
//! row destroys the soft-wrap continuity that DECAWM auto-wrap established
//! (`Line::wrapped == true` means the next physical row continues this one with
//! no explicit newline between them).  Real terminals (kitty, wezterm, foot,
//! iTerm2) instead *reflow*: they coalesce runs of soft-wrapped physical rows
//! back into their original **logical** lines, then re-split each logical line
//! at the new width.
//!
//! This module implements that for the PRIMARY screen content + scrollback.
//! The alternate screen is never reflowed (fullscreen apps redraw themselves),
//! and height-only changes (`new_cols == old_cols`) skip reflow entirely.
//!
//! Algorithm (see [`reflow_primary`]):
//! 1. Concatenate scrollback + primary rows into one chronological sequence.
//! 2. Coalesce soft-wrap runs into logical lines (each carries the full cell
//!    vector up to its logical end; the trailing blank padding on a logical
//!    line's final physical row is trimmed so the rewrap doesn't preserve
//!    spurious spaces).
//! 3. Re-split each logical line into physical rows at `new_cols`, marking
//!    `wrapped = true` on every physical row except the last of each logical
//!    line.  A wide character (`CellWidth::Full` + `CellWidth::Wide` pair) is
//!    never split across the right margin: it is pushed to the next physical
//!    row, leaving the trailing cell blank exactly as the printer does.
//! 4. The last `new_rows` physical rows become the live screen; the remainder
//!    becomes scrollback (capped to `scrollback_max_lines`).
//! 5. The cursor's logical (line, offset) position — captured before the
//!    rewrap — is recomputed into a physical (row, col) afterwards.

use super::{Cell, CellWidth, Line, Screen};

/// A logical line: the concatenated cells of a soft-wrap run, plus the
/// cursor's offset within it when the cursor fell on this logical line.
struct LogicalLine {
    cells: Vec<Cell>,
    /// `Some(offset)` when the (pre-reflow) cursor sat on this logical line;
    /// `offset` is the column index into `cells` (clamped to `cells.len()`).
    cursor_offset: Option<usize>,
}

/// Return the number of trailing cells that are "blank padding": a default
/// (space, default attrs, no extras, `Half` width) cell.  Used to trim the
/// final physical row of a logical line so the rewrap does not carry spurious
/// trailing spaces.  Soft-wrapped (non-final) rows are never trimmed — their
/// trailing cells are real content that filled the right margin.
#[inline]
fn trailing_blank_len(cells: &[Cell]) -> usize {
    let blank = Cell::default();
    cells.iter().rev().take_while(|c| **c == blank).count()
}

/// True when `cell` is the left half (`Full`) of a wide character pair.
#[inline]
fn is_wide_lead(cell: &Cell) -> bool {
    cell.width == CellWidth::Full
}

/// Coalesce a chronological run of physical lines into logical lines.
///
/// `cursor_index` / `cursor_col` identify the physical row + column the cursor
/// occupied (in the combined sequence); the cursor's logical offset is recorded
/// on the matching [`LogicalLine`].
fn coalesce_logical(
    mut rows: Vec<Line>,
    cursor_index: usize,
    cursor_col: usize,
) -> Vec<LogicalLine> {
    let mut logical: Vec<LogicalLine> = Vec::with_capacity(rows.len());

    // Accumulator for the in-progress logical line.
    let mut acc: Vec<Cell> = Vec::new();
    // Cursor offset within the in-progress logical line, if known.
    let mut acc_cursor: Option<usize> = None;
    // Whether the accumulator currently holds any rows (so we can flush at end).
    let mut acc_active = false;

    // Index-based iteration with one-row lookahead: distinguishing wide-char
    // wrap padding from a real typed trailing space requires inspecting the row
    // that follows a soft-wrapped row (see below).
    let n_rows = rows.len();
    for idx in 0..n_rows {
        let continues = rows[idx].wrapped;
        // Offset of this row's first cell within the logical line.
        let base = acc.len();

        // Capture the cursor offset before we (possibly) trim trailing blanks:
        // the cursor can legitimately sit in the trailing-blank region.
        if idx == cursor_index {
            acc_cursor = Some(base + cursor_col);
        }

        if continues {
            // Soft-wrapped row: its cells filled the right margin with real
            // content — EXCEPT for the one case where a wide character could not
            // fit in the last column and the printer left that cell blank before
            // wrapping.  That case is identified unambiguously by the NEXT row
            // starting with a wide lead (`Full`): the printer pushed the wide
            // char to the next row, blanking this row's final column.  Only then
            // is the trailing default cell padding to be dropped.  A genuine
            // typed trailing space (e.g. "abcd ef" wrapping at width 5) must be
            // preserved — dropping it unconditionally corrupts logical content.
            let next_is_wide_lead = idx + 1 < n_rows
                && rows[idx + 1].cells.first().is_some_and(is_wide_lead);
            let mut cells = std::mem::take(&mut rows[idx].cells);
            if next_is_wide_lead && cells.last().is_some_and(|c| *c == Cell::default()) {
                cells.pop();
            }
            acc.extend(cells);
            acc_active = true;
        } else {
            // Final physical row of this logical line: trim trailing blank
            // padding so rewrap doesn't preserve spurious spaces.
            let mut cells = std::mem::take(&mut rows[idx].cells);
            let trim = trailing_blank_len(&cells);
            cells.truncate(cells.len() - trim);
            acc.extend(cells);
            // Flush the completed logical line.
            logical.push(LogicalLine {
                cells: std::mem::take(&mut acc),
                cursor_offset: acc_cursor.take(),
            });
            acc_active = false;
        }
    }

    // A trailing soft-wrapped run with no terminating non-wrapped row (e.g. the
    // last screen row had `wrapped == true`) still forms a logical line.
    if acc_active {
        logical.push(LogicalLine {
            cells: acc,
            cursor_offset: acc_cursor,
        });
    }

    logical
}

/// Result of re-splitting all logical lines into physical rows at the new width.
struct Resplit {
    rows: Vec<Line>,
    /// `Some((row, col))` physical cursor position recovered from the logical
    /// cursor offset, or `None` when no logical line carried a cursor.
    cursor: Option<(usize, usize)>,
}

/// Push `cells` as one physical [`Line`] of width `new_cols`, padding with
/// blanks and setting `wrapped` to `soft`.
fn make_physical(mut cells: Vec<Cell>, new_cols: usize, soft: bool) -> Line {
    if cells.len() < new_cols {
        cells.resize(new_cols, Cell::default());
    } else {
        cells.truncate(new_cols);
    }
    let mut line = Line::new(new_cols);
    let has_wide = cells.iter().any(|c| c.width == CellWidth::Wide || c.width == CellWidth::Full);
    line.cells = cells;
    line.has_wide = has_wide;
    line.wrapped = soft;
    line.mark_dirty_and_bump();
    line
}

/// Re-split one logical line into physical rows at `new_cols`, never splitting a
/// wide character across the right margin.  Returns the produced rows and, when
/// the logical line carried a cursor offset, the (relative row, col) of the
/// cursor within those rows.
fn resplit_one(
    logical: LogicalLine,
    new_cols: usize,
    out: &mut Vec<Line>,
) -> Option<(usize, usize)> {
    let LogicalLine {
        cells,
        cursor_offset,
    } = logical;

    let first_row = out.len();
    let mut cursor_phys: Option<(usize, usize)> = None;

    // Empty logical line still occupies exactly one physical (blank) row.
    if cells.is_empty() {
        out.push(make_physical(Vec::new(), new_cols, false));
        if let Some(off) = cursor_offset {
            cursor_phys = Some((first_row, off.min(new_cols.saturating_sub(1))));
        }
        return cursor_phys;
    }

    let mut chunk: Vec<Cell> = Vec::with_capacity(new_cols);
    // Source-cell index where the current chunk starts (for cursor mapping).
    let mut chunk_src_start = 0usize;
    let total = cells.len();

    for (i, cell) in cells.into_iter().enumerate() {
        // Before placing a wide lead, ensure both halves fit on this row.
        // If only one column remains, blank-pad the row and wrap so the wide
        // char is never split (matches the printer's behavior).
        if chunk.len() == new_cols
            || (is_wide_lead(&cell) && chunk.len() + 2 > new_cols && new_cols >= 2)
        {
            // Map cursor if it falls within this chunk's source range.
            map_cursor_into_chunk(
                cursor_offset,
                chunk_src_start,
                i,
                out.len(),
                new_cols,
                &mut cursor_phys,
            );
            out.push(make_physical(std::mem::take(&mut chunk), new_cols, true));
            chunk_src_start = i;
        }
        chunk.push(cell);
    }

    // Flush the final chunk (the last physical row → wrapped = false).
    map_cursor_into_chunk(
        cursor_offset,
        chunk_src_start,
        total,
        out.len(),
        new_cols,
        &mut cursor_phys,
    );
    out.push(make_physical(chunk, new_cols, false));

    // If the cursor offset is exactly at the logical end (past the last cell),
    // it lands at the column just after the final content on the last row.
    if cursor_phys.is_none() {
        if let Some(off) = cursor_offset {
            // off >= total: clamp to the end of the last produced row.
            let last_row = out.len() - 1;
            let col_in_last = total.saturating_sub(chunk_src_start);
            let col = (off - total + col_in_last).min(new_cols.saturating_sub(1));
            cursor_phys = Some((last_row, col));
        }
    }

    cursor_phys
}

/// If `cursor_offset` lies within `[src_start, src_end)`, record its physical
/// position on the row that is about to be flushed (`phys_row`).
#[inline]
fn map_cursor_into_chunk(
    cursor_offset: Option<usize>,
    src_start: usize,
    src_end: usize,
    phys_row: usize,
    new_cols: usize,
    out: &mut Option<(usize, usize)>,
) {
    if out.is_some() {
        return;
    }
    if let Some(off) = cursor_offset {
        if off >= src_start && off < src_end {
            let col = (off - src_start).min(new_cols.saturating_sub(1));
            *out = Some((phys_row, col));
        }
    }
}

/// Re-split every logical line into physical rows at `new_cols`.
fn resplit_all(logicals: Vec<LogicalLine>, new_cols: usize) -> Resplit {
    let mut rows: Vec<Line> = Vec::with_capacity(logicals.len());
    let mut cursor: Option<(usize, usize)> = None;

    for logical in logicals {
        if let Some(pos) = resplit_one(logical, new_cols, &mut rows) {
            cursor = Some(pos);
        }
    }

    Resplit { rows, cursor }
}

impl Screen {
    /// Reflow (rewrap) the primary screen content + scrollback to `new_cols`.
    ///
    /// Caller guarantees this is the PRIMARY buffer (never the alternate screen)
    /// and that `new_cols != old_cols`.  `new_rows` is the new screen height.
    /// `cursor_row` / `cursor_col` are the primary cursor's position *before*
    /// the resize — passed explicitly because when the alternate screen is
    /// active the primary cursor lives in `saved_primary_cursor`, not
    /// `self.cursor`.
    ///
    /// Returns the recovered cursor position `(row, col)` within the new screen
    /// rows, or `None` when the cursor's logical line could not be located
    /// (in which case the caller should fall back to clamping).
    pub(super) fn reflow_primary(
        &mut self,
        new_rows: usize,
        new_cols: usize,
        cursor_row: usize,
        cursor_col: usize,
    ) -> Option<(usize, usize)> {
        // 1. Build the chronological combined sequence: scrollback then screen.
        let scrollback_len = self.scrollback_buffer.len();
        let cursor_index = scrollback_len + cursor_row;

        let mut combined: Vec<Line> = Vec::with_capacity(scrollback_len + self.lines.len());
        combined.extend(self.scrollback_buffer.drain(..));
        combined.extend(self.lines.drain(..));

        // 2. Coalesce into logical lines.
        let logicals = coalesce_logical(combined, cursor_index, cursor_col);

        // 3. Re-split at the new width.
        let Resplit { mut rows, cursor } = resplit_all(logicals, new_cols);

        // Trim trailing blank physical rows so the original screen's empty
        // bottom region does not artificially push live content into
        // scrollback.  Keep at least `cursor_row + 1` rows so the cursor's row
        // is never trimmed away, and never trim below one row.
        let keep_min = cursor.map_or(0, |(r, _)| r + 1);
        while rows.len() > keep_min && rows.len() > 1 {
            let last_is_blank = rows
                .last()
                .is_some_and(|l| !l.wrapped && l.cells.iter().all(|c| c.grapheme() == " "));
            if last_is_blank {
                rows.pop();
            } else {
                break;
            }
        }

        // 4. Re-place: last `new_rows` rows are the live screen, rest scrollback.
        let total = rows.len();
        let mut rows_iter = rows.into_iter();

        let screen_count = new_rows.min(total);
        let scrollback_count = total - screen_count;

        // Rebuild scrollback (capped to max).
        self.scrollback_buffer.clear();
        for _ in 0..scrollback_count {
            // Unwrap is safe: scrollback_count + screen_count == total.
            self.scrollback_buffer.push_back(rows_iter.next().unwrap());
        }
        // Cap scrollback to its configured maximum (oldest dropped first).
        let max = self.scrollback_max_lines;
        while self.scrollback_buffer.len() > max {
            self.scrollback_buffer.pop_front();
        }
        self.scrollback_line_count = self.scrollback_buffer.len();

        // Live screen rows.
        self.lines.clear();
        for line in rows_iter {
            self.lines.push_back(line);
        }
        // Pad to exactly new_rows blank rows if the content was shorter.
        while self.lines.len() < new_rows {
            self.lines.push_back(Line::new(new_cols));
        }

        // 5. Recover the cursor's physical position within the live screen.
        // `cursor` is (physical_row_in_full_sequence, col).  Subtract the
        // scrollback offset (rows that were pushed to scrollback) to get the
        // row within the live screen.
        cursor.map(|(phys_row, col)| {
            let row_in_screen = phys_row.saturating_sub(scrollback_count);
            (
                row_in_screen.min(new_rows.saturating_sub(1)),
                col.min(new_cols.saturating_sub(1)),
            )
        })
    }
}

#[cfg(test)]
#[path = "reflow/tests.rs"]
mod tests;

#[cfg(test)]
#[path = "reflow/adversarial_tests.rs"]
mod adversarial_tests;
