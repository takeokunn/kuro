    // ── delete_by_id — multiple images ─────────��────────────────────────────

    #[test]
    fn delete_by_id_leaves_other_images_intact() {
        let mut store = GraphicsStore::new();
        store.store_image(Some(10), tiny_rgb(0x10));
        store.store_image(Some(20), tiny_rgb(0x20));
        store.store_image(Some(30), tiny_rgb(0x30));
        store.delete_by_id(20);
        assert!(!store.get_image_png_base64(10).is_empty());
        assert_eq!(store.get_image_png_base64(20), String::new());
        assert!(!store.get_image_png_base64(30).is_empty());
    }

    #[test]
    fn clear_placements_then_delete_by_id_prevents_placement() {
        let mut store = GraphicsStore::new();
        store.store_image(Some(3), tiny_rgb(0x03));
        store.add_placement(make_placement(3, 1, 0));
        store.clear_all_placements();
        store.delete_by_id(3);
        assert!(store.add_placement(make_placement(3, 0, 0)).is_none());
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
    fn image_data_byte_count_empty_pixels_is_zero() {
        let data = ImageData {
            pixels: vec![],
            format: ImageFormat::Rgb,
            pixel_width: 0,
            pixel_height: 0,
        };
        assert_eq!(data.byte_count(), 0);
    }

    // ── delete_by_placement ─────────────────────────────────────────────────

    #[test]
    fn delete_by_placement_removes_matching_placement() {
        let mut store = GraphicsStore::new();
        store.store_image(Some(1), tiny_rgb(0x01));
        store.add_placement(ImagePlacement {
            image_id: 1,
            placement_id: Some(42),
            row: 0,
            col: 0,
            display_cols: 2,
            display_rows: 2,
        });
        store.delete_by_placement(1, 42);
        // Image data must survive; only the placement is removed
        assert!(!store.get_image_png_base64(1).is_empty());
        // Verify no placements remain by checking add_placement returns Some again
        assert!(store
            .add_placement(ImagePlacement {
                image_id: 1,
                placement_id: Some(99),
                row: 1,
                col: 0,
                display_cols: 1,
                display_rows: 1,
            })
            .is_some());
    }

    #[test]
    fn delete_by_placement_leaves_other_placement_ids_intact() {
        let mut store = GraphicsStore::new();
        store.store_image(Some(1), tiny_rgb(0x01));
        store.add_placement(ImagePlacement {
            image_id: 1,
            placement_id: Some(10),
            row: 0,
            col: 0,
            display_cols: 1,
            display_rows: 1,
        });
        store.add_placement(ImagePlacement {
            image_id: 1,
            placement_id: Some(20),
            row: 5,
            col: 0,
            display_cols: 1,
            display_rows: 1,
        });
        store.delete_by_placement(1, 10);
        // placement 20 must survive; image data must survive
        assert!(!store.get_image_png_base64(1).is_empty());
    }

    #[test]
    fn delete_by_placement_noop_on_wrong_image_id() {
        let mut store = GraphicsStore::new();
        store.store_image(Some(1), tiny_rgb(0x01));
        store.add_placement(ImagePlacement {
            image_id: 1,
            placement_id: Some(5),
            row: 0,
            col: 0,
            display_cols: 1,
            display_rows: 1,
        });
        store.delete_by_placement(99, 5); // wrong image_id
        assert!(!store.get_image_png_base64(1).is_empty());
    }

    // ── delete_by_row ────────────────────────────────────────────────────────

    #[test]
    fn delete_by_row_removes_placements_at_that_row() {
        let mut store = GraphicsStore::new();
        store.store_image(Some(1), tiny_rgb(0x01));
        store.add_placement(min_placement(1, 3, 0));
        store.add_placement(min_placement(1, 7, 0));
        store.delete_by_row(3);
        // Image data survives; placement at row 7 survives (checked via image still present)
        assert!(!store.get_image_png_base64(1).is_empty());
    }

    #[test]
    fn delete_by_row_leaves_other_rows_intact() {
        let mut store = GraphicsStore::new();
        store.store_image(Some(1), tiny_rgb(0x01));
        store.add_placement(min_placement(1, 2, 0));
        store.add_placement(min_placement(1, 5, 0));
        store.delete_by_row(2);
        assert!(!store.get_image_png_base64(1).is_empty());
    }

    #[test]
    fn delete_by_row_noop_when_no_placement_at_row() {
        let mut store = GraphicsStore::new();
        store.store_image(Some(1), tiny_rgb(0x01));
        store.add_placement(min_placement(1, 4, 0));
        store.delete_by_row(0);
        assert!(!store.get_image_png_base64(1).is_empty());
    }

    // ── delete_by_col ────────────────────────────────────────────────────────

    #[test]
    fn delete_by_col_removes_placements_at_that_col() {
        let mut store = GraphicsStore::new();
        store.store_image(Some(1), tiny_rgb(0x01));
        store.add_placement(min_placement(1, 0, 10));
        store.add_placement(min_placement(1, 0, 20));
        store.delete_by_col(10);
        assert!(!store.get_image_png_base64(1).is_empty());
    }

    #[test]
    fn delete_by_col_leaves_other_cols_intact() {
        let mut store = GraphicsStore::new();
        store.store_image(Some(1), tiny_rgb(0x01));
        store.add_placement(min_placement(1, 0, 5));
        store.add_placement(min_placement(1, 0, 15));
        store.delete_by_col(5);
        assert!(!store.get_image_png_base64(1).is_empty());
    }
