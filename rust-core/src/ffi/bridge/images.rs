//! Kitty Graphics Protocol: image store and placement notifications

use super::{
    build_emacs_list_from_values, define_session_data_query_or_false,
};
use emacs::defun;
use emacs::{Env, IntoLisp as _, Result as EmacsResult, Value};

define_session_data_query_or_false!(
    /// Retrieve a stored Kitty Graphics image as a base64-encoded PNG string.
    ///
    /// Returns the base64-encoded PNG string if the image exists, or nil if not found.
        /// The Elisp caller should decode: `(base64-decode-string data t)` to get unibyte PNG bytes
        /// suitable for `(create-image bytes 'png t)`.
        kuro_core_get_image,
        "get_image",
        image_id: u32,
        |session| session.get_image_png_base64(image_id),
        |kuro_env, b64| {
            if b64.is_empty() {
                false.into_lisp(kuro_env)
            } else {
                b64.into_lisp(kuro_env)
            }
        }
    );

// Poll for pending Kitty Graphics image placement notifications.
//
// Returns a list of image placement descriptors, each of the form:
//   (IMAGE-ID ROW COL CELL-WIDTH CELL-HEIGHT)
//
// This is separate from `kuro-core-poll-updates-with-faces` for backward compatibility.
// Call this after `kuro-core-poll-updates-with-faces` to check for new image placements.
define_drain_session_vec_to_lisp!(
    kuro_core_poll_image_notifications,
    |session| { Ok(session.take_pending_image_notifications()) },
    |env, notif| {
        let id_val = i64::from(notif.image_id).into_lisp(env)?;
        let row_val = (notif.row as i64).into_lisp(env)?;
        let col_val = (notif.col as i64).into_lisp(env)?;
        let cw_val = i64::from(notif.cell_width).into_lisp(env)?;
        let ch_val = i64::from(notif.cell_height).into_lisp(env)?;

        build_emacs_list_from_values(env, [id_val, row_val, col_val, cw_val, ch_val])
    }
);
