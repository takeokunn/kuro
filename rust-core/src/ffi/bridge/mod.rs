//! FFI bridge implementation using emacs-module-rs
//!
//! This module provides the primary FFI implementation using the emacs-module-rs crate,
//! with the ability to fall back to raw FFI bindings if needed.

use std::panic::{catch_unwind, AssertUnwindSafe};

use emacs::{Env, IntoLisp, Result as EmacsResult, Value};

use crate::error::KuroError;

macro_rules! define_drain_session_vec_to_lisp {
    ($(#[$attr:meta])* $fn_name:ident, $label:expr, $take:expr, |$env:ident, $item:pat_param| $body:block) => {
        $(#[$attr])*
        #[expect(
            clippy::cast_possible_wrap,
            reason = "row/col are terminal dimensions (≤ 65535); usize→i64 never wraps"
        )]
        #[expect(
            clippy::similar_names,
            reason = "cw_val/ch_val are intentional abbreviations for cell-width and cell-height; renaming would reduce clarity"
        )]
        #[defun]
        fn $fn_name(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
            let values = $crate::ffi::bridge::query_session_data_or_default_mut_with_panic(
                session_id,
                Vec::new,
                || {
                    let _ = env.message(format!("kuro: panic in {}", $label));
                    Vec::new()
                },
                |session| Ok($take(session)),
            );

            $crate::ffi::bridge::build_emacs_list_from_rev(env, values, |$env, $item| $body)
        }
    };
    ($(#[$attr:meta])* $fn_name:ident, $take:expr, |$env:ident, $item:pat_param| $body:block) => {
        $(#[$attr])*
        #[expect(
            clippy::cast_possible_wrap,
            reason = "row/col are terminal dimensions (≤ 65535); usize→i64 never wraps"
        )]
        #[expect(
            clippy::similar_names,
            reason = "cw_val/ch_val are intentional abbreviations for cell-width and cell-height; renaming would reduce clarity"
        )]
        #[defun]
        fn $fn_name(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
            let values = $crate::ffi::bridge::query_session_data_or_default_mut(
                session_id,
                Vec::new(),
                $take,
            );

            $crate::ffi::bridge::build_emacs_list_from_rev(env, values, |$env, $item| $body)
        }
    };
}

mod emacs_impl;
mod events;
mod images;
mod lifecycle;
mod queries;
mod render;

pub use emacs_impl::EmacsModuleFFI;

macro_rules! define_session_query_opt {
    ($(#[$doc:meta])* $fn_name:ident, $query:ident, |$session:ident| $body:block) => {
        $(#[$doc])*
        #[defun]
        fn $fn_name(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
            $query(env, session_id, |$session| $body)
        }
    };
    ($(#[$doc:meta])* $fn_name:ident, $query:ident, |$session:ident| $body:expr) => {
        $(#[$doc])*
        #[defun]
        fn $fn_name(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
            $query(env, session_id, |$session| Ok($body))
        }
    };
}

macro_rules! define_session_query_default {
    ($(#[$doc:meta])* $fn_name:ident, $default:expr, $query:ident, |$session:ident| $body:block) => {
        $(#[$doc])*
        #[defun]
        fn $fn_name(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
            $query(env, session_id, $default, |$session| $body)
        }
    };
    ($(#[$doc:meta])* $fn_name:ident, $default:expr, $query:ident, |$session:ident| $body:expr) => {
        $(#[$doc])*
        #[defun]
        fn $fn_name(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
            $query(env, session_id, $default, |$session| Ok($body))
        }
    };
    ($(#[$doc:meta])* $fn_name:ident, $default:expr, $arg_name:ident : $arg_ty:ty, $query:ident, |$session:ident| $body:block) => {
        $(#[$doc])*
        #[defun]
        fn $fn_name(
            env: &Env,
            session_id: u64,
            $arg_name: $arg_ty,
        ) -> EmacsResult<Value<'_>> {
            $query(env, session_id, $default, |$session| $body)
        }
    };
    ($(#[$doc:meta])* $fn_name:ident, $default:expr, $arg_name:ident : $arg_ty:ty, $query:ident, |$session:ident| $body:expr) => {
        $(#[$doc])*
        #[defun]
        fn $fn_name(
            env: &Env,
            session_id: u64,
            $arg_name: $arg_ty,
        ) -> EmacsResult<Value<'_>> {
            $query(env, session_id, $default, |$session| Ok($body))
        }
    };
}

macro_rules! define_session_query_bool {
    ($(#[$doc:meta])* $fn_name:ident, |$($arg_name:ident : $arg_ty:ty),*| $query:ident, |$session:ident| $body:block) => {
        $(#[$doc])*
        #[defun]
        fn $fn_name(env: &Env, session_id: u64 $(, $arg_name: $arg_ty)*) -> EmacsResult<Value<'_>> {
            $query(env, session_id, false, |$session| $body)
        }
    };
    ($(#[$doc:meta])* $fn_name:ident, |$($arg_name:ident : $arg_ty:ty),*| $query:ident, |$session:ident| $body:expr) => {
        $(#[$doc])*
        #[defun]
        fn $fn_name(env: &Env, session_id: u64 $(, $arg_name: $arg_ty)*) -> EmacsResult<Value<'_>> {
            $query(env, session_id, false, |$session| Ok($body))
        }
    };
}

macro_rules! define_session_data_query_or_false {
    ($(#[$attr:meta])* $fn_name:ident, $label:expr, |$session:ident| $query:block, |$env:ident, $value:pat_param| $value_body:expr) => {
        $(#[$attr])*
        #[defun]
        fn $fn_name(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
            $crate::ffi::bridge::query_session_data_to_lisp_or_false(
                env,
                $label,
                session_id,
                |$session| $query,
                |$value| {
                    let $env = env;
                    $value_body
                },
            )
        }
    };
    ($(#[$attr:meta])* $fn_name:ident, $label:expr, |$session:ident| $query:expr, |$env:ident, $value:pat_param| $value_body:expr) => {
        $(#[$attr])*
        #[defun]
        fn $fn_name(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
            $crate::ffi::bridge::query_session_data_to_lisp_or_false(
                env,
                $label,
                session_id,
                |$session| Ok($query),
                |$value| {
                    let $env = env;
                    $value_body
                },
            )
        }
    };
    ($(#[$attr:meta])* $fn_name:ident, $label:expr, $arg_name:ident : $arg_ty:ty, |$session:ident| $query:block, |$env:ident, $value:pat_param| $value_body:expr) => {
        $(#[$attr])*
        #[defun]
        fn $fn_name(
            env: &Env,
            session_id: u64,
            $arg_name: $arg_ty,
        ) -> EmacsResult<Value<'_>> {
            $crate::ffi::bridge::query_session_data_to_lisp_or_false(
                env,
                $label,
                session_id,
                |$session| $query,
                |$value| {
                    let $env = env;
                    $value_body
                },
            )
        }
    };
    ($(#[$attr:meta])* $fn_name:ident, $label:expr, $arg_name:ident : $arg_ty:ty, |$session:ident| $query:expr, |$env:ident, $value:pat_param| $value_body:expr) => {
        $(#[$attr])*
        #[defun]
        fn $fn_name(
            env: &Env,
            session_id: u64,
            $arg_name: $arg_ty,
        ) -> EmacsResult<Value<'_>> {
            $crate::ffi::bridge::query_session_data_to_lisp_or_false(
                env,
                $label,
                session_id,
                |$session| Ok($query),
                |$value| {
                    let $env = env;
                    $value_body
                },
            )
        }
    };
}

macro_rules! define_session_data_query {
    ($(#[$attr:meta])* $fn_name:ident, $label:expr, |$session:ident| $query:block, |$env:ident, $value:pat_param| $value_body:expr, |$missing_env:ident| $missing_body:expr) => {
        $(#[$attr])*
        #[defun]
        fn $fn_name(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
            $crate::ffi::bridge::query_session_data_to_lisp(
                env,
                $label,
                session_id,
                |$session| $query,
                |$value| {
                    let $env = env;
                    $value_body
                },
                || {
                    let $missing_env = env;
                    $missing_body
                },
            )
        }
    };
    ($(#[$attr:meta])* $fn_name:ident, $label:expr, |$session:ident| $query:expr, |$env:ident, $value:pat_param| $value_body:expr, |$missing_env:ident| $missing_body:expr) => {
        $(#[$attr])*
        #[defun]
        fn $fn_name(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
            $crate::ffi::bridge::query_session_data_to_lisp(
                env,
                $label,
                session_id,
                |$session| Ok($query),
                |$value| {
                    let $env = env;
                    $value_body
                },
                || {
                    let $missing_env = env;
                    $missing_body
                },
            )
        }
    };
    ($(#[$attr:meta])* $fn_name:ident, $label:expr, $arg_name:ident : $arg_ty:ty, |$session:ident| $query:block, |$env:ident, $value:pat_param| $value_body:expr, |$missing_env:ident| $missing_body:expr) => {
        $(#[$attr])*
        #[defun]
        fn $fn_name(
            env: &Env,
            session_id: u64,
            $arg_name: $arg_ty,
        ) -> EmacsResult<Value<'_>> {
            $crate::ffi::bridge::query_session_data_to_lisp(
                env,
                $label,
                session_id,
                |$session| $query,
                |$value| {
                    let $env = env;
                    $value_body
                },
                || {
                    let $missing_env = env;
                    $missing_body
                },
            )
        }
    };
    ($(#[$attr:meta])* $fn_name:ident, $label:expr, $arg_name:ident : $arg_ty:ty, |$session:ident| $query:expr, |$env:ident, $value:pat_param| $value_body:expr, |$missing_env:ident| $missing_body:expr) => {
        $(#[$attr])*
        #[defun]
        fn $fn_name(
            env: &Env,
            session_id: u64,
            $arg_name: $arg_ty,
        ) -> EmacsResult<Value<'_>> {
            $crate::ffi::bridge::query_session_data_to_lisp(
                env,
                $label,
                session_id,
                |$session| Ok($query),
                |$value| {
                    let $env = env;
                    $value_body
                },
                || {
                    let $missing_env = env;
                    $missing_body
                },
            )
        }
    };
}

macro_rules! define_session_data_query_mut {
    ($(#[$attr:meta])* $fn_name:ident, $label:expr, |$session:ident| $query:block, |$env:ident, $value:pat_param| $value_body:expr, |$missing_env:ident| $missing_body:expr) => {
        $(#[$attr])*
        #[defun]
        fn $fn_name(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
            $crate::ffi::bridge::query_session_data_to_lisp_mut(
                env,
                $label,
                session_id,
                |$session| $query,
                |$value| {
                    let $env = env;
                    $value_body
                },
                || {
                    let $missing_env = env;
                    $missing_body
                },
            )
        }
    };
    ($(#[$attr:meta])* $fn_name:ident, $label:expr, |$session:ident| $query:expr, |$env:ident, $value:pat_param| $value_body:expr, |$missing_env:ident| $missing_body:expr) => {
        $(#[$attr])*
        #[defun]
        fn $fn_name(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
            $crate::ffi::bridge::query_session_data_to_lisp_mut(
                env,
                $label,
                session_id,
                |$session| Ok($query),
                |$value| {
                    let $env = env;
                    $value_body
                },
                || {
                    let $missing_env = env;
                    $missing_body
                },
            )
        }
    };
}

pub(super) use define_session_data_query_or_false;
pub(super) use define_session_data_query;
pub(super) use define_session_data_query_mut;
pub(super) use define_session_query_bool;
pub(super) use define_session_query_default;
pub(super) use define_session_query_opt;

/// Outcome of reading raw Rust session data under the bridge lock.
#[derive(Debug)]
pub(super) enum SessionDataOutcome<T> {
    Value(T),
    MissingSession,
    Error(KuroError),
    Panic,
}

pub(super) fn read_session_data<T, F>(session_id: u64, f: F) -> SessionDataOutcome<T>
where
    F: FnOnce(&crate::ffi::abstraction::TerminalSession) -> Result<T, KuroError>,
{
    match catch_unwind(AssertUnwindSafe(
        || match crate::ffi::abstraction::TERMINAL_SESSIONS.lock() {
            Ok(global) => {
                global
                    .get(&session_id)
                    .map_or(SessionDataOutcome::MissingSession, |session| {
                        f(session).map_or_else(SessionDataOutcome::Error, SessionDataOutcome::Value)
                    })
            }
            Err(_) => SessionDataOutcome::Error(KuroError::State(
                crate::ffi::error::StateError::NoTerminalSession,
            )),
        },
    )) {
        Ok(outcome) => outcome,
        Err(_) => SessionDataOutcome::Panic,
    }
}

pub(super) fn read_session_data_mut<T, F>(session_id: u64, f: F) -> SessionDataOutcome<T>
where
    F: FnOnce(&mut crate::ffi::abstraction::TerminalSession) -> Result<T, KuroError>,
{
    match catch_unwind(AssertUnwindSafe(
        || match crate::ffi::abstraction::TERMINAL_SESSIONS.lock() {
            Ok(mut global) => {
                global
                    .get_mut(&session_id)
                    .map_or(SessionDataOutcome::MissingSession, |session| {
                        f(session).map_or_else(SessionDataOutcome::Error, SessionDataOutcome::Value)
                    })
            }
            Err(_) => SessionDataOutcome::Error(KuroError::State(
                crate::ffi::error::StateError::NoTerminalSession,
            )),
        },
    )) {
        Ok(outcome) => outcome,
        Err(_) => SessionDataOutcome::Panic,
    }
}

/// Read mutable raw session data without converting to Lisp values.
///
/// Missing sessions, errors, and panics all fall back to `default`.
pub(super) fn query_session_data_or_default_mut<T, F>(session_id: u64, default: T, f: F) -> T
where
    F: FnOnce(&mut crate::ffi::abstraction::TerminalSession) -> Result<T, KuroError>,
{
    match read_session_data_mut(session_id, f) {
        SessionDataOutcome::Value(value) => value,
        SessionDataOutcome::MissingSession
        | SessionDataOutcome::Error(_)
        | SessionDataOutcome::Panic => default,
    }
}

/// Convert a raw `SessionDataOutcome` into a Lisp value while handling
/// missing-session fallbacks and logging bridge errors/panics consistently.
#[inline]
pub(super) fn session_data_outcome_to_lisp<'e, T, FV, FM>(
    env: &'e Env,
    label: &'static str,
    outcome: SessionDataOutcome<T>,
    on_value: FV,
    on_missing: FM,
) -> EmacsResult<Value<'e>>
where
    FV: FnOnce(T) -> EmacsResult<Value<'e>>,
    FM: FnOnce() -> EmacsResult<Value<'e>>,
{
    match outcome {
        SessionDataOutcome::Value(value) => on_value(value),
        SessionDataOutcome::MissingSession => on_missing(),
        SessionDataOutcome::Error(e) => {
            let msg = format!("kuro: error in {label}: {e}");
            let _ = env.message(&msg);
            false.into_lisp(env)
        }
        SessionDataOutcome::Panic => {
            let _ = env.message(&format!("kuro: panic in {label}"));
            false.into_lisp(env)
        }
    }
}

/// Read session data and convert the result to a Lisp value in one step.
///
/// This keeps the data fetch and Lisp conversion paired at the call site while
/// still centralizing the missing-session and error/panic handling.
#[inline]
pub(super) fn query_session_data_to_lisp<'e, T, F, FV, FM>(
    env: &'e Env,
    label: &'static str,
    session_id: u64,
    f: F,
    on_value: FV,
    on_missing: FM,
) -> EmacsResult<Value<'e>>
where
    F: FnOnce(&crate::ffi::abstraction::TerminalSession) -> Result<T, KuroError>,
    FV: FnOnce(T) -> EmacsResult<Value<'e>>,
    FM: FnOnce() -> EmacsResult<Value<'e>>,
{
    session_data_outcome_to_lisp(
        env,
        label,
        read_session_data(session_id, f),
        on_value,
        on_missing,
    )
}

/// Convenience wrapper for session reads that should return Emacs nil when the
/// session is missing.
#[inline]
pub(super) fn query_session_data_to_lisp_or_false<'e, T, F, FV>(
    env: &'e Env,
    label: &'static str,
    session_id: u64,
    f: F,
    on_value: FV,
) -> EmacsResult<Value<'e>>
where
    F: FnOnce(&crate::ffi::abstraction::TerminalSession) -> Result<T, KuroError>,
    FV: FnOnce(T) -> EmacsResult<Value<'e>>,
{
    query_session_data_to_lisp(env, label, session_id, f, on_value, || false.into_lisp(env))
}

/// Mutable variant of [`query_session_data_to_lisp`].
#[inline]
pub(super) fn query_session_data_to_lisp_mut<'e, T, F, FV, FM>(
    env: &'e Env,
    label: &'static str,
    session_id: u64,
    f: F,
    on_value: FV,
    on_missing: FM,
) -> EmacsResult<Value<'e>>
where
    F: FnOnce(&mut crate::ffi::abstraction::TerminalSession) -> Result<T, KuroError>,
    FV: FnOnce(T) -> EmacsResult<Value<'e>>,
    FM: FnOnce() -> EmacsResult<Value<'e>>,
{
    session_data_outcome_to_lisp(
        env,
        label,
        read_session_data_mut(session_id, f),
        on_value,
        on_missing,
    )
}

/// Read mutable raw session data and surface bridge errors as `Result`.
///
/// Missing sessions fall back to `default`; errors propagate; panics become
/// a standard bridge error for the provided `context`.
#[inline]
pub(super) fn query_session_data_or_error_mut<T, F, M>(
    session_id: u64,
    context: &'static str,
    default: M,
    f: F,
) -> Result<T, KuroError>
where
    F: FnOnce(&mut crate::ffi::abstraction::TerminalSession) -> Result<T, KuroError>,
    M: FnOnce() -> T,
{
    match read_session_data_mut(session_id, f) {
        SessionDataOutcome::Value(value) => Ok(value),
        SessionDataOutcome::MissingSession => Ok(default()),
        SessionDataOutcome::Error(e) => Err(e),
        SessionDataOutcome::Panic => Err(crate::ffi::error::ffi_error(context)),
    }
}

/// Read mutable raw session data and return `default` on missing session or error.
///
/// On panic, runs `on_panic` so callers can keep panic-specific logging local
/// while still reusing the same session-read boundary.
#[inline]
pub(super) fn query_session_data_or_default_mut_with_panic<T, F, P>(
    session_id: u64,
    default: impl Fn() -> T,
    on_panic: P,
    f: F,
) -> T
where
    F: FnOnce(&mut crate::ffi::abstraction::TerminalSession) -> Result<T, KuroError>,
    P: FnOnce() -> T,
{
    match read_session_data_mut(session_id, f) {
        SessionDataOutcome::Value(value) => value,
        SessionDataOutcome::MissingSession | SessionDataOutcome::Error(_) => default(),
        SessionDataOutcome::Panic => on_panic(),
    }
}

/// Catch Rust panics and convert to Emacs errors
fn catch_panic<'e, R, F>(env: &'e Env, f: F) -> EmacsResult<Value<'e>>
where
    R: IntoLisp<'e> + 'static,
    F: std::panic::UnwindSafe + FnOnce() -> std::result::Result<R, KuroError>,
{
    let result = catch_unwind(f);

    match result {
        Ok(Ok(value)) => value.into_lisp(env),
        Ok(Err(e)) => {
            let msg = format!("Kuro error: {e}");
            let _ = env.message(&msg);
            let _ = env.call("error", (msg,));
            false.into_lisp(env)
        }
        Err(panic_payload) => {
            let msg = panic_payload.downcast::<String>().map_or_else(
                |p| {
                    p.downcast::<&'static str>().map_or_else(
                        |_| "Panic: Unknown panic payload".to_owned(),
                        |msg| format!("Panic: {msg}"),
                    )
                },
                |msg| format!("Panic: {msg}"),
            );
            let _ = env.message(&msg);
            let _ = env.call("error", (msg,));
            false.into_lisp(env)
        }
    }
}

/// Build an Emacs proper list from a double-ended iterator in reverse order.
#[inline]
pub(super) fn build_emacs_list_from_rev<'e, I, T, F>(
    env: &'e Env,
    items: I,
    mut build_item: F,
) -> EmacsResult<Value<'e>>
where
    I: IntoIterator<Item = T>,
    I::IntoIter: DoubleEndedIterator,
    F: FnMut(&'e Env, T) -> EmacsResult<Value<'e>>,
{
    let mut list = false.into_lisp(env)?;
    for item in items.into_iter().rev() {
        let value = build_item(env, item)?;
        list = env.cons(value, list)?;
    }
    Ok(list)
}

/// Build an Emacs proper list from already-converted Lisp values.
#[inline]
pub(super) fn build_emacs_list_from_values<'e, I>(env: &'e Env, values: I) -> EmacsResult<Value<'e>>
where
    I: IntoIterator<Item = Value<'e>>,
    I::IntoIter: DoubleEndedIterator,
{
    let mut list = false.into_lisp(env)?;
    for value in values.into_iter().rev() {
        list = env.cons(value, list)?;
    }
    Ok(list)
}

/// Helper for FFI functions that read a single value from a specific session.
///
/// Calls `f(session)` when the session exists; returns `default` otherwise.
/// Wraps in `catch_panic` automatically.
pub(crate) fn query_session<'e, T, F>(
    env: &'e Env,
    session_id: u64,
    default: T,
    f: F,
) -> EmacsResult<Value<'e>>
where
    T: IntoLisp<'e> + std::panic::UnwindSafe + 'static,
    F: FnOnce(&crate::ffi::abstraction::TerminalSession) -> Result<T, KuroError>
        + std::panic::UnwindSafe,
{
    catch_panic(env, || match read_session_data(session_id, f) {
        SessionDataOutcome::Value(value) => Ok(value),
        SessionDataOutcome::MissingSession
        | SessionDataOutcome::Error(_)
        | SessionDataOutcome::Panic => Ok(default),
    })
}

/// Helper for FFI functions that mutate a specific session.
///
/// Calls `f(session)` when the session exists; returns `default` otherwise.
/// Wraps in `catch_panic` automatically.
pub(crate) fn query_session_mut<'e, T, F>(
    env: &'e Env,
    session_id: u64,
    default: T,
    f: F,
) -> EmacsResult<Value<'e>>
where
    T: IntoLisp<'e> + std::panic::UnwindSafe + 'static,
    F: FnOnce(&mut crate::ffi::abstraction::TerminalSession) -> Result<T, KuroError>
        + std::panic::UnwindSafe,
{
    catch_panic(env, || match read_session_data_mut(session_id, f) {
        SessionDataOutcome::Value(value) => Ok(value),
        SessionDataOutcome::MissingSession
        | SessionDataOutcome::Error(_)
        | SessionDataOutcome::Panic => Ok(default),
    })
}

/// Helper for FFI functions returning `Option<T>`.
///
/// Unlike [`query_session_mut`], the closure returns `Result<Option<T>>`.
/// `Some(v)` maps to the corresponding Lisp value; `None` and "no session"
/// both become `false`.
#[inline]
pub(crate) fn query_session_opt<'e, T, F>(
    env: &'e Env,
    session_id: u64,
    f: F,
) -> EmacsResult<Value<'e>>
where
    T: IntoLisp<'e>,
    F: FnOnce(&mut crate::ffi::abstraction::TerminalSession) -> Result<Option<T>, KuroError>
        + std::panic::UnwindSafe,
{
    match read_session_data_mut(session_id, f) {
        SessionDataOutcome::Value(Some(v)) => v.into_lisp(env),
        SessionDataOutcome::Value(None)
        | SessionDataOutcome::MissingSession
        | SessionDataOutcome::Error(_)
        | SessionDataOutcome::Panic => false.into_lisp(env),
    }
}

/// Emacs plugin initialization (called from lib.rs via #[`emacs::module`])
///
/// # Errors
/// Returns `Err` if the Emacs environment rejects the module message.
pub fn module_init(env: &Env) -> EmacsResult<()> {
    env.message("Kuro terminal emulator module loaded")?;
    Ok(())
}

// Test FFI functions are in the dedicated `test_terminal` module.
// See: ffi/test_terminal.rs

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_emacs_module_ffi_is_zero_sized() {
        assert_eq!(std::mem::size_of::<EmacsModuleFFI>(), 0);
    }
}
