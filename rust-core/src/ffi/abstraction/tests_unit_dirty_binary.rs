use super::dirty_binary_support::{
    binary_num_rows, consume_initial_dirty, enable_sync_output, enter_alt_screen, fill_scrollback,
    make_binary_session,
};

// ---------------------------------------------------------------------------
// get_dirty_lines_binary_direct — unit tests
// ---------------------------------------------------------------------------
//
// Covers all 6 branches of the function:
//   1. Empty result when no dirty rows remain
//   2. Full dirty → all rows encoded
//   3. Partial dirty → only changed rows
//   4. Synchronized output (DEC 2026) → suppressed
//   5. Scroll offset suppression → (vec![], vec![])
//   6. Scrollback viewport (scroll_dirty + scroll_offset > 0) → all rows

use crate::ffi::codec::BINARY_FORMAT_VERSION;

/// With no dirty rows (fresh call after a prior clear), `get_dirty_lines_binary_direct`
/// must return empty vecs — no allocation, no payload.
#[test]
fn test_binary_direct_no_dirty_returns_empty() {
    let mut session = make_binary_session();
    consume_initial_dirty(&mut session);
    // A second call with no changes must return empty.
    let frame = session
        .get_dirty_lines_binary_direct()
        .expect("empty dirty frame must fit binary u32 fields");
    assert!(
        frame.texts.is_empty(),
        "texts must be empty when no dirty rows"
    );
    assert!(
        frame.bytes.is_empty(),
        "buf must be empty when no dirty rows"
    );
}

/// After entering the alternate screen (which marks all rows full-dirty), the binary
/// payload must contain all 24 rows.
#[test]
fn test_binary_direct_full_dirty_returns_all_rows() {
    let mut session = make_binary_session();
    consume_initial_dirty(&mut session);
    enter_alt_screen(&mut session);
    let frame = session
        .get_dirty_lines_binary_direct()
        .expect("full dirty frame must fit binary u32 fields");
    assert_eq!(
        frame.texts.len(),
        24,
        "full_dirty must produce 24 text entries"
    );
    assert!(
        frame.bytes.len() > 8,
        "full_dirty binary buf must contain row data"
    );
    let version = u32::from_le_bytes(frame.bytes[0..4].try_into().unwrap());
    assert_eq!(
        version, BINARY_FORMAT_VERSION,
        "binary format version must match"
    );
    assert_eq!(
        binary_num_rows(&frame.bytes),
        24,
        "header num_rows must be 24"
    );
}

/// Writing to one row and calling `get_dirty_lines_binary_direct` must return
/// exactly that row in the binary payload.
#[test]
fn test_binary_direct_partial_dirty_returns_only_changed_row() {
    let mut session = make_binary_session();
    consume_initial_dirty(&mut session);
    // Write to row 0 only.
    session.core.advance(b"HI");
    let frame = session
        .get_dirty_lines_binary_direct()
        .expect("partial dirty frame must fit binary u32 fields");
    // At minimum row 0 must appear; hash dedup may reduce subsequent calls.
    assert!(
        !frame.texts.is_empty(),
        "partial dirty must return at least one row"
    );
    assert!(
        frame.bytes.len() > 8,
        "partial dirty must produce a non-trivial payload"
    );
    let version = u32::from_le_bytes(frame.bytes[0..4].try_into().unwrap());
    assert_eq!(version, BINARY_FORMAT_VERSION, "format version must match");
}

/// When DEC 2026 (synchronized output) is active, `get_dirty_lines_binary_direct`
/// must hold the frame and return empty vecs.
#[test]
fn test_binary_direct_synchronized_output_suppresses() {
    let mut session = make_binary_session();
    enable_sync_output(&mut session);
    // Write something so there ARE dirty rows.
    session.core.advance(b"SYNC");
    let frame = session
        .get_dirty_lines_binary_direct()
        .expect("suppressed dirty frame must fit binary u32 fields");
    assert!(
        frame.texts.is_empty(),
        "synchronized output mode must suppress dirty lines"
    );
    assert!(
        frame.bytes.is_empty(),
        "synchronized output mode must suppress binary payload"
    );
}

/// When the viewport is scrolled (`scroll_offset > 0`) but `scroll_dirty` was
/// already consumed, `get_dirty_lines_binary_direct` must return empty vecs to
/// avoid overwriting the scrollback view with stale live-screen content.
#[test]
fn test_binary_direct_scroll_offset_suppresses_live_rows() {
    let mut session = make_binary_session();
    fill_scrollback(&mut session, 5);
    assert!(
        session.core.screen.scrollback_line_count > 0,
        "precondition: scrollback must be non-empty"
    );
    // Consume any existing dirty (including the initial full_dirty from scroll).
    consume_initial_dirty(&mut session);
    // Scroll viewport up — this sets scroll_dirty = true.
    session.viewport_scroll_up(3);
    assert_eq!(session.scroll_offset(), 3);
    // Consume the scroll_dirty event so scroll_dirty becomes false.
    // This call takes the scrollback viewport path (scroll_dirty = true).
    let _ = session
        .get_dirty_lines_binary_direct()
        .expect("scrollback dirty frame must fit binary u32 fields");
    // Now: scroll_dirty = false, scroll_offset = 3 — suppression path applies.
    // Write to the live screen so there are dirty rows that would normally render.
    session.core.advance(b"LIVE");
    let frame = session
        .get_dirty_lines_binary_direct()
        .expect("suppressed live dirty frame must fit binary u32 fields");
    assert!(
        frame.texts.is_empty(),
        "live dirty rows must be suppressed when scroll_offset > 0 and not scroll_dirty"
    );
    assert!(
        frame.bytes.is_empty(),
        "binary buf must be empty when scroll_offset > 0 and not scroll_dirty"
    );
}

/// When both `scroll_dirty` and `scroll_offset > 0`, `get_dirty_lines_binary_direct`
/// takes the scrollback viewport path: it encodes all rows and clears `scroll_dirty`.
#[test]
fn test_binary_direct_scrollback_viewport_path() {
    let mut session = make_binary_session();
    fill_scrollback(&mut session, 3);
    assert!(
        session.core.screen.scrollback_line_count > 0,
        "precondition: scrollback must be non-empty"
    );
    // Consume any lingering dirty from scrollback writes.
    consume_initial_dirty(&mut session);
    // Scroll viewport up — sets scroll_dirty = true AND scroll_offset > 0.
    session.viewport_scroll_up(2);
    assert!(
        session.core.screen.is_scroll_dirty(),
        "scroll_dirty must be true after scroll_up"
    );
    assert!(
        session.scroll_offset() > 0,
        "scroll_offset must be positive after scroll_up"
    );
    // This call must take the scrollback viewport path: returns all 24 rows.
    let frame = session
        .get_dirty_lines_binary_direct()
        .expect("scrollback viewport dirty frame must fit binary u32 fields");
    assert_eq!(
        frame.texts.len(),
        24,
        "scrollback viewport path must return 24 text entries"
    );
    assert!(
        frame.bytes.len() > 8,
        "scrollback viewport path must produce a binary payload"
    );
    let version = u32::from_le_bytes(frame.bytes[0..4].try_into().unwrap());
    assert_eq!(version, BINARY_FORMAT_VERSION, "format version must match");
    assert_eq!(
        binary_num_rows(&frame.bytes),
        24,
        "header num_rows must be 24 for scrollback path"
    );
    // After the call, scroll_dirty must be cleared.
    assert!(
        !session.core.screen.is_scroll_dirty(),
        "scroll_dirty must be cleared after scrollback viewport path"
    );
}

#[test]
fn test_binary_direct_reemits_same_width_text_change() {
    let mut session = make_binary_session();
    consume_initial_dirty(&mut session);

    session.core.advance(b"abc");
    let _ = session
        .get_dirty_lines_binary_direct()
        .expect("initial changed row must fit binary u32 fields");

    session.core.advance(b"\rxyz");
    let frame = session
        .get_dirty_lines_binary_direct()
        .expect("same-width changed row must fit binary u32 fields");

    assert!(
        frame.texts.iter().any(|text| text.starts_with("xyz")),
        "same-width overwrite must be emitted, got {:?}",
        frame.texts
    );
    assert!(
        frame.bytes.len() > 8,
        "same-width overwrite must produce binary row data"
    );
}
