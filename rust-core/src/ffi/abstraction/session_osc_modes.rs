// OSC data accessors and DEC mode getters for TerminalSession.

use super::TerminalSession;

impl TerminalSession {
    dec_mode_getter!(
        /// Get mouse pixel mode state (?1016)
        fn get_mouse_pixel -> bool = mouse_pixel
    );

    /// Get current 256-color palette overrides (non-None entries only).
    ///
    /// Returns a Vec of (index, R, G, B) for each overridden palette entry.
    #[must_use]
    #[expect(
        clippy::cast_possible_truncation,
        reason = "palette index is enumerate() over a 256-element array; i ≤ 255 always fits in u8"
    )]
    pub fn get_palette_updates(&self) -> Vec<(u8, u8, u8, u8)> {
        self.core
            .osc_data
            .palette
            .iter()
            .enumerate()
            .filter_map(|(i, entry)| entry.map(|[r, g, b]| (i as u8, r, g, b)))
            .collect()
    }

    /// Get default foreground/background/cursor colors (None = unset = use Emacs default).
    /// Returns (`fg_encoded`, `bg_encoded`, `cursor_encoded`) as u32 FFI color values.
    #[must_use]
    pub fn get_default_colors(&self) -> (u32, u32, u32) {
        let encode = |color: &Option<crate::types::Color>| -> u32 {
            color.as_ref().map_or(
                crate::ffi::codec::COLOR_DEFAULT_SENTINEL,
                Self::encode_color,
            )
        };
        (
            encode(&self.core.osc_data.default_fg),
            encode(&self.core.osc_data.default_bg),
            encode(&self.core.osc_data.cursor_color),
        )
    }

    take_bool_field!(
        /// Check and unconditionally clear the default-colors-dirty flag.
        ///
        /// Returns `true` if the flag was set (i.e., the default colors changed since
        /// the last call), then resets the flag to `false` regardless of its value.
        /// Subsequent calls return `false` until the flag is set again by the parser.
        fn take_default_colors_dirty from osc_data.default_colors_dirty
    );

    take_bool_field!(
        /// Check and clear the pending bell flag.
        ///
        /// Returns `true` if a BEL character has been received since the last call,
        /// then unconditionally resets the flag to `false`.
        /// Subsequent calls return `false` until another BEL is received.
        fn take_bell_pending from meta.bell_pending
    );

    take_some_if_dirty!(
        /// Return the window title if it has been updated since the last call, clearing the dirty flag.
        fn take_title_if_dirty from meta when title_dirty take title : String
    );

    take_option_field_if_dirty!(
        /// Return the working directory if it has been updated since the last call, clearing the dirty flag.
        /// Returns None if not dirty or if no cwd has been set.
        fn take_cwd_if_dirty from osc_data when cwd_dirty take cwd : String
    );

    take_vec_field!(
        /// Drain and return all pending clipboard actions (OSC 52).
        fn take_clipboard_actions from osc_data take clipboard_actions : crate::types::osc::ClipboardAction
    );

    take_vec_field!(
        /// Drain and return all pending eval commands (OSC 51).
        fn take_eval_commands from osc_data take eval_commands : String
    );

    /// Get the hostname from the last OSC 7 notification.
    /// Returns `None` if localhost or unset.
    #[inline]
    #[must_use]
    pub fn get_cwd_host(&self) -> Option<String> {
        self.core.osc_data.cwd_host.clone()
    }

    take_vec_field!(
        /// Drain and return all pending prompt mark events (OSC 133).
        fn take_prompt_marks from osc_data take prompt_marks : crate::types::osc::PromptMarkEvent
    );

    take_vec_field!(
        /// Drain and return all pending desktop notifications (OSC 9 / OSC 777).
        fn take_notifications from osc_data take notifications : crate::types::osc::Notification
    );

    /// Enqueue an OSC 99 notification action response back to the application.
    ///
    /// Pushes `OSC 99 ; i=<id> ; <button> ST` (or the `p=close` variant) onto the
    /// terminal's pending responses so it flows out to the PTY like a DSR/DA
    /// reply. `button` is `None` for plain activation, `Some(N)` for button N;
    /// `close` selects the `p=close` close-report variant.
    pub fn notify_action_response(&mut self, id: &str, button: Option<u32>, close: bool) {
        self.core
            .push_notification_action_response(id, button, close);
    }

    dec_mode_getter!(/// Get the current mouse tracking mode.
        fn get_mouse_mode -> u16 = mouse_mode);
    dec_mode_getter!(/// Get whether SGR mouse coordinate encoding is active.
        fn get_mouse_sgr -> bool = mouse_sgr);
    dec_mode_getter!(/// Get whether application cursor keys mode (DECCKM) is active.
        fn get_app_cursor_keys -> bool = app_cursor_keys);
    dec_mode_getter!(/// Get whether application keypad mode is active.
        fn get_app_keypad -> bool = app_keypad);
    dec_mode_getter!(/// Get the kitty keyboard protocol flags bitmask.
        fn get_keyboard_flags -> u32 = keyboard_flags);
    dec_mode_getter!(/// Get the current cursor shape.
        fn get_cursor_shape -> crate::types::cursor::CursorShape = cursor_shape);
    dec_mode_getter!(/// Get whether bracketed paste mode is active.
        fn get_bracketed_paste -> bool = bracketed_paste);
    dec_mode_getter!(/// Get whether focus event reporting is active.
        fn get_focus_events -> bool = focus_events);
    dec_mode_getter!(/// Get whether synchronized output mode is active.
        fn get_synchronized_output -> bool = synchronized_output);

    /// Return hyperlink ranges for all visible rows.
    ///
    /// Returns a flat Vec of `(row, start, end, uri)` tuples — one entry per
    /// hyperlink range per row.  Only rows that contain at least one hyperlink
    /// are included.  `start` and `end` are buffer character offsets (matching
    /// the convention used by `encode_hyperlink_ranges`).
    #[must_use]
    pub fn get_hyperlink_ranges(&self) -> Vec<(usize, usize, usize, String)> {
        let rows = self.core.screen.rows() as usize;
        let mut result = Vec::new();
        for row in 0..rows {
            if let Some(line) = self.core.screen.get_line(row) {
                let ranges = crate::ffi::codec::encode_hyperlink_ranges(&line.cells);
                for (start, end, uri) in ranges {
                    result.push((row, start, end, uri));
                }
            }
        }
        result
    }

    /// Return Kitty text-sizing (OSC 66) ranges for all visible rows.
    ///
    /// Returns a flat Vec of `(row, start, end, scaled_permille)` tuples — one
    /// entry per text-size range per row.  Only rows that contain at least one
    /// sized cell are included.  `start` and `end` are buffer character offsets
    /// (matching the convention used by `encode_text_size_ranges` and
    /// `get_hyperlink_ranges`).  `scaled_permille` is the effective size
    /// multiplier ×1000 (e.g. `2000` = 2×, `500` = half size).
    #[must_use]
    pub fn get_text_size_ranges(&self) -> Vec<(usize, usize, usize, u32)> {
        let rows = self.core.screen.rows() as usize;
        let mut result = Vec::new();
        for row in 0..rows {
            if let Some(line) = self.core.screen.get_line(row) {
                let ranges = crate::ffi::codec::encode_text_size_ranges(&line.cells);
                for (start, end, permille) in ranges {
                    result.push((row, start, end, permille));
                }
            }
        }
        result
    }
}
