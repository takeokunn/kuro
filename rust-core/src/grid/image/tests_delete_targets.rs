//! Tests for the full Kitty `a=d` delete-target list and z-index / pixel-offset
//! placement metadata on [`GraphicsStore`].
//!
//! Module under test: `grid/image.rs`

use super::tests_support::*;
use crate::grid::screen::{GraphicsStore, ImagePlacement};

/// Build a placement with explicit geometry, z-index and pixel offsets.
fn placement_full(
    image_id: u32,
    row: usize,
    col: usize,
    cols: u32,
    rows: u32,
    z: i32,
) -> ImagePlacement {
    ImagePlacement {
        image_id,
        placement_id: None,
        row,
        col,
        display_cols: cols,
        display_rows: rows,
        z_index: z,
        ..ImagePlacement::default()
    }
}

// --- z-index ordering ---

/// INTENT: placements are stored in ascending z-index order regardless of
/// insertion order (the `z=` stacking key controls draw order).
#[test]
fn add_placement_sorts_by_z_index() {
    let mut store = store_with_image(1);
    store.add_placement(placement_full(1, 0, 0, 1, 1, 5));
    store.add_placement(placement_full(1, 0, 1, 1, 1, -3));
    store.add_placement(placement_full(1, 0, 2, 1, 1, 0));

    assert_eq!(store.placement_z_indices(), vec![-3, 0, 5]);
}

/// INTENT: equal z-index placements keep insertion (arrival) order — stable.
#[test]
fn add_placement_stable_for_equal_z() {
    let mut store = store_with_image(1);
    store.add_placement(placement_full(1, 0, 0, 1, 1, 2));
    store.add_placement(placement_full(1, 0, 9, 1, 1, 2));

    assert_eq!(store.placement_z_indices(), vec![2, 2]);
    // First-inserted (col 0) must still be first.
    let notifs = store.notifications_for_image(1);
    assert_eq!(notifs[0].col, 0);
    assert_eq!(notifs[1].col, 9);
}

// --- pixel offsets stored ---

/// INTENT: cell-internal pixel X/Y offsets are stored on the placement.
#[test]
fn placement_stores_pixel_offsets() {
    let placement = ImagePlacement {
        image_id: 1,
        placement_id: None,
        row: 0,
        col: 0,
        display_cols: 1,
        display_rows: 1,
        z_index: 0,
        pixel_x_offset: 7,
        pixel_y_offset: 11,
    };
    assert_eq!(placement.pixel_x_offset, 7);
    assert_eq!(placement.pixel_y_offset, 11);
}

// --- d=z : delete by z-index ---

/// INTENT: `d=z` removes only placements with the matching z-index; lowercase
/// keeps the image data.
#[test]
fn delete_by_z_lowercase_removes_matching_layer_keeps_image() {
    let mut store = store_with_image(1);
    store.add_placement(placement_full(1, 0, 0, 1, 1, 4));
    store.add_placement(placement_full(1, 0, 1, 1, 1, 9));

    store.delete_by_z(4, false);

    assert_eq!(store.placement_z_indices(), vec![9]);
    assert_image_present(&store, 1);
}

/// INTENT: `d=Z` (uppercase) frees the backing image data of matched placements.
#[test]
fn delete_by_z_uppercase_frees_image() {
    let mut store = store_with_image(1);
    store.add_placement(placement_full(1, 0, 0, 1, 1, 4));

    store.delete_by_z(4, true);

    assert_eq!(store.placement_count(), 0);
    assert_image_missing(&store, 1);
}

// --- d=p : delete at cell ---

/// INTENT: `d=p` removes placements whose display rectangle covers the cell.
#[test]
fn delete_at_cell_removes_covering_placement() {
    let mut store = store_with_image(1);
    // 3x2 image anchored at (row 2, col 5): covers rows 2..4, cols 5..7.
    store.add_placement(placement_full(1, 2, 5, 3, 2, 0));
    // A second placement that does NOT cover (10, 10).
    store.add_placement(placement_full(1, 10, 10, 1, 1, 0));

    store.delete_at_cell(3, 6, false);

    assert_eq!(store.placement_count(), 1, "only the covering placement is removed");
    let notifs = store.notifications_for_image(1);
    assert_eq!(notifs[0].row, 10);
}

/// INTENT: `d=P` (uppercase) at cell frees the backing image data.
#[test]
fn delete_at_cell_uppercase_frees_image() {
    let mut store = store_with_image(1);
    store.add_placement(placement_full(1, 0, 0, 1, 1, 0));
    store.delete_at_cell(0, 0, true);
    assert_image_missing(&store, 1);
}

// --- d=x / d=y : intersecting column / row ---

/// INTENT: `d=x` removes placements intersecting a column across their full
/// width.
#[test]
fn delete_intersecting_col_spans_full_width() {
    let mut store = store_with_image(1);
    // width 4 starting at col 2 → covers cols 2..6.
    store.add_placement(placement_full(1, 0, 2, 4, 1, 0));
    store.add_placement(placement_full(1, 0, 20, 1, 1, 0));

    store.delete_intersecting_col(5, false);

    assert_eq!(store.placement_count(), 1);
    assert_eq!(store.notifications_for_image(1)[0].col, 20);
}

/// INTENT: `d=y` removes placements intersecting a row across their full height.
#[test]
fn delete_intersecting_row_spans_full_height() {
    let mut store = store_with_image(1);
    // height 3 starting at row 4 → covers rows 4..7.
    store.add_placement(placement_full(1, 4, 0, 1, 3, 0));
    store.add_placement(placement_full(1, 20, 0, 1, 1, 0));

    store.delete_intersecting_row(6, false);

    assert_eq!(store.placement_count(), 1);
    assert_eq!(store.notifications_for_image(1)[0].row, 20);
}

// --- d=q : delete at cell with z ---

/// INTENT: `d=q` removes only placements covering the cell AND matching z.
#[test]
fn delete_at_cell_with_z_matches_both_cell_and_z() {
    let mut store = store_with_image(1);
    store.add_placement(placement_full(1, 0, 0, 2, 2, 5)); // covers (0,0), z=5
    store.add_placement(placement_full(1, 0, 0, 2, 2, 9)); // covers (0,0), z=9

    store.delete_at_cell_with_z(0, 0, 5, false);

    assert_eq!(store.placement_z_indices(), vec![9], "only z=5 layer removed");
}

// --- d=n : newest by number ---

/// INTENT: `d=n` with no number deletes placements of the highest-id image.
#[test]
fn delete_newest_targets_highest_image_id() {
    let mut store = store_with_images(&[1, 2, 3]);
    store.add_placement(placement_full(1, 0, 0, 1, 1, 0));
    store.add_placement(placement_full(3, 0, 1, 1, 1, 0));

    store.delete_newest(None, false);

    assert_image_present(&store, 1);
    assert_image_present(&store, 2);
    // image 3 (highest) placement removed; lowercase keeps data.
    assert_eq!(store.placement_count(), 1);
    assert_eq!(store.notifications_for_image(1).len(), 1);
}

/// INTENT: `d=N` (uppercase) with explicit number frees that image's data.
#[test]
fn delete_newest_with_number_uppercase_frees_image() {
    let mut store = store_with_images(&[5, 6]);
    store.add_placement(placement_full(5, 0, 0, 1, 1, 0));

    store.delete_newest(Some(5), true);

    assert_image_missing(&store, 5);
    assert_image_present(&store, 6);
}

// --- d=r : id range ---

/// INTENT: `d=r` removes placements whose image id is in the inclusive range.
#[test]
fn delete_id_range_inclusive() {
    let mut store = store_with_images(&[10, 11, 12, 13]);
    for id in [10, 11, 12, 13] {
        store.add_placement(placement_full(id, 0, 0, 1, 1, 0));
    }

    store.delete_id_range(11, 12, false);

    assert_image_present(&store, 10);
    assert_image_present(&store, 13);
    assert_eq!(store.placement_count(), 2, "ids 11 and 12 placements removed");
}

/// INTENT: `d=R` (uppercase) id range frees image data in range.
#[test]
fn delete_id_range_uppercase_frees_images() {
    let mut store = store_with_images(&[10, 11, 12]);
    for id in [10, 11, 12] {
        store.add_placement(placement_full(id, 0, 0, 1, 1, 0));
    }

    store.delete_id_range(10, 11, true);

    assert_image_missing(&store, 10);
    assert_image_missing(&store, 11);
    assert_image_present(&store, 12);
}

// --- d=a : all ---

/// INTENT: `d=a` (lowercase) clears every placement but keeps image data.
#[test]
fn delete_all_lowercase_keeps_images() {
    let mut store = store_with_images(&[1, 2]);
    store.add_placement(placement_full(1, 0, 0, 1, 1, 0));
    store.add_placement(placement_full(2, 0, 1, 1, 1, 0));

    store.delete_all(false);

    assert_eq!(store.placement_count(), 0);
    assert_image_present(&store, 1);
    assert_image_present(&store, 2);
}

/// INTENT: `d=A` (uppercase) frees image data of every placed image.
#[test]
fn delete_all_uppercase_frees_placed_images() {
    let mut store = store_with_images(&[1, 2, 3]);
    store.add_placement(placement_full(1, 0, 0, 1, 1, 0));
    store.add_placement(placement_full(2, 0, 1, 1, 1, 0));

    store.delete_all(true);

    assert_eq!(store.placement_count(), 0);
    assert_image_missing(&store, 1);
    assert_image_missing(&store, 2);
    // image 3 had no placement → its data is untouched.
    assert_image_present(&store, 3);
}

/// INTENT: deleting placements that reference an image still in use elsewhere
/// frees the image entirely (freeing image data invalidates all its placements).
#[test]
fn free_data_removes_all_placements_of_freed_image() {
    let mut store = store_with_image(1);
    store.add_placement(placement_full(1, 0, 0, 1, 1, 7));
    store.add_placement(placement_full(1, 5, 5, 1, 1, 7));
    // Two placements of image 1 at z=7. Uppercase d=z frees image 1 entirely.
    store.delete_by_z(7, true);
    assert_image_missing(&store, 1);
    assert_eq!(store.placement_count(), 0);
}

// --- adversarial: malformed / non-matching delete targets ---

/// INTENT: `d=z` with a *negative* z-index matches only the negative layer;
/// signed z is honored end-to-end (the `z=` key is parsed as i32).
#[test]
fn delete_by_z_negative_matches_only_negative_layer() {
    let mut store = store_with_image(1);
    store.add_placement(placement_full(1, 0, 0, 1, 1, -5));
    store.add_placement(placement_full(1, 0, 1, 1, 1, 3));

    store.delete_by_z(-5, false);

    assert_eq!(store.placement_z_indices(), vec![3]);
    assert_image_present(&store, 1);
}

/// INTENT: deleting a nonexistent image id is a no-op — placements of other
/// images and their data are untouched.
#[test]
fn delete_nonexistent_id_is_noop() {
    let mut store = store_with_image(1);
    store.add_placement(placement_full(1, 0, 0, 1, 1, 0));

    store.delete_id(999, false);

    assert_eq!(store.placement_count(), 1);
    assert_image_present(&store, 1);
}

/// INTENT: an inverted `d=r` range (min > max) matches nothing — no placement
/// is removed and no image is freed.
#[test]
fn delete_id_range_inverted_matches_nothing() {
    let mut store = store_with_images(&[10, 11, 12]);
    for id in [10, 11, 12] {
        store.add_placement(placement_full(id, 0, 0, 1, 1, 0));
    }

    store.delete_id_range(12, 10, false);

    assert_eq!(store.placement_count(), 3);
    assert_image_present(&store, 10);
    assert_image_present(&store, 11);
    assert_image_present(&store, 12);
}

/// INTENT: `d=p` at an empty cell (no placement covers it) removes nothing.
#[test]
fn delete_at_empty_cell_is_noop() {
    let mut store = store_with_image(1);
    store.add_placement(placement_full(1, 5, 5, 1, 1, 0));

    store.delete_at_cell(0, 0, false);

    assert_eq!(store.placement_count(), 1);
}

/// INTENT: uppercase `d=P` at an empty cell must NOT free the backing image —
/// freeing only happens when a placement actually matched.
#[test]
fn uppercase_delete_at_empty_cell_keeps_image() {
    let mut store = store_with_image(1);
    store.add_placement(placement_full(1, 5, 5, 1, 1, 0));

    store.delete_at_cell(0, 0, true);

    assert_eq!(store.placement_count(), 1);
    assert_image_present(&store, 1);
}

/// INTENT: uppercase `d=Z` at a z-index with no matching placement must NOT
/// free the backing image data.
#[test]
fn uppercase_delete_by_z_no_match_keeps_image() {
    let mut store = store_with_image(1);
    store.add_placement(placement_full(1, 0, 0, 1, 1, 5));

    store.delete_by_z(99, true);

    assert_eq!(store.placement_count(), 1);
    assert_image_present(&store, 1);
}
