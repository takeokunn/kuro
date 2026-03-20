//! Kitty Graphics Protocol: image store and placement notifications

use super::lock_session;
use crate::error::KuroError;
use emacs::defun;
use emacs::{Env, IntoLisp as _, Result as EmacsResult, Value};

/// Retrieve a stored Kitty Graphics image as a base64-encoded PNG string.
///
/// Returns the base64-encoded PNG string if the image exists, or nil if not found.
/// The Elisp caller should decode: `(base64-decode-string data t)` to get unibyte PNG bytes
/// suitable for `(create-image bytes 'png t)`.
#[defun]
fn kuro_core_get_image(env: &Env, session_id: u64, image_id: u32) -> EmacsResult<Value<'_>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = lock_session!();
        global.get(&session_id)
            .map_or_else(|| Ok(String::new()), |session| Ok::<String, KuroError>(session.get_image_png_base64(image_id)))
    }));
    match result {
        Ok(Ok(b64)) => {
            if b64.is_empty() {
                false.into_lisp(env)
            } else {
                b64.into_lisp(env)
            }
        }
        Ok(Err(e)) => {
            let _ = env.message(format!("kuro: error in get_image: {e}"));
            false.into_lisp(env)
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_image");
            false.into_lisp(env)
        }
    }
}

/// Poll for pending Kitty Graphics image placement notifications.
///
/// Returns a list of image placement descriptors, each of the form:
///   (IMAGE-ID ROW COL CELL-WIDTH CELL-HEIGHT)
///
/// This is separate from `kuro-core-poll-updates-with-faces` for backward compatibility.
/// Call this after `kuro-core-poll-updates-with-faces` to check for new image placements.
#[defun]
#[expect(clippy::cast_possible_wrap, reason = "row/col are terminal dimensions (≤ 65535); usize→i64 never wraps")]
#[expect(clippy::similar_names, reason = "cw_val/ch_val are intentional abbreviations for cell-width and cell-height; renaming would reduce clarity")]
fn kuro_core_poll_image_notifications(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    let notifications = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut global = lock_session!();
        global.get_mut(&session_id)
            .map_or_else(|| Ok(Vec::new()), |session| Ok::<Vec<_>, KuroError>(session.take_pending_image_notifications()))
    }))
    .unwrap_or_else(|_| Ok(Vec::new()))
    .unwrap_or_default();

    // Build Elisp list: each item is (image-id row col cell-width cell-height)
    let mut list = false.into_lisp(env)?;
    for notif in notifications.into_iter().rev() {
        let id_val = i64::from(notif.image_id).into_lisp(env)?;
        let row_val = (notif.row as i64).into_lisp(env)?;
        let col_val = (notif.col as i64).into_lisp(env)?;
        let cw_val = i64::from(notif.cell_width).into_lisp(env)?;
        let ch_val = i64::from(notif.cell_height).into_lisp(env)?;

        // Build proper list: (image-id row col cell-width cell-height)
        let nil = false.into_lisp(env)?;
        let item = env.cons(ch_val, nil)?;
        let item = env.cons(cw_val, item)?;
        let item = env.cons(col_val, item)?;
        let item = env.cons(row_val, item)?;
        let item = env.cons(id_val, item)?;
        list = env.cons(item, list)?;
    }
    Ok(list)
}
