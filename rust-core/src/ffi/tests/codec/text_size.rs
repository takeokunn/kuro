use super::*;
use crate::types::cell::TextSize;

// -------------------------------------------------------------------------
// encode_text_size_ranges
// -------------------------------------------------------------------------

fn sized(c: char, scale: u8) -> Cell {
    Cell::new(c).with_text_size(TextSize {
        scale,
        ..TextSize::default()
    })
}

#[test]
fn text_size_ranges_empty_cells() {
    let ranges = encode_text_size_ranges(&[]);
    assert!(ranges.is_empty(), "empty cells must produce no ranges");
}

#[test]
fn text_size_ranges_no_sizes() {
    let cells: Vec<Cell> = (0..5).map(|_| Cell::new('a')).collect();
    let ranges = encode_text_size_ranges(&cells);
    assert!(
        ranges.is_empty(),
        "cells without text sizes must produce no ranges"
    );
}

#[test]
fn text_size_ranges_single_contiguous_run() {
    let cells: Vec<Cell> = (0..5).map(|_| sized('a', 2)).collect();
    let ranges = encode_text_size_ranges(&cells);
    assert_eq!(ranges.len(), 1, "single contiguous run → 1 range");
    assert_eq!(ranges[0], (0, 5, 2000), "scale 2 over 5 cells → (0,5,2000)");
}

#[test]
fn text_size_ranges_grouping_contiguous_equal_sizes() {
    // 2× 2× 3× 3× normal 2× → groups: [0,2)=2000, [2,4)=3000, [5,6)=2000
    let cells = vec![
        sized('a', 2),
        sized('b', 2),
        sized('c', 3),
        sized('d', 3),
        Cell::new('e'),
        sized('f', 2),
    ];
    let ranges = encode_text_size_ranges(&cells);
    assert_eq!(
        ranges,
        vec![(0, 2, 2000), (2, 4, 3000), (5, 6, 2000)],
        "contiguous equal sizes must group; the normal cell breaks the run"
    );
}

#[test]
fn text_size_ranges_skips_wide_placeholder() {
    // A wide (Full) sized cell followed by its Wide placeholder. The placeholder
    // must be skipped — the range spans the single buffer offset.
    let wide = Cell::with_char_and_width('漢', SgrAttributes::default(), CellWidth::Full)
        .with_text_size(TextSize {
            scale: 2,
            ..TextSize::default()
        });
    let mut placeholder = Cell::with_char_and_width(' ', SgrAttributes::default(), CellWidth::Wide);
    placeholder.set_text_size(Some(TextSize {
        scale: 2,
        ..TextSize::default()
    }));
    let cells = vec![wide, placeholder, sized('x', 2)];
    let ranges = encode_text_size_ranges(&cells);
    // buf offsets: wide char = offset 0, placeholder skipped, 'x' = offset 1.
    assert_eq!(
        ranges,
        vec![(0, 2, 2000)],
        "wide placeholder must be skipped; contiguous run spans buf offsets 0..2"
    );
}

#[test]
fn text_size_ranges_fractional_permille() {
    let cell = Cell::new('h').with_text_size(TextSize {
        numerator: 1,
        denominator: 2,
        width: 1,
        ..TextSize::default()
    });
    let ranges = encode_text_size_ranges(std::slice::from_ref(&cell));
    assert_eq!(ranges, vec![(0, 1, 500)], "1/2 size → 500 permille");
}
