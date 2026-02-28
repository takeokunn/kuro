//! DEC private mode handling

/// DEC private mode state
#[derive(Debug, Clone, Copy, Default)]
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
        }
    }

    /// Set a DEC private mode
    pub fn set_mode(&mut self, mode: u16) {
        match mode {
            1 => self.app_cursor_keys = true,
            7 => self.auto_wrap = true,
            25 => self.cursor_visible = true,
            1049 => self.alternate_screen = true,
            2004 => self.bracketed_paste = true,
            _ => {}
        }
    }

    /// Reset a DEC private mode
    pub fn reset_mode(&mut self, mode: u16) {
        match mode {
            1 => self.app_cursor_keys = false,
            7 => self.auto_wrap = false,
            25 => self.cursor_visible = false,
            1049 => self.alternate_screen = false,
            2004 => self.bracketed_paste = false,
            _ => {}
        }
    }

    /// Query a DEC private mode state
    pub fn get_mode(&self, mode: u16) -> Option<bool> {
        match mode {
            1 => Some(self.app_cursor_keys),
            7 => Some(self.auto_wrap),
            25 => Some(self.cursor_visible),
            1049 => Some(self.alternate_screen),
            2004 => Some(self.bracketed_paste),
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

                // Handle side effects for mode 1049 (alternate screen)
                if mode == 1049 {
                    term.screen.switch_to_alternate();
                }
            } else {
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
    fn test_unknown_mode_no_panic() {
        let mut modes = DecModes::new();
        modes.set_mode(9999); // Unknown mode, should not panic
        modes.reset_mode(9999); // Should also not panic
    }
}
