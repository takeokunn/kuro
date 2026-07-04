use super::*;

/// A Sixel DCS sequence with valid pixel data must produce exactly one image
/// placement notification.
///
/// The sixel data "#0~" uses color register 0 (black by default) and encodes
/// a 1×6 pixel column. Raster attributes "\"1;1;1;6" declare 1×6 pixel size.
#[test]
fn test_sixel_produces_image_placement() {
    let mut core = crate::TerminalCore::new(24, 80);

    run_dcs(&mut core, b"", 'q', b"\"1;1;1;6#0~");

    assert_single_sixel_notification(&core, 0, 0);
}

/// Two consecutive Sixel DCS sequences must each produce a separate image
/// notification, giving two notifications total.
#[test]
fn test_two_consecutive_sixels_produce_two_placements() {
    let mut core = crate::TerminalCore::new(24, 80);

    run_dcs(&mut core, b"", 'q', b"\"1;1;1;6#0~");
    run_dcs(&mut core, b"", 'q', b"\"1;1;1;6#0~");

    assert_sixel_notification_count(&core, 2);
}

/// After a Sixel DCS sequence, the cursor must have advanced past the rendered
/// image region (row should be greater than the initial row).
#[test]
fn test_sixel_advances_cursor_after_render() {
    let mut core = crate::TerminalCore::new(24, 80);

    assert_eq!(core.screen.cursor().row, 0);

    run_dcs(&mut core, b"", 'q', b"\"1;1;1;6#0~");

    let cursor = core.screen.cursor();
    assert!(
        cursor.row >= 1,
        "cursor row must advance past the rendered sixel region, got row {}",
        cursor.row
    );
    assert_eq!(
        cursor.col, 0,
        "sixel rendering must reset cursor column to 0"
    );
}

/// A Sixel DCS sequence with empty data (no pixel commands) must not add any
/// image notification (`decoder.finish()` returns None for an empty sequence).
#[test]
fn test_sixel_empty_data_no_placement() {
    let mut core = crate::TerminalCore::new(24, 80);

    // Hook a sixel DCS but provide no pixel data at all.
    run_dcs(&mut core, b"", 'q', b"");

    assert_no_sixel_notifications(&core);
}
