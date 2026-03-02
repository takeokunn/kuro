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

    /// Spawn a new PTY with the given shell command
    ///
    /// This creates a proper PTY master/slave pair using openpty(),
    /// forks a child process, and executes the shell with the slave
    /// PTY as stdin/stdout/stderr.
    pub fn spawn(command: &str) -> Result<Self> {
        // Validate command against whitelist
        let shell_path = Self::validate_shell(command)?;

        // Open PTY master/slave pair
        let OpenptyResult { master, slave } = openpty(None, None)
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

                // Execute shell
                let shell_name = shell_path
                    .file_name()
                    .and_then(|n| n.to_str())
                    .unwrap_or("sh");

                let shell_cstr = std::ffi::CString::new(shell_name)
                    .map_err(|e| KuroError::Pty(format!("Invalid shell name: {}", e)))?;

                // execvp expects the program name and arguments as separate C strings
                // First argument is the program name (argv[0])
                nix::unistd::execvp(&shell_cstr, &[shell_cstr.as_c_str()])
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
        let pty = Pty::spawn("sh");
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
            assert!(result.is_ok(), "/bin/bash should be accepted when it exists");
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
        assert!(result.is_err(), "python3 should be rejected (not in whitelist)");
    }
}
