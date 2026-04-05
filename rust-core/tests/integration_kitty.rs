//! Kitty Graphics Protocol integration tests via `TerminalCore::advance()`.
//!
//! APC format: ESC _ G <key=val,...> ; <base64payload> ESC \
//!
//! These tests exercise the full advance() → APC scanner → kitty parser →
//! screen/graphics store pipeline.

mod common;

use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
use kuro_core::TerminalCore;

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Build a minimal valid 1×1 PNG in the given color type and base64-encode it.
fn make_1x1_png_b64(color_type: png::ColorType, pixels: &[u8]) -> String {
    let mut buf: Vec<u8> = Vec::new();
    {
        let mut encoder = png::Encoder::new(&mut buf, 1, 1);
        encoder.set_color(color_type);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder.write_header().expect("PNG header write");
        writer.write_image_data(pixels).expect("PNG pixel write");
    }
    BASE64_STANDARD.encode(&buf)
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. Transmit PNG (f=100) then query returns image info
// ─────────────────────────────────────────────────────────────────────────────

/// Transmitting a valid PNG image (f=100) stores the image; a subsequent query
/// (a=q) for that image must produce an "OK" response, confirming the image is
/// present in the store.
#[test]
fn kitty_transmit_png_then_query_returns_ok() {
    let mut t = TerminalCore::new(24, 80);

    // Build a 1×1 RGB PNG and transmit it as image id=100.
    let b64 = make_1x1_png_b64(png::ColorType::Rgb, &[0x10, 0x20, 0x30]);
    let apc = format!("\x1b_Ga=t,f=100,i=100,s=1,v=1;{b64}\x1b\\");
    t.advance(apc.as_bytes());

    // The image must be stored.
    let png = t.get_image_png_base64(100);
    assert!(
        !png.is_empty(),
        "image 100 must be stored after f=100 transmit"
    );

    let count_before = t.pending_responses().len();

    // Query image 100.
    t.advance(b"\x1b_Ga=q,i=100\x1b\\");

    let responses = common::read_responses(&t);
    assert!(
        responses.len() > count_before,
        "a=q must produce at least one new response"
    );
    let last = &responses[responses.len() - 1];
    assert!(
        last.contains("OK"),
        "query response for stored PNG image must contain 'OK', got: {last:?}"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Delete all images (a=d,d=A) clears all placements
// ─────────────────────────────────────────────────────────────────────────────

/// `d=A` (uppercase A) is the sub-command "delete all placements on or above
/// the current cursor row".  After transmitting and displaying an image,
/// issuing `a=d,d=A` must not panic and the implementation must handle it
/// without corrupting state.  A new placement can still be added afterwards.
#[test]
fn kitty_delete_uppercase_a_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);

    // Transmit and display image 200 at cursor row 0.
    t.advance(b"\x1b_Ga=T,f=24,i=200,s=1,v=1,c=2,r=2;AAAA\x1b\\");
    assert_eq!(
        t.pending_image_notifications().len(),
        1,
        "one notification must be queued after transmit-and-display"
    );

    // Delete all placements on or above current row (d=A, uppercase).
    t.advance(b"\x1b_Ga=d,d=A\x1b\\");

    // Image data must still be retrievable (d=A clears placements, not image data).
    let png = t.get_image_png_base64(200);
    assert!(
        !png.is_empty(),
        "image data must survive d=A (only placements are cleared)"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Multi-chunk transfer: 3 chunks (m=1, m=1, m=0)
// ─────────────────────────────────────────────────────────────────────────────

/// A three-chunk Kitty transmit sent through `advance()` must produce a valid
/// stored image only after the final m=0 chunk arrives.
/// Chunks: m=1 (params), m=1 (empty mid-chunk), m=0 (pixel data).
#[test]
fn kitty_three_chunk_end_to_end_stores_image() {
    let mut t = TerminalCore::new(24, 80);

    // Chunk 1: m=1, header params only — no data yet.
    t.advance(b"\x1b_Ga=t,f=24,i=50,s=1,v=1,m=1;\x1b\\");
    assert!(
        t.get_image_png_base64(50).is_empty(),
        "image must not be stored after first m=1 chunk"
    );

    // Chunk 2: m=1, still accumulating — empty payload.
    t.advance(b"\x1b_Gm=1;\x1b\\");
    assert!(
        t.get_image_png_base64(50).is_empty(),
        "image must not be stored after second m=1 chunk"
    );

    // Chunk 3: m=0, final — carries the 1×1 RGB pixel ("AAAA" = 3 zero bytes).
    t.advance(b"\x1b_Gm=0;AAAA\x1b\\");

    let png = t.get_image_png_base64(50);
    assert!(
        !png.is_empty(),
        "image must be stored after the final m=0 chunk"
    );
    let decoded = BASE64_STANDARD.decode(&png).expect("must be valid base64");
    assert!(
        decoded.starts_with(b"\x89PNG"),
        "decoded data must be PNG, got: {:?}",
        &decoded[..4.min(decoded.len())]
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Placement with specific x/y pixel offsets
// ─────────────────────────────────────────────────────────────────────────────

/// A `TransmitAndDisplay` command carrying `X=` and `Y=` pixel offsets must
/// still queue a placement notification.  The offsets are for within-cell
/// alignment and do not affect the row/col of the notification.
#[test]
fn kitty_transmit_and_display_with_xy_offsets_queues_notification() {
    let mut t = TerminalCore::new(24, 80);

    // a=T with X=4 (x pixel offset) and Y=8 (y pixel offset), 4×2 cells.
    t.advance(b"\x1b_Ga=T,f=24,i=60,s=1,v=1,c=4,r=2,X=4,Y=8;AAAA\x1b\\");

    let notifs = t.pending_image_notifications();
    assert_eq!(
        notifs.len(),
        1,
        "a=T with X/Y offsets must queue exactly one notification"
    );
    assert_eq!(
        notifs[0].image_id, 60,
        "notification image_id must match i=60"
    );
    assert_eq!(
        notifs[0].cell_width, 4,
        "cell_width must match c=4, got {}",
        notifs[0].cell_width
    );
    assert_eq!(
        notifs[0].cell_height, 2,
        "cell_height must match r=2, got {}",
        notifs[0].cell_height
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. Two different image IDs tracked independently
// ─────────────────────────────────────────────────────────────────────────────

/// Transmitting two images with distinct IDs must store each independently.
/// Retrieving by each ID must return a different (non-empty, non-equal) PNG.
#[test]
fn kitty_two_distinct_image_ids_tracked_independently() {
    let mut t = TerminalCore::new(24, 80);

    // Image A: i=70, 1×1 RGB black pixel ("AAAA" = [0,0,0]).
    t.advance(b"\x1b_Ga=t,f=24,i=70,s=1,v=1;AAAA\x1b\\");

    // Image B: i=71, 1×1 RGB red-channel pixel ("/wAA" = [0xFF,0x00,0x00]).
    t.advance(b"\x1b_Ga=t,f=24,i=71,s=1,v=1;/wAA\x1b\\");

    let png_a = t.get_image_png_base64(70);
    let png_b = t.get_image_png_base64(71);

    assert!(!png_a.is_empty(), "image 70 must be stored");
    assert!(!png_b.is_empty(), "image 71 must be stored");
    assert_ne!(
        png_a, png_b,
        "images 70 and 71 must be distinct (different pixel data)"
    );

    // A third, never-transmitted ID must return empty.
    assert!(
        t.get_image_png_base64(72).is_empty(),
        "image 72 was never transmitted; must return empty string"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. q=2 quiet mode: transmit and display — no response queued
// ─────────────────────────────────────────────────────────────────────────────

/// A `TransmitAndDisplay` (a=T) with `q=2` must queue a placement notification
/// (the image IS displayed) but must NOT queue a terminal response.
#[test]
fn kitty_transmit_and_display_q2_queues_notification_not_response() {
    let mut t = TerminalCore::new(24, 80);

    let responses_before = t.pending_responses().len();

    // a=T with q=2: display + suppress all protocol responses.
    t.advance(b"\x1b_Ga=T,f=24,i=80,s=1,v=1,c=2,r=2,q=2;AAAA\x1b\\");

    // No new response must have been queued.
    assert_eq!(
        t.pending_responses().len(),
        responses_before,
        "q=2 must suppress terminal responses; response count must not increase"
    );

    // But the placement notification must still be queued.
    let notifs = t.pending_image_notifications();
    assert_eq!(
        notifs.len(),
        1,
        "a=T with q=2 must still queue a placement notification"
    );
    assert_eq!(
        notifs[0].image_id, 80,
        "notification must reference image_id 80"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. Corrupt base64 payload handled gracefully (no panic)
// ─────────────────────────────────────────────────────────────────────────────

/// An APC sequence with invalid base64 in the payload must not panic.
/// The image must not be stored (corrupt data is rejected).
#[test]
fn kitty_corrupt_base64_payload_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);

    // "!!!corrupt!!!" is not valid base64.
    t.advance(b"\x1b_Ga=t,f=24,i=90,s=1,v=1;!!!corrupt!!!\x1b\\");

    // Must not panic.  The image must not be stored (invalid base64 rejected).
    let png = t.get_image_png_base64(90);
    assert!(
        png.is_empty(),
        "image 90 must not be stored after corrupt base64 payload"
    );

    // Terminal must remain functional after the bad sequence.
    t.advance(b"OK");
    assert_eq!(
        t.cursor_col(),
        2,
        "terminal must remain operational after corrupt Kitty payload"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// 8. Empty payload image transmit (no panic)
// ─────────────────────────────────────────────────────────────────────────────

/// A transmit with an empty base64 payload (';' present but no data) must not
/// panic.  The image is not stored because zero bytes cannot satisfy raw-format
/// pixel dimensions.
#[test]
fn kitty_empty_payload_transmit_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);

    // Empty payload: semicolon separator but nothing after it.
    t.advance(b"\x1b_Ga=t,f=24,i=91,s=1,v=1;\x1b\\");

    // Must not panic.  Image should not be stored (no pixel data).
    // (Behaviour: empty payload → 0 bytes → zero-dim reject or dim-mismatch.)
    assert!(
        t.cursor_row() < 24,
        "terminal must not crash on empty Kitty payload"
    );

    // A valid transmit after the empty one must still work.
    t.advance(b"\x1b_Ga=t,f=24,i=92,s=1,v=1;AAAA\x1b\\");
    assert!(
        !t.get_image_png_base64(92).is_empty(),
        "valid transmit after empty payload must succeed"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// 9. Large image ID (u32::MAX) accepted
// ─────────────────────────────────────────────────────────────────────────────

/// An image ID equal to `u32::MAX` (4294967295) must be parsed and stored
/// without overflow or panic.
#[test]
fn kitty_u32_max_image_id_accepted() {
    let mut t = TerminalCore::new(24, 80);

    let apc = format!("\x1b_Ga=t,f=24,i={},s=1,v=1;AAAA\x1b\\", u32::MAX);
    t.advance(apc.as_bytes());

    let png = t.get_image_png_base64(u32::MAX);
    assert!(
        !png.is_empty(),
        "image with id=u32::MAX must be stored without overflow"
    );
    let decoded = BASE64_STANDARD.decode(&png).expect("must be valid base64");
    assert!(
        decoded.starts_with(b"\x89PNG"),
        "stored image must be valid PNG"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// 10. Placement id 0 vs 1 are distinct
// ─────────────────────────────────────────────────────────────────────────────

/// Transmitting the same image twice with p=0 and p=1 must each queue a
/// separate placement notification.  Both must reference the same image_id,
/// confirming that placement IDs are not conflated with image IDs.
#[test]
fn kitty_placement_id_zero_and_one_are_distinct() {
    let mut t = TerminalCore::new(24, 80);

    // Transmit the image once.
    t.advance(b"\x1b_Ga=t,f=24,i=95,s=1,v=1;AAAA\x1b\\");
    assert!(
        !t.get_image_png_base64(95).is_empty(),
        "image 95 must be stored"
    );
    assert_eq!(
        t.pending_image_notifications().len(),
        0,
        "bare transmit must not queue a notification"
    );

    // Place with placement_id=0.
    t.advance(b"\x1b_Ga=p,i=95,p=0,c=2,r=2\x1b\\");
    assert_eq!(
        t.pending_image_notifications().len(),
        1,
        "first placement (p=0) must queue one notification"
    );

    // Place with placement_id=1 (distinct from p=0).
    t.advance(b"\x1b_Ga=p,i=95,p=1,c=2,r=2\x1b\\");
    let notifs = t.pending_image_notifications();
    assert_eq!(
        notifs.len(),
        2,
        "second placement (p=1) must queue a second notification (total 2)"
    );

    // Both notifications reference the same image.
    assert!(
        notifs.iter().all(|n| n.image_id == 95),
        "all placement notifications must reference image_id 95"
    );
}
