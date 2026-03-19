//! Insert and delete operations for VTE compliance
//!
//! This module implements:
//! - IL  (CSI Ps L): Insert Lines
//! - DL  (CSI Ps M): Delete Lines
//! - ICH (CSI Ps @): Insert Characters
//! - DCH (CSI Ps P): Delete Characters
//! - ECH (CSI Ps X): Erase Characters

/// Dispatch IL / DL / ICH / DCH / ECH sequences
pub fn handle_insert_delete(term: &mut crate::TerminalCore, params: &vte::Params, c: char) {
    match c {
        'L' => csi_il(term, params),
        'M' => csi_dl(term, params),
        '@' => csi_ich(term, params),
        'P' => csi_dch(term, params),
        'X' => csi_ech(term, params),
        _ => {}
    }
}

/// Extract the first parameter, defaulting to 1 (minimum 1).
fn get_param(params: &vte::Params) -> usize {
    params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(1)
        .max(1) as usize
}

/// IL — Insert Lines (CSI Ps L)
fn csi_il(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = get_param(params);
    term.screen.insert_lines(n);
}

/// DL — Delete Lines (CSI Ps M)
fn csi_dl(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = get_param(params);
    term.screen.delete_lines(n);
}

/// ICH — Insert Characters (CSI Ps @)
fn csi_ich(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = get_param(params);
    let attrs = term.current_attrs;
    term.screen.insert_chars(n, attrs);
}

/// DCH — Delete Characters (CSI Ps P)
fn csi_dch(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = get_param(params);
    term.screen.delete_chars(n);
}

/// ECH — Erase Characters (CSI Ps X)
fn csi_ech(term: &mut crate::TerminalCore, params: &vte::Params) {
    let n = get_param(params);
    let attrs = term.current_attrs;
    term.screen.erase_chars(n, attrs);
}

#[cfg(test)]
#[path = "tests/insert_delete.rs"]
mod tests;
