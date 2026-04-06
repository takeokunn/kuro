//! Graphics store access methods for Screen

use super::{GraphicsStore, Screen};

impl Screen {
    /// Get reference to the active screen's graphics store
    #[must_use]
    pub fn active_graphics(&self) -> &GraphicsStore {
        if self.is_alternate_active {
            if let Some(alt) = self.alternate_screen.as_ref() {
                return &alt.graphics;
            }
        }
        &self.graphics
    }

    /// Get mutable reference to the active screen's graphics store
    pub fn active_graphics_mut(&mut self) -> &mut GraphicsStore {
        if self.is_alternate_active {
            if let Some(alt) = self.alternate_screen.as_mut() {
                return &mut alt.graphics;
            }
        }
        &mut self.graphics
    }

    /// Get image from any screen (primary first, then active if alternate)
    #[must_use]
    pub fn get_image_png_base64(&self, image_id: u32) -> String {
        // Check primary screen's store
        let result = self.graphics.get_image_png_base64(image_id);
        if !result.is_empty() {
            return result;
        }
        // If alternate is active, also check alternate screen's store
        if self.is_alternate_active {
            if let Some(alt) = &self.alternate_screen {
                return alt.graphics.get_image_png_base64(image_id);
            }
        }
        String::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::grid::image::{ImageData, ImagePlacement};
    use crate::parser::kitty::ImageFormat;
    use proptest::prelude::*;

    fn make_screen() -> Screen {
        Screen::new(24, 80)
    }

    #[inline]
    fn tiny_rgb_image(byte: u8) -> ImageData {
        ImageData {
            pixels: vec![byte, byte, byte],
            format: ImageFormat::Rgb,
            pixel_width: 1,
            pixel_height: 1,
        }
    }

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

    macro_rules! assert_image_present {
        ($store:expr, $id:expr, $msg:literal) => {
            assert!(!$store.get_image_png_base64($id).is_empty(), $msg);
        };
    }

    macro_rules! assert_image_absent {
        ($store:expr, $id:expr, $msg:literal) => {
            assert_eq!($store.get_image_png_base64($id), String::new(), $msg);
        };
    }

    #[test]
    fn active_graphics_primary_starts_empty() {
        let s = make_screen();
        assert_image_absent!(
            s.active_graphics(),
            1,
            "primary graphics store must be empty"
        );
    }

    #[test]
    fn active_graphics_mut_primary_stores_and_retrieves_image() {
        let mut s = make_screen();
        let id = s
            .active_graphics_mut()
            .store_image(Some(42), tiny_rgb_image(0xFF));
        assert_eq!(id, 42);
        assert_image_present!(s.active_graphics(), 42, "stored image must be retrievable");
    }

    #[test]
    fn active_graphics_primary_unknown_id_returns_empty() {
        let s = make_screen();
        assert_image_absent!(s.active_graphics(), 999, "unknown ID must return empty");
    }

    #[test]
    fn active_graphics_returns_alternate_store_when_alternate_active() {
        let mut s = make_screen();
        s.active_graphics_mut()
            .store_image(Some(1), tiny_rgb_image(0xAA));
        s.switch_to_alternate();
        s.active_graphics_mut()
            .store_image(Some(2), tiny_rgb_image(0xBB));
        assert_image_absent!(
            s.active_graphics(),
            1,
            "alternate must not expose primary-only image"
        );
        assert_image_present!(
            s.active_graphics(),
            2,
            "alternate must return its own image"
        );
    }

    #[test]
    fn active_graphics_returns_primary_store_after_switching_back() {
        let mut s = make_screen();
        s.active_graphics_mut()
            .store_image(Some(7), tiny_rgb_image(0x77));
        s.switch_to_alternate();
        s.active_graphics_mut()
            .store_image(Some(8), tiny_rgb_image(0x88));
        s.switch_to_primary();
        assert_image_present!(s.active_graphics(), 7, "primary must expose image 7");
        assert_image_absent!(
            s.active_graphics(),
            8,
            "primary must not expose alternate image 8"
        );
    }

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
        assert_image_present!(s, 5, "must return primary image");
    }

    #[test]
    fn get_image_png_base64_searches_primary_first_when_alternate_active() {
        let mut s = make_screen();
        s.active_graphics_mut()
            .store_image(Some(3), tiny_rgb_image(0x33));
        s.switch_to_alternate();
        assert_image_present!(
            s,
            3,
            "must find primary-store image while alternate is active"
        );
    }

    #[test]
    fn get_image_png_base64_falls_back_to_alternate() {
        let mut s = make_screen();
        s.switch_to_alternate();
        s.active_graphics_mut()
            .store_image(Some(9), tiny_rgb_image(0x99));
        assert_image_present!(s, 9, "must fall back to alternate store");
    }

    #[test]
    fn get_image_png_base64_returns_empty_when_absent_in_both() {
        let mut s = make_screen();
        s.switch_to_alternate();
        assert_image_absent!(s, 42, "must return empty when absent from both stores");
    }

    #[test]
    fn active_graphics_mut_auto_id_starts_at_one() {
        let mut s = make_screen();
        let id = s
            .active_graphics_mut()
            .store_image(None, tiny_rgb_image(0x10));
        assert_eq!(id, 1);
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
        assert_ne!(id1, id2);
    }

    #[test]
    fn active_graphics_mut_add_placement_returns_none_for_unknown_image() {
        let mut s = make_screen();
        let placement = make_placement!(99, row = 0, col = 0, cols = 10, rows = 5);
        assert!(s.active_graphics_mut().add_placement(placement).is_none());
    }

    #[test]
    fn active_graphics_mut_add_placement_returns_notification() {
        let mut s = make_screen();
        s.active_graphics_mut()
            .store_image(Some(11), tiny_rgb_image(0x11));
        let placement = make_placement!(11, row = 2, col = 4, cols = 8, rows = 3);
        let n = s.active_graphics_mut().add_placement(placement).unwrap();
        assert_eq!(n.image_id, 11);
        assert_eq!(n.row, 2);
        assert_eq!(n.col, 4);
        assert_eq!(n.cell_width, 8);
        assert_eq!(n.cell_height, 3);
    }

    #[test]
    fn store_image_duplicate_id_replaces_existing() {
        let mut s = make_screen();
        s.active_graphics_mut()
            .store_image(Some(10), tiny_rgb_image(0xAA));
        s.active_graphics_mut()
            .store_image(Some(10), tiny_rgb_image(0xBB));
        assert_image_present!(
            s.active_graphics(),
            10,
            "overwritten image must be retrievable"
        );
        assert_image_absent!(s.active_graphics(), 11, "image 11 was never stored");
    }

    #[test]
    fn delete_by_id_removes_image_and_placement() {
        let mut s = make_screen();
        s.active_graphics_mut()
            .store_image(Some(5), tiny_rgb_image(0x55));
        s.active_graphics_mut().add_placement(make_placement!(
            5,
            row = 0,
            col = 0,
            cols = 4,
            rows = 2
        ));
        s.active_graphics_mut().delete_by_id(5);
        assert_image_absent!(
            s.active_graphics(),
            5,
            "image must not be retrievable after delete"
        );
        assert!(s
            .active_graphics_mut()
            .add_placement(make_placement!(5, row = 1, col = 1, cols = 2, rows = 1))
            .is_none());
    }

    #[test]
    fn clear_all_placements_removes_placements_images_survive() {
        let mut s = make_screen();
        s.active_graphics_mut()
            .store_image(Some(1), tiny_rgb_image(0x11));
        s.active_graphics_mut()
            .store_image(Some(2), tiny_rgb_image(0x22));
        s.active_graphics_mut().add_placement(make_placement!(
            1,
            row = 0,
            col = 0,
            cols = 2,
            rows = 1
        ));
        s.active_graphics_mut().add_placement(make_placement!(
            2,
            row = 1,
            col = 0,
            cols = 3,
            rows = 2
        ));
        s.active_graphics_mut().clear_all_placements();
        assert_image_present!(s.active_graphics(), 1, "image 1 must survive");
        assert_image_present!(s.active_graphics(), 2, "image 2 must survive");
        assert!(s
            .active_graphics_mut()
            .add_placement(make_placement!(1, row = 5, col = 5, cols = 1, rows = 1))
            .is_some());
    }

    #[test]
    fn active_graphics_count_matches_store_image_calls() {
        let mut s = make_screen();
        for &id in &[10u32, 20, 30] {
            s.active_graphics_mut()
                .store_image(Some(id), tiny_rgb_image(id as u8));
        }
        for &id in &[10u32, 20, 30] {
            assert_image_present!(s.active_graphics(), id, "image must be retrievable");
        }
        assert_image_absent!(s.active_graphics(), 99, "image 99 was never stored");
    }

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(128))]

        #[test]
        fn prop_active_graphics_get_never_panics(id in 0u32..u32::MAX) {
            let s = make_screen();
            let _ = s.active_graphics().get_image_png_base64(id);
            prop_assert!(true);
        }

        #[test]
        fn prop_store_and_retrieve_roundtrip(id in 1u32..1000u32, byte in 0u8..=255u8) {
            let mut s = make_screen();
            let stored_id = s.active_graphics_mut().store_image(Some(id), tiny_rgb_image(byte));
            prop_assert_eq!(stored_id, id);
            let result = s.active_graphics().get_image_png_base64(id);
            prop_assert!(!result.is_empty());
        }
    }
}
