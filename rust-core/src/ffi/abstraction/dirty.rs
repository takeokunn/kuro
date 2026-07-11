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

/// Cursor state as encoded in the version-4 frame header.
///
/// `meta` carries bit 0 = visible (DECTCEM) and bits 1–3 = DECSCUSR shape;
/// it deliberately EXCLUDES the bell bit (bit 4 on the wire): bell is a
/// one-shot event, not cursor state, so it must not participate in the
/// "did the cursor change since the last emitted frame?" comparison.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct CursorWire {
    row: u32,
    col: u32,
    meta: u32,
}

/// Wire bit position of the bell event in the v4 header's `cursor_meta`.
const CURSOR_META_BELL_BIT: u32 = 1 << 4;

/// Raw-bytes view of a binary dirty frame, kept for unit tests that assert
/// on the wire layout (header fields, byte offsets).  The production bridge
/// uses [`TerminalSession::get_dirty_lines_binary_payload`], which transcodes
/// the frame to a Latin-1 string without consuming the session scratch
/// buffer's capacity.
#[cfg(test)]
pub(crate) struct BinaryDirtyFrame {
    pub(crate) texts: Vec<String>,
    pub(crate) bytes: Vec<u8>,
}

#[cfg(test)]
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
        if self.core.screen.scroll_offset() > 0 {
            // Scrollback viewing: live dirty state is discarded outright —
            // returning to the live view forces a full repaint
            // (`reset_live_view_scroll_state`), so nothing is lost.
            self.core.screen.clear_dirty();
            return true;
        }
        if self.core.dec_modes.synchronized_output {
            // Synchronized output (DEC 2026): HOLD updates without discarding
            // them.  Dirty bits and pending scroll shifts keep accumulating
            // while the frame is suppressed; when the application sends the
            // closing `?2026 l` the next poll drains exactly the rows that
            // changed during the batch.  The previous design cleared the
            // dirty set here and compensated with `mark_all_dirty()` on
            // reset, which turned every synchronized frame (one per repaint
            // for Ink-based apps like Claude Code) into a full-screen
            // repaint on the Emacs side.
            //
            // The poll counter caps how long a stuck `?2026 h` (application
            // crash mid-batch) can freeze the display, mirroring the timeout
            // kitty/wezterm apply.  Past the cap we render live again.
            if self.sync_suppressed_polls < Self::SYNC_SUPPRESS_MAX_POLLS {
                self.sync_suppressed_polls += 1;
                return true;
            }
            return false;
        }
        self.sync_suppressed_polls = 0;
        false
    }

    /// Discard pending scroll shifts by degrading them to a full repaint.
    ///
    /// The legacy drain paths (`get_dirty_lines`, `get_dirty_lines_with_faces`,
    /// and the cons-cell FFI wrappers built on them) predate the atomic
    /// shift-in-frame protocol and have no way to tell Emacs to shift its
    /// buffer, so a pending shift must become "repaint everything" for them.
    pub(super) fn degrade_scroll_shift_to_full_repaint(&mut self) {
        let (up, down) = self.core.screen.consume_scroll_events();
        if up > 0 || down > 0 {
            self.core.screen.mark_all_dirty();
        }
    }

    /// Rotate `row_hashes` to track a viewport shift of `up`/`down` rows.
    ///
    /// After Emacs applies the shift (delete N edge lines + insert N blanks
    /// at the opposite edge), the content previously rendered at row `i`
    /// lives at row `i - up + down`; rotating the cache the same way keeps
    /// the skip-unchanged-rows optimisation valid across scrolls.  Slots
    /// vacated by the rotation are cleared: they now describe rows whose
    /// Emacs-side content is a fresh blank, which must not match any hash.
    fn rotate_row_hashes_for_shift(&mut self, up: usize, down: usize) {
        let len = self.row_hashes.len();
        if len == 0 {
            return;
        }
        if up > 0 {
            if up >= len {
                self.row_hashes.fill(None);
            } else {
                self.row_hashes.rotate_left(up);
                self.row_hashes[len - up..].fill(None);
            }
        }
        if down > 0 {
            if down >= len {
                self.row_hashes.fill(None);
            } else {
                self.row_hashes.rotate_right(down);
                self.row_hashes[..down].fill(None);
            }
        }
    }

    /// Atomically consume the pending full-screen scroll shift for a drain
    /// that transmits it in-frame (the binary v3 protocol).
    ///
    /// Returns `(up, down)` clamped to the screen height (a shift of ≥ rows
    /// blanks the whole viewport, so larger counts carry no extra
    /// information and would make the Emacs buffer edit overshoot).  When
    /// `full_dirty` is set the counters have already been discarded
    /// (`mark_all_dirty` invariant); the guard here is defensive.
    fn consume_scroll_shift(&mut self) -> (u32, u32) {
        let (up, down) = self.core.screen.consume_scroll_events();
        if (up == 0 && down == 0) || self.core.screen.is_full_dirty() {
            return (0, 0);
        }
        let rows = u32::from(self.core.screen.rows());
        let up = up.min(rows);
        let down = down.min(rows);
        self.rotate_row_hashes_for_shift(
            usize::try_from(up).unwrap_or(usize::MAX),
            usize::try_from(down).unwrap_or(usize::MAX),
        );
        (up, down)
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

        // mem::take instead of clone: the loop needs `&mut self` while
        // iterating the dirty indices, but a take + restore keeps the Vec's
        // capacity without allocating a per-frame copy.
        let dirty_rows = std::mem::take(&mut self.dirty_scratch);
        let mut result: Vec<T> = Vec::with_capacity(dirty_rows.len());
        for &row in &dirty_rows {
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
        self.dirty_scratch = dirty_rows;

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

        // mem::take instead of clone (see collect_dirty_rows_with_cache).  On
        // the error return the take'd Vec is dropped and `dirty_scratch` stays
        // empty-but-valid — `take_dirty_lines_into` refills it next frame, so
        // only the (rare) error path pays a one-time capacity loss.
        let dirty_rows = std::mem::take(&mut self.dirty_scratch);
        let mut result: Vec<T> = Vec::with_capacity(dirty_rows.len());
        for &row in &dirty_rows {
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
        self.dirty_scratch = dirty_rows;

        Ok(result)
    }

    /// Number of consecutive suppressed polls after which a stuck
    /// synchronized-output batch (`?2026 h` with no matching `l`) stops
    /// freezing the display.  At the 120 fps render rate this is ≈1 s —
    /// far above any legitimate batch, in line with the ~150 ms timeouts
    /// kitty and wezterm apply.
    pub(super) const SYNC_SUPPRESS_MAX_POLLS: u32 = 120;

    /// Current cursor state in v4 wire form (bell bit excluded — see
    /// [`CursorWire`]).
    fn cursor_wire_state(&self) -> BinaryFrameResult<CursorWire> {
        let (row, col) = self.get_cursor();
        let row = BinaryFrameU32::from_usize(row, BinaryFrameU32Field::CursorRow)?.value();
        let col = BinaryFrameU32::from_usize(col, BinaryFrameU32Field::CursorCol)?.value();
        #[expect(
            clippy::cast_possible_truncation,
            clippy::cast_sign_loss,
            reason = "DECSCUSR shape is 0..=6 by construction; fits any unsigned width"
        )]
        let shape = i64::from(self.get_cursor_shape()) as u32;
        let meta = u32::from(self.get_cursor_visible()) | (shape << 1);
        Ok(CursorWire { row, col, meta })
    }

    fn begin_binary_dirty_frame(
        &mut self,
        scroll_up: u32,
        scroll_down: u32,
        cursor: CursorWire,
        bell: bool,
    ) -> usize {
        self.texts_scratch.clear();
        self.buf_scratch.clear();
        self.buf_scratch
            .extend_from_slice(&crate::ffi::codec::BINARY_FORMAT_VERSION.to_le_bytes());
        let num_rows_offset = self.buf_scratch.len();
        self.buf_scratch.extend_from_slice(&0u32.to_le_bytes());
        // Version 3: the scroll shift travels in the same frame as the dirty
        // rows so Emacs can apply "shift buffer, then rewrite rows" as one
        // atomic edit.  Draining the shift through a separate FFI call (the
        // retired `consume_scroll_events` protocol) allowed a parse to run
        // between the two drains, which is what corrupted the display and
        // forced the interim full-repaint-per-scroll design.
        self.buf_scratch.extend_from_slice(&scroll_up.to_le_bytes());
        self.buf_scratch
            .extend_from_slice(&scroll_down.to_le_bytes());
        // Version 4: cursor state + bell travel in the same frame, replacing
        // the per-frame `get_cursor_state` / `take_bell_pending` FFI calls.
        self.buf_scratch
            .extend_from_slice(&cursor.row.to_le_bytes());
        self.buf_scratch
            .extend_from_slice(&cursor.col.to_le_bytes());
        let meta = cursor.meta | if bell { CURSOR_META_BELL_BIT } else { 0 };
        self.buf_scratch.extend_from_slice(&meta.to_le_bytes());
        num_rows_offset
    }

    fn finish_binary_dirty_frame(&mut self, num_rows_offset: usize) -> BinaryFrameResult<()> {
        BinaryFrameU32::from_usize(self.texts_scratch.len(), BinaryFrameU32Field::TextCount)?
            .copy_le(
                &mut self.buf_scratch[num_rows_offset..num_rows_offset + BinaryFrameU32::WIDTH],
            );
        Ok(())
    }

    /// Collect dirty lines in the binary direct frame format for FFI transfer.
    ///
    /// Returns `(texts, payload)` where `payload` is the serialised frame
    /// transcoded to a Latin-1 string (byte `b` → `char U+00b`), ready for a
    /// single `make_string` transfer to Emacs.  The transcode reads
    /// `buf_scratch` **in place** — unlike the former `mem::take`, the 2–50 KB
    /// byte buffer keeps its capacity across frames, eliminating the
    /// realloc-and-regrow cycle on every 30fps poll.  Both vectors empty means
    /// "no frame" (the bridge returns nil).
    pub(crate) fn get_dirty_lines_binary_payload(
        &mut self,
    ) -> BinaryFrameResult<(Vec<String>, String)> {
        if !self.build_binary_dirty_frame()? {
            return Ok((Vec::new(), String::new()));
        }
        let texts = std::mem::take(&mut self.texts_scratch);
        // Bytes ≥ 0x80 become 2-byte UTF-8 sequences; reserve 2× upfront to
        // avoid a mid-loop realloc on color-heavy frames.
        let mut payload = String::with_capacity(self.buf_scratch.len() * 2);
        for &byte in &self.buf_scratch {
            payload.push(char::from(byte));
        }
        Ok((texts, payload))
    }

    /// Raw-bytes variant of [`Self::get_dirty_lines_binary_payload`], kept for
    /// unit tests that assert on the wire layout.  Clones `buf_scratch` (test
    /// convenience; the production path never copies the byte buffer).
    #[cfg(test)]
    pub(crate) fn get_dirty_lines_binary_direct(&mut self) -> BinaryFrameResult<BinaryDirtyFrame> {
        if !self.build_binary_dirty_frame()? {
            return Ok(BinaryDirtyFrame::empty());
        }
        Ok(BinaryDirtyFrame::new(
            std::mem::take(&mut self.texts_scratch),
            self.buf_scratch.clone(),
        ))
    }

    /// Build the binary dirty frame into the session scratch buffers.
    ///
    /// Returns `Ok(false)` when there is nothing to transmit this frame
    /// (scratch buffers are left cleared); `Ok(true)` when `texts_scratch` +
    /// `buf_scratch` hold a complete frame.
    fn build_binary_dirty_frame(&mut self) -> BinaryFrameResult<bool> {
        let bell = self.core.meta.bell_pending;
        let cursor = self.cursor_wire_state()?;

        // Scrollback viewport path: when scroll_dirty, encode all scrollback rows.
        if self.core.screen.is_scroll_dirty() && self.core.screen.scroll_offset() > 0 {
            let num_rows_offset = self.begin_binary_dirty_frame(0, 0, cursor, bell);
            self.core.meta.bell_pending = false;
            self.last_sent_cursor = Some(cursor);
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
            self.finish_binary_dirty_frame(num_rows_offset)?;
            return Ok(true);
        }

        // Suppress live dirty lines when viewport is scrolled (but not scroll_dirty).
        if self.suppress_live_dirty_if_scrolled_or_sync() {
            // A bell must still ring while the display is suppressed (scrolled
            // back or inside a DEC 2026 batch): emit a header-only frame with
            // 0 rows and no shift.  The cursor fields repeat the LAST-SENT
            // state (not the live one) so the displayed cursor does not move
            // mid-suppression; Emacs treats unchanged cursor state as a no-op.
            if bell {
                self.core.meta.bell_pending = false;
                let held_cursor = self.last_sent_cursor.unwrap_or(cursor);
                let num_rows_offset = self.begin_binary_dirty_frame(0, 0, held_cursor, true);
                self.finish_binary_dirty_frame(num_rows_offset)?;
                return Ok(true);
            }
            self.texts_scratch.clear();
            self.buf_scratch.clear();
            return Ok(false);
        }

        let epoch = self.refresh_render_epoch();

        // Consume the pending scroll shift atomically with the dirty rows:
        // both were produced by the parse that ran earlier in this same FFI
        // call, and both are applied by Emacs inside one render block.
        let (scroll_up, scroll_down) = self.consume_scroll_shift();

        // Reuse persistent scratch allocations: the serialised binary frame
        // buffer is cleared (retaining capacity) and transcoded in place by
        // `get_dirty_lines_binary_payload` — it is never moved out, so its
        // 2–50 KB capacity survives across frames at 120fps.
        let num_rows_offset = self.begin_binary_dirty_frame(scroll_up, scroll_down, cursor, bell);

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

        // Emit when anything changed: dirty rows, a scroll shift, a cursor
        // state change since the last emitted frame, or a bell event.  A
        // rows-free frame still reaches Emacs for the latter three — the v4
        // header is the transport for all of them.
        let cursor_changed = self.last_sent_cursor != Some(cursor);
        if self.texts_scratch.is_empty()
            && scroll_up == 0
            && scroll_down == 0
            && !cursor_changed
            && !bell
        {
            self.buf_scratch.clear();
            return Ok(false);
        }

        self.core.meta.bell_pending = false;
        self.last_sent_cursor = Some(cursor);
        self.finish_binary_dirty_frame(num_rows_offset)?;
        Ok(true)
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

        // This legacy cons-cell path cannot transmit a scroll shift; any
        // pending shift becomes a full repaint (same behaviour this path
        // has always had for scrolls).
        self.degrade_scroll_shift_to_full_repaint();

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
