use super::tests_support::*;
use crate::grid::screen::{GraphicsStore, ImageData, ImagePlacement};
use crate::parser::kitty::ImageFormat;

#[test]
fn new_returns_empty_store() {
    let store = GraphicsStore::new();
    assert_image_missing(&store, 1);
}

#[test]
fn default_is_equivalent_to_new() {
    let by_new = GraphicsStore::new();
    let by_default = GraphicsStore::default();

    assert_eq!(
        by_new.get_image_png_base64(1),
        by_default.get_image_png_base64(1)
    );
}

#[test]
fn store_image_explicit_id_returns_that_id() {
    let mut store = GraphicsStore::new();

    let id = store.store_image(Some(42), tiny_rgb(0xFF));

    assert_eq!(id, 42);
}

#[test]
fn store_image_explicit_id_is_retrievable() {
    let mut store = GraphicsStore::new();

    store.store_image(Some(7), tiny_rgb(0xAA));

    assert_image_present(&store, 7);
}

#[test]
fn store_image_auto_id_starts_at_one() {
    let mut store = GraphicsStore::new();

    let id = store.store_image(None, tiny_rgb(0x10));

    assert_eq!(id, 1);
}

#[test]
fn store_image_auto_id_increments_on_each_call() {
    let mut store = GraphicsStore::new();

    let id1 = store.store_image(None, tiny_rgb(0x10));
    let id2 = store.store_image(None, tiny_rgb(0x20));
    let id3 = store.store_image(None, tiny_rgb(0x30));

    assert!(id1 < id2);
    assert!(id2 < id3);
}

#[test]
fn store_image_auto_id_five_consecutive_are_unique() {
    let mut store = GraphicsStore::new();
    let mut ids = Vec::new();

    for byte in 0u8..5 {
        ids.push(store.store_image(None, tiny_rgb(byte)));
    }

    let mut sorted = ids.clone();
    sorted.sort_unstable();
    sorted.dedup();
    assert_eq!(sorted.len(), 5);
}

#[test]
fn store_image_overwrite_same_id_replaces_data() {
    let mut store = GraphicsStore::new();

    store.store_image(Some(5), tiny_rgb(0x00));
    store.store_image(Some(5), tiny_rgba(0xFF));

    assert_image_present(&store, 5);
    assert_eq!(store.current_bytes, 4);
}

#[test]
fn get_image_png_base64_returns_empty_for_unknown_id() {
    let store = GraphicsStore::new();

    assert_image_missing(&store, 999);
}

#[test]
fn get_image_png_base64_returns_valid_base64_for_known_id() {
    let store = store_with_image(3);
    let result = store.get_image_png_base64(3);

    assert!(result
        .chars()
        .all(|c| c.is_alphanumeric() || c == '+' || c == '/' || c == '='));
}

#[test]
fn add_placement_returns_none_for_unknown_image() {
    let mut store = GraphicsStore::new();

    assert!(store.add_placement(placement(99, 0, 0)).is_none());
}

#[test]
fn add_placement_returns_notification_with_correct_fields() {
    let mut store = store_with_image(10);
    let placement = ImagePlacement {
        image_id: 10,
        placement_id: None,
        row: 3,
        col: 7,
        display_cols: 12,
        display_rows: 4,
        ..ImagePlacement::default()
    };

    let notif = store.add_placement(placement).expect("must return Some");

    assert_eq!(notif.image_id, 10);
    assert_eq!(notif.row, 3);
    assert_eq!(notif.col, 7);
    assert_eq!(notif.cell_width, 12);
    assert_eq!(notif.cell_height, 4);
}

#[test]
fn add_placement_multiple_placements_for_same_image() {
    let mut store = store_with_image(1);

    assert!(store.add_placement(placement(1, 0, 0)).is_some());
    assert!(store.add_placement(placement(1, 5, 2)).is_some());
    assert_eq!(store.placements.len(), 2);
}

#[test]
fn clear_all_placements_empties_the_placement_list() {
    let mut store = store_with_images(&[1, 2]);

    store.add_placement(placement(1, 0, 0));
    store.add_placement(placement(2, 1, 0));
    store.clear_all_placements();

    assert!(store.placements.is_empty());
    assert_image_present(&store, 1);
    assert_image_present(&store, 2);
}

#[test]
fn scroll_up_shifts_placement_rows_up_by_n() {
    let mut store = store_with_image(1);

    store.add_placement(placement(1, 5, 0));
    store.scroll_up(3);

    assert_placement_rows(&store, &[2]);
}

#[test]
fn scroll_up_discards_placements_that_scroll_off_the_top() {
    let mut store = store_with_image(1);

    store.add_placement(placement(1, 1, 0));
    store.scroll_up(2);

    assert!(store.placements.is_empty());
}

#[test]
fn scroll_down_shifts_placement_rows_down_by_n() {
    let mut store = store_with_image(1);

    store.add_placement(placement(1, 2, 0));
    store.scroll_down(3, 24);

    assert_placement_rows(&store, &[5]);
}

#[test]
fn delete_by_id_removes_image_from_store() {
    let mut store = store_with_image(20);

    store.delete_by_id(20);

    assert_image_missing(&store, 20);
}

#[test]
fn delete_by_id_leaves_other_images_intact() {
    let mut store = store_with_images(&[10, 20, 30]);

    store.delete_by_id(20);

    assert_image_present(&store, 10);
    assert_image_missing(&store, 20);
    assert_image_present(&store, 30);
}

#[test]
fn delete_by_id_on_unknown_id_does_not_panic() {
    let mut store = GraphicsStore::new();

    store.delete_by_id(9999);
    store.store_image(Some(1), tiny_rgb(0x01));

    assert_image_present(&store, 1);
}

#[test]
fn delete_by_id_removes_associated_placements() {
    let mut store = store_with_image(5);

    store.add_placement(placement(5, 1, 0));
    store.delete_by_id(5);

    assert!(store.placements.is_empty());
    assert!(store.add_placement(placement(5, 2, 0)).is_none());
}

#[test]
fn clear_placements_then_delete_by_id_prevents_placement() {
    let mut store = store_with_image(3);

    store.add_placement(placement(3, 1, 0));
    store.clear_all_placements();
    store.delete_by_id(3);

    assert!(store.add_placement(placement(3, 0, 0)).is_none());
}

#[test]
fn image_data_byte_count_matches_pixel_vec_len() {
    let rgb = ImageData::new(vec![1, 2, 3, 4, 5, 6], ImageFormat::Rgb, 2, 1);
    let rgba = ImageData::new(vec![1, 2, 3, 4], ImageFormat::Rgba, 1, 1);

    assert_eq!(rgb.byte_count(), 6);
    assert_eq!(rgba.byte_count(), 4);
}

#[test]
fn image_data_byte_count_empty_pixels_is_zero() {
    assert_eq!(empty_rgb().byte_count(), 0);
}

assert_to_png_base64_non_empty!(
    to_png_base64_produces_non_empty_string_for_valid_image,
    tiny_rgb(0x80)
);

assert_to_png_base64_non_empty!(
    to_png_base64_rgba_produces_non_empty_string,
    tiny_rgba(0x40)
);

assert_image_survives!(
    scroll_up_zero_is_noop,
    |store| {
        store.add_placement(placement(1, 5, 0));
    },
    |store| {
        store.scroll_up(0);
        assert_placement_rows(store, &[5]);
    }
);

assert_image_survives!(
    scroll_up_keeps_placement_at_row_boundary,
    |store| {
        store.add_placement(placement(1, 5, 0));
    },
    |store| {
        store.scroll_up(5);
        assert_placement_rows(store, &[0]);
    }
);

assert_image_survives!(
    scroll_down_with_zero_max_row_clamps_to_zero,
    |store| {
        store.add_placement(placement(1, 0, 0));
    },
    |store| {
        store.scroll_down(5, 0);
        assert_placement_rows(store, &[0]);
    }
);

assert_image_survives!(
    scroll_down_clamps_placement_to_max_row_minus_one,
    |store| {
        store.add_placement(placement(1, 20, 0));
    },
    |store| {
        store.scroll_down(100, 24);
        assert_placement_rows(store, &[23]);
    }
);

#[test]
fn delete_by_placement_removes_matching_placement() {
    let mut store = store_with_image(1);

    store.add_placement(placement_with_id(1, 42, 0, 0));
    store.delete_by_placement(1, 42);

    assert!(store.placements.is_empty());
    assert_image_present(&store, 1);
}

#[test]
fn delete_by_placement_leaves_other_placement_ids_intact() {
    let mut store = store_with_image(1);

    store.add_placement(placement_with_id(1, 10, 0, 0));
    store.add_placement(placement_with_id(1, 20, 5, 0));
    store.delete_by_placement(1, 10);

    assert_eq!(store.placements.len(), 1);
    assert_eq!(store.placements[0].placement_id, Some(20));
    assert_image_present(&store, 1);
}

#[test]
fn delete_by_placement_noop_on_wrong_image_id() {
    let mut store = store_with_image(1);

    store.add_placement(placement_with_id(1, 5, 0, 0));
    store.delete_by_placement(99, 5);

    assert_eq!(store.placements.len(), 1);
    assert_image_present(&store, 1);
}

#[test]
fn delete_by_row_removes_placements_at_that_row() {
    let mut store = store_with_image(1);

    store.add_placement(placement(1, 3, 0));
    store.add_placement(placement(1, 7, 0));
    store.delete_by_row(3);

    assert_placement_rows(&store, &[7]);
    assert_image_present(&store, 1);
}

#[test]
fn delete_by_row_leaves_other_rows_intact() {
    let mut store = store_with_image(1);

    store.add_placement(placement(1, 2, 0));
    store.add_placement(placement(1, 5, 0));
    store.delete_by_row(2);

    assert_placement_rows(&store, &[5]);
}

#[test]
fn delete_by_row_noop_when_no_placement_at_row() {
    let mut store = store_with_image(1);

    store.add_placement(placement(1, 4, 0));
    store.delete_by_row(0);

    assert_placement_rows(&store, &[4]);
}

#[test]
fn delete_by_col_removes_placements_at_that_col() {
    let mut store = store_with_image(1);

    store.add_placement(placement(1, 0, 10));
    store.add_placement(placement(1, 0, 20));
    store.delete_by_col(10);

    assert_eq!(store.placements.len(), 1);
    assert_eq!(store.placements[0].col, 20);
}

#[test]
fn delete_by_col_leaves_other_cols_intact() {
    let mut store = store_with_image(1);

    store.add_placement(placement(1, 0, 5));
    store.add_placement(placement(1, 0, 15));
    store.delete_by_col(5);

    assert_eq!(store.placements.len(), 1);
    assert_eq!(store.placements[0].col, 15);
}

// ── Animation frame composition (a=f) ───────────────────────────────────────────

/// Build a 2x2 RGBA image (all transparent black) for compose tests.
fn store_with_2x2(id: u32) -> GraphicsStore {
    let mut store = GraphicsStore::new();
    store.store_image(Some(id), ImageData::new(vec![0u8; 2 * 2 * 4], ImageFormat::Rgba, 2, 2));
    store
}

#[test]
fn add_frame_materializes_base_as_frame_one() {
    let mut store = store_with_2x2(1);
    assert_eq!(store.frame_count(1), 0, "still image has no frames yet");
    // Add a 2x2 opaque-red full-canvas frame.
    let red: Vec<u8> = std::iter::repeat([0xFF, 0, 0, 0xFF]).take(4).flatten().collect();
    let n = store.add_frame(1, &red, ImageFormat::Rgba, 0, 0, 0, 0, None, None, 0, true, 50);
    assert_eq!(n, Some(2), "base becomes frame 1, new frame is frame 2");
    assert_eq!(store.frame_count(1), 2, "frame 1 (base) + frame 2");
    assert_eq!(store.frame_gap_ms(1, 1), 50, "frame 2 gap recorded");
}

#[test]
fn add_frame_replace_overwrites_region() {
    let mut store = store_with_2x2(1);
    // Replace just the top-left pixel with opaque green using X=replace.
    let green = [0u8, 0xFF, 0, 0xFF];
    store.add_frame(1, &green, ImageFormat::Rgba, 0, 0, 1, 1, None, None, 0, true, 0);
    let png = store.frame_png_base64(1, 1);
    assert!(!png.is_empty(), "composed frame must render to PNG");
}

#[test]
fn add_frame_edit_target_composes_in_place() {
    let mut store = store_with_2x2(1);
    // Frame 2 created.
    let red: Vec<u8> = std::iter::repeat([0xFF, 0, 0, 0xFF]).take(4).flatten().collect();
    store.add_frame(1, &red, ImageFormat::Rgba, 0, 0, 0, 0, None, None, 0, true, 0);
    assert_eq!(store.frame_count(1), 2);
    // Edit frame 2 in place (r=2) — no new frame added.
    let blue = [0u8, 0, 0xFF, 0xFF];
    let n = store.add_frame(1, &blue, ImageFormat::Rgba, 0, 0, 1, 1, None, Some(2), 0, true, 0);
    assert_eq!(n, Some(2), "r=2 edits frame 2 in place");
    assert_eq!(store.frame_count(1), 2, "edit must not add a frame");
}

#[test]
fn add_frame_base_canvas_copies_existing_frame() {
    let mut store = store_with_2x2(1);
    let red: Vec<u8> = std::iter::repeat([0xFF, 0, 0, 0xFF]).take(4).flatten().collect();
    store.add_frame(1, &red, ImageFormat::Rgba, 0, 0, 0, 0, None, None, 0, true, 0); // frame 2
    // New frame uses c=2 as canvas, overlay one green pixel.
    let green = [0u8, 0xFF, 0, 0xFF];
    let n = store.add_frame(1, &green, ImageFormat::Rgba, 1, 1, 1, 1, Some(2), None, 0, true, 0);
    assert_eq!(n, Some(3), "c=2 canvas → frame 3 appended");
    assert_eq!(store.frame_count(1), 3);
}

#[test]
fn add_frame_unknown_image_returns_none() {
    let mut store = GraphicsStore::new();
    let n = store.add_frame(99, &[0u8; 4], ImageFormat::Rgba, 0, 0, 1, 1, None, None, 0, true, 0);
    assert_eq!(n, None, "a=f on unknown image is a no-op");
}

/// INTENT (security/DoS regression): an a=f frame whose region dimensions
/// (s=,v=) would force a multi-gigabyte RGBA allocation is refused outright,
/// returning None and adding NO frame — even though the payload is tiny. The
/// region pixel count (65535*65535 ≈ 4.3e9) far exceeds the byte cap; a missing
/// guard here would attempt a ~17 GB allocation and OOM the host Emacs.
#[test]
fn add_frame_huge_region_dimensions_rejected_without_allocation() {
    let mut store = store_with_2x2(1);
    let n = store.add_frame(
        1,
        &[0u8; 4], // tiny payload — the danger is the declared region size
        ImageFormat::Rgba,
        0,
        0,
        65535, // s= region width
        65535, // v= region height
        None,
        None,
        0,
        true,
        0,
    );
    assert_eq!(n, None, "oversized a=f region must be refused, not allocated");
    assert_eq!(store.frame_count(1), 0, "no frame may be created on rejection");
}

/// INTENT (security/DoS regression): an a=f frame onto an image whose *declared*
/// dimensions are enormous (the canvas the frame composes onto) is refused. The
/// stored base image holds only a few payload bytes but claims a 50000x50000
/// canvas; materializing frame 1 would allocate ~10 GB. The guard rejects it.
#[test]
fn add_frame_huge_canvas_dimensions_rejected_without_allocation() {
    let mut store = GraphicsStore::new();
    // Declared 50000x50000 but only 4 bytes of pixel data backing it.
    store.store_image(
        Some(7),
        ImageData::new(vec![0u8; 4], ImageFormat::Rgba, 50000, 50000),
    );
    let red = [0xFFu8, 0, 0, 0xFF];
    let n = store.add_frame(7, &red, ImageFormat::Rgba, 0, 0, 1, 1, None, None, 0, true, 0);
    assert_eq!(n, None, "oversized canvas must refuse frame composition");
    assert_eq!(store.frame_count(7), 0, "no frame materialized on rejection");
}

/// INTENT: a frame exactly at the canvas-pixel cap is still accepted — the guard
/// rejects only what exceeds the budget, never legitimate large-but-bounded
/// frames. A 1024x256 = 262144-pixel canvas (1 MiB RGBA) is well within cap.
#[test]
fn add_frame_at_reasonable_large_size_is_accepted() {
    let mut store = GraphicsStore::new();
    store.store_image(
        Some(3),
        ImageData::new(vec![0u8; 1024 * 256 * 4], ImageFormat::Rgba, 1024, 256),
    );
    let n = store.add_frame(3, &[0u8; 4], ImageFormat::Rgba, 0, 0, 1, 1, None, None, 0, true, 0);
    assert_eq!(n, Some(2), "a bounded large frame is accepted");
}

// ── Animation control (a=a) ─────────────────────────────────────────────────────

#[test]
fn set_animation_run_state_marks_playing_and_infinite_loop() {
    let mut store = store_with_2x2(1);
    let red: Vec<u8> = std::iter::repeat([0xFF, 0, 0, 0xFF]).take(4).flatten().collect();
    store.add_frame(1, &red, ImageFormat::Rgba, 0, 0, 0, 0, None, None, 0, true, 0);
    assert!(store.set_animation(1, Some(3), Some(1), None), "image exists");
    let (playing, current, loops) = store.animation_state(1).expect("state present");
    assert!(playing, "s=3 starts playback");
    assert_eq!(current, 1, "current frame defaults to 1");
    assert_eq!(loops, 0, "v=1 → infinite (0 sentinel)");
}

#[test]
fn set_animation_stop_state_pauses() {
    let mut store = store_with_2x2(1);
    store.set_animation(1, Some(3), None, None);
    store.set_animation(1, Some(1), None, None);
    let (playing, _, _) = store.animation_state(1).expect("state present");
    assert!(!playing, "s=1 stops playback");
}

#[test]
fn set_animation_current_frame_clamps_and_selects() {
    let mut store = store_with_2x2(1);
    let red: Vec<u8> = std::iter::repeat([0xFF, 0, 0, 0xFF]).take(4).flatten().collect();
    store.add_frame(1, &red, ImageFormat::Rgba, 0, 0, 0, 0, None, None, 0, true, 0); // 2 frames
    store.set_animation(1, None, None, Some(99)); // beyond range
    let (_, current, _) = store.animation_state(1).expect("state present");
    assert_eq!(current, 2, "out-of-range current frame clamps to last");
}

#[test]
fn set_animation_finite_loop_count_recorded() {
    let mut store = store_with_2x2(1);
    store.set_animation(1, Some(3), Some(5), None);
    let (_, _, loops) = store.animation_state(1).expect("state present");
    assert_eq!(loops, 5, "v=5 is a finite loop count");
}

#[test]
fn set_animation_unknown_image_returns_false() {
    let mut store = GraphicsStore::new();
    assert!(!store.set_animation(42, Some(3), None, None), "unknown image → false");
}

#[test]
fn notifications_for_image_covers_each_placement() {
    let mut store = store_with_2x2(1);
    store.add_placement(placement(1, 3, 4));
    store.add_placement(placement(1, 7, 8));
    let notifs = store.notifications_for_image(1);
    assert_eq!(notifs.len(), 2, "one redisplay notification per placement");
    assert_eq!(notifs[0].row, 3);
    assert_eq!(notifs[1].row, 7);
}
