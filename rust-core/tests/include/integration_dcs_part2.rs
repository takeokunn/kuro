use super::*;

#[test]
fn kitty_quiet_two_suppresses_response() {
    let mut t = common::new_terminal();

    let count_before = t.pending_responses().len();

    // Transmit with q=2 — all responses suppressed.
    t.advance(b"\x1b_Ga=t,f=24,i=8,s=1,v=1,q=2;AAAA\x1b\\");

    // No new response must have been queued.
    assert_eq!(
        t.pending_responses().len(),
        count_before,
        "q=2 must suppress all responses; pending_responses count must not increase"
    );

    // But the image must still be stored.
    let png = t.get_image_png_base64(8);
    assert!(
        !png.is_empty(),
        "image must be stored even when q=2 suppresses the response"
    );
}

/// Multi-chunk accumulation: a two-chunk RGBA transfer using m=1 / m=0 must
/// produce a valid stored image.
#[test]
fn kitty_two_chunk_accumulation_produces_valid_image() {
    let mut t = common::new_terminal();

    // Chunk 1: m=1, carries header params and empty payload (accumulation starts).
    // Using f=24 (RGB), 1×1 image.  No data yet.
    t.advance(b"\x1b_Ga=t,f=24,i=15,s=1,v=1,m=1;\x1b\\");

    // Image must NOT be stored yet (still accumulating).
    assert!(
        t.get_image_png_base64(15).is_empty(),
        "image must not be stored after m=1 (still accumulating)"
    );

    // Chunk 2: m=0, supplies the pixel data ("AAAA" = 3 bytes = 1×1 RGB pixel).
    t.advance(b"\x1b_Gm=0;AAAA\x1b\\");

    // Image must now be stored.
    let png = t.get_image_png_base64(15);
    assert!(
        !png.is_empty(),
        "image must be stored after final m=0 chunk"
    );
    let decoded = BASE64_STANDARD.decode(&png).expect("must be valid base64");
    assert!(
        decoded.starts_with(b"\x89PNG"),
        "decoded data must be PNG, got: {:?}",
        &decoded[..4.min(decoded.len())]
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sixel — end-to-end coverage via TerminalCore::advance()
// ─────────────────────────────────────────────────────────────────────────────

/// A sixel sequence must produce an image placement notification visible via
/// `pending_image_notifications()`.
#[test]
fn sixel_produces_image_notification_via_public_api() {
    let mut t = common::new_terminal();

    assert_eq!(
        t.pending_image_notifications().len(),
        0,
        "no notifications before any sixel data"
    );

    // Minimal valid sixel: raster attrs 1×6, color #0, one sixel band.
    // DCS 0;1;0 q " 1;1;1;6 #0 ~ ST
    t.advance(b"\x1bP0;1;0q\"1;1;1;6#0~\x1b\\");

    let notifs = t.pending_image_notifications();
    assert_eq!(
        notifs.len(),
        1,
        "one sixel sequence must produce exactly one notification"
    );
    assert_eq!(
        notifs[0].row, 0,
        "sixel must be placed at the cursor row (0), got {}",
        notifs[0].row
    );
    assert_eq!(
        notifs[0].col, 0,
        "sixel must be placed at the cursor col (0), got {}",
        notifs[0].col
    );
}

/// A sixel sequence stores image data retrievable via `get_image_png_base64`.
#[test]
fn sixel_image_retrievable_as_png_base64() {
    let mut t = common::new_terminal();

    // A 10×6 all-red sixel: raster attrs, color register 0 = red (100% R, 0% G, 0% B).
    // "#0;2;100;0;0" sets register 0 to RGB(255,0,0); "!10~" encodes 10 red pixels.
    t.advance(b"\x1bP0;1;0q\"1;1;10;6#0;2;100;0;0!10~\x1b\\");

    let notifs = t.pending_image_notifications();
    assert!(!notifs.is_empty(), "sixel must produce a notification");

    let image_id = notifs[0].image_id;
    let png_b64 = t.get_image_png_base64(image_id);
    assert!(
        !png_b64.is_empty(),
        "sixel image_id {image_id} must be stored and retrievable as PNG base64"
    );

    let decoded = BASE64_STANDARD
        .decode(&png_b64)
        .expect("sixel PNG base64 must decode without error");
    assert!(
        decoded.starts_with(b"\x89PNG"),
        "decoded sixel image must be valid PNG"
    );
}

/// Sixel cursor advancement: after a sixel the cursor row must advance past the
/// image height and cursor col must be reset to 0.
#[test]
fn sixel_cursor_advances_past_image_height() {
    let mut t = common::new_terminal();

    assert_eq!(t.cursor_row(), 0, "cursor must start at row 0");
    assert_eq!(t.cursor_col(), 0, "cursor must start at col 0");

    // Sixel with declared height = 6 pixels → cell_h = ceil(6/16) = 1 row.
    t.advance(b"\x1bP0;1;0q\"1;1;1;6#0~\x1b\\");

    assert!(
        t.cursor_row() >= 1,
        "cursor row must advance past the sixel region (≥1), got {}",
        t.cursor_row()
    );
    assert_eq!(
        t.cursor_col(),
        0,
        "cursor col must reset to 0 after sixel, got {}",
        t.cursor_col()
    );
}

/// Two consecutive sixel sequences must produce two distinct placement
/// notifications, each with a unique image ID.
#[test]
fn sixel_two_consecutive_each_produce_distinct_notification() {
    let mut t = common::new_terminal();

    t.advance(b"\x1bP0;1;0q\"1;1;1;6#0~\x1b\\");
    t.advance(b"\x1bP0;1;0q\"1;1;1;6#0~\x1b\\");

    let notifs = t.pending_image_notifications();
    assert_eq!(
        notifs.len(),
        2,
        "two sixel sequences must produce two notifications"
    );

    // Image IDs must be distinct (each sixel gets its own store slot).
    let ids: Vec<u32> = notifs.iter().map(|n| n.image_id).collect();
    assert_ne!(
        ids[0], ids[1],
        "consecutive sixels must use distinct image IDs, got ids: {ids:?}"
    );
}

/// Concurrent Kitty Graphics and Sixel: both protocols can be used in the
/// same terminal session without interfering with each other's image store.
#[test]
fn kitty_and_sixel_coexist_in_same_session() {
    let mut t = common::new_terminal();

    // Send a Kitty transmit (stores image 20 via APC).
    t.advance(b"\x1b_Ga=t,f=24,i=20,s=1,v=1;AAAA\x1b\\");
    let kitty_png = t.get_image_png_base64(20);
    assert!(
        !kitty_png.is_empty(),
        "Kitty image 20 must be stored before sixel"
    );
    assert_eq!(
        t.pending_image_notifications().len(),
        0,
        "bare transmit must not queue a notification"
    );

    // Send a Sixel sequence (stores image via DCS, queues notification).
    t.advance(b"\x1bP0;1;0q\"1;1;1;6#0~\x1b\\");

    let notifs = t.pending_image_notifications();
    assert_eq!(
        notifs.len(),
        1,
        "sixel must add exactly one notification after the Kitty transmit"
    );
    let sixel_id = notifs[0].image_id;

    // Kitty image and sixel image must be distinct IDs.
    assert_ne!(
        sixel_id, 20,
        "sixel image ID must not collide with Kitty image ID 20"
    );

    // Both images must be independently retrievable.
    let sixel_png = t.get_image_png_base64(sixel_id);
    assert!(
        !sixel_png.is_empty(),
        "sixel image must still be retrievable after Kitty transmit"
    );
    let kitty_png_after = t.get_image_png_base64(20);
    assert!(
        !kitty_png_after.is_empty(),
        "Kitty image must still be retrievable after sixel was sent"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// DCS DECRQSS (DCS $ q <setting> ST) — Request Status String
// ─────────────────────────────────────────────────────────────────────────────

/// DECRQSS cursor style (DCS $ q SP q ST): a fresh terminal has the default
/// BlinkingBlock cursor → DECSCUSR Ps 0, answered as DCS 1 $ r 0 SP q ST.
#[test]
fn decrqss_cursor_style_default_reports_blinking_block() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1bP$q q\x1b\\"); // DCS $ q <space> q ST
    assert_eq!(
        t.pending_responses().to_vec(),
        vec![b"\x1bP1$r0 q\x1b\\".to_vec()]
    );
}

/// DECRQSS cursor style reflects a prior DECSCUSR (CSI 2 SP q = steady block).
/// This is the query neovim issues to restore the cursor shape on exit.
#[test]
fn decrqss_cursor_style_reflects_decscusr() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[2 q"); // DECSCUSR 2 = steady block
    t.advance(b"\x1bP$q q\x1b\\"); // DECRQSS query
    assert_eq!(
        t.pending_responses().to_vec(),
        vec![b"\x1bP1$r2 q\x1b\\".to_vec()]
    );
}

/// DECRQSS scroll region (DCS $ q r ST): a fresh 24-row terminal has the
/// full-screen region, reported 1-indexed inclusive as "1;24".
#[test]
fn decrqss_scroll_region_default_full_screen() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1bP$qr\x1b\\"); // DCS $ q r ST
    assert_eq!(
        t.pending_responses().to_vec(),
        vec![b"\x1bP1$r1;24r\x1b\\".to_vec()]
    );
}

/// DECRQSS scroll region reflects a prior DECSTBM (CSI 5;10 r → margins 5;10).
#[test]
fn decrqss_scroll_region_reflects_decstbm() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[5;10r"); // DECSTBM rows 5..10 (1-indexed inclusive)
    t.advance(b"\x1bP$qr\x1b\\");
    assert_eq!(
        t.pending_responses().to_vec(),
        vec![b"\x1bP1$r5;10r\x1b\\".to_vec()]
    );
}

/// DECRQSS for SGR (DCS $ q m ST) on a fresh terminal reports the reset
/// rendition: DCS 1 $ r 0 m ST.
#[test]
fn decrqss_sgr_default_reports_reset() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1bP$qm\x1b\\"); // DCS $ q m ST
    assert_eq!(
        t.pending_responses().to_vec(),
        vec![b"\x1bP1$r0m\x1b\\".to_vec()]
    );
}

/// DECRQSS SGR serializes active flags after the leading reset.
#[test]
fn decrqss_sgr_reports_active_flags() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[1;3;4;7;9m"); // bold italic underline inverse strikethrough
    t.advance(b"\x1bP$qm\x1b\\");
    assert_eq!(
        t.pending_responses().to_vec(),
        vec![b"\x1bP1$r0;1;3;4;7;9m\x1b\\".to_vec()]
    );
}

/// DECRQSS SGR serializes a named foreground and an indexed background.
#[test]
fn decrqss_sgr_reports_named_and_indexed_colors() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[31;48;5;236m"); // fg red (named), bg indexed 236
    t.advance(b"\x1bP$qm\x1b\\");
    assert_eq!(
        t.pending_responses().to_vec(),
        vec![b"\x1bP1$r0;31;48;5;236m\x1b\\".to_vec()]
    );
}

/// DECRQSS SGR serializes RGB fg/bg, a curly underline, and an underline color.
#[test]
fn decrqss_sgr_reports_truecolor_and_underline() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[38;2;10;20;30;48;2;1;2;3;4:3;58;2;9;8;7m");
    t.advance(b"\x1bP$qm\x1b\\");
    assert_eq!(
        t.pending_responses().to_vec(),
        vec![b"\x1bP1$r0;4:3;38;2;10;20;30;48;2;1;2;3;58;2;9;8;7m\x1b\\".to_vec()]
    );
}

/// DECRQSS for an unsupported setting (DCS $ q " p ST = DECSCL) → invalid.
#[test]
fn decrqss_unknown_setting_reports_invalid() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1bP$q\"p\x1b\\");
    assert_eq!(
        t.pending_responses().to_vec(),
        vec![b"\x1bP0$r\x1b\\".to_vec()]
    );
}
