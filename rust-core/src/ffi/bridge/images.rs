//! Kitty Graphics Protocol: image store and placement notifications

use super::{
    build_emacs_list_from_rev, build_emacs_list_from_values, define_session_data_query_or_false,
    query_session_data_to_lisp_or_false, usize_to_lisp_i64,
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

/// Return the number of Kitty animation frames for an image (0 = still image).
#[defun]
fn kuro_core_image_frame_count(
    env: &Env,
    session_id: u64,
    image_id: u32,
) -> EmacsResult<Value<'_>> {
    query_session_data_to_lisp_or_false(
        env,
        "image_frame_count",
        session_id,
        |session| Ok(session.image_frame_count(image_id)),
        |count| (count as i64).into_lisp(env),
    )
}

/// Render Kitty animation frame `frame_index` (0-based) as a base64 PNG string,
/// or nil when the frame does not exist.
#[defun]
fn kuro_core_image_frame_png(
    env: &Env,
    session_id: u64,
    image_id: u32,
    frame_index: u32,
) -> EmacsResult<Value<'_>> {
    query_session_data_to_lisp_or_false(
        env,
        "image_frame_png",
        session_id,
        |session| Ok(session.image_frame_png_base64(image_id, frame_index as usize)),
        |b64| {
            if b64.is_empty() {
                false.into_lisp(env)
            } else {
                b64.into_lisp(env)
            }
        },
    )
}

/// Return the display gap (ms) for Kitty animation frame `frame_index` (0-based).
#[defun]
fn kuro_core_image_frame_gap(
    env: &Env,
    session_id: u64,
    image_id: u32,
    frame_index: u32,
) -> EmacsResult<Value<'_>> {
    query_session_data_to_lisp_or_false(
        env,
        "image_frame_gap",
        session_id,
        |session| Ok(session.image_frame_gap_ms(image_id, frame_index as usize)),
        |gap| i64::from(gap).into_lisp(env),
    )
}

/// Return Kitty animation playback state as `(PLAYING CURRENT-FRAME LOOP-COUNT)`,
/// where CURRENT-FRAME is 1-based and LOOP-COUNT of 0 means infinite; nil if the
/// image is unknown.
#[defun]
fn kuro_core_image_animation_state(
    env: &Env,
    session_id: u64,
    image_id: u32,
) -> EmacsResult<Value<'_>> {
    query_session_data_to_lisp_or_false(
        env,
        "image_animation_state",
        session_id,
        |session| Ok(session.image_animation_state(image_id)),
        |state| match state {
            Some((playing, current, loops)) => {
                let p = playing.into_lisp(env)?;
                let c = (current as i64).into_lisp(env)?;
                let l = i64::from(loops).into_lisp(env)?;
                build_emacs_list_from_values(env, [p, c, l])
            }
            None => false.into_lisp(env),
        },
    )
}

// Poll for pending Kitty Graphics image placement notifications.
//
// Returns a list of image placement descriptors, each of the form:
//   (IMAGE-ID ROW COL CELL-WIDTH CELL-HEIGHT PIXEL-X-OFFSET PIXEL-Y-OFFSET)
//
// PIXEL-X-OFFSET / PIXEL-Y-OFFSET are the Kitty `X=`/`Y=` cell-internal pixel
// offsets (0 when unset), letting Emacs draw the image shifted inside its anchor
// cell.
//
// This is separate from `kuro-core-poll-updates-with-faces` for backward compatibility.
// Call this after `kuro-core-poll-updates-with-faces` to check for new image placements.
define_drain_session_vec_to_lisp!(
    kuro_core_poll_image_notifications,
    |session| { Ok(session.take_pending_image_notifications()) },
    |env, notif| {
        let id_val = i64::from(notif.image_id).into_lisp(env)?;
        let row_val =
            usize_to_lisp_i64(notif.row, "image notification row must fit i64").into_lisp(env)?;
        let col_val = usize_to_lisp_i64(notif.col, "image notification column must fit i64")
            .into_lisp(env)?;
        let cw_val = i64::from(notif.cell_width).into_lisp(env)?;
        let ch_val = i64::from(notif.cell_height).into_lisp(env)?;
        let px_val = i64::from(notif.pixel_x_offset).into_lisp(env)?;
        let py_val = i64::from(notif.pixel_y_offset).into_lisp(env)?;

        build_emacs_list_from_values(
            env,
            [id_val, row_val, col_val, cw_val, ch_val, px_val, py_val],
        )
    }
);

/// Poll for Kitty Unicode-placeholder (`U+10EEEE`) image regions on the active
/// grid.
///
/// Returns a list of placeholder-region descriptors, each of the form:
///   `(IMAGE-ID PLACEMENT-ID SCREEN-ROW SCREEN-COL CELL-COLS CELL-ROWS IMG-ROW
///    IMG-COL IMG-ROWS IMG-COLS)`
///
/// where SCREEN-ROW/SCREEN-COL are the 0-based top-left of the placeholder
/// rectangle, CELL-COLS×CELL-ROWS its size in terminal cells, IMG-ROW/IMG-COL
/// the image-grid tile origin, and IMG-ROWS×IMG-COLS the total image-grid extent
/// the rectangle covers. Emacs uses these to slice the referenced PNG into
/// per-cell tiles (fit-to-rectangle). Contiguous same-image / same-placement
/// runs are grouped into one rectangle; orphan placeholders (image not stored)
/// are excluded.
///
/// Unlike `kuro-core-poll-image-notifications`, this is a non-draining *query*:
/// it re-derives regions from the grid each call, so the placeholder image
/// survives scrolling/reflow exactly like the underlying text cells.
#[defun]
fn kuro_core_poll_placeholder_placements(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    query_session_data_to_lisp_or_false(
        env,
        "poll_placeholder_placements",
        session_id,
        |session| Ok(session.collect_placeholder_regions()),
        |regions| {
            build_emacs_list_from_rev(env, regions, |env, region| {
                #[expect(
                    clippy::cast_possible_wrap,
                    reason = "screen/cell dimensions are terminal-bounded (≤ 65535); usize→i64 never wraps"
                )]
                let values = [
                    i64::from(region.image_id).into_lisp(env)?,
                    i64::from(region.placement_id).into_lisp(env)?,
                    (region.screen_row as i64).into_lisp(env)?,
                    (region.screen_col as i64).into_lisp(env)?,
                    (region.cell_cols as i64).into_lisp(env)?,
                    (region.cell_rows as i64).into_lisp(env)?,
                    i64::from(region.img_row).into_lisp(env)?,
                    i64::from(region.img_col).into_lisp(env)?,
                    i64::from(region.img_rows).into_lisp(env)?,
                    i64::from(region.img_cols).into_lisp(env)?,
                ];
                build_emacs_list_from_values(env, values)
            })
        },
    )
}
