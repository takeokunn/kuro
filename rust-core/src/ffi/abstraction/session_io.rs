// PTY read/poll orchestration for TerminalSession.

use super::{advance_with_budget, TerminalSession, MAX_BYTES_PER_POLL};
use crate::Result;

impl TerminalSession {
    /// Pull bytes from the PTY and feed them into the terminal core.
    ///
    /// This keeps the per-frame parser budget bounded so busy terminal apps do
    /// not starve the UI event loop.  Excess bytes are preserved in
    /// `pending_input` and retried on the next frame.
    pub fn poll_output(&mut self) -> Result<()> {
        #[cfg(unix)]
        if let Some(ref mut pty) = self.pty {
            let mut budget = MAX_BYTES_PER_POLL;
            let mut overflow = Vec::new();

            if !self.pending_input.is_empty() {
                let pending = std::mem::take(&mut self.pending_input);
                advance_with_budget(&mut self.core, &pending, &mut budget, &mut overflow);
            }

            let data = pty.read()?;
            advance_with_budget(&mut self.core, &data, &mut budget, &mut overflow);

            // Yield once to give the PTY reader thread a chance to replenish.
            std::thread::yield_now();

            let data = pty.read()?;
            advance_with_budget(&mut self.core, &data, &mut budget, &mut overflow);

            for response in self.core.meta.pending_responses.drain(..) {
                pty.write(&response)?;
            }

            self.pending_input = overflow;
        }

        Ok(())
    }
}
