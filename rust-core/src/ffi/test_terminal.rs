//! Test FFI Functions — Direct TerminalCore access without PTY
//!
//! These functions expose the terminal core to Emacs Lisp for testing purposes.
//! They work directly with `TerminalCore` without spawning a PTY process, which
//! avoids the session-killing issues when running tests in batch Emacs.
//!
//! All exported functions follow the `kuro-core-test-*` naming convention
//! and are only intended for use in ERT test suites.

use crate::error::KuroError;
use crate::TerminalCore;
use emacs::defun;
use emacs::{Env, IntoLisp, Result as EmacsResult, Value};
use std::panic::catch_unwind;
use std::sync::Mutex;

/// Global test terminal storage (no PTY).
///
/// Holds a single `TerminalCore` for test use. Created via
/// [`kuro_core_test_create`] and destroyed via [`kuro_core_test_destroy`].
static TEST_TERMINAL: Mutex<Option<TerminalCore>> = Mutex::new(None);

/// Catch Rust panics and convert them to Emacs errors, for test terminal functions.
fn catch_panic_test<'e, R, F>(env: &'e Env, f: F) -> EmacsResult<Value<'e>>
where
    R: IntoLisp<'e> + 'static,
    F: std::panic::UnwindSafe + FnOnce() -> std::result::Result<R, KuroError>,
{
    match catch_unwind(f) {
        Ok(Ok(value)) => value.into_lisp(env),
        Ok(Err(e)) => {
            let msg = format!("kuro test error: {}", e);
            let _ = env.message(&msg);
            let _ = env.call("error", (msg,));
            false.into_lisp(env)
        }
        Err(panic_payload) => {
            let msg = match panic_payload.downcast::<String>() {
                Ok(s) => format!("kuro test panic: {}", s),
                Err(p) => match p.downcast::<&'static str>() {
                    Ok(s) => format!("kuro test panic: {}", s),
                    Err(_) => "kuro test panic: unknown payload".to_string(),
                },
            };
            let _ = env.message(&msg);
            let _ = env.call("error", (msg,));
            false.into_lisp(env)
        }
    }
}

/// Lock `TEST_TERMINAL` with a descriptive error message on poison.
macro_rules! lock_test {
    (mut $guard:ident) => {
        TEST_TERMINAL
            .lock()
            .map_err(|e| KuroError::Ffi(format!("TEST_TERMINAL mutex poisoned: {}", e)))?
    };
    ($guard:ident) => {
        TEST_TERMINAL
            .lock()
            .map_err(|e| KuroError::Ffi(format!("TEST_TERMINAL mutex poisoned: {}", e)))?
    };
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

/// Create a test terminal without PTY for Emacs Lisp testing.
///
/// This creates a `TerminalCore` directly without spawning a PTY process.
/// Used for vttest-style compliance testing from ERT.
#[defun]
fn kuro_core_test_create<'e>(env: &'e Env, rows: u16, cols: u16) -> EmacsResult<Value<'e>> {
    catch_panic_test(env, || {
        let terminal = TerminalCore::new(rows, cols);
        let mut global = lock_test!(mut global);
        *global = Some(terminal);
        Ok(true)
    })
}

/// Destroy the test terminal and free resources.
#[defun]
fn kuro_core_test_destroy<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    catch_panic_test(env, || {
        let mut global = lock_test!(mut global);
        *global = None;
        Ok(true)
    })
}

/// Feed raw bytes directly to the test terminal VTE parser.
///
/// DATA is a Lisp string whose byte representation is fed to `advance()`.
#[defun]
fn kuro_core_test_feed<'e>(env: &'e Env, data: String) -> EmacsResult<Value<'e>> {
    catch_panic_test(env, || {
        let bytes = data.into_bytes();
        let mut global = lock_test!(mut global);
        if let Some(ref mut terminal) = *global {
            terminal.advance(&bytes);
            Ok(true)
        } else {
            Ok(false)
        }
    })
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

/// Get cursor position as `(ROW . COL)` (0-indexed).
#[defun]
fn kuro_core_test_get_cursor<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = lock_test!(global);
        let (row, col) = if let Some(ref t) = *global {
            let c = t.screen.cursor();
            (c.row, c.col)
        } else {
            (0, 0)
        };
        Ok::<(usize, usize), KuroError>((row, col))
    }));
    match result {
        Ok(Ok((row, col))) => {
            let r = (row as i64).into_lisp(env)?;
            let c = (col as i64).into_lisp(env)?;
            env.cons(r, c)
        }
        Ok(Err(e)) => {
            let _ = env.message(format!("kuro: test-get-cursor error: {}", e));
            env.cons(0i64.into_lisp(env)?, 0i64.into_lisp(env)?)
        }
        Err(_) => {
            let _ = env.message("kuro: panic in test-get-cursor");
            env.cons(0i64.into_lisp(env)?, 0i64.into_lisp(env)?)
        }
    }
}

/// Get the grapheme string at `(ROW, COL)`, or `""` if out of bounds.
#[defun]
fn kuro_core_test_get_cell<'e>(env: &'e Env, row: usize, col: usize) -> EmacsResult<Value<'e>> {
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = lock_test!(global);
        let s = if let Some(ref t) = *global {
            t.screen
                .get_cell(row, col)
                .map(|c| c.grapheme.as_str().to_string())
                .unwrap_or_default()
        } else {
            String::new()
        };
        Ok::<String, KuroError>(s)
    }));
    match result {
        Ok(Ok(s)) => s.into_lisp(env),
        Ok(Err(e)) => {
            let _ = env.message(format!("kuro: test-get-cell error: {}", e));
            "".into_lisp(env)
        }
        Err(_) => {
            let _ = env.message("kuro: panic in test-get-cell");
            "".into_lisp(env)
        }
    }
}

/// Get the content of line `ROW` as a trimmed string.
#[defun]
fn kuro_core_test_get_line<'e>(env: &'e Env, row: usize) -> EmacsResult<Value<'e>> {
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = lock_test!(global);
        let s = if let Some(ref t) = *global {
            t.screen
                .get_line(row)
                .map(|line| {
                    let mut buf = String::new();
                    for cell in &line.cells {
                        buf.push_str(cell.grapheme.as_str());
                    }
                    buf.trim_end().to_string()
                })
                .unwrap_or_default()
        } else {
            String::new()
        };
        Ok::<String, KuroError>(s)
    }));
    match result {
        Ok(Ok(s)) => s.into_lisp(env),
        Ok(Err(e)) => {
            let _ = env.message(format!("kuro: test-get-line error: {}", e));
            "".into_lisp(env)
        }
        Err(_) => {
            let _ = env.message("kuro: panic in test-get-line");
            "".into_lisp(env)
        }
    }
}

/// Get the scroll region as `(TOP . BOTTOM)` (0-indexed, inclusive).
///
/// Returns `(0 . 23)` if no test terminal is active.
#[defun]
fn kuro_core_test_get_scroll_region<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = lock_test!(global);
        let (top, bottom) = if let Some(ref t) = *global {
            let r = t.screen.get_scroll_region();
            (r.top, r.bottom.saturating_sub(1))
        } else {
            (0, 23)
        };
        Ok::<(usize, usize), KuroError>((top, bottom))
    }));
    match result {
        Ok(Ok((top, bottom))) => {
            let t = (top as i64).into_lisp(env)?;
            let b = (bottom as i64).into_lisp(env)?;
            env.cons(t, b)
        }
        Ok(Err(e)) => {
            let _ = env.message(format!("kuro: test-get-scroll-region error: {}", e));
            env.cons(0i64.into_lisp(env)?, 23i64.into_lisp(env)?)
        }
        Err(_) => {
            let _ = env.message("kuro: panic in test-get-scroll-region");
            env.cons(0i64.into_lisp(env)?, 23i64.into_lisp(env)?)
        }
    }
}

/// Get terminal dimensions as `(ROWS . COLS)`.
///
/// Returns `(24 . 80)` if no test terminal is active.
#[defun]
fn kuro_core_test_get_size<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = lock_test!(global);
        let (rows, cols) = if let Some(ref t) = *global {
            (t.screen.rows() as usize, t.screen.cols() as usize)
        } else {
            (24, 80)
        };
        Ok::<(usize, usize), KuroError>((rows, cols))
    }));
    match result {
        Ok(Ok((rows, cols))) => {
            let r = (rows as i64).into_lisp(env)?;
            let c = (cols as i64).into_lisp(env)?;
            env.cons(r, c)
        }
        Ok(Err(e)) => {
            let _ = env.message(format!("kuro: test-get-size error: {}", e));
            env.cons(24i64.into_lisp(env)?, 80i64.into_lisp(env)?)
        }
        Err(_) => {
            let _ = env.message("kuro: panic in test-get-size");
            env.cons(24i64.into_lisp(env)?, 80i64.into_lisp(env)?)
        }
    }
}

// ---------------------------------------------------------------------------
// Mutations
// ---------------------------------------------------------------------------

/// Resize the test terminal to `(ROWS, COLS)`.
#[defun]
fn kuro_core_test_resize<'e>(env: &'e Env, rows: u16, cols: u16) -> EmacsResult<Value<'e>> {
    catch_panic_test(env, || {
        let mut global = lock_test!(mut global);
        if let Some(ref mut t) = *global {
            t.screen.resize(rows, cols);
            Ok(true)
        } else {
            Ok(false)
        }
    })
}
