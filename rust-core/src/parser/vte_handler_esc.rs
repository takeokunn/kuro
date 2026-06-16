use crate::parser;
use crate::TerminalCore;

/// Dispatch body for ESC sequences — extracted from `esc_dispatch` to keep vte_handler.rs ≤ 500L.
#[inline]
pub(super) fn handle_esc_dispatch(term: &mut TerminalCore, intermediates: &[u8], byte: u8) {
    match (intermediates, byte) {
        ([], b'7') => term.save_cursor(), // DECSC: Save cursor position and attributes
        ([], b'8') => term.restore_cursor(), // DECRC: Restore cursor position and attributes
        ([], b'c') => term.reset(),       // RIS: Full terminal reset
        ([], b'H') => {
            // HTS: Horizontal tab set at current cursor column
            parser::tabs::handle_hts(&term.screen, &mut term.tab_stops);
        }
        ([], b'M') => {
            // RI: Reverse Index — move cursor up one line, scroll down if at top of scroll region
            parser::scroll::handle_ri(term);
        }
        ([], b'D') => {
            // IND: Index — move cursor down one line, scroll up if at bottom of scroll region
            term.screen.line_feed(term.current_attrs.background);
        }
        ([], b'E') => {
            // NEL: Next Line — CR + LF
            term.screen.carriage_return();
            term.screen.line_feed(term.current_attrs.background);
        }
        ([], b'=') => {
            // DECKPAM: application keypad mode
            term.dec_modes.app_keypad = true;
        }
        ([], b'>') => {
            // DECKPNM: normal keypad mode
            term.dec_modes.app_keypad = false;
        }
        // SCS — Select Character Set
        // ESC ( 0 → designate G0 as DEC Special Graphics (line drawing)
        // ESC ( B → designate G0 as US ASCII
        (b"(", b'0') => {
            term.g0_charset = crate::types::charset::CharsetType::DecLineDrawing;
        }
        (b"(", b'B') => {
            term.g0_charset = crate::types::charset::CharsetType::Ascii;
        }
        // ESC ) 0 → designate G1 as DEC Special Graphics (line drawing)
        // ESC ) B → designate G1 as US ASCII
        (b")", b'0') => {
            term.g1_charset = crate::types::charset::CharsetType::DecLineDrawing;
        }
        (b")", b'B') => {
            term.g1_charset = crate::types::charset::CharsetType::Ascii;
        }
        // DEC line-height/width attributes (ESC # 3/4/5/6) — silently accepted.
        // These set double-height-top, double-height-bottom, single-width, and
        // double-width line modes. Kuro has no per-line width state, but accepting
        // them without panic is required for VT compliance.
        (b"#", b'3' | b'4' | b'5' | b'6') => {}
        // DECALN — Screen Alignment Pattern (ESC # 8)
        // Fills every cell with 'E' using default SGR attributes and homes the cursor.
        (b"#", b'8') => {
            let rows = term.screen.rows() as usize;
            let cols = term.screen.cols() as usize;
            let default_attrs = crate::types::cell::SgrAttributes::default();
            for row in 0..rows {
                term.screen.move_cursor(row, 0);
                for _ in 0..cols {
                    term.screen.print('E', default_attrs, false);
                }
            }
            term.screen.move_cursor(0, 0);
        }
        _ => {
            // Unknown ESC sequence — silently ignore
        }
    }
}
