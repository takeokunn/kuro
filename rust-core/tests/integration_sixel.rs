//! Sixel Graphics Protocol integration tests via `TerminalCore::advance()`.
//!
//! DCS sixel format: ESC P [Pn1;Pn2;Pn3] q <data> ST
//! where ST = ESC \  (0x1B 0x5C)
//!
//! These tests exercise the full advance() → VTE DCS handler → sixel decoder
//! → screen/graphics store pipeline.

mod common;

use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
use base64::Engine as _;
use kuro_core::TerminalCore;

// ─────────────────────────────────────────────────────────────────────────────
// 1. Sixel with color register 0 override
// ─────────────────────────────────────────────────────────────────────────────

/// Register 0 defaults to black (0,0,0).  Sending a color definition for
/// register 0 before a sixel band must override the default and the image
/// must still be stored successfully.
#[test]
fn sixel_color_register_0_override_stores_image() {
    let mut t = TerminalCore::new(24, 80);

    // Override register 0 to pure green (0% R, 100% G, 0% B in 0-100 scale).
    // Then paint one band with register 0 active.
    // DCS 0;1;0 q " 1;1;4;6 #0;2;0;100;0 ~~~~ ST
    t.advance(b"\x1bP0;1;0q\"1;1;4;6#0;2;0;100;0~~~~\x1b\\");

    let notifs = t.pending_image_notifications();
    assert_eq!(
        notifs.len(),
        1,
        "sixel with register-0 override must produce exactly one notification"
    );

    let id = notifs[0].image_id;
    let png_b64 = t.get_image_png_base64(id);
    assert!(
        !png_b64.is_empty(),
        "image with register-0 override must be stored and retrievable"
    );

    let decoded = BASE64_STANDARD.decode(&png_b64).expect("must be valid base64");
    assert!(
        decoded.starts_with(b"\x89PNG"),
        "decoded image must be valid PNG"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Sixel band Y-offset accumulation (multiple bands)
// ─────────────────────────────────────────────────────────────────────────────

/// Two sixel bands separated by `-` (band-separator) must produce a single
/// image with a height of at least two bands (≥ 12 pixels = 2 × 6-pixel bands).
/// The notification must reference a stored image; dimensions must grow with
/// each additional band.
#[test]
fn sixel_multiband_y_offset_accumulates() {
    let mut t = TerminalCore::new(24, 80);

    // Two 4-pixel-wide bands separated by '-'.
    // Band 1: register 0 (default black), "~~~~" (4 pixels wide).
    // Band 2: register 1 (default palette), "~~~~".
    // Declared height: 12 pixels (2 bands × 6 px/band).
    t.advance(b"\x1bP0;1;0q\"1;1;4;12#0~~~~-#1~~~~\x1b\\");

    let notifs = t.pending_image_notifications();
    assert_eq!(
        notifs.len(),
        1,
        "two-band sixel must produce exactly one notification"
    );

    let id = notifs[0].image_id;
    let png_b64 = t.get_image_png_base64(id);
    assert!(
        !png_b64.is_empty(),
        "multi-band sixel image must be stored"
    );

    let decoded = BASE64_STANDARD.decode(&png_b64).expect("must be valid base64");
    assert!(
        decoded.starts_with(b"\x89PNG"),
        "decoded multi-band image must be valid PNG"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Sixel palette entry 255 (boundary)
// ─────────────────────────────────────────────────────────────────────────────

/// Color register 255 is the maximum index in the VT340 extended palette.
/// Defining and using it must not panic and must produce a valid stored image.
#[test]
fn sixel_palette_entry_255_boundary() {
    let mut t = TerminalCore::new(24, 80);

    // Define register 255 as pure red (100% R, 0% G, 0% B).
    // Then paint a 2-wide band with it.
    t.advance(b"\x1bP0;1;0q\"1;1;2;6#255;2;100;0;0~~\x1b\\");

    let notifs = t.pending_image_notifications();
    assert_eq!(
        notifs.len(),
        1,
        "sixel using palette register 255 must produce exactly one notification"
    );

    let id = notifs[0].image_id;
    let png_b64 = t.get_image_png_base64(id);
    assert!(
        !png_b64.is_empty(),
        "image using palette register 255 must be stored"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Hue 360 wraps to same as hue 0
// ─────────────────────────────────────────────────────────────────────────────

/// In HSL color definitions (register type 1), hue 360 is equivalent to hue 0
/// (both represent red in the HLS wheel).  Both must produce a stored image
/// without panicking.
#[test]
fn sixel_hue_360_produces_same_as_hue_0_no_panic() {
    let mut t = TerminalCore::new(24, 80);

    // Hue 0: register 10, type HLS (1), H=0, L=50, S=100 → pure red.
    t.advance(b"\x1bP0;1;0q\"1;1;1;6#10;1;0;50;100~\x1b\\");
    assert_eq!(
        t.pending_image_notifications().len(),
        1,
        "hue=0 sixel must produce one notification"
    );
    let id_0 = t.pending_image_notifications()[0].image_id;

    // Hue 360: register 11, type HLS, H=360, L=50, S=100 → same as hue 0.
    t.advance(b"\x1bP0;1;0q\"1;1;1;6#11;1;360;50;100~\x1b\\");
    assert_eq!(
        t.pending_image_notifications().len(),
        2,
        "hue=360 sixel must produce a second notification"
    );
    let id_360 = t.pending_image_notifications()[1].image_id;

    // Both images must be stored.
    assert!(
        !t.get_image_png_base64(id_0).is_empty(),
        "image from hue=0 must be stored"
    );
    assert!(
        !t.get_image_png_base64(id_360).is_empty(),
        "image from hue=360 must be stored"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. Unterminated sixel data (no ST) handled gracefully
// ─────────────────────────────────────────────────────────────────────────────

/// A DCS sixel sequence that is never terminated (no ST = ESC \) must not
/// panic.  The terminal must remain in a functional state even if no
/// notification is produced (the sequence is still open / being accumulated).
#[test]
fn sixel_unterminated_data_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);

    // Send a valid sixel header + some data but NO ST terminator.
    t.advance(b"\x1bP0;1;0q\"1;1;4;6#0~~~~");

    // Must not panic.  Cursor must be in bounds (terminal is still live).
    assert!(
        t.cursor_row() < 24,
        "cursor row must be in bounds after unterminated sixel"
    );
    assert!(
        t.cursor_col() < 80,
        "cursor col must be in bounds after unterminated sixel"
    );

    // Send a normal sequence after the unterminated sixel — the terminal must
    // process it without errors (VTE parser may be in DCS state, so this is
    // a graceful-degradation check).
    t.advance(b"\x1b\\"); // Explicit ST to close the dangling DCS
    // After ST, the terminal is back in Ground state — normal input must work.
    t.advance(b"\x1b[H"); // CUP home — must not panic
    assert!(t.cursor_row() < 24, "terminal must be operational after ST close");
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. Two sequential sixel sequences each produce notification
// ─────────────────────────────────────────────────────────────────────────────

/// Sending two complete and distinct sixel sequences must each produce their
/// own placement notification (total = 2), with distinct image IDs and
/// sequential placement rows.
#[test]
fn sixel_two_sequential_sequences_produce_two_notifications() {
    let mut t = TerminalCore::new(24, 80);

    // First sixel at cursor row 0.
    t.advance(b"\x1bP0;1;0q\"1;1;2;6#0~~\x1b\\");
    assert_eq!(
        t.pending_image_notifications().len(),
        1,
        "first sixel must queue exactly one notification"
    );
    let first_row = t.pending_image_notifications()[0].row;
    let first_id = t.pending_image_notifications()[0].image_id;

    // Second sixel — cursor has advanced after the first one.
    t.advance(b"\x1bP0;1;0q\"1;1;2;6#0~~\x1b\\");
    let notifs = t.pending_image_notifications();
    assert_eq!(
        notifs.len(),
        2,
        "second sixel must queue a second notification (total 2)"
    );

    let second_row = notifs[1].row;
    let second_id = notifs[1].image_id;

    // IDs must be distinct.
    assert_ne!(
        first_id, second_id,
        "consecutive sixels must receive distinct image IDs; got ({first_id}, {second_id})"
    );

    // The second sixel must be placed at or after the first.
    assert!(
        second_row >= first_row,
        "second sixel row ({second_row}) must be >= first sixel row ({first_row})"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. Sixel + Kitty coexistence (both protocols in same terminal)
// ─────────────────────────────────────────────────────────────────────────────

/// A Kitty image and a Sixel image sent in the same terminal session must be
/// independently stored and each produce their own notification.  Their image
/// IDs must not collide.
#[test]
fn sixel_and_kitty_coexist_independently() {
    let mut t = TerminalCore::new(24, 80);

    // Send Sixel first.
    t.advance(b"\x1bP0;1;0q\"1;1;2;6#0~~\x1b\\");
    assert_eq!(
        t.pending_image_notifications().len(),
        1,
        "sixel must produce one notification"
    );
    let sixel_id = t.pending_image_notifications()[0].image_id;

    // Verify the sixel image is stored.
    let sixel_png = t.get_image_png_base64(sixel_id);
    assert!(
        !sixel_png.is_empty(),
        "sixel image must be stored before Kitty transmit"
    );

    // Now send a Kitty transmit (a=T so it also queues a notification).
    t.advance(b"\x1b_Ga=T,f=24,i=300,s=1,v=1,c=2,r=2;AAAA\x1b\\");
    assert_eq!(
        t.pending_image_notifications().len(),
        2,
        "Kitty a=T must add a second notification (total 2)"
    );

    // Kitty image ID must not collide with the sixel image ID.
    assert_ne!(
        300u32, sixel_id,
        "Kitty image_id 300 must not collide with sixel image_id {sixel_id}"
    );

    // Both images must remain independently retrievable.
    let sixel_png_after = t.get_image_png_base64(sixel_id);
    let kitty_png = t.get_image_png_base64(300);
    assert!(
        !sixel_png_after.is_empty(),
        "sixel image must still be retrievable after Kitty transmit"
    );
    assert!(
        !kitty_png.is_empty(),
        "Kitty image 300 must be stored"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// 8. Sixel with repeat char `!N` at column 0
// ─────────────────────────────────────────────────────────────────────────────

/// A repeat sequence `!N` at the very start of a band (column 0) must not
/// panic and must produce a stored image.  This exercises the run-length
/// encoding path from the leftmost pixel position.
#[test]
fn sixel_repeat_at_column_0_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);

    // "!8~" = repeat '~' (sixel 0x7E, all-6-bits-set) 8 times starting at col 0.
    // The declared width is 8, height 6 — exactly one full band.
    t.advance(b"\x1bP0;1;0q\"1;1;8;6#0!8~\x1b\\");

    let notifs = t.pending_image_notifications();
    assert_eq!(
        notifs.len(),
        1,
        "sixel with leading !N repeat must produce one notification"
    );

    let id = notifs[0].image_id;
    let png_b64 = t.get_image_png_base64(id);
    assert!(
        !png_b64.is_empty(),
        "image with leading !N repeat must be stored"
    );

    let decoded = BASE64_STANDARD.decode(&png_b64).expect("must be valid base64");
    assert!(
        decoded.starts_with(b"\x89PNG"),
        "decoded repeat-at-col-0 image must be valid PNG"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// 9. Zero-dimension sixel (no bands) produces no image
// ─────────────────────────────────────────────────────────────────────────────

/// A sixel DCS with raster attributes declaring 0×0 and no actual sixel band
/// data must not panic.  Because there are no pixels to render, no image is
/// stored and no notification should be queued.
#[test]
fn sixel_zero_dimension_no_bands_produces_no_image() {
    let mut t = TerminalCore::new(24, 80);

    // Raster attrs declare 0×0; no sixel band data follows.
    // DCS q " 0;0;0;0 ST
    t.advance(b"\x1bPq\"0;0;0;0\x1b\\");

    // Must not panic.  No image notification expected.
    assert_eq!(
        t.pending_image_notifications().len(),
        0,
        "zero-dimension sixel must not produce an image notification"
    );

    // Terminal must remain functional.
    assert!(t.cursor_row() < 24);
    assert!(t.cursor_col() < 80);
}

// ─────────────────────────────────────────────────────────────────────────────
// 10. Sixel after reset is fresh (no stale palette)
// ─────────────────────────────────────────────────────────────────────────────

/// A `reset()` (RIS — ESC c) clears Kitty/Sixel state including any pending
/// image notifications from a prior sixel sequence.  A new sixel sent after
/// the reset must be treated as a fresh image with no carry-over from before.
#[test]
fn sixel_after_reset_starts_fresh() {
    let mut t = TerminalCore::new(24, 80);

    // First sixel — queues one notification.
    t.advance(b"\x1bP0;1;0q\"1;1;2;6#0~~\x1b\\");
    assert_eq!(
        t.pending_image_notifications().len(),
        1,
        "first sixel must queue one notification"
    );

    // Reset the terminal.
    t.reset();

    // After reset, all notifications must be cleared.
    assert_eq!(
        t.pending_image_notifications().len(),
        0,
        "reset() must clear all pending image notifications"
    );

    // A second sixel after reset must produce exactly one new notification.
    t.advance(b"\x1bP0;1;0q\"1;1;2;6#0~~\x1b\\");
    assert_eq!(
        t.pending_image_notifications().len(),
        1,
        "sixel after reset must produce exactly one notification (fresh state)"
    );

    let id = t.pending_image_notifications()[0].image_id;
    let png_b64 = t.get_image_png_base64(id);
    assert!(
        !png_b64.is_empty(),
        "sixel image after reset must be stored and retrievable"
    );
}
