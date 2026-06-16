// Session creation and PTY write entrypoints for TerminalSession.

use super::{SessionState, TerminalSession};
use crate::{Result, TerminalCore};

#[cfg(unix)]
use crate::pty::Pty;

impl TerminalSession {
    /// Create a new terminal session for `command`.
    ///
    /// On Unix, spawns a PTY-backed child process.  On non-Unix platforms,
    /// creates an in-memory session for tests and pure rendering flows.
    pub fn new(command: &str, shell_args: &[String], rows: u16, cols: u16) -> Result<Self> {
        #[cfg(unix)]
        let mut pty = Pty::spawn(command, shell_args, rows, cols)?;
        #[cfg(unix)]
        pty.set_winsize(rows, cols)?;

        Ok(Self {
            core: TerminalCore::new(rows, cols),
            #[cfg(unix)]
            pty: Some(pty),
            command: command.to_owned(),
            state: SessionState::Bound,
            #[cfg(unix)]
            pending_input: Vec::new(),
            row_hashes: Vec::new(),
            palette_epoch: 0,
            was_alt_screen: false,
            encode_pool: crate::ffi::codec::EncodePool::new(),
            dirty_scratch: Vec::new(),
            texts_scratch: Vec::new(),
            buf_scratch: Vec::new(),
        })
    }

    /// Send input bytes to the child PTY.
    ///
    /// On Unix, writes directly to the PTY.  On non-Unix platforms this is a
    /// no-op so that tests and rendering-only flows can still compile.
    pub fn send_input(&mut self, bytes: &[u8]) -> Result<()> {
        #[cfg(unix)]
        if let Some(ref mut pty) = self.pty {
            pty.write(bytes)?;
        }
        #[cfg(not(unix))]
        let _ = bytes;
        Ok(())
    }
}
