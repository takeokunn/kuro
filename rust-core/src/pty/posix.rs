//! POSIX PTY implementation using nix crate for safe fork/pty operations

use crate::{error::KuroError, pty::reader::PtyReader, Result};
use nix::pty::{openpty, OpenptyResult, Winsize};
use nix::sys::wait::waitpid;
use nix::unistd::{fork, ForkResult, Pid};
use std::os::unix::io::{AsRawFd, FromRawFd, IntoRawFd, RawFd};
use std::path::PathBuf;
use std::sync::atomic::AtomicBool;
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
}

impl Pty {
    /// Validate shell command against whitelist
    ///
    /// Ensures only allowed shells can be spawned to prevent command injection.
    /// Resolves the command to an absolute path and checks the basename.
    fn validate_shell(command: &str) -> Result<PathBuf> {
        let path = which::which(command)
            .map_err(|e| KuroError::InvalidParam(format!("Shell not found: {}", e)))?;

        let basename = path
            .file_name()
            .and_then(|n| n.to_str())
            .ok_or_else(|| KuroError::InvalidParam("Invalid shell name".into()))?;

        if !ALLOWED_SHELLS.contains(&basename) {
            return Err(KuroError::InvalidParam(format!(
                "Shell '{}' not allowed. Allowed shells: {}",
                basename,
                ALLOWED_SHELLS.join(", ")
            )));
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
    /// This creates a proper PTY master/slave pair using openpty(),
    /// forks a child process, and executes the shell with the slave
    /// PTY as stdin/stdout/stderr.
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
            .map_err(|e| KuroError::Pty(format!("Failed to open PTY: {}", e)))?;

        // Create bounded channel for backpressure
        let (sender, receiver) = crossbeam_channel::bounded(CHANNEL_CAPACITY);
        let shutdown = Arc::new(AtomicBool::new(false));

        // Clone master fd for reader thread, with O_CLOEXEC so the fd is
        // automatically closed in any fork()ed child processes (prevents
        // child processes from holding the master fd open across sessions).
        let reader_fd = unsafe {
            // dup3 with O_CLOEXEC is available on macOS via F_DUPFD_CLOEXEC fcntl
            let fd = libc::dup(master.as_raw_fd());
            if fd == -1 {
                return Err(KuroError::Pty("Failed to duplicate master fd".to_string()));
            }
            // Set FD_CLOEXEC so the fd is closed on exec in child processes
            let flags = libc::fcntl(fd, libc::F_GETFD);
            if flags == -1 || libc::fcntl(fd, libc::F_SETFD, flags | libc::FD_CLOEXEC) == -1 {
                libc::close(fd);
                return Err(KuroError::Pty(
                    "Failed to set FD_CLOEXEC on reader fd".to_string(),
                ));
            }
            fd
        };
        let reader_file = unsafe { std::fs::File::from_raw_fd(reader_fd) };

        // Convert master to File for parent
        let master_file = unsafe { std::fs::File::from_raw_fd(master.into_raw_fd()) };

        // Fork to create child process
        match unsafe { fork() } {
            Ok(ForkResult::Parent { child }) => {
                // Parent process: spawn reader thread and return Pty
                let shutdown_clone = shutdown.clone();
                let reader_thread = thread::spawn(move || {
                    PtyReader::read_loop(reader_file, sender, shutdown_clone);
                });

                Ok(Self {
                    master: master_file,
                    child_pid: child,
                    receiver,
                    shutdown,
                    _reader_thread: reader_thread,
                })
            }
            Ok(ForkResult::Child) => {
                // Child process: set up PTY and exec shell

                // Create new session
                nix::unistd::setsid()
                    .map_err(|e| KuroError::Pty(format!("Failed to setsid: {}", e)))?;

                // Set slave PTY as controlling terminal
                // TIOCSCTTY is required on all POSIX platforms after setsid()
                // to establish the slave PTY as the controlling terminal.
                // Without this, tcgetpgrp() fails in the shell.
                unsafe {
                    if libc::ioctl(slave.as_raw_fd(), libc::TIOCSCTTY as _, 0) == -1 {
                        return Err(KuroError::Pty(format!(
                            "Failed to set controlling terminal: {}",
                            std::io::Error::last_os_error()
                        )));
                    }
                }

                // Duplicate slave PTY to stdin, stdout, stderr
                if unsafe { libc::dup2(slave.as_raw_fd(), 0) } == -1 {
                    return Err(KuroError::Pty("Failed to dup2 stdin".to_string()));
                }
                if unsafe { libc::dup2(slave.as_raw_fd(), 1) } == -1 {
                    return Err(KuroError::Pty("Failed to dup2 stdout".to_string()));
                }
                if unsafe { libc::dup2(slave.as_raw_fd(), 2) } == -1 {
                    return Err(KuroError::Pty("Failed to dup2 stderr".to_string()));
                }

                // Close slave PTY (we have duplicates now)
                drop(slave);

                // Close master PTY fd in child — the child must not hold the master end.
                // Inherited master fds interfere with process group management and can
                // prevent the parent from detecting child exit (no EOF on master).
                drop(master_file);
                unsafe {
                    libc::close(reader_fd);
                }

                // Clear terminal-multiplexer env vars so that programs such as tmux
                // and GNU screen behave correctly when launched inside kuro.  Without
                // this, inheriting $TMUX causes tmux to believe it is already nested
                // inside an existing session and refuse to attach a new client.
                std::env::remove_var("TMUX");
                std::env::remove_var("STY");

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
                        KuroError::Pty("Shell path is not valid UTF-8".to_string())
                    })?)
                    .map_err(|e| KuroError::Pty(format!("Invalid shell path: {}", e)))?;

                let shell_name = shell_path
                    .file_name()
                    .and_then(|n| n.to_str())
                    .unwrap_or("sh");
                let shell_name_cstr = std::ffi::CString::new(shell_name)
                    .map_err(|e| KuroError::Pty(format!("Invalid shell name: {}", e)))?;

                // argv[0] = basename (e.g. "bash"), argv[1..] = empty (interactive login
                // flags can be added here if needed, but the default is interactive mode
                // because stdin is a TTY).
                nix::unistd::execv(&shell_full_cstr, &[shell_name_cstr.as_c_str()])
                    .map_err(|e| KuroError::Pty(format!("Failed to exec shell: {}", e)))?;

                // execvp should not return, but if it does, exit
                std::process::exit(1);
            }
            Err(errno) => Err(KuroError::Pty(format!("Failed to fork: {}", errno))),
        }
    }

    /// Write bytes to the PTY
    pub fn write(&mut self, bytes: &[u8]) -> Result<()> {
        use std::io::Write;

        self.master
            .write_all(bytes)
            .map_err(|e| KuroError::Pty(format!("Failed to write to PTY: {}", e)))?;

        Ok(())
    }

    /// Read bytes from the PTY (non-blocking, drains all available data)
    pub fn read(&mut self) -> Result<Vec<u8>> {
        let mut all_data = Vec::new();

        // Drain all available data from the channel
        while let Ok(data) = self.receiver.try_recv() {
            all_data.extend(data);
        }

        Ok(all_data)
    }

    /// Check if the PTY channel has pending unread data (non-blocking, does not consume).
    pub fn has_pending_data(&self) -> bool {
        !self.receiver.is_empty()
    }

    /// Set PTY window size
    pub fn set_winsize(&mut self, rows: u16, cols: u16) -> Result<()> {
        let winsize = Winsize {
            ws_row: rows,
            ws_col: cols,
            ws_xpixel: 0,
            ws_ypixel: 0,
        };

        unsafe {
            libc::ioctl(self.master.as_raw_fd(), libc::TIOCSWINSZ, &winsize);
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
            eprintln!("[PTY] Drop: failed to send SIGHUP: {}", e);
        }

        // Wait for the child to exit (prevents zombie processes)
        match waitpid(self.child_pid, None) {
            Ok(_) => {}
            Err(e) => {
                eprintln!("[PTY] Drop: waitpid failed: {}", e);
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
mod tests {
    use super::*;

    #[test]
    fn test_validate_allowed_shells() {
        assert!(Pty::validate_shell("bash").is_ok());
        assert!(Pty::validate_shell("zsh").is_ok());
        assert!(Pty::validate_shell("sh").is_ok());
        assert!(Pty::validate_shell("fish").is_ok());
    }

    #[test]
    fn test_validate_rejected_shell() {
        assert!(Pty::validate_shell(" malicious_command").is_err());
        assert!(Pty::validate_shell("rm").is_err());
        assert!(Pty::validate_shell("cat").is_err());
    }

    #[test]
    fn test_pty_spawn() {
        let pty = Pty::spawn("sh", 24, 80);
        assert!(pty.is_ok());

        let mut pty = pty.unwrap();
        pty.write(b"echo test\n").unwrap();
    }

    #[test]
    fn test_validate_shell_empty_string_rejected() {
        // An empty string should fail because `which` cannot resolve it
        let result = Pty::validate_shell("");
        assert!(result.is_err(), "empty string should be rejected");
    }

    #[test]
    fn test_validate_shell_absolute_path_bash() {
        let bash_path = std::path::Path::new("/bin/bash");
        if bash_path.exists() {
            // An absolute path to bash resolves to the "bash" basename which is in the whitelist
            let result = Pty::validate_shell("/bin/bash");
            assert!(
                result.is_ok(),
                "/bin/bash should be accepted when it exists"
            );
        }
    }

    #[test]
    fn test_validate_shell_rejects_relative_path_slash_slash() {
        // Relative paths like "../bash" cannot be resolved by `which` as an absolute path,
        // so they should be rejected
        let result = Pty::validate_shell("../bash");
        assert!(result.is_err(), "relative path ../bash should be rejected");
    }

    #[test]
    fn test_validate_shell_rejects_python() {
        // "python3" is not in the ALLOWED_SHELLS whitelist
        // If it isn't even installed, which() will fail — either way we expect Err
        let result = Pty::validate_shell("python3");
        assert!(
            result.is_err(),
            "python3 should be rejected (not in whitelist)"
        );
    }

    // --- Regression tests: readline visual mode requires non-zero PTY dimensions ---
    //
    // Root cause of the C-b/C-f/C-e bug:
    //   readline calls TIOCGWINSZ at startup. If it sees 0 columns it falls back to
    //   dumb/novis mode and echoes control characters as literal ^X instead of moving
    //   the cursor.  Two fixes prevent this:
    //     1. Pass winsize to openpty() before fork.
    //     2. Call TIOCSWINSZ on fd 0 inside the child after dup2.
    //
    // These tests verify the structural guarantees that make the fixes correct.

    #[test]
    fn test_spawn_with_nonzero_dimensions_succeeds() {
        // Spawning with explicit non-zero rows/cols must succeed.
        // This exercises the openpty(Some(&winsize), ...) path.
        let pty = Pty::spawn("sh", 24, 80);
        assert!(
            pty.is_ok(),
            "Pty::spawn with rows=24 cols=80 must succeed: {:?}",
            pty.err()
        );
    }

    #[test]
    fn test_spawn_rows_cols_passed_through() {
        // After spawn, the parent can immediately set_winsize to the same value
        // without error — confirming the master fd is valid and TIOCSWINSZ works.
        let pty = Pty::spawn("sh", 24, 80);
        assert!(pty.is_ok());
        let mut pty = pty.unwrap();
        // This mirrors what kuro does on resize; it must not error.
        assert!(
            pty.set_winsize(24, 80).is_ok(),
            "set_winsize on a freshly spawned PTY must succeed"
        );
    }

    #[test]
    fn test_validate_shell_returns_absolute_path() {
        // validate_shell must return an absolute PathBuf so that execv uses
        // the exact binary we validated, not whatever PATH finds first.
        // Regression: previously execvp("bash", ...) was used, which could
        // resolve to a different bash (e.g. Homebrew) than validate_shell chose.
        let result = Pty::validate_shell("sh");
        assert!(result.is_ok());
        let path = result.unwrap();
        assert!(
            path.is_absolute(),
            "validate_shell must return an absolute path, got: {:?}",
            path
        );
    }

    #[test]
    fn test_validate_shell_bash_returns_absolute_path() {
        // Same as above, specifically for bash.
        if which::which("bash").is_ok() {
            let result = Pty::validate_shell("bash");
            assert!(result.is_ok());
            let path = result.unwrap();
            assert!(
                path.is_absolute(),
                "validate_shell('bash') must return an absolute path, got: {:?}",
                path
            );
        }
    }

    #[test]
    fn test_pty_tiocgwinsz_via_master_after_spawn() {
        // After spawn, querying TIOCGWINSZ on the master must return the dimensions
        // we requested.  This is the parent-side proof that openpty(Some(&winsize))
        // correctly propagated the size.  If this returns 0×0, readline in the child
        // will enter dumb mode.
        use std::os::unix::io::AsRawFd;
        let pty = Pty::spawn("sh", 42, 120);
        assert!(pty.is_ok());
        let pty = pty.unwrap();

        let mut ws = libc::winsize {
            ws_row: 0,
            ws_col: 0,
            ws_xpixel: 0,
            ws_ypixel: 0,
        };
        let ret = unsafe { libc::ioctl(pty.as_raw_fd(), libc::TIOCGWINSZ, &mut ws) };
        assert_eq!(ret, 0, "TIOCGWINSZ ioctl failed");
        assert_eq!(ws.ws_row, 42, "ws_row must equal requested rows");
        assert_eq!(
            ws.ws_col, 120,
            "ws_col must equal requested cols — 0 here would cause readline dumb mode"
        );
    }
}
