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

impl vte::Perform for TerminalCore {
    #[inline]
    fn print(&mut self, c: char) {
        self.vte_callback_count += 1;
        self.vte_last_ground = true;

        let c = self.translate_print_char(c);
        if self.buffer_ascii_print(c) {
            return;
        }

        self.flush_print_buf();

        let width = UnicodeWidthChar::width(c);
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
    }

    #[inline]
    fn execute(&mut self, byte: u8) {
        self.flush_print_buf();
        self.vte_callback_count += 1;
        self.vte_last_ground = true;
        match byte {
            0x05 => {
                // ENQ — Enquiry: respond with terminal answerback string.
                // Many terminal apps use this to identify the terminal type.
                self.meta.pending_responses.push(b"kuro".to_vec());
            }
            0x07 => self.meta.bell_pending = true,
            0x08 => {
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
            0x09 => {
                // HT - Horizontal Tab
                if self.dec_modes.tab_stops_enabled() {
                    parser::tabs::handle_ht(&mut self.screen, &self.tab_stops);
                } else {
                    // Fall back to default tab behavior if disabled
                    self.screen.tab();
                }
            }
            0x0A..=0x0C => {
                // LNM (mode 20): LF also performs CR when newline_mode is set.
                if self.dec_modes.newline_mode {
                    self.screen.carriage_return();
                }
                self.screen.line_feed(self.current_attrs.background);
            }
            0x0D => self.screen.carriage_return(),
            0x0E => self.gl_is_g1 = true, // SO — Shift Out (switch GL to G1)
            0x0F => self.gl_is_g1 = false, // SI — Shift In (switch GL to G0)
            _ => {}
        }
    }

    #[inline]
    fn csi_dispatch(&mut self, params: &vte::Params, intermediates: &[u8], _ignore: bool, c: char) {
        self.flush_print_buf();
        self.vte_callback_count += 1;
        self.vte_last_ground = true;
        csi::handle_csi_dispatch(self, params, intermediates, c);
    }

    /// Handle OSC (Operating System Command) sequences from the VTE parser.
    ///
    /// Delegates to `parser::osc::handle_osc` for the full implementation.
    #[inline]
    fn osc_dispatch(&mut self, params: &[&[u8]], bell_terminated: bool) {
        self.flush_print_buf();
        self.vte_callback_count += 1;
        self.vte_last_ground = true;
        parser::osc::handle_osc(self, params, bell_terminated);
    }

    #[inline]
    fn esc_dispatch(&mut self, intermediates: &[u8], _ignore: bool, byte: u8) {
        self.flush_print_buf();
        self.vte_callback_count += 1;
        self.vte_last_ground = true;
        esc::handle_esc_dispatch(self, intermediates, byte);
    }

    #[inline]
    fn hook(&mut self, params: &vte::Params, intermediates: &[u8], ignore: bool, c: char) {
        self.flush_print_buf();
        self.vte_callback_count += 1;
        self.vte_last_ground = false;
        parser::dcs::dcs_hook(self, params, intermediates, ignore, c);
    }

    #[inline]
    fn put(&mut self, byte: u8) {
        self.flush_print_buf();
        self.vte_callback_count += 1;
        self.vte_last_ground = false;
        parser::dcs::dcs_put(self, byte);
    }

    #[inline]
    fn unhook(&mut self) {
        self.flush_print_buf();
        self.vte_callback_count += 1;
        self.vte_last_ground = true;
        parser::dcs::dcs_unhook(self);
    }
}

impl TerminalCore {
    #[inline]
    fn translate_print_char(&self, c: char) -> char {
        if self.active_charset() == crate::types::charset::CharsetType::DecLineDrawing && c.is_ascii()
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

    #[inline]
    fn handle_combining_char(&mut self, c: char, width: Option<usize>) -> bool {
        if width == Some(0) || (width.is_none() && !c.is_control()) {
            let cursor = *self.screen.cursor();
            let (row, col) = if cursor.col > 0 {
                (cursor.row, cursor.col - 1)
            } else if cursor.row > 0 {
                let prev_row = cursor.row - 1;
                let last_col = self.screen.cols().saturating_sub(1) as usize;
                (prev_row, last_col)
            } else {
                self.screen
                    .print(c, self.current_attrs, self.dec_modes.auto_wrap);
                return true;
            };
            self.screen.attach_combining(row, col, c);
            return true;
        }
        false
    }

    #[inline]
    fn stamp_printed_hyperlink(&mut self, pre_cursor: crate::types::cursor::Cursor, width: usize) {
        if let Some(uri) = &self.osc_data.hyperlink.uri {
            let cursor_after = *self.screen.cursor();
            let (write_row, write_col) =
                if cursor_after.row != pre_cursor.row || cursor_after.col < pre_cursor.col {
                    (cursor_after.row, 0)
                } else {
                    (pre_cursor.row, pre_cursor.col)
                };
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
}

#[cfg(test)]
#[path = "tests/vte_handler.rs"]
mod tests;
