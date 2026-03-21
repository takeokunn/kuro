//! POSIX PTY implementation using nix crate for safe fork/pty operations

use crate::{
    ffi::error::{invalid_parameter_error, pty_operation_error, pty_spawn_error},
    pty::reader::PtyReader,
    Result,
};
use nix::pty::{openpty, OpenptyResult, Winsize};
use nix::sys::wait::waitpid;
use nix::unistd::{fork, ForkResult, Pid};
use std::os::unix::io::{AsRawFd, FromRawFd as _, IntoRawFd as _, RawFd};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;

/// Allowed shells whitelist for security
const ALLOWED_SHELLS: &[&str] = &["bash", "zsh", "sh", "fish"];

/// Channel capacity for PTY data - prevents unbounded memory growth
const CHANNEL_CAPACITY: usize = 100;

/// PTY master handle with proper fork/exec implementation
pub struct Pty {
    /// Master file descriptor
    master: std::fs::File,
    /// Child process ID
    child_pid: Pid,
    /// Channel for receiving PTY output (bounded for backpressure)
    receiver: crossbeam_channel::Receiver<Vec<u8>>,
    /// Shutdown signal for reader thread
    shutdown: Arc<AtomicBool>,
    /// Thread handle for PTY reader
    _reader_thread: thread::JoinHandle<()>,
    /// Flag set by the reader thread when EOF is detected (child process exited).
    process_exited: Arc<AtomicBool>,
}

impl Pty {
    /// Validate shell command against whitelist
    ///
    /// Ensures only allowed shells can be spawned to prevent command injection.
    /// Resolves the command to an absolute path and checks the basename.
    fn validate_shell(command: &str) -> Result<PathBuf> {
        let path = which::which(command)
            .map_err(|e| invalid_parameter_error("command", &format!("Shell not found: {e}")))?;

        let basename = path
            .file_name()
            .and_then(|n| n.to_str())
            .ok_or_else(|| invalid_parameter_error("command", "Invalid shell name"))?;

        if !ALLOWED_SHELLS.contains(&basename) {
            return Err(invalid_parameter_error(
                "command",
                &format!(
                    "Shell '{}' not allowed. Allowed shells: {}",
                    basename,
                    ALLOWED_SHELLS.join(", ")
                ),
            ));
        }

        Ok(path)
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
    #[expect(
        clippy::too_many_lines,
        reason = "PTY setup is inherently multi-step: open, dup, fork, exec, teardown — splitting into smaller fns would increase complexity without clarity"
    )]
    pub fn spawn(command: &str, rows: u16, cols: u16) -> Result<Self> {
        // Validate command against whitelist
        let shell_path = Self::validate_shell(command)?;

        // Open PTY master/slave pair with the correct initial window size.
        // Setting the winsize here (before fork) ensures the child process sees
        // the correct dimensions from TIOCGWINSZ on its very first query.
        let winsize = Winsize {
            ws_row: rows,
            ws_col: cols,
            ws_xpixel: 0,
            ws_ypixel: 0,
        };
        let OpenptyResult { master, slave } = openpty(Some(&winsize), None)
            .map_err(|e| pty_spawn_error(command, &format!("Failed to open PTY: {e}")))?;

        // Create bounded channel for backpressure
        let (sender, receiver) = crossbeam_channel::bounded(CHANNEL_CAPACITY);
        let shutdown = Arc::new(AtomicBool::new(false));
        let process_exited = Arc::new(AtomicBool::new(false));

        // Clone master fd for reader thread, with O_CLOEXEC so the fd is
        // automatically closed in any fork()ed child processes (prevents
        // child processes from holding the master fd open across sessions).
        // SAFETY: master.as_raw_fd() is a valid open fd returned by openpty;
        // libc::dup and libc::fcntl are safe on valid fds; the result is
        // checked for -1 (error) before any further use.
        let reader_fd = unsafe {
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
            fd
        };
        // SAFETY: reader_fd was obtained from dup above and is valid; File::from_raw_fd
        // takes ownership; the fd will only be accessed through this File handle.
        let reader_file = unsafe { std::fs::File::from_raw_fd(reader_fd) };

        // Convert master to File for parent
        // SAFETY: master.into_raw_fd() transfers ownership of the valid PTY master fd;
        // File::from_raw_fd takes exclusive ownership; the OwnedFd is consumed.
        let master_file = unsafe { std::fs::File::from_raw_fd(master.into_raw_fd()) };

        // Fork to create child process
        // SAFETY: all shared state (channel sender, Arc clones, reader_fd) is fully set
        // up before forking; the Child branch runs only async-signal-safe code until exec.
        match unsafe { fork() } {
            Ok(ForkResult::Parent { child }) => {
                // Parent process: spawn reader thread and return Pty
                let shutdown_clone = shutdown.clone();
                let process_exited_clone = process_exited.clone();
                let reader_thread = thread::spawn(move || {
                    PtyReader::read_loop(reader_file, sender, shutdown_clone, process_exited_clone);
                });

                Ok(Self {
                    master: master_file,
                    child_pid: child,
                    receiver,
                    shutdown,
                    _reader_thread: reader_thread,
                    process_exited,
                })
            }
            Ok(ForkResult::Child) => {
                // Child process: set up PTY and exec shell

                // Create new session
                nix::unistd::setsid().map_err(|e| {
                    pty_operation_error("setsid", &format!("Failed to setsid: {e}"))
                })?;

                // Set slave PTY as controlling terminal
                // TIOCSCTTY is required on all POSIX platforms after setsid()
                // to establish the slave PTY as the controlling terminal.
                // Without this, tcgetpgrp() fails in the shell.
                // SAFETY: slave is a valid PTY slave fd; TIOCSCTTY is async-signal-safe
                // after setsid(); the third arg (0) is a required no-op placeholder.
                // TIOCSCTTY is u32 on macOS, u64 on Linux; .into() needed cross-platform
                #[allow(clippy::useless_conversion)]
                unsafe {
                    if libc::ioctl(slave.as_raw_fd(), libc::TIOCSCTTY.into(), 0) == -1 {
                        return Err(pty_operation_error(
                            "TIOCSCTTY",
                            &format!(
                                "Failed to set controlling terminal: {}",
                                std::io::Error::last_os_error()
                            ),
                        ));
                    }
                }

                // Duplicate slave PTY to stdin, stdout, stderr
                // SAFETY: slave.as_raw_fd() is a valid open fd; dup2 to 0/1/2 is
                // async-signal-safe and valid in the child process after fork.
                unsafe {
                    if libc::dup2(slave.as_raw_fd(), 0) == -1 {
                        return Err(pty_operation_error("dup2", "Failed to dup2 stdin"));
                    }
                    if libc::dup2(slave.as_raw_fd(), 1) == -1 {
                        return Err(pty_operation_error("dup2", "Failed to dup2 stdout"));
                    }
                    if libc::dup2(slave.as_raw_fd(), 2) == -1 {
                        return Err(pty_operation_error("dup2", "Failed to dup2 stderr"));
                    }
                }

                // Close slave PTY (we have duplicates now)
                drop(slave);

                // Close master PTY fd in child — the child must not hold the master end.
                // Inherited master fds interfere with process group management and can
                // prevent the parent from detecting child exit (no EOF on master).
                drop(master_file);
                // SAFETY: reader_fd is a valid open fd in the child; all File handles for
                // reader_fd exist only in the parent path; closing it prevents the child
                // from holding the master end open (which would block parent EOF detection).
                unsafe {
                    libc::close(reader_fd);
                }

                // Clear terminal-multiplexer env vars so that programs such as tmux
                // and GNU screen behave correctly when launched inside kuro.  Without
                // this, inheriting $TMUX causes tmux to believe it is already nested
                // inside an existing session and refuse to attach a new client.
                std::env::remove_var("TMUX");
                std::env::remove_var("STY");

                // Remove Emacs-specific variables so that programs inside kuro
                // do not detect the parent Emacs environment.  Without this,
                // $INSIDE_EMACS causes emacsclient and other Emacs-aware tools
                // to try talking to the parent Emacs server through the PTY,
                // producing garbled output ("*ERROR*: Unknown message").
                std::env::remove_var("INSIDE_EMACS");
                std::env::remove_var("EMACS_SOCKET_NAME");
                // Signal that we are running inside kuro, so programs can
                // detect the kuro terminal environment if needed.
                std::env::set_var("KURO_TERMINAL", "1");

                // Set TERM so that readline/ncurses programs (bash, vim, etc.) know
                // what escape sequences to use.  Without TERM set, bash readline will
                // not handle cursor-movement keys correctly and may echo raw control
                // characters such as ^B, ^F instead of moving the cursor.
                std::env::set_var("TERM", "xterm-256color");
                // COLORTERM signals 24-bit truecolor support to color-aware programs.
                std::env::set_var("COLORTERM", "truecolor");
                // Set COLUMNS and LINES so bash/readline uses the correct terminal
                // dimensions even before it can call TIOCGWINSZ.  This is a belt-and-
                // suspenders complement to passing winsize to openpty: some shells read
                // these env vars first and only fall back to the ioctl if they are unset.
                std::env::set_var("COLUMNS", cols.to_string());
                std::env::set_var("LINES", rows.to_string());

                // Set the window size on fd 0 (stdin = slave PTY) inside the child.
                //
                // Even though we already called openpty(Some(&winsize), ...) before
                // the fork, calling TIOCSWINSZ again here on fd 0 is the most reliable
                // guarantee that readline's very first TIOCGWINSZ call — which happens
                // during terminal initialisation, before the shell's own SIGWINCH handler
                // fires — returns non-zero columns.  Without this, some readline builds
                // see 0 columns and permanently fall back to dumb/novis mode, causing
                // C-b/C-f/C-e to be echoed as literal ^X characters instead of moving
                // the cursor.
                // SAFETY: fd 0 is the PTY slave we dup2'd above; TIOCSWINSZ reads a
                // stack-allocated winsize struct that outlives the ioctl call.
                unsafe {
                    let ws = libc::winsize {
                        ws_row: rows,
                        ws_col: cols,
                        ws_xpixel: 0,
                        ws_ypixel: 0,
                    };
                    libc::ioctl(0, libc::TIOCSWINSZ, &ws);
                }

                // Execute shell using the full absolute path validated above.
                //
                // We intentionally use execv (not execvp) so the kernel runs exactly
                // the binary that validate_shell() resolved — e.g. /bin/bash — rather
                // than whatever "bash" $PATH resolves to first (which on a Homebrew
                // macOS system can be a different version at /opt/homebrew/bin/bash).
                // Using argv[0] = basename keeps ps/top output readable.
                let shell_full_cstr =
                    std::ffi::CString::new(shell_path.to_str().ok_or_else(|| {
                        pty_spawn_error(command, "Shell path is not valid UTF-8")
                    })?)
                    .map_err(|e| pty_spawn_error(command, &format!("Invalid shell path: {e}")))?;

                let shell_name = shell_path
                    .file_name()
                    .and_then(|n| n.to_str())
                    .unwrap_or("sh");
                let shell_name_cstr = std::ffi::CString::new(shell_name)
                    .map_err(|e| pty_spawn_error(command, &format!("Invalid shell name: {e}")))?;

                // argv[0] = basename (e.g. "bash"), argv[1..] = empty (interactive login
                // flags can be added here if needed, but the default is interactive mode
                // because stdin is a TTY).
                nix::unistd::execv(&shell_full_cstr, &[shell_name_cstr.as_c_str()])
                    .map_err(|e| pty_spawn_error(command, &format!("Failed to exec shell: {e}")))?;

                // execvp should not return, but if it does, exit
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
        let mut all_data = Vec::new();

        // Drain all available data from the channel
        while let Ok(data) = self.receiver.try_recv() {
            all_data.extend(data);
        }

        Ok(all_data)
    }

    /// Check if the PTY channel has pending unread data (non-blocking, does not consume).
    #[must_use]
    pub fn has_pending_data(&self) -> bool {
        !self.receiver.is_empty()
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
    /// Sends SIGHUP to the child so it exits, which causes the slave PTY to
    /// close and unblocks the reader thread.  Waits for the child to prevent
    /// zombie processes.  The reader thread will detect EOF on the master fd
    /// and exit on its own once the child has closed the slave side.
    fn drop(&mut self) {
        // Signal the reader thread to stop after its current read returns
        self.shutdown
            .store(true, std::sync::atomic::Ordering::Relaxed);

        // Send SIGHUP to the child process so it exits gracefully
        if let Err(e) = nix::sys::signal::kill(self.child_pid, nix::sys::signal::Signal::SIGHUP) {
            eprintln!("[PTY] Drop: failed to send SIGHUP: {e}");
        }

        // Wait for the child to exit (prevents zombie processes)
        match waitpid(self.child_pid, None) {
            Ok(_) => {}
            Err(e) => {
                eprintln!("[PTY] Drop: waitpid failed: {e}");
            }
        }
        // The master File is dropped next (by the compiler-generated cleanup),
        // which closes the master fd.  The reader thread, unblocked by EOF on
        // the master, will detect the shutdown flag or a channel-send error and
        // exit on its own.
    }
}

#[cfg(test)]
#[cfg(unix)]
#[path = "tests/posix.rs"]
mod tests;
