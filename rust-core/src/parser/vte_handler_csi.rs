use super::PALETTE_STACK_MAX;
use crate::parser;
use crate::TerminalCore;

macro_rules! dispatch_if_handled {
    ($call:expr) => {
        if $call {
            return;
        }
    };
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct ModifyOtherKeysLevel(u8);

impl ModifyOtherKeysLevel {
    fn from_param(value: u16) -> Option<Self> {
        match value {
            0..=2 => u8::try_from(value).ok().map(Self),
            _ => None,
        }
    }
}

impl From<ModifyOtherKeysLevel> for u8 {
    fn from(level: ModifyOtherKeysLevel) -> Self {
        level.0
    }
}

#[inline]
fn handle_csi_dsr_color_scheme_query(tc: &mut TerminalCore, params: &vte::Params) {
    // CSI ? Ps n — DEC DSR queries
    // See: https://contour-terminal.org/vt-extensions/color-palette-update-notifications/
    for param_group in params {
        for &ps in param_group {
            if ps == 996 {
                parser::dec_private::handle_dsr_color_scheme(tc);
            }
        }
    }
}

#[inline]
fn handle_csi_modify_other_keys(tc: &mut TerminalCore, params: &vte::Params) {
    // XTMODKEYS — modifyOtherKeys (CSI > type ; value m)
    // type 4 = modifyOtherKeys; value 0/1/2 = disabled/level1/level2.
    // We record the setting for type 4; other types are silently accepted.
    let mut iter = params.iter();
    let key_type = iter.next().and_then(|p| p.first()).copied().unwrap_or(0);
    let value = iter.next().and_then(|p| p.first()).copied().unwrap_or(0);
    if key_type == 4 {
        if let Some(level) = ModifyOtherKeysLevel::from_param(value) {
            tc.dec_modes.modify_other_keys = u8::from(level);
        }
    }
}

#[inline]
fn handle_csi_da1_response(tc: &mut TerminalCore) {
    // DA1 (Primary): ESC[c or ESC[0c → respond with the terminal's capability list.
    // Attributes: 1 = 132 columns, 2 = printer/advanced video, 4 = Sixel graphics.
    tc.meta.pending_responses.push(b"\x1b[?1;2;4c".to_vec());
}

#[inline]
fn handle_csi_da2_response(tc: &mut TerminalCore) {
    // DA2 (Secondary Device Attributes): ESC[>c or ESC[>0c
    tc.meta.pending_responses.push(b"\x1b[>1;10;0c".to_vec());
}

#[inline]
fn handle_csi_xtversion_response(tc: &mut TerminalCore) {
    // XTVERSION — terminal version identification: CSI > q → DCS > | name ST
    tc.meta
        .pending_responses
        .push(b"\x1bP>|kuro-1.0.0\x1b\\".to_vec());
}

#[inline]
fn handle_csi_da3_response(tc: &mut TerminalCore) {
    // DA3 (Tertiary Device Attributes): ESC[=c or ESC[=0c
    // Response: DCS ! | <unit-id-hex> ST. Kuro unit id = "00000000".
    // See: https://vt100.net/docs/vt510-rm/DA3.html
    tc.meta
        .pending_responses
        .push(b"\x1bP!|00000000\x1b\\".to_vec());
}

#[inline]
fn handle_csi_palette_stack_push(tc: &mut TerminalCore) {
    // XTPUSHCOLORS — save 256-color palette onto stack (CSI # P)
    // Capped at 10 entries (same as xterm's colorSaveCount default).
    if tc.osc_data.palette_stack.len() < PALETTE_STACK_MAX {
        tc.osc_data.palette_stack.push(tc.osc_data.palette.clone());
    }
}

#[inline]
fn handle_csi_palette_stack_pop(tc: &mut TerminalCore) {
    // XTPOPCOLORS — restore palette from stack (CSI # Q)
    if let Some(saved) = tc.osc_data.palette_stack.pop() {
        tc.osc_data.restore_palette(saved);
    }
}

#[inline]
fn handle_csi_palette_stack_report(tc: &mut TerminalCore) {
    // XTREPORTCOLORS — report palette stack depth (CSI # R → CSI N # S)
    let n = tc.osc_data.palette_stack.len();
    let response = format!("\x1b[{}#S", n);
    tc.meta.pending_responses.push(response.into_bytes());
}

#[inline]
fn handle_csi_repeat_last_printed_char(tc: &mut TerminalCore, params: &vte::Params) {
    // REP — Repeat Character (CSI Ps b)
    // Repeats the last printed character Ps times using current SGR attributes.
    if let Some(ch) = tc.last_printed_char {
        let n = params
            .iter()
            .next()
            .and_then(|p| p.iter().next())
            .copied()
            .unwrap_or(1)
            .max(1);
        for _ in 0..n {
            tc.screen
                .print(ch, tc.current_attrs, tc.dec_modes.auto_wrap);
        }
    }
}

#[inline]
fn handle_csi_prefixed_dispatch(
    tc: &mut TerminalCore,
    params: &vte::Params,
    intermediates: &[u8],
    c: char,
) -> bool {
    match intermediates.first() {
        Some(b'?') => {
            handle_csi_dec_prefixed_dispatch(tc, params, intermediates, c);
            true
        }
        Some(b'>') => {
            handle_csi_kitty_prefixed_dispatch(tc, params, c);
            true
        }
        Some(b'<') => {
            handle_csi_keyboard_pop_dispatch(tc, c);
            true
        }
        Some(b'=') => {
            handle_csi_da3_dispatch(tc, c);
            true
        }
        _ => false,
    }
}

fn handle_csi_dec_prefixed_dispatch(
    tc: &mut TerminalCore,
    params: &vte::Params,
    intermediates: &[u8],
    c: char,
) {
    match c {
        'h' | 'l' => {
            let set = c == 'h';
            parser::dec_private::handle_dec_modes(tc, params, set);
        }
        'u' => {
            // CSI ? u — Query keyboard flags
            parser::dec_private::handle_kitty_kb_query(tc);
        }
        'p' if intermediates.len() >= 2 && intermediates[1] == b'$' => {
            // DECRQM — DEC private mode query
            parser::dec_private::handle_decrqm(tc, params);
        }
        'n' => handle_csi_dsr_color_scheme_query(tc, params),
        // DECSED / DECSEL — Selective Erase (same as ED/EL; we don't track protection)
        'J' | 'K' => parser::erase::handle_erase(tc, params, c),
        _ => {}
    }
}

fn handle_csi_kitty_prefixed_dispatch(tc: &mut TerminalCore, params: &vte::Params, c: char) {
    match c {
        'u' => {
            // CSI > Ps u — Push and set keyboard flags (Kitty keyboard protocol)
            parser::dec_private::handle_kitty_kb_push(tc, params);
        }
        'c' => handle_csi_da2_response(tc),
        'q' => handle_csi_xtversion_response(tc),
        'm' => handle_csi_modify_other_keys(tc, params),
        _ => {}
    }
}

fn handle_csi_keyboard_pop_dispatch(tc: &mut TerminalCore, c: char) {
    if c == 'u' {
        // CSI < u — Pop keyboard flags (Kitty keyboard protocol)
        parser::dec_private::handle_kitty_kb_pop(tc);
    }
}

fn handle_csi_da3_dispatch(tc: &mut TerminalCore, c: char) {
    if c == 'c' {
        handle_csi_da3_response(tc);
    }
}

#[inline]
fn handle_csi_standard_status_dispatch(
    tc: &mut TerminalCore,
    params: &vte::Params,
    intermediates: &[u8],
    c: char,
) -> bool {
    match c {
        // Device Attribute queries — terminal must respond to avoid shell hangs
        // DA2 (Secondary, ESC[>c) is handled above in the '>' intermediates block.
        'c' if intermediates.is_empty() => handle_csi_da1_response(tc),
        // ANSI mode set/reset (CSI Ps h / CSI Ps l, no '?' intermediate)
        // Handles IRM (mode 4) and LNM (mode 20).
        'h' if intermediates.is_empty() => {
            parser::dec_private::handle_ansi_modes(tc, params, true);
        }
        'l' if intermediates.is_empty() => {
            parser::dec_private::handle_ansi_modes(tc, params, false);
        }
        // ANSI SCP/RCP - Save/Restore Cursor (CSI s / CSI u)
        // Save/restore the cursor position without disturbing other state.
        's' if intermediates.is_empty() => {
            tc.save_cursor();
        }
        'u' if intermediates.is_empty() => {
            tc.restore_cursor();
        }
        // DECSTR - Soft Terminal Reset (CSI ! p)
        'p' if intermediates == b"!" => {
            tc.soft_reset();
        }
        // DECRQM (ANSI) — query ANSI mode state (CSI Ps $ p, no '?').
        // Reports IRM (4) and LNM (20) status; unrecognized → status 0.
        'p' if intermediates == b"$" => {
            parser::dec_private::handle_ansi_decrqm(tc, params);
        }
        // DECREQTPARM — Request Terminal Parameters (CSI Ps x).
        // VT100 parameter report; apps use it as a liveness/identity probe.
        'x' if intermediates.is_empty() => {
            parser::csi::handle_decreqtparm(tc, params);
        }
        // XTWINOPS (CSI Ps t) — answer size-report queries (14/18/19);
        // window-manipulation and host-revealing ops are ignored (security).
        't' if intermediates.is_empty() => {
            parser::csi::handle_xtwinops(tc, params);
        }
        // REP — Repeat Character (CSI Ps b)
        // Repeats the last printed character Ps times using current SGR attributes.
        'b' if intermediates.is_empty() => handle_csi_repeat_last_printed_char(tc, params),
        _ => return false,
    }

    true
}

#[inline]
fn handle_csi_standard_sgr_dispatch(tc: &mut TerminalCore, params: &vte::Params, c: char) -> bool {
    match c {
        // SGR — Select Graphic Rendition (CSI Ps m)
        'm' => {
            parser::sgr::handle_sgr(tc, params);
        }
        _ => return false,
    }

    true
}

#[inline]
fn handle_csi_standard_spacing_dispatch(
    tc: &mut TerminalCore,
    params: &vte::Params,
    intermediates: &[u8],
    c: char,
) -> bool {
    match c {
        // DECSCUSR - Set Cursor Style (CSI Ps SP q)
        'q' if intermediates == b" " => {
            parser::csi::handle_decscusr(tc, params);
        }
        // SL — Scroll Left (CSI Ps SP @) — must precede the ICH '@' arm
        '@' if intermediates == b" " => {
            parser::scroll::handle_sl(tc, params);
        }
        // SR — Scroll Right (CSI Ps SP A) — must precede the CUU 'A' arm
        'A' if intermediates == b" " => {
            parser::scroll::handle_sr(tc, params);
        }
        // CHT — Cursor Horizontal Tab Forward (CSI Ps I)
        'I' if intermediates.is_empty() => {
            parser::tabs::handle_cht(&mut tc.screen, &tc.tab_stops, params);
        }
        // CBT — Cursor Backward Tab (CSI Ps Z)
        'Z' if intermediates.is_empty() => {
            parser::tabs::handle_cbt(&mut tc.screen, &tc.tab_stops, params);
        }
        // Tab clear (TBC)
        'g' => {
            parser::tabs::handle_tbc(&tc.screen, &mut tc.tab_stops, params);
        }
        _ => return false,
    }

    true
}

#[inline]
fn handle_csi_standard_cursor_dispatch(
    tc: &mut TerminalCore,
    params: &vte::Params,
    c: char,
) -> bool {
    match c {
        // Cursor positioning: CUP/CUU/CUD/CUF/CUB/CNL/CPL/VPA/CHA/HPA/HVP/DSR/HPR/VPR
        'H' | 'A' | 'B' | 'C' | 'D' | 'E' | 'F' | 'd' | 'G' | '`' | 'f' | 'n' | 'a' | 'e' => {
            parser::csi::handle_csi_cursor(tc, params, c);
        }
        _ => return false,
    }

    true
}

#[inline]
fn handle_csi_standard_edit_dispatch(
    tc: &mut TerminalCore,
    params: &vte::Params,
    intermediates: &[u8],
    c: char,
) -> bool {
    handle_csi_standard_erase_dispatch(tc, params, intermediates, c)
        || handle_csi_standard_scroll_dispatch(tc, params, c)
        || handle_csi_standard_insert_delete_dispatch(tc, params, intermediates, c)
}

#[inline]
fn handle_csi_standard_erase_dispatch(
    tc: &mut TerminalCore,
    params: &vte::Params,
    intermediates: &[u8],
    c: char,
) -> bool {
    match c {
        // Erase operations
        'J' | 'K' => {
            parser::erase::handle_erase(tc, params, c);
        }
        // DECCARA — Change Attributes in Rectangular Area (CSI Pt;Pl;Pb;Pr;Ps... $ r)
        'r' if intermediates == b"$" => {
            parser::erase::handle_deccara(tc, params);
        }
        // DECERA — Erase Rectangular Area (CSI Pt;Pl;Pb;Pr $ z)
        'z' if intermediates == b"$" => {
            parser::erase::handle_decera(tc, params);
        }
        // DECFRA — Fill Rectangular Area (CSI Pch;Pt;Pl;Pb;Pr $ x)
        'x' if intermediates == b"$" => {
            parser::erase::handle_decfra(tc, params);
        }
        // DECCRA — Copy Rectangular Area (CSI Pt;Pl;Pb;Pr;Pp;Pt2;Pl2;Pp2 $ v)
        'v' if intermediates == b"$" => {
            parser::erase::handle_deccra(tc, params);
        }
        _ => return false,
    }

    true
}

#[inline]
fn handle_csi_standard_scroll_dispatch(
    tc: &mut TerminalCore,
    params: &vte::Params,
    c: char,
) -> bool {
    match c {
        // Scroll operations ('T' and '^' are both SD; '^' is MINTTY/terminfo alias)
        'r' | 'S' | 'T' | '^' => {
            parser::scroll::handle_scroll(tc, params, c);
        }
        _ => return false,
    }

    true
}

#[inline]
fn handle_csi_standard_insert_delete_dispatch(
    tc: &mut TerminalCore,
    params: &vte::Params,
    intermediates: &[u8],
    c: char,
) -> bool {
    match c {
        // Insert / delete sequences (IL, DL, ICH, DCH, ECH)
        'L' | 'M' | '@' | 'P' | 'X' => {
            parser::insert_delete::handle_insert_delete(tc, params, c);
        }
        // DECIC — Insert Column(s) (CSI Ps ' })
        '}' if intermediates == b"'" => {
            parser::insert_delete::handle_decic(tc, params);
        }
        // DECDC — Delete Column(s) (CSI Ps ' ~)
        '~' if intermediates == b"'" => {
            parser::insert_delete::handle_decdc(tc, params);
        }
        _ => return false,
    }

    true
}

#[inline]
fn handle_csi_standard_palette_dispatch(
    tc: &mut TerminalCore,
    intermediates: &[u8],
    c: char,
) -> bool {
    match c {
        // XTPUSHCOLORS — save 256-color palette onto stack (CSI # P)
        // Must precede the insert/delete arm which also catches bare 'P' (DCH).
        // Capped at 10 entries (same as xterm's colorSaveCount default).
        'P' if intermediates == b"#" => handle_csi_palette_stack_push(tc),
        // XTPOPCOLORS — restore palette from stack (CSI # Q)
        'Q' if intermediates == b"#" => handle_csi_palette_stack_pop(tc),
        // XTREPORTCOLORS — report palette stack depth (CSI # R → CSI N # S)
        'R' if intermediates == b"#" => handle_csi_palette_stack_report(tc),
        // XTPUSHSGR — push current SGR attributes onto the stack (CSI # {)
        '{' if intermediates == b"#" => {
            tc.sgr_stack.push(tc.current_attrs);
        }
        // XTPOPSGR — pop and apply SGR attributes from the stack (CSI # })
        '}' if intermediates == b"#" => {
            if let Some(attrs) = tc.sgr_stack.pop() {
                tc.current_attrs = attrs;
            }
        }
        _ => return false,
    }

    true
}

#[inline]
fn handle_csi_standard_dispatch(
    tc: &mut TerminalCore,
    params: &vte::Params,
    intermediates: &[u8],
    c: char,
) {
    // Handle standard CSI sequences.
    dispatch_if_handled!(handle_csi_standard_status_dispatch(
        tc,
        params,
        intermediates,
        c
    ));
    dispatch_if_handled!(handle_csi_standard_sgr_dispatch(tc, params, c));
    dispatch_if_handled!(handle_csi_standard_spacing_dispatch(
        tc,
        params,
        intermediates,
        c
    ));
    dispatch_if_handled!(handle_csi_standard_cursor_dispatch(tc, params, c));
    // Palette stack opcodes use the `#` intermediate and share command letters
    // with insert/delete. Dispatch them first so `CSI #P/#Q/#R` is not
    // consumed by the plain edit path.
    dispatch_if_handled!(handle_csi_standard_palette_dispatch(tc, intermediates, c));
    dispatch_if_handled!(handle_csi_standard_edit_dispatch(
        tc,
        params,
        intermediates,
        c
    ));

    // Unknown/unhandled CSI sequences are silently ignored
}

#[inline]
pub(super) fn handle_csi_dispatch(
    tc: &mut TerminalCore,
    params: &vte::Params,
    intermediates: &[u8],
    c: char,
) {
    if handle_csi_prefixed_dispatch(tc, params, intermediates, c) {
        return;
    }

    handle_csi_standard_dispatch(tc, params, intermediates, c);
}
