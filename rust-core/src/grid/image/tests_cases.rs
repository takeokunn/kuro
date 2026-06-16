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
    let rgb = ImageData {
        pixels: vec![1, 2, 3, 4, 5, 6],
        format: ImageFormat::Rgb,
        pixel_width: 2,
        pixel_height: 1,
    };
    let rgba = ImageData {
        pixels: vec![1, 2, 3, 4],
        format: ImageFormat::Rgba,
        pixel_width: 1,
        pixel_height: 1,
    };

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

assert_to_png_base64_non_empty!(to_png_base64_rgba_produces_non_empty_string, tiny_rgba(0x40));

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
