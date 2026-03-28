// ---------------------------------------------------------------------------
// get_dirty_lines: text-only encoding (no face ranges)
// ---------------------------------------------------------------------------

/// `get_dirty_lines` returns `(row, text)` tuples for dirty rows.
///
/// Verifies the basic contract: after writing to the terminal, exactly the
/// written row is returned and the text matches the cell content.
#[test]
fn test_get_dirty_lines_returns_dirty_rows() {
    let mut session = make_session();
    session.core.advance(b"Hello");

    let dirty = session.get_dirty_lines();
    assert!(
        !dirty.is_empty(),
        "get_dirty_lines must return at least one row after writing"
    );

    let row0 = dirty.iter().find(|(r, _)| *r == 0);
    assert!(row0.is_some(), "Row 0 must be present in get_dirty_lines");
    let (_, text) = row0.unwrap();
    assert!(
        text.starts_with("Hello"),
        "Row 0 text must start with 'Hello', got: {text:?}"
    );
}

/// After `get_dirty_lines` the dirty set is cleared; a second call returns empty.
#[test]
fn test_get_dirty_lines_clears_dirty_set() {
    let mut session = make_session();
    session.core.advance(b"ABC");

    let first = session.get_dirty_lines();
    assert!(!first.is_empty(), "First call must return dirty rows");

    let second = session.get_dirty_lines();
    assert!(
        second.is_empty(),
        "Second call with no changes must return empty (dirty set cleared)"
    );
}

/// `get_dirty_lines` on a fresh session returns rows marked dirty by init.
#[test]
fn test_get_dirty_lines_full_dirty_path() {
    let mut session = make_session();
    // full_dirty is set during construction; writing any content triggers it.
    session.core.advance(b"\x1b[?1049h"); // enter alt screen — sets full_dirty
    let dirty = session.get_dirty_lines();
    assert_eq!(dirty.len(), 24, "full_dirty path must return all 24 rows");
}

// ---------------------------------------------------------------------------
// get_scrollback / get_scrollback_count / clear_scrollback / set_scrollback_max_lines
// ---------------------------------------------------------------------------

/// `get_scrollback` returns lines pushed into scrollback.
#[test]
fn test_get_scrollback_returns_pushed_lines() {
    let mut session = make_session();

    // Write a distinctive line, then scroll it into scrollback.
    session.core.advance(b"SCROLLBACK_LINE");
    let newlines = b"\n".repeat(24);
    session.core.advance(&newlines);

    let sb = session.get_scrollback(100);
    assert!(
        !sb.is_empty(),
        "get_scrollback must return non-empty vec after pushing lines"
    );
    assert!(
        sb.iter().any(|l| l.contains("SCROLLBACK_LINE")),
        "scrollback must contain the written line"
    );
}

/// `get_scrollback` is capped by `max_lines`.
#[test]
fn test_get_scrollback_respects_max_lines() {
    let mut session = make_session();

    // Push many lines into scrollback.
    for _ in 0..50 {
        session.core.advance(b"line\n");
    }

    let sb = session.get_scrollback(5);
    assert!(
        sb.len() <= 5,
        "get_scrollback must return at most max_lines entries, got {}",
        sb.len()
    );
}

/// `get_scrollback_count` returns non-zero after pushing lines.
#[test]
fn test_get_scrollback_count_nonzero_after_push() {
    let mut session = make_session();
    session.core.advance(b"line1\nline2\n");
    let newlines = b"\n".repeat(24);
    session.core.advance(&newlines);

    assert!(
        session.get_scrollback_count() > 0,
        "scrollback_count must be > 0 after pushing lines into scrollback"
    );
}

/// `clear_scrollback` empties the scrollback buffer and resets the count.
#[test]
fn test_clear_scrollback_empties_buffer() {
    let mut session = make_session();

    // Push lines into scrollback.
    session.core.advance(b"Keep\n");
    let newlines = b"\n".repeat(24);
    session.core.advance(&newlines);
    assert!(
        session.get_scrollback_count() > 0,
        "Pre-condition: scrollback must be non-empty before clear"
    );

    session.clear_scrollback();

    assert_eq!(
        session.get_scrollback_count(),
        0,
        "clear_scrollback must reset scrollback_count to 0"
    );
    assert!(
        session.get_scrollback(100).is_empty(),
        "clear_scrollback must empty the scrollback lines"
    );
}

/// `set_scrollback_max_lines(0)` causes `get_scrollback` to always return empty.
#[test]
fn test_set_scrollback_max_lines_zero_disables_scrollback() {
    let mut session = make_session();
    session.set_scrollback_max_lines(0);

    session.core.advance(b"line\n");
    let newlines = b"\n".repeat(24);
    session.core.advance(&newlines);

    let sb = session.get_scrollback(100);
    assert!(
        sb.is_empty(),
        "set_scrollback_max_lines(0) must prevent scrollback accumulation"
    );
}

// ---------------------------------------------------------------------------
// scroll_offset / viewport_scroll_down
// ---------------------------------------------------------------------------

/// `scroll_offset` starts at 0 on a fresh session.
#[test]
fn test_scroll_offset_zero_initially() {
    let session = make_session();
    assert_eq!(
        session.scroll_offset(),
        0,
        "scroll_offset must be 0 on a fresh session"
    );
}

/// `viewport_scroll_up` increases offset; `viewport_scroll_down` decreases it.
#[test]
fn test_viewport_scroll_down_reduces_offset() {
    let mut session = make_session();

    // Push enough lines to have scrollback.
    for _ in 0..30 {
        session.core.advance(b"line\n");
    }

    session.viewport_scroll_up(5);
    let offset_after_up = session.scroll_offset();
    assert!(
        offset_after_up > 0,
        "viewport_scroll_up must increase scroll_offset"
    );

    session.viewport_scroll_down(3);
    let offset_after_down = session.scroll_offset();
    assert!(
        offset_after_down < offset_after_up,
        "viewport_scroll_down must decrease scroll_offset (was {offset_after_up}, now {offset_after_down})"
    );
}

/// `viewport_scroll_down` to 0 restores the live view (scroll_offset == 0).
#[test]
fn test_viewport_scroll_down_to_zero_restores_live() {
    let mut session = make_session();

    for _ in 0..30 {
        session.core.advance(b"line\n");
    }

    session.viewport_scroll_up(5);
    session.viewport_scroll_down(usize::MAX); // clamp to 0
    assert_eq!(
        session.scroll_offset(),
        0,
        "viewport_scroll_down past 0 must clamp offset to 0"
    );
}

// ---------------------------------------------------------------------------
// command() / pid()
// ---------------------------------------------------------------------------

/// `command()` returns the shell command string stored at construction.
#[test]
fn test_command_returns_stored_command() {
    let mut session = make_session();
    session.command = "fish".to_owned();
    assert_eq!(session.command(), "fish");
}

/// `command()` returns an empty string for sessions created with no command.
#[test]
fn test_command_empty_for_make_session() {
    let session = make_session();
    assert_eq!(
        session.command(),
        "",
        "make_session sets command to empty string"
    );
}

/// `pid()` returns `None` for test sessions with `pty: None`.
#[test]
fn test_pid_returns_none_without_pty() {
    let session = make_session();
    assert!(
        session.pid().is_none(),
        "pid() must return None when no PTY is attached"
    );
}

// ---------------------------------------------------------------------------
// get_palette_updates / get_default_colors
// ---------------------------------------------------------------------------

/// `get_palette_updates` returns empty vec when no OSC 4 has been sent.
#[test]
fn test_get_palette_updates_empty_initially() {
    let session = make_session();
    let updates = session.get_palette_updates();
    assert!(
        updates.is_empty(),
        "get_palette_updates must return empty vec on a fresh session"
    );
}

/// After OSC 4 sets palette entry 1, `get_palette_updates` includes that entry.
#[test]
fn test_get_palette_updates_after_osc4() {
    let mut session = make_session();
    // OSC 4 ; 1 ; rgb:ff/00/00 ST
    session.core.advance(b"\x1b]4;1;rgb:ff/00/00\x1b\\");

    let updates = session.get_palette_updates();
    assert!(
        updates
            .iter()
            .any(|(idx, r, g, b)| *idx == 1 && *r == 0xff && *g == 0 && *b == 0),
        "get_palette_updates must include index=1 with rgb(255,0,0) after OSC 4"
    );
}

/// `get_default_colors` returns the `0xFF00_0000` sentinel when no OSC 10/11/12 set.
#[test]
fn test_get_default_colors_sentinel_when_unset() {
    let session = make_session();
    let (fg, bg, cursor) = session.get_default_colors();
    assert_eq!(
        fg, 0xFF00_0000u32,
        "Default fg must be 0xFF00_0000 when no OSC 10 was sent"
    );
    assert_eq!(
        bg, 0xFF00_0000u32,
        "Default bg must be 0xFF00_0000 when no OSC 11 was sent"
    );
    assert_eq!(
        cursor, 0xFF00_0000u32,
        "Default cursor color must be 0xFF00_0000 when no OSC 12 was sent"
    );
}

/// After OSC 10 sets default fg, `get_default_colors` returns the new value.
#[test]
fn test_get_default_colors_after_osc10() {
    let mut session = make_session();
    session.core.advance(b"\x1b]10;rgb:ff/80/00\x07");

    let (fg, _bg, _cursor) = session.get_default_colors();
    assert_ne!(
        fg, 0xFF00_0000u32,
        "get_default_colors fg must not be the sentinel after OSC 10"
    );
}

include!("tests_unit_dec_accessors.rs");
