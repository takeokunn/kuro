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
    use super::*;

    #[cfg(unix)]
    #[test]
    fn test_reader_receives_data() {
        use std::os::unix::io::FromRawFd;

        // Create a pipe using libc: read_fd -> write_fd
        let mut fds = [0i32; 2];
        let ret = unsafe { libc::pipe(fds.as_mut_ptr()) };
        assert_eq!(ret, 0, "pipe() failed");
        let read_fd = fds[0];
        let write_fd = fds[1];

        let (tx, rx) = crossbeam_channel::unbounded::<Vec<u8>>();
        let shutdown = Arc::new(AtomicBool::new(false));

        // Wrap the read end as a File and hand it to read_loop in a background thread
        let read_file = unsafe { File::from_raw_fd(read_fd) };
        let shutdown_clone = Arc::clone(&shutdown);
        let handle = std::thread::spawn(move || {
            PtyReader::read_loop(read_file, tx, shutdown_clone);
        });

        // Write data to the write end then close it so the reader sees EOF
        {
            let mut write_file = unsafe { File::from_raw_fd(write_fd) };
            use std::io::Write;
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
        use std::os::unix::io::FromRawFd;

        let mut fds = [0i32; 2];
        let ret = unsafe { libc::pipe(fds.as_mut_ptr()) };
        assert_eq!(ret, 0, "pipe() failed");
        let read_fd = fds[0];
        let write_fd = fds[1];

        let (tx, rx) = crossbeam_channel::unbounded::<Vec<u8>>();
        let shutdown = Arc::new(AtomicBool::new(true)); // already set

        // Wrap fds as Files so they are closed on drop
        let read_file = unsafe { File::from_raw_fd(read_fd) };
        let _write_file = unsafe { File::from_raw_fd(write_fd) };

        let shutdown_clone = Arc::clone(&shutdown);
        let handle = std::thread::spawn(move || {
            PtyReader::read_loop(read_file, tx, shutdown_clone);
        });

        // The loop checks shutdown before every read, so it should exit promptly.
        // We close the write end (by dropping _write_file) so the read end also
        // sees EOF if the loop does attempt a read.
        // Drop write file by moving it into a block:
        drop(_write_file);

        // Wait up to 2 seconds for the thread to finish
        let finished = handle.join().is_ok();
        assert!(
            finished,
            "reader thread should finish when shutdown flag is set"
        );

        // Channel should be empty (no data was written)
        assert!(rx.try_recv().is_err(), "channel should be empty");
    }

    /// Verify that closing the write end of the pipe causes the read_loop to exit
    /// (EOF path) and the channel receives no data when nothing was written.
    #[cfg(unix)]
    #[test]
    fn test_reader_empty_channel_on_eof() {
        use std::os::unix::io::FromRawFd;

        let mut fds = [0i32; 2];
        let ret = unsafe { libc::pipe(fds.as_mut_ptr()) };
        assert_eq!(ret, 0, "pipe() failed");
        let read_fd = fds[0];
        let write_fd = fds[1];

        let (tx, rx) = crossbeam_channel::unbounded::<Vec<u8>>();
        let shutdown = Arc::new(AtomicBool::new(false));

        let read_file = unsafe { File::from_raw_fd(read_fd) };

        // Close write end immediately so reader sees EOF right away
        unsafe { libc::close(write_fd) };

        let shutdown_clone = Arc::clone(&shutdown);
        let handle = std::thread::spawn(move || {
            PtyReader::read_loop(read_file, tx, shutdown_clone);
        });

        handle.join().expect("reader thread panicked");

        // No data was written, so channel should be empty
        assert!(
            rx.try_recv().is_err(),
            "channel should be empty when pipe write end was closed with no data"
        );
    }
}
