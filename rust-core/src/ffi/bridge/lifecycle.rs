//! Session lifecycle: init / `send_key` / resize / shutdown / detach / attach / list

use super::{
    build_emacs_list_from_rev, build_emacs_list_from_values, catch_panic,
    define_session_query_bool, define_session_query_default, query_session, query_session_mut,
};
use crate::ffi::abstraction::{
    attach_session, detach_session, init_session, list_sessions, shutdown_session, PasteText,
};
use emacs::defun;
use emacs::{Env, IntoLisp as _, Result as EmacsResult, Value};

macro_rules! define_catch_panic_true_action {
    ($(#[$attr:meta])* $fn_name:ident, $action:path) => {
        $(#[$attr])*
        #[defun]
        fn $fn_name(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
            catch_panic(env, || {
                $action(session_id)?;
                Ok(true)
            })
        }
    };
}

fn collect_shell_args(env: &Env, shell_args: Value<'_>) -> EmacsResult<Vec<String>> {
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

    Ok(result)
}

fn build_session_list_entry<'e>(
    env: &'e Env,
    id: u64,
    command: String,
    is_detached: bool,
    is_alive: bool,
) -> EmacsResult<Value<'e>> {
    let id_val = (id as i64).into_lisp(env)?;
    let cmd_val = command.into_lisp(env)?;
    let detached_val = is_detached.into_lisp(env)?;
    let alive_val = is_alive.into_lisp(env)?;

    build_emacs_list_from_values(env, [id_val, cmd_val, detached_val, alive_val])
}

/// Initialize Kuro with the given shell command and terminal dimensions.
///
/// Returns the session ID (a positive integer) on success, or nil on failure.
/// The first session returns 1; subsequent sessions return incrementing values.
///
/// ROWS and COLS must match the actual Emacs window dimensions so that the PTY
/// is created with the correct size from the start.  Spawning the shell with the
/// wrong size and then immediately resizing causes a SIGWINCH race: full-screen
/// programs (vim, htop, …) that start before the resize is processed will render
/// using the stale 24×80 geometry and never re-draw correctly.
// `#[defun]` requires owned String for Emacs string arguments — &str is not supported.
#[defun]
fn kuro_core_init<'e>(
    env: &'e Env,
    command: String,
    shell_args: Value<'e>,
    rows: u16,
    cols: u16,
) -> EmacsResult<Value<'e>> {
    let args = collect_shell_args(env, shell_args)?;
    catch_panic(env, move || {
        let session_id = init_session(&command, &args, rows, cols)?;
        Ok(session_id as i64)
    })
}

define_session_query_bool!(
    /// Send key input to the terminal
    kuro_core_send_key,
    |data: String| query_session_mut,
    |session| session.send_input(&data.into_bytes()).is_ok()
);

define_session_query_bool!(
    /// Send pasted text to the terminal using the session's current DEC 2004 mode
    kuro_core_send_paste,
    |data: String| query_session_mut,
    |session| session.send_paste_text(PasteText::new(&data)).is_ok()
);

define_session_query_bool!(
    /// Resize the terminal
    kuro_core_resize,
    |rows: u16, cols: u16| query_session_mut,
    |session| session.resize(rows, cols).is_ok()
);

define_session_query_bool!(
    /// Set the cell pixel size `(width, height)` in points for iTerm2 OSC 1337
    /// `ReportCellSize` replies. Emacs pushes `default-font-width` /
    /// `default-font-height` so size-probing apps see real metrics.
    kuro_core_set_cell_pixel_size,
    |width: u16, height: u16| query_session_mut,
    |session| session.set_cell_pixel_size(width, height)
);

define_catch_panic_true_action!(
    /// Shutdown the terminal session and release all resources.
    ///
    /// Removes the session from the global map, dropping the PTY and killing
    /// the child process.
    kuro_core_shutdown,
    shutdown_session
);

define_catch_panic_true_action!(
    /// Detach a session from its buffer, keeping the PTY process alive.
    ///
    /// The session remains in the global map with `SessionState::Detached`.
    /// Use `kuro-list-sessions` to enumerate detached sessions and
    /// `kuro-core-attach` to reattach one to a new buffer.
    kuro_core_detach,
    detach_session
);

define_catch_panic_true_action!(
    /// Reattach a detached session to a new Emacs buffer.
    ///
    /// Marks the session as `Bound`.  The caller is responsible for setting up
    /// the new buffer (kuro-mode, render loop, etc.) on the Elisp side.
    kuro_core_attach,
    attach_session
);

define_session_query_default!(
    /// Return the PID of the PTY child process for the given session.
    ///
    /// Returns the PID as an integer, or 0 if the session does not exist or
    /// has no PTY (non-Unix builds).
    kuro_core_get_pid,
    0i64,
    query_session,
    |session| i64::from(session.pid().unwrap_or(0))
);

/// List all active terminal sessions.
///
/// Returns a proper list where each element is `(SESSION-ID COMMAND DETACHED-P ALIVE-P)`.
/// SESSION-ID is an integer, COMMAND is a string, DETACHED-P and ALIVE-P are booleans.
#[defun]
fn kuro_core_list_sessions(env: &Env) -> EmacsResult<Value<'_>> {
    let sessions = list_sessions();
    build_emacs_list_from_rev(
        env,
        sessions,
        |env, (id, command, is_detached, is_alive)| {
            build_session_list_entry(env, id, command, is_detached, is_alive)
        },
    )
}
