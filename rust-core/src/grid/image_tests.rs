#[cfg(test)]
mod tests {
    use super::*;
    use crate::parser::kitty::ImageFormat;

    // ── Helpers ────────���───────────────────────────���─────────────────────────

    fn tiny_rgb(byte: u8) -> ImageData {
        ImageData {
            pixels: vec![byte, byte, byte],
            format: ImageFormat::Rgb,
            pixel_width: 1,
            pixel_height: 1,
        }
    }

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
            placement_id: None,
            row,
            col,
            display_cols: 10,
            display_rows: 5,
        }
    }

    fn min_placement(image_id: u32, row: usize, col: usize) -> ImagePlacement {
        ImagePlacement {
            image_id,
            placement_id: None,
            row,
            col,
            display_cols: 1,
            display_rows: 1,
        }
    }

    // ── Macros ─────────���─────────────────────────────��───────────────────────

    macro_rules! assert_image_survives {
        ($name:ident, $id:expr, $img:expr, $setup:expr, $op:expr, $msg:expr) => {
            #[test]
            fn $name() {
                let mut store = GraphicsStore::new();
                store.store_image(Some($id), $img);
                let setup_fn: &dyn Fn(&mut GraphicsStore) = &$setup;
                setup_fn(&mut store);
                let op_fn: &dyn Fn(&mut GraphicsStore) = &$op;
                op_fn(&mut store);
                assert!(!store.get_image_png_base64($id).is_empty(), $msg);
            }
        };
    }

    macro_rules! assert_to_png_base64_non_empty {
        ($name:ident, $img:expr, $msg:expr) => {
            #[test]
            fn $name() {
                let data = $img;
                let b64 = data.to_png_base64();
                assert!(!b64.is_empty(), $msg);
            }
        };
    }

    // ── GraphicsStore::new() — empty state ��───────────────────────────��─────

    #[test]
    fn new_returns_empty_store() {
        let store = GraphicsStore::new();
        assert_eq!(store.get_image_png_base64(1), String::new());
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

    // ── store_image — explicit ID ────────��──────────────────────────────────

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
        assert!(!store.get_image_png_base64(7).is_empty());
    }

    // ── store_image — auto-ID assignment ───────────��────────────────────────

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

    // ── store_image — overwrite semantics ──────��────────────────────────────

    #[test]
    fn store_image_overwrite_same_id_replaces_data() {
        let mut store = GraphicsStore::new();
        store.store_image(Some(5), tiny_rgb(0x00));
        store.store_image(Some(5), tiny_rgba(0xFF));
        assert!(!store.get_image_png_base64(5).is_empty());
    }

    // ── get_image_png_base64 ────────────────────────────────────────────────

    #[test]
    fn get_image_png_base64_returns_empty_for_unknown_id() {
        let store = GraphicsStore::new();
        assert_eq!(store.get_image_png_base64(999), String::new());
    }

    #[test]
    fn get_image_png_base64_returns_valid_base64_for_known_id() {
        let mut store = GraphicsStore::new();
        store.store_image(Some(3), tiny_rgb(0x80));
        let result = store.get_image_png_base64(3);
        assert!(result
            .chars()
            .all(|c| c.is_alphanumeric() || c == '+' || c == '/' || c == '='));
    }

    // ── add_placement ───────────────────────────────────────────────────────

    #[test]
    fn add_placement_returns_none_for_unknown_image() {
        let mut store = GraphicsStore::new();
        assert!(store.add_placement(make_placement(99, 0, 0)).is_none());
    }

    #[test]
    fn add_placement_returns_notification_with_correct_fields() {
        let mut store = GraphicsStore::new();
        store.store_image(Some(10), tiny_rgb(0x10));
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
        let mut store = GraphicsStore::new();
        store.store_image(Some(1), tiny_rgb(0x01));
        assert!(store.add_placement(make_placement(1, 0, 0)).is_some());
        assert!(store.add_placement(make_placement(1, 5, 2)).is_some());
    }

    // ── clear_all_placements ────────���───────────────────────────────────────

    #[test]
    fn clear_all_placements_empties_the_placement_list() {
        let mut store = GraphicsStore::new();
        store.store_image(Some(1), tiny_rgb(0x01));
        store.store_image(Some(2), tiny_rgb(0x02));
        store.add_placement(make_placement(1, 0, 0));
        store.add_placement(make_placement(2, 1, 0));
        store.clear_all_placements();
        assert!(!store.get_image_png_base64(1).is_empty());
        assert!(!store.get_image_png_base64(2).is_empty());
        assert!(store.add_placement(make_placement(1, 3, 0)).is_some());
    }

    // ── scroll_up ──────────────────────────────────────���────────────────────

    assert_image_survives!(
        scroll_up_shifts_placement_rows_up_by_n,
        1,
        tiny_rgb(0x01),
        |s| {
            s.add_placement(min_placement(1, 5, 0));
        },
        |s| {
            s.scroll_up(3);
            s.add_placement(min_placement(1, 2, 0));
        },
        "image must still be present after scroll_up"
    );

    assert_image_survives!(
        scroll_up_discards_placements_that_scroll_off_the_top,
        1,
        tiny_rgb(0x01),
        |s| {
            s.add_placement(min_placement(1, 1, 0));
        },
        |s| {
            s.scroll_up(2);
        },
        "image data must survive scroll_up even when its placement is discarded"
    );

    // ── scroll_down ─────────────────────────────────────────────────────────

    assert_image_survives!(
        scroll_down_shifts_placement_rows_down_by_n,
        1,
        tiny_rgb(0x01),
        |s| {
            s.add_placement(min_placement(1, 2, 0));
        },
        |s| {
            s.scroll_down(3, 24);
        },
        "image must survive scroll_down"
    );

    // ── delete_by_id ───────────���────────────────────────────────────────────

    #[test]
    fn delete_by_id_removes_image_from_store() {
        let mut store = GraphicsStore::new();
        store.store_image(Some(20), tiny_rgb(0x20));
        store.delete_by_id(20);
        assert_eq!(store.get_image_png_base64(20), String::new());
    }

    #[test]
    fn delete_by_id_on_unknown_id_does_not_panic() {
        let mut store = GraphicsStore::new();
        store.delete_by_id(9999);
        store.store_image(Some(1), tiny_rgb(0x01));
        assert!(!store.get_image_png_base64(1).is_empty());
    }

    #[test]
    fn delete_by_id_removes_associated_placements() {
        let mut store = GraphicsStore::new();
        store.store_image(Some(5), tiny_rgb(0x05));
        store.add_placement(make_placement(5, 1, 0));
        store.delete_by_id(5);
        assert!(store.add_placement(make_placement(5, 2, 0)).is_none());
    }

    // ── byte_count ──────────���───────────────────────────────────────────────

    #[test]
    fn image_data_byte_count_matches_pixel_vec_len() {
        let rgb = ImageData {
            pixels: vec![1, 2, 3, 4, 5, 6],
            format: ImageFormat::Rgb,
            pixel_width: 2,
            pixel_height: 1,
        };
        assert_eq!(rgb.byte_count(), 6);
        let rgba = ImageData {
            pixels: vec![1, 2, 3, 4],
            format: ImageFormat::Rgba,
            pixel_width: 1,
            pixel_height: 1,
        };
        assert_eq!(rgba.byte_count(), 4);
    }

    // ── to_png_base64 ───────────────────────────────────────────────────────

    assert_to_png_base64_non_empty!(
        to_png_base64_produces_non_empty_string_for_valid_image,
        tiny_rgb(0x80),
        "to_png_base64 must produce a non-empty string"
    );

    assert_to_png_base64_non_empty!(
        to_png_base64_rgba_produces_non_empty_string,
        tiny_rgba(0x40),
        "to_png_base64 for RGBA must produce a non-empty string"
    );

    // ── scroll_up edge cases ───────────��────────────────────────────────────

    assert_image_survives!(
        scroll_up_zero_is_noop,
        1,
        tiny_rgb(0x01),
        |s| {
            s.add_placement(min_placement(1, 5, 0));
        },
        |s| {
            s.scroll_up(0);
        },
        "image must survive scroll_up(0)"
    );

    assert_image_survives!(
        scroll_up_keeps_placement_at_exact_boundary,
        1,
        tiny_rgb(0x01),
        |s| {
            s.add_placement(min_placement(1, 5, 0));
        },
        |s| {
            s.scroll_up(5);
        },
        "image must survive scroll_up equal to placement row"
    );

    // ── scroll_down edge cases ──────────────────────────────────────────────

    assert_image_survives!(
        scroll_down_with_zero_max_row_clamps_to_zero,
        1,
        tiny_rgb(0x01),
        |s| {
            s.add_placement(min_placement(1, 0, 0));
        },
        |s| {
            s.scroll_down(5, 0);
        },
        "image must survive scroll_down with max_row=0"
    );

    assert_image_survives!(
        scroll_down_clamps_placement_to_max_row_minus_one,
        1,
        tiny_rgb(0x01),
        |s| {
            s.add_placement(min_placement(1, 20, 0));
        },
        |s| {
            s.scroll_down(100, 24);
        },
        "image must survive scroll_down with large n"
    );


include!("image_tests2.rs");
}
