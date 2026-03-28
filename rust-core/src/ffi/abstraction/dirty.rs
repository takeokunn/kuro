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
            let mut texts: Vec<String> = Vec::with_capacity(rows);
            // Header placeholder: format_version(4) + num_rows placeholder(4).
            let mut buf = Vec::with_capacity(8 + rows * 16);
            buf.extend_from_slice(&crate::ffi::codec::BINARY_FORMAT_VERSION.to_le_bytes());
            let num_rows_offset = buf.len();
            buf.extend_from_slice(&0u32.to_le_bytes()); // placeholder — backfilled below
            for row in 0..rows {
                match self.core.screen.get_scrollback_viewport_line(row) {
                    Some(line) => {
                        let text =
                            crate::ffi::codec::encode_line_into_buf(&line.cells, &mut self.encode_pool, row, &mut buf);
                        texts.push(text);
                    }
                    None => {
                        // Emit an empty row entry.
                        #[expect(
                            clippy::cast_possible_truncation,
                            reason = "row index is a terminal row (≤ 65535); fits u32"
                        )]
                        buf.extend_from_slice(&(row as u32).to_le_bytes());
                        buf.extend_from_slice(&0u32.to_le_bytes()); // num_face_ranges
                        buf.extend_from_slice(&0u32.to_le_bytes()); // text_byte_len = 0
                        buf.extend_from_slice(&0u32.to_le_bytes()); // col_to_buf_len
                        texts.push(String::new());
                    }
                }
            }
            // Backfill num_rows.
            #[expect(
                clippy::cast_possible_truncation,
                reason = "number of rows is bounded by terminal height (≤ 65535); fits u32"
            )]
            buf[num_rows_offset..num_rows_offset + 4]
                .copy_from_slice(&(texts.len() as u32).to_le_bytes());
            return (texts, buf);
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

        // Pre-allocate with a conservative estimate; the header placeholder is
        // 8 bytes and each row adds at least 16 bytes (row header fields).
        let mut texts: Vec<String> = Vec::new();
        // Reserve header placeholder: format_version(4) + num_rows(4).
        let mut buf = Vec::new();
        buf.extend_from_slice(&crate::ffi::codec::BINARY_FORMAT_VERSION.to_le_bytes());
        let num_rows_offset = buf.len();
        buf.extend_from_slice(&0u32.to_le_bytes()); // placeholder

        if self.core.screen.is_full_dirty() {
            let rows = self.core.screen.rows() as usize;
            self.core.screen.clear_dirty();
            if self.row_hashes.len() < rows {
                self.row_hashes.resize(rows, None);
            }
            let epoch = self.palette_epoch;
            texts.reserve(rows);
            for row in 0..rows {
                if let Some(line) = self.core.screen.get_line(row) {
                    let text =
                        crate::ffi::codec::encode_line_into_buf(&line.cells, &mut self.encode_pool, row, &mut buf);
                    let hash = crate::ffi::codec::compute_row_hash(line, &self.encode_pool.col_to_buf);
                    self.row_hashes[row] = Some((line.version, hash, epoch));
                    texts.push(text);
                }
            }
        } else {
            let dirty_indices = self.core.screen.take_dirty_lines();
            let epoch = self.palette_epoch;
            texts.reserve(dirty_indices.len());

            for row in dirty_indices {
                if let Some(line) = self.core.screen.get_line(row) {
                    // Fast path: version + epoch match → skip without encoding.
                    if let Some((stored_ver, _stored_hash, stored_epoch)) =
                        self.row_hashes.get(row).copied().flatten()
                    {
                        if line.version == stored_ver && stored_epoch == epoch {
                            continue;
                        }
                    }

                    // Snapshot buf length before encoding so we can roll back if
                    // the hash confirms the row is unchanged.
                    let buf_snapshot = buf.len();

                    // Encode into pool and serialise to buf.
                    let text =
                        crate::ffi::codec::encode_line_into_buf(&line.cells, &mut self.encode_pool, row, &mut buf);
                    let new_hash = crate::ffi::codec::compute_row_hash(line, &self.encode_pool.col_to_buf);

                    // Hash-skip: roll back the partial write if row is unchanged.
                    if let Some((_stored_ver, stored_hash, stored_epoch)) =
                        self.row_hashes.get(row).copied().flatten()
                    {
                        if stored_hash == new_hash && stored_epoch == epoch {
                            buf.truncate(buf_snapshot);
                            continue;
                        }
                    }

                    if row >= self.row_hashes.len() {
                        self.row_hashes.resize(row + 1, None);
                    }
                    self.row_hashes[row] = Some((line.version, new_hash, epoch));
                    texts.push(text);
                }
            }
        }

        if texts.is_empty() {
            return (vec![], vec![]);
        }

        // Backfill num_rows in the header.
        #[expect(
            clippy::cast_possible_truncation,
            reason = "number of dirty rows is bounded by terminal height (≤ 65535); fits u32"
        )]
        buf[num_rows_offset..num_rows_offset + 4]
            .copy_from_slice(&(texts.len() as u32).to_le_bytes());

        (texts, buf)
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
                        let encoded = Self::encode_line_faces(row, &line.cells);
                        result.push(encoded);
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
                    // Fast path: version + epoch match → no hash needed, skip row.
                    if let Some((stored_ver, stored_hash, stored_epoch)) =
                        self.row_hashes[row]
                    {
                        if line.version == stored_ver && epoch == stored_epoch {
                            // Re-emit with cached data to keep render state consistent.
                            // We still need to send the row content because full_dirty
                            // requires all rows to be returned.
                            // (fall through to encode below)
                            let _ = (stored_ver, stored_hash, stored_epoch);
                        }
                    }
                    let (text, face_ranges, col_to_buf) =
                        crate::ffi::codec::encode_line_with_pool(&line.cells, &mut self.encode_pool);
                    let hash = crate::ffi::codec::compute_row_hash(line, &col_to_buf);
                    self.row_hashes[row] = Some((line.version, hash, epoch));
                    result.push((row, text, face_ranges, col_to_buf));
                }
            }
            return result;
        }

        let dirty_indices = self.core.screen.take_dirty_lines();
        let mut result = Vec::with_capacity(dirty_indices.len());
        let epoch = self.palette_epoch;

        for row in dirty_indices {
            if let Some(line) = self.core.screen.get_line(row) {
                // Fast path: if version and palette epoch both match the stored
                // values, the row content is guaranteed unchanged — skip hash.
                if let Some((stored_ver, _stored_hash, stored_epoch)) =
                    self.row_hashes.get(row).copied().flatten()
                {
                    if line.version == stored_ver && epoch == stored_epoch {
                        // Unchanged row — skip without computing hash.
                        continue;
                    }
                }

                let (text, face_ranges, col_to_buf) =
                    crate::ffi::codec::encode_line_with_pool(&line.cells, &mut self.encode_pool);
                let new_hash = crate::ffi::codec::compute_row_hash(line, &col_to_buf);

                // Slow path: check hash + epoch to guard against false positives
                // (e.g. version counter wrapped, or palette changed without version bump).
                if let Some((_stored_ver, stored_hash, stored_epoch)) =
                    self.row_hashes.get(row).copied().flatten()
                {
                    if stored_hash == new_hash && stored_epoch == epoch {
                        // Hash confirms unchanged — do not include in output.
                        continue;
                    }
                }

                // Grow Vec if needed (row index may exceed current len on first use).
                if row >= self.row_hashes.len() {
                    self.row_hashes.resize(row + 1, None);
                }
                self.row_hashes[row] = Some((line.version, new_hash, epoch));
                result.push((row, text, face_ranges, col_to_buf));
            }
        }

        result
    }
}
