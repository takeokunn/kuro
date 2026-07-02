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
            let byte = u8::try_from(u32::from(c)).expect("ASCII char fits in u8");
            self.print_buf.push(byte);
            return true;
        }
        false
    }

    #[inline]
    fn handle_combining_char(&mut self, c: char, width: Option<usize>) -> bool {
        if !should_treat_as_combining_char(c, width) {
            return false;
        }

        let cursor = *self.screen.cursor();
        if let Some((row, col)) = combining_attach_position(cursor, usize::from(self.screen.cols()))
        {
            self.screen.attach_combining(row, col, c);
        } else {
            self.screen
                .print(c, self.current_attrs, self.dec_modes.auto_wrap);
        }
        true
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
            let last_col = usize::from(self.screen.cols()).saturating_sub(1);
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
        self.note_vte_callback(ground);
    }
}

#[cfg(test)]
#[path = "tests/vte_handler.rs"]
mod tests;
