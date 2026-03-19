//! Regression tests for SPC cursor movement and trailing-space preservation.
//!
//! These tests guard against the following bug that was introduced and fixed:
//!
//!   encode_line() was trimming trailing spaces from the rendered text before
//!   sending it to Emacs.  kuro--update-cursor computes the buffer position as
//!   `(min (+ line-start col) line-end)`.  After trimming, line-end was
//!   smaller than the cursor column when the cursor was inside whitespace,
//!   so the visual cursor was clamped to the wrong (non-space) column.
//!
//!   Symptom: pressing SPC at a bash prompt didn't visually move the cursor.
//!
//! DO NOT add trim_end_matches logic back to encode_line or get_dirty_lines
//! without also fixing the Emacs-side cursor computation.

use crate::ffi::codec::encode_line;

/// Typing a single space must advance the cursor by one column.
///
/// This is the minimal reproduction of the original bug: pressing SPC at a
/// bash prompt left the cursor at col 0 because the echoed space was trimmed
/// from the line text, making line-end == 0 and clamping the cursor.
#[test]
fn test_spc_advances_cursor_col_by_one() {
    let mut term = super::make_term();
    term.advance(b" ");
    assert_eq!(
        term.cursor_col(),
        1,
        "cursor col must be 1 after printing one space (SPC regression)"
    );
}

/// Multiple spaces must all advance the cursor correctly.
#[test]
fn test_multiple_spaces_advance_cursor() {
    let mut term = super::make_term();
    term.advance(b"   ");
    assert_eq!(
        term.cursor_col(),
        3,
        "cursor col must be 3 after printing three spaces"
    );
}

/// Text followed by trailing spaces: cursor lands after the last space.
///
/// Reproduces: typing "echo hello " (with trailing space) must leave the
/// cursor at col 11, not col 10 (which would be the trimmed position).
#[test]
fn test_cursor_col_after_text_then_space() {
    let mut term = super::make_term();
    term.advance(b"echo hello ");
    assert_eq!(
        term.cursor_col(),
        11,
        "cursor col must be 11 after 'echo hello ' (10 chars + 1 trailing space)"
    );
}

/// encode_line must preserve trailing spaces so the Emacs buffer line is
/// at least as long as the terminal cursor column.
#[test]
fn test_encode_line_preserves_trailing_spaces_for_cursor() {
    let mut term = super::make_term();
    // Print text then a space — the space is now the cursor position
    term.advance(b"$ ");
    let cursor_col = term.cursor_col(); // should be 2
    assert_eq!(cursor_col, 2);

    let line = term.screen.get_line(0).expect("line 0 must exist");
    let (text, _, _) = encode_line(&line.cells);

    // The encoded text must be at least cursor_col characters long so that
    // `(+ line-start cursor_col)` never exceeds `line-end-position`.
    assert!(
        text.len() >= cursor_col,
        "encoded text length ({}) must be >= cursor_col ({}) — \
         trimming trailing spaces would break kuro--update-cursor",
        text.len(),
        cursor_col
    );
}

/// A line consisting entirely of spaces must not encode as an empty string.
///
/// When the terminal is freshly initialized, all cells are spaces.  If
/// encode_line collapsed such a line to "", every cursor-update call would
/// clamp to col 0.
#[test]
fn test_blank_line_is_not_empty_after_encode() {
    let term = super::make_term();
    let line = term.screen.get_line(0).expect("line 0 must exist");
    let (text, _, _) = encode_line(&line.cells);
    // A blank 80-column line: encoded text must be 80 spaces, not "".
    assert_eq!(
        text.len(),
        80,
        "a blank 80-col line must encode to 80 spaces, not an empty string"
    );
}

/// Spaces appearing between non-space characters must be preserved.
/// (These were never trimmed, but guard against regressions in internal
/// run-length logic that could accidentally collapse middle spans.)
#[test]
fn test_internal_spaces_preserved() {
    let mut term = super::make_term();
    term.advance(b"foo   bar");
    let cell_space = term.get_cell(0, 3).expect("cell at (0,3) must exist");
    assert_eq!(
        cell_space.char(),
        ' ',
        "space at col 3 in 'foo   bar' must be stored in the grid"
    );
    let line = term.screen.get_line(0).expect("line 0 must exist");
    let (text, _, _) = encode_line(&line.cells);
    assert!(
        text.starts_with("foo   bar"),
        "encoded text must start with 'foo   bar' (spaces preserved), got: {:?}",
        &text[..text.len().min(20)]
    );
}
