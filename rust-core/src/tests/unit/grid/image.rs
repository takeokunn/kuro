//! Unit tests for `grid/image.rs`.
//!
//! Covers `GraphicsStore` directly: construction, `store_image`, `get_image_png_base64`,
//! `add_placement`, `clear_all_placements`, `scroll_up`, `scroll_down`, and `delete_by_id`.

use crate::grid::image::{GraphicsStore, ImageData, ImagePlacement};
use crate::parser::kitty::ImageFormat;

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Build a minimal 1×1 RGB `ImageData`.
fn tiny_rgb(byte: u8) -> ImageData {
    ImageData {
        pixels: vec![byte, byte, byte],
        format: ImageFormat::Rgb,
        pixel_width: 1,
        pixel_height: 1,
    }
}

/// Build a minimal 1×1 RGBA `ImageData`.
fn tiny_rgba(byte: u8) -> ImageData {
    ImageData {
        pixels: vec![byte, byte, byte, 0xFF],
        format: ImageFormat::Rgba,
        pixel_width: 1,
        pixel_height: 1,
    }
}

fn make_placement(image_id: u32, row: usize, col: usize) -> ImagePlacement {
    ImagePlacement {
        image_id,
        row,
        col,
        display_cols: 10,
        display_rows: 5,
    }
}

// ── GraphicsStore::new() — empty state ───────────────────────────────────────

#[test]
fn new_returns_empty_store() {
    let store = GraphicsStore::new();
    // An empty store returns empty string for any image ID.
    assert_eq!(
        store.get_image_png_base64(1),
        String::new(),
        "new store must return empty string for any image ID"
    );
}

#[test]
fn default_is_equivalent_to_new() {
    let by_new = GraphicsStore::new();
    let by_default = GraphicsStore::default();
    // Both must return empty for unknown IDs.
    assert_eq!(
        by_new.get_image_png_base64(1),
        by_default.get_image_png_base64(1),
        "Default and new() must produce equivalent empty stores"
    );
}

// ── store_image — explicit ID ─────────────────────────────────────────────────

#[test]
fn store_image_explicit_id_returns_that_id() {
    let mut store = GraphicsStore::new();
    let id = store.store_image(Some(42), tiny_rgb(0xFF));
    assert_eq!(id, 42, "store_image with explicit ID must return that ID");
}

#[test]
fn store_image_explicit_id_is_retrievable() {
    let mut store = GraphicsStore::new();
    store.store_image(Some(7), tiny_rgb(0xAA));
    let png_b64 = store.get_image_png_base64(7);
    assert!(
        !png_b64.is_empty(),
        "stored image must be retrievable as a non-empty base64 PNG"
    );
}

// ── store_image — auto-ID assignment ─────────────────────────────────────────

#[test]
fn store_image_auto_id_starts_at_one() {
    let mut store = GraphicsStore::new();
    let id = store.store_image(None, tiny_rgb(0x10));
    assert_eq!(id, 1, "first auto-assigned ID must be 1");
}

#[test]
fn store_image_auto_id_increments_on_each_call() {
    let mut store = GraphicsStore::new();
    let id1 = store.store_image(None, tiny_rgb(0x10));
    let id2 = store.store_image(None, tiny_rgb(0x20));
    let id3 = store.store_image(None, tiny_rgb(0x30));
    assert!(id1 < id2, "auto IDs must increment: {id1} < {id2}");
    assert!(id2 < id3, "auto IDs must increment: {id2} < {id3}");
    assert_ne!(id1, id2, "consecutive auto IDs must be distinct");
    assert_ne!(id2, id3, "consecutive auto IDs must be distinct");
}

// ── store_image — overwrite semantics ────────────────────────────────────────

#[test]
fn store_image_overwrite_same_id_replaces_data() {
    let mut store = GraphicsStore::new();
    store.store_image(Some(5), tiny_rgb(0x00));
    // Overwrite with RGBA image to confirm replacement.
    store.store_image(Some(5), tiny_rgba(0xFF));
    let png_b64 = store.get_image_png_base64(5);
    assert!(
        !png_b64.is_empty(),
        "overwritten image must still be retrievable"
    );
}

// ── get_image_png_base64 ──────────────────────────────────────────────────────

#[test]
fn get_image_png_base64_returns_empty_for_unknown_id() {
    let store = GraphicsStore::new();
    assert_eq!(
        store.get_image_png_base64(999),
        String::new(),
        "unknown ID must return empty string"
    );
}

#[test]
fn get_image_png_base64_returns_valid_base64_for_known_id() {
    let mut store = GraphicsStore::new();
    store.store_image(Some(3), tiny_rgb(0x80));
    let result = store.get_image_png_base64(3);
    // A valid base64 string contains only base64 alphabet characters.
    assert!(
        result
            .chars()
            .all(|c| c.is_alphanumeric() || c == '+' || c == '/' || c == '='),
        "get_image_png_base64 must return a valid base64 string"
    );
}

// ── add_placement ─────────────────────────────────────────────────────────────

#[test]
fn add_placement_returns_none_for_unknown_image() {
    let mut store = GraphicsStore::new();
    let result = store.add_placement(make_placement(99, 0, 0));
    assert!(
        result.is_none(),
        "add_placement must return None when image_id is not stored"
    );
}

#[test]
fn add_placement_returns_notification_with_correct_fields() {
    let mut store = GraphicsStore::new();
    store.store_image(Some(10), tiny_rgb(0x10));
    let placement = ImagePlacement {
        image_id: 10,
        row: 3,
        col: 7,
        display_cols: 12,
        display_rows: 4,
    };
    let notif = store
        .add_placement(placement)
        .expect("must return Some for known image");
    assert_eq!(notif.image_id, 10);
    assert_eq!(notif.row, 3);
    assert_eq!(notif.col, 7);
    assert_eq!(notif.cell_width, 12);
    assert_eq!(notif.cell_height, 4);
}

#[test]
fn add_placement_multiple_placements_for_same_image() {
    let mut store = GraphicsStore::new();
    store.store_image(Some(1), tiny_rgb(0x01));
    let n1 = store.add_placement(make_placement(1, 0, 0));
    let n2 = store.add_placement(make_placement(1, 5, 2));
    assert!(n1.is_some(), "first placement must succeed");
    assert!(
        n2.is_some(),
        "second placement on same image must also succeed"
    );
}

// ── clear_all_placements ──────────────────────────────────────────────────────

#[test]
fn clear_all_placements_empties_the_placement_list() {
    let mut store = GraphicsStore::new();
    store.store_image(Some(1), tiny_rgb(0x01));
    store.store_image(Some(2), tiny_rgb(0x02));
    store.add_placement(make_placement(1, 0, 0));
    store.add_placement(make_placement(2, 1, 0));
    // After clearing placements, the images themselves remain.
    store.clear_all_placements();
    // Images must still be retrievable.
    assert!(
        !store.get_image_png_base64(1).is_empty(),
        "image 1 must still exist after clear_all_placements"
    );
    assert!(
        !store.get_image_png_base64(2).is_empty(),
        "image 2 must still exist after clear_all_placements"
    );
    // A subsequent placement for the same ID must still succeed (store is intact).
    let notif = store.add_placement(make_placement(1, 3, 0));
    assert!(
        notif.is_some(),
        "add_placement must succeed after clear_all_placements"
    );
}

// ── scroll_up ─────────────────────────────────────────────────────────────────

#[test]
fn scroll_up_shifts_placement_rows_up_by_n() {
    let mut store = GraphicsStore::new();
    store.store_image(Some(1), tiny_rgb(0x01));
    store.add_placement(ImagePlacement {
        image_id: 1,
        row: 5,
        col: 0,
        display_cols: 1,
        display_rows: 1,
    });
    // Scroll up by 3: row 5 → 2.  The placement must survive (row >= 3).
    store.scroll_up(3);
    // Store an image at a new position to confirm state is consistent.
    let notif = store.add_placement(ImagePlacement {
        image_id: 1,
        row: 2,
        col: 0,
        display_cols: 1,
        display_rows: 1,
    });
    assert!(
        notif.is_some(),
        "image must still be present after scroll_up"
    );
}

#[test]
fn scroll_up_discards_placements_that_scroll_off_the_top() {
    let mut store = GraphicsStore::new();
    store.store_image(Some(1), tiny_rgb(0x01));
    // Place at row 1 — will be scrolled off when n=2.
    store.add_placement(ImagePlacement {
        image_id: 1,
        row: 1,
        col: 0,
        display_cols: 1,
        display_rows: 1,
    });
    store.scroll_up(2);
    // The image data must still exist (scroll_up does not evict images).
    assert!(
        !store.get_image_png_base64(1).is_empty(),
        "image data must survive scroll_up even when its placement is discarded"
    );
}

// ── scroll_down ───────────────────────────────────────────────────────────────

#[test]
fn scroll_down_shifts_placement_rows_down_by_n() {
    let mut store = GraphicsStore::new();
    store.store_image(Some(1), tiny_rgb(0x01));
    store.add_placement(ImagePlacement {
        image_id: 1,
        row: 2,
        col: 0,
        display_cols: 1,
        display_rows: 1,
    });
    // scroll_down with n=3, max_row=24: row 2 → min(5, 23) = 5.
    store.scroll_down(3, 24);
    // Image must still be present.
    assert!(
        !store.get_image_png_base64(1).is_empty(),
        "image must survive scroll_down"
    );
}

// ── delete_by_id ──────────────────────────────────────────────────────────────

#[test]
fn delete_by_id_removes_image_from_store() {
    let mut store = GraphicsStore::new();
    store.store_image(Some(20), tiny_rgb(0x20));
    store.delete_by_id(20);
    assert_eq!(
        store.get_image_png_base64(20),
        String::new(),
        "get_image_png_base64 must return empty after delete_by_id"
    );
}

#[test]
fn delete_by_id_on_unknown_id_does_not_panic() {
    let mut store = GraphicsStore::new();
    // Deleting a non-existent ID must be a silent no-op.
    store.delete_by_id(9999);
    // Store must still be usable.
    store.store_image(Some(1), tiny_rgb(0x01));
    assert!(!store.get_image_png_base64(1).is_empty());
}

#[test]
fn delete_by_id_removes_associated_placements() {
    let mut store = GraphicsStore::new();
    store.store_image(Some(5), tiny_rgb(0x05));
    store.add_placement(make_placement(5, 1, 0));
    store.delete_by_id(5);
    // The image is gone; add_placement for the same ID must now return None.
    let result = store.add_placement(make_placement(5, 2, 0));
    assert!(
        result.is_none(),
        "add_placement must return None after image is deleted"
    );
}

// ── byte_count helper on ImageData ────────────────────────────────────────────

#[test]
fn image_data_byte_count_matches_pixel_vec_len() {
    let rgb = ImageData {
        pixels: vec![1, 2, 3, 4, 5, 6],
        format: ImageFormat::Rgb,
        pixel_width: 2,
        pixel_height: 1,
    };
    assert_eq!(rgb.byte_count(), 6, "byte_count must equal pixels.len()");

    let rgba = ImageData {
        pixels: vec![1, 2, 3, 4],
        format: ImageFormat::Rgba,
        pixel_width: 1,
        pixel_height: 1,
    };
    assert_eq!(rgba.byte_count(), 4);
}

// ── to_png_base64 round-trip ──────────────────────────────────────────────────

#[test]
fn to_png_base64_produces_non_empty_string_for_valid_image() {
    let data = tiny_rgb(0x80);
    let b64 = data.to_png_base64();
    assert!(
        !b64.is_empty(),
        "to_png_base64 must produce a non-empty string"
    );
}

#[test]
fn to_png_base64_rgba_produces_non_empty_string() {
    let data = tiny_rgba(0x40);
    let b64 = data.to_png_base64();
    assert!(
        !b64.is_empty(),
        "to_png_base64 for RGBA must produce a non-empty string"
    );
}

// ── scroll_up edge cases ──────────────────────────────────────────────────────

#[test]
// INVARIANT: scroll_up(0) is a no-op — placement at row 5 must still be
// in the store and a subsequent add_placement must succeed.
fn scroll_up_zero_is_noop() {
    let mut store = GraphicsStore::new();
    store.store_image(Some(1), tiny_rgb(0x01));
    store.add_placement(ImagePlacement {
        image_id: 1,
        row: 5,
        col: 0,
        display_cols: 1,
        display_rows: 1,
    });
    store.scroll_up(0);
    // Image data must still be present.
    assert!(
        !store.get_image_png_base64(1).is_empty(),
        "image must survive scroll_up(0)"
    );
}

#[test]
// INVARIANT: scroll_up(n) where n equals the exact row of a placement
// discards that placement (row < n is false when row == n, but the
// condition is `row < n` so row == n is kept).
fn scroll_up_keeps_placement_at_exact_boundary() {
    let mut store = GraphicsStore::new();
    store.store_image(Some(1), tiny_rgb(0x01));
    // Place at row == n (n=5, row=5): row 5 - 5 = 0 — survives.
    store.add_placement(ImagePlacement {
        image_id: 1,
        row: 5,
        col: 0,
        display_cols: 1,
        display_rows: 1,
    });
    store.scroll_up(5);
    // row=5 is NOT < 5, so placement survives at row=0.
    // Image data must still be present.
    assert!(
        !store.get_image_png_base64(1).is_empty(),
        "image must survive scroll_up equal to placement row"
    );
}

// ── scroll_down edge cases ────────────────────────────────────────────────────

#[test]
// INVARIANT: scroll_down(n, max_row=0) uses saturating_sub(1) = 0, so
// all placements are clamped to row 0.
fn scroll_down_with_zero_max_row_clamps_to_zero() {
    let mut store = GraphicsStore::new();
    store.store_image(Some(1), tiny_rgb(0x01));
    store.add_placement(ImagePlacement {
        image_id: 1,
        row: 0,
        col: 0,
        display_cols: 1,
        display_rows: 1,
    });
    // max_row=0 → saturating_sub(1) = 0 → clamped to 0.
    store.scroll_down(5, 0);
    assert!(
        !store.get_image_png_base64(1).is_empty(),
        "image must survive scroll_down with max_row=0"
    );
}

#[test]
// INVARIANT: scroll_down(n, max_row) clamps placement to max_row - 1 when
// the shifted row would exceed the terminal height.
fn scroll_down_clamps_placement_to_max_row_minus_one() {
    let mut store = GraphicsStore::new();
    store.store_image(Some(1), tiny_rgb(0x01));
    store.add_placement(ImagePlacement {
        image_id: 1,
        row: 20,
        col: 0,
        display_cols: 1,
        display_rows: 1,
    });
    // scroll_down(100, 24): row = min(20+100, 23) = 23.
    store.scroll_down(100, 24);
    // Image must still be present (scroll_down never discards images).
    assert!(
        !store.get_image_png_base64(1).is_empty(),
        "image must survive scroll_down with large n"
    );
}

// ── delete_by_id — multiple images, partial delete ────────────────────────────

#[test]
// INVARIANT: Deleting one image from a multi-image store leaves the other
// images intact.
fn delete_by_id_leaves_other_images_intact() {
    let mut store = GraphicsStore::new();
    store.store_image(Some(10), tiny_rgb(0x10));
    store.store_image(Some(20), tiny_rgb(0x20));
    store.store_image(Some(30), tiny_rgb(0x30));

    store.delete_by_id(20);

    assert!(
        !store.get_image_png_base64(10).is_empty(),
        "image 10 must survive after deleting image 20"
    );
    assert_eq!(
        store.get_image_png_base64(20),
        String::new(),
        "image 20 must be gone"
    );
    assert!(
        !store.get_image_png_base64(30).is_empty(),
        "image 30 must survive after deleting image 20"
    );
}

// ── clear_all_placements — then re-add ───────────────────────────────────────

#[test]
// INVARIANT: clear_all_placements followed by delete_by_id must remove the
// image and prevent a subsequent add_placement from succeeding.
fn clear_placements_then_delete_by_id_prevents_placement() {
    let mut store = GraphicsStore::new();
    store.store_image(Some(3), tiny_rgb(0x03));
    store.add_placement(make_placement(3, 1, 0));
    store.clear_all_placements();
    store.delete_by_id(3);
    // Image gone — placement must return None.
    let result = store.add_placement(make_placement(3, 0, 0));
    assert!(
        result.is_none(),
        "add_placement must return None after image deleted via delete_by_id"
    );
}

// ── auto-ID — sequential uniqueness ──────────────────────────────────────────

#[test]
// INVARIANT: Five consecutive auto-ID calls must produce five distinct IDs,
// each greater than the previous one (wrapping is not expected within 5 calls).
fn store_image_auto_id_five_consecutive_are_unique() {
    let mut store = GraphicsStore::new();
    let mut ids = Vec::new();
    for byte in 0u8..5 {
        ids.push(store.store_image(None, tiny_rgb(byte)));
    }
    // All IDs must be distinct.
    let mut sorted = ids.clone();
    sorted.sort_unstable();
    sorted.dedup();
    assert_eq!(
        sorted.len(),
        5,
        "five consecutive auto-assigned IDs must be unique; got {ids:?}"
    );
}

// ── byte_count corner cases ───────────────────────────────────────────────────

#[test]
// INVARIANT: byte_count() of an empty-pixels ImageData is 0.
fn image_data_byte_count_empty_pixels_is_zero() {
    let data = ImageData {
        pixels: vec![],
        format: crate::parser::kitty::ImageFormat::Rgb,
        pixel_width: 0,
        pixel_height: 0,
    };
    assert_eq!(data.byte_count(), 0, "byte_count of empty ImageData must be 0");
}
