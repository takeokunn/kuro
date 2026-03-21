use super::*;

#[test]
fn test_validate_allowed_shells() {
    assert!(Pty::validate_shell("bash").is_ok());
    assert!(Pty::validate_shell("zsh").is_ok());
    assert!(Pty::validate_shell("sh").is_ok());
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
