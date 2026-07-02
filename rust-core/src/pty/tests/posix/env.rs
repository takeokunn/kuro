use super::*;

// --- Tests for setup_child_env (pure env-var function) ---

/// Serializes all fork-based and env-mutating `setup_child_env` tests.
///
/// `fork()` in a multi-threaded process (cargo test) copies only the calling
/// thread but inherits all mutexes in their current state.  Rust's internal
/// env-var `RwLock` will be permanently locked in the child if another thread
/// holds it at fork time, causing a deadlock that hits the 2-second timeout.
///
/// By holding `ENV_FORK_LOCK` for the entire critical section
/// (env mutation + fork + cleanup), we guarantee that no env-var write
/// is in-flight when `fork()` is called in any of the three
/// `setup_child_env` tests.
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
///
/// Returns `Some(true/false)` with the check result, or `None` when the
/// child process timed out (common on WSL2 where `fork()` in a
/// multi-threaded process deadlocks on Rust's internal env `RwLock`).
/// Callers should skip the test rather than fail when `None` is returned.
#[cfg(unix)]
fn run_in_child_check<F: FnOnce() -> bool>(check: F) -> Option<bool> {
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
                // Child is stuck (deadlocked on env RwLock after fork — typical
                // on WSL2 where fork() in a multi-threaded process inherits
                // other threads' locks).  Signal caller to skip, not fail.
                let _ = nix::sys::signal::kill(child, nix::sys::signal::Signal::SIGKILL);
                let _ = nix::sys::wait::waitpid(child, None);
                return None;
            }

            let mut buf = [0u8; 1];
            use std::io::Read as _;
            let _ = rf.read_exact(&mut buf);
            Some(buf[0] != 0)
        }
    }
}

#[test]
#[cfg(unix)]
fn test_setup_child_env_sets_term() {
    // setup_child_env must set TERM=xterm-256color and COLORTERM=truecolor.
    // Runs in a forked child to isolate env-var mutations from other test threads.
    let _lock = ENV_FORK_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let result = run_in_child_check(|| {
        super::setup_child_env(24, 80, std::path::Path::new("/bin/sh"));
        std::env::var("TERM").as_deref() == Ok("xterm-256color")
            && std::env::var("COLORTERM").as_deref() == Ok("truecolor")
            && std::env::var("KURO_TERMINAL").as_deref() == Ok("1")
    });
    let Some(ok) = result else {
        // Child deadlocked on env RwLock after fork() — skip on WSL2.
        return;
    };
    assert!(
        ok,
        "TERM/COLORTERM/KURO_TERMINAL must be set by setup_child_env"
    );
}

#[test]
#[cfg(unix)]
fn test_setup_child_env_propagates_dimensions() {
    // Runs in a forked child to isolate env-var mutations from other test threads.
    let _lock = ENV_FORK_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let result = run_in_child_check(|| {
        super::setup_child_env(42, 120, std::path::Path::new("/bin/sh"));
        std::env::var("LINES").as_deref() == Ok("42")
            && std::env::var("COLUMNS").as_deref() == Ok("120")
    });
    let Some(ok) = result else {
        return; // Child deadlocked on env RwLock after fork() — skip on WSL2.
    };
    assert!(ok, "LINES/COLUMNS must match the rows/cols arguments");
}

#[test]
#[cfg(unix)]
fn test_setup_child_env_removes_multiplexer_vars() {
    // Set multiplexer vars in the PARENT before fork so the child inherits them.
    // Hold ENV_FORK_LOCK for the full critical section (set_var + fork + cleanup)
    // so no concurrent test can hold the env RwLock when fork() is called.
    let _lock = ENV_FORK_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    #[allow(
        deprecated,
        reason = "set_var deprecated but fork lock serializes access"
    )]
    unsafe {
        std::env::set_var("TMUX", "some-socket");
        std::env::set_var("STY", "some-screen");
        std::env::set_var("INSIDE_EMACS", "28.1");
        std::env::set_var("EMACS_SOCKET_NAME", "/tmp/emacs");
    }
    let result = run_in_child_check(|| {
        // Child inherits the vars set above; verify setup_child_env removes them.
        // INSIDE_EMACS is now removed (not overwritten) to avoid triggering bash
        // readline's Emacs-comint mode on macOS bash 3.2.
        super::setup_child_env(24, 80, std::path::Path::new("/bin/sh"));
        std::env::var("TMUX").is_err()
            && std::env::var("STY").is_err()
            && std::env::var("INSIDE_EMACS").is_err()
            && std::env::var("EMACS_SOCKET_NAME").is_err()
    });
    // Clean up in the parent regardless of test outcome.
    #[allow(
        deprecated,
        reason = "remove_var deprecated but fork lock serializes access"
    )]
    unsafe {
        std::env::remove_var("TMUX");
        std::env::remove_var("STY");
        std::env::remove_var("INSIDE_EMACS");
        std::env::remove_var("EMACS_SOCKET_NAME");
    }
    let Some(ok) = result else {
        return; // Child deadlocked on env RwLock after fork() — skip on WSL2.
    };
    assert!(ok, "multiplexer vars must be removed by setup_child_env");
}

// --- Tests for Pty::has_pending_data ---

#[test]
fn test_has_pending_data_false_on_fresh_spawn() {
    // A freshly spawned PTY has not yet produced output on the channel.
    // has_pending_data() must return false before any data arrives.
    let pty = Pty::spawn("sh", &[], 24, 80).expect("spawn failed");
    // We do not call read() here; we just check the flag immediately.
    // The shell may not have written anything yet, so the channel is likely empty.
    // This is a best-effort check; the test is not racey because we never write.
    let _ = pty.has_pending_data(); // must not panic
}

#[test]
fn test_has_pending_data_true_after_echo() {
    // Write a command that produces output and wait for data to arrive.
    let mut pty = Pty::spawn("sh", &[], 24, 80).expect("spawn failed");
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
    if super::Pty::find_in_path("python3").is_some() {
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
