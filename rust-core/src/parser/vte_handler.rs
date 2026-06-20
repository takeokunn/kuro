//! VTE Perform trait implementation for `TerminalCore`
//!
//! This module implements the `vte::Perform` trait, which is the callback
//! interface for the VTE parser. Each method handles a different class of
//! terminal escape sequences.

use std::sync::Arc;

use crate::parser;
use crate::TerminalCore;
use unicode_width::UnicodeWidthChar;

/// Maximum depth of the XTPUSHCOLORS/XTPOPCOLORS palette save stack (CSI # P/Q).
///
/// Matches xterm's `colorSaveCount` default.
const PALETTE_STACK_MAX: usize = 10;

#[path = "vte_handler_esc.rs"]
mod esc;

#[path = "vte_handler_csi.rs"]
mod csi;

fn combining_attach_position(
    cursor: crate::types::cursor::Cursor,
    cols: usize,
) -> Option<(usize, usize)> {
    // When a deferred wrap is pending the most-recently-printed cell is the
    // cell the cursor is still sitting ON (the last column) — the cursor did
    // NOT advance past it. A combining scalar or grapheme-cluster continuation
    // must therefore attach to `(row, col)` itself, not `(row, col - 1)`.
    // Without this guard a combining accent / ZWJ / regional-indicator merge
    // lands on the wrong (previous) glyph and, for flag pairs, destroys the
    // freshly-printed regional indicator at the last column.
    if cursor.pending_wrap {
        return Some((cursor.row, cursor.col));
    }
    if cursor.col > 0 {
        Some((cursor.row, cursor.col - 1))
    } else if cursor.row > 0 {
        Some((cursor.row - 1, cols.saturating_sub(1)))
    } else {
        None
    }
}

fn should_treat_as_combining_char(c: char, width: Option<usize>) -> bool {
    width == Some(0) || (width.is_none() && !c.is_control())
}

fn hyperlink_write_position(
    pre_cursor: crate::types::cursor::Cursor,
    cursor_after: crate::types::cursor::Cursor,
) -> (usize, usize) {
    if cursor_after.row != pre_cursor.row || cursor_after.col < pre_cursor.col {
        (cursor_after.row, 0)
    } else {
        (pre_cursor.row, pre_cursor.col)
    }
}

impl vte::Perform for TerminalCore {
    #[inline]
    fn print(&mut self, c: char) {
        self.note_vte_callback(true);

        let c = self.translate_print_char(c);
        if self.buffer_ascii_print(c) {
            // ASCII printables are ordinary advancing prints: a ZWJ-join or
            // regional-indicator pairing can never continue through one, so a
            // buffered ASCII char must break any pending grapheme cluster.
            if self.dec_modes.grapheme_clustering {
                self.clear_grapheme_cluster_state();
            }
            return;
        }

        self.flush_print_buf();

        let width = UnicodeWidthChar::width(c);

        // Grapheme clustering (DEC mode 2027): coalesce ZWJ sequences and
        // regional-indicator flag pairs onto the previous cell. Only consulted
        // when the mode is enabled — a single cheap bool keeps the default path
        // byte-for-byte unchanged.
        if self.dec_modes.grapheme_clustering && self.handle_grapheme_clustering(c, width) {
            return;
        }

        if self.handle_combining_char(c, width) {
            return;
        }

        let pre_cursor = *self.screen.cursor();
        if self.dec_modes.insert_mode {
            self.screen.insert_chars(1, self.current_attrs);
        }
        self.screen
            .print(c, self.current_attrs, self.dec_modes.auto_wrap);

        self.last_printed_char = Some(c);
        self.stamp_printed_hyperlink(pre_cursor, width.unwrap_or(1));

        // Kitty Unicode placeholder: a printed U+10EEEE cell is a virtual image
        // placement anchor. Decode the referenced image (id from fg color,
        // placement id from underline color) and associate it with the cell.
        // Diacritics (row/col) may still be pending; finalize again as each one
        // attaches in handle_combining_char.
        if crate::grid::placeholder::is_placeholder_char(c) {
            let cursor_after = *self.screen.cursor();
            let (row, col) = hyperlink_write_position(pre_cursor, cursor_after);
            if let Some(info) = self.finalize_placeholder_cell(row, col) {
                self.notify_placeholder_placement(row, col, info);
            }
        }
    }

    #[inline]
    fn execute(&mut self, byte: u8) {
        self.prepare_vte_callback(true);
        match byte {
            0x05 => self.handle_enquiry(),
            0x07 => self.meta.bell_pending = true,
            0x08 => self.handle_backspace(),
            0x09 => self.handle_horizontal_tab(),
            0x0A..=0x0C => self.handle_newline_control(),
            0x0D => self.screen.carriage_return(),
            0x0E => self.handle_shift_out(),
            0x0F => self.handle_shift_in(),
            _ => {}
        }
    }

    #[inline]
    fn csi_dispatch(&mut self, params: &vte::Params, intermediates: &[u8], _ignore: bool, c: char) {
        self.prepare_vte_callback(true);
        csi::handle_csi_dispatch(self, params, intermediates, c);
    }

    /// Handle OSC (Operating System Command) sequences from the VTE parser.
    ///
    /// Delegates to `parser::osc::handle_osc` for the full implementation.
    #[inline]
    fn osc_dispatch(&mut self, params: &[&[u8]], bell_terminated: bool) {
        self.prepare_vte_callback(true);
        parser::osc::handle_osc(self, params, bell_terminated);
    }

    #[inline]
    fn esc_dispatch(&mut self, intermediates: &[u8], _ignore: bool, byte: u8) {
        self.prepare_vte_callback(true);
        esc::handle_esc_dispatch(self, intermediates, byte);
    }

    #[inline]
    fn hook(&mut self, params: &vte::Params, intermediates: &[u8], ignore: bool, c: char) {
        self.prepare_vte_callback(false);
        parser::dcs::dcs_hook(self, params, intermediates, ignore, c);
    }

    #[inline]
    fn put(&mut self, byte: u8) {
        self.prepare_vte_callback(false);
        parser::dcs::dcs_put(self, byte);
    }

    #[inline]
    fn unhook(&mut self) {
        self.prepare_vte_callback(true);
        parser::dcs::dcs_unhook(self);
    }
}

impl TerminalCore {
    #[inline]
    fn translate_print_char(&self, c: char) -> char {
        if self.active_charset() == crate::types::charset::CharsetType::DecLineDrawing
            && c.is_ascii()
        {
            crate::types::charset::translate_dec_line_drawing(c)
        } else {
            c
        }
    }

    #[inline]
    fn buffer_ascii_print(&mut self, c: char) -> bool {
        if c.is_ascii() && !self.dec_modes.insert_mode {
            self.print_buf.push(c as u8);
            return true;
        }
        false
    }

    /// Clear all DEC mode 2027 grapheme-clustering continuation state.
    ///
    /// Called whenever a non-clustering event interrupts a cluster: a control
    /// char, cursor movement, line wrap, CR/LF, screen edit, or an ordinary
    /// advancing print. This prevents a stray ZWJ or lone regional indicator
    /// from corrupting an unrelated cell printed later.
    #[inline]
    pub(crate) fn clear_grapheme_cluster_state(&mut self) {
        self.grapheme_join_pending = false;
        self.regional_indicator_pending = false;
    }

    /// True for Unicode regional indicator symbols (U+1F1E6..=U+1F1FF) — the
    /// codepoints that pair up to render national flag emoji.
    #[inline]
    const fn is_regional_indicator(c: char) -> bool {
        matches!(c, '\u{1F1E6}'..='\u{1F1FF}')
    }

    /// DEC mode 2027 grapheme clustering for the print path.
    ///
    /// Returns `true` when `c` was consumed as part of a cluster (caller must
    /// then skip the normal print). Returns `false` to fall through to the
    /// ordinary combining/print path. Only invoked when
    /// `dec_modes.grapheme_clustering` is set.
    ///
    /// Handles three cases:
    /// 1. **ZWJ continuation** — a printable (width ≥ 1) arriving while a ZWJ
    ///    join is pending is appended to the previous cell's cluster instead of
    ///    advancing the cursor (family/profession emoji).
    /// 2. **ZWJ (U+200D)** — attaches to the previous cell (width 0) and arms
    ///    the join-pending flag so the next printable continues the cluster.
    /// 3. **Regional indicators** — a second RI joins the lone RI already in the
    ///    previous cell to form one width-2 flag cluster; a first RI prints
    ///    normally and arms the RI-pending flag.
    fn handle_grapheme_clustering(&mut self, c: char, width: Option<usize>) -> bool {
        // Case 1: continue a ZWJ-joined cluster with the next printable char.
        if self.grapheme_join_pending && width.unwrap_or(0) >= 1 {
            self.grapheme_join_pending = false;
            self.regional_indicator_pending = false;
            if self.append_to_previous_cluster(c) {
                return true;
            }
            // No previous cell (line start): fall through to a normal print.
            return false;
        }

        // Case 2: a ZWJ (U+200D, width 0) — attach to the previous cell and arm
        // the join so the following printable extends this cluster.
        if c == '\u{200D}' {
            self.regional_indicator_pending = false;
            if self.append_to_previous_cluster(c) {
                self.grapheme_join_pending = true;
                return true;
            }
            // No previous cell: a stray ZWJ at col 0 is dropped harmlessly.
            return true;
        }

        // Case 3: regional indicators (flags).
        if Self::is_regional_indicator(c) {
            if self.regional_indicator_pending {
                // Second RI: fold into the lone RI's cell as one width-2 flag.
                self.regional_indicator_pending = false;
                if self.merge_regional_indicator(c) {
                    return true;
                }
                // No previous cell — print this RI as a fresh first indicator.
            }
            // First RI: print normally, then arm the pairing flag.
            self.regional_indicator_pending = true;
            self.grapheme_join_pending = false;
            let pre_cursor = *self.screen.cursor();
            if self.dec_modes.insert_mode {
                self.screen.insert_chars(1, self.current_attrs);
            }
            self.screen
                .print(c, self.current_attrs, self.dec_modes.auto_wrap);
            self.last_printed_char = Some(c);
            self.stamp_printed_hyperlink(pre_cursor, width.unwrap_or(1));
            return true;
        }

        // Any other character: not a cluster continuation. Break pending state
        // and let the normal combining/print path handle it.
        self.clear_grapheme_cluster_state();
        false
    }

    /// Append `c` to the grapheme cluster of the cell preceding the cursor
    /// without advancing the cursor. Returns `false` when there is no previous
    /// cell (cursor at line start / origin), so the caller can fall back.
    ///
    /// When the preceding cell is a [`CellWidth::Wide`] continuation (the second
    /// half of a wide grapheme), the join lands on the wide base cell one column
    /// further back so the cluster scalars stay on a single logical cell.
    #[inline]
    fn append_to_previous_cluster(&mut self, c: char) -> bool {
        let cursor = *self.screen.cursor();
        let Some((row, col)) = combining_attach_position(cursor, self.screen.cols() as usize) else {
            return false;
        };
        let base_col = self.cluster_base_col(row, col);
        self.screen.attach_combining(row, base_col, c);
        true
    }

    /// Resolve the base column of a (possibly wide) grapheme at `(row, col)`.
    ///
    /// If `(row, col)` is the trailing [`CellWidth::Wide`] continuation cell of
    /// a wide grapheme, returns `col - 1` (the base cell holding the scalars);
    /// otherwise returns `col` unchanged.
    #[inline]
    fn cluster_base_col(&self, row: usize, col: usize) -> usize {
        if col > 0
            && self
                .screen
                .get_cell(row, col)
                .is_some_and(|cell| cell.width == crate::types::cell::CellWidth::Wide)
        {
            col - 1
        } else {
            col
        }
    }

    /// Fold a second regional indicator into the previous (lone-RI) cell,
    /// promoting that cell to a width-2 flag cluster and reserving the trailing
    /// continuation cell. Returns `false` when there is no previous cell.
    #[inline]
    fn merge_regional_indicator(&mut self, c: char) -> bool {
        let cursor = *self.screen.cursor();
        let Some((row, col)) = combining_attach_position(cursor, self.screen.cols() as usize) else {
            return false;
        };
        self.screen.merge_flag_pair(row, col, c);
        true
    }

    #[inline]
    fn handle_combining_char(&mut self, c: char, width: Option<usize>) -> bool {
        if !should_treat_as_combining_char(c, width) {
            return false;
        }

        let cursor = *self.screen.cursor();
        if let Some((row, col)) = combining_attach_position(cursor, self.screen.cols() as usize) {
            self.screen.attach_combining(row, col, c);
            // If the cell we just extended is a Kitty Unicode placeholder, the
            // newly-attached diacritic carries row/column (or high-id-byte)
            // metadata — re-decode the placeholder association.
            if self
                .screen
                .get_cell(row, col)
                .is_some_and(|cell| crate::grid::placeholder::is_placeholder_char(cell.char()))
            {
                self.finalize_placeholder_cell(row, col);
            }
        } else {
            self.screen
                .print(c, self.current_attrs, self.dec_modes.auto_wrap);
        }
        true
    }

    /// Decode the Kitty Unicode placeholder cell at (`row`, `col`) and associate
    /// it with its referenced image.
    ///
    /// Reads the cell's grapheme (placeholder base + row/col diacritics) and its
    /// foreground/underline colors, decodes the `(image_id, placement_id, img_row,
    /// img_col)` association, and stamps `image_id` onto the cell so the encoder /
    /// Emacs treats it as an image cell. Returns the decoded
    /// [`crate::grid::placeholder::PlaceholderInfo`] (so the caller can emit a
    /// notification on first print), or `None` for a malformed placeholder (no
    /// image id encoded in the foreground), which is ignored.
    #[inline]
    fn finalize_placeholder_cell(
        &mut self,
        row: usize,
        col: usize,
    ) -> Option<crate::grid::placeholder::PlaceholderInfo> {
        let cell = self.screen.get_cell(row, col)?;
        let info = crate::grid::placeholder::decode_placeholder(
            cell.grapheme(),
            cell.attrs.foreground,
            cell.attrs.underline_color,
        )?;

        if let Some(cell) = self.screen.get_cell_mut(row, col) {
            cell.set_image_id(Some(info.image_id));
        }
        Some(info)
    }

    /// Emit a redisplay notification for a Unicode-placeholder anchor at
    /// (`row`, `col`) when the referenced image is present in the store. Orphan
    /// placeholders (unknown image id) draw nothing and are silently skipped.
    /// The placement records `placement_id` (from the underline color) so it can
    /// be targeted by Kitty `a=d,p=` deletion.
    #[inline]
    fn notify_placeholder_placement(
        &mut self,
        row: usize,
        col: usize,
        info: crate::grid::placeholder::PlaceholderInfo,
    ) {
        if self
            .screen
            .active_graphics()
            .get_image_png_base64(info.image_id)
            .is_empty()
        {
            return;
        }
        let placement = crate::grid::screen::ImagePlacement {
            image_id: info.image_id,
            placement_id: info.placement_id,
            row,
            col,
            display_cols: 1,
            display_rows: 1,
            ..crate::grid::screen::ImagePlacement::default()
        };
        if let Some(notif) = self.screen.active_graphics_mut().add_placement(placement) {
            self.kitty.pending_image_notifications.push(notif);
        }
    }

    #[inline]
    fn handle_enquiry(&mut self) {
        // ENQ: respond with the terminal answerback string.
        self.meta.pending_responses.push(b"kuro".to_vec());
    }

    #[inline]
    fn handle_backspace(&mut self) {
        // Reverse-wraparound (mode 45): BS at col 0 wraps to previous line's last col.
        let cursor = *self.screen.cursor();
        if self.dec_modes.reverse_wraparound
            && !cursor.pending_wrap
            && cursor.col == 0
            && cursor.row > 0
        {
            let last_col = (self.screen.cols() as usize).saturating_sub(1);
            self.screen.move_cursor(cursor.row - 1, last_col);
        } else {
            self.screen.backspace();
        }
    }

    #[inline]
    fn handle_horizontal_tab(&mut self) {
        if self.dec_modes.tab_stops_enabled() {
            parser::tabs::handle_ht(&mut self.screen, &self.tab_stops);
        } else {
            self.screen.tab();
        }
    }

    #[inline]
    fn handle_newline_control(&mut self) {
        // LNM (mode 20): LF also performs CR when newline_mode is set.
        if self.dec_modes.newline_mode {
            self.screen.carriage_return();
        }
        self.screen.line_feed(self.current_attrs.background);
    }

    #[inline]
    fn handle_shift_out(&mut self) {
        self.gl_is_g1 = true;
    }

    #[inline]
    fn handle_shift_in(&mut self) {
        self.gl_is_g1 = false;
    }

    #[inline]
    fn stamp_printed_hyperlink(&mut self, pre_cursor: crate::types::cursor::Cursor, width: usize) {
        if let Some(uri) = &self.osc_data.hyperlink.uri {
            let cursor_after = *self.screen.cursor();
            let (write_row, write_col) = hyperlink_write_position(pre_cursor, cursor_after);
            if let Some(cell) = self.screen.get_cell_mut(write_row, write_col) {
                cell.set_hyperlink_id(Some(Arc::clone(uri)));
            }
            if width > 1 {
                if let Some(cell) = self.screen.get_cell_mut(write_row, write_col + 1) {
                    cell.set_hyperlink_id(Some(Arc::clone(uri)));
                }
            }
        }
    }

    #[inline]
    fn note_vte_callback(&mut self, ground: bool) {
        self.vte_callback_count = self.vte_callback_count.saturating_add(1);
        self.vte_last_ground = ground;
    }

    #[inline]
    fn prepare_vte_callback(&mut self, ground: bool) {
        self.flush_print_buf();
        // DEC mode 2027: any non-print VTE callback (control char, CSI cursor
        // move, OSC, ESC, DCS, screen edit) interrupts a grapheme cluster. Clear
        // the continuation state so a stray ZWJ or lone RI cannot reach forward
        // and corrupt a later, unrelated cell.
        if self.dec_modes.grapheme_clustering
            && (self.grapheme_join_pending || self.regional_indicator_pending)
        {
            self.clear_grapheme_cluster_state();
        }
        self.note_vte_callback(ground);
    }
}

#[cfg(test)]
#[path = "tests/vte_handler.rs"]
mod tests;
