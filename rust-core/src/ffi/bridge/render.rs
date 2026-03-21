//! Render polling: dirty lines with face/color data, scrollback, scroll viewport, bell

use std::panic::{catch_unwind, AssertUnwindSafe};
use std::result::Result;

use emacs::defun;
use emacs::{Env, IntoLisp as _, Result as EmacsResult, Value};

use super::{catch_panic, lock_session, query_session, query_session_mut};
use crate::error::KuroError;
use crate::ffi::abstraction::with_session;

/// Poll for terminal updates and return dirty lines
#[defun]
#[expect(
    clippy::cast_possible_wrap,
    reason = "line_no is a terminal row index (≤ 65535); usize→i64 never wraps"
)]
fn kuro_core_poll_updates(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    let result: Result<Vec<(usize, String)>, KuroError> = catch_unwind(AssertUnwindSafe(|| {
        let mut global = lock_session!();

        if let Some(session) = global.get_mut(&session_id) {
            session.poll_output()?;
            Ok(session.get_dirty_lines())
        } else {
            Ok(Vec::new())
        }
    }))
    .unwrap_or_else(|_| Err(crate::ffi::error::ffi_error("panic in poll_updates")));

    match result {
        Ok(dirty_lines) => {
            let mut list = false.into_lisp(env)?;
            for (line_no, text) in dirty_lines.into_iter().rev() {
                let line_no_val = (line_no as i64).into_lisp(env)?;
                let text_val = text.into_lisp(env)?;
                let pair = env.cons(line_no_val, text_val)?;
                list = env.cons(pair, list)?;
            }
            Ok(list)
        }
        Err(e) => {
            let msg = format!("Kuro error: {e}");
            let _ = env.message(&msg);
            let _ = env.call("error", (msg,));
            false.into_lisp(env)
        }
    }
}

/// Poll for terminal updates and return dirty lines with face information
#[defun]
#[expect(
    clippy::cast_possible_wrap,
    reason = "line_no/start_buf/end_buf/offset are terminal indices (≤ 65535); flags is a u64 bitmask (≤ 0x1FF); all fit in i64"
)]
#[expect(
    clippy::significant_drop_tightening,
    reason = "`session` borrows from `global` (MutexGuard) across poll_output + get_dirty_lines_with_faces; the guard cannot be released before the borrow ends"
)]
fn kuro_core_poll_updates_with_faces(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    let result: Result<Vec<crate::ffi::codec::EncodedLine>, KuroError> =
        catch_unwind(AssertUnwindSafe(|| {
            let lines = {
                let mut global = lock_session!();
                let Some(session) = global.get_mut(&session_id) else {
                    return Ok(Vec::new());
                };
                session.poll_output()?;
                session.get_dirty_lines_with_faces()
            };
            Ok(lines)
        }))
        .unwrap_or_else(|_| {
            Err(crate::ffi::error::ffi_error(
                "panic in poll_updates_with_faces",
            ))
        });

    match result {
        Ok(lines) => {
            let mut list = false.into_lisp(env)?;
            for (line_no, text, face_ranges, col_to_buf) in lines.into_iter().rev() {
                let line_no_val = (line_no as i64).into_lisp(env)?;
                let text_val = text.into_lisp(env)?;

                // Convert face ranges to Emacs list of flat (start-buf end-buf fg bg flags) lists
                // NOTE: start/end are now buffer offsets (not grid column indices)
                let mut face_list = false.into_lisp(env)?;
                for (start_buf, end_buf, fg, bg, flags) in face_ranges {
                    let start_val = (start_buf as i64).into_lisp(env)?;
                    let end_val = (end_buf as i64).into_lisp(env)?;
                    let fg_val = i64::from(fg).into_lisp(env)?;
                    let bg_val = i64::from(bg).into_lisp(env)?;
                    let flags_val = (flags as i64).into_lisp(env)?;

                    // Build flat proper list: (start end fg bg flags)
                    let nil = false.into_lisp(env)?;
                    let range_list = env.cons(flags_val, nil)?;
                    let range_list = env.cons(bg_val, range_list)?;
                    let range_list = env.cons(fg_val, range_list)?;
                    let range_list = env.cons(end_val, range_list)?;
                    let range_list = env.cons(start_val, range_list)?;
                    face_list = env.cons(range_list, face_list)?;
                }

                // Build col_to_buf as Emacs vector for cursor placement.
                // When col_to_buf is empty (ASCII fast path from encode_line),
                // return an empty Emacs vector instead of nil so the Elisp
                // (puthash row #() kuro--col-to-buf-map) overwrites any stale
                // CJK mapping for this row, letting the identity fallback apply.
                let col_to_buf_len = col_to_buf.len();
                let col_to_buf_vec = if col_to_buf_len == 0 {
                    // Single make_vector(0) call instead of N+1 calls for ASCII lines.
                    env.make_vector(0, false.into_lisp(env)?)?
                } else {
                    let v = env.make_vector(col_to_buf_len, false.into_lisp(env)?)?;
                    for (i, &offset) in col_to_buf.iter().enumerate() {
                        v.set(i, (offset as i64).into_lisp(env)?)?;
                    }
                    v
                };

                let line_pair = env.cons(line_no_val, text_val)?;
                // line_tuple = ((line_no . text) face_ranges... col_to_buf_vec)
                // We wrap as: ((line_no . text) . (face_list . col_to_buf_vec))
                let line_data = env.cons(line_pair, face_list)?;
                let line_with_ctb = env.cons(line_data, col_to_buf_vec)?;
                list = env.cons(line_with_ctb, list)?;
            }
            Ok(list)
        }
        Err(e) => {
            let msg = format!("Kuro error: {e}");
            let _ = env.message(&msg);
            let _ = env.call("error", (msg,));
            false.into_lisp(env)
        }
    }
}

/// Get scrollback buffer lines
#[defun]
fn kuro_core_get_scrollback(
    env: &Env,
    session_id: u64,
    max_lines: usize,
) -> EmacsResult<Value<'_>> {
    let scrollback_lines: Vec<String> =
        catch_unwind(AssertUnwindSafe(|| -> crate::Result<Vec<String>> {
            let global = lock_session!();
            Ok(global
                .get(&session_id)
                .map(|s| s.get_scrollback(max_lines))
                .unwrap_or_default())
        }))
        .unwrap_or_else(|_| {
            let _ = env.message("kuro: panic in get_scrollback");
            Ok(Vec::new())
        })
        .unwrap_or_default();

    let mut list = false.into_lisp(env)?;
    for line in scrollback_lines.into_iter().rev() {
        let line_val = line.into_lisp(env)?;
        list = env.cons(line_val, list)?;
    }
    Ok(list)
}

/// Clear scrollback buffer
#[defun]
fn kuro_core_clear_scrollback(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    query_session_mut(env, session_id, false, |session| {
        session.clear_scrollback();
        Ok(true)
    })
}

/// Scroll the viewport up by n lines (toward older scrollback content)
#[defun]
fn kuro_core_scroll_up(env: &Env, session_id: u64, n: usize) -> EmacsResult<Value<'_>> {
    catch_panic(env, || {
        with_session(session_id, |session| {
            session.viewport_scroll_up(n);
            Ok(true)
        })
    })
}

/// Scroll the viewport down by n lines (toward live content)
#[defun]
fn kuro_core_scroll_down(env: &Env, session_id: u64, n: usize) -> EmacsResult<Value<'_>> {
    catch_panic(env, || {
        with_session(session_id, |session| {
            session.viewport_scroll_down(n);
            Ok(true)
        })
    })
}

/// Check and clear the pending bell flag atomically.
///
/// Returns `t` if a BEL character has been received since the last call,
/// then unconditionally resets the flag.  Subsequent calls return `nil`
/// until another BEL is received.  Merges the former two-call
/// `kuro-core-bell-pending` + `kuro-core-clear-bell` pattern into a single
/// lock acquisition.
#[defun]
fn kuro_core_take_bell_pending(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    query_session_mut(env, session_id, false, |session| {
        Ok(session.take_bell_pending())
    })
}

/// Set scrollback buffer max lines
#[defun]
fn kuro_core_set_scrollback_max_lines(
    env: &Env,
    session_id: u64,
    max_lines: usize,
) -> EmacsResult<Value<'_>> {
    query_session_mut(env, session_id, false, |session| {
        session.set_scrollback_max_lines(max_lines);
        Ok(true)
    })
}

/// Get scrollback buffer line count
#[defun]
fn kuro_core_get_scrollback_count(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    query_session(env, session_id, 0usize, |session| {
        Ok(session.get_scrollback_count())
    })
}

/// Get the current viewport scroll offset (0 = live view, N = scrolled back N lines)
#[defun]
fn kuro_core_get_scroll_offset(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    catch_panic(env, || {
        with_session(session_id, |session| Ok(session.scroll_offset()))
    })
}

/// Atomically consume pending full-screen scroll event counts and reset them.
///
/// Returns a cons cell `(UP . DOWN)` where UP and DOWN are the number of
/// full-screen scroll-up and scroll-down steps accumulated since the last
/// call.  Returns `nil` when both counts are zero (no-op frame).
///
/// Must be called BEFORE `kuro-core-poll-updates-with-faces` each frame so
/// that Emacs can perform buffer-level line deletion/insertion first,
/// preventing double-rendering of the newly revealed bottom row.
#[defun]
fn kuro_core_consume_scroll_events(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    let (up, down): (u32, u32) = catch_unwind(AssertUnwindSafe(|| -> crate::Result<(u32, u32)> {
        let mut global = lock_session!();
        Ok(global.get_mut(&session_id).map_or(
            (0, 0),
            super::super::abstraction::session::TerminalSession::consume_scroll_events,
        ))
    }))
    .unwrap_or_else(|_| {
        let _ = env.message("kuro: panic in consume_scroll_events");
        Ok((0, 0))
    })
    .unwrap_or((0, 0));

    if up > 0 || down > 0 {
        let up_val = i64::from(up).into_lisp(env)?;
        let down_val = i64::from(down).into_lisp(env)?;
        env.cons(up_val, down_val)
    } else {
        false.into_lisp(env)
    }
}
