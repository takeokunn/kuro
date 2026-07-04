//! DEC private mode handling

use crate::types::cursor::CursorShape;

#[path = "dec_private_support.rs"]
mod support;

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

    /// Grapheme clustering (?2027) — when set, the print path coalesces ZWJ
    /// emoji sequences, variation selectors, and regional-indicator flag pairs
    /// into a single grapheme cluster occupying one logical cell run. Default
    /// OFF so existing byte-for-byte print behavior is unchanged.
    /// See: <https://github.com/contour-terminal/terminal-unicode-core>
    pub(crate) grapheme_clustering: bool,

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
    /// DECCOLM (?3) — 132-column mode is currently active.
    pub deccolm: bool,
    /// Reverse-wraparound mode (?45) — BS at col 0 wraps to previous line's last col.
    pub reverse_wraparound: bool,
    /// DECSDM (?80) — Sixel Display Mode.
    /// When set, sixel images are rendered without scrolling (DEC VT340 "display" mode).
    /// When reset (default), sixel images scroll normally.
    pub sixel_display_mode: bool,

    /// Save/restore stack for XTSAVE/XTRESTORE private modes (CSI ? Pm s / CSI ? Pm r).
    ///
    /// xterm's `CSI ? Pm s` saves the listed DEC private modes and `CSI ? Pm r`
    /// restores them. Kuro implements a full-snapshot approximation: each `s`
    /// pushes a complete clone of the current [`DecModes`] (regardless of which
    /// modes `Pm` lists) and each `r` pops and restores the whole snapshot. The
    /// snapshots themselves carry an empty stack so the depth cannot grow
    /// quadratically. Capped at [`SAVED_MODES_STACK_MAX`] entries.
    pub saved_modes: Vec<DecModes>,
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
            grapheme_clustering: false,
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
            deccolm: false,
            reverse_wraparound: false,
            sixel_display_mode: false,
            saved_modes: Vec::new(),
        }
    }

    /// Save the current DEC private modes onto the save/restore stack
    /// (XTSAVE — `CSI ? Pm s`).
    ///
    /// Full-snapshot approximation: the *entire* [`DecModes`] is cloned
    /// regardless of the requested `Pm` list. The pushed snapshot carries an
    /// empty `saved_modes` so the stack depth cannot grow quadratically. The
    /// stack is capped at [`SAVED_MODES_STACK_MAX`]; once full, the oldest
    /// entry is evicted to keep the most recent saves.
    pub fn save_modes(&mut self) {
        let mut snapshot = self.clone();
        snapshot.saved_modes = Vec::new();
        if self.saved_modes.len() >= SAVED_MODES_STACK_MAX {
            self.saved_modes.remove(0);
        }
        self.saved_modes.push(snapshot);
    }

    /// Restore the most recently saved DEC private modes from the save/restore
    /// stack (XTRESTORE — `CSI ? Pm r`).
    ///
    /// Full-snapshot approximation: pops the last snapshot and replaces the
    /// whole [`DecModes`] with it (preserving the remaining stack). An empty
    /// stack makes this a no-op. Returns `true` when a snapshot was restored.
    pub fn restore_modes(&mut self) -> bool {
        match self.saved_modes.pop() {
            Some(mut snapshot) => {
                // Preserve the remaining save stack across the restore.
                snapshot.saved_modes = std::mem::take(&mut self.saved_modes);
                *self = snapshot;
                true
            }
            None => false,
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
            // Mode 3 — DECCOLM (132-column mode). Only valid when allow_deccolm
            // (?40) is set; silently ignored otherwise.  The side-effect (grid
            // resize + screen clear) lives in apply_mode_set / apply_mode_reset.
            3 if self.allow_deccolm => self.deccolm = value,
            5 => self.screen_reverse = value,
            6 => self.origin_mode = value,
            7 => self.auto_wrap = value,
            // Mode 12 — Start/Stop Blinking Cursor (DECBKM).
            // Toggle cursor blink: blink variants ↔ steady variants of current shape.
            12 => {
                use crate::types::cursor::CursorShape;
                self.cursor_shape = match (value, self.cursor_shape) {
                    (true, CursorShape::SteadyBlock) => CursorShape::BlinkingBlock,
                    (true, CursorShape::SteadyUnderline) => CursorShape::BlinkingUnderline,
                    (true, CursorShape::SteadyBar) => CursorShape::BlinkingBar,
                    (false, CursorShape::BlinkingBlock) => CursorShape::SteadyBlock,
                    (false, CursorShape::BlinkingUnderline) => CursorShape::SteadyUnderline,
                    (false, CursorShape::BlinkingBar) => CursorShape::SteadyBar,
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
            2027 => self.grapheme_clustering = value,
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
            3 => Some(self.deccolm),
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
            2027 => Some(self.grapheme_clustering),
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
    support::handle_ansi_modes(term, params, value);
}

/// Handle ANSI DECRQM — ANSI mode query (CSI Ps $ p → CSI Ps ; status $ y, no `?`).
///
/// Reports the status of ANSI modes: 1 = set, 2 = reset, 0 = unrecognized.
/// Currently tracks IRM (mode 4) and LNM (mode 20).
#[inline]
pub fn handle_ansi_decrqm(term: &mut crate::TerminalCore, params: &vte::Params) {
    support::handle_ansi_decrqm(term, params);
}

/// Handle DECRQM — DEC private mode query (CSI ? Ps $ p → CSI ? Ps ; status $ y)
///
/// For each queried mode, returns status: 1 = set, 2 = reset, 0 = not recognised.
#[inline]
pub fn handle_decrqm(term: &mut crate::TerminalCore, params: &vte::Params) {
    support::handle_decrqm(term, params);
}

/// Handle DEC private mode sequences (CSI ? Pm h/l).
///
/// - CSI ? Pm h — set each mode in `params`
/// - CSI ? Pm l — reset each mode in `params`
pub fn handle_dec_modes(term: &mut crate::TerminalCore, params: &vte::Params, set: bool) {
    support::handle_dec_modes(term, params, set);
}

/// Maximum depth of the Kitty keyboard flags push/pop stack (CSI > Ps u / CSI < u).
///
/// Matches the limit used by other terminal emulators (e.g. foot, kitty).
const KEYBOARD_FLAGS_STACK_MAX: usize = 64;

/// Maximum depth of the XTSAVE/XTRESTORE DEC private mode save stack
/// (CSI ? Pm s / CSI ? Pm r). Capped to bound memory against a hostile stream
/// that issues unbounded `CSI ? s` saves without matching restores.
pub(crate) const SAVED_MODES_STACK_MAX: usize = 32;

/// Handle XTSAVE — save DEC private modes (`CSI ? Pm s`).
///
/// Full-snapshot approximation: pushes a clone of the entire current
/// [`DecModes`] regardless of the `Pm` list. See [`DecModes::save_modes`].
#[inline]
pub fn handle_save_modes(term: &mut crate::TerminalCore) {
    term.dec_modes.save_modes();
}

/// Handle XTRESTORE — restore DEC private modes (`CSI ? Pm r`).
///
/// Full-snapshot approximation: pops and restores the entire [`DecModes`].
/// An empty stack is a no-op. See [`DecModes::restore_modes`].
#[inline]
pub fn handle_restore_modes(term: &mut crate::TerminalCore) {
    term.dec_modes.restore_modes();
}

#[path = "dec_private_kitty.rs"]
mod kitty_keyboard;

pub(crate) use kitty_keyboard::{
    apply_color_scheme, handle_dsr_color_scheme, handle_dsr_cursor_style,
    handle_dsr_cursor_visibility, handle_kitty_kb_pop, handle_kitty_kb_push, handle_kitty_kb_query,
};

#[cfg(test)]
#[path = "tests/dec_private.rs"]
mod tests;
