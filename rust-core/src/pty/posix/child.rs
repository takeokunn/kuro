//! Child-process helpers: environment setup and shell exec after `fork()`.
//!
//! All functions here run in the child process after `fork()` and have no
//! observable effect on the parent process.  Only `exec_in_child` is
//! `pub(super)` — the remaining helpers are fully private to this module.

use crate::ffi::error::{pty_operation_error, pty_spawn_error};
use crate::Result;
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
#[expect(
    clippy::too_many_arguments,
    reason = "all 8 parameters are required: this function bridges fork-child setup with PTY I/O redirection, env init, and shell exec in a single pass"
)]
pub(super) fn exec_in_child(
    slave: std::os::fd::OwnedFd,
    master_file: std::fs::File,
    reader_fd: RawFd,
    shell_path: &std::path::Path,
    rows: u16,
    cols: u16,
    command: &str,
    shell_args: &[String],
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

    // Convert caller-supplied shell_args to CStrings and append them before the rcfile flag.
    // These args come from the Elisp call site (e.g. `--norc --noprofile` for test stability).
    let shell_arg_cstrings: Vec<std::ffi::CString> = shell_args
        .iter()
        .map(|s| {
            std::ffi::CString::new(s.as_str())
                .map_err(|e| pty_spawn_error(command, &format!("Invalid shell arg: {e}")))
        })
        .collect::<Result<Vec<_>>>()?;
    for cstr in &shell_arg_cstrings {
        argv.push(cstr.as_c_str());
    }

    let rcfile_flag;
    let rcfile_path_cstr;
    if let Ok(rcfile) = std::env::var("KURO_BASH_RCFILE") {
        std::env::remove_var("KURO_BASH_RCFILE");
        rcfile_flag = std::ffi::CString::new("--rcfile").expect("static flag");
        rcfile_path_cstr = std::ffi::CString::new(rcfile)
            .map_err(|e| pty_spawn_error(command, &format!("Invalid rcfile path: {e}")))?;
        argv.push(rcfile_flag.as_c_str());
        argv.push(rcfile_path_cstr.as_c_str());
    }

    nix::unistd::execv(&shell_full_cstr, &argv)
        .map_err(|e| pty_spawn_error(command, &format!("Failed to exec shell: {e}")))?;

    // execv succeeded — process image was replaced; this line is unreachable.
    Ok(())
}
