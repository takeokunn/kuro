// Accessors, queries, soft_reset, and reset for TerminalCore.

use super::TerminalCore;
use crate::parser;
use crate::parser::apc::ApcScanState;
use crate::parser::dec_private::DecModes;
use crate::parser::tabs::TabStops;
use crate::types;

impl TerminalCore {
    // === Public accessors for integration tests ===
    // Note: current_bold/italic/underline expose internal SGR state for testing.
    // These should not be used in production code paths.

    /// Get the cursor row (0-indexed), using the active screen (primary or alternate)
    #[must_use]
    pub fn cursor_row(&self) -> usize {
        self.screen.cursor().row
    }

    /// Get the cursor column (0-indexed), using the active screen (primary or alternate)
    #[must_use]
    pub fn cursor_col(&self) -> usize {
        self.screen.cursor().col
    }

    /// Get the number of rows in the terminal screen
    #[must_use]
    pub const fn rows(&self) -> u16 {
        self.screen.rows()
    }

    /// Get the number of columns in the terminal screen
    #[must_use]
    pub const fn cols(&self) -> u16 {
        self.screen.cols()
    }

    /// Get whether the cursor is visible (DECTCEM state)
    #[must_use]
    pub const fn cursor_visible(&self) -> bool {
        self.dec_modes.cursor_visible
    }

    /// Get whether application cursor keys mode is active (DECCKM)
    #[must_use]
    pub const fn app_cursor_keys(&self) -> bool {
        self.dec_modes.app_cursor_keys
    }

    /// Get whether bracketed paste mode is active (mode 2004)
    #[must_use]
    pub const fn bracketed_paste(&self) -> bool {
        self.dec_modes.bracketed_paste
    }

    /// Get whether the alternate screen buffer is currently active
    #[must_use]
    pub const fn is_alternate_screen_active(&self) -> bool {
        self.screen.is_alternate_screen_active()
    }

    /// Get whether bold SGR attribute is currently set
    #[must_use]
    pub const fn current_bold(&self) -> bool {
        self.current_attrs
            .flags
            .contains(types::cell::SgrFlags::BOLD)
    }

    /// Get whether italic SGR attribute is currently set
    #[must_use]
    pub const fn current_italic(&self) -> bool {
        self.current_attrs
            .flags
            .contains(types::cell::SgrFlags::ITALIC)
    }

    /// Get whether underline SGR attribute is currently set
    #[must_use]
    pub fn current_underline(&self) -> bool {
        self.current_attrs.underline()
    }

    /// Get whether overline SGR attribute (SGR 53) is currently set
    #[must_use]
    pub const fn current_overline(&self) -> bool {
        self.current_attrs.overline
    }

    /// Get a cell from the screen at the given (row, col) position
    #[must_use]
    pub fn get_cell(&self, row: usize, col: usize) -> Option<&types::cell::Cell> {
        self.screen.get_cell(row, col)
    }

    /// Get the number of lines currently in the scrollback buffer
    #[must_use]
    pub const fn scrollback_line_count(&self) -> usize {
        self.screen.scrollback_line_count
    }

    /// Get scrollback lines as cell characters; most recent line first.
    /// Each inner Vec is the characters of one scrolled-off line.
    #[must_use]
    pub fn scrollback_chars(&self, max_lines: usize) -> Vec<Vec<char>> {
        self.screen
            .get_scrollback_lines(max_lines)
            .into_iter()
            .map(|line| line.cells.iter().map(types::cell::Cell::char).collect())
            .collect()
    }

    /// Get current DEC modes state (read-only reference)
    #[must_use]
    pub const fn dec_modes(&self) -> &parser::dec_private::DecModes {
        &self.dec_modes
    }

    /// Get current SGR attributes (read-only reference)
    #[must_use]
    pub const fn current_attrs(&self) -> &types::cell::SgrAttributes {
        &self.current_attrs
    }

    /// Get current OSC data (read-only reference)
    #[must_use]
    pub const fn osc_data(&self) -> &types::osc::OscData {
        &self.osc_data
    }

    /// Returns whether the 256-color palette has been updated since the last render (OSC 4).
    #[inline]
    #[must_use]
    pub const fn palette_dirty(&self) -> bool {
        self.osc_data.palette_dirty
    }

    /// Returns whether the default fg/bg/cursor colors have changed since the last render (OSC 10/11/12).
    #[inline]
    #[must_use]
    pub const fn default_colors_dirty(&self) -> bool {
        self.osc_data.default_colors_dirty
    }

    /// Get the current window title
    #[must_use]
    pub fn title(&self) -> &str {
        &self.meta.title
    }

    /// Get whether the title has been updated and not yet read
    #[must_use]
    pub const fn title_dirty(&self) -> bool {
        self.meta.title_dirty
    }

    /// Get pending terminal responses (for DA1, DA2, Kitty keyboard, etc.)
    #[must_use]
    pub fn pending_responses(&self) -> &[Vec<u8>] {
        &self.meta.pending_responses
    }

    /// Enqueue an OSC 99 desktop-notification action response back to the
    /// application, flowing out to the PTY alongside DSR/DA replies.
    ///
    /// Per the Kitty OSC 99 protocol, when the user acts on a notification that
    /// requested `a=report`:
    ///   - activation / clicking the body sends `OSC 99 ; i=<id> ; ST` — pass
    ///     `button = None`.
    ///   - clicking button N sends `OSC 99 ; i=<id> ; <N> ST` — pass
    ///     `button = Some(N)`.
    ///   - closing a `c=1` notification sends `OSC 99 ; i=<id> : p=close ; ST` —
    ///     pass `button = None` and `close = true`.
    ///
    /// `id` is the notification id echoed back to the application. The response
    /// is terminated with BEL (`ST` equivalent) to match the rest of the OSC
    /// replies in this crate.
    pub fn push_notification_action_response(
        &mut self,
        id: &str,
        button: Option<u32>,
        close: bool,
    ) {
        let metadata = if close {
            format!("i={id}:p=close")
        } else {
            format!("i={id}")
        };
        let payload = match button {
            Some(n) => n.to_string(),
            None => String::new(),
        };
        let resp = format!("\x1b]99;{metadata};{payload}\x07");
        self.meta.pending_responses.push(resp.into_bytes());
    }

    /// Get pending image placement notifications (Kitty Graphics + Sixel).
    ///
    /// Returns notifications that have accumulated since terminal construction.
    /// Each notification describes one image that was placed on the terminal grid.
    #[must_use]
    pub fn pending_image_notifications(&self) -> &[crate::grid::screen::ImageNotification] {
        &self.kitty.pending_image_notifications
    }

    /// Re-encode a stored image as a base64-encoded PNG string.
    ///
    /// Returns an empty string if no image with `image_id` is stored.
    /// Searches the active screen's graphics store (primary or alternate).
    #[must_use]
    pub fn get_image_png_base64(&self, image_id: u32) -> String {
        self.screen.get_image_png_base64(image_id)
    }

    /// Get current foreground color
    #[must_use]
    pub const fn current_foreground(&self) -> &types::Color {
        &self.current_attrs.foreground
    }

    /// Soft terminal reset (DECSTR - CSI ! p)
    ///
    /// Resets modes but preserves screen content and scrollback.
    pub fn soft_reset(&mut self) {
        // Reset cursor keys to normal mode
        self.dec_modes.app_cursor_keys = false;
        // Reset origin mode
        self.dec_modes.origin_mode = false;
        // Auto-wrap back on
        self.dec_modes.auto_wrap = true;
        // Cursor visible
        self.dec_modes.cursor_visible = true;
        // IRM (ANSI mode 4) back to replace
        self.dec_modes.insert_mode = false;
        // LNM (ANSI mode 20) off
        self.dec_modes.newline_mode = false;
        // Reverse-wraparound (DEC private mode 45) off
        self.dec_modes.reverse_wraparound = false;
        // Reset SGR attributes
        self.current_attrs = types::cell::SgrAttributes::default();
        // Clear the XTPUSHSGR stack so a later XTPOPSGR cannot restore stale attrs
        self.sgr_stack.clear();
        // Reset scroll region to full screen
        let rows = self.screen.rows() as usize;
        self.screen.set_scroll_region(0, rows);
        // Move cursor to home
        self.screen.move_cursor(0, 0);
        // Reset cursor shape
        self.dec_modes.cursor_shape = types::cursor::CursorShape::BlinkingBlock;
        // Reset Kitty keyboard protocol flags
        self.dec_modes.keyboard_flags = 0;
        self.dec_modes.keyboard_flags_stack.clear();
        // Clear alt-screen SGR snapshot so a subsequent ?1049l cannot restore stale attrs
        self.saved_primary_attrs = None;
        // Reset character set designations to US ASCII
        self.g0_charset = types::charset::CharsetType::Ascii;
        self.g1_charset = types::charset::CharsetType::Ascii;
        self.gl_is_g1 = false;
        // Note: does NOT clear scrollback, does NOT switch screens, does NOT clear screen
    }

    /// Full terminal reset (RIS - ESC c)
    pub fn reset(&mut self) {
        // Switch back to primary screen if alternate is active
        if self.screen.is_alternate_screen_active() {
            self.screen.switch_to_primary();
        }
        // Reset cursor to home position
        self.screen.move_cursor(0, 0);
        // Reset SGR attributes to defaults
        self.current_attrs = types::cell::SgrAttributes::default();
        // Clear saved cursor state
        self.saved_cursor = None;
        self.saved_attrs = None;
        self.saved_primary_attrs = None;
        self.saved_g0_charset = None;
        self.saved_g1_charset = None;
        self.saved_gl_is_g1 = None;
        // Reset DEC private modes to correct terminal defaults
        self.dec_modes = DecModes::new();
        // Reset tab stops to every 8th column
        self.tab_stops = TabStops::new(self.screen.cols() as usize);
        // Clear title state
        self.meta.title = String::new();
        self.meta.title_dirty = false;
        // Clear pending bell
        self.meta.bell_pending = false;
        // Clear pending responses
        self.meta.pending_responses.clear();
        // Clear Kitty Graphics state
        self.kitty.apc_state = ApcScanState::Idle;
        self.kitty.apc_buf.clear();
        self.kitty.kitty_chunk = None;
        self.meta.dcs_state = parser::dcs::DcsState::Idle;
        self.kitty.pending_image_notifications.clear();
        // Clear OSC data
        self.osc_data = types::osc::OscData::default();
        // Reset VTE parser to fresh Ground state
        self.parser = Some(vte::Parser::new());
        self.parser_in_ground = true;
        // Clear any buffered print characters
        self.print_buf.clear();
        // Reset character set designations to US ASCII
        self.g0_charset = types::charset::CharsetType::Ascii;
        self.g1_charset = types::charset::CharsetType::Ascii;
        self.gl_is_g1 = false;
    }
}
