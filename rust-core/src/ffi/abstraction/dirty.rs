//! Dirty-line rendering and scroll-event methods for `TerminalSession`
//!
//! This module contains the `consume_scroll_events` and `get_dirty_lines_with_faces`
//! methods, which handle the scrollback viewport and synchronized-output logic.

use super::session::TerminalSession;

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

    /// Get dirty lines for the binary-with-strings FFI protocol in a single pass.
    ///
    /// This is a performance-optimised alternative to calling
    /// [`get_dirty_lines_with_faces`] followed by
    /// `encode_screen_binary_no_text`.  Instead of building an intermediate
    /// `Vec<EncodedLine>` (which requires **three heap clones** per dirty row —
    /// `String`, `Vec<face_ranges>`, `Vec<col_to_buf>`), this method encodes
    /// face ranges and `col_to_buf` **directly** into the returned `Vec<u8>`
    /// binary buffer, cloning only the text `String` (one clone per row).
    ///
    /// Returns `(text_strings, binary_buf)` where:
    /// - `text_strings[i]` is the UTF-8 text for the *i*-th row in the frame.
    /// - `binary_buf` is a complete binary frame in the same format as
    ///   [`encode_screen_binary_no_text`] (`text_byte_len = 0` per row).
    ///
    /// Returns `(vec![], vec![])` when there are no dirty rows to emit.
    pub fn get_dirty_lines_binary_direct(&mut self) -> (Vec<String>, Vec<u8>) {
        // Scrollback viewport path: when scroll_dirty, encode all scrollback rows.
        if self.core.screen.is_scroll_dirty() && self.core.screen.scroll_offset() > 0 {
            self.core.screen.clear_scroll_dirty();
            let rows = self.core.screen.rows() as usize;
            // Reuse persistent scratch allocations for scrollback path (same pattern as main path).
            self.texts_scratch.clear();
            self.texts_scratch.reserve(rows);
            self.buf_scratch.clear();
            self.buf_scratch
                .extend_from_slice(&crate::ffi::codec::BINARY_FORMAT_VERSION.to_le_bytes());
            let num_rows_offset = self.buf_scratch.len();
            self.buf_scratch.extend_from_slice(&0u32.to_le_bytes()); // placeholder — backfilled below
            for row in 0..rows {
                if let Some(line) = self.core.screen.get_scrollback_viewport_line(row) {
                    let text = crate::ffi::codec::encode_line_into_buf(
                        &line.cells,
                        line.has_wide,
                        &mut self.encode_pool,
                        row,
                        &mut self.buf_scratch,
                    );
                    self.texts_scratch.push(text);
                } else {
                    // Emit an empty row entry.
                    #[expect(
                        clippy::cast_possible_truncation,
                        reason = "row index is a terminal row (≤ 65535); fits u32"
                    )]
                    self.buf_scratch
                        .extend_from_slice(&(row as u32).to_le_bytes());
                    self.buf_scratch.extend_from_slice(&0u32.to_le_bytes()); // num_face_ranges
                    self.buf_scratch.extend_from_slice(&0u32.to_le_bytes()); // text_byte_len = 0
                    self.buf_scratch.extend_from_slice(&0u32.to_le_bytes()); // col_to_buf_len
                    self.texts_scratch.push(String::new());
                }
            }
            // Backfill num_rows.
            #[expect(
                clippy::cast_possible_truncation,
                reason = "number of rows is bounded by terminal height (≤ 65535); fits u32"
            )]
            self.buf_scratch[num_rows_offset..num_rows_offset + 4]
                .copy_from_slice(&(self.texts_scratch.len() as u32).to_le_bytes());
            return (
                std::mem::take(&mut self.texts_scratch),
                std::mem::take(&mut self.buf_scratch),
            );
        }

        // Suppress live dirty lines when viewport is scrolled (but not scroll_dirty).
        if self.core.screen.scroll_offset() > 0 {
            self.core.screen.clear_dirty();
            return (vec![], vec![]);
        }

        // Synchronized Output mode: hold until batch complete.
        if self.core.dec_modes.synchronized_output {
            self.core.screen.clear_dirty();
            return (vec![], vec![]);
        }

        // Palette epoch bump (same logic as get_dirty_lines_with_faces).
        if self.core.osc_data.palette_dirty {
            self.core.osc_data.palette_dirty = false;
            self.palette_epoch = self.palette_epoch.wrapping_add(1);
        }
        let now_alt = self.core.screen.is_alternate_screen_active();
        if now_alt != self.was_alt_screen {
            self.was_alt_screen = now_alt;
            self.palette_epoch = self.palette_epoch.wrapping_add(1);
        }

        // Reuse persistent scratch allocations: both the text-strings Vec and the
        // serialised binary frame buffer are cleared (retaining capacity) and
        // mem::take'd on return — eliminating two heap allocations per frame at 120fps.
        self.texts_scratch.clear();
        self.buf_scratch.clear();
        self.buf_scratch
            .extend_from_slice(&crate::ffi::codec::BINARY_FORMAT_VERSION.to_le_bytes());
        let num_rows_offset = self.buf_scratch.len();
        self.buf_scratch.extend_from_slice(&0u32.to_le_bytes()); // placeholder

        if self.core.screen.is_full_dirty() {
            let rows = self.core.screen.rows() as usize;
            self.core.screen.clear_dirty();
            if self.row_hashes.len() < rows {
                self.row_hashes.resize(rows, None);
            }
            let epoch = self.palette_epoch;
            self.texts_scratch.reserve(rows);
            for row in 0..rows {
                if let Some(line) = self.core.screen.get_line(row) {
                    let text = crate::ffi::codec::encode_line_into_buf(
                        &line.cells,
                        line.has_wide,
                        &mut self.encode_pool,
                        row,
                        &mut self.buf_scratch,
                    );
                    let hash = crate::ffi::codec::compute_row_hash_from_pool(&self.encode_pool);
                    self.row_hashes[row] = Some((line.version, hash, epoch));
                    self.texts_scratch.push(text);
                }
            }
        } else {
            self.core
                .screen
                .take_dirty_lines_into(&mut self.dirty_scratch);
            let epoch = self.palette_epoch;
            self.texts_scratch.reserve(self.dirty_scratch.len());
            // Pre-size row_hashes to the screen height once before the loop.
            // Avoids a branch + possible realloc on every dirty row that would
            // otherwise be triggered by the per-row `if row >= len` guard.
            let screen_rows = self.core.screen.rows() as usize;
            if self.row_hashes.len() < screen_rows {
                self.row_hashes.resize(screen_rows, None);
            }

            for &row in &self.dirty_scratch {
                if let Some(line) = self.core.screen.get_line(row) {
                    // Direct index: row_hashes is pre-sized to screen_rows above,
                    // and dirty rows are bounded by screen dimensions — no get+flatten needed.
                    let cached = self.row_hashes[row];

                    // Fast path: version + epoch match → skip without encoding.
                    if let Some((stored_ver, _stored_hash, stored_epoch)) = cached {
                        if line.version == stored_ver && stored_epoch == epoch {
                            continue;
                        }
                    }

                    // Snapshot buf length before encoding so we can roll back if
                    // the hash confirms the row is unchanged.
                    let buf_snapshot = self.buf_scratch.len();

                    // Encode into pool and serialise to buf_scratch.
                    let text = crate::ffi::codec::encode_line_into_buf(
                        &line.cells,
                        line.has_wide,
                        &mut self.encode_pool,
                        row,
                        &mut self.buf_scratch,
                    );
                    let new_hash = crate::ffi::codec::compute_row_hash_from_pool(&self.encode_pool);

                    // Hash-skip: use already-fetched cached value — no second lookup.
                    if let Some((_stored_ver, stored_hash, stored_epoch)) = cached {
                        if stored_hash == new_hash && stored_epoch == epoch {
                            self.buf_scratch.truncate(buf_snapshot);
                            continue;
                        }
                    }

                    self.row_hashes[row] = Some((line.version, new_hash, epoch));
                    self.texts_scratch.push(text);
                }
            }
        }

        if self.texts_scratch.is_empty() {
            return (vec![], vec![]);
        }

        // Backfill num_rows in the header.
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
            self.core.screen.clear_scroll_dirty();
            let rows = self.core.screen.rows() as usize;
            let mut result = Vec::with_capacity(rows);
            for row in 0..rows {
                match self.core.screen.get_scrollback_viewport_line(row) {
                    Some(line) => {
                        let (text, face_ranges, col_to_buf) =
                            crate::ffi::codec::encode_line_with_pool(
                                &line.cells,
                                line.has_wide,
                                &mut self.encode_pool,
                            );
                        result.push((row, text, face_ranges, col_to_buf));
                    }
                    None => {
                        result.push((row, String::new(), vec![], vec![]));
                    }
                }
            }
            return result;
        }

        // If viewport is scrolled but not dirty (scroll_dirty == false),
        // suppress live dirty lines to preserve the scrollback view.
        if self.core.screen.scroll_offset() > 0 {
            self.core.screen.clear_dirty();
            return vec![];
        }

        // Synchronized Output mode (DEC ?2026): hold until batch complete.
        if self.core.dec_modes.synchronized_output {
            self.core.screen.clear_dirty();
            return vec![];
        }

        // Check if the 256-color palette changed since the last render and bump
        // palette_epoch so every cached row hash is implicitly invalidated.
        if self.core.osc_data.palette_dirty {
            self.core.osc_data.palette_dirty = false;
            self.palette_epoch = self.palette_epoch.wrapping_add(1);
        }

        // Check if alternate screen was toggled since the last render and bump
        // palette_epoch to implicitly invalidate all cached row hashes without
        // clearing the Vec (avoids the O(rows) fill on every screen switch).
        let now_alt = self.core.screen.is_alternate_screen_active();
        if now_alt != self.was_alt_screen {
            self.was_alt_screen = now_alt;
            self.palette_epoch = self.palette_epoch.wrapping_add(1);
        }

        // Fast path: full_dirty → iterate 0..rows directly without allocating a Vec.
        // Also update row_hashes for each encoded row so subsequent partial-dirty
        // frames can skip rows that haven't changed.
        // NOTE: The hash-skip optimisation (below) only applies in the partial-dirty
        // path.  Full-dirty frames — triggered by scrolling, resize, alt-screen switch,
        // or programs that dirty more rows than the dirty threshold — always return all
        // rows.  This is intentional: `full_dirty` is a conservative "repaint everything"
        // signal where correctness requires sending every row to the Elisp renderer.
        if self.core.screen.is_full_dirty() {
            let rows = self.core.screen.rows() as usize;
            self.core.screen.clear_dirty();
            // Ensure Vec is sized to hold all rows.
            if self.row_hashes.len() < rows {
                self.row_hashes.resize(rows, None);
            }
            let epoch = self.palette_epoch;
            let mut result = Vec::with_capacity(rows);
            for row in 0..rows {
                if let Some(line) = self.core.screen.get_line(row) {
                    // full_dirty requires all rows — no version/hash-skip here.
                    // Row hashes are still updated so the subsequent partial-dirty
                    // frames can skip unchanged rows.
                    let (text, face_ranges, col_to_buf) = crate::ffi::codec::encode_line_with_pool(
                        &line.cells,
                        line.has_wide,
                        &mut self.encode_pool,
                    );
                    // encode_line_with_pool uses mem::take, so pool is empty here.
                    // Hash the returned data directly instead of the pool.
                    let hash = crate::ffi::codec::compute_row_hash_from_encoded(
                        &text,
                        &face_ranges,
                        &col_to_buf,
                    );
                    self.row_hashes[row] = Some((line.version, hash, epoch));
                    result.push((row, text, face_ranges, col_to_buf));
                }
            }
            return result;
        }

        self.core
            .screen
            .take_dirty_lines_into(&mut self.dirty_scratch);
        let mut result = Vec::with_capacity(self.dirty_scratch.len());
        let epoch = self.palette_epoch;
        // Pre-size row_hashes to screen height before the loop — same pattern as
        // get_dirty_lines_binary_direct (RUST-33).  Eliminates the per-row
        // `if row >= len` branch + possible realloc on every dirty row.
        let screen_rows = self.core.screen.rows() as usize;
        if self.row_hashes.len() < screen_rows {
            self.row_hashes.resize(screen_rows, None);
        }

        for &row in &self.dirty_scratch {
            if let Some(line) = self.core.screen.get_line(row) {
                // Direct index: row_hashes is pre-sized to screen_rows above.
                let cached = self.row_hashes[row];

                // Fast path: if version and palette epoch both match the stored
                // values, the row content is guaranteed unchanged — skip hash.
                if let Some((stored_ver, _stored_hash, stored_epoch)) = cached {
                    if line.version == stored_ver && epoch == stored_epoch {
                        // Unchanged row — skip without computing hash.
                        continue;
                    }
                }

                let (text, face_ranges, col_to_buf) = crate::ffi::codec::encode_line_with_pool(
                    &line.cells,
                    line.has_wide,
                    &mut self.encode_pool,
                );
                // encode_line_with_pool uses mem::take, so pool is empty here.
                let new_hash = crate::ffi::codec::compute_row_hash_from_encoded(
                    &text,
                    &face_ranges,
                    &col_to_buf,
                );

                // Slow path: use already-fetched cached value — no second lookup.
                if let Some((_stored_ver, stored_hash, stored_epoch)) = cached {
                    if stored_hash == new_hash && stored_epoch == epoch {
                        // Hash confirms unchanged — do not include in output.
                        continue;
                    }
                }

                self.row_hashes[row] = Some((line.version, new_hash, epoch));
                result.push((row, text, face_ranges, col_to_buf));
            }
        }

        result
    }
}
