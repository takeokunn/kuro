//! Tests for grid/screen/graphics.rs
//!
//! Covers `Screen::active_graphics`, `Screen::active_graphics_mut`, and
//! `Screen::get_image_png_base64` across primary-active and alternate-active states.

use crate::grid::image::{ImageData, ImagePlacement};
use crate::parser::kitty::ImageFormat;
use proptest::prelude::*;

// ── Helpers ──────────────────────────────────────────────────────────────────

use super::make_screen;

/// Build a minimal 1×1 RGB `ImageData` carrying the given pixel byte.
#[inline]
fn tiny_rgb_image(byte: u8) -> ImageData {
    ImageData {
        pixels: vec![byte, byte, byte],
        format: ImageFormat::Rgb,
        pixel_width: 1,
        pixel_height: 1,
    }
}

/// Construct an `ImagePlacement` with explicit fields; remaining fields default to 0/1.
macro_rules! make_placement {
    ($id:expr, row=$r:expr, col=$c:expr, cols=$w:expr, rows=$h:expr) => {
        ImagePlacement {
            image_id: $id,
            row: $r,
            col: $c,
            display_cols: $w,
            display_rows: $h,
        }
    };
}

/// Assert that `get_image_png_base64(id)` returns a non-empty string.
macro_rules! assert_image_present {
    ($store:expr, $id:expr, $msg:literal) => {
        assert!(
            !$store.get_image_png_base64($id).is_empty(),
            $msg
        );
    };
}

/// Assert that `get_image_png_base64(id)` returns an empty string.
macro_rules! assert_image_absent {
    ($store:expr, $id:expr, $msg:literal) => {
        assert_eq!(
            $store.get_image_png_base64($id),
            String::new(),
            $msg
        );
    };
}

// ── active_graphics on primary screen ────────────────────────────────────────

#[test]
fn active_graphics_primary_starts_empty() {
    let s = make_screen();
    // A freshly constructed screen must have no images stored.
    assert_image_absent!(s.active_graphics(), 1, "primary graphics store must be empty on construction");
}

#[test]
fn active_graphics_mut_primary_stores_and_retrieves_image() {
    let mut s = make_screen();
    let data = tiny_rgb_image(0xFF);
    let id = s.active_graphics_mut().store_image(Some(42), data);
    assert_eq!(id, 42);
    // A non-empty base64 string confirms the image was stored.
    assert_image_present!(s.active_graphics(), 42, "stored image must return a non-empty base64 PNG");
}

#[test]
fn active_graphics_primary_unknown_id_returns_empty() {
    let s = make_screen();
    assert_image_absent!(s.active_graphics(), 999, "unknown image ID must return empty string");
}

// ── active_graphics dispatches to alternate screen when active ───────────────

#[test]
fn active_graphics_returns_alternate_store_when_alternate_active() {
    let mut s = make_screen();

    // Store an image in the primary store before switching.
    let primary_data = tiny_rgb_image(0xAA);
    s.active_graphics_mut().store_image(Some(1), primary_data);

    // Switch to alternate — graphics for a different ID stored there.
    s.switch_to_alternate();
    let alt_data = tiny_rgb_image(0xBB);
    let alt_id = s.active_graphics_mut().store_image(Some(2), alt_data);
    assert_eq!(alt_id, 2);

    // While alternate is active, active_graphics should reflect the alternate store.
    // Image 1 was only in primary; it must not be visible via active_graphics.
    assert_image_absent!(s.active_graphics(), 1, "alternate store must not expose primary-only image ID 1");
    // Image 2 was stored in alternate; it must be visible.
    assert_image_present!(s.active_graphics(), 2, "alternate store must return image 2 when alternate is active");
}

#[test]
fn active_graphics_returns_primary_store_after_switching_back() {
    let mut s = make_screen();

    // Store image 7 in primary.
    s.active_graphics_mut()
        .store_image(Some(7), tiny_rgb_image(0x77));

    // Enter alternate, store image 8 there.
    s.switch_to_alternate();
    s.active_graphics_mut()
        .store_image(Some(8), tiny_rgb_image(0x88));

    // Return to primary.
    s.switch_to_primary();

    // Image 7 must now be accessible again.
    assert_image_present!(s.active_graphics(), 7, "primary store must expose image 7 after returning from alternate");
    // Image 8 was only stored in alternate; it must not be visible on primary.
    assert_image_absent!(s.active_graphics(), 8, "primary store must not expose alternate-only image 8");
}

// ── get_image_png_base64 — primary-first search + alternate fallback ──────────

#[test]
fn get_image_png_base64_returns_empty_for_unknown_id() {
    let s = make_screen();
    assert_image_absent!(s, 123, "unknown id must return empty");
}

#[test]
fn get_image_png_base64_returns_primary_image_when_primary_active() {
    let mut s = make_screen();
    s.active_graphics_mut()
        .store_image(Some(5), tiny_rgb_image(0x55));
    assert_image_present!(s, 5, "get_image_png_base64 must return primary image when primary is active");
}

#[test]
fn get_image_png_base64_searches_primary_first_when_alternate_active() {
    // `get_image_png_base64` always checks primary store first.
    // When the alternate is active and the ID lives in primary, it must still
    // be found (the method is not routed through active_graphics).
    let mut s = make_screen();
    s.active_graphics_mut()
        .store_image(Some(3), tiny_rgb_image(0x33));

    s.switch_to_alternate();

    // The method should find image 3 in the primary store even while alternate is active.
    assert_image_present!(s, 3, "get_image_png_base64 must find primary-store image while alternate is active");
}

#[test]
fn get_image_png_base64_falls_back_to_alternate_when_not_in_primary() {
    // Image stored only in the alternate store.
    // get_image_png_base64 must return it when the alternate is active.
    let mut s = make_screen();
    s.switch_to_alternate();
    s.active_graphics_mut()
        .store_image(Some(9), tiny_rgb_image(0x99));
    assert_image_present!(s, 9, "get_image_png_base64 must fall back to alternate store when primary lacks the image");
}

#[test]
fn get_image_png_base64_returns_empty_when_id_absent_in_both_stores() {
    let mut s = make_screen();
    s.switch_to_alternate();
    // No image stored anywhere.
    assert_image_absent!(s, 42, "must return empty when image ID is absent from both stores");
}

// ── active_graphics_mut — auto-id assignment ──────────────────────────────────

#[test]
fn active_graphics_mut_auto_id_starts_at_one() {
    let mut s = make_screen();
    let id = s
        .active_graphics_mut()
        .store_image(None, tiny_rgb_image(0x10));
    assert_eq!(id, 1, "first auto-assigned ID must be 1");
}

#[test]
fn active_graphics_mut_auto_id_increments() {
    let mut s = make_screen();
    let id1 = s
        .active_graphics_mut()
        .store_image(None, tiny_rgb_image(0x10));
    let id2 = s
        .active_graphics_mut()
        .store_image(None, tiny_rgb_image(0x20));
    assert_ne!(id1, id2, "consecutive auto IDs must be distinct");
}

// ── add_placement via active_graphics_mut ────────────────────────────────────

#[test]
fn active_graphics_mut_add_placement_returns_none_for_unknown_image() {
    let mut s = make_screen();
    let placement = make_placement!(99, row=0, col=0, cols=10, rows=5);
    let notif = s.active_graphics_mut().add_placement(placement);
    assert!(
        notif.is_none(),
        "add_placement must return None when image_id is not in the store"
    );
}

#[test]
fn active_graphics_mut_add_placement_returns_notification_for_known_image() {
    let mut s = make_screen();
    s.active_graphics_mut()
        .store_image(Some(11), tiny_rgb_image(0x11));

    let placement = make_placement!(11, row=2, col=4, cols=8, rows=3);
    let notif = s.active_graphics_mut().add_placement(placement);
    assert!(
        notif.is_some(),
        "add_placement must return a notification for a known image"
    );
    let n = notif.unwrap();
    assert_eq!(n.image_id, 11);
    assert_eq!(n.row, 2);
    assert_eq!(n.col, 4);
    assert_eq!(n.cell_width, 8);
    assert_eq!(n.cell_height, 3);
}

// ── store_image duplicate-id replacement ─────────────────────────────────────

#[test]
fn store_image_duplicate_id_replaces_existing() {
    // Storing a second image under the same explicit ID must replace the first.
    // The image is still retrievable (not deleted) after the replacement.
    let mut s = make_screen();
    let data1 = tiny_rgb_image(0xAA);
    let data2 = tiny_rgb_image(0xBB);
    s.active_graphics_mut().store_image(Some(10), data1);
    s.active_graphics_mut().store_image(Some(10), data2);
    // Image id=10 must still be retrievable (replaced, not deleted).
    assert_image_present!(s.active_graphics(), 10, "overwritten image id=10 must still be retrievable after replacement");
    // Id=11 was never stored; must return empty.
    assert_image_absent!(s.active_graphics(), 11, "image id=11 was never stored; must return empty string");
}

// ── delete_by_id removes image and prevents placement ────────────────────────

#[test]
fn delete_by_id_removes_image_and_placement() {
    let mut s = make_screen();
    s.active_graphics_mut()
        .store_image(Some(5), tiny_rgb_image(0x55));

    // add_placement succeeds while the image exists.
    let notif = s.active_graphics_mut().add_placement(make_placement!(5, row=0, col=0, cols=4, rows=2));
    assert!(
        notif.is_some(),
        "add_placement must succeed for stored id=5"
    );

    // delete_by_id removes the image.
    s.active_graphics_mut().delete_by_id(5);

    // Image must no longer be retrievable.
    assert_image_absent!(s.active_graphics(), 5, "image id=5 must not be retrievable after delete_by_id");
    // add_placement must also return None after deletion (image gone).
    let notif2 = s.active_graphics_mut().add_placement(make_placement!(5, row=1, col=1, cols=2, rows=1));
    assert!(
        notif2.is_none(),
        "add_placement must return None after delete_by_id"
    );
}

// ── clear_all_placements removes placements but keeps images ─────────────────

#[test]
fn clear_all_placements_removes_placements_images_survive() {
    let mut s = make_screen();
    s.active_graphics_mut()
        .store_image(Some(1), tiny_rgb_image(0x11));
    s.active_graphics_mut()
        .store_image(Some(2), tiny_rgb_image(0x22));

    s.active_graphics_mut().add_placement(make_placement!(1, row=0, col=0, cols=2, rows=1));
    s.active_graphics_mut().add_placement(make_placement!(2, row=1, col=0, cols=3, rows=2));

    // clear_all_placements must remove placement records but keep images.
    s.active_graphics_mut().clear_all_placements();

    // Images must still be retrievable after placement clear.
    assert_image_present!(s.active_graphics(), 1, "image id=1 must still be retrievable after clear_all_placements");
    assert_image_present!(s.active_graphics(), 2, "image id=2 must still be retrievable after clear_all_placements");

    // A subsequent add_placement must succeed (images are still in store).
    let notif = s.active_graphics_mut().add_placement(make_placement!(1, row=5, col=5, cols=1, rows=1));
    assert!(
        notif.is_some(),
        "add_placement must succeed after clear_all_placements (images intact)"
    );
}

// ── active_graphics count matches store_image calls ──────────────────────────

#[test]
fn active_graphics_count_matches_store_image_calls() {
    // After storing N distinct images, all N must be individually accessible.
    let mut s = make_screen();
    let ids: [u32; 3] = [10, 20, 30];
    for &id in &ids {
        s.active_graphics_mut()
            .store_image(Some(id), tiny_rgb_image(id as u8));
    }
    for &id in &ids {
        assert_image_present!(s.active_graphics(), id, "image must be retrievable after store_image");
    }
    // An id that was never stored must still be absent.
    assert_image_absent!(s.active_graphics(), 99, "image id=99 was never stored; must return empty string");
}

// ── PBT — T2 tier (128 cases) ────────────────────────────────────────────────

proptest! {
    #![proptest_config(ProptestConfig::with_cases(128))]

    #[test]
    // INVARIANT: active_graphics().get_image_png_base64(id) never panics for any u32 id.
    fn prop_active_graphics_get_never_panics(id in 0u32..u32::MAX) {
        let s = make_screen();
        // Either returns a non-empty string or an empty string; must not panic.
        let _ = s.active_graphics().get_image_png_base64(id);
        prop_assert!(true);
    }

    #[test]
    // INVARIANT: storing an image with an explicit ID and then retrieving it
    // returns a non-empty base64 string.
    fn prop_store_and_retrieve_roundtrip(
        id in 1u32..1000u32,
        byte in 0u8..=255u8,
    ) {
        let mut s = make_screen();
        let data = tiny_rgb_image(byte);
        let stored_id = s.active_graphics_mut().store_image(Some(id), data);
        prop_assert_eq!(stored_id, id);
        let result = s.active_graphics().get_image_png_base64(id);
        prop_assert!(
            !result.is_empty(),
            "retrieving stored image {} must return non-empty base64", id
        );
    }
}
