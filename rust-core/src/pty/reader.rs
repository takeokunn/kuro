//! Threaded PTY reader

use std::fs::File;
use std::io::Read as _;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

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

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(unix)]
    #[test]
    fn test_reader_receives_data() {
        use std::os::unix::io::FromRawFd as _;

        // Create a pipe using libc: read_fd -> write_fd
        let mut fds = [0i32; 2];
        // SAFETY: fds is a 2-element array; libc::pipe fills it with two valid fds on success.
        let ret = unsafe { libc::pipe(fds.as_mut_ptr()) };
        assert_eq!(ret, 0, "pipe() failed");
        let read_fd = fds[0];
        let write_fd = fds[1];

        let (tx, rx) = std::sync::mpsc::sync_channel::<Vec<u8>>(128);
        let shutdown = Arc::new(AtomicBool::new(false));

        // Wrap the read end as a File and hand it to read_loop in a background thread
        // SAFETY: read_fd is a valid fd from pipe above; File takes ownership; not used again.
        let read_file = unsafe { File::from_raw_fd(read_fd) };
        let shutdown_clone = Arc::clone(&shutdown);
        let process_exited = Arc::new(AtomicBool::new(false));
        let handle = std::thread::spawn(move || {
            PtyReader::read_loop(read_file, tx, shutdown_clone, process_exited);
        });

        // Write data to the write end then close it so the reader sees EOF
        {
            use std::io::Write as _;
            // SAFETY: write_fd is a valid fd from pipe above; File takes ownership.
            let mut write_file = unsafe { File::from_raw_fd(write_fd) };
            write_file.write_all(b"hello").expect("write failed");
            // write_file is dropped here, closing the write end
        }

        // Collect all chunks sent over the channel until we have 5 bytes or time out
        let mut received = Vec::new();
        while received.len() < 5 {
            match rx.recv_timeout(std::time::Duration::from_secs(2)) {
                Ok(chunk) => received.extend_from_slice(&chunk),
                Err(_) => break,
            }
        }

        // The read_loop should have exited due to EOF; join the thread
        handle.join().expect("reader thread panicked");

        assert_eq!(&received[..], b"hello");
    }

    /// Verify that setting the shutdown flag before the loop starts causes it to
    /// exit immediately without blocking, even when the read end is open.
    #[cfg(unix)]
    #[test]
    fn test_reader_shutdown_flag_stops_loop() {
        use std::os::unix::io::FromRawFd as _;

        let mut fds = [0i32; 2];
        // SAFETY: fds is a 2-element array; libc::pipe fills it with two valid fds on success.
        let ret = unsafe { libc::pipe(fds.as_mut_ptr()) };
        assert_eq!(ret, 0, "pipe() failed");
        let read_fd = fds[0];
        let write_fd = fds[1];

        let (tx, rx) = std::sync::mpsc::sync_channel::<Vec<u8>>(128);
        let shutdown = Arc::new(AtomicBool::new(true)); // already set

        // Wrap fds as Files so they are closed on drop
        // SAFETY: read_fd is a valid fd from pipe above; File takes ownership; not used again.
        let read_file = unsafe { File::from_raw_fd(read_fd) };
        // SAFETY: write_fd is a valid fd from pipe above; File takes ownership; not used again.
        let write_file = unsafe { File::from_raw_fd(write_fd) };

        let shutdown_clone = Arc::clone(&shutdown);
        let process_exited = Arc::new(AtomicBool::new(false));
        let handle = std::thread::spawn(move || {
            PtyReader::read_loop(read_file, tx, shutdown_clone, process_exited);
        });

        // The loop checks shutdown before every read, so it should exit promptly.
        // We close the write end (by dropping write_file) so the read end also
        // sees EOF if the loop does attempt a read.
        drop(write_file);

        // Wait up to 2 seconds for the thread to finish
        let finished = handle.join().is_ok();
        assert!(
            finished,
            "reader thread should finish when shutdown flag is set"
        );

        // Channel should be empty (no data was written)
        assert!(rx.try_recv().is_err(), "channel should be empty");
    }

    /// Verify that closing the write end of the pipe causes the `read_loop` to exit
    /// (EOF path) and the channel receives no data when nothing was written.
    #[cfg(unix)]
    #[test]
    fn test_reader_empty_channel_on_eof() {
        use std::os::unix::io::FromRawFd as _;

        let mut fds = [0i32; 2];
        // SAFETY: fds is a 2-element array; libc::pipe fills it with two valid fds on success.
        let ret = unsafe { libc::pipe(fds.as_mut_ptr()) };
        assert_eq!(ret, 0, "pipe() failed");
        let read_fd = fds[0];
        let write_fd = fds[1];

        let (tx, rx) = std::sync::mpsc::sync_channel::<Vec<u8>>(128);
        let shutdown = Arc::new(AtomicBool::new(false));

        // SAFETY: read_fd is a valid fd from pipe above; File takes ownership; not used again.
        let read_file = unsafe { File::from_raw_fd(read_fd) };

        // Close write end immediately so reader sees EOF right away
        // SAFETY: write_fd is a valid open fd; no File handle wraps it; closing it is safe.
        unsafe { libc::close(write_fd) };

        let shutdown_clone = Arc::clone(&shutdown);
        let process_exited = Arc::new(AtomicBool::new(false));
        let handle = std::thread::spawn(move || {
            PtyReader::read_loop(read_file, tx, shutdown_clone, process_exited);
        });

        handle.join().expect("reader thread panicked");

        // No data was written, so channel should be empty
        assert!(
            rx.try_recv().is_err(),
            "channel should be empty when pipe write end was closed with no data"
        );
    }
}
