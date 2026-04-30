//! DEC private mode handling

use crate::types::cursor::CursorShape;

/// DEC private mode state
#[expect(
    clippy::struct_excessive_bools,
    reason = "DecModes fields map 1:1 to VT DEC private mode numbers; bool semantics are the clearest representation for terminal state flags"
)]
#[derive(Debug, Clone)]
pub struct DecModes {
    /// Application Cursor Keys mode (DECCKM - ?1)
    /// When set, cursor keys send application codes (ESC OA etc.)
    /// When reset, cursor keys send ANSI cursor codes (ESC [ A etc.)
    pub app_cursor_keys: bool,

    /// Auto Wrap Mode (DECAWM - ?7)
    /// When set, cursor wraps to next line at right margin
    /// When reset, cursor stays at right margin
    pub auto_wrap: bool,

    /// Text Cursor Enable (DECTCEM - ?25)
    /// When set, cursor is visible
    /// When reset, cursor is hidden
    pub cursor_visible: bool,

    /// Alternate Screen Buffer (mode 1049)
    /// When set, use alternate screen buffer and save cursor state
    /// When reset, return to primary screen buffer and restore cursor state
    pub alternate_screen: bool,

    /// Bracketed Paste Mode (mode 2004)
    /// When set, paste operations are bracketed with ESC [ 200~ and ESC [ 201~
    /// When reset, paste is not bracketed
    pub bracketed_paste: bool,

    /// Mouse tracking mode:
    /// 0 = disabled, 1000 = normal, 1002 = button-event, 1003 = any-event
    pub mouse_mode: u16,

    /// SGR extended coordinate modifier (mode 1006)
    /// When true, use SGR format \e[<btn;col;rowM/m instead of X10 format
    pub mouse_sgr: bool,

    /// Application Keypad Mode (DECKPAM / DECKPNM)
    /// Set by ESC = (DECKPAM), cleared by ESC > (DECKPNM).
    /// Not a CSI ?h/l mode — handled directly in `esc_dispatch`.
    pub app_keypad: bool,

    /// DECOM (?6) - Origin Mode. When set, cursor addressing is relative to scroll region.
    pub origin_mode: bool,

    /// Focus events (?1004) - When set, terminal sends CSI I / CSI O on focus in/out
    pub focus_events: bool,

    /// Synchronized output (?2026) - When set, screen updates are batched
    pub synchronized_output: bool,

    /// DEC mode 2031: color scheme change notifications (Contour/Ghostty).
    /// When enabled, terminal proactively emits CSI ? 997 ; Ps n on theme change.
    /// See: <https://contour-terminal.org/vt-extensions/color-palette-update-notifications/>
    pub color_scheme_notifications: bool,

    /// Cursor shape (DECSCUSR)
    pub cursor_shape: CursorShape,

    /// Kitty keyboard protocol flags (current active flags bitmask)
    pub keyboard_flags: u32,

    /// Stack for push/pop keyboard flags (CSI > Ps u / CSI < u)
    pub keyboard_flags_stack: Vec<u32>,

    /// SGR pixel mouse mode (?1016) — report mouse positions in pixels
    pub mouse_pixel: bool,
}

impl Default for DecModes {
    fn default() -> Self {
        Self::new()
    }
}

impl DecModes {
    /// Create a new DEC modes structure with default values
    #[must_use]
    pub const fn new() -> Self {
        Self {
            app_cursor_keys: false,
            auto_wrap: true,      // Default: auto wrap enabled
            cursor_visible: true, // Default: cursor visible
            alternate_screen: false,
            bracketed_paste: false,
            mouse_mode: 0,
            mouse_sgr: false,
            app_keypad: false,
            origin_mode: false,
            focus_events: false,
            synchronized_output: false,
            color_scheme_notifications: false,
            cursor_shape: CursorShape::BlinkingBlock,
            keyboard_flags: 0,
            keyboard_flags_stack: Vec::new(),
            mouse_pixel: false,
        }
    }

    /// Apply a DEC private mode — shared implementation for set (`value=true`) and reset (`value=false`).
    ///
    /// Mouse tracking modes (1000/1002/1003) are special: set stores the mode number;
    /// reset always clears `mouse_mode` to 0 regardless of which mode number is given.
    #[inline]
    pub fn apply_mode(&mut self, mode: u16, value: bool) {
        match mode {
            1 => self.app_cursor_keys = value,
            6 => self.origin_mode = value,
            7 => self.auto_wrap = value,
            25 => self.cursor_visible = value,
            1004 => self.focus_events = value,
            1006 => self.mouse_sgr = value,
            1016 => self.mouse_pixel = value,
            1049 => self.alternate_screen = value,
            2004 => self.bracketed_paste = value,
            2026 => self.synchronized_output = value,
            2031 => self.color_scheme_notifications = value,
            // Mouse tracking: set stores the mode number; reset clears to 0.
            1000 | 1002 | 1003 => self.mouse_mode = if value { mode } else { 0 },
            _ => {}
        }
    }

    /// Set a DEC private mode
    #[inline]
    pub fn set_mode(&mut self, mode: u16) {
        self.apply_mode(mode, true);
    }

    /// Reset a DEC private mode
    #[inline]
    pub fn reset_mode(&mut self, mode: u16) {
        self.apply_mode(mode, false);
    }

    /// Query a DEC private mode state
    #[must_use]
    pub const fn get_mode(&self, mode: u16) -> Option<bool> {
        match mode {
            1 => Some(self.app_cursor_keys),
            6 => Some(self.origin_mode),
            7 => Some(self.auto_wrap),
            25 => Some(self.cursor_visible),
            1004 => Some(self.focus_events),
            1049 => Some(self.alternate_screen),
            2004 => Some(self.bracketed_paste),
            1000 => Some(self.mouse_mode == 1000),
            1002 => Some(self.mouse_mode == 1002),
            1003 => Some(self.mouse_mode == 1003),
            1006 => Some(self.mouse_sgr),
            1016 => Some(self.mouse_pixel),
            2026 => Some(self.synchronized_output),
            2031 => Some(self.color_scheme_notifications),
            _ => None,
        }
    }

    /// Check if tab stops are enabled (tabs always enabled in standard VT)
    /// This is a placeholder for future tab mode support
    #[must_use]
    pub const fn tab_stops_enabled(&self) -> bool {
        true
    }
}

/// Handle DECRQM — DEC private mode query (CSI ? Ps $ p → CSI ? Ps ; status $ y)
///
/// For each queried mode, returns status: 1 = set, 2 = reset, 0 = not recognised.
#[inline]
pub fn handle_decrqm(term: &mut crate::TerminalCore, params: &vte::Params) {
    for param_group in params {
        for &mode in param_group {
            let status: u8 = match term.dec_modes.get_mode(mode) {
                Some(true) => 1,  // set
                Some(false) => 2, // reset
                None => 0,        // not recognized
            };
            let response = format!("\x1b[?{mode};{status}$y");
            term.meta.pending_responses.push(response.into_bytes());
        }
    }
}

/// Apply a single DEC private mode set (CSI ? Ps h) with its side effects.
///
/// Calls [`DecModes::set_mode`] first, then triggers the mode-specific side
/// effect that requires the updated state to already be recorded.
#[inline]
fn apply_mode_set(term: &mut crate::TerminalCore, mode: u16) {
    term.dec_modes.set_mode(mode);
    match mode {
        // DECOM (?6): cursor moves to top of scroll region on activation.
        6 => {
            let top = term.screen.get_scroll_region().top;
            term.screen.move_cursor(top, 0);
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

/// Apply a single DEC private mode reset (CSI ? Ps l) with its side effects.
///
/// Side effects that depend on reading the *current* (pre-reset) state are
/// handled first; [`DecModes::reset_mode`] is called last to clear the bit.
#[inline]
fn apply_mode_reset(term: &mut crate::TerminalCore, mode: u16) {
    match mode {
        // DECOM (?6): cursor returns to absolute home position.
        6 => term.screen.move_cursor(0, 0),
        // Alternate screen (?1049): restore primary buffer and SGR state.
        // Guard on `alternate_screen` being set so the switch only fires once.
        // `.take()` ensures saved attrs are consumed and cannot be restored twice.
        1049 if term.dec_modes.alternate_screen => {
            term.screen.switch_to_primary();
            if let Some(attrs) = term.saved_primary_attrs.take() {
                term.current_attrs = attrs;
            }
        }
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
pub fn handle_dec_modes(term: &mut crate::TerminalCore, params: &vte::Params, set: bool) {
    for param_group in params {
        for &mode in param_group {
            if set {
                apply_mode_set(term, mode);
            } else {
                apply_mode_reset(term, mode);
            }
        }
    }
}

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
    if term.dec_modes.keyboard_flags_stack.len() < 64 {
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

#[cfg(test)]
#[path = "tests/dec_private.rs"]
mod tests;
