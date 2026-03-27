// ---------------------------------------------------------------------------
// Global session state: detach / attach / list
// ---------------------------------------------------------------------------

/// Insert a fresh `Bound` session under an arbitrary sentinel key.
/// The caller must clean up with `shutdown_session(id)` when done.
fn insert_bound_session(id: u64) {
    let session = make_session(); // state: SessionState::Bound
    TERMINAL_SESSIONS.lock().unwrap().insert(id, session);
}

/// Insert a fresh `Detached` session under an arbitrary sentinel key.
fn insert_detached_session(id: u64) {
    let mut session = make_session();
    session.set_detached();
    TERMINAL_SESSIONS.lock().unwrap().insert(id, session);
}

/// `detach_session` transitions a Bound session to Detached and returns Ok.
#[test]
fn test_detach_session_bound_to_detached() {
    const ID: u64 = u64::MAX - 20;
    shutdown_session(ID).ok();
    insert_bound_session(ID);

    let result = detach_session(ID);
    assert!(
        result.is_ok(),
        "detach_session should succeed for a Bound session"
    );

    let is_detached = TERMINAL_SESSIONS
        .lock()
        .unwrap()
        .get(&ID)
        .is_some_and(super::session::TerminalSession::is_detached);
    assert!(is_detached, "session must be Detached after detach_session");

    shutdown_session(ID).ok();
}

/// `attach_session` transitions a Detached session to Bound and returns Ok.
#[test]
fn test_attach_session_detached_to_bound() {
    const ID: u64 = u64::MAX - 21;
    shutdown_session(ID).ok();
    insert_detached_session(ID);

    let result = attach_session(ID);
    assert!(
        result.is_ok(),
        "attach_session should succeed for a Detached session"
    );

    let is_detached = TERMINAL_SESSIONS
        .lock()
        .unwrap()
        .get(&ID)
        .is_none_or(super::session::TerminalSession::is_detached);
    assert!(
        !is_detached,
        "session must be Bound (not Detached) after attach_session"
    );

    shutdown_session(ID).ok();
}

/// `attach_session` on a Bound session returns Err(TerminalSessionExists).
///
/// This guard prevents two Emacs buffers from owning the same session
/// simultaneously with competing render loops.
#[test]
fn test_attach_session_already_bound_returns_terminal_session_exists() {
    const ID: u64 = u64::MAX - 22;
    shutdown_session(ID).ok();
    insert_bound_session(ID); // already Bound

    let result = attach_session(ID);
    assert!(
        result.is_err(),
        "attach_session must return Err when the session is already Bound"
    );
    assert!(
        matches!(
            result.unwrap_err(),
            KuroError::State(StateError::TerminalSessionExists)
        ),
        "error must be TerminalSessionExists"
    );

    shutdown_session(ID).ok();
}

/// `detach_session` on a nonexistent ID returns Err(NoTerminalSession).
#[test]
fn test_detach_session_nonexistent_returns_no_session() {
    const ID: u64 = u64::MAX - 23;
    shutdown_session(ID).ok(); // ensure absent

    let result = detach_session(ID);
    assert!(
        result.is_err(),
        "detach_session must return Err for nonexistent ID"
    );
    assert!(
        matches!(
            result.unwrap_err(),
            KuroError::State(StateError::NoTerminalSession)
        ),
        "error must be NoTerminalSession"
    );
}

/// `attach_session` on a nonexistent ID returns Err(NoTerminalSession).
#[test]
fn test_attach_session_nonexistent_returns_no_session() {
    const ID: u64 = u64::MAX - 24;
    shutdown_session(ID).ok(); // ensure absent

    let result = attach_session(ID);
    assert!(
        result.is_err(),
        "attach_session must return Err for nonexistent ID"
    );
    assert!(
        matches!(
            result.unwrap_err(),
            KuroError::State(StateError::NoTerminalSession)
        ),
        "error must be NoTerminalSession"
    );
}

/// `list_sessions` tuple order: (id, command, `is_detached`, `is_alive`) at indices 0..3.
///
/// A Detached session must have `is_detached=true` at index 2 and
/// `is_alive=true` at index 3 (pty:None sessions always report alive).
/// This is the Rust-side mirror of the Elisp nth-index regression test.
#[test]
fn test_list_sessions_tuple_order_detached() {
    const ID: u64 = u64::MAX - 25;
    shutdown_session(ID).ok();
    insert_detached_session(ID); // Detached, command = ""

    let sessions = list_sessions();
    let entry = sessions.iter().find(|(id, ..)| *id == ID);
    assert!(
        entry.is_some(),
        "list_sessions must include the inserted session"
    );

    let (found_id, _command, is_detached, is_alive) = entry.unwrap();
    assert_eq!(*found_id, ID, "index 0 must be the session ID");
    assert!(
        *is_detached,
        "index 2 must be is_detached=true for a Detached session"
    );
    assert!(
        *is_alive,
        "index 3 must be is_alive=true (pty:None reports alive)"
    );

    shutdown_session(ID).ok();
}

/// `list_sessions`: a Bound session has `is_detached=false` at index 2.
#[test]
fn test_list_sessions_bound_session_not_detached() {
    const ID: u64 = u64::MAX - 26;
    shutdown_session(ID).ok();
    insert_bound_session(ID);

    let sessions = list_sessions();
    let entry = sessions.iter().find(|(id, ..)| *id == ID);
    assert!(
        entry.is_some(),
        "list_sessions must include the inserted session"
    );

    let (_, _, is_detached, is_alive) = entry.unwrap();
    assert!(
        !is_detached,
        "index 2 must be is_detached=false for a Bound session"
    );
    assert!(
        *is_alive,
        "index 3 must be is_alive=true for a Bound session with pty:None"
    );

    shutdown_session(ID).ok();
}

/// `list_sessions` does not include the sentinel ID when that ID has been cleaned up.
///
/// This verifies that `shutdown_session` actually removes the entry so the
/// test sentinel IDs do not pollute subsequent `list_sessions` calls.
#[test]
fn test_list_sessions_cleaned_up_id_absent() {
    const ID: u64 = u64::MAX - 27;
    shutdown_session(ID).ok();
    insert_bound_session(ID);
    shutdown_session(ID).ok();

    let sessions = list_sessions();
    assert!(
        sessions.iter().all(|(id, ..)| *id != ID),
        "list_sessions must not include a session that was shut down"
    );
}

/// `list_sessions` includes the non-empty `command` string in tuple index 1.
#[test]
fn test_list_sessions_command_field_included() {
    const ID: u64 = u64::MAX - 28;
    shutdown_session(ID).ok();
    let mut session = make_session();
    session.command = "fish".to_owned();
    TERMINAL_SESSIONS.lock().unwrap().insert(ID, session);

    let sessions = list_sessions();
    let entry = sessions.iter().find(|(id, ..)| *id == ID);
    assert!(
        entry.is_some(),
        "list_sessions must include the inserted session"
    );
    let (_, command, _, _) = entry.unwrap();
    assert_eq!(
        command, "fish",
        "command field must match the session's command string"
    );

    shutdown_session(ID).ok();
}

/// `list_sessions` returns entries for both Bound and Detached sessions.
#[test]
fn test_list_sessions_mixed_bound_and_detached() {
    const BOUND_ID: u64 = u64::MAX - 29;
    const DETACHED_ID: u64 = u64::MAX - 30;
    shutdown_session(BOUND_ID).ok();
    shutdown_session(DETACHED_ID).ok();
    insert_bound_session(BOUND_ID);
    insert_detached_session(DETACHED_ID);

    let sessions = list_sessions();
    let bound_entry = sessions.iter().find(|(id, ..)| *id == BOUND_ID);
    let detached_entry = sessions.iter().find(|(id, ..)| *id == DETACHED_ID);

    assert!(
        bound_entry.is_some(),
        "list_sessions must include the Bound session"
    );
    assert!(
        detached_entry.is_some(),
        "list_sessions must include the Detached session"
    );

    let (_, _, is_detached_b, _) = bound_entry.unwrap();
    let (_, _, is_detached_d, _) = detached_entry.unwrap();
    assert!(!is_detached_b, "Bound session must have is_detached=false");
    assert!(
        *is_detached_d,
        "Detached session must have is_detached=true"
    );

    shutdown_session(BOUND_ID).ok();
    shutdown_session(DETACHED_ID).ok();
}

/// `list_sessions` does NOT reap a detached session whose PTY is None (alive=true).
///
/// The retain predicate `is_detached && !is_alive` must NOT fire for sessions
/// with `pty: None` since `is_process_alive()` returns `true` for those.
/// This is the regression guard for the opportunistic-reap change in FR-D.
#[test]
fn test_list_sessions_live_detached_not_reaped() {
    const ID: u64 = u64::MAX - 31;
    shutdown_session(ID).ok();
    insert_detached_session(ID); // pty: None => is_alive=true

    let sessions = list_sessions();
    let entry = sessions.iter().find(|(id, ..)| *id == ID);
    assert!(
        entry.is_some(),
        "list_sessions must NOT reap a detached session whose PTY reports alive \
         (pty:None sessions always report alive and must survive the retain call)"
    );

    shutdown_session(ID).ok();
}

/// `list_sessions` command field is empty string for sessions created with no command.
#[test]
fn test_list_sessions_command_field_empty_for_no_command() {
    const ID: u64 = u64::MAX - 32;
    shutdown_session(ID).ok();
    insert_bound_session(ID); // make_session sets command = ""

    let sessions = list_sessions();
    let entry = sessions.iter().find(|(id, ..)| *id == ID);
    assert!(entry.is_some(), "session must appear in list_sessions");
    let (_, command, _, _) = entry.unwrap();
    assert_eq!(
        command, "",
        "command field must be empty string when no command was set"
    );

    shutdown_session(ID).ok();
}

/// `detach_session` then `attach_session` round-trips the session state.
///
/// Starting from Bound: detach → Detached → attach → Bound.
/// Both transitions must succeed.
#[test]
fn test_detach_then_attach_round_trips_state() {
    const ID: u64 = u64::MAX - 33;
    shutdown_session(ID).ok();
    insert_bound_session(ID);

    // Bound → Detached
    assert!(
        detach_session(ID).is_ok(),
        "detach_session must succeed from Bound"
    );
    {
        let guard = TERMINAL_SESSIONS.lock().unwrap();
        let session = guard.get(&ID).expect("session must exist after detach");
        assert!(
            session.is_detached(),
            "session must be Detached after detach_session"
        );
    }

    // Detached → Bound
    assert!(
        attach_session(ID).is_ok(),
        "attach_session must succeed from Detached"
    );
    {
        let guard = TERMINAL_SESSIONS.lock().unwrap();
        let session = guard.get(&ID).expect("session must exist after attach");
        assert!(
            !session.is_detached(),
            "session must be Bound (not Detached) after attach_session"
        );
    }

    shutdown_session(ID).ok();
}

/// `detach_session` on an already-detached session is idempotent (succeeds).
///
/// `set_detached()` is unconditional so a second `detach_session` call must
/// return `Ok(())` and leave the session in the Detached state.
#[test]
fn test_detach_session_already_detached_is_idempotent() {
    const ID: u64 = u64::MAX - 34;
    shutdown_session(ID).ok();
    insert_detached_session(ID);

    // Second detach on an already-detached session must succeed.
    let result = detach_session(ID);
    assert!(
        result.is_ok(),
        "detach_session must succeed (idempotent) when session is already Detached"
    );

    // Session must remain Detached.
    let is_detached = TERMINAL_SESSIONS
        .lock()
        .unwrap()
        .get(&ID)
        .is_some_and(super::session::TerminalSession::is_detached);
    assert!(
        is_detached,
        "session must still be Detached after second detach_session call"
    );

    shutdown_session(ID).ok();
}
