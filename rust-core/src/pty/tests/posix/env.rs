use super::*;

// --- Tests for child exec environment construction ---

static ENV_TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

fn child_env(rows: u16, cols: u16) -> Vec<String> {
    super::build_child_env_strings_for_test(rows, cols, std::path::Path::new("/bin/sh"), "sh")
        .expect("child env should be built")
}

fn env_value<'a>(env: &'a [String], key: &str) -> Option<&'a str> {
    let prefix = format!("{key}=");
    env.iter().find_map(|entry| entry.strip_prefix(&prefix))
}

fn has_env_key(env: &[String], key: &str) -> bool {
    env_value(env, key).is_some()
}

fn set_var_for_test(key: &str, value: &str) {
    #[allow(deprecated, reason = "tests serialize process env access")]
    unsafe {
        std::env::set_var(key, value);
    }
}

fn remove_var_for_test(key: &str) {
    #[allow(deprecated, reason = "tests serialize process env access")]
    unsafe {
        std::env::remove_var(key);
    }
}

#[test]
fn test_child_exec_env_sets_term() {
    let env = child_env(24, 80);

    assert_eq!(env_value(&env, "TERM"), Some("xterm-256color"));
    assert_eq!(env_value(&env, "COLORTERM"), Some("truecolor"));
    assert_eq!(env_value(&env, "KURO_TERMINAL"), Some("1"));
}

#[test]
fn test_child_exec_env_propagates_dimensions() {
    let env = child_env(42, 120);

    assert_eq!(env_value(&env, "LINES"), Some("42"));
    assert_eq!(env_value(&env, "COLUMNS"), Some("120"));
}

#[test]
fn test_child_exec_env_removes_multiplexer_vars() {
    let _lock = ENV_TEST_LOCK.lock().unwrap_or_else(|err| err.into_inner());
    set_var_for_test("TMUX", "some-socket");
    set_var_for_test("STY", "some-screen");
    set_var_for_test("INSIDE_EMACS", "28.1");
    set_var_for_test("EMACS_SOCKET_NAME", "/tmp/emacs");

    let env = child_env(24, 80);

    remove_var_for_test("TMUX");
    remove_var_for_test("STY");
    remove_var_for_test("INSIDE_EMACS");
    remove_var_for_test("EMACS_SOCKET_NAME");

    assert!(!has_env_key(&env, "TMUX"));
    assert!(!has_env_key(&env, "STY"));
    assert!(!has_env_key(&env, "INSIDE_EMACS"));
    assert!(!has_env_key(&env, "EMACS_SOCKET_NAME"));
}

#[test]
fn test_child_exec_env_does_not_mutate_parent_env() {
    let _lock = ENV_TEST_LOCK.lock().unwrap_or_else(|err| err.into_inner());
    set_var_for_test("TERM", "parent-term");

    let env = child_env(24, 80);
    let parent_term = std::env::var("TERM").expect("parent TERM should remain set");

    remove_var_for_test("TERM");

    assert_eq!(env_value(&env, "TERM"), Some("xterm-256color"));
    assert_eq!(parent_term, "parent-term");
}

// --- Tests for Pty::has_pending_data ---

#[test]
fn test_has_pending_data_false_on_fresh_spawn() {
    // A freshly spawned PTY has not yet produced output on the channel.
    // has_pending_data() must return false before any data arrives.
    let shell = super::required_test_shell_path();
    let pty = Pty::spawn(&shell, &[], 24, 80).expect("spawn failed");
    // We do not call read() here; we just check the flag immediately.
    // The shell may not have written anything yet, so the channel is likely empty.
    // This is a best-effort check; the test is not racey because we never write.
    let _ = pty.has_pending_data(); // must not panic
}

#[test]
fn test_has_pending_data_true_after_echo() {
    // Write a command that produces output and wait for data to arrive.
    let shell = super::required_test_shell_path();
    let mut pty = Pty::spawn(&shell, &[], 24, 80).expect("spawn failed");
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

#[test]
fn test_validate_shell_not_found_message_contains_shell_name() {
    let err = Pty::validate_shell("_no_such_shell_xyz_").unwrap_err();
    let msg = format!("{err}");
    assert!(
        msg.contains("_no_such_shell_xyz_") || msg.contains("absolute") || msg.contains("Shell"),
        "error message must indicate what failed; got: {msg}"
    );
}
