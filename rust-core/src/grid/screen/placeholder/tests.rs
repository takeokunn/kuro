//! Unit tests for the Unicode-placeholder region walk.
//!
//! Module under test: `grid/screen/placeholder.rs`
//! (`Screen::collect_placeholder_regions`).

use crate::grid::image::ImageData;
use crate::grid::placeholder::{PlaceholderRegion, PLACEHOLDER_CHAR, ROWCOLUMN_DIACRITICS};
use crate::grid::screen::Screen;
use crate::parser::kitty::ImageFormat;
use crate::types::cell::SgrAttributes;
use crate::types::color::Color;
use crate::types::Cell;

/// Encode an image id into a truecolor foreground (`(r<<16)|(g<<8)|b`), matching
/// the kitty placeholder convention.
fn fg_for_id(id: u32) -> Color {
    Color::Rgb(
        ((id >> 16) & 0xFF) as u8,
        ((id >> 8) & 0xFF) as u8,
        (id & 0xFF) as u8,
    )
}

/// Build a placeholder cell for image `id` at image-grid tile (`img_row`,
/// `img_col`). `placement` becomes the underline color when `Some`.
fn placeholder_cell(id: u32, img_row: usize, img_col: usize, placement: Option<u32>) -> Cell {
    let attrs = SgrAttributes {
        foreground: fg_for_id(id),
        underline_color: placement.map_or(Color::Default, fg_for_id),
        ..SgrAttributes::default()
    };
    let mut cell = Cell::with_attrs(PLACEHOLDER_CHAR, attrs);
    cell.push_combining(ROWCOLUMN_DIACRITICS[img_row]);
    cell.push_combining(ROWCOLUMN_DIACRITICS[img_col]);
    cell
}

/// 1x1 RGB image so the store reports the id as present (orphan filtering keys
/// off store membership, not pixel content).
fn store_tiny_image(screen: &mut Screen, id: u32) {
    let data = ImageData::new(vec![1, 2, 3], ImageFormat::Rgb, 1, 1);
    screen.active_graphics_mut().store_image(Some(id), data);
}

/// Place a cell on the screen at (`row`, `col`).
fn put(screen: &mut Screen, row: usize, col: usize, cell: Cell) {
    *screen.get_cell_mut(row, col).expect("cell in bounds") = cell;
}

/// INTENT: a 2x2 block of `U+10EEEE` cells for one stored image yields exactly
/// one region descriptor of size 2x2 cells covering a 2x2 image tile grid.
#[test]
fn two_by_two_grid_yields_one_region() {
    let mut screen = Screen::new(8, 16);
    store_tiny_image(&mut screen, 42);

    for r in 0..2 {
        for c in 0..2 {
            put(&mut screen, r, c, placeholder_cell(42, r, c, None));
        }
    }

    let regions = screen.collect_placeholder_regions();
    assert_eq!(
        regions.len(),
        1,
        "contiguous 2x2 must collapse to one region"
    );
    assert_eq!(
        regions[0],
        PlaceholderRegion {
            image_id: 42,
            placement_id: 0,
            screen_row: 0,
            screen_col: 0,
            cell_cols: 2,
            cell_rows: 2,
            img_row: 0,
            img_col: 0,
            img_rows: 2,
            img_cols: 2,
        }
    );
}

/// INTENT: two placeholder cells separated by a gap on the same row are
/// non-contiguous and split into two distinct single-cell regions.
#[test]
fn non_contiguous_placeholders_split() {
    let mut screen = Screen::new(8, 16);
    store_tiny_image(&mut screen, 7);

    put(&mut screen, 0, 0, placeholder_cell(7, 0, 0, None));
    // gap at col 1 (default space cell)
    put(&mut screen, 0, 2, placeholder_cell(7, 0, 1, None));

    let regions = screen.collect_placeholder_regions();
    assert_eq!(regions.len(), 2, "gap must split into two regions");
    assert_eq!(regions[0].screen_col, 0);
    assert_eq!(regions[0].cell_cols, 1);
    assert_eq!(regions[1].screen_col, 2);
    assert_eq!(regions[1].cell_cols, 1);
}

/// INTENT: a placeholder referencing an image that is NOT in the store (orphan)
/// is excluded entirely — no region is produced.
#[test]
fn orphan_placeholder_excluded() {
    let mut screen = Screen::new(8, 16);
    // Note: image id 99 is never stored.
    put(&mut screen, 0, 0, placeholder_cell(99, 0, 0, None));

    let regions = screen.collect_placeholder_regions();
    assert!(
        regions.is_empty(),
        "orphan placeholder (no stored image) must yield no regions, got {regions:?}"
    );
}

/// INTENT: the empty grid (no placeholders at all) returns an empty vec cheaply.
#[test]
fn no_placeholders_yields_empty() {
    let screen = Screen::new(8, 16);
    assert!(screen.collect_placeholder_regions().is_empty());
}

/// INTENT: two adjacent placeholder cells referencing DIFFERENT images split
/// into separate regions even though they are physically contiguous.
#[test]
fn different_images_adjacent_split() {
    let mut screen = Screen::new(8, 16);
    store_tiny_image(&mut screen, 1);
    store_tiny_image(&mut screen, 2);

    put(&mut screen, 0, 0, placeholder_cell(1, 0, 0, None));
    put(&mut screen, 0, 1, placeholder_cell(2, 0, 0, None));

    let regions = screen.collect_placeholder_regions();
    assert_eq!(regions.len(), 2);
    assert_eq!(regions[0].image_id, 1);
    assert_eq!(regions[1].image_id, 2);
}

/// INTENT: placement id from the underline color is preserved in the descriptor
/// and distinguishes regions sharing the same image id.
#[test]
fn placement_id_preserved() {
    let mut screen = Screen::new(8, 16);
    store_tiny_image(&mut screen, 5);

    put(&mut screen, 0, 0, placeholder_cell(5, 0, 0, Some(3)));

    let regions = screen.collect_placeholder_regions();
    assert_eq!(regions.len(), 1);
    assert_eq!(regions[0].placement_id, 3);
}

/// INTENT: a vertical strip (same single column, two rows) merges into one 1x2
/// region with the correct image-grid extent.
#[test]
fn vertical_strip_merges() {
    let mut screen = Screen::new(8, 16);
    store_tiny_image(&mut screen, 8);

    put(&mut screen, 0, 0, placeholder_cell(8, 0, 0, None));
    put(&mut screen, 1, 0, placeholder_cell(8, 1, 0, None));

    let regions = screen.collect_placeholder_regions();
    assert_eq!(regions.len(), 1);
    assert_eq!(regions[0].cell_cols, 1);
    assert_eq!(regions[0].cell_rows, 2);
    assert_eq!(regions[0].img_rows, 2);
    assert_eq!(regions[0].img_cols, 1);
}

/// INTENT (adversarial): a contiguous same-image run whose 2nd cell encodes a
/// SMALLER img_col than the 1st (e.g. img_col 5 then img_col 2) must not panic
/// via u32 underflow in `img_cols` accumulation. The descriptor must still be
/// produced with a sane (non-wrapped) img_cols span.
#[test]
fn descending_img_col_in_run_no_underflow() {
    let mut screen = Screen::new(8, 16);
    store_tiny_image(&mut screen, 11);
    // col 0: img_col 5 ; col 1: img_col 2 (descending) — same image/placement.
    put(&mut screen, 0, 0, placeholder_cell(11, 0, 5, None));
    put(&mut screen, 0, 1, placeholder_cell(11, 0, 2, None));

    let regions = screen.collect_placeholder_regions();
    assert_eq!(
        regions.len(),
        1,
        "contiguous same-image run stays one region"
    );
    let r = regions[0];
    assert_eq!(r.cell_cols, 2);
    // img_cols must be a small sane number, never a wrapped ~4 billion value.
    assert!(
        r.img_cols < 1000,
        "img_cols sane, not underflow-wrapped: {}",
        r.img_cols
    );
}
