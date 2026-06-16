use crate::grid::image::ImageData;
use crate::grid::screen::Screen;
use crate::parser::kitty::ImageFormat;

pub(crate) fn make_screen() -> Screen {
    Screen::new(24, 80)
}

#[inline]
pub(crate) fn tiny_rgb_image(byte: u8) -> ImageData {
    ImageData {
        pixels: vec![byte, byte, byte],
        format: ImageFormat::Rgb,
        pixel_width: 1,
        pixel_height: 1,
    }
}

macro_rules! make_placement {
    ($id:expr, row=$r:expr, col=$c:expr, cols=$w:expr, rows=$h:expr) => {
        crate::grid::image::ImagePlacement {
            image_id: $id,
            placement_id: None,
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
