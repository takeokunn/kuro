//! Child-process helpers for POSIX PTY spawn.
//!
//! Environment, argv, and shell-integration files are prepared in the parent
//! before `fork()`. The child path only performs fd/session syscalls and
//! `execve(2)`, then terminates with `_exit(2)` on failure.

use super::shell::{shell_name_to_cstring, shell_path_to_cstring};
use crate::ffi::error::pty_spawn_error;
use crate::Result;
use std::ffi::{CString, OsStr};
use std::fs::{DirBuilder, File, OpenOptions};
use std::io::{Read as _, Write as _};
use std::os::fd::OwnedFd;
use std::os::raw::c_char;
use std::os::unix::ffi::OsStrExt as _;
use std::os::unix::fs::{DirBuilderExt as _, OpenOptionsExt as _};
use std::os::unix::io::{AsRawFd as _, RawFd};
use std::path::{Path, PathBuf};

const SECURE_TEMP_DIR_ATTEMPTS: usize = 64;
const CHILD_EXIT_SETUP_FAILED: i32 = 126;
const CHILD_EXIT_EXEC_FAILED: i32 = 127;
const CHILD_ENV_RESERVED_KEYS: &[&[u8]] = &[
    b"TMUX",
    b"STY",
    b"INSIDE_EMACS",
    b"EMACS_SOCKET_NAME",
    b"KURO_BASH_RCFILE",
    b"KURO_SHELL_INTEGRATION_DIR",
    b"KURO_TERMINAL",
    b"BASH_SILENCE_DEPRECATION_WARNING",
    b"TERM",
    b"COLORTERM",
    b"COLUMNS",
    b"LINES",
];

#[derive(Default)]
pub(crate) enum ShellIntegrationConfig {
    #[default]
    None,
    Bash {
        rcfile: PathBuf,
    },
}

struct ChildEnvBuilder {
    entries: Vec<(Vec<u8>, Vec<u8>)>,
}

impl ChildEnvBuilder {
    fn from_parent() -> Self {
        let entries = std::env::vars_os()
            .filter_map(|(key, value)| {
                let key_bytes = key.as_os_str().as_bytes();
                if !is_valid_env_key(key_bytes) || is_child_env_reserved_key(key_bytes) {
                    return None;
                }
                Some((key_bytes.to_vec(), value.as_os_str().as_bytes().to_vec()))
            })
            .collect();

        Self { entries }
    }

    fn set_bytes(&mut self, key: &[u8], value: Vec<u8>) {
        self.remove(key);
        self.entries.push((key.to_vec(), value));
    }

    fn set_str(&mut self, key: &[u8], value: &str) {
        self.set_bytes(key, value.as_bytes().to_vec());
    }

    fn set_os(&mut self, key: &[u8], value: &OsStr) {
        self.set_bytes(key, value.as_bytes().to_vec());
    }

    fn remove(&mut self, key: &[u8]) {
        self.entries.retain(|(candidate, _)| candidate != key);
    }

    fn into_cstrings(self, command: &str) -> Result<Vec<CString>> {
        self.entries
            .into_iter()
            .map(|(key, value)| {
                let mut entry = Vec::with_capacity(key.len() + 1 + value.len());
                entry.extend_from_slice(&key);
                entry.push(b'=');
                entry.extend_from_slice(&value);
                CString::new(entry).map_err(|err| {
                    pty_spawn_error(command, &format!("Invalid child environment: {err}"))
                })
            })
            .collect()
    }
}

#[inline]
fn is_valid_env_key(key: &[u8]) -> bool {
    !key.is_empty() && !key.contains(&b'=') && !key.contains(&0)
}

#[inline]
fn is_child_env_reserved_key(key: &[u8]) -> bool {
    CHILD_ENV_RESERVED_KEYS.contains(&key)
}

fn build_child_env(
    rows: u16,
    cols: u16,
    shell_path: &Path,
    command: &str,
) -> Result<(PreparedCStringArray, ShellIntegrationConfig)> {
    let mut env = ChildEnvBuilder::from_parent();

    env.set_str(b"KURO_TERMINAL", "1");
    env.set_str(b"BASH_SILENCE_DEPRECATION_WARNING", "1");
    env.set_str(b"TERM", "xterm-256color");
    env.set_str(b"COLORTERM", "truecolor");
    env.set_str(b"COLUMNS", &cols.to_string());
    env.set_str(b"LINES", &rows.to_string());

    let integration = prepare_shell_integration(shell_path, &mut env);
    Ok((
        PreparedCStringArray::new(env.into_cstrings(command)?),
        integration,
    ))
}

#[cfg(test)]
pub(crate) fn build_child_env_strings_for_test(
    rows: u16,
    cols: u16,
    shell_path: &Path,
    command: &str,
) -> Result<Vec<String>> {
    let (env, _) = build_child_env(rows, cols, shell_path, command)?;
    Ok(env.to_strings())
}

/// Prepare shell-specific environment values to auto-source kuro integration scripts.
///
/// Reads `KURO_SHELL_INTEGRATION_DIR` (set by `kuro-lifecycle.el` before spawn) and
/// configures the appropriate env var for the detected shell:
///   - bash: temporary bashrc that sources `~/.bashrc` then `kuro-shell.bash`
///   - zsh:  temporary `ZDOTDIR` that sources `~/.zshrc` then `kuro-shell.zsh`
///   - fish: `XDG_DATA_DIRS` prepended so fish autoloads `kuro-shell.fish`
///
/// Does nothing when `KURO_SHELL_INTEGRATION_DIR` is unset or the shell is unknown.
#[inline]
fn prepare_shell_integration(
    shell_path: &Path,
    env: &mut ChildEnvBuilder,
) -> ShellIntegrationConfig {
    let dir = match std::env::var_os("KURO_SHELL_INTEGRATION_DIR") {
        Some(dir) if !dir.as_os_str().as_bytes().is_empty() => PathBuf::from(dir),
        _ => return ShellIntegrationConfig::default(),
    };

    let basename = shell_path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("");

    match basename {
        "bash" => setup_bash_integration(&dir)
            .map(|rcfile| ShellIntegrationConfig::Bash { rcfile })
            .unwrap_or_default(),
        "zsh" => {
            setup_zsh_integration(&dir, env);
            ShellIntegrationConfig::default()
        }
        "fish" => {
            setup_fish_integration(&dir, env);
            ShellIntegrationConfig::default()
        }
        _ => ShellIntegrationConfig::default(),
    }
}

/// Create an owner-only temporary directory with a unique name.
#[inline]
fn create_secure_temp_dir(prefix: &str) -> Option<PathBuf> {
    for _ in 0..SECURE_TEMP_DIR_ATTEMPTS {
        let suffix = random_temp_suffix()?;
        let tmp =
            std::env::temp_dir().join(format!("{prefix}-{}-{suffix:016x}", std::process::id()));
        let mut builder = DirBuilder::new();
        builder.mode(0o700);

        match builder.create(&tmp) {
            Ok(()) => return Some(tmp),
            Err(err) if err.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(_) => return None,
        }
    }
    None
}

#[inline]
fn random_temp_suffix() -> Option<u64> {
    let mut bytes = [0_u8; 8];
    File::open("/dev/urandom")
        .ok()?
        .read_exact(&mut bytes)
        .ok()?;
    Some(u64::from_ne_bytes(bytes))
}

/// Create a temporary rcfile under a secure temp dir and write shell integration content into it.
#[inline]
fn write_temp_shell_rcfile(prefix: &str, filename: &str, content: String) -> Option<PathBuf> {
    let tmp = create_secure_temp_dir(prefix)?;
    let rcfile_path = tmp.join(filename);
    let mut file = match OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&rcfile_path)
    {
        Ok(file) => file,
        Err(_) => {
            let _ = std::fs::remove_dir(&tmp);
            return None;
        }
    };

    if file.write_all(content.as_bytes()).is_err() {
        let _ = std::fs::remove_file(&rcfile_path);
        let _ = std::fs::remove_dir(&tmp);
        return None;
    }

    Some(rcfile_path)
}

fn shell_quote(text: &str) -> String {
    if text.is_empty() {
        "''".to_owned()
    } else {
        format!("'{}'", text.replace('\'', "'\\''"))
    }
}

fn shell_quote_path(path: &Path) -> String {
    shell_quote(&path.display().to_string())
}

fn build_bash_rcfile_content(home: Option<&Path>, script: &Path) -> String {
    let mut content = String::new();
    if let Some(home) = home {
        let bashrc = shell_quote_path(&home.join(".bashrc"));
        content.push_str(&format!("[ -f {bashrc} ] && source {bashrc}\n"));
    }
    content.push_str(&format!("source {}\n", shell_quote_path(script)));
    content
}

fn build_zsh_rcfile_content(original_zdotdir: Option<&Path>, script: &Path) -> String {
    let mut content = String::new();
    if let Some(original_zdotdir) = original_zdotdir {
        let zshrc = shell_quote_path(&original_zdotdir.join(".zshrc"));
        let zdotdir = shell_quote_path(original_zdotdir);
        content.push_str(&format!(
            "[ -f {zshrc} ] && ZDOTDIR={zdotdir} source {zshrc}\n"
        ));
    }
    content.push_str(&format!("source {}\n", shell_quote_path(script)));
    content
}

/// Create a temporary bashrc that sources `~/.bashrc` then kuro integration.
///
/// Returns a typed rcfile path to `exec_in_child`, which adds
/// `--rcfile <path>` to the bash invocation.
/// This avoids overriding HOME (which breaks tilde expansion, cd, etc.).
#[inline]
fn setup_bash_integration(integration_dir: &Path) -> Option<PathBuf> {
    let script = integration_dir.join("kuro-shell.bash");
    if !script.exists() {
        return None;
    }
    let home = std::env::var_os("HOME").map(PathBuf::from);
    let bashrc_content = build_bash_rcfile_content(home.as_deref(), &script);
    write_temp_shell_rcfile("kuro-bash", ".bashrc", bashrc_content)
}

/// Create a temporary ZDOTDIR that sources `~/.zshrc` then kuro integration.
#[inline]
fn setup_zsh_integration(integration_dir: &Path, env: &mut ChildEnvBuilder) {
    let script = integration_dir.join("kuro-shell.zsh");
    if !script.exists() {
        return;
    }
    let original_zdotdir = std::env::var_os("ZDOTDIR")
        .or_else(|| std::env::var_os("HOME"))
        .map(PathBuf::from)
        .unwrap_or_default();

    let original_zdotdir_arg =
        (!original_zdotdir.as_os_str().as_bytes().is_empty()).then_some(original_zdotdir.as_path());
    let zshrc_content = build_zsh_rcfile_content(original_zdotdir_arg, &script);
    if let Some(zshrc_path) = write_temp_shell_rcfile("kuro-zsh", ".zshrc", zshrc_content) {
        let zshdir = zshrc_path
            .parent()
            .map(Path::to_path_buf)
            .unwrap_or_default();
        env.set_os(b"ZDOTDIR", zshdir.as_os_str());
        env.set_os(b"KURO_ORIGINAL_ZDOTDIR", original_zdotdir.as_os_str());
    }
}

/// Prepend the integration directory to `XDG_DATA_DIRS` for fish autoloading.
#[inline]
fn setup_fish_integration(integration_dir: &Path, env: &mut ChildEnvBuilder) {
    let script = integration_dir.join("kuro-shell.fish");
    if !script.exists() {
        return;
    }
    let vendor_dir = integration_dir.join("fish").join("vendor_conf.d");
    if !vendor_dir.exists() {
        return;
    }
    let existing = std::env::var_os("XDG_DATA_DIRS").unwrap_or_default();
    let mut new_val = integration_dir.as_os_str().as_bytes().to_vec();
    if !existing.as_os_str().as_bytes().is_empty() {
        new_val.push(b':');
        new_val.extend_from_slice(existing.as_os_str().as_bytes());
    }
    env.set_bytes(b"XDG_DATA_DIRS", new_val);
}

/// Shell invocation state built from the validated shell path and args.
struct PreparedCStringArray {
    cstrings: Vec<CString>,
    ptrs: Vec<*const c_char>,
}

impl PreparedCStringArray {
    fn new(cstrings: Vec<CString>) -> Self {
        let mut ptrs = cstrings
            .iter()
            .map(|cstring| cstring.as_ptr())
            .collect::<Vec<_>>();
        ptrs.push(std::ptr::null());
        Self { cstrings, ptrs }
    }

    fn as_ptr(&self) -> *const *const c_char {
        debug_assert_eq!(self.ptrs.len(), self.cstrings.len() + 1);
        self.ptrs.as_ptr()
    }

    #[cfg(test)]
    fn to_strings(&self) -> Vec<String> {
        self.cstrings
            .iter()
            .map(|cstring| cstring.to_string_lossy().into_owned())
            .collect()
    }
}

/// Shell invocation state built from the validated shell path and args.
pub(super) struct ShellExecContext {
    shell_full_cstr: CString,
    argv: PreparedCStringArray,
    env: PreparedCStringArray,
}

impl ShellExecContext {
    #[cfg(test)]
    fn argv_strings(&self) -> Vec<String> {
        self.argv.to_strings()
    }
}

/// Put the PTY slave in control of the child session.
#[inline]
fn set_controlling_terminal(slave_fd: RawFd) -> bool {
    // SAFETY: setsid is async-signal-safe and takes no Rust-managed state.
    unsafe {
        if libc::setsid() == -1 {
            return false;
        }
    }

    // SAFETY: slave_fd is a valid PTY slave fd; TIOCSCTTY is async-signal-safe after setsid().
    #[allow(clippy::useless_conversion)]
    unsafe {
        if libc::ioctl(slave_fd, libc::TIOCSCTTY.into(), 0) == -1 {
            return false;
        }
    }

    true
}

/// Redirect stdin/stdout/stderr to the PTY slave.
#[inline]
fn redirect_standard_streams(slave_fd: RawFd) -> bool {
    // SAFETY: slave_fd is a valid open fd; dup2 to 0/1/2 is async-signal-safe.
    unsafe {
        if libc::dup2(slave_fd, 0) == -1 {
            return false;
        }
        if libc::dup2(slave_fd, 1) == -1 {
            return false;
        }
        if libc::dup2(slave_fd, 2) == -1 {
            return false;
        }
    }
    true
}

/// Drop the PTY ends that the child no longer needs.
#[inline]
fn close_child_descriptors(slave_fd: RawFd, master_fd: RawFd, reader_fd: RawFd) {
    // SAFETY: these are the child's inherited fd copies.  Closing them prevents
    // the child from keeping the master/slave ends alive after stdio dup2.
    unsafe {
        if slave_fd > 2 {
            libc::close(slave_fd);
        }
        if master_fd > 2 && master_fd != slave_fd {
            libc::close(master_fd);
        }
        if reader_fd > 2 && reader_fd != slave_fd && reader_fd != master_fd {
            libc::close(reader_fd);
        }
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

#[inline]
fn child_exit(code: i32) -> ! {
    // SAFETY: _exit terminates the child immediately without running Rust Drop
    // glue or atexit handlers, which are unsafe after fork in a multithreaded process.
    unsafe { libc::_exit(code) }
}

/// Child-process resources and arguments required to exec the validated shell.
pub(super) struct ChildExecContext {
    pub(super) slave: OwnedFd,
    pub(super) master_file: File,
    pub(super) reader_fd: RawFd,
    pub(super) rows: u16,
    pub(super) cols: u16,
    pub(super) exec: ShellExecContext,
}

/// Build the shell path, argv[0], and optional rcfile arguments.
fn build_shell_exec_context(
    shell_path: &Path,
    command: &str,
    shell_args: &[String],
    integration: &ShellIntegrationConfig,
    env: PreparedCStringArray,
) -> Result<ShellExecContext> {
    let shell_full_cstr = shell_path_to_cstring(shell_path, command)?;
    let mut argv = Vec::with_capacity(shell_args.len() + 3);
    argv.push(shell_name_to_cstring(shell_path, command)?);
    argv.extend(
        shell_args
            .iter()
            .map(|s| {
                CString::new(s.as_str())
                    .map_err(|e| pty_spawn_error(command, &format!("Invalid shell arg: {e}")))
            })
            .collect::<Result<Vec<_>>>()?,
    );

    if let ShellIntegrationConfig::Bash { rcfile } = integration {
        argv.push(
            CString::new("--rcfile")
                .map_err(|e| pty_spawn_error(command, &format!("Invalid bash rcfile flag: {e}")))?,
        );
        argv.push(
            CString::new(rcfile.as_os_str().as_bytes())
                .map_err(|e| pty_spawn_error(command, &format!("Invalid rcfile path: {e}")))?,
        );
    }

    Ok(ShellExecContext {
        shell_full_cstr,
        argv: PreparedCStringArray::new(argv),
        env,
    })
}

/// Build every allocation-backed child exec input before fork.
pub(super) fn build_child_exec_context(
    shell_path: &Path,
    rows: u16,
    cols: u16,
    command: &str,
    shell_args: &[String],
) -> Result<ShellExecContext> {
    let (env, integration) = build_child_env(rows, cols, shell_path, command)?;
    build_shell_exec_context(shell_path, command, shell_args, &integration, env)
}

/// Configure a forked child process: establish a PTY session, redirect I/O,
/// and exec the shell.
///
/// This function runs entirely in the child process after `fork()`.  If it
/// cannot complete setup, it terminates via `_exit`.  On success, `execve`
/// replaces the child image with the shell binary and this function never
/// returns normally.
///
/// # Safety
/// Must only be called in the child process after `fork()`.
/// It performs only async-signal-safe syscalls until `execve`.
pub(super) fn exec_in_child(ctx: ChildExecContext) -> ! {
    let ChildExecContext {
        slave,
        master_file,
        reader_fd,
        rows,
        cols,
        exec,
    } = ctx;

    let slave_fd = slave.as_raw_fd();
    let master_fd = master_file.as_raw_fd();
    if !set_controlling_terminal(slave_fd) {
        child_exit(CHILD_EXIT_SETUP_FAILED);
    }
    if !redirect_standard_streams(slave_fd) {
        child_exit(CHILD_EXIT_SETUP_FAILED);
    }

    // Release the slave and master ends — stdin/stdout/stderr duplicates cover I/O.
    close_child_descriptors(slave_fd, master_fd, reader_fd);

    // Re-assert window size on fd 0 inside the child.
    // Some readline builds call TIOCGWINSZ before the parent's SIGWINCH handler fires;
    // without this they see 0 columns and permanently enter dumb/novis mode.
    set_child_winsize(rows, cols);

    // Execute the shell via its absolute path so the exact validated binary is used
    // (not whatever $PATH resolves first).  argv[0] = basename keeps ps/top readable.
    // SAFETY: all pointers refer to CString storage prepared before fork and
    // kept alive by `exec` until execve either replaces the image or fails.
    unsafe {
        libc::execve(
            exec.shell_full_cstr.as_ptr(),
            exec.argv.as_ptr(),
            exec.env.as_ptr(),
        );
    }
    child_exit(CHILD_EXIT_EXEC_FAILED);
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt as _;
    use std::sync::Mutex;

    static ENV_TEST_LOCK: Mutex<()> = Mutex::new(());

    fn empty_env() -> PreparedCStringArray {
        PreparedCStringArray::new(Vec::new())
    }

    #[test]
    fn shell_quote_escapes_single_quotes() {
        assert_eq!(shell_quote("a'b"), r"'a'\''b'");
    }

    #[test]
    fn bash_rcfile_content_quotes_paths() {
        let content = build_bash_rcfile_content(
            Some(Path::new("/tmp/home dir/o'clock")),
            Path::new("/tmp/kuro dir/o'clock/kuro-shell.bash"),
        );

        assert!(content.contains(r"[ -f '/tmp/home dir/o'\''clock/.bashrc' ]"));
        assert!(content.contains(r"source '/tmp/kuro dir/o'\''clock/kuro-shell.bash'"));
    }

    #[test]
    fn build_shell_exec_context_uses_typed_bash_rcfile() {
        let integration = ShellIntegrationConfig::Bash {
            rcfile: PathBuf::from("/tmp/kuro-bash/.bashrc"),
        };
        let ctx = build_shell_exec_context(
            Path::new("/bin/bash"),
            "bash",
            &[],
            &integration,
            empty_env(),
        )
        .unwrap();

        assert_eq!(
            ctx.argv_strings(),
            ["bash", "--rcfile", "/tmp/kuro-bash/.bashrc"]
        );
    }

    #[test]
    fn build_shell_exec_context_ignores_parent_bash_rcfile_env() {
        let _lock = ENV_TEST_LOCK.lock().unwrap_or_else(|err| err.into_inner());
        #[allow(deprecated, reason = "test serializes process env access")]
        unsafe {
            std::env::set_var("KURO_BASH_RCFILE", "/tmp/injected");
        }

        let ctx = build_shell_exec_context(
            Path::new("/bin/zsh"),
            "zsh",
            &[],
            &ShellIntegrationConfig::default(),
            empty_env(),
        )
        .unwrap();

        #[allow(deprecated, reason = "test serializes process env access")]
        unsafe {
            std::env::remove_var("KURO_BASH_RCFILE");
        }
        assert_eq!(ctx.argv_strings(), ["zsh"]);
    }

    #[test]
    fn write_temp_shell_rcfile_uses_owner_only_permissions() {
        let rcfile =
            write_temp_shell_rcfile("kuro-child-test", ".bashrc", "source '/tmp/a'\n".to_owned())
                .expect("rcfile should be created");
        let dir = rcfile
            .parent()
            .expect("rcfile should have parent")
            .to_path_buf();

        let dir_mode = std::fs::metadata(&dir).unwrap().permissions().mode();
        let file_mode = std::fs::metadata(&rcfile).unwrap().permissions().mode();

        let _ = std::fs::remove_file(&rcfile);
        let _ = std::fs::remove_dir(&dir);

        assert_eq!(
            dir_mode & 0o077,
            0,
            "temp dir must not be group/world accessible"
        );
        assert_eq!(
            file_mode & 0o077,
            0,
            "rcfile must not be group/world accessible"
        );
    }

    #[test]
    fn test_shell_quote_escapes_single_quotes_without_enabling_expansion() {
        assert_eq!(
            shell_quote("a'$(touch hacked)`id`"),
            "'a'\\''$(touch hacked)`id`'"
        );
    }

    #[test]
    fn test_build_bash_rcfile_content_shell_quotes_paths() {
        let content = build_bash_rcfile_content(
            Some(Path::new("/tmp/home'$(touch hacked)")),
            Path::new("/tmp/integration`touch hacked`/kuro-shell.bash"),
        );
        assert_eq!(
            content,
            "[ -f '/tmp/home'\\''$(touch hacked)/.bashrc' ] && source '/tmp/home'\\''$(touch hacked)/.bashrc'\nsource '/tmp/integration`touch hacked`/kuro-shell.bash'\n"
        );
    }

    #[test]
    fn test_build_zsh_rcfile_content_shell_quotes_paths() {
        let content = build_zsh_rcfile_content(
            Some(Path::new("/tmp/zdot'$(touch hacked)")),
            Path::new("/tmp/integration`touch hacked`/kuro-shell.zsh"),
        );
        assert_eq!(
            content,
            "[ -f '/tmp/zdot'\\''$(touch hacked)/.zshrc' ] && ZDOTDIR='/tmp/zdot'\\''$(touch hacked)' source '/tmp/zdot'\\''$(touch hacked)/.zshrc'\nsource '/tmp/integration`touch hacked`/kuro-shell.zsh'\n"
        );
    }

    #[test]
    fn test_shell_rcfile_content_skips_empty_original_startup_dir() {
        assert_eq!(
            build_bash_rcfile_content(None, Path::new("/tmp/kuro-shell.bash")),
            "source '/tmp/kuro-shell.bash'\n"
        );
        assert_eq!(
            build_zsh_rcfile_content(None, Path::new("/tmp/kuro-shell.zsh")),
            "source '/tmp/kuro-shell.zsh'\n"
        );
    }
}
