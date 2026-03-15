//! Render polling: dirty lines with face/color data, scrollback, scroll viewport, bell

use super::{catch_panic, lock_session};
use crate::error::KuroError;
use crate::ffi::abstraction::with_session;
use emacs::defun;
use emacs::{Env, IntoLisp, Result as EmacsResult, Value};

/// Poll for terminal updates and return dirty lines
#[defun]
fn kuro_core_poll_updates<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result: std::result::Result<Vec<(usize, String)>, KuroError> =
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let mut global = lock_session!();

            if let Some(ref mut session) = *global {
                session.poll_output()?;
                Ok(session.get_dirty_lines())
            } else {
                Ok(Vec::new())
            }
        }))
        .unwrap_or_else(|_| Err(KuroError::Ffi("panic in poll_updates".to_string())));

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
            let msg = match e {
                KuroError::Pty(msg) => format!("PTY error: {}", msg),
                KuroError::Ffi(msg) => format!("FFI error: {}", msg),
                KuroError::Parser(msg) => format!("Parser error: {}", msg),
                _ => format!("Error: {}", e),
            };
            let _ = env.message(&msg);
            let _ = env.call("error", (msg,));
            false.into_lisp(env)
        }
    }
}

/// Poll for terminal updates and return dirty lines with face information
#[defun]
#[allow(clippy::type_complexity)]
fn kuro_core_poll_updates_with_faces<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result: std::result::Result<
        Vec<(
            usize,
            String,
            Vec<(usize, usize, u32, u32, u64)>,
            Vec<usize>,
        )>,
        KuroError,
    > = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut global = lock_session!();

        if let Some(ref mut session) = *global {
            session.poll_output()?;
            Ok(session.get_dirty_lines_with_faces())
        } else {
            Ok(Vec::new())
        }
    }))
    .unwrap_or_else(|_| {
        Err(KuroError::Ffi(
            "panic in poll_updates_with_faces".to_string(),
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
                    let fg_val = (fg as i64).into_lisp(env)?;
                    let bg_val = (bg as i64).into_lisp(env)?;
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

                // Build col_to_buf as Emacs vector for cursor placement
                let col_to_buf_len = col_to_buf.len();
                let col_to_buf_vec = env.make_vector(col_to_buf_len, false.into_lisp(env)?)?;
                for (i, &offset) in col_to_buf.iter().enumerate() {
                    col_to_buf_vec.set(i, (offset as i64).into_lisp(env)?)?;
                }

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
            let msg = match e {
                KuroError::Pty(msg) => format!("PTY error: {}", msg),
                KuroError::Ffi(msg) => format!("FFI error: {}", msg),
                KuroError::Parser(msg) => format!("Parser error: {}", msg),
                _ => format!("Error: {}", e),
            };
            let _ = env.message(&msg);
            let _ = env.call("error", (msg,));
            false.into_lisp(env)
        }
    }
}

/// Get scrollback buffer lines
#[defun]
fn kuro_core_get_scrollback<'e>(env: &'e Env, max_lines: usize) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = lock_session!();
        if let Some(ref session) = *global {
            Ok::<Vec<String>, KuroError>(session.get_scrollback(max_lines))
        } else {
            Ok(Vec::new())
        }
    }));
    match result {
        Ok(Ok(scrollback_lines)) => {
            let mut list = false.into_lisp(env)?;
            for line in scrollback_lines.into_iter().rev() {
                let line_val = line.into_lisp(env)?;
                list = env.cons(line_val, list)?;
            }
            Ok(list)
        }
        Ok(Err(e)) => {
            let _ = env.message(format!("kuro: error in get_scrollback: {}", e));
            false.into_lisp(env)
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_scrollback");
            false.into_lisp(env)
        }
    }
}

/// Clear scrollback buffer
#[defun]
fn kuro_core_clear_scrollback<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    catch_panic(env, || {
        let mut global = lock_session!();
        if let Some(ref mut session) = *global {
            session.clear_scrollback();
            Ok(true)
        } else {
            Ok(false)
        }
    })
}

/// Scroll the viewport up by n lines (toward older scrollback content)
#[defun]
fn kuro_core_scroll_up<'e>(env: &'e Env, n: usize) -> EmacsResult<Value<'e>> {
    catch_panic(env, || {
        with_session(|session| {
            session.viewport_scroll_up(n);
            Ok(true)
        })
    })
}

/// Scroll the viewport down by n lines (toward live content)
#[defun]
fn kuro_core_scroll_down<'e>(env: &'e Env, n: usize) -> EmacsResult<Value<'e>> {
    catch_panic(env, || {
        with_session(|session| {
            session.viewport_scroll_down(n);
            Ok(true)
        })
    })
}

/// Check whether a BEL character has been received and not yet cleared
#[defun]
fn kuro_core_bell_pending<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    catch_panic(env, || {
        let global = lock_session!();
        if let Some(ref session) = *global {
            Ok(session.core.bell_pending)
        } else {
            Ok(false)
        }
    })
}

/// Clear the pending bell flag
#[defun]
fn kuro_core_clear_bell<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    catch_panic(env, || {
        let mut global = lock_session!();
        if let Some(ref mut session) = *global {
            session.core.bell_pending = false;
            Ok(true)
        } else {
            Ok(false)
        }
    })
}

/// Set scrollback buffer max lines
#[defun]
fn kuro_core_set_scrollback_max_lines<'e>(
    env: &'e Env,
    max_lines: usize,
) -> EmacsResult<Value<'e>> {
    catch_panic(env, || {
        let mut global = lock_session!();
        if let Some(ref mut session) = *global {
            session.set_scrollback_max_lines(max_lines);
            Ok(true)
        } else {
            Ok(false)
        }
    })
}

/// Get scrollback buffer line count
#[defun]
fn kuro_core_get_scrollback_count<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    catch_panic(env, || {
        let global = lock_session!();
        if let Some(ref session) = *global {
            Ok(session.get_scrollback_count())
        } else {
            Ok(0)
        }
    })
}

/// Get the current viewport scroll offset (0 = live view, N = scrolled back N lines)
#[defun]
fn kuro_core_get_scroll_offset<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    catch_panic(env, || with_session(|session| Ok(session.scroll_offset())))
}
