use super::dirty_binary_support::{
    binary_cursor, binary_num_rows, binary_scroll_shift, consume_initial_dirty, enable_sync_output,
    enter_alt_screen, fill_screen_and_drain, fill_scrollback, make_binary_session,
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

use super::TerminalSession;
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

// ---------------------------------------------------------------------------
// Version-3 scroll shift transport — unit tests
// ---------------------------------------------------------------------------

/// A full-screen scroll travels in the frame header as `scroll_up`, and only
/// the rows the scroll actually touched are re-encoded — NOT all 24 rows.
/// This is the core smooth-streaming property: per-scroll render cost is
/// O(exposed rows), not O(screen).
#[test]
fn test_binary_direct_scroll_shift_in_header_not_full_repaint() {
    let mut session = make_binary_session();
    fill_screen_and_drain(&mut session);

    // Two more lines at the bottom margin → two full-screen scrolls.
    session.core.advance(b"new line A\n");
    session.core.advance(b"new line B\n");

    let frame = session
        .get_dirty_lines_binary_direct()
        .expect("scroll frame must fit binary u32 fields");
    assert!(!frame.bytes.is_empty(), "scroll frame must not be empty");
    assert_eq!(
        binary_scroll_shift(&frame.bytes),
        (2, 0),
        "the two scrolls must travel as scroll_up in the frame header"
    );
    assert!(
        frame.texts.len() < 24,
        "a scroll must not force a full repaint; got {} rows",
        frame.texts.len()
    );
    assert_eq!(
        frame.texts.len() as u32,
        binary_num_rows(&frame.bytes),
        "num_rows header must match the text vector"
    );
}

/// After a scroll frame is drained, a poll with no new output must be empty:
/// the rotated row-hash cache stays aligned with the shifted viewport.
#[test]
fn test_binary_direct_after_scroll_drain_next_poll_is_empty() {
    let mut session = make_binary_session();
    fill_screen_and_drain(&mut session);
    session.core.advance(b"new line\n");
    let _ = session.get_dirty_lines_binary_direct();

    let frame = session
        .get_dirty_lines_binary_direct()
        .expect("idle frame must fit binary u32 fields");
    assert!(
        frame.texts.is_empty() && frame.bytes.is_empty(),
        "no new output → the frame after a drained scroll must be empty"
    );
}

/// `mark_all_dirty` (resize, alt-screen switch, live-view return) discards
/// pending scroll shifts: a full repaint supersedes the buffer shift.
#[test]
fn test_binary_direct_full_dirty_discards_scroll_shift() {
    let mut session = make_binary_session();
    fill_screen_and_drain(&mut session);
    session.core.advance(b"new line\n"); // one pending scroll_up
    session.core.screen.mark_all_dirty();

    let frame = session
        .get_dirty_lines_binary_direct()
        .expect("full dirty frame must fit binary u32 fields");
    assert_eq!(
        binary_scroll_shift(&frame.bytes),
        (0, 0),
        "full_dirty must discard the pending scroll shift"
    );
    assert_eq!(
        binary_num_rows(&frame.bytes),
        24,
        "full_dirty must re-encode all rows"
    );
}

/// Synchronized output holds dirty rows AND scroll shifts; the closing
/// `?2026 l` flushes both in one atomic frame.
#[test]
fn test_binary_direct_sync_holds_scroll_then_flushes_atomically() {
    let mut session = make_binary_session();
    fill_screen_and_drain(&mut session);

    enable_sync_output(&mut session);
    session.core.advance(b"inside batch\n");
    let held = session
        .get_dirty_lines_binary_direct()
        .expect("held frame must fit binary u32 fields");
    assert!(held.bytes.is_empty(), "open sync batch must hold the frame");

    session.core.advance(b"\x1b[?2026l");
    let flushed = session
        .get_dirty_lines_binary_direct()
        .expect("flushed frame must fit binary u32 fields");
    assert_eq!(
        binary_scroll_shift(&flushed.bytes),
        (1, 0),
        "the scroll from inside the batch must flush with the batch"
    );
    assert!(
        binary_num_rows(&flushed.bytes) < 24,
        "closing a sync batch must not force a full repaint"
    );
}

/// A stuck `?2026 h` (no closing `l`) stops suppressing after
/// `SYNC_SUPPRESS_MAX_POLLS` polls so the display cannot freeze forever.
#[test]
fn test_binary_direct_sync_suppression_times_out() {
    let mut session = make_binary_session();
    consume_initial_dirty(&mut session);
    enable_sync_output(&mut session);
    session.core.advance(b"stuck batch");

    let mut released = false;
    // One poll beyond the cap must render live again.
    for _ in 0..=TerminalSession::SYNC_SUPPRESS_MAX_POLLS {
        let frame = session
            .get_dirty_lines_binary_direct()
            .expect("suppressed frame must fit binary u32 fields");
        if !frame.texts.is_empty() {
            released = true;
            break;
        }
    }
    assert!(
        released,
        "a stuck sync batch must stop suppressing after the poll cap"
    );
}

// ---------------------------------------------------------------------------
// get_dirty_lines_binary_payload — Latin-1 string transport
// ---------------------------------------------------------------------------

/// Map a Latin-1 payload string back to raw frame bytes (char U+00b → byte b).
fn payload_bytes(payload: &str) -> Vec<u8> {
    payload
        .chars()
        .map(|c| u8::try_from(u32::from(c)).expect("payload chars must be Latin-1 code points"))
        .collect()
}

/// The payload transport must be byte-identical to the raw-bytes view:
/// same frame, same texts, payload chars mapping 1:1 to the wire bytes.
#[test]
fn test_binary_payload_matches_direct_bytes() {
    let mut direct_session = make_binary_session();
    let mut payload_session = make_binary_session();
    for session in [&mut direct_session, &mut payload_session] {
        consume_initial_dirty(session);
        session
            .core
            .advance(b"\x1b[31mcolored\x1b[0m plain \xc3\xa9");
    }

    let frame = direct_session
        .get_dirty_lines_binary_direct()
        .expect("direct frame must fit binary u32 fields");
    let (texts, payload) = payload_session
        .get_dirty_lines_binary_payload()
        .expect("payload frame must fit binary u32 fields");

    assert_eq!(texts, frame.texts, "texts must match the raw-bytes view");
    assert_eq!(
        payload_bytes(&payload),
        frame.bytes,
        "payload chars must map 1:1 onto the wire bytes"
    );
}

/// The payload transcode reads `buf_scratch` in place: after a non-empty
/// poll the scratch buffer must retain its capacity for the next frame
/// (the former `mem::take` reset it to zero, forcing a realloc per poll).
#[test]
fn test_binary_payload_retains_buf_scratch_capacity() {
    let mut session = make_binary_session();
    fill_screen_and_drain(&mut session);
    session.core.advance(b"dirty row\n");

    let (texts, _payload) = session
        .get_dirty_lines_binary_payload()
        .expect("payload frame must fit binary u32 fields");
    assert!(!texts.is_empty(), "precondition: frame must be non-empty");
    assert!(
        session.buf_scratch.capacity() > 0,
        "buf_scratch must keep its capacity after the payload poll"
    );
}

/// A scrolling payload frame must carry the shift in its header with the
/// row count consistent between the header and the texts vector — the same
/// smooth-streaming property as the raw-bytes view, through the Latin-1
/// transport.
#[test]
fn test_binary_payload_scroll_shift_in_header() {
    let mut session = make_binary_session();
    consume_initial_dirty(&mut session);
    // Walk the blank screen to the bottom margin plus one scroll, then drain
    // so every row hash is populated and the shift is consumed.
    session.core.advance(&b"\n".repeat(24));
    let _ = session.get_dirty_lines_binary_payload();

    // One more LF scrolls: the shift travels in the payload header.
    session.core.advance(b"\n");
    let (texts, payload) = session
        .get_dirty_lines_binary_payload()
        .expect("scroll frame must fit binary u32 fields");
    assert!(
        !payload.is_empty(),
        "a scroll frame must transmit its header shift"
    );
    let bytes = payload_bytes(&payload);
    assert_eq!(
        binary_scroll_shift(&bytes),
        (1, 0),
        "the scroll must travel as scroll_up in the header"
    );
    assert_eq!(
        texts.len() as u32,
        binary_num_rows(&bytes),
        "num_rows header must match the text vector"
    );
    assert!(
        texts.len() < 24,
        "a scroll must not force a full repaint; got {} rows",
        texts.len()
    );
}

// ---------------------------------------------------------------------------
// Version-4 cursor + bell transport — unit tests
// ---------------------------------------------------------------------------

/// A pure cursor movement (no dirty rows, no scroll) must emit a header-only
/// frame carrying the new cursor position — this replaces the per-frame
/// `get_cursor_state` FFI poll.
#[test]
fn test_binary_v4_cursor_move_only_emits_header_frame() {
    let mut session = make_binary_session();
    consume_initial_dirty(&mut session);

    // CUP to row 5, col 7 (1-based in CSI; 0-based on the wire).
    session.core.advance(b"\x1b[6;8H");
    let frame = session
        .get_dirty_lines_binary_direct()
        .expect("cursor-move frame must fit binary u32 fields");
    assert!(
        frame.texts.is_empty(),
        "a pure cursor move must not re-encode any row"
    );
    assert!(
        !frame.bytes.is_empty(),
        "a pure cursor move must emit a header-only frame"
    );
    let (row, col, meta) = binary_cursor(&frame.bytes);
    assert_eq!((row, col), (5, 7), "header must carry the new position");
    assert_eq!(meta & 1, 1, "cursor must be visible by default");
    assert_eq!(meta & (1 << 4), 0, "no bell was pending");

    // A second poll with no further movement must be empty.
    let idle = session
        .get_dirty_lines_binary_direct()
        .expect("idle frame must fit binary u32 fields");
    assert!(
        idle.texts.is_empty() && idle.bytes.is_empty(),
        "unchanged cursor must not re-emit a frame"
    );
}

/// A BEL with no other changes must emit a header-only frame with the bell
/// bit set — and the bell must not repeat on the next poll.
#[test]
fn test_binary_v4_bell_only_emits_frame_once() {
    let mut session = make_binary_session();
    consume_initial_dirty(&mut session);

    session.core.advance(b"\x07");
    let frame = session
        .get_dirty_lines_binary_direct()
        .expect("bell frame must fit binary u32 fields");
    assert!(
        !frame.bytes.is_empty(),
        "a bell must force a header-only frame"
    );
    let (_, _, meta) = binary_cursor(&frame.bytes);
    assert_eq!(meta & (1 << 4), 1 << 4, "bell bit must be set");

    let idle = session
        .get_dirty_lines_binary_direct()
        .expect("idle frame must fit binary u32 fields");
    assert!(
        idle.bytes.is_empty(),
        "the bell must be consumed by the frame that carried it"
    );
}

/// DECTCEM hide (`?25l`) is a cursor-state change: it must emit a header
/// frame with the visible bit cleared.
#[test]
fn test_binary_v4_cursor_hide_emits_frame() {
    let mut session = make_binary_session();
    consume_initial_dirty(&mut session);

    session.core.advance(b"\x1b[?25l");
    let frame = session
        .get_dirty_lines_binary_direct()
        .expect("hide frame must fit binary u32 fields");
    assert!(!frame.bytes.is_empty(), "DECTCEM change must emit a frame");
    let (_, _, meta) = binary_cursor(&frame.bytes);
    assert_eq!(meta & 1, 0, "visible bit must be cleared after ?25l");
}

/// DECSCUSR shape changes travel in meta bits 1-3.
#[test]
fn test_binary_v4_cursor_shape_in_meta() {
    let mut session = make_binary_session();
    consume_initial_dirty(&mut session);

    session.core.advance(b"\x1b[6 q"); // steady bar = 6
    let frame = session
        .get_dirty_lines_binary_direct()
        .expect("shape frame must fit binary u32 fields");
    assert!(!frame.bytes.is_empty(), "DECSCUSR change must emit a frame");
    let (_, _, meta) = binary_cursor(&frame.bytes);
    assert_eq!((meta >> 1) & 0x7, 6, "shape bits must carry DECSCUSR 6");
}

/// A bell arriving while the viewport is scrolled back (live rows suppressed)
/// must still reach Emacs as a header-only frame, with the cursor fields
/// repeating the last-sent state so the display does not move.
#[test]
fn test_binary_v4_bell_rings_through_scrollback_suppression() {
    let mut session = make_binary_session();
    fill_scrollback(&mut session, 5);
    consume_initial_dirty(&mut session);
    session.viewport_scroll_up(3);
    // Drain the scrollback viewport frame (scroll_dirty path).
    let viewport = session
        .get_dirty_lines_binary_direct()
        .expect("viewport frame must fit binary u32 fields");
    let (sent_row, sent_col, _) = binary_cursor(&viewport.bytes);

    // Bell while suppressed: live rows must stay suppressed, bell must ring.
    session.core.advance(b"\x07");
    let frame = session
        .get_dirty_lines_binary_direct()
        .expect("suppressed bell frame must fit binary u32 fields");
    assert!(
        frame.texts.is_empty(),
        "suppression must still hold back live rows"
    );
    assert!(
        !frame.bytes.is_empty(),
        "the bell must ring through suppression"
    );
    let (row, col, meta) = binary_cursor(&frame.bytes);
    assert_eq!(meta & (1 << 4), 1 << 4, "bell bit must be set");
    assert_eq!(
        (row, col),
        (sent_row, sent_col),
        "suppressed bell frame must repeat the last-sent cursor"
    );
}
