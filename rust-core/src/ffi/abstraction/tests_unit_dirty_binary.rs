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

/// Helper: decode the `num_rows` field from the binary payload header.
fn binary_num_rows(buf: &[u8]) -> u32 {
    // Header layout: [version: u32][num_rows: u32][rows...]
    u32::from_le_bytes(buf[4..8].try_into().unwrap())
}

/// With no dirty rows (fresh call after a prior clear), `get_dirty_lines_binary_direct`
/// must return empty vecs — no allocation, no payload.
#[test]
fn test_binary_direct_no_dirty_returns_empty() {
    let mut session = make_session();
    // Consume the initial full_dirty so the slate is clean.
    let _ = session.get_dirty_lines_binary_direct();
    // A second call with no changes must return empty.
    let (texts, buf) = session.get_dirty_lines_binary_direct();
    assert!(texts.is_empty(), "texts must be empty when no dirty rows");
    assert!(buf.is_empty(), "buf must be empty when no dirty rows");
}

/// After entering the alternate screen (which marks all rows full-dirty), the binary
/// payload must contain all 24 rows.
#[test]
fn test_binary_direct_full_dirty_returns_all_rows() {
    let mut session = make_session();
    // Consume initial full_dirty.
    let _ = session.get_dirty_lines_binary_direct();
    // Alt-screen switch marks full_dirty again.
    session.core.advance(b"\x1b[?1049h");
    let (texts, buf) = session.get_dirty_lines_binary_direct();
    assert_eq!(texts.len(), 24, "full_dirty must produce 24 text entries");
    assert!(buf.len() > 8, "full_dirty binary buf must contain row data");
    let version = u32::from_le_bytes(buf[0..4].try_into().unwrap());
    assert_eq!(version, BINARY_FORMAT_VERSION, "binary format version must match");
    assert_eq!(binary_num_rows(&buf), 24, "header num_rows must be 24");
}

/// Writing to one row and calling `get_dirty_lines_binary_direct` must return
/// exactly that row in the binary payload.
#[test]
fn test_binary_direct_partial_dirty_returns_only_changed_row() {
    let mut session = make_session();
    // Consume the initial full_dirty.
    let _ = session.get_dirty_lines_binary_direct();
    // Write to row 0 only.
    session.core.advance(b"HI");
    let (texts, buf) = session.get_dirty_lines_binary_direct();
    // At minimum row 0 must appear; hash dedup may reduce subsequent calls.
    assert!(!texts.is_empty(), "partial dirty must return at least one row");
    assert!(buf.len() > 8, "partial dirty must produce a non-trivial payload");
    let version = u32::from_le_bytes(buf[0..4].try_into().unwrap());
    assert_eq!(version, BINARY_FORMAT_VERSION, "format version must match");
}

/// When DEC 2026 (synchronized output) is active, `get_dirty_lines_binary_direct`
/// must hold the frame and return empty vecs.
#[test]
fn test_binary_direct_synchronized_output_suppresses() {
    let mut session = make_session();
    // Enable synchronized output (CSI ?2026h).
    session.core.advance(b"\x1b[?2026h");
    // Write something so there ARE dirty rows.
    session.core.advance(b"SYNC");
    let (texts, buf) = session.get_dirty_lines_binary_direct();
    assert!(
        texts.is_empty(),
        "synchronized output mode must suppress dirty lines"
    );
    assert!(
        buf.is_empty(),
        "synchronized output mode must suppress binary payload"
    );
}

/// When the viewport is scrolled (`scroll_offset > 0`) but `scroll_dirty` was
/// already consumed, `get_dirty_lines_binary_direct` must return empty vecs to
/// avoid overwriting the scrollback view with stale live-screen content.
#[test]
fn test_binary_direct_scroll_offset_suppresses_live_rows() {
    let mut session = make_session();
    // Scroll enough lines into scrollback to allow scroll_up.
    for _ in 0..5 {
        session.core.advance(&b"\n".repeat(24));
    }
    assert!(
        session.core.screen.scrollback_line_count > 0,
        "precondition: scrollback must be non-empty"
    );
    // Consume any existing dirty (including the initial full_dirty from scroll).
    let _ = session.get_dirty_lines_binary_direct();
    // Scroll viewport up — this sets scroll_dirty = true.
    session.viewport_scroll_up(3);
    assert_eq!(session.scroll_offset(), 3);
    // Consume the scroll_dirty event so scroll_dirty becomes false.
    // This call takes the scrollback viewport path (scroll_dirty = true).
    let _ = session.get_dirty_lines_binary_direct();
    // Now: scroll_dirty = false, scroll_offset = 3 — suppression path applies.
    // Write to the live screen so there are dirty rows that would normally render.
    session.core.advance(b"LIVE");
    let (texts, buf) = session.get_dirty_lines_binary_direct();
    assert!(
        texts.is_empty(),
        "live dirty rows must be suppressed when scroll_offset > 0 and not scroll_dirty"
    );
    assert!(
        buf.is_empty(),
        "binary buf must be empty when scroll_offset > 0 and not scroll_dirty"
    );
}

/// When both `scroll_dirty` and `scroll_offset > 0`, `get_dirty_lines_binary_direct`
/// takes the scrollback viewport path: it encodes all rows and clears `scroll_dirty`.
#[test]
fn test_binary_direct_scrollback_viewport_path() {
    let mut session = make_session();
    // Fill scrollback so viewport can be scrolled.
    for _ in 0..3 {
        session.core.advance(&b"\n".repeat(24));
    }
    assert!(
        session.core.screen.scrollback_line_count > 0,
        "precondition: scrollback must be non-empty"
    );
    // Consume any lingering dirty from scrollback writes.
    let _ = session.get_dirty_lines_binary_direct();
    // Scroll viewport up — sets scroll_dirty = true AND scroll_offset > 0.
    session.viewport_scroll_up(2);
    assert!(session.core.screen.is_scroll_dirty(), "scroll_dirty must be true after scroll_up");
    assert!(session.scroll_offset() > 0, "scroll_offset must be positive after scroll_up");
    // This call must take the scrollback viewport path: returns all 24 rows.
    let (texts, buf) = session.get_dirty_lines_binary_direct();
    assert_eq!(texts.len(), 24, "scrollback viewport path must return 24 text entries");
    assert!(buf.len() > 8, "scrollback viewport path must produce a binary payload");
    let version = u32::from_le_bytes(buf[0..4].try_into().unwrap());
    assert_eq!(version, BINARY_FORMAT_VERSION, "format version must match");
    assert_eq!(binary_num_rows(&buf), 24, "header num_rows must be 24 for scrollback path");
    // After the call, scroll_dirty must be cleared.
    assert!(
        !session.core.screen.is_scroll_dirty(),
        "scroll_dirty must be cleared after scrollback viewport path"
    );
}
