//! Helpers for render polling and Emacs output assembly.

use emacs::{Env, IntoLisp as _, Result as EmacsResult, Value};

use super::{build_emacs_list_from_rev, build_emacs_list_from_values};
use crate::error::KuroError;
use crate::ffi::bridge::query_session_data_or_error_mut;

#[inline]
fn poll_session_data_after_output<T, F, M>(
    session_id: u64,
    context: &'static str,
    default: M,
    f: F,
) -> Result<T, KuroError>
where
    F: FnOnce(&mut crate::ffi::abstraction::TerminalSession) -> Result<T, KuroError>,
    M: FnOnce() -> T,
{
    query_session_data_or_error_mut(session_id, context, default, |session| {
        session.poll_output()?;
        f(session)
    })
}

#[inline]
pub(super) fn poll_encoded_lines(
    session_id: u64,
    context: &'static str,
) -> Result<Vec<crate::ffi::codec::EncodedLine>, KuroError> {
    poll_session_data_after_output(session_id, context, Vec::new, |session| {
        Ok(session.get_dirty_lines_with_faces())
    })
}

/// Poll dirty lines using the single-pass binary-direct encoding.
///
/// Shared by `kuro_core_poll_updates_with_faces` and
/// `kuro_core_poll_updates_binary`.  Returns `Vec::new()` when the session
/// does not exist.
#[inline]
pub(super) fn poll_binary_direct(
    session_id: u64,
    context: &'static str,
) -> Result<(Vec<String>, Vec<u8>), KuroError> {
    poll_session_data_after_output(
        session_id,
        context,
        || (Vec::new(), Vec::new()),
        |session| Ok(session.get_dirty_lines_binary_direct()),
    )
}

/// Poll dirty lines and return the standard `(row, text)` pairs.
#[inline]
pub(super) fn poll_dirty_lines(
    session_id: u64,
    context: &'static str,
) -> Result<Vec<(usize, String)>, KuroError> {
    poll_session_data_after_output(session_id, context, Vec::new, |session| {
        Ok(session.get_dirty_lines())
    })
}

/// Build an Emacs vector from an iterator of values.
#[inline]
pub(super) fn build_emacs_vector_from_iter<'e, I, T, F>(
    env: &'e Env,
    len: usize,
    init: Value<'e>,
    items: I,
    mut build_item: F,
) -> EmacsResult<Value<'e>>
where
    I: IntoIterator<Item = T>,
    F: FnMut(&'e Env, T) -> EmacsResult<Value<'e>>,
{
    let vec = env.make_vector(len, init)?;
    for (idx, item) in items.into_iter().enumerate() {
        vec.set(idx, build_item(env, item)?)?;
    }
    vec.into_lisp(env)
}

#[inline]
fn build_emacs_face_range<'e>(
    env: &'e Env,
    (start_buf, end_buf, fg, bg, flags, ul_color): (usize, usize, u32, u32, u64, u32),
) -> EmacsResult<Value<'e>> {
    let start_val = (start_buf as i64).into_lisp(env)?;
    let end_val = (end_buf as i64).into_lisp(env)?;
    let fg_val = i64::from(fg).into_lisp(env)?;
    let bg_val = i64::from(bg).into_lisp(env)?;
    let flags_val = (flags as i64).into_lisp(env)?;
    let ul_color_val = i64::from(ul_color).into_lisp(env)?;

    build_emacs_list_from_values(
        env,
        [start_val, end_val, fg_val, bg_val, flags_val, ul_color_val],
    )
}

#[inline]
pub(super) fn build_emacs_poll_updates_with_faces_line<'e>(
    env: &'e Env,
    (line_no, text, face_ranges, col_to_buf): crate::ffi::codec::EncodedLine,
) -> EmacsResult<Value<'e>> {
    let line_no_val = (line_no as i64).into_lisp(env)?;
    let text_val = text.into_lisp(env)?;

    let face_list = build_emacs_list_from_rev(env, face_ranges, build_emacs_face_range)?;

    let col_to_buf_vec = build_emacs_vector_from_iter(
        env,
        col_to_buf.len(),
        false.into_lisp(env)?,
        col_to_buf,
        |env, offset| (offset as i64).into_lisp(env),
    )?;

    let line_pair = build_emacs_list_from_values(env, [line_no_val, text_val])?;
    let line_data = build_emacs_list_from_values(env, [line_pair, face_list])?;
    build_emacs_list_from_values(env, [line_data, col_to_buf_vec])
}
