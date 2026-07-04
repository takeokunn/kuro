//! Threaded PTY reader

use std::fs::File;
use std::io::Read as _;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

/// PTY reader that runs in a separate thread
pub struct PtyReader;

impl PtyReader {
    /// Read loop that runs in a separate thread
    ///
    /// Uses a reusable buffer to minimize allocations and respects the shutdown signal
    /// for graceful termination.
    // The Arc and Sender args are moved into the thread body — taking references
    // would require 'static lifetimes, which defeats the purpose.
    #[expect(
        clippy::needless_pass_by_value,
        reason = "args are moved into the thread body"
    )]
    pub fn read_loop(
        mut master: File,
        sender: std::sync::mpsc::SyncSender<Vec<u8>>,
        shutdown: Arc<AtomicBool>,
        process_exited: Arc<AtomicBool>,
    ) {
        const BUFFER_SIZE: usize = 65536;
        let mut buffer = vec![0u8; BUFFER_SIZE];

        while !shutdown.load(Ordering::Relaxed) {
            match master.read(&mut buffer) {
                Ok(0) => {
                    // EOF - child process exited
                    process_exited.store(true, Ordering::Relaxed);
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
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {
                    // EINTR: the blocking read was interrupted by a signal
                    // (e.g. SIGCHLD, SIGWINCH). This is transient — retry.
                    continue;
                }
                Err(e) => {
                    // Treat persistent read errors (e.g. EIO on Linux after child
                    // exit) the same as EOF: mark the process as exited so Emacs
                    // can close the buffer.
                    process_exited.store(true, Ordering::Relaxed);
                    eprintln!("[PTY] Read error: {e}");
                    break;
                }
            }
        }
    }
}

#[cfg(all(test, unix))]
#[path = "reader/tests.rs"]
mod tests;
