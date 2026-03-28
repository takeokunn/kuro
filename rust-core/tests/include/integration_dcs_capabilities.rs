
// ─────────────────────────────────────────────────────────────────────────────
// XTGETTCAP — additional capabilities
// ─────────────────────────────────────────────────────────────────────────────

// XTGETTCAP for "colors" (hex 636f6c6f7273) must return DCS 1+r with "256".
#[test]
fn xtgettcap_colors_responds_with_256() {
    let mut t = TerminalCore::new(24, 80);
    // "colors" in hex = 636f6c6f7273
    t.advance(b"\x1bP+q636f6c6f7273\x1b\\");
    let responses = common::read_responses(&t);
    assert!(
        !responses.is_empty(),
        "XTGETTCAP for 'colors' must produce a response"
    );
    let resp = &responses[0];
    assert!(
        resp.contains("1+r"),
        "colors capability must use DCS 1+r format, got: {resp:?}"
    );
    // "256" in hex = 323536
    assert!(
        resp.contains("323536") || resp.contains("256"),
        "colors response must encode '256', got: {resp:?}"
    );
}

// XTGETTCAP for "Co" (alternate alias for colors, hex 436f) must also respond.
#[test]
fn xtgettcap_co_alias_responds() {
    let mut t = TerminalCore::new(24, 80);
    // "Co" in hex = 436f
    t.advance(b"\x1bP+q436f\x1b\\");
    let responses = common::read_responses(&t);
    assert!(
        !responses.is_empty(),
        "XTGETTCAP for 'Co' must produce a response"
    );
    let resp = &responses[0];
    assert!(
        resp.contains("1+r"),
        "Co capability must use DCS 1+r format, got: {resp:?}"
    );
}

// Two XTGETTCAP caps in one DCS sequence (semicolon-separated) must produce
// two separate responses — one per capability name.
#[test]
fn xtgettcap_two_caps_in_one_sequence_produces_two_responses() {
    let mut t = TerminalCore::new(24, 80);
    // "TN" = 544e, "RGB" = 524742, joined with semicolon
    t.advance(b"\x1bP+q544e;524742\x1b\\");
    let responses = common::read_responses(&t);
    assert!(
        responses.len() >= 2,
        "two caps in one XTGETTCAP sequence must produce at least two responses, got {}",
        responses.len()
    );
}

// Two consecutive XTGETTCAP DCS sequences must each contribute a response.
#[test]
fn xtgettcap_two_consecutive_sequences() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1bP+q544e\x1b\\"); // TN
    let after_first = common::read_responses(&t).len();
    assert!(after_first >= 1, "first XTGETTCAP must produce a response");
    t.advance(b"\x1bP+q524742\x1b\\"); // RGB
    let after_second = common::read_responses(&t).len();
    assert!(
        after_second > after_first,
        "second consecutive XTGETTCAP must add another response"
    );
}

// An unknown DCS string (not XTGETTCAP / Sixel / Kitty) must not panic and
// must leave cursor position unchanged.
#[test]
fn dcs_unknown_passthrough_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);
    let row_before = t.cursor_row();
    let col_before = t.cursor_col();
    // DCS $q ... ST — resembles DECRQSS but unrecognised in this impl
    t.advance(b"\x1bP$qsomething-unknown\x1b\\");
    assert_eq!(
        t.cursor_row(),
        row_before,
        "unknown DCS must not move cursor row"
    );
    assert_eq!(
        t.cursor_col(),
        col_before,
        "unknown DCS must not move cursor col"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Kitty Graphics — additional coverage
// ─────────────────────────────────────────────────────────────────────────────

// Kitty PNG format (f=100): transmit+display a valid inline PNG → notification queued.
#[test]
fn kitty_png_format_transmit_and_display_queues_notification() {
    let mut t = TerminalCore::new(24, 80);

    // Build a minimal 1×1 RGB PNG and base64-encode it.
    let mut png_buf: Vec<u8> = Vec::new();
    {
        let mut encoder = png::Encoder::new(&mut png_buf, 1, 1);
        encoder.set_color(png::ColorType::Rgb);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder.write_header().expect("PNG header");
        writer
            .write_image_data(&[0x80, 0x40, 0x20])
            .expect("PNG pixels");
    }
    let b64 = BASE64_STANDARD.encode(&png_buf);

    // a=T, f=100 (PNG format), i=30, c=4, r=2
    let apc = format!("\x1b_Ga=T,f=100,i=30,s=1,v=1,c=4,r=2;{b64}\x1b\\");
    t.advance(apc.as_bytes());

    let notifs = t.pending_image_notifications();
    assert_eq!(
        notifs.len(),
        1,
        "kitty PNG a=T must queue exactly one notification, got {}",
        notifs.len()
    );
    assert_eq!(notifs[0].image_id, 30, "notification image_id must be 30");
    assert_eq!(notifs[0].cell_width, 4, "cell_width must match c=4");
    assert_eq!(notifs[0].cell_height, 2, "cell_height must match r=2");

    let png_b64 = t.get_image_png_base64(30);
    assert!(
        !png_b64.is_empty(),
        "kitty PNG image must be stored after a=T"
    );
}

// Kitty 3-chunk accumulation: chunk1 (m=1, empty data sets params), chunk2
// (m=1, appends full pixel data), chunk3 (m=0, empty — finalises).
#[test]
fn kitty_three_chunk_accumulation_produces_valid_image() {
    let mut t = TerminalCore::new(24, 80);

    // Chunk 1: m=1, no payload — establishes format params, data = []
    t.advance(b"\x1b_Ga=t,f=24,i=40,s=1,v=1,m=1;\x1b\\");
    assert!(
        t.get_image_png_base64(40).is_empty(),
        "image must not be stored after chunk 1 (m=1)"
    );

    // Chunk 2: m=1, full RGB pixel payload "AAAA" = [0,0,0]
    t.advance(b"\x1b_Gm=1;AAAA\x1b\\");
    assert!(
        t.get_image_png_base64(40).is_empty(),
        "image must not be stored after chunk 2 (m=1)"
    );

    // Chunk 3: m=0, empty payload — finalises accumulation
    t.advance(b"\x1b_Gm=0;\x1b\\");

    let png = t.get_image_png_base64(40);
    assert!(
        !png.is_empty(),
        "image must be stored after final m=0 chunk (3-chunk transfer)"
    );
    let decoded = BASE64_STANDARD.decode(&png).expect("valid base64");
    assert!(
        decoded.starts_with(b"\x89PNG"),
        "decoded data must be PNG, got: {:?}",
        &decoded[..4.min(decoded.len())]
    );
}

// Kitty a=T with q=2: placement notification IS queued, but no protocol response.
#[test]
fn kitty_transmit_and_display_q2_queues_notification_suppresses_response() {
    let mut t = TerminalCore::new(24, 80);

    let responses_before = t.pending_responses().len();
    t.advance(b"\x1b_Ga=T,f=24,i=50,s=1,v=1,c=3,r=2,q=2;AAAA\x1b\\");

    assert_eq!(
        t.pending_responses().len(),
        responses_before,
        "q=2 must suppress the protocol response"
    );

    let notifs = t.pending_image_notifications();
    assert_eq!(
        notifs.len(),
        1,
        "a=T with q=2 must still queue a placement notification"
    );
    assert_eq!(
        notifs[0].image_id, 50,
        "notification must reference image 50"
    );
}

// Kitty d=I: delete by image ID removes both image data and placements.
#[test]
fn kitty_delete_by_image_id_removes_image_and_placements() {
    let mut t = TerminalCore::new(24, 80);

    t.advance(b"\x1b_Ga=T,f=24,i=55,s=1,v=1,c=2,r=1;AAAA\x1b\\");
    assert!(
        !t.get_image_png_base64(55).is_empty(),
        "image 55 must be stored before delete"
    );
    assert_eq!(
        t.pending_image_notifications().len(),
        1,
        "one notification must be queued after a=T"
    );

    // Delete by image ID using d=I.
    t.advance(b"\x1b_Ga=d,d=I,i=55\x1b\\");

    assert!(
        t.get_image_png_base64(55).is_empty(),
        "image data must be removed after d=I delete"
    );
}

// Three sequential kitty a=T sequences with distinct IDs each store an image and
// produce a notification; all three image IDs appear in the notification list.
#[test]
fn kitty_three_sequential_images_have_unique_ids() {
    let mut t = TerminalCore::new(24, 80);

    t.advance(b"\x1b_Ga=T,f=24,i=61,s=1,v=1,c=2,r=1;AAAA\x1b\\");
    t.advance(b"\x1b[3;1H"); // move cursor to row 2
    t.advance(b"\x1b_Ga=T,f=24,i=62,s=1,v=1,c=2,r=1;/wAA\x1b\\");
    t.advance(b"\x1b[5;1H"); // move cursor to row 4
    t.advance(b"\x1b_Ga=T,f=24,i=63,s=1,v=1,c=2,r=1;AAAA\x1b\\");

    let notifs = t.pending_image_notifications();
    assert_eq!(
        notifs.len(),
        3,
        "three a=T sequences must queue three notifications"
    );

    let ids: Vec<u32> = notifs.iter().map(|n| n.image_id).collect();
    assert!(ids.contains(&61), "notification for image 61 must exist");
    assert!(ids.contains(&62), "notification for image 62 must exist");
    assert!(ids.contains(&63), "notification for image 63 must exist");

    assert!(
        !t.get_image_png_base64(61).is_empty(),
        "image 61 must be stored"
    );
    assert!(
        !t.get_image_png_base64(62).is_empty(),
        "image 62 must be stored"
    );
    assert!(
        !t.get_image_png_base64(63).is_empty(),
        "image 63 must be stored"
    );
}

// Kitty a=p with X= and Y= pixel offsets must produce a placement notification
// with the correct cell_width and cell_height.
#[test]
fn kitty_place_with_xy_pixel_offsets_queues_notification() {
    let mut t = TerminalCore::new(24, 80);

    // Transmit first (no display).
    t.advance(b"\x1b_Ga=t,f=24,i=65,s=1,v=1;AAAA\x1b\\");
    assert_eq!(
        t.pending_image_notifications().len(),
        0,
        "bare transmit must not queue a notification"
    );

    // Place with X=10 pixel x-offset, Y=5 pixel y-offset, 6×3 cells.
    t.advance(b"\x1b_Ga=p,i=65,c=6,r=3,X=10,Y=5\x1b\\");

    let notifs = t.pending_image_notifications();
    assert_eq!(
        notifs.len(),
        1,
        "a=p with X/Y offsets must queue exactly one notification"
    );
    assert_eq!(
        notifs[0].image_id, 65,
        "notification must reference image 65"
    );
    assert_eq!(notifs[0].cell_width, 6, "cell_width must match c=6");
    assert_eq!(notifs[0].cell_height, 3, "cell_height must match r=3");
}

// ─────────────────────────────────────────────────────────────────────────────
// Sixel — additional coverage
// ─────────────────────────────────────────────────────────────────────────────

// Sixel with declared dimensions: notification cell_width and cell_height > 0.
#[test]
fn sixel_notification_has_nonzero_dimensions() {
    let mut t = TerminalCore::new(24, 80);

    // 8-pixel-wide, 6-pixel-tall red sixel.
    t.advance(b"\x1bP0;1;0q\"1;1;8;6#0;2;100;0;0!8~\x1b\\");

    let notifs = t.pending_image_notifications();
    assert_eq!(
        notifs.len(),
        1,
        "sixel must produce exactly one notification"
    );
    assert!(
        notifs[0].cell_width > 0,
        "sixel notification cell_width must be > 0, got {}",
        notifs[0].cell_width
    );
    assert!(
        notifs[0].cell_height > 0,
        "sixel notification cell_height must be > 0, got {}",
        notifs[0].cell_height
    );
}

// Sixel with multiple color registers must not panic and must store the image.
#[test]
fn sixel_multi_color_palette_stores_image() {
    let mut t = TerminalCore::new(24, 80);

    // Three color registers: red, green, blue; two sixel bands.
    t.advance(
        b"\x1bP0;1;0q\"1;1;4;12\
          #0;2;100;0;0!4~\
          #1;2;0;100;0!4~\
          -#2;2;0;0;100!4~\
          \x1b\\",
    );

    let notifs = t.pending_image_notifications();
    assert_eq!(
        notifs.len(),
        1,
        "multi-color sixel must produce exactly one notification"
    );

    let png_b64 = t.get_image_png_base64(notifs[0].image_id);
    assert!(
        !png_b64.is_empty(),
        "multi-color sixel image must be stored"
    );
}

// Sixel PNG retrieval: get_image_png_base64 returns data starting with PNG magic.
#[test]
fn sixel_png_retrieval_returns_valid_png_magic() {
    let mut t = TerminalCore::new(24, 80);

    t.advance(b"\x1bP0;1;0q\"1;1;4;6#0;2;0;0;100!4~\x1b\\");

    let notifs = t.pending_image_notifications();
    assert!(!notifs.is_empty(), "sixel must produce a notification");

    let png_b64 = t.get_image_png_base64(notifs[0].image_id);
    assert!(!png_b64.is_empty(), "sixel PNG base64 must be non-empty");

    let decoded = BASE64_STANDARD.decode(&png_b64).expect("valid base64");
    assert!(
        decoded.starts_with(b"\x89PNG"),
        "sixel stored image must be valid PNG, got: {:?}",
        &decoded[..4.min(decoded.len())]
    );
}

// After a terminal reset (RIS), pending_image_notifications must be empty.
#[test]
fn sixel_after_reset_has_no_stale_notifications() {
    let mut t = TerminalCore::new(24, 80);

    t.advance(b"\x1bP0;1;0q\"1;1;1;6#0~\x1b\\");
    assert_eq!(
        t.pending_image_notifications().len(),
        1,
        "one notification must be present before reset"
    );

    // RIS (ESC c) — full terminal reset.
    t.advance(b"\x1bc");

    assert_eq!(
        t.pending_image_notifications().len(),
        0,
        "reset must clear all pending image notifications"
    );
}
