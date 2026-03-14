//! DEC private mode handling

use crate::types::cursor::CursorShape;

/// DEC private mode state
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
    /// Not a CSI ?h/l mode — handled directly in esc_dispatch.
    pub app_keypad: bool,

    /// DECOM (?6) - Origin Mode. When set, cursor addressing is relative to scroll region.
    pub origin_mode: bool,

    /// Focus events (?1004) - When set, terminal sends CSI I / CSI O on focus in/out
    pub focus_events: bool,

    /// Synchronized output (?2026) - When set, screen updates are batched
    pub synchronized_output: bool,

    /// Cursor shape (DECSCUSR)
    pub cursor_shape: CursorShape,

    /// Kitty keyboard protocol flags (current active flags bitmask)
    pub keyboard_flags: u32,

    /// Stack for push/pop keyboard flags (CSI > Ps u / CSI < u)
    pub keyboard_flags_stack: Vec<u32>,
}

impl Default for DecModes {
    fn default() -> Self {
        Self::new()
    }
}

impl DecModes {
    /// Create a new DEC modes structure with default values
    pub fn new() -> Self {
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
            cursor_shape: CursorShape::BlinkingBlock,
            keyboard_flags: 0,
            keyboard_flags_stack: Vec::new(),
        }
    }

    /// Set a DEC private mode
    pub fn set_mode(&mut self, mode: u16) {
        match mode {
            1 => self.app_cursor_keys = true,
            6 => self.origin_mode = true,
            7 => self.auto_wrap = true,
            25 => self.cursor_visible = true,
            1004 => self.focus_events = true,
            1049 => self.alternate_screen = true,
            2004 => self.bracketed_paste = true,
            1000 | 1002 | 1003 => self.mouse_mode = mode,
            1006 => self.mouse_sgr = true,
            2026 => self.synchronized_output = true,
            _ => {}
        }
    }

    /// Reset a DEC private mode
    pub fn reset_mode(&mut self, mode: u16) {
        match mode {
            1 => self.app_cursor_keys = false,
            6 => self.origin_mode = false,
            7 => self.auto_wrap = false,
            25 => self.cursor_visible = false,
            1004 => self.focus_events = false,
            1049 => self.alternate_screen = false,
            2004 => self.bracketed_paste = false,
            1000 | 1002 | 1003 => self.mouse_mode = 0,
            1006 => self.mouse_sgr = false,
            2026 => self.synchronized_output = false,
            _ => {}
        }
    }

    /// Query a DEC private mode state
    pub fn get_mode(&self, mode: u16) -> Option<bool> {
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
            2026 => Some(self.synchronized_output),
            _ => None,
        }
    }

    /// Check if tab stops are enabled (tabs always enabled in standard VT)
    /// This is a placeholder for future tab mode support
    pub fn tab_stops_enabled(&self) -> bool {
        true
    }
}

/// Handle DEC private mode sequences (CSI ? Pm h/l)
///
/// - CSI ? Pm h: Set DEC private mode(s)
/// - CSI ? Pm l: Reset DEC private mode(s)
pub fn handle_dec_modes(term: &mut crate::TerminalCore, params: &vte::Params, set: bool) {
    for param_group in params {
        for &mode in param_group {
            if set {
                term.dec_modes.set_mode(mode);

                // Handle side effects for mode 6 (DECOM - origin mode)
                // When set, move cursor to home position within scroll region
                if mode == 6 {
                    let top = term.screen.get_scroll_region().top;
                    term.screen.move_cursor(top, 0);
                }

                // Handle side effects for mode 1049 (alternate screen)
                if mode == 1049 {
                    term.screen.switch_to_alternate();
                }
            } else {
                // Handle side effects for mode 6 (DECOM - origin mode)
                // When reset, move cursor to home position
                if mode == 6 {
                    term.screen.move_cursor(0, 0);
                }

                // Handle side effects for mode 1049 before resetting
                if mode == 1049 && term.dec_modes.alternate_screen {
                    term.screen.switch_to_primary();
                }

                term.dec_modes.reset_mode(mode);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    #[test]
    fn test_dec_modes_default() {
        let modes = DecModes::new();
        assert!(!modes.app_cursor_keys);
        assert!(modes.auto_wrap);
        assert!(modes.cursor_visible);
        assert!(!modes.alternate_screen);
        assert!(!modes.bracketed_paste);
    }

    #[test]
    fn test_set_decckm() {
        let mut modes = DecModes::new();
        assert!(!modes.app_cursor_keys);

        modes.set_mode(1);
        assert!(modes.app_cursor_keys);
    }

    #[test]
    fn test_reset_decckm() {
        let mut modes = DecModes::new();
        modes.app_cursor_keys = true;
        modes.reset_mode(1);
        assert!(!modes.app_cursor_keys);
    }

    #[test]
    fn test_set_decawm() {
        let mut modes = DecModes::new();
        modes.auto_wrap = false;

        modes.set_mode(7);
        assert!(modes.auto_wrap);
    }

    #[test]
    fn test_reset_decawm() {
        let mut modes = DecModes::new();
        modes.set_mode(7);
        assert!(modes.auto_wrap);

        modes.reset_mode(7);
        assert!(!modes.auto_wrap);
    }

    #[test]
    fn test_set_dectcem() {
        let mut modes = DecModes::new();
        modes.cursor_visible = false;

        modes.set_mode(25);
        assert!(modes.cursor_visible);
    }

    #[test]
    fn test_reset_dectcem() {
        let mut modes = DecModes::new();
        modes.reset_mode(25);
        assert!(!modes.cursor_visible);
    }

    #[test]
    fn test_set_alternate_screen() {
        let mut modes = DecModes::new();
        assert!(!modes.alternate_screen);

        modes.set_mode(1049);
        assert!(modes.alternate_screen);
    }

    #[test]
    fn test_reset_alternate_screen() {
        let mut modes = DecModes::new();
        modes.set_mode(1049);
        assert!(modes.alternate_screen);

        modes.reset_mode(1049);
        assert!(!modes.alternate_screen);
    }

    #[test]
    fn test_set_bracketed_paste() {
        let mut modes = DecModes::new();
        assert!(!modes.bracketed_paste);

        modes.set_mode(2004);
        assert!(modes.bracketed_paste);
    }

    #[test]
    fn test_reset_bracketed_paste() {
        let mut modes = DecModes::new();
        modes.set_mode(2004);
        assert!(modes.bracketed_paste);

        modes.reset_mode(2004);
        assert!(!modes.bracketed_paste);
    }

    #[test]
    fn test_get_mode() {
        let mut modes = DecModes::new();

        modes.set_mode(1);
        modes.set_mode(7);

        assert_eq!(modes.get_mode(1), Some(true));
        assert_eq!(modes.get_mode(7), Some(true));
        assert_eq!(modes.get_mode(25), Some(true)); // default
        assert_eq!(modes.get_mode(1049), Some(false));
        assert_eq!(modes.get_mode(9999), None);
    }

    #[test]
    fn test_app_keypad_default_is_false() {
        let modes = DecModes::new();
        assert!(!modes.app_keypad);
    }

    #[test]
    fn test_app_keypad_set_and_clear() {
        let mut modes = DecModes::new();
        modes.app_keypad = true;
        assert!(modes.app_keypad);
        modes.app_keypad = false;
        assert!(!modes.app_keypad);
    }

    #[test]
    fn test_unknown_mode_no_panic() {
        let mut modes = DecModes::new();
        modes.set_mode(9999); // Unknown mode, should not panic
        modes.reset_mode(9999); // Should also not panic
    }

    #[test]
    fn test_mouse_mode_default_is_zero() {
        let modes = DecModes::new();
        assert_eq!(modes.mouse_mode, 0);
        assert!(!modes.mouse_sgr);
    }

    #[test]
    fn test_set_mouse_mode_1000() {
        let mut modes = DecModes::new();
        modes.set_mode(1000);
        assert_eq!(modes.mouse_mode, 1000);
    }

    #[test]
    fn test_set_mouse_mode_1002() {
        let mut modes = DecModes::new();
        modes.set_mode(1002);
        assert_eq!(modes.mouse_mode, 1002);
    }

    #[test]
    fn test_set_mouse_mode_1003() {
        let mut modes = DecModes::new();
        modes.set_mode(1003);
        assert_eq!(modes.mouse_mode, 1003);
    }

    #[test]
    fn test_reset_mouse_mode_sets_zero() {
        let mut modes = DecModes::new();
        modes.set_mode(1002);
        modes.reset_mode(1002);
        assert_eq!(modes.mouse_mode, 0);
    }

    #[test]
    fn test_reset_any_mouse_mode_clears_all() {
        let mut modes = DecModes::new();
        modes.set_mode(1003);
        // Resetting mode 1000 still clears mouse_mode
        modes.reset_mode(1000);
        assert_eq!(modes.mouse_mode, 0);
    }

    #[test]
    fn test_set_mouse_mode_replaces_previous() {
        let mut modes = DecModes::new();
        modes.set_mode(1000);
        modes.set_mode(1002); // switch to a different mode
        assert_eq!(modes.mouse_mode, 1002);
    }

    #[test]
    fn test_set_mouse_sgr() {
        let mut modes = DecModes::new();
        modes.set_mode(1006);
        assert!(modes.mouse_sgr);
    }

    #[test]
    fn test_reset_mouse_sgr() {
        let mut modes = DecModes::new();
        modes.set_mode(1006);
        modes.reset_mode(1006);
        assert!(!modes.mouse_sgr);
    }

    #[test]
    fn test_get_mode_mouse_1000_active() {
        let mut modes = DecModes::new();
        modes.set_mode(1000);
        assert_eq!(modes.get_mode(1000), Some(true));
        assert_eq!(modes.get_mode(1002), Some(false));
        assert_eq!(modes.get_mode(1003), Some(false));
    }

    #[test]
    fn test_get_mode_mouse_sgr() {
        let mut modes = DecModes::new();
        assert_eq!(modes.get_mode(1006), Some(false));
        modes.set_mode(1006);
        assert_eq!(modes.get_mode(1006), Some(true));
    }

    #[test]
    fn test_decom_mode_set_reset() {
        let mut modes = DecModes::new();
        assert!(!modes.origin_mode, "origin_mode should default to false");

        modes.set_mode(6);
        assert!(
            modes.origin_mode,
            "origin_mode should be set after set_mode(6)"
        );

        modes.reset_mode(6);
        assert!(
            !modes.origin_mode,
            "origin_mode should be cleared after reset_mode(6)"
        );
    }

    #[test]
    fn test_focus_events_mode_set_reset() {
        let mut modes = DecModes::new();
        assert!(!modes.focus_events, "focus_events should default to false");

        modes.set_mode(1004);
        assert!(
            modes.focus_events,
            "focus_events should be set after set_mode(1004)"
        );

        modes.reset_mode(1004);
        assert!(
            !modes.focus_events,
            "focus_events should be cleared after reset_mode(1004)"
        );
    }

    #[test]
    fn test_sync_output_mode_set_reset() {
        let mut modes = DecModes::new();
        assert!(
            !modes.synchronized_output,
            "synchronized_output should default to false"
        );

        modes.set_mode(2026);
        assert!(
            modes.synchronized_output,
            "synchronized_output should be set after set_mode(2026)"
        );

        modes.reset_mode(2026);
        assert!(
            !modes.synchronized_output,
            "synchronized_output should be cleared after reset_mode(2026)"
        );
    }

    #[test]
    fn test_get_mode_new_modes() {
        let mut modes = DecModes::new();
        assert_eq!(modes.get_mode(6), Some(false));
        assert_eq!(modes.get_mode(1004), Some(false));
        assert_eq!(modes.get_mode(2026), Some(false));

        modes.set_mode(6);
        modes.set_mode(1004);
        modes.set_mode(2026);

        assert_eq!(modes.get_mode(6), Some(true));
        assert_eq!(modes.get_mode(1004), Some(true));
        assert_eq!(modes.get_mode(2026), Some(true));
    }

    proptest! {
        #[test]
        fn prop_dec_modes_set_reset_no_panic(mode in 0u16..=65535u16) {
            let mut modes = DecModes::new();
            modes.set_mode(mode);   // must not panic
            modes.reset_mode(mode); // must not panic
            let _ = modes.get_mode(mode);
        }
    }
}
