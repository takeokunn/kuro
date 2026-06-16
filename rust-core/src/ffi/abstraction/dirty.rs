//! Dirty-line rendering and scroll-event methods for `TerminalSession`
//!
//! This module contains the `consume_scroll_events` and `get_dirty_lines_with_faces`
//! methods, which handle the scrollback viewport and synchronized-output logic.

use super::session::TerminalSession;

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
        let rows = self.core.screen.rows() as usize;
        for row in 0..rows {
            visit_row(self, row);
        }
    }

    fn collect_scrollback_viewport_rows<T, F>(&mut self, mut visit_row: F) -> Vec<T>
    where
        F: FnMut(&mut Self, usize) -> T,
    {
        let mut result = Vec::with_capacity(self.core.screen.rows() as usize);
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
        ) -> Option<(T, u64)>,
    {
        let rows = self.core.screen.rows() as usize;
        self.core.screen.clear_dirty();
        self.ensure_row_hash_capacity(rows);

        let mut result = Vec::with_capacity(rows);
        for row in 0..rows {
            if let Some(line) = self.core.screen.get_line(row) {
                if let Some((value, hash)) =
                    emit_row(&mut self.encode_pool, &mut self.buf_scratch, line, row)
                {
                    self.row_hashes[row] = Some((line.version, hash, epoch));
                    result.push(value);
                }
            }
        }

        result
    }

    fn encode_line_with_faces_and_hash(
        encode_pool: &mut crate::ffi::codec::EncodePool,
        line: &crate::grid::line::Line,
    ) -> (
        String,
        Vec<(usize, usize, u32, u32, u64, u32)>,
        Vec<usize>,
        u64,
    ) {
        let (text, face_ranges, col_to_buf) = crate::ffi::codec::encode_line_with_pool(
            &line.cells,
            line.has_wide,
            encode_pool,
        );
        let hash = crate::ffi::codec::compute_row_hash_from_encoded(&text, &face_ranges, &col_to_buf);
        (text, face_ranges, col_to_buf, hash)
    }

    fn encode_line_into_binary_frame_and_hash(
        encode_pool: &mut crate::ffi::codec::EncodePool,
        buf_scratch: &mut Vec<u8>,
        line: &crate::grid::line::Line,
        row: usize,
    ) -> (String, u64) {
        crate::ffi::codec::encode_line_into_buf_and_hash(
            &line.cells,
            line.has_wide,
            encode_pool,
            row,
            buf_scratch,
        )
    }

    fn collect_dirty_rows_with_cache<T, F>(
        &mut self,
        epoch: u64,
        mut emit_row: F,
    ) -> Vec<T>
    where
        F: FnMut(
            &mut crate::ffi::codec::EncodePool,
            &mut Vec<u8>,
            &crate::grid::line::Line,
            usize,
            Option<(u64, u64, u64)>,
            u64,
        ) -> Option<(T, u64)>,
    {
        self.core.screen.take_dirty_lines_into(&mut self.dirty_scratch);
        let screen_rows = self.core.screen.rows() as usize;
        self.ensure_row_hash_capacity(screen_rows);

        let mut result: Vec<T> = Vec::with_capacity(self.dirty_scratch.len());
        for &row in &self.dirty_scratch {
            if let Some(line) = self.core.screen.get_line(row) {
                let cached = self.row_hashes[row];

                if let Some((stored_ver, _stored_hash, stored_epoch)) = cached {
                    if line.version == stored_ver && epoch == stored_epoch {
                        continue;
                    }
                }

                let buf_snapshot = self.buf_scratch.len();
                if let Some((value, new_hash)) = emit_row(
                    &mut self.encode_pool,
                    &mut self.buf_scratch,
                    line,
                    row,
                    cached,
                    epoch,
                ) {
                    if let Some((_stored_ver, stored_hash, stored_epoch)) = cached {
                        if stored_hash == new_hash && stored_epoch == epoch {
                            self.buf_scratch.truncate(buf_snapshot);
                            continue;
                        }
                    }

                    self.row_hashes[row] = Some((line.version, new_hash, epoch));
                    result.push(value);
                } else {
                    self.buf_scratch.truncate(buf_snapshot);
                }
            }
        }

        result
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

    fn finish_binary_dirty_frame(&mut self, num_rows_offset: usize) -> (Vec<String>, Vec<u8>) {
        #[expect(
            clippy::cast_possible_truncation,
            reason = "number of dirty rows is bounded by terminal height (≤ 65535); fits u32"
        )]
        self.buf_scratch[num_rows_offset..num_rows_offset + 4]
            .copy_from_slice(&(self.texts_scratch.len() as u32).to_le_bytes());
        (
            std::mem::take(&mut self.texts_scratch),
            std::mem::take(&mut self.buf_scratch),
        )
    }

    /// Collect dirty lines in the binary direct frame format.
    ///
    /// This reuses the session scratch buffers for both text rows and the
    /// serialized binary payload so callers can avoid per-frame heap churn.

    pub fn get_dirty_lines_binary_direct(&mut self) -> (Vec<String>, Vec<u8>) {
        // Scrollback viewport path: when scroll_dirty, encode all scrollback rows.
        if self.core.screen.is_scroll_dirty() && self.core.screen.scroll_offset() > 0 {
            // Reuse the same row-collection shape as the face-range path.
            let num_rows_offset = self.begin_binary_dirty_frame();
            self.texts_scratch = self.collect_scrollback_viewport_rows(|this, row| {
                if let Some(line) = this.core.screen.get_scrollback_viewport_line(row) {
                    let text = crate::ffi::codec::encode_line_into_buf(
                        &line.cells,
                        line.has_wide,
                        &mut this.encode_pool,
                        row,
                        &mut this.buf_scratch,
                    );
                    text
                } else {
                    // Emit an empty row entry.
                    #[expect(
                        clippy::cast_possible_truncation,
                        reason = "row index is a terminal row (≤ 65535); fits u32"
                    )]
                    this.buf_scratch
                        .extend_from_slice(&(row as u32).to_le_bytes());
                    this.buf_scratch.extend_from_slice(&0u32.to_le_bytes()); // num_face_ranges
                    this.buf_scratch.extend_from_slice(&0u32.to_le_bytes()); // text_byte_len = 0
                    this.buf_scratch.extend_from_slice(&0u32.to_le_bytes()); // col_to_buf_len
                    String::new()
                }
            });
            return self.finish_binary_dirty_frame(num_rows_offset);
        }

        // Suppress live dirty lines when viewport is scrolled (but not scroll_dirty).
        if self.suppress_live_dirty_if_scrolled_or_sync() {
            return (vec![], vec![]);
        }

        let epoch = self.refresh_render_epoch();

        // Reuse persistent scratch allocations: both the text-strings Vec and the
        // serialised binary frame buffer are cleared (retaining capacity) and
        // mem::take'd on return — eliminating two heap allocations per frame at 120fps.
        let num_rows_offset = self.begin_binary_dirty_frame();

        if self.core.screen.is_full_dirty() {
            self.texts_scratch = self.collect_full_dirty_rows(
                epoch,
                |encode_pool, buf_scratch, line, row| {
                    let (text, hash) = Self::encode_line_into_binary_frame_and_hash(
                        encode_pool,
                        buf_scratch,
                        line,
                        row,
                    );
                    Some((text, hash))
                },
            );
        } else {
            let epoch = self.palette_epoch;
            let rows = self.collect_dirty_rows_with_cache(
                epoch,
                |encode_pool, buf_scratch, line, row, _cached, _epoch| {
                    let (text, hash) = Self::encode_line_into_binary_frame_and_hash(
                        encode_pool,
                        buf_scratch,
                        line,
                        row,
                    );
                    Some((text, hash))
                },
            );
            self.texts_scratch.extend(rows);
        }

        if self.texts_scratch.is_empty() {
            return (vec![], vec![]);
        }

        self.finish_binary_dirty_frame(num_rows_offset)
    }

    /// Get dirty lines with face ranges from screen, with scrollback viewport support.
    ///
    /// When the viewport is scrolled back (`scroll_offset > 0`) and `scroll_dirty` is
    /// set, returns all rows as scrollback content. Otherwise falls through to the
    /// standard live dirty-line path.
    ///
    /// Returns a list where each element is `(line_no, text, face_ranges, col_to_buf)`:
    /// - `face_ranges`: `(start_buf, end_buf, fg_color, bg_color, flags)` in buffer offsets
    /// - `col_to_buf`: mapping from grid column index to buffer char offset
    pub fn get_dirty_lines_with_faces(&mut self) -> Vec<crate::ffi::codec::EncodedLine> {
        // Scrollback viewport path: when scroll_dirty, return scrollback lines instead of live lines
        if self.core.screen.is_scroll_dirty() && self.core.screen.scroll_offset() > 0 {
            return self.collect_scrollback_viewport_rows(|this, row| {
                match this.core.screen.get_scrollback_viewport_line(row) {
                    Some(line) => {
                        let (text, face_ranges, col_to_buf) =
                            crate::ffi::codec::encode_line_with_pool(
                                &line.cells,
                                line.has_wide,
                                &mut this.encode_pool,
                            );
                        (row, text, face_ranges, col_to_buf)
                    }
                    None => (row, String::new(), vec![], vec![]),
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
                let (text, face_ranges, col_to_buf, hash) =
                    Self::encode_line_with_faces_and_hash(encode_pool, line);
                Some(((row, text, face_ranges, col_to_buf), hash))
            });
        }

        let epoch = self.palette_epoch;
        self.collect_dirty_rows_with_cache(
            epoch,
            |encode_pool, _buf_scratch, line, row, _cached, _epoch| {
                let (text, face_ranges, col_to_buf, hash) =
                    Self::encode_line_with_faces_and_hash(encode_pool, line);
                Some(((row, text, face_ranges, col_to_buf), hash))
            },
        )
    }
}
