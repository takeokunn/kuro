//! Child-process helpers: environment setup and shell exec after `fork()`.
//!
//! All functions here run in the child process after `fork()` and have no
//! observable effect on the parent process.  Only `exec_in_child` is
//! `pub(super)` — the remaining helpers are fully private to this module.

use super::shell::{shell_name_to_cstring, shell_path_to_cstring};
use crate::ffi::error::{pty_operation_error, pty_spawn_error};
use crate::Result;
use std::fs::File;
use std::os::fd::OwnedFd;
#[cfg(unix)]
use std::os::unix::fs::PermissionsExt as _;
use std::os::unix::io::{AsRawFd as _, RawFd};
use std::path::{Path, PathBuf};

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
pub(crate) fn setup_child_env(rows: u16, cols: u16, shell_path: &Path) {
    // Remove terminal-multiplexer variables so tmux/screen behave correctly inside kuro.
    std::env::remove_var("TMUX");
    std::env::remove_var("STY");
    // Remove INSIDE_EMACS: setting it to "kuro,comint" triggers bash readline's
    // Emacs-comint mode on macOS bash 3.2, which suppresses prompt output and
    // causes shell-ready detection to time out.  Shell integration scripts that
    // need this variable should set it themselves via KURO_SHELL_INTEGRATION_DIR.
    std::env::remove_var("INSIDE_EMACS");
    std::env::remove_var("EMACS_SOCKET_NAME");
    // Advertise the kuro environment to programs that wish to detect it.
    std::env::set_var("KURO_TERMINAL", "1");
    // Suppress the macOS bash 3.2 deprecation warning ("Please switch to zsh").
    // Without this, bash writes the warning to stderr before the prompt, which
    // can cause shell-ready detection to race against the multi-stage startup output.
    std::env::set_var("BASH_SILENCE_DEPRECATION_WARNING", "1");
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

/// Create an owner-only temporary directory with a unique name.
#[inline]
fn create_secure_temp_dir(prefix: &str) -> Option<PathBuf> {
    let unique = format!(
        "{prefix}-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_nanos())
    );
    let tmp = std::env::temp_dir().join(unique);
    if std::fs::create_dir_all(&tmp).is_err() {
        return None;
    }
    // Restrict directory to owner-only access.
    let _ = std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o700));
    Some(tmp)
}

/// Create a temporary rcfile under a secure temp dir and write shell integration content into it.
#[inline]
fn write_temp_shell_rcfile(prefix: &str, filename: &str, content: String) -> Option<PathBuf> {
    let tmp = create_secure_temp_dir(prefix)?;
    let rcfile_path = tmp.join(filename);
    if std::fs::write(&rcfile_path, content).is_ok() {
        Some(rcfile_path)
    } else {
        None
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
    let bashrc_content = format!(
        "[ -f \"{home}/.bashrc\" ] && source \"{home}/.bashrc\"\n\
         source \"{}\"\n",
        script.display()
    );
    if let Some(bashrc_path) =
        write_temp_shell_rcfile("kuro-bash", ".bashrc", bashrc_content)
    {
        // Signal exec_in_child to pass --rcfile instead of overriding HOME.
        std::env::set_var("KURO_BASH_RCFILE", bashrc_path);
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

    let zshrc_content = format!(
        "[ -f \"{original_zdotdir}/.zshrc\" ] && ZDOTDIR=\"{original_zdotdir}\" source \"{original_zdotdir}/.zshrc\"\n\
         source \"{}\"\n",
        script.display()
    );
    if let Some(zshrc_path) = write_temp_shell_rcfile("kuro-zsh", ".zshrc", zshrc_content) {
        let zshdir = zshrc_path
            .parent()
            .map(Path::to_path_buf)
            .unwrap_or_default();
        std::env::set_var("ZDOTDIR", &zshdir);
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

/// Shell invocation state built from the validated shell path and args.
struct ShellExecContext {
    shell_full_cstr: std::ffi::CString,
    shell_name_cstr: std::ffi::CString,
    shell_arg_cstrings: Vec<std::ffi::CString>,
    rcfile_flag: Option<std::ffi::CString>,
    rcfile_path_cstr: Option<std::ffi::CString>,
}

impl ShellExecContext {
    fn argv(&self) -> Vec<&std::ffi::CStr> {
        let mut argv = vec![self.shell_name_cstr.as_c_str()];
        for cstr in &self.shell_arg_cstrings {
            argv.push(cstr.as_c_str());
        }
        if let (Some(flag), Some(path)) = (&self.rcfile_flag, &self.rcfile_path_cstr) {
            argv.push(flag.as_c_str());
            argv.push(path.as_c_str());
        }
        argv
    }
}

/// Put the PTY slave in control of the child session.
#[inline]
fn set_controlling_terminal(slave_fd: RawFd) -> Result<()> {
    nix::unistd::setsid()
        .map_err(|e| pty_operation_error("setsid", &format!("Failed to setsid: {e}")))?;

    // SAFETY: slave_fd is a valid PTY slave fd; TIOCSCTTY is async-signal-safe after setsid().
    #[allow(clippy::useless_conversion)]
    unsafe {
        if libc::ioctl(slave_fd, libc::TIOCSCTTY.into(), 0) == -1 {
            return Err(pty_operation_error(
                "TIOCSCTTY",
                &format!(
                    "Failed to set controlling terminal: {}",
                    std::io::Error::last_os_error()
                ),
            ));
        }
    }

    Ok(())
}

/// Redirect stdin/stdout/stderr to the PTY slave.
#[inline]
fn redirect_standard_streams(slave_fd: RawFd) -> Result<()> {
    // SAFETY: slave_fd is a valid open fd; dup2 to 0/1/2 is async-signal-safe.
    unsafe {
        if libc::dup2(slave_fd, 0) == -1 {
            return Err(pty_operation_error("dup2", "Failed to dup2 stdin"));
        }
        if libc::dup2(slave_fd, 1) == -1 {
            return Err(pty_operation_error("dup2", "Failed to dup2 stdout"));
        }
        if libc::dup2(slave_fd, 2) == -1 {
            return Err(pty_operation_error("dup2", "Failed to dup2 stderr"));
        }
    }
    Ok(())
}

/// Drop the PTY ends that the child no longer needs.
#[inline]
fn close_child_descriptors(master_file: std::fs::File, reader_fd: RawFd) {
    drop(master_file);
    // SAFETY: reader_fd is the child's copy of the master-reader dup; closing it
    // prevents the child from holding the master end open (which blocks parent EOF).
    unsafe {
        libc::close(reader_fd);
    }
}

/// Re-assert the PTY size after the stdio redirection has been installed.
#[inline]
fn set_child_winsize(rows: u16, cols: u16) {
    // SAFETY: fd 0 is the PTY slave after dup2; winsize is stack-allocated.
    unsafe {
        let ws = libc::winsize {
            ws_row: rows,
            ws_col: cols,
            ws_xpixel: 0,
            ws_ypixel: 0,
        };
        libc::ioctl(0, libc::TIOCSWINSZ, &ws);
    }
}

/// Child-process resources and arguments required to exec the validated shell.
pub(super) struct ChildExecContext<'a> {
    pub(super) slave: OwnedFd,
    pub(super) master_file: File,
    pub(super) reader_fd: RawFd,
    pub(super) shell_path: &'a Path,
    pub(super) rows: u16,
    pub(super) cols: u16,
    pub(super) command: &'a str,
    pub(super) shell_args: &'a [String],
}

/// Build the shell path, argv[0], and optional rcfile arguments.
fn build_shell_exec_context(
    shell_path: &Path,
    command: &str,
    shell_args: &[String],
) -> Result<ShellExecContext> {
    let shell_full_cstr = shell_path_to_cstring(shell_path, command)?;
    let shell_name_cstr = shell_name_to_cstring(shell_path, command)?;
    let shell_arg_cstrings: Vec<std::ffi::CString> = shell_args
        .iter()
        .map(|s| {
            std::ffi::CString::new(s.as_str())
                .map_err(|e| pty_spawn_error(command, &format!("Invalid shell arg: {e}")))
        })
        .collect::<Result<Vec<_>>>()?;

    let mut rcfile_flag = None;
    let mut rcfile_path_cstr = None;
    if let Ok(rcfile) = std::env::var("KURO_BASH_RCFILE") {
        std::env::remove_var("KURO_BASH_RCFILE");
        rcfile_flag = Some(std::ffi::CString::new("--rcfile").expect("static flag"));
        rcfile_path_cstr = Some(
            std::ffi::CString::new(rcfile)
                .map_err(|e| pty_spawn_error(command, &format!("Invalid rcfile path: {e}")))?,
        );
    }

    Ok(ShellExecContext {
        shell_full_cstr,
        shell_name_cstr,
        shell_arg_cstrings,
        rcfile_flag,
        rcfile_path_cstr,
    })
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
pub(super) fn exec_in_child(ctx: ChildExecContext<'_>) -> Result<()> {
    let ChildExecContext {
        slave,
        master_file,
        reader_fd,
        shell_path,
        rows,
        cols,
        command,
        shell_args,
    } = ctx;

    let slave_fd = slave.as_raw_fd();
    set_controlling_terminal(slave_fd)?;
    redirect_standard_streams(slave_fd)?;

    // Release the slave and master ends — stdin/stdout/stderr duplicates cover I/O.
    drop(slave);
    close_child_descriptors(master_file, reader_fd);

    // Configure the environment: strip multiplexer vars, set TERM/COLORTERM/KURO_TERMINAL,
    // propagate initial PTY dimensions, and inject shell integration scripts.
    setup_child_env(rows, cols, shell_path);

    // Re-assert window size on fd 0 inside the child.
    // Some readline builds call TIOCGWINSZ before the parent's SIGWINCH handler fires;
    // without this they see 0 columns and permanently enter dumb/novis mode.
    set_child_winsize(rows, cols);

    // Execute the shell via its absolute path so the exact validated binary is used
    // (not whatever $PATH resolves first).  argv[0] = basename keeps ps/top readable.
    let exec_ctx = build_shell_exec_context(shell_path, command, shell_args)?;
    let argv = exec_ctx.argv();

    nix::unistd::execv(&exec_ctx.shell_full_cstr, &argv)
        .map_err(|e| pty_spawn_error(command, &format!("Failed to exec shell: {e}")))?;

    // execv succeeded — process image was replaced; this line is unreachable.
    Ok(())
}
