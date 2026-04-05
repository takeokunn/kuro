//! Session lifecycle: init / `send_key` / resize / shutdown / detach / attach / list

use super::{catch_panic, query_session};
use crate::ffi::abstraction::{
    attach_session, detach_session, init_session, list_sessions, shutdown_session, with_session,
};
use emacs::defun;
use emacs::{Env, IntoLisp as _, Result as EmacsResult, Value};

/// Initialize Kuro with the given shell command and terminal dimensions.
///
/// Returns the session ID (a non-negative integer) on success, or nil on failure.
/// The first session returns 0; subsequent sessions return incrementing values.
///
/// ROWS and COLS must match the actual Emacs window dimensions so that the PTY
/// is created with the correct size from the start.  Spawning the shell with the
/// wrong size and then immediately resizing causes a SIGWINCH race: full-screen
/// programs (vim, htop, …) that start before the resize is processed will render
/// using the stale 24×80 geometry and never re-draw correctly.
// `#[defun]` requires owned String for Emacs string arguments — &str is not supported.
#[expect(
    clippy::cast_possible_wrap,
    reason = "session_id is a monotonically increasing counter starting at 0; will never reach i64::MAX in practice"
)]
#[defun]
fn kuro_core_init<'e>(
    env: &'e Env,
    command: String,
    shell_args: Value<'e>,
    rows: u16,
    cols: u16,
) -> EmacsResult<Value<'e>> {
    // Convert Emacs list of strings to Vec<String> before entering catch_panic.
    // env.call() returns emacs::Result, so ? works here in the EmacsResult context.
    // `nil` (empty list) is the base case; each iteration takes car/cdr.
    let args: Vec<String> = {
        let mut result = Vec::new();
        let mut remaining = shell_args;
        loop {
            // `(null remaining)` returns t when remaining is nil (end of list).
            if env.call("null", [remaining])?.is_not_nil() {
                break;
            }
            let car = env.call("car", [remaining])?;
            let s: String = car.into_rust()?;
            result.push(s);
            remaining = env.call("cdr", [remaining])?;
        }
        result
    };
    catch_panic(env, move || {
        let session_id = init_session(&command, &args, rows, cols)?;
        Ok(session_id as i64)
    })
}

/// Send key input to the terminal
#[defun]
fn kuro_core_send_key(env: &Env, session_id: u64, data: String) -> EmacsResult<Value<'_>> {
    let byte_vec: Vec<u8> = data.into_bytes();
    catch_panic(env, || {
        Ok(with_session(session_id, |session| session.send_input(&byte_vec)).is_ok())
    })
}

/// Resize the terminal
#[defun]
fn kuro_core_resize(env: &Env, session_id: u64, rows: u16, cols: u16) -> EmacsResult<Value<'_>> {
    catch_panic(env, || {
        Ok(with_session(session_id, |session| session.resize(rows, cols)).is_ok())
    })
}

/// Shutdown the terminal session and release all resources.
///
/// Removes the session from the global map, dropping the PTY and killing
/// the child process.
#[defun]
fn kuro_core_shutdown(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    catch_panic(env, || {
        shutdown_session(session_id)?;
        Ok(true)
    })
}

/// Detach a session from its buffer, keeping the PTY process alive.
///
/// The session remains in the global map with `SessionState::Detached`.
/// Use `kuro-list-sessions` to enumerate detached sessions and
/// `kuro-core-attach` to reattach one to a new buffer.
#[defun]
fn kuro_core_detach(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    catch_panic(env, || {
        detach_session(session_id)?;
        Ok(true)
    })
}

/// Reattach a detached session to a new Emacs buffer.
///
/// Marks the session as `Bound`.  The caller is responsible for setting up
/// the new buffer (kuro-mode, render loop, etc.) on the Elisp side.
#[defun]
fn kuro_core_attach(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    catch_panic(env, || {
        attach_session(session_id)?;
        Ok(true)
    })
}

/// Return the PID of the PTY child process for the given session.
///
/// Returns the PID as an integer, or 0 if the session does not exist or
/// has no PTY (non-Unix builds).
#[defun]
fn kuro_core_get_pid(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    query_session(env, session_id, 0i64, |session| {
        Ok(i64::from(session.pid().unwrap_or(0)))
    })
}

/// List all active terminal sessions.
///
/// Returns a proper list where each element is `(SESSION-ID COMMAND DETACHED-P ALIVE-P)`.
/// SESSION-ID is an integer, COMMAND is a string, DETACHED-P and ALIVE-P are booleans.
#[defun]
#[expect(
    clippy::cast_possible_wrap,
    reason = "session IDs are small monotonically increasing counters; will never reach i64::MAX"
)]
fn kuro_core_list_sessions(env: &Env) -> EmacsResult<Value<'_>> {
    let sessions = list_sessions();
    let mut list = false.into_lisp(env)?;
    for (id, command, is_detached, is_alive) in sessions.into_iter().rev() {
        let id_val = (id as i64).into_lisp(env)?;
        let cmd_val = command.into_lisp(env)?;
        let detached_val = is_detached.into_lisp(env)?;
        let alive_val = is_alive.into_lisp(env)?;

        let nil = false.into_lisp(env)?;
        let entry = env.cons(alive_val, nil)?;
        let entry = env.cons(detached_val, entry)?;
        let entry = env.cons(cmd_val, entry)?;
        let entry = env.cons(id_val, entry)?;
        list = env.cons(entry, list)?;
    }
    Ok(list)
}
