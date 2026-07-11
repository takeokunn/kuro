// Session creation and PTY write entrypoints for TerminalSession.

use super::{SessionState, TerminalSession};
use crate::{Result, TerminalCore};

#[cfg(unix)]
use crate::pty::Pty;

const BRACKETED_PASTE_OPEN: &[u8] = b"\x1b[200~";
const BRACKETED_PASTE_CLOSE: &[u8] = b"\x1b[201~";

/// Text that must be delivered through the terminal paste path, not as raw keys.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PasteText<'a> {
    text: &'a str,
}

impl<'a> PasteText<'a> {
    /// Wrap `text` as paste input that will be encoded according to the current terminal mode.
    #[must_use]
    pub const fn new(text: &'a str) -> Self {
        Self { text }
    }

    fn raw_bytes(self) -> &'a [u8] {
        self.text.as_bytes()
    }

    fn bracketed_bytes(self) -> Vec<u8> {
        let mut bytes = Vec::with_capacity(
            BRACKETED_PASTE_OPEN.len() + self.text.len() + BRACKETED_PASTE_CLOSE.len(),
        );
        bytes.extend_from_slice(BRACKETED_PASTE_OPEN);
        for ch in self.text.chars() {
            if matches!(ch, '\u{1b}' | '\u{9b}') {
                continue;
            }
            let mut encoded = [0; 4];
            bytes.extend_from_slice(ch.encode_utf8(&mut encoded).as_bytes());
        }
        bytes.extend_from_slice(BRACKETED_PASTE_CLOSE);
        bytes
    }

    fn bytes_for_mode(self, bracketed_paste: bool) -> EncodedPaste<'a> {
        if bracketed_paste {
            EncodedPaste::Bracketed(self.bracketed_bytes())
        } else {
            EncodedPaste::Raw(self.raw_bytes())
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum EncodedPaste<'a> {
    Raw(&'a [u8]),
    Bracketed(Vec<u8>),
}

impl EncodedPaste<'_> {
    fn as_slice(&self) -> &[u8] {
        match self {
            Self::Raw(bytes) => bytes,
            Self::Bracketed(bytes) => bytes.as_slice(),
        }
    }
}

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
            last_sent_cursor: None,
            buf_scratch: Vec::new(),
            sync_suppressed_polls: 0,
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

    /// Send paste text using the session's current DEC 2004 mode.
    ///
    /// The mode check and write happen in one mutable session operation through
    /// the FFI bridge, so callers do not depend on the render poll's cached
    /// bracketed-paste state.
    pub fn send_paste_text(&mut self, paste: PasteText<'_>) -> Result<()> {
        let bytes = paste.bytes_for_mode(self.get_bracketed_paste());
        self.send_input(bytes.as_slice())
    }
}

#[cfg(test)]
mod tests {
    use super::PasteText;

    #[test]
    fn raw_paste_preserves_escape_controls() {
        let encoded = PasteText::new("a\x1bb\u{9b}c").bytes_for_mode(false);

        assert_eq!(encoded.as_slice(), "a\x1bb\u{9b}c".as_bytes());
    }

    #[test]
    fn bracketed_paste_wraps_and_removes_escape_controls() {
        let encoded = PasteText::new("a\x1bb\u{9b}201~c").bytes_for_mode(true);

        assert_eq!(encoded.as_slice(), b"\x1b[200~ab201~c\x1b[201~");
    }
}
