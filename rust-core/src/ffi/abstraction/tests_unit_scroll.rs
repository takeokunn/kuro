use super::*;

// ---------------------------------------------------------------------------
// Scrollback viewport: get_dirty_lines_with_faces paths (dirty.rs lines ~30-52)
// ---------------------------------------------------------------------------

/// When the viewport is scrolled back and `scroll_dirty` is set,
/// `get_dirty_lines_with_faces` must return scrollback content for all rows
/// rather than live screen content.
#[test]
fn test_scrollback_viewport_dirty_returns_scrollback_content() {
    let mut session = make_session();

    // Write a distinctive marker, then scroll the screen enough to push
    // it into scrollback (advance 24 newlines after the marker so the
    // marker line is pushed off the top of the 24-row screen).
    session.core.advance(b"SCROLLBACK_MARKER");
    // 24 newlines push the marker line into the scrollback buffer.
    let newlines = b"\n".repeat(24);
    session.core.advance(&newlines);

    // There must now be scrollback content.
    assert!(
        session.core.screen.scrollback_line_count > 0,
        "scrollback buffer must be non-empty after scrolling 24 lines"
    );

    // Clear live dirty state so only the viewport path fires.
    session.core.screen.take_dirty_lines();

    // Scroll the viewport up by 1 to enter the scrollback view.
    // This sets scroll_offset > 0 and raises scroll_dirty.
    session.viewport_scroll_up(1);
    assert!(
        session.core.screen.scroll_offset() > 0,
        "scroll_offset must be > 0 after viewport_scroll_up"
    );
    assert!(
        session.core.screen.is_scroll_dirty(),
        "scroll_dirty must be true after viewport_scroll_up"
    );

    // get_dirty_lines_with_faces must return exactly `rows` entries
    // (one per viewport row) from the scrollback path.
    let rows = session.core.screen.rows() as usize;
    let result = session.get_dirty_lines_with_faces();
    assert_eq!(
        result.len(),
        rows,
        "scrollback viewport path must return {} lines (one per row), got {}",
        rows,
        result.len()
    );

    // scroll_dirty must be cleared after the call.
    assert!(
        !session.core.screen.is_scroll_dirty(),
        "scroll_dirty must be cleared after get_dirty_lines_with_faces"
    );
}

/// When the viewport is scrolled back but `scroll_dirty` is false (no new
/// scroll event), `get_dirty_lines_with_faces` must suppress live dirty lines
/// to preserve the scrollback view.
#[test]
fn test_scrollback_not_dirty_suppresses_live_lines() {
    let mut session = make_session();

    // Push content into scrollback.
    session.core.advance(b"LIVE_CONTENT");
    let newlines = b"\n".repeat(24);
    session.core.advance(&newlines);

    // Enter scrollback view (raises scroll_dirty).
    session.viewport_scroll_up(1);
    assert!(session.core.screen.is_scroll_dirty());

    // Consume the scroll_dirty by calling get_dirty_lines_with_faces once.
    let _ = session.get_dirty_lines_with_faces();
    assert!(
        !session.core.screen.is_scroll_dirty(),
        "scroll_dirty must be false after first get_dirty_lines_with_faces"
    );

    // Now write new live content — this marks live rows dirty.
    session.core.advance(b"NEW_LIVE_CONTENT");
    // Confirm live rows are dirty.
    assert!(
        !session.core.screen.take_dirty_lines().is_empty(),
        "live rows should be dirty after advance"
    );

    // Mark them dirty again (take consumed them above; re-mark for the test).
    session.core.advance(b"X");

    // With scroll_offset > 0 and scroll_dirty == false, the suppression
    // branch must fire: result must be empty.
    let result = session.get_dirty_lines_with_faces();
    assert!(
        result.is_empty(),
        "get_dirty_lines_with_faces must return empty vec when scrolled back \
         but scroll_dirty is false (suppression branch), got {} lines",
        result.len()
    );
}

/// Full-screen `scroll_up` accumulates `pending_scroll_up` shift events.
///
/// The binary drain transmits the shift in the same frame as the dirty rows
/// (atomically, under one FFI call), so Emacs replays the scroll as a cheap
/// buffer edit and only the newly exposed rows are repainted.
#[test]
fn test_consume_scroll_events_accumulates_after_full_screen_scroll() {
    let mut session = make_session();

    // Fill the screen so the cursor sits at the bottom margin, then drain
    // whatever scrolls the fill produced to establish a clean baseline.
    for _ in 0..24 {
        session.core.advance(b"line\n");
    }
    session.consume_scroll_events();

    // Each further line feed at the bottom margin is one full-screen scroll.
    session.core.advance(b"line\n");
    session.core.advance(b"line\n");

    let (up, down) = session.consume_scroll_events();
    assert_eq!(
        up, 2,
        "each full-screen scroll must accumulate pending_scroll_up"
    );
    assert_eq!(down, 0, "no scroll-down events expected");

    // full_dirty must NOT be set: only the shifted-in rows are dirty.
    assert!(
        !session.core.screen.is_full_dirty(),
        "full-screen scroll must not force a full repaint"
    );
}

/// Full-screen `scroll_down` accumulates `pending_scroll_down` shift events.
///
/// Reverse index (RI) at the top margin on a full-screen scroll region
/// records a downward shift; the exposed top rows are the only dirty rows.
#[test]
fn test_consume_scroll_events_accumulates_scroll_down() {
    let mut session = make_session();

    // ESC [ r        — DECSTBM: scroll region = full screen
    // ESC [ 1 ; 1 H  — CUP: move cursor to top-left
    // ESC M          — RI: reverse index — scrolls content down at top margin
    session.core.advance(b"\x1b[r\x1b[1;1H\x1bM\x1bM\x1bM");

    let (up, down) = session.consume_scroll_events();
    assert_eq!(up, 0, "no scroll-up events expected after RI-only input");
    assert_eq!(
        down, 3,
        "each RI-driven full-screen scroll must accumulate pending_scroll_down"
    );

    // full_dirty must NOT be set: only the shifted-in rows are dirty.
    assert!(
        !session.core.screen.is_full_dirty(),
        "full-screen scroll-down must not force a full repaint"
    );
}

/// `is_process_alive()` returns true when pty is None (test sessions).
///
/// Unit test sessions are constructed with `pty: None` via `make_session()`.
/// `is_process_alive()` must report `true` in that case so that test-only
/// sessions never trigger the auto-kill path.
#[test]
fn test_is_process_alive_no_pty() {
    let session = make_session();
    assert!(
        session.is_process_alive(),
        "session with pty: None should report process as alive (safe default)"
    );
}

// consume_scroll_events returns (0, 0) during scrollback view.
//
// With the full_dirty approach, consume_scroll_events always returns (0, 0)
// for full-screen scrolls.  This test verifies the scrollback path still
// returns (0, 0) and that full_dirty is cleared by take_dirty_lines.

#[test]
fn test_consume_scroll_events_suppressed_during_scrollback() {
    let mut session = make_session();

    // Generate scrollback content
    for _ in 0..25 {
        session.core.advance(b"line\n");
    }
    // Drain dirty state from initial scrolling
    let _ = session.core.screen.take_dirty_lines();

    // Generate more scroll events
    for _ in 0..5 {
        session.core.advance(b"more\n");
    }

    // Enter scrollback view
    session.core.screen.viewport_scroll_up(10);
    assert!(session.core.screen.scroll_offset() > 0);

    // consume_scroll_events must return (0, 0) while in scrollback
    let (up, down) = session.consume_scroll_events();
    assert_eq!(
        up, 0,
        "scroll events must be suppressed during scrollback view"
    );
    assert_eq!(
        down, 0,
        "scroll events must be suppressed during scrollback view"
    );
}
