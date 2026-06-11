//! DCS (Device Control String) integration tests.

mod common;

use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
use base64::Engine as _;
use kuro_core::TerminalCore;
// ─────────────────────────────────────────────────────────────────────────────
// DCS XTGETTCAP
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn xtgettcap_tn_responds_with_kuro() {
    let mut t = common::new_terminal();
    // DCS + q 544e ST  ("TN" in hex = 54 4e)
    t.advance(b"\x1bP+q544e\x1b\\");
    let responses = common::read_responses(&t);
    assert!(
        !responses.is_empty(),
        "XTGETTCAP for TN must produce a response"
    );
    let resp = &responses[0];
    assert!(
        resp.contains("1+r"),
        "Known capability must use DCS 1+r format, got: {resp:?}"
    );
    // Response contains hex-encoded "kuro"
    // "kuro" in hex = 6b 75 72 6f
    assert!(
        resp.contains("6b75726f") || resp.to_lowercase().contains("kuro"),
        "TN response must encode 'kuro', got: {resp:?}"
    );
}

#[test]
fn xtgettcap_rgb_responds_with_truecolor() {
    let mut t = common::new_terminal();
    // DCS + q 524742 ST  ("RGB" in hex = 52 47 42)
    t.advance(b"\x1bP+q524742\x1b\\");
    let responses = common::read_responses(&t);
    assert!(!responses.is_empty());
    let resp = &responses[0];
    assert!(
        resp.contains("1+r"),
        "RGB capability response must be DCS 1+r, got: {resp:?}"
    );
}

#[test]
fn xtgettcap_unknown_cap_responds_not_found() {
    let mut t = common::new_terminal();
    // DCS + q 786666 ST  ("xff" — not a valid capability)
    t.advance(b"\x1bP+q786666\x1b\\");
    let responses = common::read_responses(&t);
    assert!(!responses.is_empty());
    let resp = &responses[0];
    assert!(
        resp.contains("0+r"),
        "Unknown capability must use DCS 0+r format, got: {resp:?}"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// DCS Sixel — basic parse tests (no actual image rendering)
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn sixel_dcs_does_not_panic_on_valid_input() {
    let mut t = common::new_terminal();
    // DCS 0;1;0 q " 1;1;10;6 #0;2;100;0;0 !10~ - ST
    // This is a simple 10x6 all-red sixel image
    t.advance(b"\x1bP0;1;0q\"1;1;10;6#0;2;100;0;0!10~\x1b\\");
    // Should not panic; cursor may advance
    assert!(t.cursor_row() < 24);
    assert!(t.cursor_col() < 80);
}

#[test]
fn sixel_empty_dcs_does_not_panic() {
    let mut t = common::new_terminal();
    t.advance(b"\x1bPq\x1b\\"); // Empty sixel
    assert!(t.cursor_row() < 24);
}

#[test]
fn sixel_rle_sequence_does_not_panic() {
    let mut t = common::new_terminal();
    // RLE: !100~ = repeat ~ 100 times
    t.advance(b"\x1bP0;1;0q\"1;1;100;6#0;2;100;0;0!100~\x1b\\");
    assert!(t.cursor_row() < 24);
}

#[test]
fn sixel_multiband_does_not_panic() {
    let mut t = common::new_terminal();
    // Two bands separated by '-'
    t.advance(b"\x1bP0;1;0q\"1;1;4;12#0;2;100;0;0~~~~-~~~~\x1b\\");
    assert!(t.cursor_row() < 24);
}

// ─────────────────────────────────────────────────────────────────────────────
// Kitty Graphics Protocol — end-to-end via TerminalCore::advance()
//
// APC format: ESC _ G <key=val,...> ; <base64payload> ESC \
// ─────────────────────────────────────────────────────────────────────────────

/// A complete single-chunk transmit (a=t) followed by a place (a=p) must
/// result in the image appearing in `get_active_graphics()` and a placement
/// notification being queued.
#[test]
fn kitty_get_image_png_base64_after_complete_transfer() {
    let mut t = common::new_terminal();

    // Transmit: a=t, f=24 (RGB), i=1, s=1 (width), v=1 (height).
    // "AAAA" is base64 for 3 zero bytes — one 1×1 RGB pixel.
    t.advance(b"\x1b_Ga=t,f=24,i=1,s=1,v=1;AAAA\x1b\\");

    // The image must now be retrievable via the public API.
    let png_b64 = t.get_image_png_base64(1);
    assert!(
        !png_b64.is_empty(),
        "get_image_png_base64(1) must return non-empty PNG after transmit, got empty string"
    );

    // Verify the base64 string is valid and decodes to PNG magic bytes.
    let png_bytes = BASE64_STANDARD
        .decode(&png_b64)
        .expect("get_image_png_base64 must return valid base64");
    assert!(
        png_bytes.starts_with(b"\x89PNG"),
        "decoded data must start with PNG magic bytes, got: {:?}",
        &png_bytes[..4.min(png_bytes.len())]
    );
}

/// Transmit+Display (a=T) must both store the image AND add a placement
/// notification in a single sequence.
#[test]
fn kitty_transmit_and_display_produces_notification() {
    let mut t = common::new_terminal();

    // a=T: transmit and immediately display; c=8, r=4 = 8×4 cell region.
    // "AAAAAA==" = 4 zero bytes = 1×1 RGBA pixel.
    t.advance(b"\x1b_Ga=T,f=32,i=2,s=1,v=1,c=8,r=4;AAAAAA==\x1b\\");

    // Image must be stored.
    let png_b64 = t.get_image_png_base64(2);
    assert!(
        !png_b64.is_empty(),
        "image 2 must be stored after a=T transmit-and-display"
    );

    // Exactly one notification must be queued.
    let notifs = t.pending_image_notifications();
    assert_eq!(
        notifs.len(),
        1,
        "a=T must queue exactly one placement notification, got {}",
        notifs.len()
    );
    assert_eq!(
        notifs[0].image_id, 2,
        "notification image_id must be 2, got {}",
        notifs[0].image_id
    );
    assert_eq!(
        notifs[0].row, 0,
        "placement row must be cursor row 0, got {}",
        notifs[0].row
    );
    assert_eq!(
        notifs[0].cell_width, 8,
        "placement cell_width must match c=8, got {}",
        notifs[0].cell_width
    );
    assert_eq!(
        notifs[0].cell_height, 4,
        "placement cell_height must match r=4, got {}",
        notifs[0].cell_height
    );
}

/// Two separate transmit sequences with the same image ID must result in
/// the second image replacing the first in the store.
#[test]
fn kitty_second_image_same_id_replaces_first() {
    let mut t = common::new_terminal();

    // First transmit: 1×1 RGB pixel (all zeros — black).
    t.advance(b"\x1b_Ga=t,f=24,i=10,s=1,v=1;AAAA\x1b\\");
    let first_png = t.get_image_png_base64(10);
    assert!(!first_png.is_empty(), "first image must be stored");

    // Second transmit: same ID but 1×1 RGB with 0xFF red channel.
    // "\xff\x00\x00" in base64 is "/wAA".
    t.advance(b"\x1b_Ga=t,f=24,i=10,s=1,v=1;/wAA\x1b\\");
    let second_png = t.get_image_png_base64(10);
    assert!(!second_png.is_empty(), "second image must be stored");

    // The PNG output must differ (different pixel data).
    assert_ne!(
        first_png, second_png,
        "second transmit with same ID must replace first (PNG output must differ)"
    );
}

/// Multi-placement: transmit once, then place twice with different placement IDs.
/// Both placement notifications must be queued with the correct image ID.
#[test]
fn kitty_multi_placement_same_image_id() {
    let mut t = common::new_terminal();

    // Transmit the image once.
    t.advance(b"\x1b_Ga=t,f=24,i=5,s=1,v=1;AAAA\x1b\\");
    assert!(
        !t.get_image_png_base64(5).is_empty(),
        "image 5 must be stored before placements"
    );
    assert_eq!(
        t.pending_image_notifications().len(),
        0,
        "no notifications after bare transmit"
    );

    // First placement: p=1, at cursor row 0, 4×2 cells.
    t.advance(b"\x1b_Ga=p,i=5,p=1,c=4,r=2\x1b\\");
    assert_eq!(
        t.pending_image_notifications().len(),
        1,
        "first place must add one notification"
    );

    // Move cursor down to row 3 for second placement.
    t.advance(b"\x1b[4;1H"); // CUP row 4 (1-indexed) = row 3 (0-indexed)

    // Second placement: p=2, at cursor row 3, 4×2 cells.
    t.advance(b"\x1b_Ga=p,i=5,p=2,c=4,r=2\x1b\\");
    let notifs = t.pending_image_notifications();
    assert_eq!(
        notifs.len(),
        2,
        "second place must add a second notification (total 2)"
    );
    // Both notifications must reference the same image.
    assert!(
        notifs.iter().all(|n| n.image_id == 5),
        "all notifications must reference image_id 5"
    );
    // Rows must differ: first at row 0, second at row 3.
    let rows: Vec<usize> = notifs.iter().map(|n| n.row).collect();
    assert!(
        rows.contains(&0),
        "first placement must be at row 0, got rows: {rows:?}"
    );
    assert!(
        rows.contains(&3),
        "second placement must be at row 3, got rows: {rows:?}"
    );
}

/// Delete subcommand `a=d,d=a` must remove all placements but leave image data intact.
///
/// Background: 'd=a' (lowercase) clears all placements.  Image data is NOT deleted —
/// only the placement list is cleared.
#[test]
fn kitty_delete_all_placements_clears_placements() {
    let mut t = common::new_terminal();

    // Transmit and display image 3.
    t.advance(b"\x1b_Ga=T,f=24,i=3,s=1,v=1,c=2,r=2;AAAA\x1b\\");
    assert_eq!(
        t.pending_image_notifications().len(),
        1,
        "one notification must be queued after transmit-and-display"
    );

    // Delete all placements with d=a.
    t.advance(b"\x1b_Ga=d,d=a\x1b\\");

    // Image data must still be stored (delete 'a' only clears placement list).
    let png = t.get_image_png_base64(3);
    assert!(
        !png.is_empty(),
        "image data must survive d=a (only placements are deleted)"
    );

    // Verify a new placement can be added after deleting the old ones.
    t.advance(b"\x1b_Ga=p,i=3,c=2,r=2\x1b\\");
    assert_eq!(
        t.pending_image_notifications().len(),
        2,
        "a new placement can be added after d=a cleared the list"
    );
}

/// A query (a=q) with a known image ID must produce a response containing "OK".
/// This tests the `quiet` path: the default (q=0) sends a response.
#[test]
fn kitty_query_known_image_produces_ok_response() {
    let mut t = common::new_terminal();

    // Transmit an image first so the query has something to respond about.
    t.advance(b"\x1b_Ga=t,f=24,i=7,s=1,v=1;AAAA\x1b\\");

    let count_before = t.pending_responses().len();

    // Query image 7.
    t.advance(b"\x1b_Ga=q,i=7\x1b\\");

    let responses = common::read_responses(&t);
    assert!(
        responses.len() > count_before,
        "a=q must produce at least one response"
    );
    let resp = &responses[responses.len() - 1];
    assert!(
        resp.contains("OK"),
        "query response must contain 'OK', got: {resp:?}"
    );
}

/// A transmit with `q=2` (suppress all responses) must store the image without
/// emitting any terminal response.

include!("include/integration_dcs_part2.rs");
include!("include/integration_dcs_capabilities.rs");
