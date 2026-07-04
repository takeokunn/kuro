//! Dirty-line rendering and scroll-event methods for `TerminalSession`
//!
//! This module contains the `consume_scroll_events` and `get_dirty_lines_with_faces`
//! methods, which handle the scrollback viewport and synchronized-output logic.

use crate::ffi::codec::{BinaryFrameResult, BinaryFrameU32, BinaryFrameU32Field};

use super::session::{RowRenderCache, TerminalSession};

struct DirtyRowEmission<T> {
    value: T,
    content_hash: u64,
}

pub(crate) struct BinaryDirtyFrame {
    pub(crate) texts: Vec<String>,
    pub(crate) bytes: Vec<u8>,
}

impl BinaryDirtyFrame {
    #[inline]
    fn empty() -> Self {
        Self::new(Vec::new(), Vec::new())
    }

    #[inline]
    fn new(texts: Vec<String>, bytes: Vec<u8>) -> Self {
        Self { texts, bytes }
    }
}

impl TerminalSession {
    fn ensure_row_hash_capacity(&mut self, rows: usize) {
        if self.row_hashes.len() < rows {
            self.row_hashes.resize(rows, None);
        }
    }

    fn refresh_render_epoch(&mut self) -> u64 {
        if self.core.osc_data.palette_dirty {
            self.core.osc_data.palette_dirty = false;
            self.palette_epoch = self.palette_epoch.wrapping_add(1);
        }

        let now_alt = self.core.screen.is_alternate_screen_active();
        if now_alt != self.was_alt_screen {
            self.was_alt_screen = now_alt;
            self.palette_epoch = self.palette_epoch.wrapping_add(1);
        }

        self.palette_epoch
    }

    fn row_cache_is_current(cached: Option<RowRenderCache>, line_version: u64, epoch: u64) -> bool {
        matches!(
            cached,
            Some(stored) if stored.line_version == line_version && stored.palette_epoch == epoch
        )
    }

    fn row_cache_matches_hash(cached: Option<RowRenderCache>, new_hash: u64, epoch: u64) -> bool {
        matches!(
            cached,
            Some(stored) if stored.content_hash == new_hash && stored.palette_epoch == epoch
        )
    }

    fn store_row_cache(&mut self, row: usize, line_version: u64, new_hash: u64, epoch: u64) {
        self.row_hashes[row] = Some(RowRenderCache::new(line_version, new_hash, epoch));
    }
}

impl TerminalSession {
    /// Consume pending full-screen scroll event counts and reset them to zero.
    ///
    /// Returns `(scroll_up, scroll_down)`.  Called by the Emacs render cycle
    /// BEFORE `get_dirty_lines_with_faces` so that buffer-level line
    /// deletion/insertion can precede per-row text updates, preventing the
    /// bottom row from being rendered twice per scroll step.
    ///
    /// Returns `(0, 0)` when the viewport is scrolled into the scrollback
    /// buffer (`scroll_offset > 0`).  Scroll events that accumulated while
    /// the user was viewing scrollback are discarded in
    /// `viewport_scroll_down` when `scroll_offset` returns to 0.
    pub fn consume_scroll_events(&mut self) -> (u32, u32) {
        if self.core.screen.scroll_offset() > 0 {
            return (0, 0);
        }
        self.core.screen.consume_scroll_events()
    }

    fn suppress_live_dirty_if_scrolled_or_sync(&mut self) -> bool {
        if self.core.screen.scroll_offset() > 0 || self.core.dec_modes.synchronized_output {
            self.core.screen.clear_dirty();
            return true;
        }
        false
    }

    fn for_each_scrollback_viewport_row<F>(&mut self, mut visit_row: F)
    where
        F: FnMut(&mut Self, usize),
    {
        self.core.screen.clear_scroll_dirty();
        let rows = usize::from(self.core.screen.rows());
        for row in 0..rows {
            visit_row(self, row);
        }
    }

    fn collect_scrollback_viewport_rows<T, F>(&mut self, mut visit_row: F) -> Vec<T>
    where
        F: FnMut(&mut Self, usize) -> T,
    {
        let mut result = Vec::with_capacity(usize::from(self.core.screen.rows()));
        self.for_each_scrollback_viewport_row(|this, row| {
            result.push(visit_row(this, row));
        });
        result
    }

    fn collect_full_dirty_rows<T, F>(&mut self, epoch: u64, mut emit_row: F) -> Vec<T>
    where
        F: FnMut(
            &mut crate::ffi::codec::EncodePool,
            &mut Vec<u8>,
            &crate::grid::line::Line,
            usize,
        ) -> Option<DirtyRowEmission<T>>,
    {
        let rows = usize::from(self.core.screen.rows());
        self.core.screen.clear_dirty();
        self.ensure_row_hash_capacity(rows);

        let mut result = Vec::with_capacity(rows);
        for row in 0..rows {
            if let Some(line) = self.core.screen.get_line(row) {
                if let Some(emission) =
                    emit_row(&mut self.encode_pool, &mut self.buf_scratch, line, row)
                {
                    self.store_row_cache(row, line.version, emission.content_hash, epoch);
                    result.push(emission.value);
                }
            }
        }

        result
    }

    fn encode_line_with_faces_and_hash(
        encode_pool: &mut crate::ffi::codec::EncodePool,
        line: &crate::grid::line::Line,
    ) -> (crate::ffi::codec::EncodedLineData, u64) {
        let encoded =
            crate::ffi::codec::encode_line_with_pool(&line.cells, line.has_wide, encode_pool);
        // `encode_line_with_pool` mem::takes text/face_ranges/col_to_buf but
        // leaves `text_sizes` in the pool — read it back to fold OSC 66 sizing
        // into the row hash so a text-size-only change still re-renders.
        let hash = crate::ffi::codec::compute_row_hash_from_encoded(
            &encoded.text,
            &encoded.face_ranges,
            &encoded.col_to_buf,
            &encode_pool.text_sizes,
        );
        (encoded, hash)
    }

    fn encode_line_into_binary_frame_and_hash(
        encode_pool: &mut crate::ffi::codec::EncodePool,
        buf_scratch: &mut Vec<u8>,
        line: &crate::grid::line::Line,
        row: usize,
    ) -> BinaryFrameResult<crate::ffi::codec::HashedEncodedText> {
        crate::ffi::codec::encode_line_into_buf_and_hash(
            &line.cells,
            line.has_wide,
            encode_pool,
            row,
            buf_scratch,
        )
    }

    fn collect_dirty_rows_with_cache<T, F>(&mut self, epoch: u64, mut emit_row: F) -> Vec<T>
    where
        F: FnMut(
            &mut crate::ffi::codec::EncodePool,
            &mut Vec<u8>,
            &crate::grid::line::Line,
            usize,
            Option<RowRenderCache>,
            u64,
        ) -> Option<DirtyRowEmission<T>>,
    {
        self.core
            .screen
            .take_dirty_lines_into(&mut self.dirty_scratch);
        let screen_rows = usize::from(self.core.screen.rows());
        self.ensure_row_hash_capacity(screen_rows);

        let dirty_rows = self.dirty_scratch.clone();
        let mut result: Vec<T> = Vec::with_capacity(dirty_rows.len());
        for row in dirty_rows {
            if let Some(line) = self.core.screen.get_line(row) {
                let cached = self.row_hashes[row];

                if Self::row_cache_is_current(cached, line.version, epoch) {
                    continue;
                }

                let buf_snapshot = self.buf_scratch.len();
                if let Some(emission) = emit_row(
                    &mut self.encode_pool,
                    &mut self.buf_scratch,
                    line,
                    row,
                    cached,
                    epoch,
                ) {
                    if Self::row_cache_matches_hash(cached, emission.content_hash, epoch) {
                        self.buf_scratch.truncate(buf_snapshot);
                        continue;
                    }

                    self.store_row_cache(row, line.version, emission.content_hash, epoch);
                    result.push(emission.value);
                } else {
                    self.buf_scratch.truncate(buf_snapshot);
                }
            }
        }

        result
    }

    fn try_collect_scrollback_viewport_rows<T, F>(
        &mut self,
        mut visit_row: F,
    ) -> BinaryFrameResult<Vec<T>>
    where
        F: FnMut(&mut Self, usize) -> BinaryFrameResult<T>,
    {
        self.core.screen.clear_scroll_dirty();
        let rows = usize::from(self.core.screen.rows());
        let mut result = Vec::with_capacity(rows);
        for row in 0..rows {
            result.push(visit_row(self, row)?);
        }
        Ok(result)
    }

    fn try_collect_full_dirty_rows<T, F>(
        &mut self,
        epoch: u64,
        mut emit_row: F,
    ) -> BinaryFrameResult<Vec<T>>
    where
        F: FnMut(
            &mut crate::ffi::codec::EncodePool,
            &mut Vec<u8>,
            &crate::grid::line::Line,
            usize,
        ) -> BinaryFrameResult<Option<DirtyRowEmission<T>>>,
    {
        let rows = usize::from(self.core.screen.rows());
        self.core.screen.clear_dirty();
        self.ensure_row_hash_capacity(rows);

        let mut result = Vec::with_capacity(rows);
        for row in 0..rows {
            if let Some(line) = self.core.screen.get_line(row) {
                if let Some(emission) =
                    emit_row(&mut self.encode_pool, &mut self.buf_scratch, line, row)?
                {
                    self.store_row_cache(row, line.version, emission.content_hash, epoch);
                    result.push(emission.value);
                }
            }
        }

        Ok(result)
    }

    fn try_collect_dirty_rows_with_cache<T, F>(
        &mut self,
        epoch: u64,
        mut emit_row: F,
    ) -> BinaryFrameResult<Vec<T>>
    where
        F: FnMut(
            &mut crate::ffi::codec::EncodePool,
            &mut Vec<u8>,
            &crate::grid::line::Line,
            usize,
            Option<RowRenderCache>,
            u64,
        ) -> BinaryFrameResult<Option<DirtyRowEmission<T>>>,
    {
        self.core
            .screen
            .take_dirty_lines_into(&mut self.dirty_scratch);
        let screen_rows = usize::from(self.core.screen.rows());
        self.ensure_row_hash_capacity(screen_rows);

        let dirty_rows = self.dirty_scratch.clone();
        let mut result: Vec<T> = Vec::with_capacity(dirty_rows.len());
        for row in dirty_rows {
            if let Some(line) = self.core.screen.get_line(row) {
                let cached = self.row_hashes[row];

                if Self::row_cache_is_current(cached, line.version, epoch) {
                    continue;
                }

                let buf_snapshot = self.buf_scratch.len();
                match emit_row(
                    &mut self.encode_pool,
                    &mut self.buf_scratch,
                    line,
                    row,
                    cached,
                    epoch,
                ) {
                    Ok(Some(emission)) => {
                        if Self::row_cache_matches_hash(cached, emission.content_hash, epoch) {
                            self.buf_scratch.truncate(buf_snapshot);
                            continue;
                        }

                        self.store_row_cache(row, line.version, emission.content_hash, epoch);
                        result.push(emission.value);
                    }
                    Ok(None) => {
                        self.buf_scratch.truncate(buf_snapshot);
                    }
                    Err(err) => {
                        self.buf_scratch.truncate(buf_snapshot);
                        return Err(err);
                    }
                }
            }
        }

        Ok(result)
    }

    fn begin_binary_dirty_frame(&mut self) -> usize {
        self.texts_scratch.clear();
        self.buf_scratch.clear();
        self.buf_scratch
            .extend_from_slice(&crate::ffi::codec::BINARY_FORMAT_VERSION.to_le_bytes());
        let num_rows_offset = self.buf_scratch.len();
        self.buf_scratch.extend_from_slice(&0u32.to_le_bytes());
        num_rows_offset
    }

    fn finish_binary_dirty_frame(
        &mut self,
        num_rows_offset: usize,
    ) -> BinaryFrameResult<BinaryDirtyFrame> {
        BinaryFrameU32::from_usize(self.texts_scratch.len(), BinaryFrameU32Field::TextCount)?
            .copy_le(
                &mut self.buf_scratch[num_rows_offset..num_rows_offset + BinaryFrameU32::WIDTH],
            );
        Ok(BinaryDirtyFrame::new(
            std::mem::take(&mut self.texts_scratch),
            std::mem::take(&mut self.buf_scratch),
        ))
    }

    /// Collect dirty lines in the binary direct frame format.
    ///
    /// This reuses the session scratch buffers for both text rows and the
    /// serialized binary payload so callers can avoid per-frame heap churn.
    pub(crate) fn get_dirty_lines_binary_direct(&mut self) -> BinaryFrameResult<BinaryDirtyFrame> {
        // Scrollback viewport path: when scroll_dirty, encode all scrollback rows.
        if self.core.screen.is_scroll_dirty() && self.core.screen.scroll_offset() > 0 {
            let num_rows_offset = self.begin_binary_dirty_frame();
            self.texts_scratch = self.try_collect_scrollback_viewport_rows(|this, row| {
                if let Some(line) = this.core.screen.get_scrollback_viewport_line(row) {
                    crate::ffi::codec::encode_line_into_buf(
                        &line.cells,
                        line.has_wide,
                        &mut this.encode_pool,
                        row,
                        &mut this.buf_scratch,
                    )
                } else {
                    BinaryFrameU32::from_usize(row, BinaryFrameU32Field::RowIndex)?
                        .write_le(&mut this.buf_scratch);
                    this.buf_scratch.extend_from_slice(&0u32.to_le_bytes()); // num_face_ranges
                    this.buf_scratch.extend_from_slice(&0u32.to_le_bytes()); // text_byte_len = 0
                    this.buf_scratch.extend_from_slice(&0u32.to_le_bytes()); // col_to_buf_len
                    Ok(String::new())
                }
            })?;
            return self.finish_binary_dirty_frame(num_rows_offset);
        }

        // Suppress live dirty lines when viewport is scrolled (but not scroll_dirty).
        if self.suppress_live_dirty_if_scrolled_or_sync() {
            return Ok(BinaryDirtyFrame::empty());
        }

        let epoch = self.refresh_render_epoch();

        // Reuse persistent scratch allocations: both the text-strings Vec and the
        // serialised binary frame buffer are cleared (retaining capacity) and
        // mem::take'd on return — eliminating two heap allocations per frame at 120fps.
        let num_rows_offset = self.begin_binary_dirty_frame();

        if self.core.screen.is_full_dirty() {
            self.texts_scratch =
                self.try_collect_full_dirty_rows(epoch, |encode_pool, buf_scratch, line, row| {
                    let encoded = Self::encode_line_into_binary_frame_and_hash(
                        encode_pool,
                        buf_scratch,
                        line,
                        row,
                    )?;
                    Ok(Some(DirtyRowEmission {
                        value: encoded.text,
                        content_hash: encoded.content_hash,
                    }))
                })?;
        } else {
            let epoch = self.palette_epoch;
            let rows = self.try_collect_dirty_rows_with_cache(
                epoch,
                |encode_pool, buf_scratch, line, row, _cached, _epoch| {
                    let encoded = Self::encode_line_into_binary_frame_and_hash(
                        encode_pool,
                        buf_scratch,
                        line,
                        row,
                    )?;
                    Ok(Some(DirtyRowEmission {
                        value: encoded.text,
                        content_hash: encoded.content_hash,
                    }))
                },
            )?;
            self.texts_scratch.extend(rows);
        }

        if self.texts_scratch.is_empty() {
            return Ok(BinaryDirtyFrame::empty());
        }

        self.finish_binary_dirty_frame(num_rows_offset)
    }

    /// Get dirty lines with face ranges from screen, with scrollback viewport support.
    ///
    /// When the viewport is scrolled back (`scroll_offset > 0`) and `scroll_dirty` is
    /// set, returns all rows as scrollback content. Otherwise falls through to the
    /// standard live dirty-line path.
    ///
    /// Returns strongly typed encoded lines:
    /// - `face_ranges`: buffer-offset style spans with encoded colors/attributes
    /// - `col_to_buf`: grid column index to buffer char offset mapping
    pub(crate) fn get_dirty_lines_with_faces(&mut self) -> Vec<crate::ffi::codec::EncodedLine> {
        // Scrollback viewport path: when scroll_dirty, return scrollback lines instead of live lines
        if self.core.screen.is_scroll_dirty() && self.core.screen.scroll_offset() > 0 {
            return self.collect_scrollback_viewport_rows(|this, row| {
                match this.core.screen.get_scrollback_viewport_line(row) {
                    Some(line) => crate::ffi::codec::encode_line_with_pool(
                        &line.cells,
                        line.has_wide,
                        &mut this.encode_pool,
                    )
                    .with_row_index(row),
                    None => crate::ffi::codec::EncodedLine::empty(row),
                }
            });
        }

        // If viewport is scrolled but not dirty (scroll_dirty == false),
        // suppress live dirty lines to preserve the scrollback view.
        if self.suppress_live_dirty_if_scrolled_or_sync() {
            return vec![];
        }

        let epoch = self.refresh_render_epoch();

        // Fast path: full_dirty → iterate 0..rows directly without allocating a Vec.
        // Also update row_hashes for each encoded row so subsequent partial-dirty
        // frames can skip rows that haven't changed.
        // NOTE: The hash-skip optimisation (below) only applies in the partial-dirty
        // path.  Full-dirty frames — triggered by scrolling, resize, alt-screen switch,
        // or programs that dirty more rows than the dirty threshold — always return all
        // rows.  This is intentional: `full_dirty` is a conservative "repaint everything"
        // signal where correctness requires sending every row to the Elisp renderer.
        if self.core.screen.is_full_dirty() {
            return self.collect_full_dirty_rows(epoch, |encode_pool, _buf_scratch, line, row| {
                // full_dirty requires all rows — no version/hash-skip here.
                // Row hashes are still updated so the subsequent partial-dirty
                // frames can skip unchanged rows.
                let (encoded, hash) = Self::encode_line_with_faces_and_hash(encode_pool, line);
                Some(DirtyRowEmission {
                    value: encoded.with_row_index(row),
                    content_hash: hash,
                })
            });
        }

        let epoch = self.palette_epoch;
        self.collect_dirty_rows_with_cache(
            epoch,
            |encode_pool, _buf_scratch, line, row, _cached, _epoch| {
                let (encoded, hash) = Self::encode_line_with_faces_and_hash(encode_pool, line);
                Some(DirtyRowEmission {
                    value: encoded.with_row_index(row),
                    content_hash: hash,
                })
            },
        )
    }
}

#[cfg(test)]
mod tests {
    use crate::ffi::codec::{BinaryFrameU32, BinaryFrameU32Field};

    #[test]
    fn binary_frame_u32_accepts_u32_max() {
        let mut buf = Vec::new();
        BinaryFrameU32::from_usize(
            usize::try_from(u32::MAX).expect("u32::MAX fits usize"),
            BinaryFrameU32Field::RowIndex,
        )
        .expect("u32::MAX is accepted")
        .write_le(&mut buf);

        assert_eq!(buf, u32::MAX.to_le_bytes());
    }

    #[cfg(target_pointer_width = "64")]
    #[test]
    fn binary_frame_u32_rejects_values_above_u32() {
        let value = usize::try_from(u32::MAX).expect("u32::MAX fits usize") + 1;
        let error = BinaryFrameU32::from_usize(value, BinaryFrameU32Field::RowIndex)
            .expect_err("row index above u32 must be rejected");

        assert_eq!(error.field, BinaryFrameU32Field::RowIndex);
        assert_eq!(error.value, value);
    }
}
