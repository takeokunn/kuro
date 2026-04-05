//! POSIX PTY implementation using nix crate for safe fork/pty operations

use crate::{
    ffi::error::{invalid_parameter_error, pty_operation_error, pty_spawn_error},
    pty::reader::PtyReader,
    Result,
};
use nix::pty::{openpty, OpenptyResult, Winsize};
use nix::sys::wait::{waitpid, WaitPidFlag};
use nix::unistd::{fork, ForkResult, Pid};
#[cfg(unix)]
use std::os::unix::fs::PermissionsExt as _;
use std::os::unix::io::{AsRawFd, FromRawFd as _, IntoRawFd as _, RawFd};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;

/// Allowed shells whitelist for security
const ALLOWED_SHELLS: &[&str] = &["bash", "zsh", "sh", "fish"];

/// Channel capacity for PTY data - prevents unbounded memory growth
const CHANNEL_CAPACITY: usize = 100;

/// Maximum time (in milliseconds) to wait for a child process to exit after
/// SIGHUP before escalating to SIGKILL.  Each retry sleeps 10 ms, so this
/// value divided by 10 gives the number of poll iterations.
const DROP_WAITPID_TIMEOUT_MS: u64 = 500;

/// Sleep interval between non-blocking waitpid polls during Pty::drop.
const DROP_WAITPID_POLL_INTERVAL: std::time::Duration = std::time::Duration::from_millis(10);

/// Set child process environment variables for terminal operation.
///
/// Removes multiplexer variables that break nesting, sets TERM/COLORTERM for
/// colour-aware programs, and propagates the initial PTY dimensions so that
/// readline/ncurses reads correct values before any SIGWINCH fires.
///
/// # Safety
/// Must only be called in the child process after `fork()` and after `dup2`
/// has redirected stdin/stdout/stderr. `std::env::set_var` is not
/// async-signal-safe in general, but is safe here because no other threads
/// exist in the child process.
#[inline]
fn setup_child_env(rows: u16, cols: u16, shell_path: &Path) {
    // Remove terminal-multiplexer variables so tmux/screen behave correctly inside kuro.
    std::env::remove_var("TMUX");
    std::env::remove_var("STY");
    // Set INSIDE_EMACS so shell integration scripts and programs can detect kuro.
    std::env::set_var("INSIDE_EMACS", "kuro,comint");
    std::env::remove_var("EMACS_SOCKET_NAME");
    // Advertise the kuro environment to programs that wish to detect it.
    std::env::set_var("KURO_TERMINAL", "1");
    // Terminal capability declarations for readline / ncurses / color-aware programs.
    std::env::set_var("TERM", "xterm-256color");
    std::env::set_var("COLORTERM", "truecolor");
    // Belt-and-suspenders: some shells read COLUMNS/LINES before calling TIOCGWINSZ.
    std::env::set_var("COLUMNS", cols.to_string());
    std::env::set_var("LINES", rows.to_string());
    // Inject shell integration scripts when KURO_SHELL_INTEGRATION_DIR is set by Elisp.
    setup_shell_integration(shell_path);
}

/// Set shell-specific environment variables to auto-source kuro integration scripts.
///
/// Reads `KURO_SHELL_INTEGRATION_DIR` (set by `kuro-lifecycle.el` before spawn) and
/// configures the appropriate env var for the detected shell:
///   - bash: temporary bashrc that sources `~/.bashrc` then `kuro-shell.bash`
///   - zsh:  temporary `ZDOTDIR` that sources `~/.zshrc` then `kuro-shell.zsh`
///   - fish: `XDG_DATA_DIRS` prepended so fish autoloads `kuro-shell.fish`
///
/// Does nothing when `KURO_SHELL_INTEGRATION_DIR` is unset or the shell is unknown.
#[inline]
fn setup_shell_integration(shell_path: &Path) {
    let dir = match std::env::var("KURO_SHELL_INTEGRATION_DIR") {
        Ok(d) if !d.is_empty() => d,
        _ => return,
    };
    std::env::remove_var("KURO_SHELL_INTEGRATION_DIR");

    let basename = shell_path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("");

    match basename {
        "bash" => setup_bash_integration(&dir),
        "zsh" => setup_zsh_integration(&dir),
        "fish" => setup_fish_integration(&dir),
        _ => {}
    }
}

/// Create a temporary bashrc that sources `~/.bashrc` then kuro integration.
///
/// Uses `KURO_BASH_RCFILE` env var to pass the path to the temporary bashrc
/// to `exec_in_child`, which adds `--rcfile <path>` to the bash invocation.
/// This avoids overriding HOME (which breaks tilde expansion, cd, etc.).
#[inline]
fn setup_bash_integration(integration_dir: &str) {
    let script = PathBuf::from(integration_dir).join("kuro-shell.bash");
    if !script.exists() {
        return;
    }
    let home = std::env::var("HOME").unwrap_or_default();
    // Use pid + monotonic timestamp for unpredictable temp path.
    let unique = format!(
        "kuro-bash-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_nanos())
    );
    let tmp = std::env::temp_dir().join(unique);
    if std::fs::create_dir_all(&tmp).is_err() {
        return;
    }
    // Restrict directory to owner-only access.
    let _ = std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o700));
    let bashrc_content = format!(
        "[ -f \"{home}/.bashrc\" ] && source \"{home}/.bashrc\"\n\
         source \"{}\"\n",
        script.display()
    );
    let bashrc_path = tmp.join(".bashrc");
    if std::fs::write(&bashrc_path, &bashrc_content).is_ok() {
        // Signal exec_in_child to pass --rcfile instead of overriding HOME.
        std::env::set_var("KURO_BASH_RCFILE", &bashrc_path);
    }
}

/// Create a temporary ZDOTDIR that sources `~/.zshrc` then kuro integration.
#[inline]
fn setup_zsh_integration(integration_dir: &str) {
    let script = PathBuf::from(integration_dir).join("kuro-shell.zsh");
    if !script.exists() {
        return;
    }
    let original_zdotdir = std::env::var("ZDOTDIR")
        .ok()
        .or_else(|| std::env::var("HOME").ok())
        .unwrap_or_default();

    let unique = format!(
        "kuro-zsh-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_nanos())
    );
    let tmp = std::env::temp_dir().join(unique);
    if std::fs::create_dir_all(&tmp).is_err() {
        return;
    }
    // Restrict directory to owner-only access.
    let _ = std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o700));
    let zshrc_content = format!(
        "[ -f \"{original_zdotdir}/.zshrc\" ] && ZDOTDIR=\"{original_zdotdir}\" source \"{original_zdotdir}/.zshrc\"\n\
         source \"{}\"\n",
        script.display()
    );
    let zshrc_path = tmp.join(".zshrc");
    if std::fs::write(&zshrc_path, zshrc_content).is_ok() {
        std::env::set_var("ZDOTDIR", &tmp);
        std::env::set_var("KURO_ORIGINAL_ZDOTDIR", original_zdotdir);
    }
}

/// Prepend the integration directory to `XDG_DATA_DIRS` for fish autoloading.
#[inline]
fn setup_fish_integration(integration_dir: &str) {
    let script = PathBuf::from(integration_dir).join("kuro-shell.fish");
    if !script.exists() {
        return;
    }
    let vendor_dir = PathBuf::from(integration_dir)
        .join("fish")
        .join("vendor_conf.d");
    if !vendor_dir.exists() {
        return;
    }
    let existing = std::env::var("XDG_DATA_DIRS").unwrap_or_default();
    let new_val = if existing.is_empty() {
        integration_dir.to_owned()
    } else {
        format!("{integration_dir}:{existing}")
    };
    std::env::set_var("XDG_DATA_DIRS", new_val);
}

/// Configure a forked child process: establish a PTY session, redirect I/O,
/// sanitize the environment, and exec the shell.
///
/// This function runs entirely in the child process after `fork()`.  If it
/// returns `Err`, the child propagates the error (the parent is a separate
/// process and is unaffected).  On success, `execv` replaces the child image
/// with the shell binary and this function never returns normally.
///
/// # Safety
/// Must only be called in the child process after `fork()`.
/// All unsafe blocks inside perform only async-signal-safe operations until `execv`.
fn exec_in_child(
    slave: std::os::fd::OwnedFd,
    master_file: std::fs::File,
    reader_fd: RawFd,
    shell_path: &std::path::Path,
    rows: u16,
    cols: u16,
    command: &str,
) -> Result<()> {
    // Establish a new session so the shell becomes the session leader.
    nix::unistd::setsid()
        .map_err(|e| pty_operation_error("setsid", &format!("Failed to setsid: {e}")))?;

    // Set the slave PTY as the controlling terminal.
    // TIOCSCTTY is required after setsid(); without it tcgetpgrp() fails in the shell.
    // SAFETY: slave is a valid PTY slave fd; TIOCSCTTY is async-signal-safe after setsid().
    // TIOCSCTTY is u32 on macOS, u64 on Linux — .into() bridges the difference.
    // TIOCSCTTY is u32 on macOS (making .into() a no-op) but u64 on Linux
    // (where .into() is required).  Use #[allow] rather than #[expect] so
    // that the annotation does not fail on the platform where the conversion
    // is already the correct type.
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

    // Redirect stdin/stdout/stderr to the slave PTY.
    // SAFETY: slave.as_raw_fd() is a valid open fd; dup2 to 0/1/2 is async-signal-safe.
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

    // Release the slave and master ends — stdin/stdout/stderr duplicates cover I/O.
    drop(slave);
    drop(master_file);
    // SAFETY: reader_fd is the child's copy of the master-reader dup; closing it
    // prevents the child from holding the master end open (which blocks parent EOF).
    unsafe {
        libc::close(reader_fd);
    }

    // Configure the environment: strip multiplexer vars, set TERM/COLORTERM/KURO_TERMINAL,
    // propagate initial PTY dimensions, and inject shell integration scripts.
    setup_child_env(rows, cols, shell_path);

    // Re-assert window size on fd 0 inside the child.
    // Some readline builds call TIOCGWINSZ before the parent's SIGWINCH handler fires;
    // without this they see 0 columns and permanently enter dumb/novis mode.
    // SAFETY: fd 0 is the PTY slave we dup2'd above; winsize is stack-allocated.
    unsafe {
        let ws = libc::winsize {
            ws_row: rows,
            ws_col: cols,
            ws_xpixel: 0,
            ws_ypixel: 0,
        };
        libc::ioctl(0, libc::TIOCSWINSZ, &ws);
    }

    // Execute the shell via its absolute path so the exact validated binary is used
    // (not whatever $PATH resolves first).  argv[0] = basename keeps ps/top readable.
    let shell_full_cstr = std::ffi::CString::new(
        shell_path
            .to_str()
            .ok_or_else(|| pty_spawn_error(command, "Shell path is not valid UTF-8"))?,
    )
    .map_err(|e| pty_spawn_error(command, &format!("Invalid shell path: {e}")))?;

    let shell_name = shell_path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("sh");
    let shell_name_cstr = std::ffi::CString::new(shell_name)
        .map_err(|e| pty_spawn_error(command, &format!("Invalid shell name: {e}")))?;

    // For bash: use --rcfile to load the integration script without overriding HOME.
    // KURO_BASH_RCFILE is set by setup_bash_integration and consumed here.
    let mut argv: Vec<&std::ffi::CStr> = vec![shell_name_cstr.as_c_str()];
    let rcfile_flag;
    let rcfile_path_cstr;
    if let Ok(rcfile) = std::env::var("KURO_BASH_RCFILE") {
        std::env::remove_var("KURO_BASH_RCFILE");
        rcfile_flag = std::ffi::CString::new("--rcfile").expect("static flag");
        rcfile_path_cstr =
            std::ffi::CString::new(rcfile).map_err(|e| {
                pty_spawn_error(command, &format!("Invalid rcfile path: {e}"))
            })?;
        argv.push(rcfile_flag.as_c_str());
        argv.push(rcfile_path_cstr.as_c_str());
    }

    nix::unistd::execv(&shell_full_cstr, &argv)
        .map_err(|e| pty_spawn_error(command, &format!("Failed to exec shell: {e}")))?;

    // execv succeeded — process image was replaced; this line is unreachable.
    Ok(())
}

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
    fn find_in_path(command: &str) -> Option<PathBuf> {
        if command.is_empty() {
            return None;
        }
        let path_var = std::env::var("PATH").unwrap_or_default();
        for dir in path_var.split(':') {
            if dir.is_empty() {
                continue;
            }
            let candidate = PathBuf::from(dir).join(command);
            if candidate.is_file() {
                return Some(candidate);
            }
        }
        None
    }

    /// Validate shell command against whitelist
    ///
    /// Ensures only allowed shells can be spawned to prevent command injection.
    /// Resolves the command to an absolute path and checks the basename.
    ///
    /// For absolute paths (e.g. NixOS Nix store paths like `/nix/store/…/bin/fish`),
    /// validates existence and executability directly without a PATH lookup.
    /// For short names, resolves via `which` as before.
    fn validate_shell(command: &str) -> Result<PathBuf> {
        let path = if Path::new(command).is_absolute() {
            // Absolute path: validate directly without PATH lookup.
            // This handles NixOS Nix store paths where the Rust process inherits
            // Emacs's restricted PATH and `which::which` cannot locate the binary.
            //
            // Single `metadata()` call — existence is inferred from `Err`, avoiding
            // a separate `Path::exists()` call (one `stat(2)` instead of two).
            let p = PathBuf::from(command);
            let meta = std::fs::metadata(&p).map_err(|_| {
                invalid_parameter_error("command", "Shell path does not exist or is inaccessible")
            })?;
            // Check any execute bit (owner, group, or world).
            // Note: raw mode bits may differ from effective kernel access for non-owner
            // users. The kernel provides final enforcement at `execv(2)` time (EACCES).
            // Nix store paths are world-executable, making this reliable in practice.
            //
            // Symlink note: `metadata()` follows symlinks (uses `stat`, not `lstat`),
            // so this check operates on the final target's permissions. The returned
            // `PathBuf` is still the original input (symlink or real path), which is
            // correct — `execv(2)` resolves symlinks itself at execution time.
            if meta.permissions().mode() & 0o111 == 0 {
                return Err(invalid_parameter_error(
                    "command",
                    "Shell is not executable",
                ));
            }
            p
        } else {
            Self::find_in_path(command).ok_or_else(|| {
                invalid_parameter_error("command", &format!("Shell not found in PATH: {command}"))
            })?
        };

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
        let (sender, receiver) = std::sync::mpsc::sync_channel(CHANNEL_CAPACITY);
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
                    peek_buffer: std::sync::Mutex::new(None),
                    shutdown,
                    _reader_thread: reader_thread,
                    process_exited,
                })
            }
            Ok(ForkResult::Child) => {
                // Child process: delegate all setup to the helper.
                // If the helper returns Err, the error propagates out of spawn() in the
                // child process (the parent is in a separate address space and unaffected).
                exec_in_child(
                    slave,
                    master_file,
                    reader_fd,
                    &shell_path,
                    rows,
                    cols,
                    command,
                )?;
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
    /// Strategy: SIGHUP → poll with WNOHANG (up to 500 ms) → SIGKILL → final reap.
    /// This prevents the blocking waitpid that previously caused `cargo test` hangs
    /// when a shell child did not exit promptly after SIGHUP.
    ///
    /// The reader thread will detect EOF on the master fd (closed by the
    /// compiler-generated File drop after this function returns) and exit on its own.
    fn drop(&mut self) {
        // Signal the reader thread to stop after its current read returns.
        self.shutdown
            .store(true, std::sync::atomic::Ordering::Relaxed);

        // Send SIGHUP to the child process so it exits gracefully.
        if let Err(e) = nix::sys::signal::kill(self.child_pid, nix::sys::signal::Signal::SIGHUP) {
            // ESRCH = process already exited — not an error worth logging.
            if e != nix::errno::Errno::ESRCH {
                eprintln!("[PTY] Drop: failed to send SIGHUP: {e}");
            }
            // If the process already exited, still reap to prevent zombie.
        }

        // Poll with WNOHANG: give the child up to DROP_WAITPID_TIMEOUT_MS to exit.
        let max_retries = DROP_WAITPID_TIMEOUT_MS / DROP_WAITPID_POLL_INTERVAL.as_millis() as u64;
        let mut reaped = false;
        for _ in 0..max_retries {
            match waitpid(self.child_pid, Some(WaitPidFlag::WNOHANG)) {
                Ok(nix::sys::wait::WaitStatus::StillAlive) => {
                    // Child still running — sleep briefly and retry.
                    std::thread::sleep(DROP_WAITPID_POLL_INTERVAL);
                }
                Ok(_) => {
                    // Child exited (any terminal status) — successfully reaped.
                    reaped = true;
                    break;
                }
                Err(nix::errno::Errno::ECHILD) => {
                    // No such child — already reaped by someone else.
                    reaped = true;
                    break;
                }
                Err(e) => {
                    eprintln!("[PTY] Drop: waitpid(WNOHANG) failed: {e}");
                    reaped = true; // Give up to avoid infinite loop.
                    break;
                }
            }
        }

        if !reaped {
            // Escalate to SIGKILL: the child did not exit after SIGHUP + timeout.
            let _ = nix::sys::signal::kill(self.child_pid, nix::sys::signal::Signal::SIGKILL);
            // Final blocking reap — SIGKILL is unconditional, so this returns quickly.
            match waitpid(self.child_pid, None) {
                Ok(_) | Err(nix::errno::Errno::ECHILD) => {}
                Err(e) => {
                    eprintln!("[PTY] Drop: final waitpid after SIGKILL failed: {e}");
                }
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
