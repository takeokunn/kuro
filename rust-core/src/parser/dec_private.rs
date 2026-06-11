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

    /// UTF-8 mouse encoding (?1005) — encode button/col/row as UTF-8 codepoints
    /// to support column numbers above 223 (superseded by SGR mode 1006 in practice)
    pub mouse_utf8: bool,

    /// SGR pixel mouse mode (?1016) — report mouse positions in pixels
    pub mouse_pixel: bool,

    /// In-band resize notifications (?2048) — when set, the terminal reports
    /// every size change via `CSI 48 ; rows ; cols ; ph ; pw t` directly in the
    /// PTY stream instead of relying solely on SIGWINCH.  Enabling (or
    /// re-enabling) the mode emits an immediate report of the current size.
    /// Pixel fields are always 0: the cell-based core has no pixel geometry.
    /// See: <https://gist.github.com/rockorager/e695fb2924d36b2bcf1fff4a3704bd83>
    pub resize_in_band: bool,
    /// modifyOtherKeys level from XTMODKEYS (CSI > 4 ; Ps m).
    /// 0 = disabled (default), 1 = modify other keys level 1, 2 = level 2.
    /// Stored so applications can query and restore the setting.
    pub modify_other_keys: u8,
    /// ANSI Insert/Replace Mode (IRM, `CSI 4 h` / `CSI 4 l`, no `?`).
    /// When true, printing a character inserts rather than overwrites.
    pub insert_mode: bool,
    /// ANSI Linefeed/Newline Mode (LNM, `CSI 20 h` / `CSI 20 l`, no `?`).
    /// When true, LF (0x0A) also performs a carriage return (like CR+LF).
    pub newline_mode: bool,
    /// DECSCNM — Screen Reverse Mode (?5).
    /// When true, the entire screen is displayed in reverse video.
    pub screen_reverse: bool,
    /// Allow DECCOLM (?40) — permits mode 3 (132-column) to function.
    pub allow_deccolm: bool,
    /// Reverse-wraparound mode (?45) — BS at col 0 wraps to previous line's last col.
    pub reverse_wraparound: bool,
    /// DECSDM (?80) — Sixel Display Mode.
    /// When set, sixel images are rendered without scrolling (DEC VT340 "display" mode).
    /// When reset (default), sixel images scroll normally.
    pub sixel_display_mode: bool,
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
            mouse_utf8: false,
            mouse_pixel: false,
            resize_in_band: false,
            modify_other_keys: 0,
            insert_mode: false,
            newline_mode: false,
            screen_reverse: false,
            allow_deccolm: false,
            reverse_wraparound: false,
            sixel_display_mode: false,
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
            5 => self.screen_reverse = value,
            6 => self.origin_mode = value,
            7 => self.auto_wrap = value,
            // Mode 12 — Start/Stop Blinking Cursor (DECBKM).
            // Toggle cursor blink: blink variants ↔ steady variants of current shape.
            12 => {
                use crate::types::cursor::CursorShape;
                self.cursor_shape = match (value, self.cursor_shape) {
                    (true,  CursorShape::SteadyBlock)     => CursorShape::BlinkingBlock,
                    (true,  CursorShape::SteadyUnderline) => CursorShape::BlinkingUnderline,
                    (true,  CursorShape::SteadyBar)       => CursorShape::BlinkingBar,
                    (false, CursorShape::BlinkingBlock)    => CursorShape::SteadyBlock,
                    (false, CursorShape::BlinkingUnderline)=> CursorShape::SteadyUnderline,
                    (false, CursorShape::BlinkingBar)      => CursorShape::SteadyBar,
                    _ => self.cursor_shape, // already in desired state
                };
            }
            25 => self.cursor_visible = value,
            40 => self.allow_deccolm = value,
            45 => self.reverse_wraparound = value,
            80 => self.sixel_display_mode = value,
            1004 => self.focus_events = value,
            // DECNKM (?66) — Numeric Keypad Mode: alias to app_keypad.
            // ?66h = application keypad, ?66l = numeric (same effect as ESC = / ESC >)
            66 => self.app_keypad = value,
            1005 => self.mouse_utf8 = value,
            1006 => self.mouse_sgr = value,
            1016 => self.mouse_pixel = value,
            47 | 1047 | 1049 => self.alternate_screen = value,
            2004 => self.bracketed_paste = value,
            2026 => self.synchronized_output = value,
            2031 => self.color_scheme_notifications = value,
            2048 => self.resize_in_band = value,
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
            5 => Some(self.screen_reverse),
            6 => Some(self.origin_mode),
            7 => Some(self.auto_wrap),
            // Mode 12: cursor is blinking when shape is a blinking variant
            12 => Some(matches!(
                self.cursor_shape,
                crate::types::cursor::CursorShape::BlinkingBlock
                    | crate::types::cursor::CursorShape::BlinkingUnderline
                    | crate::types::cursor::CursorShape::BlinkingBar
            )),
            25 => Some(self.cursor_visible),
            40 => Some(self.allow_deccolm),
            45 => Some(self.reverse_wraparound),
            80 => Some(self.sixel_display_mode),
            1004 => Some(self.focus_events),
            // Alternate-screen variants 47 / 1047 / 1049 all track the same
            // `alternate_screen` flag, so DECRQM reports the buffer's state for
            // any of them (status 2 when on the primary screen, 1 when on alt).
            47 | 1047 | 1049 => Some(self.alternate_screen),
            2004 => Some(self.bracketed_paste),
            1000 => Some(self.mouse_mode == 1000),
            1002 => Some(self.mouse_mode == 1002),
            1003 => Some(self.mouse_mode == 1003),
            66 => Some(self.app_keypad),
            1005 => Some(self.mouse_utf8),
            1006 => Some(self.mouse_sgr),
            1016 => Some(self.mouse_pixel),
            2026 => Some(self.synchronized_output),
            2031 => Some(self.color_scheme_notifications),
            2048 => Some(self.resize_in_band),
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

/// Handle ANSI mode set/reset (`CSI Ps h` / `CSI Ps l`, no `?` intermediate).
///
/// Implements the subset of ANSI X3.64 modes that Kuro tracks:
/// - Mode 4 (IRM): Insert/Replace Mode
/// - Mode 20 (LNM): Linefeed/Newline Mode
#[inline]
pub fn handle_ansi_modes(term: &mut crate::TerminalCore, params: &vte::Params, value: bool) {
    for param_group in params {
        for &mode in param_group {
            match mode {
                4  => term.dec_modes.insert_mode  = value,
                20 => term.dec_modes.newline_mode = value,
                _  => {}
            }
        }
    }
}

/// Handle ANSI DECRQM — ANSI mode query (CSI Ps $ p → CSI Ps ; status $ y, no `?`).
///
/// Reports the status of ANSI modes: 1 = set, 2 = reset, 0 = unrecognized.
/// Currently tracks IRM (mode 4) and LNM (mode 20).
#[inline]
pub fn handle_ansi_decrqm(term: &mut crate::TerminalCore, params: &vte::Params) {
    for param_group in params {
        for &mode in param_group {
            let status: u8 = match mode {
                4 => {
                    if term.dec_modes.insert_mode {
                        1
                    } else {
                        2
                    }
                }
                20 => {
                    if term.dec_modes.newline_mode {
                        1
                    } else {
                        2
                    }
                }
                _ => 0, // not recognized
            };
            // ANSI DECRPM response has NO '?' prefix (unlike DEC private).
            let response = format!("\x1b[{mode};{status}$y");
            term.meta.pending_responses.push(response.into_bytes());
        }
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
/// handled first; [`DecModes::reset_mode`] is called last to clear the bit.
#[inline]
fn apply_mode_reset(term: &mut crate::TerminalCore, mode: u16) {
    match mode {
        // DECOM (?6): cursor returns to absolute home position.
        6 => term.screen.move_cursor(0, 0),
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

/// Maximum depth of the Kitty keyboard flags push/pop stack (CSI > Ps u / CSI < u).
///
/// Matches the limit used by other terminal emulators (e.g. foot, kitty).
const KEYBOARD_FLAGS_STACK_MAX: usize = 64;

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

#[cfg(test)]
#[path = "tests/dec_private.rs"]
mod tests;
