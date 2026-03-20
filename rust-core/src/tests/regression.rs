//! Regression tests for SPC cursor movement, trailing-space preservation,
//! and DEC pending wrap (DECAWM last-column flag).
//!
//! ## SPC / trailing-space regression
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
//!
//! ## Pending wrap regression (btop / TUI rendering)
//!
//!   print() was immediately wrapping and scrolling when a character was
//!   written at the last column.  DEC VT terminals defer this wrap: the
//!   cursor stays at the last column with a "pending wrap" flag, and the
//!   actual wrap + scroll only fires when the *next* printable character
//!   arrives.  Without this, full-screen TUI apps like btop that carefully
//!   place characters at the last column get an extra unwanted scroll,
//!   shifting the entire display up by one row.
//!
//!   Symptom: btop showed "disk root" twice / display shifted up by 1.

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

/// Feed captured btop output in chunks and report the first divergence.
/// Reads /tmp/btop-capture.bin and prints row 0 at 10K intervals.
/// Run with: cargo test btop_render -- --ignored --nocapture
#[test]
#[ignore]
fn test_btop_render_dump() {
    let data = match std::fs::read("/tmp/btop-capture.bin") {
        Ok(d) => d,
        Err(_) => {
            eprintln!("SKIP: /tmp/btop-capture.bin not found");
            return;
        }
    };

    // Feed in 1K chunks between 30K-40K to find exact divergence point
    let chunk_size = 1000;
    let mut term = crate::TerminalCore::new(40, 120);
    let mut parser = vte::Parser::new();
    let mut offset = 0;
    while offset < data.len() {
        let end = (offset + chunk_size).min(data.len());
        parser.advance(&mut term, &data[offset..end]);
        offset = end;

        if let Some(line) = term.screen.get_line(0) {
            let text: String = line.cells.iter().map(|c| c.char()).collect();
            let trimmed = text.trim_end();
            let end_idx = trimmed.char_indices().nth(40).map(|(i, _)| i).unwrap_or(trimmed.len());
            let starts_with = &trimmed[..end_idx];
            eprintln!("@{:6}: |{}|", end, starts_with);
        }
    }

    // Full dump at the end
    eprintln!("\n--- Final screen dump (40x120) ---");
    for row in 0..40usize {
        if let Some(line) = term.screen.get_line(row) {
            let text: String = line.cells.iter().map(|c| c.char()).collect();
            eprintln!("{:02}: |{}|", row, text.trim_end());
        }
    }
    eprintln!("cursor: ({}, {}), alt: {}", term.screen.cursor().row, term.screen.cursor().col, term.screen.is_alternate_screen_active());
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

// ── Pending wrap (DECAWM last-column flag) tests ────────────────────

/// Printing at the last column must NOT immediately scroll.
///
/// This is the root cause of the btop rendering bug: btop writes a box-drawing
/// character at (last_row, last_col), which should NOT cause a scroll.  The
/// scroll should only happen when the next printable character arrives.
#[test]
fn test_pending_wrap_no_immediate_scroll() {
    let mut term = crate::TerminalCore::new(5, 10);
    // Fill row 0 with 'A' so we can detect if it scrolls away
    term.advance(b"\x1b[1;1HAAAAAAAAAA");
    // Move to last row, last column
    term.advance(b"\x1b[5;10H");
    assert_eq!(term.cursor_row(), 4);
    assert_eq!(term.cursor_col(), 9);
    // Print one char at the last cell
    term.advance(b"X");
    // Cursor should stay at last column (pending wrap), NOT scroll
    assert_eq!(
        term.cursor_col(),
        9,
        "cursor must stay at col 9 (last col) with pending wrap set"
    );
    assert_eq!(
        term.cursor_row(),
        4,
        "cursor must stay at row 4 (last row) — no scroll yet"
    );
    // Row 0 must still have 'A' — no scroll has happened
    let cell = term.get_cell(0, 0).expect("cell at (0,0)");
    assert_eq!(
        cell.char(),
        'A',
        "row 0 must still contain 'A' — pending wrap must NOT cause an immediate scroll"
    );
}

/// The next printable character after pending wrap must trigger the deferred wrap.
#[test]
fn test_pending_wrap_fires_on_next_print() {
    let mut term = crate::TerminalCore::new(5, 10);
    // Fill row 0 with 'A'
    term.advance(b"\x1b[1;1HAAAAAAAAAA");
    // Fill row 1 with 'B'
    term.advance(b"\x1b[2;1HBBBBBBBBBB");
    // Move to last row, last col, print X (sets pending wrap)
    term.advance(b"\x1b[5;10HX");
    // Now print Y — this must trigger the deferred wrap + scroll
    term.advance(b"Y");
    // After scroll: old row 0 ('A') is gone, old row 1 ('B') is now row 0
    let cell = term.get_cell(0, 0).expect("cell at (0,0)");
    assert_eq!(
        cell.char(),
        'B',
        "row 0 must now be 'B' — the deferred wrap scrolled the screen up"
    );
    // Y should be at the new last row, col 0
    assert_eq!(term.cursor_row(), 4);
    assert_eq!(term.cursor_col(), 1, "cursor must be at col 1 after 'Y'");
}

/// Cursor movement (CUP) must clear pending wrap without scrolling.
///
/// This is critical for TUI apps: btop writes at the last cell, then
/// immediately repositions the cursor with CUP.  If pending wrap is
/// not cleared, the next print would cause a spurious scroll.
#[test]
fn test_cursor_move_clears_pending_wrap() {
    let mut term = crate::TerminalCore::new(5, 10);
    // Fill row 0
    term.advance(b"\x1b[1;1HAAAAAAAAAA");
    // Print at last cell (sets pending wrap)
    term.advance(b"\x1b[5;10HX");
    // Move cursor explicitly — must clear pending wrap
    term.advance(b"\x1b[1;1H");
    assert_eq!(term.cursor_row(), 0);
    assert_eq!(term.cursor_col(), 0);
    // Print at (0,0) — must NOT trigger a scroll
    term.advance(b"Z");
    let cell = term.get_cell(0, 0).expect("cell at (0,0)");
    assert_eq!(
        cell.char(),
        'Z',
        "after CUP clears pending wrap, printing at (0,0) must overwrite, not scroll"
    );
}

/// CR (carriage return) must clear pending wrap.
#[test]
fn test_cr_clears_pending_wrap() {
    let mut term = crate::TerminalCore::new(5, 10);
    term.advance(b"\x1b[1;1HAAAAAAAAAA");
    // Set pending wrap
    term.advance(b"\x1b[5;10HX");
    // CR
    term.advance(b"\r");
    assert_eq!(term.cursor_col(), 0);
    // Print — should NOT scroll
    term.advance(b"Z");
    let cell = term.get_cell(0, 0).expect("cell at (0,0)");
    assert_eq!(cell.char(), 'A', "CR must clear pending wrap; row 0 must be intact");
}

/// BS (backspace) must clear pending wrap.
#[test]
fn test_bs_clears_pending_wrap() {
    let mut term = crate::TerminalCore::new(5, 10);
    // Set pending wrap at last cell of row 4
    term.advance(b"\x1b[5;10HX");
    // BS
    term.advance(b"\x08");
    assert_eq!(term.cursor_col(), 8, "BS from col 9 should go to col 8");
    // Verify pending wrap was cleared by printing — no scroll should occur
    term.advance(b"Q");
    assert_eq!(term.cursor_col(), 9);
}

/// Simulates the btop TUI pattern: fill last row with box-drawing chars,
/// then reposition cursor — must not cause spurious scrolling.
///
/// This is the exact pattern that btop uses: CSI 40;120H followed by a
/// box-drawing char (╯) at the absolute last cell of a 40×120 screen.
/// After writing, btop repositions with CUP, and no scroll should occur.
#[test]
fn test_btop_last_cell_pattern() {
    let mut term = crate::TerminalCore::new(40, 120);
    // Switch to alternate screen (like btop does)
    term.advance(b"\x1b[?1049h");
    // Fill row 0 with recognizable content
    term.advance(b"\x1b[1;1H");
    term.advance(b"CPU_HEADER_ROW_0_CONTENT");
    // Move to last cell and write a box-drawing char
    term.advance(b"\x1b[40;120H");
    term.advance("╯".as_bytes());
    // Verify: cursor at last col, row 0 intact (no scroll)
    assert_eq!(term.cursor_row(), 39);
    assert_eq!(term.cursor_col(), 119);
    let cell = term.get_cell(0, 0).expect("cell at (0,0)");
    assert_eq!(
        cell.char(),
        'C',
        "row 0 must still start with 'C' from 'CPU_HEADER...' — no spurious scroll"
    );
    // Now reposition cursor (like btop does after drawing the box)
    term.advance(b"\x1b[1;1H");
    // Print something — must NOT scroll
    term.advance(b"Z");
    let cell = term.get_cell(0, 0).expect("cell at (0,0)");
    assert_eq!(
        cell.char(),
        'Z',
        "after CUP clears pending wrap, overwriting (0,0) must work without scrolling"
    );
}

/// Line feed must clear pending wrap.
#[test]
fn test_lf_clears_pending_wrap() {
    let mut term = crate::TerminalCore::new(5, 10);
    term.advance(b"\x1b[1;1HAAAAAAAAAA");
    // Set pending wrap at last cell of row 0
    term.advance(b"\x1b[1;10HX");
    // LF — should clear pending wrap and move down (not cause double-advance)
    term.advance(b"\n");
    assert_eq!(term.cursor_row(), 1, "LF after pending wrap: cursor at row 1");
    assert_eq!(term.cursor_col(), 9, "LF should not change column");
}
