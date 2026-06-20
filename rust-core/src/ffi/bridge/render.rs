//! Render polling: dirty lines with face/color data, scrollback, scroll viewport, bell

use emacs::defun;
use emacs::{Env, IntoLisp as _, Result as EmacsResult, Value};

use super::{
    build_emacs_list_from_rev, build_emacs_list_from_values, define_session_query_default,
    query_session, query_session_data_or_default_mut_with_panic, query_session_mut,
};
use crate::error::KuroError;

mod helpers;

use self::helpers::{
    build_emacs_poll_updates_with_faces_line, build_emacs_vector_from_iter, poll_binary_direct,
    poll_dirty_lines, poll_encoded_lines,
};

macro_rules! define_poll_updates_handler {
    ($(#[$attr:meta])* $fn_name:ident, $label:expr, $poll:expr, |$env:ident, $value:pat_param| $success:block) => {
        $(#[$attr])*
        #[defun]
        fn $fn_name(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
            match $poll(session_id, $label) {
                Ok($value) => {
                    let $env = env;
                    $success
                }
                Err(e) => emit_error(env, &e),
            }
        }
    };
}

/// Signal a Kuro error to Emacs and return `nil`.
///
/// Called from every FFI render function on the error path.  Emits an Emacs
/// `message` (visible in *Messages*) followed by `(error …)` to signal a
/// non-fatal Lisp condition, then returns `false` (nil) to Emacs.
#[inline]
fn emit_error<'e>(env: &'e Env, e: &KuroError) -> EmacsResult<Value<'e>> {
    let msg = format!("Kuro error: {e}");
    let _ = env.message(&msg);
    let _ = env.call("error", (msg,));
    false.into_lisp(env)
}

define_poll_updates_handler!(
    /// Poll for terminal updates and return dirty lines
    #[expect(
        clippy::cast_possible_wrap,
        reason = "line_no is a terminal row index (≤ 65535); usize→i64 never wraps"
    )]
    kuro_core_poll_updates,
    "panic in poll_updates",
    poll_dirty_lines,
    |env, dirty_lines| {
        build_emacs_list_from_rev(env, dirty_lines, |env, (line_no, text)| {
            let line_no_val = (line_no as i64).into_lisp(env)?;
            let text_val = text.into_lisp(env)?;
            build_emacs_list_from_values(env, [line_no_val, text_val])
        })
    }
);

define_poll_updates_handler!(
    /// Poll for terminal updates and return dirty lines with face information.
    ///
    /// # 1-frame latency between reading and rendering
    ///
    /// This function calls `poll_output()` followed by
    /// `get_dirty_lines_with_faces()` in a single lock acquisition:
    ///
    /// - **`poll_output()`** reads new bytes from the PTY channel and feeds them
    ///   into the parser/grid, which may mark additional lines as dirty.
    /// - **`get_dirty_lines_with_faces()`** returns (and clears) the lines that
    ///   were marked dirty by *previous* `poll_output()` calls.
    ///
    /// Consequently, bytes read in *this* call will not appear in the returned
    /// dirty set — they will surface as dirty lines in the *next* render cycle.
    /// This is correct behaviour: the worst-case additional latency is bounded
    /// to `1 / frame_rate` (typically ≤ 16 ms at 60 fps), which is imperceptible.
    #[expect(
        clippy::cast_possible_wrap,
        reason = "line_no/start_buf/end_buf/offset are terminal indices (≤ 65535); flags is a u64 bitmask (≤ 0x1FF); all fit in i64"
    )]
    kuro_core_poll_updates_with_faces,
    "panic in poll_updates_with_faces",
    poll_encoded_lines,
    |env, lines| {
        build_emacs_list_from_rev(env, lines, build_emacs_poll_updates_with_faces_line)
    }
);

define_poll_updates_handler!(
    /// Poll for terminal updates and return a binary-encoded frame as an Emacs vector.
    ///
    /// Returns an Emacs vector of integers (each element is a byte value 0–255)
    /// encoding the dirty line data in the binary frame format defined in
    /// `crate::ffi::codec::encode_screen_binary`.
    ///
    /// Using an Emacs vector of fixnums avoids the GC pressure from thousands of
    /// cons-cell allocations per frame that `kuro_core_poll_updates_with_faces`
    /// produces, at the cost of a slightly more complex Elisp decoder.
    ///
    /// Returns `nil` (`false`) when no dirty lines are present.
    #[expect(
        clippy::cast_possible_wrap,
        reason = "line_no/start_buf/end_buf/offset are terminal indices (≤ 65535); flags is a u64 bitmask (≤ 0x1FF); all fit in i64"
    )]
    kuro_core_poll_updates_binary,
    "panic in poll_updates_binary",
    poll_encoded_lines,
    |env, lines| {
        if lines.is_empty() {
            return false.into_lisp(env);
        }
        let bytes = crate::ffi::codec::encode_screen_binary(&lines);
        build_emacs_vector_from_iter(
            env,
            bytes.len(),
            0i64.into_lisp(env)?,
            bytes,
            |env, byte| i64::from(byte).into_lisp(env),
        )
    }
);

define_poll_updates_handler!(
    /// Poll for terminal updates and return a cons `(text-strings . binary-face-data)`.
    ///
    /// This is a text-decode-optimised companion to `kuro_core_poll_updates_binary`.
    /// Instead of embedding UTF-8 bytes in the binary frame (requiring the Elisp
    /// side to perform a `make-string` + `dotimes aset` loop + `decode-coding-string`
    /// triple-copy decode), this function:
    ///
    /// - Returns row text as **native Emacs strings** via `env.into_lisp(text)`,
    ///   crossing the FFI boundary without any extra byte-by-byte copy on the Lisp side.
    /// - Returns face/color/col-to-buf data in the same compact binary format as
    ///   `kuro_core_poll_updates_binary`, so the optimised binary decoder continues
    ///   to apply for those fields.
    ///
    /// Return value: a cons cell `(TEXT-STRINGS . BINARY-DATA)` where:
    /// - `TEXT-STRINGS` is an Emacs vector of strings, one entry per dirty row,
    ///   in the same order as the rows encoded in `BINARY-DATA`.
    /// - `BINARY-DATA` is an Emacs vector of byte fixnums identical to what
    ///   `kuro_core_poll_updates_binary` would return, **except** the `text_byte_len`
    ///   header field is always 0 and no text bytes are written for any row (the
    ///   strings are provided via `TEXT-STRINGS` instead).
    ///
    /// Returns `nil` (`false`) when no dirty lines are present.
    #[expect(
        clippy::cast_possible_wrap,
        reason = "line_no/start_buf/end_buf/offset are terminal indices (≤ 65535); flags is a u64 bitmask (≤ 0x1FF); all fit in i64"
    )]
    kuro_core_poll_updates_binary_with_strings,
    "panic in poll_updates_binary_with_strings",
    poll_binary_direct,
    |env, (texts, bytes)| {
        if texts.is_empty() {
            return false.into_lisp(env);
        }

        let strings_vec = build_emacs_vector_from_iter(
            env,
            texts.len(),
            false.into_lisp(env)?,
            texts,
            |env, text| text.as_str().into_lisp(env),
        )?;
        let bytes_vec = build_emacs_vector_from_iter(
            env,
            bytes.len(),
            0i64.into_lisp(env)?,
            bytes,
            |env, byte| i64::from(byte).into_lisp(env),
        )?;

        // Return a true cons cell `(TEXT-STRINGS . BINARY-DATA)` as documented:
        // the Elisp decoder (`kuro--poll-updates-binary-optimised`) reads
        // `(cdr result)` AS the binary vector. Using `build_emacs_list_from_values`
        // here would instead produce the 2-element list `(TEXT-STRINGS BINARY-DATA)`,
        // whose `cdr` is `(BINARY-DATA)` — a list, not the vector — causing the
        // decoder to throw `wrong-type-argument arrayp` every frame and leaving the
        // terminal buffer blank under the default `kuro-use-binary-ffi` path.
        env.cons(strings_vec, bytes_vec)
    }
);

define_session_query_default!(
    /// Clear scrollback buffer
    kuro_core_clear_scrollback,
    false,
    query_session_mut,
    |session| {
        session.clear_scrollback();
        Ok(true)
    }
);

define_session_query_default!(
    /// Scroll the viewport up by n lines (toward older scrollback content)
    kuro_core_scroll_up,
    false,
    n: usize,
    query_session_mut,
    |session| {
        session.viewport_scroll_up(n);
        Ok(true)
    }
);

define_session_query_default!(
    /// Scroll the viewport down by n lines (toward live content)
    kuro_core_scroll_down,
    false,
    n: usize,
    query_session_mut,
    |session| {
        session.viewport_scroll_down(n);
        Ok(true)
    }
);

define_session_query_default!(
    /// Check and clear the pending bell flag atomically.
    ///
    /// Returns `t` if a BEL character has been received since the last call,
    /// then unconditionally resets the flag.  Subsequent calls return `nil`
    /// until another BEL is received.  Merges the former two-call
    /// `kuro-core-bell-pending` + `kuro-core-clear-bell` pattern into a single
    /// lock acquisition.
    kuro_core_take_bell_pending,
    false,
    query_session_mut,
    |session| session.take_bell_pending()
);

define_session_query_default!(
    /// Set scrollback buffer max lines
    kuro_core_set_scrollback_max_lines,
    false,
    max_lines: usize,
    query_session_mut,
    |session| {
        session.set_scrollback_max_lines(max_lines);
        Ok(true)
    }
);

define_session_query_default!(
    /// Get scrollback buffer line count
    kuro_core_get_scrollback_count,
    0usize,
    query_session,
    |session| session.get_scrollback_count()
);

define_session_query_default!(
    /// Get the current viewport scroll offset (0 = live view, N = scrolled back N lines)
    kuro_core_get_scroll_offset,
    0usize,
    query_session,
    |session| session.scroll_offset()
);

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
    use crate::ffi::abstraction::TerminalSession;
    let (up, down): (u32, u32) = query_session_data_or_default_mut_with_panic(
        session_id,
        || (0, 0),
        || {
            let _ = env.message("kuro: panic in consume_scroll_events");
            (0, 0)
        },
        |session| Ok(TerminalSession::consume_scroll_events(session)),
    );

    if up > 0 || down > 0 {
        let up_val = i64::from(up).into_lisp(env)?;
        let down_val = i64::from(down).into_lisp(env)?;
        build_emacs_list_from_values(env, [up_val, down_val])
    } else {
        false.into_lisp(env)
    }
}
