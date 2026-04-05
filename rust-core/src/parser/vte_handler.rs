//! VTE Perform trait implementation for `TerminalCore`
//!
//! This module implements the `vte::Perform` trait, which is the callback
//! interface for the VTE parser. Each method handles a different class of
//! terminal escape sequences.

use std::sync::Arc;

use crate::parser;
use crate::TerminalCore;
use unicode_width::UnicodeWidthChar;

impl vte::Perform for TerminalCore {
    #[inline]
    fn print(&mut self, c: char) {
        self.vte_callback_count += 1;
        self.vte_last_ground = true;

        // Charset translation: apply DEC line drawing substitution if active.
        // The comparison is nearly always false (branch predictor friendly).
        let c = if self.active_charset()
            == crate::types::charset::CharsetType::DecLineDrawing
            && c.is_ascii()
        {
            crate::types::charset::translate_dec_line_drawing(c)
        } else {
            c
        };

        // ASCII fast-path: buffer printable ASCII and defer to batch flush.
        // This avoids per-character Cell construction + width lookup overhead.
        if c.is_ascii() {
            self.print_buf.push(c as u8);
            return;
        }

        // Non-ASCII: flush any buffered ASCII first, then handle this character.
        self.flush_print_buf();

        // Combining characters (Unicode width 0) are attached to the previous cell.
        // Characters returning `None` from unicode-width (Variation Selectors
        // U+FE00–U+FE0F, interlinear annotations, tag characters, etc.) that
        // are not C0/C1 control characters are also treated as combining —
        // they are effectively zero-width and would otherwise waste a grid cell.
        let w = UnicodeWidthChar::width(c);
        if w == Some(0) || (w.is_none() && !c.is_control()) {
            // Attach to the cell just before the current cursor position
            let cursor = *self.screen.cursor();
            let (row, col) = if cursor.col > 0 {
                (cursor.row, cursor.col - 1)
            } else if cursor.row > 0 {
                // Cursor is at column 0; attach to last cell of previous row
                let prev_row = cursor.row - 1;
                let last_col = self.screen.cols().saturating_sub(1) as usize;
                (prev_row, last_col)
            } else {
                // No previous cell available; print as standalone character
                self.screen
                    .print(c, self.current_attrs, self.dec_modes.auto_wrap);
                return;
            };
            self.screen.attach_combining(row, col, c);
            return;
        }

        // Capture cursor position before printing so we can stamp the
        // hyperlink on the correct cell(s) afterward.  Single deref matches
        // the combining-char path above (line ~48: `let cursor = *self.screen.cursor()`).
        let pre_cursor = *self.screen.cursor();
        let pre_row = pre_cursor.row;
        let pre_col = pre_cursor.col;

        self.screen
            .print(c, self.current_attrs, self.dec_modes.auto_wrap);

        // Stamp hyperlink on the just-written cell(s) — nearly free
        // when no hyperlink is active (branch predictor skips).
        if let Some(uri) = &self.osc_data.hyperlink.uri {
            let width = w.unwrap_or(1);
            // The cell was written at (pre_row, pre_col) unless a wide char
            // at the last column caused a wrap, in which case it's at (new_row, 0).
            let cursor_after = *self.screen.cursor();
            let (write_row, write_col) = if cursor_after.row != pre_row
                || cursor_after.col < pre_col
            {
                // Wrap occurred — cell was placed at start of new row
                (cursor_after.row, 0)
            } else {
                (pre_row, pre_col)
            };
            if let Some(cell) = self.screen.get_cell_mut(write_row, write_col) {
                cell.set_hyperlink_id(Some(Arc::clone(uri)));
            }
            // For wide chars, also stamp the placeholder cell.
            // Reuse `uri' from the outer borrow — no redundant re-lookup needed.
            if width > 1 {
                if let Some(cell) = self.screen.get_cell_mut(write_row, write_col + 1) {
                    cell.set_hyperlink_id(Some(Arc::clone(uri)));
                }
            }
        }
    }

    #[inline]
    fn execute(&mut self, byte: u8) {
        self.flush_print_buf();
        self.vte_callback_count += 1;
        self.vte_last_ground = true;
        match byte {
            0x07 => self.meta.bell_pending = true,
            0x08 => self.screen.backspace(),
            0x09 => {
                // HT - Horizontal Tab
                if self.dec_modes.tab_stops_enabled() {
                    parser::tabs::handle_ht(&mut self.screen, &self.tab_stops);
                } else {
                    // Fall back to default tab behavior if disabled
                    self.screen.tab();
                }
            }
            0x0A..=0x0C => self.screen.line_feed(self.current_attrs.background),
            0x0D => self.screen.carriage_return(),
            0x0E => self.gl_is_g1 = true,  // SO — Shift Out (switch GL to G1)
            0x0F => self.gl_is_g1 = false,  // SI — Shift In (switch GL to G0)
            _ => {}
        }
    }

    #[inline]
    fn csi_dispatch(&mut self, params: &vte::Params, intermediates: &[u8], _ignore: bool, c: char) {
        self.flush_print_buf();
        self.vte_callback_count += 1;
        self.vte_last_ground = true;
        // Handle DEC-private and Kitty-protocol CSI sequences (CSI ? … / CSI > … / CSI < …).
        // A single `first()` call replaces three separate is_empty()+index checks.
        // Note: `b' '` (DECSCUSR) and `b'!'` (DECSTR) must fall through to the
        // standard match below, so only the three DEC-prefix bytes return early here.
        match intermediates.first() {
            Some(b'?') => {
                match c {
                    'h' | 'l' => {
                        let set = c == 'h';
                        parser::dec_private::handle_dec_modes(self, params, set);
                    }
                    'u' => {
                        // CSI ? u — Query keyboard flags
                        parser::dec_private::handle_kitty_kb_query(self);
                    }
                    'p' if intermediates.len() >= 2 && intermediates[1] == b'$' => {
                        // DECRQM — DEC private mode query
                        parser::dec_private::handle_decrqm(self, params);
                    }
                    _ => {}
                }
                return;
            }
            Some(b'>') => {
                match c {
                    'u' => {
                        // CSI > Ps u — Push and set keyboard flags (Kitty keyboard protocol)
                        parser::dec_private::handle_kitty_kb_push(self, params);
                    }
                    'c' => {
                        // DA2 (Secondary Device Attributes): ESC[>c or ESC[>0c
                        self.meta.pending_responses.push(b"\x1b[>1;10;0c".to_vec());
                    }
                    'q' => {
                        // XTVERSION — terminal version identification: CSI > q → DCS > | name ST
                        self.meta
                            .pending_responses
                            .push(b"\x1bP>|kuro-1.0.0\x1b\\".to_vec());
                    }
                    _ => {}
                }
                return;
            }
            Some(b'<') => {
                if c == 'u' {
                    // CSI < u — Pop keyboard flags (Kitty keyboard protocol)
                    parser::dec_private::handle_kitty_kb_pop(self);
                }
                return;
            }
            _ => {}
        }

        // Handle standard CSI sequences
        match c {
            // Device Attribute queries — terminal must respond to avoid shell hangs
            // DA2 (Secondary, ESC[>c) is handled above in the '>' intermediates block.
            'c' => {
                if intermediates.is_empty() {
                    // DA1 (Primary): ESC[c or ESC[0c → respond with VT100 + advanced video
                    self.meta.pending_responses.push(b"\x1b[?1;2c".to_vec());
                }
            }
            // DECSCUSR - Set Cursor Style (CSI Ps SP q)
            'q' if intermediates == b" " => {
                parser::csi::handle_decscusr(self, params);
            }
            // DECSTR - Soft Terminal Reset (CSI ! p)
            'p' if intermediates == b"!" => {
                self.soft_reset();
            }
            // Cursor positioning (includes CNL=E and CPL=F)
            'H' | 'A' | 'B' | 'C' | 'D' | 'E' | 'F' | 'd' | 'G' | 'f' | 'n' => {
                parser::csi::handle_csi_cursor(self, params, c);
            }
            // Erase operations
            'J' | 'K' => {
                parser::erase::handle_erase(self, params, c);
            }
            // Scroll operations
            'r' | 'S' | 'T' => {
                parser::scroll::handle_scroll(self, params, c);
            }
            // Tab clear (TBC)
            'g' => {
                parser::tabs::handle_tbc(&self.screen, &mut self.tab_stops, params);
            }
            // Insert / delete sequences (IL, DL, ICH, DCH, ECH)
            'L' | 'M' | '@' | 'P' | 'X' => {
                parser::insert_delete::handle_insert_delete(self, params, c);
            }
            // SGR - Select Graphic Rendition
            'm' => {
                parser::sgr::handle_sgr(self, params);
            }
            // ANSI SCP/RCP — save/restore cursor (same semantics as DECSC ESC 7 / DECRC ESC 8)
            's' if intermediates.is_empty() => {
                self.save_cursor();
            }
            'u' if intermediates.is_empty() => {
                self.restore_cursor();
            }
            // Unknown/unhandled CSI sequences are silently ignored
            _ => {}
        }
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
        match (intermediates, byte) {
            ([], b'7') => self.save_cursor(), // DECSC: Save cursor position and attributes
            ([], b'8') => self.restore_cursor(), // DECRC: Restore cursor position and attributes
            ([], b'c') => self.reset(),       // RIS: Full terminal reset
            ([], b'H') => {
                // HTS: Horizontal tab set at current cursor column
                parser::tabs::handle_hts(&self.screen, &mut self.tab_stops);
            }
            ([], b'M') => {
                // RI: Reverse Index — move cursor up one line, scroll down if at top of scroll region
                parser::scroll::handle_ri(self);
            }
            ([], b'D') => {
                // IND: Index — move cursor down one line, scroll up if at bottom of scroll region
                self.screen.line_feed(self.current_attrs.background);
            }
            ([], b'E') => {
                // NEL: Next Line — CR + LF
                self.screen.carriage_return();
                self.screen.line_feed(self.current_attrs.background);
            }
            ([], b'=') => {
                // DECKPAM: application keypad mode
                self.dec_modes.app_keypad = true;
            }
            ([], b'>') => {
                // DECKPNM: normal keypad mode
                self.dec_modes.app_keypad = false;
            }
            // SCS — Select Character Set
            // ESC ( 0 → designate G0 as DEC Special Graphics (line drawing)
            // ESC ( B → designate G0 as US ASCII
            (b"(", b'0') => {
                self.g0_charset = crate::types::charset::CharsetType::DecLineDrawing;
            }
            (b"(", b'B') => {
                self.g0_charset = crate::types::charset::CharsetType::Ascii;
            }
            // ESC ) 0 → designate G1 as DEC Special Graphics (line drawing)
            // ESC ) B → designate G1 as US ASCII
            (b")", b'0') => {
                self.g1_charset = crate::types::charset::CharsetType::DecLineDrawing;
            }
            (b")", b'B') => {
                self.g1_charset = crate::types::charset::CharsetType::Ascii;
            }
            _ => {
                // Unknown ESC sequence — silently ignore
            }
        }
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

#[cfg(test)]
#[path = "tests/vte_handler.rs"]
mod tests;
