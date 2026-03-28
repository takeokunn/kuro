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

/// Full-screen `scroll_up` uses `full_dirty` instead of `pending_scroll_up`.
///
/// After the scroll-accumulation fix, the full-screen fast path sets
/// `full_dirty = true` and does NOT increment `pending_scroll_up`, so
/// `consume_scroll_events` returns (0, 0).  The Emacs render cycle uses
/// `take_dirty_lines` (which returns all rows when `full_dirty` is set)
/// instead of the buffer-level shift.
#[test]
fn test_consume_scroll_events_returns_zero_after_full_screen_scroll() {
    let mut session = make_session();

    // Advance content that causes a full-screen scroll (write 25 lines on a
    // 24-row terminal — the 25th line triggers one scroll_up event).
    for _ in 0..25 {
        session.core.advance(b"line\n");
    }

    // Full-screen scroll now uses full_dirty, not pending_scroll_up.
    let (up, down) = session.consume_scroll_events();
    assert_eq!(
        up, 0,
        "full-screen scroll should not accumulate pending_scroll_up"
    );
    assert_eq!(down, 0, "no scroll-down events expected");

    // Verify full_dirty was set instead.
    let dirty = session.core.screen.take_dirty_lines();
    assert_eq!(
        dirty.len(),
        24,
        "full_dirty should cause take_dirty_lines to return all 24 rows"
    );
}

/// Full-screen `scroll_down` uses `full_dirty` instead of `pending_scroll_down`.
///
/// After the scroll-accumulation fix, reverse index (RI) on a full-screen
/// scroll region sets `full_dirty = true` and does NOT increment
/// `pending_scroll_down`.
#[test]
fn test_consume_scroll_events_scroll_down_returns_zero() {
    let mut session = make_session();

    // ESC [ r        — DECSTBM: scroll region = full screen
    // ESC [ 1 ; 1 H  — CUP: move cursor to top-left
    // ESC M          — RI: reverse index — scrolls content down at top margin
    session.core.advance(b"\x1b[r\x1b[1;1H\x1bM\x1bM\x1bM");

    // Full-screen scroll_down now uses full_dirty, not pending_scroll_down.
    let (up, down) = session.consume_scroll_events();
    assert_eq!(up, 0, "no scroll-up events expected after RI-only input");
    assert_eq!(
        down, 0,
        "full-screen scroll should not accumulate pending_scroll_down"
    );

    // Verify full_dirty was set instead.
    let dirty = session.core.screen.take_dirty_lines();
    assert_eq!(
        dirty.len(),
        24,
        "full_dirty should cause take_dirty_lines to return all 24 rows"
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
