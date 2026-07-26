// PTY read/poll orchestration for TerminalSession.

use super::{advance_with_budget, TerminalSession, MAX_BYTES_PER_POLL};
use crate::{error::KuroError, Result};

fn read_for_remaining_budget(
    budget: usize,
    read: impl FnOnce(usize) -> Result<Vec<u8>>,
) -> Result<Vec<u8>> {
    if budget == 0 {
        return Ok(Vec::new());
    }
    read(budget)
}

fn flush_pending_responses(
    responses: &mut Vec<Vec<u8>>,
    mut write: impl FnMut(&[u8]) -> Result<usize>,
) -> Result<()> {
    let mut completed = 0;
    while completed < responses.len() {
        let mut offset = 0;
        while offset < responses[completed].len() {
            match write(&responses[completed][offset..]) {
                Ok(0) => {
                    responses[completed].drain(..offset);
                    responses.drain(..completed);
                    return Err(invalid_write_progress_error());
                }
                Ok(written) => offset += written,
                Err(error) => {
                    responses[completed].drain(..offset);
                    responses.drain(..completed);
                    return Err(error);
                }
            }
        }
        completed += 1;
    }

    responses.clear();
    Ok(())
}

fn invalid_write_progress_error() -> KuroError {
    crate::ffi::error::invalid_parameter_error("response", "PTY write made no forward progress")
}

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

            if budget > 0 {
                let data = read_for_remaining_budget(budget, |limit| pty.read_limited(limit))?;
                advance_with_budget(&mut self.core, &data, &mut budget, &mut overflow);
            }

            // Yield once to give the PTY reader thread a chance to replenish.
            if budget > 0 {
                std::thread::yield_now();
                let data = read_for_remaining_budget(budget, |limit| pty.read_limited(limit))?;
                advance_with_budget(&mut self.core, &data, &mut budget, &mut overflow);
            }

            // Preserve parser input and terminal replies before any fallible PTY
            // write. Only remove a reply after it has been written successfully.
            self.pending_input = overflow;
            flush_pending_responses(&mut self.core.meta.pending_responses, |response| {
                pty.write(response)
            })?;
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::{flush_pending_responses, read_for_remaining_budget};
    use crate::ffi::error::invalid_parameter_error;

    #[test]
    fn read_uses_exact_remaining_budget_and_skips_zero_budget() {
        let mut requested = Vec::new();
        let data = read_for_remaining_budget(7, |limit| {
            requested.push(limit);
            Ok(vec![b'x'; limit])
        })
        .unwrap();
        let empty = read_for_remaining_budget(0, |limit| {
            requested.push(limit);
            Ok(vec![b'x'; limit])
        })
        .unwrap();

        assert_eq!(data.len(), 7);
        assert!(empty.is_empty());
        assert_eq!(requested, [7]);
    }

    #[test]
    fn failed_response_and_following_responses_remain_in_order() {
        let mut responses = vec![b"first".to_vec(), b"second".to_vec(), b"third".to_vec()];
        let mut attempted = Vec::new();

        let result = flush_pending_responses(&mut responses, |response| {
            attempted.push(response.to_vec());
            if response == b"second" {
                return Err(invalid_parameter_error(
                    "response",
                    "injected write failure",
                ));
            }
            Ok(response.len())
        });

        assert!(result.is_err());
        assert_eq!(attempted, [b"first".to_vec(), b"second".to_vec()]);
        assert_eq!(responses, [b"second".to_vec(), b"third".to_vec()]);
    }

    #[test]
    fn first_failed_response_preserves_the_entire_queue() {
        let mut responses = vec![b"first".to_vec(), b"second".to_vec()];

        let result = flush_pending_responses(&mut responses, |_| {
            Err(invalid_parameter_error(
                "response",
                "injected write failure",
            ))
        });

        assert!(result.is_err());
        assert_eq!(responses, [b"first".to_vec(), b"second".to_vec()]);
    }

    #[test]
    fn successful_flush_writes_in_order_and_empties_the_queue() {
        let mut responses = vec![b"first".to_vec(), b"second".to_vec(), b"third".to_vec()];
        let mut written = Vec::new();

        flush_pending_responses(&mut responses, |response| {
            written.push(response.to_vec());
            Ok(response.len())
        })
        .unwrap();

        assert_eq!(
            written,
            [b"first".to_vec(), b"second".to_vec(), b"third".to_vec()]
        );
        assert!(responses.is_empty());
    }

    #[test]
    fn partial_write_failure_preserves_only_the_unwritten_suffix() {
        let mut responses = vec![b"first".to_vec(), b"second".to_vec()];
        let mut calls = 0;

        let result = flush_pending_responses(&mut responses, |_response| {
            calls += 1;
            match calls {
                1 => Ok(2),
                _ => Err(invalid_parameter_error(
                    "response",
                    "injected partial write failure",
                )),
            }
        });

        assert!(result.is_err());
        assert_eq!(responses, [b"rst".to_vec(), b"second".to_vec()]);
    }
}
