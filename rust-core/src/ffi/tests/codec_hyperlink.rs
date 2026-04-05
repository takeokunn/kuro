// -------------------------------------------------------------------------
// encode_hyperlink_ranges
// -------------------------------------------------------------------------

#[test]
fn hyperlink_ranges_empty_cells() {
    let ranges = encode_hyperlink_ranges(&[]);
    assert!(ranges.is_empty(), "empty cells must produce no ranges");
}

#[test]
fn hyperlink_ranges_no_hyperlinks() {
    let cells: Vec<Cell> = (0..5).map(|_| Cell::new('a')).collect();
    let ranges = encode_hyperlink_ranges(&cells);
    assert!(
        ranges.is_empty(),
        "cells without hyperlinks must produce no ranges"
    );
}

#[test]
fn hyperlink_ranges_single_contiguous_run() {
    let uri = "https://example.com";
    let cells: Vec<Cell> = (0..5)
        .map(|_| Cell::new('a').with_hyperlink(Arc::from(uri)))
        .collect();
    let ranges = encode_hyperlink_ranges(&cells);
    assert_eq!(
        ranges.len(),
        1,
        "single contiguous run must produce 1 range"
    );
    assert_eq!(ranges[0], (0, 5, uri.to_owned()));
}

#[test]
fn hyperlink_ranges_two_different_uris() {
    let uri_a = "https://a.example.com";
    let uri_b = "https://b.example.com";
    let mut cells = Vec::new();
    for _ in 0..3 {
        cells.push(Cell::new('a').with_hyperlink(Arc::from(uri_a)));
    }
    for _ in 0..2 {
        cells.push(Cell::new('b').with_hyperlink(Arc::from(uri_b)));
    }
    let ranges = encode_hyperlink_ranges(&cells);
    assert_eq!(ranges.len(), 2, "two different URIs must produce 2 ranges");
    assert_eq!(ranges[0], (0, 3, uri_a.to_owned()));
    assert_eq!(ranges[1], (3, 5, uri_b.to_owned()));
}

#[test]
fn hyperlink_ranges_mixed_with_plain_cells() {
    let uri = "https://example.com";
    let mut cells = Vec::new();
    // 2 plain cells
    cells.push(Cell::new('p'));
    cells.push(Cell::new('p'));
    // 3 linked cells
    for _ in 0..3 {
        cells.push(Cell::new('l').with_hyperlink(Arc::from(uri)));
    }
    // 2 plain cells
    cells.push(Cell::new('p'));
    cells.push(Cell::new('p'));

    let ranges = encode_hyperlink_ranges(&cells);
    assert_eq!(ranges.len(), 1, "only linked cells must produce a range");
    assert_eq!(ranges[0], (2, 5, uri.to_owned()));
}

#[test]
fn hyperlink_ranges_wide_char_skipped() {
    let uri = "https://example.com";
    let mut cells = Vec::new();
    // Wide char (CJK): Full cell + Wide placeholder
    let mut full_cell = Cell::with_char_and_width(
        '\u{4E2D}', // '中'
        SgrAttributes::default(),
        CellWidth::Full,
    );
    full_cell.set_hyperlink_id(Some(Arc::from(uri)));
    cells.push(full_cell);
    let placeholder = Cell {
        width: CellWidth::Wide,
        ..Cell::default()
    };
    cells.push(placeholder);
    // Normal cell with hyperlink
    cells.push(Cell::new('a').with_hyperlink(Arc::from(uri)));

    let ranges = encode_hyperlink_ranges(&cells);
    assert_eq!(
        ranges.len(),
        1,
        "wide placeholder must be skipped; contiguous URI run preserved"
    );
    // '中' is 1 char, 'a' is 1 char; Wide placeholder skipped → offsets 0..2
    assert_eq!(ranges[0], (0, 2, uri.to_owned()));
}

#[test]
fn hyperlink_ranges_link_then_gap_then_link() {
    let uri = "https://example.com";
    let cells = vec![
        Cell::new('a').with_hyperlink(Arc::from(uri)),
        Cell::new(' '), // gap
        Cell::new('b').with_hyperlink(Arc::from(uri)),
    ];

    let ranges = encode_hyperlink_ranges(&cells);
    assert_eq!(
        ranges.len(),
        2,
        "same URI with gap must produce 2 separate ranges"
    );
    assert_eq!(ranges[0], (0, 1, uri.to_owned()));
    assert_eq!(ranges[1], (2, 3, uri.to_owned()));
}
