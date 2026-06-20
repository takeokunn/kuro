// Viewport, PTY-liveness, and session lifecycle accessors for TerminalSession.

use super::{SessionState, TerminalSession};

impl TerminalSession {
    take_vec_field!(
        /// Drain and return all pending image placement notifications.
        fn take_pending_image_notifications from kitty take pending_image_notifications : crate::grid::screen::ImageNotification
    );

    /// Get scrollback line count
    #[must_use]
    pub const fn get_scrollback_count(&self) -> usize {
        self.core.screen.scrollback_line_count
    }

    /// Scroll the viewport up by n lines (toward older scrollback content)
    pub fn viewport_scroll_up(&mut self, n: usize) {
        self.core.screen.viewport_scroll_up(n);
    }

    /// Scroll the viewport down by n lines (toward live content)
    pub const fn viewport_scroll_down(&mut self, n: usize) {
        self.core.screen.viewport_scroll_down(n);
    }

    /// Return the current viewport scroll offset (0 = live view)
    #[must_use]
    pub const fn scroll_offset(&self) -> usize {
        self.core.screen.scroll_offset()
    }

    #[cfg(unix)]
    #[inline]
    fn pty_has_pending_output(&self) -> bool {
        self.pty
            .as_ref()
            .is_some_and(crate::pty::posix::Pty::has_pending_data)
    }

    #[cfg(not(unix))]
    #[inline]
    fn pty_has_pending_output(&self) -> bool {
        false
    }

    /// Check if the PTY channel has pending unread data (without consuming it).
    ///
    /// Used by Elisp to trigger immediate rendering when streaming output arrives.
    #[must_use]
    pub fn has_pending_output(&self) -> bool {
        !self.pending_input.is_empty() || self.pty_has_pending_output()
    }

    #[cfg(unix)]
    #[inline]
    #[must_use]
    fn pty_is_alive(&self) -> bool {
        self.pty
            .as_ref()
            .is_none_or(crate::pty::posix::Pty::is_alive)
    }

    #[cfg(not(unix))]
    #[inline]
    fn pty_is_alive(&self) -> bool {
        true
    }

    /// Returns true if the PTY child process has not yet exited.
    ///
    /// On Unix: reads the `process_exited` flag written by the reader thread on EOF.
    /// Returns `true` when `pty` is `None` (test sessions without a real PTY) so that
    /// test buffers are never auto-killed.
    /// On non-Unix: always returns `true` (no PTY process to track).
    #[must_use]
    pub fn is_process_alive(&self) -> bool {
        self.pty_is_alive()
    }

    /// Return the shell command used to spawn this session.
    #[inline]
    #[must_use]
    pub fn command(&self) -> &str {
        &self.command
    }

    /// Return `true` if this session is in the `Detached` state.
    #[inline]
    #[must_use]
    pub fn is_detached(&self) -> bool {
        self.state == SessionState::Detached
    }

    /// Mark this session as `Detached` (keeps PTY alive, no buffer attached).
    #[inline]
    pub const fn set_detached(&mut self) {
        self.state = SessionState::Detached;
    }

    /// Mark this session as `Bound` (re-attaching it to a buffer).
    #[inline]
    pub const fn set_bound(&mut self) {
        self.state = SessionState::Bound;
    }

    /// Return the PID of the PTY child process, if available.
    ///
    /// Returns `None` on non-Unix platforms or when no PTY is attached.
    #[must_use]
    pub const fn pid(&self) -> Option<u32> {
        #[cfg(unix)]
        if let Some(pty) = &self.pty {
            return Some(pty.pid());
        }
        None
    }
}
