use crate::grid::screen::{GraphicsStore, ImageData, ImagePlacement};
use crate::parser::kitty::ImageFormat;

const DEFAULT_DISPLAY_COLS: u32 = 10;
const DEFAULT_DISPLAY_ROWS: u32 = 5;

pub(crate) fn tiny_rgb(byte: u8) -> ImageData {
    ImageData {
        pixels: vec![byte, byte, byte],
        format: ImageFormat::Rgb,
        pixel_width: 1,
        pixel_height: 1,
    }
}

pub(crate) fn tiny_rgba(byte: u8) -> ImageData {
    ImageData {
        pixels: vec![byte, byte, byte, 0xFF],
        format: ImageFormat::Rgba,
        pixel_width: 1,
        pixel_height: 1,
    }
}

pub(crate) fn empty_rgb() -> ImageData {
    ImageData {
        pixels: Vec::new(),
        format: ImageFormat::Rgb,
        pixel_width: 0,
        pixel_height: 0,
    }
}

pub(crate) fn placement(image_id: u32, row: usize, col: usize) -> ImagePlacement {
    ImagePlacement {
        image_id,
        placement_id: None,
        row,
        col,
        display_cols: DEFAULT_DISPLAY_COLS,
        display_rows: DEFAULT_DISPLAY_ROWS,
    }
}

pub(crate) fn placement_with_id(
    image_id: u32,
    placement_id: u32,
    row: usize,
    col: usize,
) -> ImagePlacement {
    ImagePlacement {
        image_id,
        placement_id: Some(placement_id),
        row,
        col,
        display_cols: 1,
        display_rows: 1,
    }
}

pub(crate) fn store_with_image(image_id: u32) -> GraphicsStore {
    let mut store = GraphicsStore::new();
    store.store_image(Some(image_id), tiny_rgb(image_id as u8));
    store
}

pub(crate) fn store_with_images(ids: &[u32]) -> GraphicsStore {
    let mut store = GraphicsStore::new();
    for &id in ids {
        store.store_image(Some(id), tiny_rgb(id as u8));
    }
    store
}

pub(crate) fn assert_image_present(store: &GraphicsStore, image_id: u32) {
    assert!(!store.get_image_png_base64(image_id).is_empty());
}

pub(crate) fn assert_image_missing(store: &GraphicsStore, image_id: u32) {
    assert_eq!(store.get_image_png_base64(image_id), String::new());
}

pub(crate) fn assert_placement_rows(store: &GraphicsStore, rows: &[usize]) {
    let actual: Vec<usize> = store
        .placements
        .iter()
        .map(|placement| placement.row)
        .collect();
    assert_eq!(actual, rows);
}

macro_rules! assert_image_survives {
    ($name:ident, $setup:expr, $op:expr) => {
        #[test]
        fn $name() {
            let mut store = store_with_image(1);
            let setup_fn: &dyn Fn(&mut GraphicsStore) = &$setup;
            setup_fn(&mut store);
            let op_fn: &dyn Fn(&mut GraphicsStore) = &$op;
            op_fn(&mut store);
            assert_image_present(&store, 1);
        }
    };
}

macro_rules! assert_to_png_base64_non_empty {
    ($name:ident, $img:expr) => {
        #[test]
        fn $name() {
            let data = $img;
            assert!(!data.to_png_base64().is_empty());
        }
    };
}
