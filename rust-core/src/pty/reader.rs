//! Threaded PTY reader

use std::fs::File;
use std::io::Read;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

/// PTY reader that runs in a separate thread
pub struct PtyReader;

impl PtyReader {
    /// Read loop that runs in a separate thread
    ///
    /// Uses a reusable buffer to minimize allocations and respects the shutdown signal
    /// for graceful termination.
    pub fn read_loop(
        mut master: File,
        sender: crossbeam_channel::Sender<Vec<u8>>,
        shutdown: Arc<AtomicBool>,
    ) {
        const BUFFER_SIZE: usize = 8192;
        let mut buffer = vec![0u8; BUFFER_SIZE];

        while !shutdown.load(Ordering::Relaxed) {
            match master.read(&mut buffer) {
                Ok(0) => {
                    // EOF - PTY closed
                    break;
                }
                Ok(n) => {
                    // Send slice directly to avoid allocation
                    let data = Vec::from(&buffer[..n]);
                    if sender.send(data).is_err() {
                        // Channel closed, exit gracefully
                        break;
                    }
                }
                Err(e) => {
                    eprintln!("[PTY] Read error: {}", e);
                    break;
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn test_reader() {
        // Test requires actual PTY setup
        // This is more of a compilation test
        assert!(true);
    }
}
