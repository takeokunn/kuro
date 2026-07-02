//! Helpers for render polling and Emacs output assembly.

use emacs::{Env, IntoLisp as _, Result as EmacsResult, Value};

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
fn build_emacs_face_ranges_vector<'e>(
    env: &'e Env,
    ranges: Vec<crate::ffi::codec::EncodedFaceRange>,
) -> EmacsResult<Value<'e>> {
    let vec = env.make_vector(ranges.len() * 6, 0i64.into_lisp(env)?)?;
    for (idx, range) in ranges.into_iter().enumerate() {
        let base = idx * 6;
        vec.set(base, (range.start_buf as i64).into_lisp(env)?)?;
        vec.set(base + 1, (range.end_buf as i64).into_lisp(env)?)?;
        vec.set(base + 2, i64::from(range.fg).into_lisp(env)?)?;
        vec.set(base + 3, i64::from(range.bg).into_lisp(env)?)?;
        vec.set(base + 4, (range.flags as i64).into_lisp(env)?)?;
        vec.set(base + 5, i64::from(range.underline_color).into_lisp(env)?)?;
    }
    vec.into_lisp(env)
}

#[inline]
pub(super) fn build_emacs_poll_updates_with_faces_line<'e>(
    env: &'e Env,
    line: crate::ffi::codec::EncodedLine,
) -> EmacsResult<Value<'e>> {
    let line_no_val = (line.row_index as i64).into_lisp(env)?;
    let text_val = line.text.into_lisp(env)?;
    let face_ranges_vec = build_emacs_face_ranges_vector(env, line.face_ranges)?;

    let col_to_buf_vec = build_emacs_vector_from_iter(
        env,
        line.col_to_buf.len(),
        false.into_lisp(env)?,
        line.col_to_buf,
        |env, offset| (offset as i64).into_lisp(env),
    )?;

    build_emacs_vector_from_iter(
        env,
        4,
        false.into_lisp(env)?,
        [line_no_val, text_val, face_ranges_vec, col_to_buf_vec],
        |_env, value| Ok(value),
    )
}
