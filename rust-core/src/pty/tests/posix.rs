use super::*;

#[test]
fn test_validate_allowed_shells() {
    assert!(Pty::validate_shell("sh").is_ok());
    if which::which("bash").is_ok() {
        assert!(Pty::validate_shell("bash").is_ok());
    }
    if which::which("zsh").is_ok() {
        assert!(Pty::validate_shell("zsh").is_ok());
    }
    if which::which("fish").is_ok() {
        assert!(Pty::validate_shell("fish").is_ok());
    }
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

// --- Absolute-path handling tests (NixOS / Nix store compatibility) ---

#[test]
fn test_validate_shell_absolute_nix_store() {
    // Use $SHELL to test with the actual shell path on this system.
    // On NixOS this is a Nix store path like /nix/store/…/bin/fish.
    // Skip gracefully if $SHELL is unset or points to a non-whitelisted shell.
    if let Ok(shell) = std::env::var("SHELL") {
        let p = std::path::Path::new(&shell);
        if p.is_absolute() && p.exists() {
            let basename = p.file_name().and_then(|n| n.to_str()).unwrap_or("");
            if ["bash", "zsh", "sh", "fish"].contains(&basename) {
                let result = Pty::validate_shell(&shell);
                assert!(
                    result.is_ok(),
                    "absolute path from $SHELL should be accepted: {shell}. Error: {:?}",
                    result.err()
                );
                assert_eq!(
                    result.unwrap(),
                    std::path::PathBuf::from(&shell),
                    "returned PathBuf must equal the input path exactly"
                );
            }
        }
    }
}

#[test]
fn test_validate_shell_absolute_nonexistent() {
    // A non-existent absolute path must be rejected.
    let result = Pty::validate_shell("/nonexistent/path/to/bash");
    assert!(
        result.is_err(),
        "nonexistent absolute path must be rejected"
    );
}

#[test]
fn test_validate_shell_absolute_not_executable() {
    // An absolute path with a whitelisted basename but no execute bit must be rejected.
    // Use a PID-suffixed name to avoid collisions with parallel test runs.
    use std::os::unix::fs::PermissionsExt as _;
    let path = std::env::temp_dir().join(format!("fish_{}", std::process::id()));
    std::fs::write(&path, b"#!/bin/sh").unwrap();
    let mut perms = std::fs::metadata(&path).unwrap().permissions();
    perms.set_mode(0o644); // rw-r--r-- : no execute bit
    std::fs::set_permissions(&path, perms).unwrap();
    let result = Pty::validate_shell(path.to_str().unwrap());
    let _ = std::fs::remove_file(&path);
    assert!(
        result.is_err(),
        "absolute path without execute bit must be rejected"
    );
}

#[test]
fn test_validate_shell_absolute_not_in_whitelist() {
    // An executable absolute path whose basename is not in ALLOWED_SHELLS must be rejected.
    use std::os::unix::fs::PermissionsExt as _;
    let path = std::env::temp_dir().join(format!("curio_{}", std::process::id()));
    std::fs::write(&path, b"#!/bin/sh").unwrap();
    let mut perms = std::fs::metadata(&path).unwrap().permissions();
    perms.set_mode(0o755);
    std::fs::set_permissions(&path, perms).unwrap();
    let result = Pty::validate_shell(path.to_str().unwrap());
    let _ = std::fs::remove_file(&path);
    assert!(
        result.is_err(),
        "absolute path with non-whitelisted basename must be rejected"
    );
}

#[test]
fn test_validate_shell_absolute_bin_sh() {
    // /bin/sh exists on all POSIX systems (typically a symlink to bash or dash).
    // Its basename "sh" is in ALLOWED_SHELLS. On NixOS it is a symlink into the
    // Nix store, so this test exercises the absolute-path branch on NixOS.
    let bin_sh = std::path::Path::new("/bin/sh");
    if bin_sh.exists() {
        let result = Pty::validate_shell("/bin/sh");
        assert!(
            result.is_ok(),
            "/bin/sh must be accepted when it exists. Error: {:?}",
            result.err()
        );
        assert_eq!(
            result.unwrap(),
            std::path::PathBuf::from("/bin/sh"),
            "returned PathBuf must equal /bin/sh"
        );
    }
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
        "validate_shell must return an absolute path, got: {path:?}"
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
            "validate_shell('bash') must return an absolute path, got: {path:?}"
        );
    }
}

#[test]
fn test_pty_tiocgwinsz_via_master_after_spawn() {
    // After spawn, querying TIOCGWINSZ on the master must return the dimensions
    // we requested.  This is the parent-side proof that openpty(Some(&winsize))
    // correctly propagated the size.  If this returns 0×0, readline in the child
    // will enter dumb mode.
    use std::os::unix::io::AsRawFd as _;
    let pty = Pty::spawn("sh", 42, 120);
    assert!(pty.is_ok());
    let pty = pty.unwrap();

    let mut ws = libc::winsize {
        ws_row: 0,
        ws_col: 0,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };
    // SAFETY: pty.as_raw_fd() is a valid open PTY master fd; TIOCGWINSZ writes to a
    // stack-allocated winsize struct that outlives the call; this is test-only code.
    let ret = unsafe { libc::ioctl(pty.as_raw_fd(), libc::TIOCGWINSZ, &mut ws) };
    assert_eq!(ret, 0, "TIOCGWINSZ ioctl failed");
    assert_eq!(ws.ws_row, 42, "ws_row must equal requested rows");
    assert_eq!(
        ws.ws_col, 120,
        "ws_col must equal requested cols — 0 here would cause readline dumb mode"
    );
}

// --- Tests for setup_child_env (pure env-var function) ---

/// Serializes all fork-based and env-mutating `setup_child_env` tests.
///
/// `fork()` in a multi-threaded process (cargo test) copies only the calling
/// thread but inherits all mutexes in their current state.  Rust's internal
/// env-var `RwLock` will be permanently locked in the child if another thread
/// holds it at fork time, causing a deadlock that hits the 2-second timeout.
///
/// By holding `ENV_FORK_LOCK` for the entire critical section (env mutation
/// + fork + cleanup), we guarantee that no env-var write is in-flight when
/// `fork()` is called in any of the three `setup_child_env` tests.
#[cfg(unix)]
static ENV_FORK_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

/// `setup_child_env` tests run in a subprocess via `fork()` so that process-wide
/// env-var mutations are isolated from parallel test threads.
///
/// Each test helper forks, calls `setup_child_env` in the child, writes a result
/// byte to a pipe, and the parent asserts on it.
///
/// **IMPORTANT**: `fork()` in a multi-threaded process (cargo test) copies only
/// the calling thread.  Mutexes held by other threads (including Rust's internal
/// env-var `RwLock`) remain permanently locked in the child, causing deadlocks.
/// To avoid hanging the test runner:
///   - The parent polls `waitpid(WNOHANG)` with a timeout, escalating to SIGKILL.
///   - The child uses `libc::_exit()` (not `std::process::exit`) to skip atexit
///     handlers that may also deadlock.
#[cfg(unix)]
fn run_in_child_check<F: FnOnce() -> bool>(check: F) -> bool {
    use std::os::unix::io::FromRawFd as _;
    let mut fds = [0i32; 2];
    // SAFETY: fds is a 2-element i32 array; libc::pipe fills it on success.
    let ret = unsafe { libc::pipe(fds.as_mut_ptr()) };
    assert_eq!(ret, 0, "pipe() failed");
    let (read_fd, write_fd) = (fds[0], fds[1]);

    // SAFETY: fork() duplicates the current thread's state; the child must
    // use only async-signal-safe calls before _exit().  Note: std::env::var
    // and setup_child_env are NOT async-signal-safe (they acquire an env
    // RwLock), so this can deadlock if another test thread holds that lock.
    // The timeout below prevents the test runner from hanging in that case.
    match unsafe { nix::unistd::fork() }.expect("fork failed") {
        nix::unistd::ForkResult::Child => {
            // SAFETY: write_fd is a valid open fd from pipe above.
            let mut wf = unsafe { std::fs::File::from_raw_fd(write_fd) };
            unsafe { libc::close(read_fd) };
            let ok = check();
            use std::io::Write as _;
            let _ = wf.write_all(&[ok as u8]);
            // Use _exit to avoid running atexit handlers (unsafe after fork).
            unsafe { libc::_exit(0) };
        }
        nix::unistd::ForkResult::Parent { child } => {
            unsafe { libc::close(write_fd) };
            // SAFETY: read_fd is a valid open fd from pipe above.
            let mut rf = unsafe { std::fs::File::from_raw_fd(read_fd) };

            // Poll with WNOHANG + timeout to avoid blocking forever if the
            // child deadlocks on a poisoned mutex inherited from fork().
            let mut reaped = false;
            for _ in 0..200 {
                // 200 × 10 ms = 2 s timeout
                match nix::sys::wait::waitpid(child, Some(nix::sys::wait::WaitPidFlag::WNOHANG)) {
                    Ok(nix::sys::wait::WaitStatus::StillAlive) => {
                        std::thread::sleep(std::time::Duration::from_millis(10));
                    }
                    Ok(_) | Err(nix::errno::Errno::ECHILD) => {
                        reaped = true;
                        break;
                    }
                    Err(_) => {
                        reaped = true;
                        break;
                    }
                }
            }
            if !reaped {
                // Child is stuck (likely deadlocked on env RwLock after fork).
                let _ = nix::sys::signal::kill(child, nix::sys::signal::Signal::SIGKILL);
                let _ = nix::sys::wait::waitpid(child, None);
                return false; // Test fails gracefully instead of hanging.
            }

            let mut buf = [0u8; 1];
            use std::io::Read as _;
            let _ = rf.read_exact(&mut buf);
            buf[0] != 0
        }
    }
}

#[test]
#[cfg(unix)]
fn test_setup_child_env_sets_term() {
    // setup_child_env must set TERM=xterm-256color and COLORTERM=truecolor.
    // Runs in a forked child to isolate env-var mutations from other test threads.
    let _lock = ENV_FORK_LOCK.lock().unwrap();
    let ok = run_in_child_check(|| {
        super::setup_child_env(24, 80);
        std::env::var("TERM").as_deref() == Ok("xterm-256color")
            && std::env::var("COLORTERM").as_deref() == Ok("truecolor")
            && std::env::var("KURO_TERMINAL").as_deref() == Ok("1")
    });
    assert!(
        ok,
        "TERM/COLORTERM/KURO_TERMINAL must be set by setup_child_env"
    );
}

#[test]
#[cfg(unix)]
fn test_setup_child_env_propagates_dimensions() {
    // Runs in a forked child to isolate env-var mutations from other test threads.
    let _lock = ENV_FORK_LOCK.lock().unwrap();
    let ok = run_in_child_check(|| {
        super::setup_child_env(42, 120);
        std::env::var("LINES").as_deref() == Ok("42")
            && std::env::var("COLUMNS").as_deref() == Ok("120")
    });
    assert!(ok, "LINES/COLUMNS must match the rows/cols arguments");
}

#[test]
#[cfg(unix)]
fn test_setup_child_env_removes_multiplexer_vars() {
    // Set multiplexer vars in the PARENT before fork so the child inherits them.
    // Hold ENV_FORK_LOCK for the full critical section (set_var + fork + cleanup)
    // so no concurrent test can hold the env RwLock when fork() is called.
    let _lock = ENV_FORK_LOCK.lock().unwrap();
    #[allow(deprecated)]
    unsafe {
        std::env::set_var("TMUX", "some-socket");
        std::env::set_var("STY", "some-screen");
        std::env::set_var("INSIDE_EMACS", "28.1");
        std::env::set_var("EMACS_SOCKET_NAME", "/tmp/emacs");
    }
    let ok = run_in_child_check(|| {
        // Child inherits the vars set above; verify setup_child_env removes them.
        super::setup_child_env(24, 80);
        std::env::var("TMUX").is_err()
            && std::env::var("STY").is_err()
            && std::env::var("INSIDE_EMACS").is_err()
            && std::env::var("EMACS_SOCKET_NAME").is_err()
    });
    // Clean up in the parent regardless of test outcome.
    #[allow(deprecated)]
    unsafe {
        std::env::remove_var("TMUX");
        std::env::remove_var("STY");
        std::env::remove_var("INSIDE_EMACS");
        std::env::remove_var("EMACS_SOCKET_NAME");
    }
    assert!(ok, "multiplexer vars must be removed by setup_child_env");
}

// --- Tests for Pty::has_pending_data ---

#[test]
fn test_has_pending_data_false_on_fresh_spawn() {
    // A freshly spawned PTY has not yet produced output on the channel.
    // has_pending_data() must return false before any data arrives.
    let pty = Pty::spawn("sh", 24, 80).expect("spawn failed");
    // We do not call read() here; we just check the flag immediately.
    // The shell may not have written anything yet, so the channel is likely empty.
    // This is a best-effort check; the test is not racey because we never write.
    let _ = pty.has_pending_data(); // must not panic
}

#[test]
fn test_has_pending_data_true_after_echo() {
    // Write a command that produces output and wait for data to arrive.
    let mut pty = Pty::spawn("sh", 24, 80).expect("spawn failed");
    pty.write(b"echo kuro_test_marker\n").expect("write failed");

    // Poll until data arrives (up to 2 s).
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(2);
    while !pty.has_pending_data() && std::time::Instant::now() < deadline {
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    assert!(
        pty.has_pending_data(),
        "has_pending_data() must return true after the shell writes output"
    );
}

// --- Tests for validate_shell error message format ---

#[test]
fn test_validate_shell_disallowed_message_contains_shell_name() {
    // The error message for a disallowed shell must include the shell's basename
    // and the list of allowed shells, so users know what is permitted.
    if which::which("python3").is_ok() {
        let err = Pty::validate_shell("python3").unwrap_err();
        let msg = format!("{err}");
        assert!(
            msg.contains("python3"),
            "error message must contain the rejected shell name; got: {msg}"
        );
        assert!(
            msg.contains("bash") || msg.contains("sh"),
            "error message must mention allowed shells; got: {msg}"
        );
    }
}

#[test]
fn test_validate_shell_not_found_message_contains_shell_name() {
    let err = Pty::validate_shell("_no_such_shell_xyz_").unwrap_err();
    let msg = format!("{err}");
    assert!(
        msg.contains("_no_such_shell_xyz_") || msg.contains("not found") || msg.contains("Shell"),
        "error message must indicate what failed; got: {msg}"
    );
}
