
/// Handle Kitty keyboard mode push (CSI > Ps u).
///
/// Pushes the current keyboard flags onto the stack (capped at 64 entries)
/// and sets the new flags from `params`.
///
/// # See Also
/// - [`handle_kitty_kb_pop`] — restore the previous flags from the stack
/// - [`handle_kitty_kb_query`] — query the current flags without modifying state
#[inline]
pub fn handle_kitty_kb_push(term: &mut crate::TerminalCore, params: &vte::Params) {
    let flags = params
        .iter()
        .next()
        .and_then(|p| p.first().copied())
        .unwrap_or(0);
    if term.dec_modes.keyboard_flags_stack.len() < KEYBOARD_FLAGS_STACK_MAX {
        term.dec_modes
            .keyboard_flags_stack
            .push(term.dec_modes.keyboard_flags);
    }
    term.dec_modes.keyboard_flags = u32::from(flags);
}

/// Handle Kitty keyboard mode pop (CSI < u).
///
/// Pops the top entry from the keyboard flags stack and restores it
/// as the current `keyboard_flags`.  No-op when the stack is empty.
///
/// # See Also
/// - [`handle_kitty_kb_push`] — save the current flags and set new ones
/// - [`handle_kitty_kb_query`] — query the current flags without modifying state
#[inline]
pub fn handle_kitty_kb_pop(term: &mut crate::TerminalCore) {
    if let Some(prev) = term.dec_modes.keyboard_flags_stack.pop() {
        term.dec_modes.keyboard_flags = prev;
    } else {
        term.dec_modes.keyboard_flags = 0;
    }
}

/// Handle CSI ? u — Query Kitty keyboard flags.
///
/// Responds with `ESC [ ? <flags> u` where `<flags>` is the current
/// keyboard protocol enhancement bitmask.
///
/// # See Also
/// - [`handle_kitty_kb_push`] — save the current flags and set new ones
/// - [`handle_kitty_kb_pop`] — restore the previous flags from the stack
#[inline]
pub fn handle_kitty_kb_query(term: &mut crate::TerminalCore) {
    let response = format!("\x1b[?{}u", term.dec_modes.keyboard_flags);
    term.meta.pending_responses.push(response.into_bytes());
}

/// Handle DSR 996 — color scheme query (Contour/Ghostty mode 2031 companion).
///
/// Sequence: CSI ? 996 n
/// Response: CSI ? 997 ; 1 n (dark) or CSI ? 997 ; 2 n (light), determined by
/// the current `meta.color_scheme_dark` state — set from Elisp via
/// `kuro_core_set_color_scheme` so Emacs can advertise its actual theme.
///
/// `color_scheme_dark` lives on `TerminalMeta` (Emacs-owned host state), NOT
/// on `DecModes` (PTY-settable state).
///
/// See: <https://contour-terminal.org/vt-extensions/color-palette-update-notifications/>
#[inline]
pub fn handle_dsr_color_scheme(term: &mut crate::TerminalCore) {
    let bytes: &[u8] = if term.meta.color_scheme_dark {
        b"\x1b[?997;1n"
    } else {
        b"\x1b[?997;2n"
    };
    term.meta.pending_responses.push(bytes.to_vec());
}

/// Pure-fn body of `kuro_core_set_color_scheme` defun — extracted so unit
/// tests in this file can exercise the state-update + notification logic
/// without going through the FFI layer.
///
/// Updates `core.meta.color_scheme_dark` to `is_dark`. When the value
/// actually changes AND mode 2031 (`color_scheme_notifications`) is enabled,
/// pushes the corresponding `CSI ? 997 ; Ps n` unsolicited notification to
/// `meta.pending_responses` (Ps=1 dark, Ps=2 light).
///
/// Returns `true` if the stored state changed, `false` if it was already at
/// the requested value (idempotent — repeat calls with the same value are a
/// no-op and push zero bytes).
#[inline]
pub(crate) fn apply_color_scheme(core: &mut crate::TerminalCore, is_dark: bool) -> bool {
    let changed = core.meta.color_scheme_dark != is_dark;
    if changed {
        core.meta.color_scheme_dark = is_dark;
        if core.dec_modes.color_scheme_notifications {
            let bytes: &[u8] = if is_dark {
                b"\x1b[?997;1n"
            } else {
                b"\x1b[?997;2n"
            };
            core.meta.pending_responses.push(bytes.to_vec());
        }
    }
    changed
}
