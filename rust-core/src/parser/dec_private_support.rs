//! DEC private mode support helpers.

#[inline]
fn for_each_mode(params: &vte::Params, mut f: impl FnMut(u16)) {
    for param_group in params {
        for &mode in param_group {
            f(mode);
        }
    }
}

#[inline]
fn apply_alternate_screen_set(term: &mut crate::TerminalCore, mode: u16) {
    match mode {
        // Alternate screen (?47): switch without cursor save/restore.
        47 => term.screen.switch_to_alternate(),
        // Alternate screen (?1047): switch to alt screen and clear it on entry.
        1047 => {
            term.screen.switch_to_alternate();
            let rows = term.screen.rows() as usize;
            term.screen.clear_lines(0, rows);
            term.screen.mark_all_dirty();
        }
        // Alternate screen (?1049): save SGR state before switching buffers.
        // Applications like vim/htop set colors before entering the alt screen;
        // without saving/restoring the primary screen would inherit those colors.
        1049 => {
            term.saved_primary_attrs = Some(term.current_attrs);
            term.screen.switch_to_alternate();
        }
        _ => {}
    }
}

#[inline]
fn apply_alternate_screen_reset(term: &mut crate::TerminalCore, mode: u16) {
    match mode {
        // Alternate screen (?47 / ?1047): switch back without cursor restore.
        47 | 1047 if term.dec_modes.alternate_screen => {
            term.screen.switch_to_primary();
        }
        // Alternate screen (?1049): restore primary buffer and SGR state.
        // Guard on `alternate_screen` being set so the switch only fires once.
        // `.take()` ensures saved attrs are consumed and cannot be restored twice.
        1049 if term.dec_modes.alternate_screen => {
            term.screen.switch_to_primary();
            if let Some(attrs) = term.saved_primary_attrs.take() {
                term.current_attrs = attrs;
            }
        }
        _ => {}
    }
}

/// Handle ANSI mode set/reset (`CSI Ps h` / `CSI Ps l`, no `?` intermediate).
///
/// Implements the subset of ANSI X3.64 modes that Kuro tracks:
/// - Mode 4 (IRM): Insert/Replace Mode
/// - Mode 20 (LNM): Linefeed/Newline Mode
#[inline]
pub fn handle_ansi_modes(term: &mut crate::TerminalCore, params: &vte::Params, value: bool) {
    for_each_mode(params, |mode| match mode {
        4 => term.dec_modes.insert_mode = value,
        20 => term.dec_modes.newline_mode = value,
        _ => {}
    });
}

/// Handle ANSI DECRQM — ANSI mode query (CSI Ps $ p → CSI Ps ; status $ y, no `?`).
///
/// Reports the status of ANSI modes: 1 = set, 2 = reset, 0 = unrecognized.
/// Currently tracks IRM (mode 4) and LNM (mode 20).
#[inline]
pub fn handle_ansi_decrqm(term: &mut crate::TerminalCore, params: &vte::Params) {
    for_each_mode(params, |mode| {
        let status: u8 = match mode {
            4 => 2 - u8::from(term.dec_modes.insert_mode),
            20 => 2 - u8::from(term.dec_modes.newline_mode),
            _ => 0, // not recognized
        };
        // ANSI DECRPM response has NO '?' prefix (unlike DEC private).
        let response = format!("\x1b[{mode};{status}$y");
        term.meta.pending_responses.push(response.into_bytes());
    });
}

/// Handle DECRQM — DEC private mode query (CSI ? Ps $ p → CSI ? Ps ; status $ y)
///
/// For each queried mode, returns status: 1 = set, 2 = reset, 0 = not recognised.
#[inline]
pub fn handle_decrqm(term: &mut crate::TerminalCore, params: &vte::Params) {
    for_each_mode(params, |mode| {
        let status: u8 = match term.dec_modes.get_mode(mode) {
            Some(true) => 1,  // set
            Some(false) => 2, // reset
            None => 0,        // not recognized
        };
        let response = format!("\x1b[?{mode};{status}$y");
        term.meta.pending_responses.push(response.into_bytes());
    });
}

/// Apply a single DEC private mode set (CSI ? Ps h) with its side effects.
///
/// Calls `DecModes::set_mode` first, then triggers the mode-specific side
/// effect that requires the updated state to already be recorded.
#[inline]
pub fn apply_mode_set(term: &mut crate::TerminalCore, mode: u16) {
    term.dec_modes.set_mode(mode);
    match mode {
        // DECOM (?6): cursor moves to top of scroll region on activation.
        6 => {
            let top = term.screen.get_scroll_region().top;
            term.screen.move_cursor(top, 0);
        }
        47 | 1047 | 1049 => apply_alternate_screen_set(term, mode),
        // In-band resize (?2048): emit an immediate report of the current size
        // on every enable, per spec ("when first enabled, the terminal MUST
        // send a report of the current size"; re-enabling reports again).
        2048 => term.push_in_band_resize_report(),
        _ => {}
    }
}

/// Apply a single DEC private mode reset (CSI ? Ps l) with its side effects.
///
/// Side effects that depend on reading the *current* (pre-reset) state are
/// handled first; `DecModes::reset_mode` is called last to clear the bit.
#[inline]
pub fn apply_mode_reset(term: &mut crate::TerminalCore, mode: u16) {
    match mode {
        // DECOM (?6): cursor returns to absolute home position.
        6 => term.screen.move_cursor(0, 0),
        47 | 1047 | 1049 => apply_alternate_screen_reset(term, mode),
        // Synchronized output (?2026): force a full redraw to flush the batch.
        // Guard on the flag still being set so mark_all_dirty fires exactly once.
        2026 if term.dec_modes.synchronized_output => {
            term.screen.mark_all_dirty();
        }
        _ => {}
    }
    term.dec_modes.reset_mode(mode);
}

/// Handle DEC private mode sequences (CSI ? Pm h/l).
///
/// - CSI ? Pm h — set each mode in `params` via [`apply_mode_set`]
/// - CSI ? Pm l — reset each mode in `params` via [`apply_mode_reset`]
#[inline]
pub fn handle_dec_modes(term: &mut crate::TerminalCore, params: &vte::Params, set: bool) {
    for_each_mode(params, |mode| {
        if set {
            apply_mode_set(term, mode);
        } else {
            apply_mode_reset(term, mode);
        }
    });
}
