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
        let c = if self.active_charset() == crate::types::charset::CharsetType::DecLineDrawing
            && c.is_ascii()
        {
            crate::types::charset::translate_dec_line_drawing(c)
        } else {
            c
        };

        // ASCII fast-path: buffer printable ASCII and defer to batch flush.
        // Bypassed when IRM (Insert Mode) is active — each character needs
        // an individual ICH before printing, which requires direct dispatch.
        if c.is_ascii() && !self.dec_modes.insert_mode {
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

        // IRM (mode 4): insert one blank before printing (shifts existing content right).
        if self.dec_modes.insert_mode {
            self.screen.insert_chars(1, self.current_attrs);
        }
        self.screen
            .print(c, self.current_attrs, self.dec_modes.auto_wrap);

        // Track for REP (CSI Ps b) — only printable non-combining chars qualify.
        self.last_printed_char = Some(c);

        // Stamp hyperlink on the just-written cell(s) — nearly free
        // when no hyperlink is active (branch predictor skips).
        if let Some(uri) = &self.osc_data.hyperlink.uri {
            let width = w.unwrap_or(1);
            // The cell was written at (pre_row, pre_col) unless a wide char
            // at the last column caused a wrap, in which case it's at (new_row, 0).
            let cursor_after = *self.screen.cursor();
            let (write_row, write_col) =
                if cursor_after.row != pre_row || cursor_after.col < pre_col {
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
                    'n' => {
                        // CSI ? Ps n — DEC DSR queries
                        // See: https://contour-terminal.org/vt-extensions/color-palette-update-notifications/
                        for param_group in params {
                            for &ps in param_group {
                                if ps == 996 {
                                    parser::dec_private::handle_dsr_color_scheme(self);
                                }
                            }
                        }
                    }
                    // DECSED / DECSEL — Selective Erase (same as ED/EL; we don't track protection)
                    'J' | 'K' => parser::erase::handle_erase(self, params, c),
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
                    'm' => {
                        // XTMODKEYS — modifyOtherKeys (CSI > type ; value m)
                        // type 4 = modifyOtherKeys; value 0/1/2 = disabled/level1/level2.
                        // We record the setting for type 4; other types are silently accepted.
                        let mut iter = params.iter();
                        let key_type = iter
                            .next()
                            .and_then(|p| p.first())
                            .copied()
                            .unwrap_or(0);
                        let value = iter
                            .next()
                            .and_then(|p| p.first())
                            .copied()
                            .unwrap_or(0);
                        if key_type == 4 {
                            self.dec_modes.modify_other_keys = value.min(2) as u8;
                        }
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
            Some(b'=') => {
                if c == 'c' {
                    // DA3 (Tertiary Device Attributes): ESC[=c or ESC[=0c
                    // Response: DCS ! | <unit-id-hex> ST. Kuro unit id = "00000000".
                    // See: https://vt100.net/docs/vt510-rm/DA3.html
                    self.meta
                        .pending_responses
                        .push(b"\x1bP!|00000000\x1b\\".to_vec());
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
                    // DA1 (Primary): ESC[c or ESC[0c → respond with the terminal's
                    // capability list. Attributes: 1 = 132 columns, 2 = printer/
                    // advanced video, 4 = Sixel graphics. Advertising 4 is what
                    // lets Sixel-capable apps (image viewers, lsix, fastfetch's
                    // image backends) actually emit Sixel — the renderer has
                    // supported it all along; only the advertisement was missing.
                    self.meta.pending_responses.push(b"\x1b[?1;2;4c".to_vec());
                }
            }
            // DECSCUSR - Set Cursor Style (CSI Ps SP q)
            'q' if intermediates == b" " => {
                parser::csi::handle_decscusr(self, params);
            }
            // SL — Scroll Left (CSI Ps SP @) — must precede the ICH '@' arm
            '@' if intermediates == b" " => {
                parser::scroll::handle_sl(self, params);
            }
            // SR — Scroll Right (CSI Ps SP A) — must precede the CUU 'A' arm
            'A' if intermediates == b" " => {
                parser::scroll::handle_sr(self, params);
            }
            // ANSI mode set/reset (CSI Ps h / CSI Ps l, no '?' intermediate)
            // Handles IRM (mode 4) and LNM (mode 20).
            'h' if intermediates.is_empty() => {
                parser::dec_private::handle_ansi_modes(self, params, true);
            }
            'l' if intermediates.is_empty() => {
                parser::dec_private::handle_ansi_modes(self, params, false);
            }
            // DECSTR - Soft Terminal Reset (CSI ! p)
            'p' if intermediates == b"!" => {
                self.soft_reset();
            }
            // DECRQM (ANSI) — query ANSI mode state (CSI Ps $ p, no '?').
            // Reports IRM (4) and LNM (20) status; unrecognized → status 0.
            'p' if intermediates == b"$" => {
                parser::dec_private::handle_ansi_decrqm(self, params);
            }
            // DECREQTPARM — Request Terminal Parameters (CSI Ps x).
            // VT100 parameter report; apps use it as a liveness/identity probe.
            'x' if intermediates.is_empty() => {
                parser::csi::handle_decreqtparm(self, params);
            }
            // CHT — Cursor Horizontal Tab Forward (CSI Ps I)
            'I' if intermediates.is_empty() => {
                parser::tabs::handle_cht(&mut self.screen, &self.tab_stops, params);
            }
            // CBT — Cursor Backward Tab (CSI Ps Z)
            'Z' if intermediates.is_empty() => {
                parser::tabs::handle_cbt(&mut self.screen, &self.tab_stops, params);
            }
            // Cursor positioning: CUP/CUU/CUD/CUF/CUB/CNL/CPL/VPA/CHA/HPA/HVP/DSR/HPR/VPR
            'H' | 'A' | 'B' | 'C' | 'D' | 'E' | 'F' | 'd' | 'G' | '`' | 'f' | 'n' | 'a' | 'e' => {
                parser::csi::handle_csi_cursor(self, params, c);
            }
            // Erase operations
            'J' | 'K' => {
                parser::erase::handle_erase(self, params, c);
            }
            // DECCARA — Change Attributes in Rectangular Area (CSI Pt;Pl;Pb;Pr;Ps... $ r)
            'r' if intermediates == b"$" => {
                parser::erase::handle_deccara(self, params);
            }
            // Scroll operations ('T' and '^' are both SD; '^' is MINTTY/terminfo alias)
            'r' | 'S' | 'T' | '^' => {
                parser::scroll::handle_scroll(self, params, c);
            }
            // Tab clear (TBC)
            'g' => {
                parser::tabs::handle_tbc(&self.screen, &mut self.tab_stops, params);
            }
            // XTPUSHCOLORS — save 256-color palette onto stack (CSI # P)
            // Must precede the insert/delete arm which also catches bare 'P' (DCH).
            // Capped at 10 entries (same as xterm's colorSaveCount default).
            'P' if intermediates == b"#" => {
                if self.osc_data.palette_stack.len() < 10 {
                    self.osc_data.palette_stack.push(self.osc_data.palette.clone());
                }
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
            // XTWINOPS (CSI Ps t) — answer size-report queries (14/18/19);
            // window-manipulation and host-revealing ops are ignored (security).
            't' if intermediates.is_empty() => {
                parser::csi::handle_xtwinops(self, params);
            }
            // DECERA — Erase Rectangular Area (CSI Pt;Pl;Pb;Pr $ z)
            'z' if intermediates == b"$" => {
                parser::erase::handle_decera(self, params);
            }
            // DECFRA — Fill Rectangular Area (CSI Pch;Pt;Pl;Pb;Pr $ x)
            'x' if intermediates == b"$" => {
                parser::erase::handle_decfra(self, params);
            }
            // DECCRA — Copy Rectangular Area (CSI Pt;Pl;Pb;Pr;Pp;Pt2;Pl2;Pp2 $ v)
            'v' if intermediates == b"$" => {
                parser::erase::handle_deccra(self, params);
            }
            // DECIC — Insert Column(s) (CSI Ps ' })
            '}' if intermediates == b"'" => {
                parser::insert_delete::handle_decic(self, params);
            }
            // DECDC — Delete Column(s) (CSI Ps ' ~)
            '~' if intermediates == b"'" => {
                parser::insert_delete::handle_decdc(self, params);
            }
            // XTPOPCOLORS — restore palette from stack (CSI # Q)
            'Q' if intermediates == b"#" => {
                if let Some(saved) = self.osc_data.palette_stack.pop() {
                    self.osc_data.palette = saved;
                    self.osc_data.palette_dirty = true;
                }
            }
            // XTREPORTCOLORS — report palette stack depth (CSI # R → CSI N # S)
            'R' if intermediates == b"#" => {
                let n = self.osc_data.palette_stack.len();
                let response = format!("\x1b[{}#S", n);
                self.meta.pending_responses.push(response.into_bytes());
            }
            // XTPUSHSGR — push current SGR attributes onto the stack (CSI # {)
            '{' if intermediates == b"#" => {
                self.sgr_stack.push(self.current_attrs);
            }
            // XTPOPSGR — pop and apply SGR attributes from the stack (CSI # })
            '}' if intermediates == b"#" => {
                if let Some(attrs) = self.sgr_stack.pop() {
                    self.current_attrs = attrs;
                }
            }
            // REP — Repeat Character (CSI Ps b)
            // Repeats the last printed character Ps times using current SGR attributes.
            'b' if intermediates.is_empty() => {
                if let Some(c) = self.last_printed_char {
                    let n = params
                        .iter()
                        .next()
                        .and_then(|p| p.iter().next())
                        .copied()
                        .unwrap_or(1)
                        .max(1);
                    for _ in 0..n {
                        self.screen.print(c, self.current_attrs, self.dec_modes.auto_wrap);
                    }
                }
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
            // DEC line-height/width attributes (ESC # 3/4/5/6) — silently accepted.
            // These set double-height-top, double-height-bottom, single-width, and
            // double-width line modes. Kuro has no per-line width state, but accepting
            // them without panic is required for VT compliance.
            (b"#", b'3' | b'4' | b'5' | b'6') => {}
            // DECALN — Screen Alignment Pattern (ESC # 8)
            // Fills every cell with 'E' using default SGR attributes and homes the cursor.
            (b"#", b'8') => {
                let rows = self.screen.rows() as usize;
                let cols = self.screen.cols() as usize;
                let default_attrs = crate::types::cell::SgrAttributes::default();
                for row in 0..rows {
                    self.screen.move_cursor(row, 0);
                    for _ in 0..cols {
                        self.screen.print('E', default_attrs, false);
                    }
                }
                self.screen.move_cursor(0, 0);
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
