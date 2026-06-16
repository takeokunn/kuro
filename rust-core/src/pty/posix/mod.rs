//! POSIX PTY implementation using nix crate for safe fork/pty operations

mod child;
mod cleanup;
mod shell;

// Re-export for unit tests that test the child-env setup directly.
#[cfg(test)]
pub(crate) use child::setup_child_env;

use crate::{
    ffi::error::{pty_operation_error, pty_spawn_error},
    pty::reader::PtyReader,
    Result,
};
use cleanup::{reap_child_until, signal_child_tree, DROP_WAITPID_TIMEOUT_MS};
use nix::pty::{openpty, OpenptyResult, Winsize};
use nix::sys::signal::Signal;
use nix::unistd::{fork, ForkResult, Pid};
use std::os::unix::io::{AsRawFd, FromRawFd as _, IntoRawFd as _, RawFd};
use shell::ShellCommand;
#[cfg(test)]
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;

/// Channel capacity for PTY data - prevents unbounded memory growth
const CHANNEL_CAPACITY: usize = 100;

/// PTY master handle with proper fork/exec implementation
pub struct Pty {
    /// Master file descriptor
    master: std::fs::File,
    /// Child process ID
    child_pid: Pid,
    /// Channel for receiving PTY output (bounded for backpressure)
    receiver: std::sync::mpsc::Receiver<Vec<u8>>,
    /// One-item peek buffer populated by `has_pending_data` so that `read` can
    /// drain it first without losing the already-consumed channel item.
    peek_buffer: std::sync::Mutex<Option<Vec<u8>>>,
    /// Shutdown signal for reader thread
    shutdown: Arc<AtomicBool>,
    /// Thread handle for PTY reader
    _reader_thread: thread::JoinHandle<()>,
    /// Flag set by the reader thread when EOF is detected (child process exited).
    process_exited: Arc<AtomicBool>,
}

impl Pty {
    /// Search `$PATH` for an executable named `command`.
    ///
    /// Returns the first absolute path found, or `None` if not found.
    #[cfg(test)]
    fn find_in_path(command: &str) -> Option<PathBuf> {
        ShellCommand::find_in_path(command)
    }

    /// Validate shell command against whitelist
    ///
    /// Ensures only allowed shells can be spawned to prevent command injection.
    /// Resolves the command to an absolute path and checks the basename.
    ///
    /// For absolute paths (e.g. NixOS Nix store paths like `/nix/store/…/bin/fish`),
    /// validates existence and executability directly without a PATH lookup.
    /// For short names, resolves via `which` as before.
    #[cfg(test)]
    fn validate_shell(command: &str) -> Result<PathBuf> {
        ShellCommand::resolve(command).map(ShellCommand::into_path)
    }

    fn build_spawn_winsize(rows: u16, cols: u16) -> Winsize {
        Winsize {
            ws_row: rows,
            ws_col: cols,
            ws_xpixel: 0,
            ws_ypixel: 0,
        }
    }

    fn open_spawn_pty(command: &str, rows: u16, cols: u16) -> Result<OpenptyResult> {
        openpty(Some(&Self::build_spawn_winsize(rows, cols)), None)
            .map_err(|e| pty_spawn_error(command, &format!("Failed to open PTY: {e}")))
    }

    fn duplicate_reader_fd(master: &std::fs::File) -> Result<RawFd> {
        // SAFETY: master.as_raw_fd() is a valid open fd returned by openpty;
        // libc::dup and libc::fcntl are safe on valid fds; the result is
        // checked for -1 (error) before any further use.
        unsafe {
            // dup3 with O_CLOEXEC is available on macOS via F_DUPFD_CLOEXEC fcntl
            let fd = libc::dup(master.as_raw_fd());
            if fd == -1 {
                return Err(pty_operation_error("dup", "Failed to duplicate master fd"));
            }
            // Set FD_CLOEXEC so the fd is closed on exec in child processes
            let flags = libc::fcntl(fd, libc::F_GETFD);
            if flags == -1 || libc::fcntl(fd, libc::F_SETFD, flags | libc::FD_CLOEXEC) == -1 {
                libc::close(fd);
                return Err(pty_operation_error(
                    "fcntl",
                    "Failed to set FD_CLOEXEC on reader fd",
                ));
            }
            Ok(fd)
        }
    }

    fn spawn_reader_thread(
        reader_file: std::fs::File,
        sender: std::sync::mpsc::SyncSender<Vec<u8>>,
        shutdown: Arc<AtomicBool>,
        process_exited: Arc<AtomicBool>,
    ) -> thread::JoinHandle<()> {
        let shutdown_clone = shutdown.clone();
        let process_exited_clone = process_exited.clone();
        thread::spawn(move || {
            PtyReader::read_loop(reader_file, sender, shutdown_clone, process_exited_clone);
        })
    }

    fn build_parent_pty(
        master: std::fs::File,
        child_pid: Pid,
        receiver: std::sync::mpsc::Receiver<Vec<u8>>,
        shutdown: Arc<AtomicBool>,
        reader_thread: thread::JoinHandle<()>,
        process_exited: Arc<AtomicBool>,
    ) -> Self {
        Self {
            master,
            child_pid,
            receiver,
            peek_buffer: std::sync::Mutex::new(None),
            shutdown,
            _reader_thread: reader_thread,
            process_exited,
        }
    }

    fn spawn_parent_pty(
        master: std::fs::File,
        child_pid: Pid,
        receiver: std::sync::mpsc::Receiver<Vec<u8>>,
        sender: std::sync::mpsc::SyncSender<Vec<u8>>,
        shutdown: Arc<AtomicBool>,
        reader_file: std::fs::File,
        process_exited: Arc<AtomicBool>,
    ) -> Self {
        let reader_thread = Self::spawn_reader_thread(
            reader_file,
            sender,
            Arc::clone(&shutdown),
            Arc::clone(&process_exited),
        );

        Self::build_parent_pty(
            master,
            child_pid,
            receiver,
            shutdown,
            reader_thread,
            process_exited,
        )
    }

    /// Spawn a new PTY with the given shell command and initial terminal dimensions.
    ///
    /// Passing `rows` and `cols` to `openpty` is critical: it sets the PTY window
    /// size **before** the child process is created, so bash/readline sees the
    /// correct dimensions when it calls `TIOCGWINSZ` on startup.  Without this,
    /// the PTY is created with a 0×0 window size and readline falls back to dumb
    /// terminal mode — causing control characters to be echoed as `^X` instead of
    /// being handled as cursor-movement commands.
    ///
    /// This creates a proper PTY master/slave pair using `openpty()`,
    /// forks a child process, and executes the shell with the slave
    /// PTY as stdin/stdout/stderr.
    ///
    /// # Errors
    /// Returns `Err` if the shell path is invalid, `openpty` fails, or `fork` fails.
    pub fn spawn(command: &str, shell_args: &[String], rows: u16, cols: u16) -> Result<Self> {
        // Validate command against whitelist
        let shell = ShellCommand::resolve(command)?;

        // Open PTY master/slave pair with the correct initial window size.
        // Setting the winsize here (before fork) ensures the child process sees
        // the correct dimensions from TIOCGWINSZ on its very first query.
        let OpenptyResult { master, slave } = Self::open_spawn_pty(command, rows, cols)?;

        // Create bounded channel for backpressure
        let (sender, receiver) = std::sync::mpsc::sync_channel(CHANNEL_CAPACITY);
        let shutdown = Arc::new(AtomicBool::new(false));
        let process_exited = Arc::new(AtomicBool::new(false));

        // Convert master to File for parent
        // SAFETY: master.into_raw_fd() transfers ownership of the valid PTY master fd;
        // File::from_raw_fd takes exclusive ownership; the OwnedFd is consumed.
        let master_file = unsafe { std::fs::File::from_raw_fd(master.into_raw_fd()) };

        // Clone master fd for reader thread, with O_CLOEXEC so the fd is
        // automatically closed in any fork()ed child processes (prevents
        // child processes from holding the master fd open across sessions).
        let reader_fd = Self::duplicate_reader_fd(&master_file)?;
        // SAFETY: reader_fd was obtained from dup above and is valid; File::from_raw_fd
        // takes ownership; the fd will only be accessed through this File handle.
        let reader_file = unsafe { std::fs::File::from_raw_fd(reader_fd) };

        // Fork to create child process
        // SAFETY: all shared state (channel sender, Arc clones, reader_fd) is fully set
        // up before forking; the Child branch runs only async-signal-safe code until exec.
        match unsafe { fork() } {
        Ok(ForkResult::Parent { child }) => Ok(Self::spawn_parent_pty(
            master_file,
            child,
            receiver,
            sender,
            shutdown,
            reader_file,
            process_exited,
        )),
            Ok(ForkResult::Child) => {
                // Child process: delegate all setup to the helper.
                // If the helper returns Err, the error propagates out of spawn() in the
                // child process (the parent is in a separate address space and unaffected).
                child::exec_in_child(child::ChildExecContext {
                    slave,
                    master_file,
                    reader_fd,
                    shell_path: shell.as_path(),
                    rows,
                    cols,
                    command,
                    shell_args,
                })?;
                // exec_in_child calls execv which replaces the process on success.
                std::process::exit(1);
            }
            Err(errno) => Err(pty_spawn_error(
                command,
                &format!("Failed to fork: {errno}"),
            )),
        }
    }

    /// Write bytes to the PTY
    ///
    /// # Errors
    /// Returns `Err` if the underlying `write_all` to the master file descriptor fails.
    pub fn write(&mut self, bytes: &[u8]) -> Result<()> {
        use std::io::Write as _;

        self.master
            .write_all(bytes)
            .map_err(|e| pty_operation_error("write", &format!("Failed to write to PTY: {e}")))?;

        Ok(())
    }

    /// Read bytes from the PTY (non-blocking, drains all available data)
    ///
    /// # Errors
    /// Never returns an error in the current implementation (channel `try_recv` is infallible after data arrives).
    pub fn read(&mut self) -> Result<Vec<u8>> {
        let mut all_data = Vec::with_capacity(8192);

        // Drain the peek buffer first (populated by has_pending_data)
        if let Some(data) = self
            .peek_buffer
            .lock()
            .expect("peek_buffer lock poisoned")
            .take()
        {
            all_data.extend(data);
        }

        // Drain remaining channel data
        while let Ok(data) = self.receiver.try_recv() {
            all_data.extend(data);
        }

        Ok(all_data)
    }

    /// Read up to `max_bytes` from the PTY channel without blocking.
    ///
    /// Any bytes beyond the limit are kept in `peek_buffer` so a later read can
    /// resume from the exact split point.  This prevents chatty full-screen TUIs
    /// from keeping a single render poll inside the channel-drain loop forever.
    ///
    /// # Errors
    /// Never returns an error in the current implementation (channel `try_recv` is infallible after data arrives).
    pub fn read_limited(&mut self, max_bytes: usize) -> Result<Vec<u8>> {
        if max_bytes == 0 {
            return Ok(Vec::new());
        }

        let mut all_data = Vec::with_capacity(max_bytes.min(8192));

        if let Some(mut data) = self
            .peek_buffer
            .lock()
            .expect("peek_buffer lock poisoned")
            .take()
        {
            if data.len() > max_bytes {
                let overflow = data.split_off(max_bytes);
                all_data.extend(data);
                *self.peek_buffer.lock().expect("peek_buffer lock poisoned") = Some(overflow);
                return Ok(all_data);
            }
            all_data.extend(data);
        }

        while all_data.len() < max_bytes {
            match self.receiver.try_recv() {
                Ok(mut data) => {
                    let remaining = max_bytes - all_data.len();
                    if data.len() > remaining {
                        let overflow = data.split_off(remaining);
                        all_data.extend(data);
                        *self.peek_buffer.lock().expect("peek_buffer lock poisoned") =
                            Some(overflow);
                        break;
                    }
                    all_data.extend(data);
                }
                Err(_) => break,
            }
        }

        Ok(all_data)
    }

    /// Check if the PTY channel has pending unread data (non-blocking, does not consume).
    #[must_use]
    pub fn has_pending_data(&self) -> bool {
        // Check peek buffer first (previously peeked item)
        {
            let peek = self.peek_buffer.lock().expect("peek_buffer lock poisoned");
            if peek.is_some() {
                return true;
            }
        }
        // Try to consume one item and store it in the peek buffer
        match self.receiver.try_recv() {
            Ok(data) => {
                *self.peek_buffer.lock().expect("peek_buffer lock poisoned") = Some(data);
                true
            }
            Err(_) => false,
        }
    }

    /// Return the child process PID.
    #[inline]
    #[must_use]
    #[expect(
        clippy::cast_sign_loss,
        reason = "PIDs are non-negative; as_raw() returns i32 by POSIX convention but valid PIDs never exceed i32::MAX"
    )]
    pub const fn pid(&self) -> u32 {
        self.child_pid.as_raw() as u32
    }

    /// Returns true if the child process has not yet exited.
    ///
    /// Set to false by the reader thread when it detects EOF (Ok(0)) on the
    /// master PTY file descriptor, which happens when the child process exits.
    #[inline]
    #[must_use]
    pub fn is_alive(&self) -> bool {
        !self.process_exited.load(Ordering::Relaxed)
    }

    /// Set PTY window size
    ///
    /// # Errors
    /// Returns `Err` if the `TIOCSWINSZ` ioctl fails.
    pub fn set_winsize(&mut self, rows: u16, cols: u16) -> Result<()> {
        let winsize = Winsize {
            ws_row: rows,
            ws_col: cols,
            ws_xpixel: 0,
            ws_ypixel: 0,
        };

        // SAFETY: self.master is a valid open PTY master fd held by this Pty;
        // winsize is stack-allocated and outlives the ioctl call.
        let ret = unsafe { libc::ioctl(self.master.as_raw_fd(), libc::TIOCSWINSZ, &winsize) };

        if ret == -1 {
            return Err(pty_operation_error(
                "TIOCSWINSZ",
                "Failed to set PTY window size",
            ));
        }

        Ok(())
    }
}

impl AsRawFd for Pty {
    fn as_raw_fd(&self) -> RawFd {
        self.master.as_raw_fd()
    }
}

impl Drop for Pty {
    /// Ensure child process is cleaned up when the Pty is dropped.
    ///
    /// Strategy: close the PTY master → SIGHUP process group → bounded WNOHANG
    /// reap → SIGKILL process group → bounded WNOHANG reap. This avoids an
    /// unbounded wait when the shell is blocked on a full-screen child process
    /// that ignores SIGHUP.
    ///
    /// Closing the master first makes the slave side observe hangup/EOF before
    /// the bounded reap loop starts; the reader thread exits on that same EOF.
    fn drop(&mut self) {
        // Signal the reader thread to stop after its current read returns.
        self.shutdown
            .store(true, std::sync::atomic::Ordering::Relaxed);

        if let Ok(dev_null) = std::fs::File::open("/dev/null") {
            let master = std::mem::replace(&mut self.master, dev_null);
            drop(master);
        }

        signal_child_tree(self.child_pid, Signal::SIGHUP);
        let timeout = std::time::Duration::from_millis(DROP_WAITPID_TIMEOUT_MS);
        if !reap_child_until(self.child_pid, timeout) {
            signal_child_tree(self.child_pid, Signal::SIGKILL);
            if !reap_child_until(self.child_pid, timeout) {
                eprintln!("[PTY] Drop: child did not exit after SIGKILL; giving up");
            }
        }

        // The reader thread, unblocked by EOF on the master, will detect the
        // shutdown flag or a channel-send error and exit on its own.
    }
}

#[cfg(test)]
#[cfg(unix)]
#[path = "../tests/posix.rs"]
mod tests;
