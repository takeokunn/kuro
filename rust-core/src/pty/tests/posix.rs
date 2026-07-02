use super::*;
use std::os::unix::fs::PermissionsExt as _;
use std::path::Path;

const TEST_SHELL_NAMES: &[&str] = &["sh", "bash", "zsh", "fish"];

fn is_executable_file(path: &Path) -> bool {
    path.is_file()
        && path
            .metadata()
            .map(|meta| meta.permissions().mode() & 0o111 != 0)
            .unwrap_or(false)
}

fn optional_shell_path(name: &str) -> Option<String> {
    let common_candidates = [
        format!("/bin/{name}"),
        format!("/usr/bin/{name}"),
        format!("/usr/local/bin/{name}"),
        format!("/opt/homebrew/bin/{name}"),
    ];

    common_candidates
        .into_iter()
        .find(|candidate| is_executable_file(Path::new(candidate.as_str())))
        .or_else(|| {
            std::env::var("SHELL").ok().filter(|shell| {
                let path = Path::new(shell);
                path.is_absolute()
                    && is_executable_file(path)
                    && path.file_name().and_then(|n| n.to_str()) == Some(name)
            })
        })
        .or_else(|| {
            std::env::var_os("PATH").and_then(|paths| {
                std::env::split_paths(&paths).find_map(|dir| {
                    let path = dir.join(name);
                    if is_executable_file(&path) {
                        Some(path.to_string_lossy().into_owned())
                    } else {
                        None
                    }
                })
            })
        })
}

fn required_test_shell_path() -> String {
    TEST_SHELL_NAMES
        .iter()
        .find_map(|name| optional_shell_path(name))
        .expect("absolute path to sh, bash, zsh, or fish is required for POSIX PTY tests")
}

#[test]
fn test_validate_allowed_shells() {
    for shell_name in TEST_SHELL_NAMES {
        if let Some(path) = optional_shell_path(shell_name) {
            let result = Pty::validate_shell(&path);
            assert!(
                result.is_ok(),
                "absolute {shell_name} path should be accepted: {path}. Error: {:?}",
                result.err()
            );
        }
    }
}

#[test]
fn test_validate_rejected_shell() {
    assert!(Pty::validate_shell("sh").is_err());
    assert!(Pty::validate_shell("bash").is_err());
    assert!(Pty::validate_shell("zsh").is_err());
    assert!(Pty::validate_shell("fish").is_err());
    assert!(Pty::validate_shell(" malicious_command").is_err());
    assert!(Pty::validate_shell("rm").is_err());
    assert!(Pty::validate_shell("cat").is_err());
}

#[test]
fn test_pty_spawn() {
    let shell = required_test_shell_path();
    let pty = Pty::spawn(&shell, &[], 24, 80);
    assert!(pty.is_ok());

    let mut pty = pty.unwrap();
    pty.write(b"echo test\n").unwrap();
}

#[test]
fn test_drop_kills_long_running_child_without_hanging() {
    let start = std::time::Instant::now();
    {
        let shell = required_test_shell_path();
        let mut pty = Pty::spawn(&shell, &[], 24, 80).unwrap();
        pty.write(b"sleep 60\n").unwrap();
        std::thread::sleep(std::time::Duration::from_millis(100));
    }

    assert!(
        start.elapsed() < std::time::Duration::from_secs(3),
        "dropping a PTY with a long-running foreground child must be bounded"
    );
}

#[test]
fn test_validate_shell_empty_string_rejected() {
    // An empty string is not an absolute path and must never be resolved via PATH.
    let result = Pty::validate_shell("");
    assert!(result.is_err(), "empty string should be rejected");
}

#[test]
fn test_validate_shell_absolute_path_bash() {
    let bash_path = std::path::Path::new("/bin/bash");
    if is_executable_file(bash_path) {
        // An absolute path to bash resolves to the "bash" basename which is in the allowlist
        let result = Pty::validate_shell("/bin/bash");
        assert!(
            result.is_ok(),
            "/bin/bash should be accepted when it exists"
        );
    }
}

#[test]
fn test_validate_shell_rejects_relative_path_slash_slash() {
    // Relative paths are rejected before any filesystem or PATH resolution.
    let result = Pty::validate_shell("../bash");
    assert!(result.is_err(), "relative path ../bash should be rejected");
}

#[test]
fn test_validate_shell_rejects_python() {
    // Relative executable names are rejected even before basename allowlist checks.
    let result = Pty::validate_shell("python3");
    assert!(
        result.is_err(),
        "python3 should be rejected (not in allowlist)"
    );
}

// --- Absolute-path handling tests (NixOS / Nix store compatibility) ---

#[test]
fn test_validate_shell_absolute_nix_store() {
    // Use $SHELL to test with the actual shell path on this system.
    // On NixOS this is a Nix store path like /nix/store/…/bin/fish.
    // Skip gracefully if $SHELL is unset or points to a shell outside the allowlist.
    if let Ok(shell) = std::env::var("SHELL") {
        let p = std::path::Path::new(&shell);
        if p.is_absolute() && is_executable_file(p) {
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
    // An absolute path with an allowed basename but no execute bit must be rejected.
    let dir = std::env::temp_dir().join(format!("kuro_pty_shell_not_exec_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir(&dir).unwrap();
    let path = dir.join("fish");
    std::fs::write(&path, b"#!/bin/sh").unwrap();
    let mut perms = std::fs::metadata(&path).unwrap().permissions();
    perms.set_mode(0o644); // rw-r--r-- : no execute bit
    std::fs::set_permissions(&path, perms).unwrap();
    let result = Pty::validate_shell(path.to_str().unwrap());
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_dir(&dir);
    assert!(
        result.is_err(),
        "absolute path without execute bit must be rejected"
    );
}

#[test]
fn test_validate_shell_absolute_not_in_allowlist() {
    // An executable absolute path whose basename is not in ALLOWED_SHELLS must be rejected.
    let dir =
        std::env::temp_dir().join(format!("kuro_pty_shell_not_allowed_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir(&dir).unwrap();
    let path = dir.join("curio");
    std::fs::write(&path, b"#!/bin/sh").unwrap();
    let mut perms = std::fs::metadata(&path).unwrap().permissions();
    perms.set_mode(0o755);
    std::fs::set_permissions(&path, perms).unwrap();
    let result = Pty::validate_shell(path.to_str().unwrap());
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_dir(&dir);
    assert!(
        result.is_err(),
        "absolute path with basename outside the allowlist must be rejected"
    );
}

#[test]
fn test_validate_shell_absolute_not_regular_file() {
    // A directory with an allowed basename is not a valid exec target.
    let dir =
        std::env::temp_dir().join(format!("kuro_pty_shell_not_regular_{}", std::process::id()));
    let path = dir.join("sh");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir(&dir).unwrap();
    std::fs::create_dir(&path).unwrap();
    let result = Pty::validate_shell(path.to_str().unwrap());
    let _ = std::fs::remove_dir(&path);
    let _ = std::fs::remove_dir(&dir);
    assert!(
        result.is_err(),
        "absolute directory path must be rejected even when basename is allowlisted"
    );
}

#[test]
fn test_validate_shell_absolute_bin_sh() {
    // /bin/sh exists on all POSIX systems (typically a symlink to bash or dash).
    // Its basename "sh" is in ALLOWED_SHELLS. On NixOS it is a symlink into the
    // Nix store, so this test exercises the absolute-path branch on NixOS.
    let bin_sh = std::path::Path::new("/bin/sh");
    if is_executable_file(bin_sh) {
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
    let shell = required_test_shell_path();
    let pty = Pty::spawn(&shell, &[], 24, 80);
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
    let shell = required_test_shell_path();
    let pty = Pty::spawn(&shell, &[], 24, 80);
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
    // the exact binary we validated, not a later PATH resolution.
    let shell = required_test_shell_path();
    let result = Pty::validate_shell(&shell);
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
    if let Some(bash) = optional_shell_path("bash") {
        let result = Pty::validate_shell(&bash);
        assert!(result.is_ok());
        let path = result.unwrap();
        assert!(
            path.is_absolute(),
            "validate_shell({bash:?}) must return an absolute path, got: {path:?}"
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
    let shell = required_test_shell_path();
    let pty = Pty::spawn(&shell, &[], 42, 120);
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

#[path = "posix/env.rs"]
mod env;
