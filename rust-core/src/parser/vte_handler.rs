//! VTE Perform trait implementation for TerminalCore
//!
//! This module implements the `vte::Perform` trait, which is the callback
//! interface for the VTE parser. Each method handles a different class of
//! terminal escape sequences.

use crate::parser;
use crate::types;
use crate::TerminalCore;
use unicode_width::UnicodeWidthChar;

impl vte::Perform for TerminalCore {
    fn print(&mut self, c: char) {
        // Combining characters (Unicode width 0) are attached to the previous cell.
        if UnicodeWidthChar::width(c) == Some(0) {
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
        self.screen
            .print(c, self.current_attrs, self.dec_modes.auto_wrap);
    }

    fn execute(&mut self, byte: u8) {
        match byte {
            0x07 => self.bell_pending = true,
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
            0x0A..=0x0C => self.screen.line_feed(),
            0x0D => self.screen.carriage_return(),
            _ => {}
        }
    }

    fn csi_dispatch(&mut self, params: &vte::Params, intermediates: &[u8], _ignore: bool, c: char) {
        // Check for DEC private mode sequences (CSI ? Pm h/l) and CSI ? u (query keyboard flags)
        if !intermediates.is_empty() && intermediates[0] == b'?' {
            match c {
                'h' | 'l' => {
                    let set = c == 'h';
                    parser::dec_private::handle_dec_modes(self, params, set);
                }
                'u' => {
                    // CSI ? u — Query keyboard flags
                    let response = format!("\x1b[?{}u", self.dec_modes.keyboard_flags);
                    self.pending_responses.push(response.into_bytes());
                }
                'p' if intermediates.len() >= 2 && intermediates[1] == b'$' => {
                    // DECRQM — DEC private mode query: CSI ? Ps $ p → CSI ? Ps ; status $ y
                    for param_group in params {
                        for &mode in param_group {
                            let status: u8 = match self.dec_modes.get_mode(mode) {
                                Some(true) => 1,  // set
                                Some(false) => 2, // reset
                                None => 0,        // not recognized
                            };
                            let response = format!("\x1b[?{};{}$y", mode, status);
                            self.pending_responses.push(response.into_bytes());
                        }
                    }
                }
                _ => {}
            }
            return;
        }

        // CSI > Ps u — Push and set keyboard flags (Kitty keyboard protocol)
        if !intermediates.is_empty() && intermediates[0] == b'>' {
            match c {
                'u' => {
                    let flags = params
                        .iter()
                        .next()
                        .and_then(|p| p.first().copied())
                        .unwrap_or(0);
                    if self.dec_modes.keyboard_flags_stack.len() < 64 {
                        self.dec_modes
                            .keyboard_flags_stack
                            .push(self.dec_modes.keyboard_flags);
                    }
                    self.dec_modes.keyboard_flags = flags as u32;
                }
                'c' => {
                    // DA2 (Secondary Device Attributes): ESC[>c or ESC[>0c
                    self.pending_responses.push(b"\x1b[>1;10;0c".to_vec());
                }
                'q' => {
                    // XTVERSION — terminal version identification: CSI > q → DCS > | name ST
                    self.pending_responses.push(b"\x1bP>|kuro-1.0.0\x1b\\".to_vec());
                }
                _ => {}
            }
            return;
        }

        // CSI < u — Pop keyboard flags (Kitty keyboard protocol)
        if !intermediates.is_empty() && intermediates[0] == b'<' {
            if c == 'u' {
                if let Some(prev) = self.dec_modes.keyboard_flags_stack.pop() {
                    self.dec_modes.keyboard_flags = prev;
                } else {
                    self.dec_modes.keyboard_flags = 0;
                }
            }
            return;
        }

        // Handle standard CSI sequences
        match c {
            // Device Attribute queries — terminal must respond to avoid shell hangs
            // DA2 (Secondary, ESC[>c) is handled above in the '>' intermediates block.
            'c' => {
                if intermediates.is_empty() {
                    // DA1 (Primary): ESC[c or ESC[0c → respond with VT100 + advanced video
                    self.pending_responses.push(b"\x1b[?1;2c".to_vec());
                }
            }
            // DECSCUSR - Set Cursor Style (CSI Ps SP q)
            'q' if intermediates == b" " => {
                let ps = params
                    .iter()
                    .next()
                    .and_then(|p| p.first().copied())
                    .unwrap_or(0);
                self.dec_modes.cursor_shape = match ps {
                    0 | 1 => types::cursor::CursorShape::BlinkingBlock,
                    2 => types::cursor::CursorShape::SteadyBlock,
                    3 => types::cursor::CursorShape::BlinkingUnderline,
                    4 => types::cursor::CursorShape::SteadyUnderline,
                    5 => types::cursor::CursorShape::BlinkingBar,
                    6 => types::cursor::CursorShape::SteadyBar,
                    _ => types::cursor::CursorShape::BlinkingBlock,
                };
            }
            // DECSTR - Soft Terminal Reset (CSI ! p)
            'p' if intermediates == b"!" => {
                self.soft_reset();
            }
            // Cursor positioning
            'H' | 'A' | 'B' | 'C' | 'D' | 'd' | 'G' | 'f' | 'n' => {
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
            // Unknown/unhandled CSI sequences are silently ignored
            _ => {}
        }
    }

    /// Handle OSC (Operating System Command) sequences from the VTE parser.
    ///
    /// Delegates to [`parser::osc::handle_osc`] for the full implementation.
    fn osc_dispatch(&mut self, params: &[&[u8]], bell_terminated: bool) {
        parser::osc::handle_osc(self, params, bell_terminated);
    }

    fn esc_dispatch(&mut self, intermediates: &[u8], _ignore: bool, byte: u8) {
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
                let cursor_row = self.screen.cursor().row;
                let scroll_top = self.screen.get_scroll_region().top;
                if cursor_row == scroll_top {
                    self.screen.scroll_down(1);
                } else if cursor_row > 0 {
                    self.screen
                        .move_cursor(cursor_row - 1, self.screen.cursor().col);
                }
            }
            ([], b'D') => {
                // IND: Index — move cursor down one line, scroll up if at bottom of scroll region
                self.screen.line_feed();
            }
            ([], b'E') => {
                // NEL: Next Line — CR + LF
                self.screen.carriage_return();
                self.screen.line_feed();
            }
            ([], b'=') => {
                // DECKPAM: application keypad mode
                self.dec_modes.app_keypad = true;
            }
            ([], b'>') => {
                // DECKPNM: normal keypad mode
                self.dec_modes.app_keypad = false;
            }
            _ => {
                // Unknown ESC sequence — silently ignore
            }
        }
    }

    fn hook(&mut self, params: &vte::Params, intermediates: &[u8], ignore: bool, c: char) {
        parser::dcs::dcs_hook(self, params, intermediates, ignore, c);
    }

    fn put(&mut self, byte: u8) {
        parser::dcs::dcs_put(self, byte);
    }

    fn unhook(&mut self) {
        parser::dcs::dcs_unhook(self);
    }
}

#[cfg(test)]
mod tests {
    use crate::TerminalCore;

    #[test]
    fn test_vte_print() {
        let mut term = TerminalCore::new(24, 80);
        term.advance(&b"Hello"[..]);

        assert_eq!(term.screen.get_cell(0, 0).unwrap().char(), 'H');
        assert_eq!(term.screen.get_cell(0, 1).unwrap().char(), 'e');
        assert_eq!(term.screen.get_cell(0, 2).unwrap().char(), 'l');
        assert_eq!(term.screen.get_cell(0, 3).unwrap().char(), 'l');
        assert_eq!(term.screen.get_cell(0, 4).unwrap().char(), 'o');
    }

    #[test]
    fn test_vte_sgr_bold() {
        let mut term = TerminalCore::new(24, 80);
        // Set bold, print text, then verify bold is active (no reset)
        term.advance(&b"\x1b[1mBold"[..]);

        assert!(term.current_attrs.bold);
    }

    #[test]
    fn test_vte_cursor_movement() {
        let mut term = TerminalCore::new(24, 80);
        term.advance(&b"ABC\x1b[2D"[..]);

        // Should move back 2 columns
        assert_eq!(term.screen.cursor.col, 1);
    }

    /// LF (0x0A) should advance the cursor to the next row.
    #[test]
    fn test_execute_lf() {
        let mut term = TerminalCore::new(24, 80);
        let row_before = term.screen.cursor.row;
        term.advance(&b"\n"[..]);
        assert_eq!(
            term.screen.cursor.row,
            row_before + 1,
            "LF should move cursor down one row"
        );
    }

    /// CR (0x0D) should move the cursor to column 0 of the current row.
    #[test]
    fn test_execute_cr() {
        let mut term = TerminalCore::new(24, 80);
        // Move cursor to a non-zero column first
        term.advance(&b"Hello"[..]);
        assert!(
            term.screen.cursor.col > 0,
            "cursor should be past col 0 after printing"
        );
        term.advance(&b"\r"[..]);
        assert_eq!(
            term.screen.cursor.col, 0,
            "CR should return cursor to column 0"
        );
    }

    /// BS (0x08) at column 0 should not underflow — cursor stays at 0.
    #[test]
    fn test_execute_bs_at_start() {
        let mut term = TerminalCore::new(24, 80);
        // Cursor starts at (0, 0)
        assert_eq!(term.screen.cursor.col, 0);
        term.advance(&b"\x08"[..]);
        assert_eq!(
            term.screen.cursor.col, 0,
            "BS at col 0 should keep cursor at 0"
        );
    }

    /// HT (0x09) should move cursor right by at least one column to the next tab stop.
    #[test]
    fn test_execute_tab() {
        let mut term = TerminalCore::new(24, 80);
        // Cursor starts at column 0; default tab stop is at column 8
        let col_before = term.screen.cursor.col;
        term.advance(&b"\t"[..]);
        assert!(
            term.screen.cursor.col > col_before,
            "HT should move cursor right by at least 1 column"
        );
    }
}
