use super::dirty_viewport_support::{
    assert_scrollback_non_empty, make_viewport_session, scrollback_batch, scrollback_with_marker,
};

/// `set_detached()` transitions the session state so `is_detached()` returns true.
#[test]
fn test_set_detached_changes_state() {
    let mut session = make_viewport_session();
    assert!(
        !session.is_detached(),
        "pre-condition: session must be Bound before set_detached()"
    );
    session.set_detached();
    assert!(
        session.is_detached(),
        "is_detached() must return true after set_detached()"
    );
}

/// `set_bound()` after `set_detached()` reverses the state transition.
#[test]
fn test_set_bound_reverses_detach() {
    let mut session = make_viewport_session();
    session.set_detached();
    assert!(
        session.is_detached(),
        "pre-condition: session must be Detached before set_bound()"
    );
    session.set_bound();
    assert!(
        !session.is_detached(),
        "is_detached() must return false after set_bound()"
    );
}

/// Multiple `set_detached` calls are idempotent.
#[test]
fn test_set_detached_idempotent() {
    let mut session = make_viewport_session();
    session.set_detached();
    session.set_detached(); // second call — must not panic or corrupt state
    assert!(
        session.is_detached(),
        "is_detached() must remain true after multiple set_detached() calls"
    );
}

// ---------------------------------------------------------------------------
// get_palette_updates: multiple OSC 4 entries
// ---------------------------------------------------------------------------

/// Two OSC 4 sequences set two palette entries; `get_palette_updates` must
/// return both with correct index and RGB values.
#[test]
fn test_get_palette_updates_multiple_entries() {
    let mut session = make_viewport_session();
    // Index 0 → red
    session.core.advance(b"\x1b]4;0;rgb:ff/00/00\x1b\\");
    // Index 1 → green
    session.core.advance(b"\x1b]4;1;rgb:00/ff/00\x1b\\");

    let updates = session.get_palette_updates();

    assert!(
        updates
            .iter()
            .any(|(idx, r, g, b)| *idx == 0 && *r == 0xff && *g == 0 && *b == 0),
        "get_palette_updates must include index=0 with rgb(255,0,0)"
    );
    assert!(
        updates
            .iter()
            .any(|(idx, r, g, b)| *idx == 1 && *r == 0 && *g == 0xff && *b == 0),
        "get_palette_updates must include index=1 with rgb(0,255,0)"
    );
    assert!(
        updates.len() >= 2,
        "get_palette_updates must return at least 2 entries after two OSC 4 sequences, got {}",
        updates.len()
    );
}

/// Three OSC 4 sequences set three distinct entries; all three must appear.
#[test]
fn test_get_palette_updates_three_entries() {
    let mut session = make_viewport_session();
    session.core.advance(b"\x1b]4;0;rgb:ff/00/00\x1b\\"); // red
    session.core.advance(b"\x1b]4;1;rgb:00/ff/00\x1b\\"); // green
    session.core.advance(b"\x1b]4;2;rgb:00/00/ff\x1b\\"); // blue

    let updates = session.get_palette_updates();

    let found: Vec<u8> = updates.iter().map(|(idx, ..)| *idx).collect();
    assert!(
        found.contains(&0),
        "index 0 must be present in palette updates"
    );
    assert!(
        found.contains(&1),
        "index 1 must be present in palette updates"
    );
    assert!(
        found.contains(&2),
        "index 2 must be present in palette updates"
    );
    assert!(
        updates
            .iter()
            .any(|(idx, r, g, b)| *idx == 2 && *r == 0 && *g == 0 && *b == 0xff),
        "index 2 must carry rgb(0,0,255)"
    );
}

// ---------------------------------------------------------------------------
// get_scrollback_count: multiple sequential scroll batches
// ---------------------------------------------------------------------------

/// After three distinct scroll batches, `get_scrollback_count` must reflect
/// the cumulative number of lines pushed into scrollback.
#[test]
fn test_get_scrollback_count_after_multiple_scrolls() {
    let mut session = make_viewport_session();
    scrollback_batch(&mut session, 3);

    let count = session.get_scrollback_count();
    assert!(
        count >= 48,
        "after 3 scroll batches of 24 lines each, scrollback count must be \
         at least 48 (two batches fully pushed), got {count}"
    );
}

/// `get_scrollback_count` increases monotonically with each scroll batch.
#[test]
fn test_get_scrollback_count_increases_monotonically() {
    let mut session = make_viewport_session();
    scrollback_batch(&mut session, 1);
    let count_after_1 = session.get_scrollback_count();

    scrollback_batch(&mut session, 1);
    let count_after_2 = session.get_scrollback_count();

    scrollback_batch(&mut session, 1);
    let count_after_3 = session.get_scrollback_count();

    assert!(
        count_after_1 > 0,
        "scrollback count must be > 0 after first scroll batch"
    );
    assert!(
        count_after_2 > count_after_1,
        "scrollback count must increase after second scroll batch \
         (was {count_after_1}, now {count_after_2})"
    );
    assert!(
        count_after_3 > count_after_2,
        "scrollback count must increase after third scroll batch \
         (was {count_after_2}, now {count_after_3})"
    );
}

// ---------------------------------------------------------------------------
// viewport_scroll_up then get_scrollback returns content
// ---------------------------------------------------------------------------

/// After `viewport_scroll_up`, `get_scrollback` must return a non-empty Vec
/// whose content includes text that was pushed into scrollback.
#[test]
fn test_viewport_scroll_up_then_lines_appear_in_get_scrollback() {
    let mut session = make_viewport_session();
    scrollback_with_marker(&mut session, b"VISIBLE_IN_SCROLLBACK");
    assert_scrollback_non_empty(
        &session,
        "pre-condition: scrollback must be non-empty before viewport_scroll_up",
    );

    // Scroll the viewport up — this moves the view into the scrollback region.
    session.viewport_scroll_up(1);
    assert!(
        session.scroll_offset() > 0,
        "scroll_offset must be > 0 after viewport_scroll_up(1)"
    );

    // get_scrollback must return the stored scrollback lines regardless of
    // the current viewport position.
    let sb = session.get_scrollback(100);
    assert!(
        !sb.is_empty(),
        "get_scrollback must return non-empty content after viewport_scroll_up"
    );
    assert!(
        sb.iter().any(|l| l.contains("VISIBLE_IN_SCROLLBACK")),
        "get_scrollback must include the line that was pushed into scrollback"
    );
}

// ---------------------------------------------------------------------------
// get_cursor_visible: hide then show round-trip (explicit show after hide)
// ---------------------------------------------------------------------------

/// After hiding the cursor with `CSI ?25l` and then showing it with `CSI ?25h`,
/// `get_cursor_visible()` must return `true` again.
#[test]
fn test_get_cursor_visible_after_show_command() {
    let mut session = make_viewport_session();

    // Hide cursor.
    session.core.advance(b"\x1b[?25l");
    assert!(
        !session.get_cursor_visible(),
        "cursor must be hidden after CSI ?25l"
    );

    // Show cursor again.
    session.core.advance(b"\x1b[?25h");
    assert!(
        session.get_cursor_visible(),
        "get_cursor_visible() must return true after CSI ?25h (show cursor)"
    );
}
